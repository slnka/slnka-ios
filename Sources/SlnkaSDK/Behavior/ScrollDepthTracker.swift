import Foundation
import SwiftUI

// MARK: - Public Modifier

public extension View {
    /// Tracks scroll depth of a `ScrollView` and emits a ``MobileScrollEvent``
    /// each time the user crosses a 25 / 50 / 75 / 90 / 100 % threshold.
    ///
    /// Each threshold fires **at most once per modifier instance** (i.e. once
    /// per screen presentation).
    ///
    /// ## Usage
    /// Apply this modifier directly to the ScrollView. The modifier installs a
    /// named coordinate space and uses a transparent geometry reader to track
    /// the scroll content's bounds — no additional setup is required:
    ///
    /// ```swift
    /// ScrollView {
    ///     ForEach(transactions) { TransactionRow($0) }
    /// }
    /// .slnkaTrackScroll("transactions_list")
    /// ```
    ///
    /// ## Approximation
    /// Depth is `(scrollOffset + viewportHeight) / contentHeight * 100`. For
    /// variable-height items this is good enough for funnel / engagement
    /// analytics; it is **not** a pixel-perfect scroll percentage because the
    /// underlying SwiftUI scroll metrics are themselves approximated.
    ///
    /// Disabled silently when ``SlnkaConfig/enableScrollDepth`` is `false`.
    func slnkaTrackScroll(_ composableId: String) -> some View {
        modifier(SlnkaTrackScrollModifier(composableId: composableId))
    }
}

// MARK: - Internal Implementation

private struct SlnkaTrackScrollModifier: ViewModifier {
    let composableId: String
    @Environment(\.slnkaScreenName) private var screenName
    @State private var emittedThresholds: Set<Int> = []
    @State private var startTime: Date = Date()
    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0

    private static let thresholds: [Int] = [25, 50, 75, 90, 100]
    private static let coordinateSpaceName = "slnka_scroll_space"

    func body(content: Content) -> some View {
        content
            .coordinateSpace(name: Self.coordinateSpaceName)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: SlnkaScrollViewportPreferenceKey.self,
                            value: proxy.size.height
                        )
                }
            )
            .overlay(
                // Inject a 1pt invisible probe at the top of the content's
                // coordinate space. Its `minY` in the named coordinate space
                // is the negated scroll offset; its `maxY` minus probe height
                // gives us the content height when we know the viewport.
                GeometryReader { proxy -> Color in
                    let frame = proxy.frame(in: .named(Self.coordinateSpaceName))
                    DispatchQueue.main.async {
                        // contentHeight ≈ |minY| + viewportHeight when scrolled
                        // to bottom; tracked via continuous offset updates.
                        let offset = -frame.minY
                        if abs(offset - scrollOffset) > 0.5 {
                            scrollOffset = offset
                        }
                        let measuredContent = max(frame.height, viewportHeight)
                        if abs(measuredContent - contentHeight) > 0.5 {
                            contentHeight = measuredContent
                        }
                    }
                    return Color.clear
                }
                .allowsHitTesting(false)
            )
            .onPreferenceChange(SlnkaScrollViewportPreferenceKey.self) { newHeight in
                viewportHeight = newHeight
                checkDepth()
            }
            .onChange(of: scrollOffset) { _ in checkDepth() }
            .onChange(of: contentHeight) { _ in checkDepth() }
            .onAppear {
                startTime = Date()
                emittedThresholds.removeAll()
            }
            .onDisappear {
                emittedThresholds.removeAll()
            }
    }

    private func checkDepth() {
        guard Slnka.isScrollDepthEnabled() else { return }
        guard contentHeight > 0, viewportHeight > 0 else { return }

        // Effective scrollable extent (content beyond the viewport).
        let scrollable = max(contentHeight - viewportHeight, 0)
        let depthPercent: Int
        if scrollable <= 0 {
            // Content fits entirely in the viewport → user has seen 100%.
            depthPercent = 100
        } else {
            let raw = (scrollOffset + viewportHeight) / contentHeight * 100
            depthPercent = max(0, min(100, Int(raw.rounded())))
        }

        for threshold in Self.thresholds where depthPercent >= threshold && !emittedThresholds.contains(threshold) {
            emittedThresholds.insert(threshold)
            emit(threshold: threshold)
        }
    }

    private func emit(threshold: Int) {
        guard Slnka.isConfiguredForBehavior(), Slnka.isScrollDepthEnabled() else { return }
        guard Slnka.isConsentGrantedSafe() else { return }
        guard let sessionId = Slnka.getCurrentSessionId() else { return }
        guard let anonymousId = Slnka.getAnonymousIdSafe() else { return }

        let timeOnScreenMs = Int64(Date().timeIntervalSince(startTime) * 1000)

        let event = MobileScrollEvent(
            eventId: "scrl_" + Slnka.shortId(),
            eventTime: Date(),
            sessionId: sessionId,
            userId: Slnka.shared.getUserId(),
            anonymousId: anonymousId,
            screenName: screenName,
            composableId: composableId,
            depthPercent: threshold,
            timeOnScreenMs: timeOnScreenMs,
            appVersion: Slnka.getAppVersionSafe(),
            osVersion: Slnka.getOsVersionSafe(),
            deviceModel: Slnka.getDeviceModelSafe()
        )

        Slnka.behaviorEventQueue?.emit(.scroll(event))
    }
}

private struct SlnkaScrollViewportPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
