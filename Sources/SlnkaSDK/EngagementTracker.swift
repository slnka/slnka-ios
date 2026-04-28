import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Engagement time tracker for iOS screens.
///
/// Measures how long each screen is actively visible (foreground) and emits a
/// `screen_view_end` event with `{ screen_name, duration_ms, platform: "ios" }`
/// when:
///  - the user navigates to a different screen (`screenDidAppear` with a
///    different name, or explicit `screenDidDisappear`),
///  - the app resigns active / enters background,
///  - the SDK is shut down.
///
/// ## Design notes
///
/// - Time source: `ProcessInfo.processInfo.systemUptime` — monotonic and
///   *does* advance across suspends, unlike Android's `SystemClock.elapsedRealtime`.
///   We pause the timer on `willResignActiveNotification`, so sleep time is
///   excluded anyway.
/// - Pause on `UIApplication.willResignActiveNotification` (app about to
///   lose focus — app switcher, control center, incoming call, backgrounding).
/// - Resume on `UIApplication.didBecomeActiveNotification`.
/// - No method swizzling: developers must call `Slnka.shared.trackScreen(_:)`
///   explicitly in `viewDidAppear(_:)`. This is App-Store-safe and leaves full
///   control to the integrator (see design doc §4 D3).
/// - Bounce filter: screens viewed for less than 500 ms are discarded
///   (accidental touches / auto-redirects).
/// - Hard cap: durations are clamped to 30 minutes.
/// - Consent gating: events are emitted through the closure supplied at
///   `configure(track:)`, which ultimately hits `EventTracker.track(...)`.
///   Consent enforcement happens downstream; no duplicate check here.
///
/// Thread-safety: all public methods are serialized on an internal lock.
final class EngagementTracker {

    /// Shared singleton used by `Slnka.shared`.
    static let shared = EngagementTracker()

    private let lock = NSLock()

    private static let minDurationMs: Int64 = 500
    private static let maxDurationMs: Int64 = 30 * 60 * 1000 // 30 minutes
    private static let platform = "ios"

    /// Closure used to emit events. Injected by `SlnkaSDK` at `configure()`
    /// time to avoid a hard reference back to the SDK (no retain cycle).
    private var trackFunc: ((String, [String: Any]) -> Void)?

    /// Name of the currently tracked screen, or nil if none.
    private var currentScreen: String?

    /// `ProcessInfo.systemUptime` captured when the current active period started.
    private var activeSince: TimeInterval = 0

    /// Duration (seconds) already accumulated across prior active periods for `currentScreen`.
    private var accumulated: TimeInterval = 0

    /// Whether the screen timer is currently running.
    private var isTimerRunning: Bool = false

    /// Whether notification observers have been registered.
    private var observersRegistered: Bool = false

    /// Opaque observer tokens returned by the block-based NotificationCenter API.
    /// Retained so we can remove them on shutdown.
    private var observerTokens: [NSObjectProtocol] = []

    private init() {}

    // MARK: - Configuration

    /// Wires the tracker to the SDK and registers UIApplication notification
    /// observers. Must be called once from `Slnka.configure`.
    ///
    /// - Parameter track: Closure invoked to emit an event. Receives the
    ///   event name and properties; it must forward to `EventTracker.track`
    ///   (or equivalent) under consent gating.
    func configure(track: @escaping (String, [String: Any]) -> Void) {
        lock.lock()
        defer { lock.unlock() }

        self.trackFunc = track

        #if canImport(UIKit)
        if !observersRegistered {
            observersRegistered = true
            let center = NotificationCenter.default
            observerTokens.append(center.addObserver(
                forName: UIApplication.willResignActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleWillResignActive()
            })
            observerTokens.append(center.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleDidBecomeActive()
            })
            observerTokens.append(center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.handleDidEnterBackground()
            })
        }
        #endif
    }

    // MARK: - Public entry points

    /// Call when a new screen becomes visible (typically from
    /// `UIViewController.viewDidAppear`). Flushes the previous screen (if any)
    /// and starts tracking `name`.
    func screenDidAppear(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        if currentScreen == trimmed {
            // Same screen re-appeared (e.g. after modal dismiss). Just make
            // sure the timer is running.
            if !isTimerRunning {
                activeSince = ProcessInfo.processInfo.systemUptime
                isTimerRunning = true
            }
            return
        }

        flushCurrentLocked(reason: "screen_change")
        currentScreen = trimmed
        accumulated = 0
        activeSince = ProcessInfo.processInfo.systemUptime
        isTimerRunning = true
    }

    /// Optional hook for integrators who want explicit disappear signals
    /// (e.g. called from `UIViewController.viewDidDisappear`). Flushes the
    /// current screen if it matches `name`.
    func screenDidDisappear(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        if currentScreen == trimmed {
            flushCurrentLocked(reason: "screen_disappeared")
        }
    }

    /// Flushes the current screen and detaches from UIApplication
    /// notifications. Called by `SlnkaSDK` on teardown.
    func shutdown() {
        lock.lock()
        flushCurrentLocked(reason: "sdk_shutdown")
        currentScreen = nil
        accumulated = 0
        activeSince = 0
        isTimerRunning = false
        trackFunc = nil
        let wasRegistered = observersRegistered
        observersRegistered = false
        lock.unlock()

        #if canImport(UIKit)
        if wasRegistered {
            let center = NotificationCenter.default
            for token in observerTokens {
                center.removeObserver(token)
            }
            observerTokens.removeAll()
        }
        #endif
    }

    // MARK: - UIApplication notification handlers

    private func handleWillResignActive() {
        // User is leaving focus (app switcher, control center, incoming call,
        // or about to background). Accumulate the active period but keep the
        // screen name so we can resume seamlessly on didBecomeActive.
        lock.lock()
        defer { lock.unlock() }
        pauseTimerLocked()
    }

    private func handleDidBecomeActive() {
        lock.lock()
        defer { lock.unlock() }
        if currentScreen != nil && !isTimerRunning {
            activeSince = ProcessInfo.processInfo.systemUptime
            isTimerRunning = true
        }
    }

    private func handleDidEnterBackground() {
        // Full background. Flush the current screen's accumulated time.
        lock.lock()
        defer { lock.unlock() }
        flushCurrentLocked(reason: "app_background")
    }

    // MARK: - Internal

    private func pauseTimerLocked() {
        guard isTimerRunning else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let delta = max(0, now - activeSince)
        accumulated += delta
        isTimerRunning = false
    }

    private func flushCurrentLocked(reason: String) {
        guard let screen = currentScreen else { return }

        pauseTimerLocked()

        var durationMs = Int64((accumulated * 1000.0).rounded())
        if durationMs > EngagementTracker.maxDurationMs {
            durationMs = EngagementTracker.maxDurationMs
        }

        // Reset state before dispatching so re-entrant calls are safe.
        currentScreen = nil
        accumulated = 0
        activeSince = 0

        guard durationMs >= EngagementTracker.minDurationMs else { return }
        guard let track = trackFunc else { return }

        let props: [String: Any] = [
            "screen_name": screen,
            "duration_ms": durationMs,
            "platform": EngagementTracker.platform,
            "flush_reason": reason
        ]
        track("screen_view_end", props)
    }
}
