import Foundation
import SwiftUI

// MARK: - Screen Name Environment

/// Environment key carrying the current screen name down the SwiftUI tree so
/// that ``View/slnkaTrackTaps(_:)`` (and the rage / scroll modifiers) don't have
/// to be passed the screen name explicitly on every call site.
///
/// Set by ``SlnkaInstrumentedScreen``. Defaults to `"unknown_screen"` when a
/// tap is captured outside any instrumented screen.
private struct SlnkaScreenNameKey: EnvironmentKey {
    static let defaultValue: String = "unknown_screen"
}

public extension EnvironmentValues {
    /// Current SLNK screen name, propagated by ``SlnkaInstrumentedScreen``.
    var slnkaScreenName: String {
        get { self[SlnkaScreenNameKey.self] }
        set { self[SlnkaScreenNameKey.self] = newValue }
    }
}

/// Wrap a screen-level view to broadcast its name to all descendant
/// `slnkaTrackTaps` / `slnkaDetectRage` / `slnkaTrackScroll` modifiers.
///
/// Combine with ``Slnka/trackScreen(_:)`` for engagement-time analytics:
/// ```swift
/// SlnkaInstrumentedScreen("home_screen") {
///     HomeView()
///         .onAppear { Slnka.shared.trackScreen("home_screen") }
/// }
/// ```
public struct SlnkaInstrumentedScreen<Content: View>: View {
    private let name: String
    private let content: () -> Content

    public init(_ name: String, @ViewBuilder content: @escaping () -> Content) {
        self.name = name
        self.content = content
    }

    public var body: some View {
        content().environment(\.slnkaScreenName, name)
    }
}

// MARK: - Tap Tracker Modifier

public extension View {
    /// Captures taps on this view as `MobileTapEvent`s and forwards them to
    /// the SDK behavior queue.
    ///
    /// ## Coordinates
    /// `xNormalized` / `yNormalized` are in `[0.0, 1.0]` relative to the bounded
    /// view — stable across screen sizes and orientations, ideal for heatmaps.
    ///
    /// ## Gesture safety (CRITICAL)
    /// Uses `simultaneousGesture(SpatialTapGesture())` so the underlying
    /// `Button` / `onTapGesture` continues to fire normally — this modifier is
    /// a non-blocking observer.
    ///
    /// ## Usage
    /// ```swift
    /// Button("Simuler un crédit") { onCreditTap() }
    ///     .slnkaTrackTaps("credit_button")
    /// ```
    ///
    /// Wrap the screen with ``SlnkaInstrumentedScreen`` so taps carry a screen
    /// name; otherwise events are emitted with `screenName = "unknown_screen"`.
    ///
    /// ## Disabled state
    /// If ``SlnkaConfig/enableHeatmaps`` is `false` or the SDK has not been
    /// configured, the tap is silently dropped (the underlying gesture still
    /// works — the modifier becomes a no-op observer).
    ///
    /// - Parameter composableId: Stable identifier of this view inside the
    ///   screen (e.g. `"credit_button"`, `"hero_card"`). Use snake_case for
    ///   consistency with the Web / Android SDKs.
    func slnkaTrackTaps(_ composableId: String) -> some View {
        modifier(SlnkaTrackTapsModifier(composableId: composableId))
    }
}

private struct SlnkaTrackTapsModifier: ViewModifier {
    let composableId: String
    @Environment(\.slnkaScreenName) private var screenName
    @State private var size: CGSize = .zero
    @State private var pressLocation: CGPoint?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: SlnkaSizePreferenceKey.self, value: proxy.size)
                }
            )
            .onPreferenceChange(SlnkaSizePreferenceKey.self) { newSize in
                self.size = newSize
            }
            // DragGesture(minimumDistance: 0) is the iOS 15-compatible
            // equivalent of `SpatialTapGesture` (iOS 16+) — it fires the
            // moment the finger touches and exposes `startLocation`.
            // Combined with `simultaneousGesture` it never blocks the
            // underlying Button / onTapGesture.
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if pressLocation == nil {
                            pressLocation = value.startLocation
                        }
                    }
                    .onEnded { value in
                        let location = pressLocation ?? value.startLocation
                        pressLocation = nil
                        Self.handleTap(
                            location: location,
                            size: size,
                            screenName: screenName,
                            composableId: composableId
                        )
                    }
            )
    }

    private static func handleTap(
        location: CGPoint,
        size: CGSize,
        screenName: String,
        composableId: String
    ) {
        guard Slnka.isHeatmapsEnabled() else { return }
        guard size.width > 0, size.height > 0 else { return }
        guard let sessionId = Slnka.getCurrentSessionId() else { return }
        guard let anonymousId = Slnka.getAnonymousIdSafe() else { return }
        guard Slnka.isConsentGrantedSafe() else { return }

        let xNorm = Float(max(0.0, min(1.0, location.x / size.width)))
        let yNorm = Float(max(0.0, min(1.0, location.y / size.height)))

        let event = MobileTapEvent(
            eventId: "tap_" + Slnka.shortId(),
            eventTime: Date(),
            sessionId: sessionId,
            userId: Slnka.shared.getUserId(),
            anonymousId: anonymousId,
            screenName: screenName,
            composableId: composableId,
            xNormalized: xNorm,
            yNormalized: yNorm,
            screenWidth: Int(size.width),
            screenHeight: Int(size.height),
            screenDensity: Float(Slnka.getScreenDensity()),
            appVersion: Slnka.getAppVersionSafe(),
            osVersion: Slnka.getOsVersionSafe(),
            deviceModel: Slnka.getDeviceModelSafe()
        )

        Slnka.behaviorEventQueue?.emit(.tap(event))
    }
}

// MARK: - Shared Preference Key

/// Internal preference key for propagating a view's measured size up the tree
/// without triggering `@State` writes during layout.
internal struct SlnkaSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}
