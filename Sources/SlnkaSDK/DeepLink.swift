import Foundation

/// Represents a resolved deep link from the SLNK platform.
public struct DeepLink {

    /// The target screen or route to navigate to in the app.
    /// Example: "/product/123" or "product_detail"
    public let screen: String?

    /// Additional parameters associated with the deep link.
    public let params: [String: Any]

    /// UTM source parameter for campaign tracking.
    public let utmSource: String?

    /// UTM medium parameter for campaign tracking.
    public let utmMedium: String?

    /// UTM campaign parameter for campaign tracking.
    public let utmCampaign: String?

    /// The SLNK link ID that generated this deep link.
    public let linkId: String?

    /// The original short code from the SLNK URL.
    public let shortCode: String?

    /// The original full URL before shortening.
    public let originalUrl: String?

    /// Match confidence score (0.0 - 1.0), relevant for deferred deep links.
    /// Direct Universal Links will have a confidence of 1.0.
    public let confidence: Double

    /// Whether this deep link was resolved via deferred matching.
    public let isDeferred: Bool

    public init(
        screen: String? = nil,
        params: [String: Any] = [:],
        utmSource: String? = nil,
        utmMedium: String? = nil,
        utmCampaign: String? = nil,
        linkId: String? = nil,
        shortCode: String? = nil,
        originalUrl: String? = nil,
        confidence: Double = 1.0,
        isDeferred: Bool = false
    ) {
        self.screen = screen
        self.params = params
        self.utmSource = utmSource
        self.utmMedium = utmMedium
        self.utmCampaign = utmCampaign
        self.linkId = linkId
        self.shortCode = shortCode
        self.originalUrl = originalUrl
        self.confidence = confidence
        self.isDeferred = isDeferred
    }

    // MARK: - Factory

    /// Creates a DeepLink from a resolved API response.
    static func from(response: DeepLinkResolveResponse, shortCode: String) -> DeepLink {
        let params: [String: Any] = response.params?.mapValues { $0.value } ?? [:]

        return DeepLink(
            screen: response.screen,
            params: params,
            utmSource: response.utmSource,
            utmMedium: response.utmMedium,
            utmCampaign: response.utmCampaign,
            linkId: response.linkId,
            shortCode: shortCode,
            originalUrl: nil,
            confidence: response.confidence ?? 1.0,
            isDeferred: false
        )
    }

    /// Creates a DeepLink from a deferred match response.
    static func from(deferred: DeferredMatchResponseDTO) -> DeepLink {
        let params: [String: Any] = deferred.params?.mapValues { $0.value } ?? [:]

        return DeepLink(
            screen: deferred.deepLinkPath,
            params: params,
            utmSource: nil,
            utmMedium: nil,
            utmCampaign: deferred.campaignId != nil ? deferred.campaignId : nil,
            linkId: nil,
            shortCode: deferred.originalShortCode,
            originalUrl: deferred.originalUrl,
            confidence: deferred.confidence ?? 0.0,
            isDeferred: true
        )
    }
}
