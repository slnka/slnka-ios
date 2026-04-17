import Foundation

/// Configuration for the SLNK iOS SDK.
public struct SlnkaConfig: Sendable {

    /// Base URL for the SLNK API server (e.g., `https://api.slnk.ma`). Required — no default.
    public let serverUrl: String

    /// Enable Universal Links / deep link handling.
    /// Default: `true`
    public let enableDeepLinks: Bool

    /// Enable attribution tracking (fingerprint matching).
    /// Default: `true`
    public let enableAttribution: Bool

    /// CNDP compliance mode (Law 09-08).
    /// When enabled, the SDK never collects IDFA and ensures IP hashing is server-side.
    /// Default: `true`
    public let cndpCompliant: Bool

    /// Interval in milliseconds between automatic event flushes.
    /// Aligned with Android/Web/RN SDKs (all use milliseconds).
    /// Default: `30_000` (30 seconds)
    public let flushIntervalMs: Int

    /// Number of events that triggers an automatic flush.
    /// Default: `10`
    public let flushSize: Int

    /// Maximum number of events stored in the offline retry queue.
    /// Default: `1000`
    public let maxQueueSize: Int

    /// Maximum number of retry attempts for failed event batches.
    /// Default: `3`
    public let maxRetries: Int

    /// Enable debug logging to the console.
    /// Default: `false`
    public let debug: Bool

    /// SDK version string, sent as context metadata.
    public static let sdkVersion = "1.0.0-beta.4"

    /// Platform identifier sent to the server.
    public static let platform = "ios"

    public init(
        serverUrl: String,
        enableDeepLinks: Bool = true,
        enableAttribution: Bool = true,
        cndpCompliant: Bool = true,
        flushIntervalMs: Int = 30_000,
        flushSize: Int = 10,
        maxQueueSize: Int = 1000,
        maxRetries: Int = 3,
        debug: Bool = false
    ) {
        self.serverUrl = serverUrl
        self.enableDeepLinks = enableDeepLinks
        self.enableAttribution = enableAttribution
        self.cndpCompliant = cndpCompliant
        self.flushIntervalMs = flushIntervalMs
        self.flushSize = flushSize
        self.maxQueueSize = maxQueueSize
        self.maxRetries = maxRetries
        self.debug = debug
    }
}
