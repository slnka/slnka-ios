import Foundation

// MARK: - Errors

/// All errors that can be thrown by the SLNK SDK.
public enum SlnkaError: Error, CustomStringConvertible {
    /// SDK has not been configured. Call `Slnka.configure(apiKey:config:)` first.
    case notConfigured
    /// A network request failed.
    case networkError(underlying: Error)
    /// The server returned an unexpected or invalid response.
    case invalidResponse(statusCode: Int, body: String?)
    /// No deep link was found for the given short code.
    case deepLinkNotFound
    /// The provided URL could not be parsed.
    case invalidURL(String)
    /// The provided API key format is invalid.
    case invalidApiKey
    /// Server returned a rate limit response (429).
    case rateLimited
    /// A generic SDK error with a description.
    case sdkError(String)

    public var description: String {
        switch self {
        case .notConfigured:
            return "SlnkaSDK is not configured. Call Slnka.configure(apiKey:config:) first."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse(let code, let body):
            return "Invalid response (HTTP \(code)): \(body ?? "no body")"
        case .deepLinkNotFound:
            return "Deep link not found."
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .invalidApiKey:
            return "Invalid API key format. Expected lsk_live_* or lsk_test_*."
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .sdkError(let message):
            return "SDK error: \(message)"
        }
    }
}

// MARK: - Events

/// An analytics event to be sent to the SLNK backend.
public struct SlnkaEvent: Codable, Sendable {
    public let eventName: String
    public let eventId: String
    public let anonymousId: String
    public let userId: String?
    public let properties: [String: AnyCodable]
    public let context: [String: AnyCodable]
    public let timestamp: String
    public let sessionId: String?
    public let platform: String

    public init(
        eventName: String,
        eventId: String = UUID().uuidString,
        anonymousId: String,
        userId: String? = nil,
        properties: [String: Any] = [:],
        context: [String: Any] = [:],
        timestamp: Date = Date(),
        sessionId: String? = nil
    ) {
        self.eventName = eventName
        self.eventId = eventId
        self.anonymousId = anonymousId
        self.userId = userId
        self.properties = properties.mapValues { AnyCodable($0) }
        self.context = context.mapValues { AnyCodable($0) }
        self.sessionId = sessionId
        self.platform = "IOS"

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestamp = formatter.string(from: timestamp)
    }
}

/// Batch payload matching the backend IngestBatchRequest.
struct BatchPayload: Codable {
    let events: [SlnkaEvent]
}

// MARK: - Attribution

/// Result of an attribution matching attempt.
public struct AttributionResult: Codable, Sendable {
    public let linkId: String?
    public let confidence: Double
    public let method: String

    public init(linkId: String?, confidence: Double, method: String) {
        self.linkId = linkId
        self.confidence = confidence
        self.method = method
    }
}

// MARK: - Attribution Model

/// Attribution model used for conversion credit distribution.
public enum AttributionModel: String, Codable, Sendable {
    case firstTouch = "FIRST_TOUCH"
    case lastTouch = "LAST_TOUCH"
    case linear = "LINEAR"
    case timeDecay = "TIME_DECAY"
    case positionBased = "POSITION_BASED"
}

// MARK: - Consent

/// Granular consent categories for CNDP (Law 09-08) compliance.
///
/// Controls which types of data processing the user has consented to.
public struct ConsentCategories: Codable, Sendable {
    /// Whether the user consents to analytics tracking.
    public let analytics: Bool
    /// Whether the user consents to ads personalization.
    public let adsPersonalization: Bool
    /// Whether the user consents to third-party data sharing.
    public let thirdPartySharing: Bool

    public init(analytics: Bool = true, adsPersonalization: Bool = true, thirdPartySharing: Bool = true) {
        self.analytics = analytics
        self.adsPersonalization = adsPersonalization
        self.thirdPartySharing = thirdPartySharing
    }
}

/// Request DTO for POST /api/v1/sdk/consent
struct ConsentDataRequest: Codable {
    let anonymousId: String
    let consentCategories: ConsentCategories
    let timestamp: String
    let platform: String
    let sdkVersion: String
}

// MARK: - Mobile Behavior Tracking (US-833 / US-834 / US-835 / US-836)

/// Tap (click) event captured by `View.slnkaTrackTaps(_:)`.
///
/// Coordinates are normalized in `[0.0, 1.0]` relative to the bounded view so
/// that tap heatmaps remain stable across screen sizes / orientations.
///
/// `screenWidth` / `screenHeight` are the **view** dimensions in points
/// (NOT the device screen) — they are useful for replay debugging only.
public struct MobileTapEvent: Sendable {
    public let eventId: String
    public let eventTime: Date
    public let sessionId: String
    public let userId: String?
    public let anonymousId: String
    public let screenName: String
    public let composableId: String
    public let xNormalized: Float
    public let yNormalized: Float
    public let screenWidth: Int
    public let screenHeight: Int
    public let screenDensity: Float
    public let platform: String = "ios"
    public let appVersion: String?
    public let osVersion: String?
    public let deviceModel: String?

    public init(
        eventId: String,
        eventTime: Date,
        sessionId: String,
        userId: String?,
        anonymousId: String,
        screenName: String,
        composableId: String,
        xNormalized: Float,
        yNormalized: Float,
        screenWidth: Int,
        screenHeight: Int,
        screenDensity: Float,
        appVersion: String?,
        osVersion: String?,
        deviceModel: String?
    ) {
        self.eventId = eventId
        self.eventTime = eventTime
        self.sessionId = sessionId
        self.userId = userId
        self.anonymousId = anonymousId
        self.screenName = screenName
        self.composableId = composableId
        self.xNormalized = xNormalized
        self.yNormalized = yNormalized
        self.screenWidth = screenWidth
        self.screenHeight = screenHeight
        self.screenDensity = screenDensity
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }
}

/// Scroll-depth checkpoint event (US-835). Emitted when the user crosses a
/// 25 % / 50 % / 75 % / 90 % / 100 % scroll milestone on a tracked container.
public struct MobileScrollEvent: Sendable {
    public let eventId: String
    public let eventTime: Date
    public let sessionId: String
    public let userId: String?
    public let anonymousId: String
    public let screenName: String
    public let composableId: String
    public let depthPercent: Int
    public let timeOnScreenMs: Int64
    public let platform: String = "ios"
    public let appVersion: String?
    public let osVersion: String?
    public let deviceModel: String?

    public init(
        eventId: String,
        eventTime: Date,
        sessionId: String,
        userId: String?,
        anonymousId: String,
        screenName: String,
        composableId: String,
        depthPercent: Int,
        timeOnScreenMs: Int64,
        appVersion: String?,
        osVersion: String?,
        deviceModel: String?
    ) {
        self.eventId = eventId
        self.eventTime = eventTime
        self.sessionId = sessionId
        self.userId = userId
        self.anonymousId = anonymousId
        self.screenName = screenName
        self.composableId = composableId
        self.depthPercent = depthPercent
        self.timeOnScreenMs = timeOnScreenMs
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }
}

/// Rage-tap event (US-834). Emitted when N taps land within `clusterRadiusDp`
/// of each other within `timeSpanMs`.
public struct MobileRageEvent: Sendable {
    public let eventId: String
    public let eventTime: Date
    public let sessionId: String
    public let userId: String?
    public let anonymousId: String
    public let screenName: String
    public let composableId: String
    public let tapCount: Int
    public let timeSpanMs: Int64
    public let clusterRadiusDp: Int
    public let centerX: Float
    public let centerY: Float
    public let platform: String = "ios"
    public let appVersion: String?
    public let osVersion: String?
    public let deviceModel: String?

    public init(
        eventId: String,
        eventTime: Date,
        sessionId: String,
        userId: String?,
        anonymousId: String,
        screenName: String,
        composableId: String,
        tapCount: Int,
        timeSpanMs: Int64,
        clusterRadiusDp: Int,
        centerX: Float,
        centerY: Float,
        appVersion: String?,
        osVersion: String?,
        deviceModel: String?
    ) {
        self.eventId = eventId
        self.eventTime = eventTime
        self.sessionId = sessionId
        self.userId = userId
        self.anonymousId = anonymousId
        self.screenName = screenName
        self.composableId = composableId
        self.tapCount = tapCount
        self.timeSpanMs = timeSpanMs
        self.clusterRadiusDp = clusterRadiusDp
        self.centerX = centerX
        self.centerY = centerY
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }
}

/// Sealed type carried by the ``BehaviorEventQueue``. Backend distinguishes
/// payloads via the `eventType` discriminator in the JSON envelope (`"click"`,
/// `"scroll"`, `"rage"`).
public enum MobileBehaviorEvent: Sendable {
    case tap(MobileTapEvent)
    case scroll(MobileScrollEvent)
    case rage(MobileRageEvent)
}

// MARK: - AnyCodable

/// A type-erased `Codable` wrapper for heterogeneous dictionaries.
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported type")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }
}
