import Foundation
import SwiftUI

// MARK: - Public Modifier

public extension View {
    /// Detects clusters of frantic taps (rage clicks) on this view.
    ///
    /// Algorithm: sliding window 2 s + clustering radius 50 pt.
    /// Emits a ``MobileRageEvent`` when at least 3 taps fall within the same
    /// radius inside the time window. Per-cluster debounce prevents double
    /// firing.
    ///
    /// ## Gesture safety (CRITICAL)
    /// Like ``View/slnkaTrackTaps(_:)``, this modifier observes events via
    /// `simultaneousGesture(SpatialTapGesture())` and never blocks the
    /// underlying `Button` / `onTapGesture`.
    ///
    /// ## Usage
    /// ```swift
    /// Button("Connexion") { onLogin() }
    ///     .slnkaDetectRage("login_button")
    /// ```
    ///
    /// Disabled silently when ``SlnkaConfig/enableRageDetection`` is `false`.
    func slnkaDetectRage(_ composableId: String) -> some View {
        modifier(SlnkaDetectRageModifier(composableId: composableId))
    }
}

// MARK: - Internal Implementation

/// Internal tap record kept inside the sliding window buffer.
private struct RageTapEvent {
    let time: Date
    let xPx: CGFloat
    let yPx: CGFloat
}

private final class RageBuffer {
    /// Lock-protected sliding-window buffer of taps. Keeps the modifier
    /// thread-safe even though SpatialTapGesture callbacks run on the main
    /// thread — defensive in case SwiftUI ever hops dispatch queues.
    private var taps: [RageTapEvent] = []
    private var lastEmit: Date = .distantPast
    private let lock = NSLock()

    func appendAndPrune(_ tap: RageTapEvent, windowSeconds: TimeInterval) -> [RageTapEvent] {
        lock.lock(); defer { lock.unlock() }
        taps.append(tap)
        let cutoff = tap.time.addingTimeInterval(-windowSeconds)
        taps.removeAll { $0.time < cutoff }
        return taps
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        taps.removeAll()
    }

    func canEmit(now: Date, windowSeconds: TimeInterval) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return now.timeIntervalSince(lastEmit) > windowSeconds
    }

    func markEmit(at date: Date) {
        lock.lock(); defer { lock.unlock() }
        lastEmit = date
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        taps.removeAll()
        lastEmit = .distantPast
    }
}

private struct SlnkaDetectRageModifier: ViewModifier {
    let composableId: String
    @Environment(\.slnkaScreenName) private var screenName
    @State private var size: CGSize = .zero
    @State private var buffer = RageBuffer()

    private static let windowSeconds: TimeInterval = 2.0
    private static let clusterRadius: CGFloat = 50
    private static let minClusterSize: Int = 3

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SlnkaSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(SlnkaSizePreferenceKey.self) { self.size = $0 }
            // DragGesture(minimumDistance: 0) is the iOS 15-compatible
            // equivalent of `SpatialTapGesture` (iOS 16+).
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        handleTap(at: value.startLocation)
                    }
            )
            .onDisappear { buffer.reset() }
    }

    private func handleTap(at location: CGPoint) {
        guard Slnka.isRageDetectionEnabled() else { return }

        let now = Date()
        let tap = RageTapEvent(time: now, xPx: location.x, yPx: location.y)
        let updated = buffer.appendAndPrune(tap, windowSeconds: Self.windowSeconds)

        guard updated.count >= Self.minClusterSize else { return }
        guard let cluster = Self.findCluster(updated, radius: Self.clusterRadius) else { return }
        guard cluster.count >= Self.minClusterSize else { return }

        // Debounce: avoid re-emitting within the same window.
        guard buffer.canEmit(now: now, windowSeconds: Self.windowSeconds) else { return }
        buffer.markEmit(at: now)

        emit(cluster: cluster, size: size, screenName: screenName, composableId: composableId)

        // Clear buffer after emit so overlapping clusters don't double-fire.
        buffer.clear()
    }

    /// Cluster algorithm: pick each tap as anchor, gather every tap within
    /// `radius`, then verify the centroid keeps every member within `radius`.
    /// Returns the largest coherent cluster (≥ minClusterSize) or nil.
    ///
    /// Brute-force O(n²) is fine — buffer is bounded by the 2s window
    /// (typically ≤ 10–15 taps even for the most frantic user).
    static func findCluster(_ taps: [RageTapEvent], radius: CGFloat) -> [RageTapEvent]? {
        guard taps.count >= minClusterSize else { return nil }

        var best: [RageTapEvent]? = nil

        for anchor in taps {
            let nearby = taps.filter {
                let dx = $0.xPx - anchor.xPx
                let dy = $0.yPx - anchor.yPx
                return (dx * dx + dy * dy).squareRoot() <= radius
            }
            guard nearby.count >= minClusterSize else { continue }

            let cx = nearby.reduce(into: CGFloat(0)) { $0 += $1.xPx } / CGFloat(nearby.count)
            let cy = nearby.reduce(into: CGFloat(0)) { $0 += $1.yPx } / CGFloat(nearby.count)
            let coherent = nearby.allSatisfy {
                let dx = $0.xPx - cx
                let dy = $0.yPx - cy
                return (dx * dx + dy * dy).squareRoot() <= radius
            }
            if coherent, best == nil || nearby.count > (best?.count ?? 0) {
                best = nearby
            }
        }

        return best
    }

    private func emit(
        cluster: [RageTapEvent],
        size: CGSize,
        screenName: String,
        composableId: String
    ) {
        guard Slnka.isConfiguredForBehavior(), Slnka.isRageDetectionEnabled() else { return }
        guard Slnka.isConsentGrantedSafe() else { return }
        guard let sessionId = Slnka.getCurrentSessionId() else { return }
        guard let anonymousId = Slnka.getAnonymousIdSafe() else { return }

        let count = cluster.count
        let centerX = cluster.reduce(into: CGFloat(0)) { $0 += $1.xPx } / CGFloat(count)
        let centerY = cluster.reduce(into: CGFloat(0)) { $0 += $1.yPx } / CGFloat(count)
        let xNorm: Float = size.width > 0 ? Float(max(0.0, min(1.0, centerX / size.width))) : 0
        let yNorm: Float = size.height > 0 ? Float(max(0.0, min(1.0, centerY / size.height))) : 0

        let firstTime = cluster.map { $0.time }.min() ?? Date()
        let lastTime = cluster.map { $0.time }.max() ?? Date()
        let timeSpanMs = Int64(lastTime.timeIntervalSince(firstTime) * 1000)

        let event = MobileRageEvent(
            eventId: "rage_" + Slnka.shortId(),
            eventTime: Date(),
            sessionId: sessionId,
            userId: Slnka.shared.getUserId(),
            anonymousId: anonymousId,
            screenName: screenName,
            composableId: composableId,
            tapCount: count,
            timeSpanMs: timeSpanMs,
            clusterRadiusDp: Int(Self.clusterRadius),
            centerX: xNorm,
            centerY: yNorm,
            appVersion: Slnka.getAppVersionSafe(),
            osVersion: Slnka.getOsVersionSafe(),
            deviceModel: Slnka.getDeviceModelSafe()
        )

        Slnka.behaviorEventQueue?.emit(.rage(event))
    }
}
