import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Main entry point for the SLNK iOS SDK.
///
/// Usage:
/// ```swift
/// // 1. Configure in App.init() or AppDelegate:
/// Slnka.configure(apiKey: "lsk_live_your_key_here", config: SlnkaConfig(serverUrl: "https://api.slnk.ma"))
///
/// // 2. Register ONE callback for ALL deep links (direct + deferred):
/// Slnka.onDeepLink { deepLink in
///     // deepLink.screen = "/payment"
///     // deepLink.isDeferred = true/false
///     // deepLink.params = [...]
///     navigateTo(deepLink.screen)
/// }
///
/// // 3. In SwiftUI .onOpenURL:
/// Slnka.handleURL(url)
///
/// // 4. In .onContinueUserActivity:
/// Slnka.handleUserActivity(userActivity)
///
/// // Track events:
/// Slnka.shared.track(event: "purchase_completed", properties: ["amount": 99.99])
///
/// // Identify user:
/// Slnka.shared.identify(userId: "user_123", traits: ["name": "Ahmed", "plan": "pro"])
///
/// // On logout:
/// Slnka.shared.reset()
/// ```
public final class Slnka {

    /// Shared singleton instance.
    public static let shared = Slnka()

    // MARK: - Internal Components

    private var apiKeyValue: String?
    private var config: SlnkaConfig?
    private var transport: Transport?
    private var storage: SlnkaStorage?
    private var eventQueue: EventQueue?
    private var eventTracker: EventTracker?
    private var deepLinkHandler: DeepLinkHandler?
    private var deferredResolver: DeferredDeepLinkResolver?
    private var attribution: Attribution?
    private var fingerprint: DeviceFingerprint?
    private var feedbackManager: FeedbackManager?

    private var isConfigured = false

    /// Stored callback for the unified `onDeepLink` API.
    private var deepLinkCallback: ((DeepLink) -> Void)?

    /// Whether auto deferred check has already been triggered.
    private var deferredCheckTriggered = false

    private init() {}

    // MARK: - Configuration

    /// Configures the SDK. Must be called before any other SDK method.
    ///
    /// Best practice: call in `AppDelegate.application(_:didFinishLaunchingWithOptions:)`
    /// or in the `init()` of your SwiftUI `App` struct.
    ///
    /// - Parameters:
    ///   - apiKey: Your SLNK API key (format: `lsk_live_*` or `lsk_test_*`).
    ///   - config: Optional SDK configuration.
    public static func configure(apiKey: String, config: SlnkaConfig) {
        guard validateApiKey(apiKey) else {
            print("[SlnkaSDK] Invalid API key format. Expected lsk_live_* or lsk_test_*.")
            return
        }

        let sdk = shared
        sdk.apiKeyValue = apiKey
        sdk.config = config
        sdk.storage = SlnkaStorage()
        sdk.transport = Transport(apiKey: apiKey, baseURL: config.serverUrl, debug: config.debug)
        sdk.fingerprint = DeviceFingerprint.collect()
        sdk.eventQueue = EventQueue(transport: sdk.transport!, config: config, storage: sdk.storage!)
        sdk.eventTracker = EventTracker(
            storage: sdk.storage!,
            eventQueue: sdk.eventQueue!,
            fingerprint: sdk.fingerprint!,
            config: config
        )

        if config.enableDeepLinks {
            sdk.deepLinkHandler = DeepLinkHandler(transport: sdk.transport!, config: config)
            sdk.deferredResolver = DeferredDeepLinkResolver(
                transport: sdk.transport!,
                storage: sdk.storage!,
                fingerprint: sdk.fingerprint!,
                config: config
            )
        }

        sdk.feedbackManager = FeedbackManager(
            transport: sdk.transport!,
            storage: sdk.storage!,
            debug: config.debug
        )

        if config.enableAttribution {
            sdk.attribution = Attribution(
                transport: sdk.transport!,
                storage: sdk.storage!,
                fingerprint: sdk.fingerprint!,
                config: config
            )
        }

        sdk.isConfigured = true
        sdk.logDebug("SDK configured (server: \(config.serverUrl), debug: \(config.debug))")

        // Wire engagement-time tracker. The closure forwards to the SDK's
        // public track(event:properties:) so it reuses the configured
        // EventTracker and benefits from consent gating downstream. `shared`
        // is a long-lived singleton, so a strong capture is fine.
        EngagementTracker.shared.configure { eventName, properties in
            Slnka.shared.track(event: eventName, properties: properties)
        }

        // Register for app lifecycle notifications
        sdk.registerLifecycleObservers()

        // Auto-check deferred deep link if callback is already registered
        sdk.autoDeferredCheckIfReady()
    }

    // MARK: - Unified Deep Link API

    /// Registers a single callback that fires for ALL deep link types:
    /// direct Universal Links, custom URL schemes, and deferred deep links.
    ///
    /// The callback is always invoked on the **main thread**.
    ///
    /// - Parameter callback: Called with the resolved `DeepLink` whenever
    ///   a deep link is detected (direct or deferred).
    ///
    /// ```swift
    /// Slnka.onDeepLink { deepLink in
    ///     print("Screen: \(deepLink.screen ?? "none")")
    ///     print("Deferred: \(deepLink.isDeferred)")
    ///     navigateTo(deepLink.screen)
    /// }
    /// ```
    public static func onDeepLink(_ callback: @escaping (DeepLink) -> Void) {
        shared.deepLinkCallback = callback
        shared.logDebug("Deep link callback registered")

        // If SDK is already configured, trigger deferred check now
        shared.autoDeferredCheckIfReady()
    }

    /// Handles a URL from SwiftUI `.onOpenURL` or a custom URL scheme.
    ///
    /// This is the simplified entry point — it resolves the deep link
    /// and fires the callback registered via `onDeepLink(_:)`.
    ///
    /// - Parameter url: The URL to resolve.
    public static func handleURL(_ url: URL) {
        let sdk = shared
        guard sdk.isConfigured else {
            sdk.logDebug("SDK not configured, ignoring handleURL")
            return
        }

        guard let callback = sdk.deepLinkCallback else {
            sdk.logDebug("No deep link callback registered, ignoring handleURL")
            return
        }

        // For custom schemes (non-HTTPS), parse query params directly into a DeepLink
        if url.scheme != "https" && url.scheme != "http" {
            sdk.logDebug("Handling custom scheme URL: \(url.absoluteString)")
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var params: [String: Any] = [:]
            components?.queryItems?.forEach { item in
                params[item.name] = item.value ?? ""
            }
            // Read screen from query param first (consistent with Android SDK),
            // fallback to host (slnka://payment) then path
            let screen = (params.removeValue(forKey: "screen") as? String)
                ?? url.host
                ?? url.path
            let deepLink = DeepLink(
                screen: screen.isEmpty ? "/" : screen,
                params: params,
                isDeferred: false
            )
            DispatchQueue.main.async { callback(deepLink) }
            return
        }

        // For HTTPS URLs, use existing DeepLinkHandler to resolve via API
        sdk.deepLinkHandler?.handleURL(url) { [weak sdk] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let deepLink):
                    if #available(macOS 10.15, iOS 13.0, *) {
                        Task { _ = await sdk?.attribution?.recordDeepLinkAttribution(deepLink: deepLink) }
                    }
                    callback(deepLink)
                case .failure(let error):
                    sdk?.logDebug("handleURL failed: \(error.description)")
                }
            }
        }
    }

    /// Handles a Universal Link from `onContinueUserActivity` in SwiftUI or
    /// `application(_:continue:restorationHandler:)` in UIKit.
    ///
    /// This is the simplified entry point — it resolves the deep link
    /// and fires the callback registered via `onDeepLink(_:)`.
    ///
    /// - Parameter userActivity: The `NSUserActivity` from the system callback.
    public static func handleUserActivity(_ userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            shared.logDebug("handleUserActivity: not a web browsing activity, ignoring")
            return
        }
        handleURL(url)
    }

    // MARK: - Auto Deferred Check

    /// Triggers the deferred deep link check if both the SDK is configured
    /// and a callback is registered. Runs at most once.
    private func autoDeferredCheckIfReady() {
        guard isConfigured,
              let callback = deepLinkCallback,
              !deferredCheckTriggered,
              config?.enableDeepLinks == true else {
            return
        }

        deferredCheckTriggered = true
        logDebug("Auto-checking deferred deep link")

        deferredResolver?.checkDeferredDeepLink { [weak self] deepLink in
            DispatchQueue.main.async {
                guard let deepLink = deepLink else { return }
                if #available(macOS 10.15, iOS 13.0, *) {
                    Task { _ = await self?.attribution?.recordDeepLinkAttribution(deepLink: deepLink) }
                }
                callback(deepLink)
            }
        }
    }

    // MARK: - Deep Links (Legacy)

    /// Handles a Universal Link from `UISceneDelegate` or `UIApplicationDelegate`.
    ///
    /// - Parameters:
    ///   - userActivity: The `NSUserActivity` from the system callback.
    ///   - completion: Called on the main thread with the resolved `DeepLink` or an error.
    @available(*, deprecated, message: "Use Slnka.onDeepLink(_:) + Slnka.handleUserActivity(_:) instead")
    public func handleUniversalLink(
        _ userActivity: NSUserActivity,
        completion: @escaping (Result<DeepLink, SlnkaError>) -> Void
    ) {
        guard isConfigured else {
            completion(.failure(.notConfigured))
            return
        }

        deepLinkHandler?.handleUniversalLink(userActivity) { [weak self] result in
            DispatchQueue.main.async {
                // Record attribution for successful deep links
                if case .success(let deepLink) = result {
                    if #available(macOS 10.15, iOS 13.0, *) {
                        Task { _ = await self?.attribution?.recordDeepLinkAttribution(deepLink: deepLink) }
                    }
                }
                completion(result)
            }
        }
    }

    /// Async variant of `handleUniversalLink`.
    @available(iOS, introduced: 15.0, deprecated: 100000, message: "Use Slnka.onDeepLink(_:) + Slnka.handleUserActivity(_:) instead")
    public func handleUniversalLink(_ userActivity: NSUserActivity) async throws -> DeepLink {
        guard isConfigured else { throw SlnkaError.notConfigured }

        guard let handler = deepLinkHandler else {
            throw SlnkaError.sdkError("Deep links not enabled in configuration")
        }

        let deepLink = try await handler.handleUniversalLink(userActivity)

        // Record attribution
        _ = await attribution?.recordDeepLinkAttribution(deepLink: deepLink)

        return deepLink
    }

    /// Handles a URL directly (e.g., from a custom URL scheme or `openURL`).
    @available(*, deprecated, message: "Use Slnka.onDeepLink(_:) + Slnka.handleURL(_:) instead")
    public func handleURL(
        _ url: URL,
        completion: @escaping (Result<DeepLink, SlnkaError>) -> Void
    ) {
        guard isConfigured else {
            completion(.failure(.notConfigured))
            return
        }

        deepLinkHandler?.handleURL(url) { [weak self] result in
            DispatchQueue.main.async {
                if case .success(let deepLink) = result {
                    if #available(macOS 10.15, iOS 13.0, *) {
                        Task { _ = await self?.attribution?.recordDeepLinkAttribution(deepLink: deepLink) }
                    }
                }
                completion(result)
            }
        }
    }

    // MARK: - Deferred Deep Links (Legacy)

    /// Checks for a deferred deep link. Call at first app launch.
    ///
    /// This will only run once per install. Subsequent calls return `nil`.
    ///
    /// - Parameter completion: Called on the main thread with the resolved `DeepLink` or `nil`.
    @available(*, deprecated, message: "Use Slnka.onDeepLink(_:) instead — deferred deep links are checked automatically")
    public func checkDeferredDeepLink(completion: @escaping (DeepLink?) -> Void) {
        guard isConfigured else {
            logDebug("SDK not configured, skipping deferred deep link check")
            completion(nil)
            return
        }

        deferredResolver?.checkDeferredDeepLink { [weak self] deepLink in
            DispatchQueue.main.async {
                if let deepLink = deepLink {
                    if #available(macOS 10.15, iOS 13.0, *) {
                        Task { _ = await self?.attribution?.recordDeepLinkAttribution(deepLink: deepLink) }
                    }
                }
                completion(deepLink)
            }
        }
    }

    /// Async variant of `checkDeferredDeepLink`.
    @available(iOS, introduced: 15.0, deprecated: 100000, message: "Use Slnka.onDeepLink(_:) instead — deferred deep links are checked automatically")
    public func checkDeferredDeepLink() async -> DeepLink? {
        guard isConfigured else {
            logDebug("SDK not configured, skipping deferred deep link check")
            return nil
        }

        let deepLink = await deferredResolver?.checkDeferredDeepLink()

        if let deepLink = deepLink {
            _ = await attribution?.recordDeepLinkAttribution(deepLink: deepLink)
        }

        return deepLink
    }

    // MARK: - Event Tracking

    /// Tracks a custom event with optional properties.
    ///
    /// - Parameters:
    ///   - event: Event name (e.g., "button_clicked", "purchase_completed").
    ///     Use alphanumeric characters, dots, hyphens, and underscores.
    ///   - properties: Optional dictionary of event properties.
    public func track(event: String, properties: [String: Any] = [:]) {
        guard isConfigured else {
            logDebug("SDK not configured, dropping event: \(event)")
            return
        }
        eventTracker?.track(event: event, properties: properties)
    }

    /// Identifies the current user, linking the anonymous ID to a known user ID.
    ///
    /// - Parameters:
    ///   - userId: The known user identifier from your backend.
    ///   - traits: Optional user traits (e.g., name, email, plan).
    public func identify(userId: String, traits: [String: Any] = [:]) {
        guard isConfigured else {
            logDebug("SDK not configured, dropping identify")
            return
        }
        eventTracker?.identify(userId: userId, traits: traits)
    }

    /// Resets the user identity. Call this on logout.
    ///
    /// This clears the user ID, generates a new anonymous ID, and starts a new session.
    public func reset() {
        guard isConfigured else { return }
        eventTracker?.reset()
    }

    /// Creates an alias mapping a new user ID to a previous one.
    ///
    /// - Parameters:
    ///   - newId: The new user identifier.
    ///   - previousId: The previous identifier. Defaults to the current anonymous ID.
    public func alias(newId: String, previousId: String? = nil) {
        guard isConfigured else { return }
        eventTracker?.alias(newId: newId, previousId: previousId)
    }

    /// Starts a timer for a named event. When `track(event:)` is called with the
    /// same name, `duration_ms` is automatically injected into the properties.
    ///
    /// - Parameter name: The event name to time.
    public func timeEvent(name: String) {
        guard isConfigured else { return }
        eventTracker?.timeEvent(name: name)
    }

    // MARK: - Engagement Time Tracking

    /// Tracks the currently visible screen for engagement-time analytics.
    ///
    /// Call this once when a screen becomes visible, typically from
    /// `UIViewController.viewDidAppear(_:)` or a SwiftUI `.onAppear` handler.
    /// SLNK measures how long the user stays on the screen and emits a
    /// `screen_view_end` event with `duration_ms` when the user navigates
    /// away, backgrounds the app, or shuts the SDK down.
    ///
    /// Screens viewed for less than 500 ms are dropped (bounce filter).
    /// Durations are capped at 30 minutes.
    ///
    /// ```swift
    /// override func viewDidAppear(_ animated: Bool) {
    ///     super.viewDidAppear(animated)
    ///     Slnka.shared.trackScreen("/home")
    /// }
    /// ```
    ///
    /// - Parameter name: Stable name of the screen (e.g. `/product/42`).
    public func trackScreen(_ name: String) {
        guard isConfigured else {
            logDebug("SDK not configured, dropping trackScreen")
            return
        }
        EngagementTracker.shared.screenDidAppear(name)
    }

    // MARK: - Conversion Attribution

    /// Records a conversion event for multi-touch attribution.
    ///
    /// Sends the conversion to the backend so that credit can be distributed
    /// across the visitor's touchpoints according to the chosen model.
    ///
    /// - Parameters:
    ///   - event: The conversion event name (e.g., "purchase_completed").
    ///   - value: Optional monetary value of the conversion.
    ///   - goalId: Optional conversion goal ID.
    ///   - model: Attribution model to use. Default: `.lastTouch`.
    public static func recordConversion(
        event: String,
        value: Double? = nil,
        goalId: String? = nil,
        model: AttributionModel = .lastTouch
    ) {
        let sdk = shared
        guard sdk.isConfigured else {
            sdk.logDebug("SDK not configured, dropping conversion: \(event)")
            return
        }

        guard sdk.isConsentGranted() else {
            sdk.logDebug("Consent not granted, dropping conversion: \(event)")
            return
        }

        Task {
            await sdk.attribution?.recordConversion(
                event: event,
                value: value,
                goalId: goalId,
                model: model
            )

            // Also fire a regular track event for the event pipeline
            sdk.track(event: event, properties: [
                "conversionValue": value as Any,
                "goalId": goalId as Any,
                "attributionModel": model.rawValue,
            ].compactMapValues { $0 is NSNull ? nil : $0 })
        }
    }

    // MARK: - Feedback

    #if canImport(UIKit)
    /// Shows a single feedback prompt as a bottom sheet.
    ///
    /// The prompt is consent-gated and fatigue-limited (max 2 per calendar week).
    ///
    /// - Parameters:
    ///   - viewController: The presenting view controller.
    ///   - options: Configuration for the prompt (type, question, etc.).
    public func showFeedback(from viewController: UIViewController, options: FeedbackShowOptions) {
        guard isConfigured else {
            logDebug("SDK not configured, ignoring showFeedback")
            return
        }

        guard isConsentGranted() else {
            logDebug("Consent not granted, ignoring showFeedback")
            return
        }

        guard let manager = feedbackManager, manager.canShowPrompt() else {
            logDebug("Feedback fatigue limit reached, ignoring showFeedback")
            return
        }

        let feedbackVC = SlnkaFeedbackViewController(options: options) { [weak self] value in
            guard let self = self, let manager = self.feedbackManager else { return }
            manager.incrementFatigueCount()

            Task {
                await manager.submitResponse(
                    promptType: options.promptType.rawValue,
                    question: options.question,
                    value: value,
                    pageUrl: options.trigger,
                    metadata: options.metadata
                )
            }
        }

        viewController.present(feedbackVC, animated: true)
    }

    /// Shows a multi-step survey as a bottom sheet.
    ///
    /// The survey is consent-gated and fatigue-limited (max 2 per calendar week).
    /// Each step answer is submitted individually; the survey is marked complete
    /// after the final step.
    ///
    /// - Parameters:
    ///   - viewController: The presenting view controller.
    ///   - config: The survey configuration (id, title, steps).
    public func showSurvey(from viewController: UIViewController, config: SurveyConfig) {
        guard isConfigured else {
            logDebug("SDK not configured, ignoring showSurvey")
            return
        }

        guard isConsentGranted() else {
            logDebug("Consent not granted, ignoring showSurvey")
            return
        }

        guard let manager = feedbackManager, manager.canShowPrompt() else {
            logDebug("Feedback fatigue limit reached, ignoring showSurvey")
            return
        }

        manager.incrementFatigueCount()

        let surveyVC = SlnkaSurveyViewController(config: config)

        surveyVC.onSurveyStart = { [weak self] surveyId in
            return await self?.feedbackManager?.startSurveyResponse(surveyId: surveyId)
        }

        surveyVC.onStepAnswer = { [weak self] responseId, stepId, promptType, value in
            guard let manager = self?.feedbackManager else { return }
            let step = config.steps.first { $0.id == stepId }
            Task {
                await manager.submitSurveyStepAnswer(
                    responseId: responseId,
                    promptConfigId: stepId,
                    promptType: promptType,
                    question: step?.question ?? "",
                    value: value
                )
            }
        }

        surveyVC.onSurveyComplete = { [weak self] responseId in
            guard let manager = self?.feedbackManager else { return }
            Task {
                await manager.completeSurveyResponse(responseId: responseId)
            }
        }

        viewController.present(surveyVC, animated: true)
    }
    #endif

    // MARK: - Identity

    /// Returns the current anonymous ID.
    public func getAnonymousId() -> String {
        guard isConfigured, let tracker = eventTracker else {
            return "not_configured"
        }
        return tracker.getAnonymousId()
    }

    /// Returns the current user ID, or `nil` if not identified.
    public func getUserId() -> String? {
        guard isConfigured else { return nil }
        return eventTracker?.getUserId()
    }

    // MARK: - Flush

    /// Manually flushes all pending events to the server.
    public func flush() {
        guard isConfigured else { return }
        eventQueue?.flush()
    }

    /// Async variant of flush that waits for completion.
    @available(iOS 15.0, *)
    public func flushAsync() async {
        guard isConfigured else { return }
        await eventQueue?.flushAsync()
    }

    // MARK: - Workspace

    /// Sets the workspace ID for event context.
    public func setWorkspaceId(_ workspaceId: String) {
        eventQueue?.setWorkspaceId(workspaceId)
    }

    // MARK: - Consent (CNDP Law 09-08)

    /// Sets granular consent categories and syncs them to the SLNK server.
    ///
    /// This is the preferred method for managing consent. It sends per-category
    /// consent data to `POST /api/v1/sdk/consent` via Transport and updates the
    /// local analytics opt-out flag based on `categories.analytics`.
    ///
    /// - Parameter categories: The granular consent categories.
    public func setConsentData(_ categories: ConsentCategories) {
        guard isConfigured else { return }

        // Update local opt-out flag based on analytics consent
        storage?.setConsentGranted(categories.analytics)
        logDebug("Consent updated: analytics=\(categories.analytics), ads=\(categories.adsPersonalization), thirdParty=\(categories.thirdPartySharing)")

        // Build the request
        let anonymousId = storage?.getOrCreateAnonymousId() ?? "unknown"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let request = ConsentDataRequest(
            anonymousId: anonymousId,
            consentCategories: categories,
            timestamp: formatter.string(from: Date()),
            platform: SlnkaConfig.platform,
            sdkVersion: SlnkaConfig.sdkVersion
        )

        // Sync to server (fire-and-forget)
        Task { [weak self, transport] in
            do {
                try await transport?.sendConsentData(request)
                self?.logDebug("Consent synced to server")
            } catch {
                self?.logDebug("Consent sync error: \(error.localizedDescription)")
            }
        }
    }

    /// Opts in to analytics tracking and syncs full consent to the SLNK server.
    ///
    /// Call this when the user grants consent for data collection.
    /// Events tracked before opt-in are silently dropped (CNDP compliance).
    public func optIn() {
        guard isConfigured else { return }
        setConsentData(ConsentCategories(analytics: true, adsPersonalization: true, thirdPartySharing: true))
    }

    /// Opts out of analytics tracking and syncs full opt-out to the SLNK server.
    ///
    /// Call this when the user revokes consent. No further events will be tracked.
    public func optOut() {
        guard isConfigured else { return }
        setConsentData(ConsentCategories(analytics: false, adsPersonalization: false, thirdPartySharing: false))
    }

    /// Returns whether the user has granted consent for analytics tracking.
    public func isConsentGranted() -> Bool {
        guard isConfigured else { return false }
        return storage?.isConsentGranted() ?? false
    }

    // MARK: - Lifecycle

    private func registerLifecycleObservers() {
        #if canImport(UIKit)
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logDebug("App will resign active, flushing events")
            self?.flush()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logDebug("App entered background, flushing events")
            self?.flush()
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.logDebug("App will terminate, flushing events")
            self?.flush()
        }
        #endif
    }

    // MARK: - Validation

    private static func validateApiKey(_ apiKey: String) -> Bool {
        let pattern = "^lsk_(live|test)_.{10,}$"
        return apiKey.range(of: pattern, options: .regularExpression) != nil
    }

    private func ensureConfigured<T>(completion: @escaping (Result<T, SlnkaError>) -> Void) -> Bool {
        guard isConfigured else {
            completion(.failure(.notConfigured))
            return false
        }
        return true
    }

    // MARK: - Logging

    private func logDebug(_ message: String) {
        if config?.debug == true {
            print("[SlnkaSDK] \(message)")
        }
    }
}
