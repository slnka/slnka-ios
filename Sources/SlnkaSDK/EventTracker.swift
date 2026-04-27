import Foundation

/// Tracks analytics events for the SLNK platform.
///
/// Provides:
/// - `track(event:properties:)` - Track a custom event
/// - `identify(userId:traits:)` - Link anonymous ID to a known user
/// - `reset()` - Clear identity on logout
///
/// Events are queued and flushed in batches via `EventQueue`.
final class EventTracker {

    private let storage: SlnkaStorage
    private let eventQueue: EventQueue
    private let fingerprint: DeviceFingerprint
    private let config: SlnkaConfig
    private let debug: Bool

    /// Session timeout in seconds (default 30 minutes).
    private let sessionTimeout: TimeInterval = 1800

    private var timedEvents: [String: TimeInterval] = [:]

    init(storage: SlnkaStorage, eventQueue: EventQueue, fingerprint: DeviceFingerprint, config: SlnkaConfig) {
        self.storage = storage
        self.eventQueue = eventQueue
        self.fingerprint = fingerprint
        self.config = config
        self.debug = config.debug

        ensureSession()
    }

    // MARK: - Track

    /// Tracks a custom event with optional properties.
    ///
    /// - Parameters:
    ///   - event: Event name (e.g., "button_clicked", "purchase_completed").
    ///   - properties: Custom key-value properties for the event.
    func track(event: String, properties: [String: Any] = [:]) {
        guard storage.isConsentGranted() else { return }
        ensureSession()

        var resolvedProperties = properties
        if let startMs = timedEvents.removeValue(forKey: event) {
            let durationMs = ProcessInfo.processInfo.systemUptime * 1000 - startMs
            resolvedProperties["duration_ms"] = durationMs
        }

        let slnkEvent = buildEvent(
            eventName: event,
            properties: resolvedProperties
        )

        logDebug("Track: \(event) (id: \(slnkEvent.eventId))")
        eventQueue.enqueue(slnkEvent)
    }

    // MARK: - Identify

    /// Links the anonymous ID to a known user.
    ///
    /// Sends a special `$identify` event and stores the user ID for future events.
    ///
    /// - Parameters:
    ///   - userId: The known user identifier.
    ///   - traits: Optional user traits (name, email, plan, etc.).
    func identify(userId: String, traits: [String: Any] = [:]) {
        ensureSession()

        let previousUserId = storage.getUserId()
        storage.setUserId(userId)
        storage.setUserTraits(traits)

        var properties: [String: Any] = traits
        properties["$user_id"] = userId
        if let previousUserId = previousUserId, previousUserId != userId {
            properties["$previous_user_id"] = previousUserId
        }

        let event = buildEvent(
            eventName: "$identify",
            properties: properties
        )

        logDebug("Identify: \(userId)")
        eventQueue.enqueue(event)
    }

    // MARK: - Reset

    /// Resets the user identity (call on logout).
    ///
    /// - Clears the stored user ID and traits
    /// - Generates a new anonymous ID
    /// - Starts a new session
    func reset() {
        let oldAnonymousId = storage.getOrCreateAnonymousId()

        storage.setUserId(nil)
        storage.setUserTraits(nil)
        let newAnonymousId = storage.resetAnonymousId()
        startNewSession()

        // Send a reset event for server-side identity graph
        let properties: [String: Any] = [
            "$previous_anonymous_id": oldAnonymousId
        ]

        let event = buildEvent(
            eventName: "$reset",
            properties: properties,
            overrideAnonymousId: newAnonymousId
        )

        logDebug("Reset: old=\(oldAnonymousId) new=\(newAnonymousId)")
        eventQueue.enqueue(event)
    }

    // MARK: - Alias

    func alias(newId: String, previousId: String? = nil) {
        guard storage.isConsentGranted() else { return }
        ensureSession()

        let resolvedPreviousId = previousId ?? storage.getOrCreateAnonymousId()

        let properties: [String: Any] = [
            "$new_id": newId,
            "$previous_id": resolvedPreviousId
        ]

        let event = buildEvent(
            eventName: "$alias",
            properties: properties
        )

        logDebug("Alias: \(resolvedPreviousId) -> \(newId)")
        eventQueue.enqueue(event)
    }

    // MARK: - Time Event

    func timeEvent(name: String) {
        timedEvents[name] = ProcessInfo.processInfo.systemUptime * 1000
        logDebug("TimeEvent started: \(name)")
    }

    // MARK: - Session Management

    /// Ensures there is an active session, creating a new one if expired or missing.
    private func ensureSession() {
        if let sessionStart = storage.getSessionStartTime(),
           storage.getSessionId() != nil {
            // Check if session is still valid
            if Date().timeIntervalSince(sessionStart) < sessionTimeout {
                return // Session still active
            }
            logDebug("Session expired, starting new session")
        }

        startNewSession()
    }

    private func startNewSession() {
        let sessionId = "sess_\(UUID().uuidString.lowercased().prefix(12))"
        storage.setSessionId(sessionId)
        storage.setSessionStartTime(Date())
        logDebug("New session: \(sessionId)")
    }

    // MARK: - Event Building

    private func buildEvent(
        eventName: String,
        properties: [String: Any],
        overrideAnonymousId: String? = nil
    ) -> SlnkaEvent {
        let anonymousId = overrideAnonymousId ?? storage.getOrCreateAnonymousId()
        let userId = storage.getUserId()
        let sessionId = storage.getSessionId()

        var context = fingerprint.toContext()
        context["app"] = [
            "name": Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Unknown",
            "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0",
            "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        ]

        return SlnkaEvent(
            eventName: eventName,
            anonymousId: anonymousId,
            userId: userId,
            properties: properties,
            context: context,
            timestamp: Date(),
            sessionId: sessionId
        )
    }

    // MARK: - Accessors

    func getAnonymousId() -> String {
        return storage.getOrCreateAnonymousId()
    }

    func getUserId() -> String? {
        return storage.getUserId()
    }

    // MARK: - Logging

    private func logDebug(_ message: String) {
        if debug {
            print("[SlnkaSDK:EventTracker] \(message)")
        }
    }
}
