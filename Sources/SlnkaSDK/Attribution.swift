import Foundation

/// Attribution module for the SLNK platform.
///
/// Sends device fingerprint data to the server for attribution matching.
/// The server compares the fingerprint against stored click contexts to determine
/// which SLNK link drove the app install or re-engagement.
///
/// CNDP Compliance:
/// - No IDFA collection (cndpCompliant mode)
/// - No raw IP sent from SDK (server extracts from request)
/// - Only non-PII device characteristics used for matching
final class Attribution {

    private let transport: Transport
    private let storage: SlnkaStorage
    private let fingerprint: DeviceFingerprint
    private let config: SlnkaConfig
    private let debug: Bool

    init(transport: Transport, storage: SlnkaStorage, fingerprint: DeviceFingerprint, config: SlnkaConfig) {
        self.transport = transport
        self.storage = storage
        self.fingerprint = fingerprint
        self.config = config
        self.debug = config.debug
    }

    /// Records an attribution touchpoint for the current device.
    ///
    /// Called internally after:
    /// - A Universal Link is opened (direct attribution)
    /// - A deferred deep link is resolved (deferred attribution)
    /// - SDK initialization (install attribution)
    ///
    /// - Parameters:
    ///   - linkId: The SLNK link ID (if known from deep link resolution).
    ///   - touchpointType: Type of touchpoint (e.g., "link_click", "app_open", "install").
    ///   - channel: Marketing channel (e.g., "social", "email", "organic").
    ///   - source: Traffic source (e.g., "twitter", "facebook").
    ///   - medium: Traffic medium (e.g., "cpc", "banner").
    ///   - campaignId: Campaign identifier.
    /// - Returns: The attribution result from the server.
    func recordTouchpoint(
        linkId: String? = nil,
        touchpointType: String = "app_open",
        channel: String = "direct",
        source: String? = nil,
        medium: String? = nil,
        campaignId: String? = nil
    ) async -> AttributionResult? {
        guard config.enableAttribution else {
            logDebug("Attribution disabled in config")
            return nil
        }

        let visitorId = storage.getOrCreateAnonymousId()

        let request = AttributionRequestDTO(
            visitorId: visitorId,
            linkId: linkId,
            touchpointType: touchpointType,
            channel: channel,
            source: source,
            medium: medium,
            campaignId: campaignId,
            fingerprint: fingerprint.toDTO()
        )

        do {
            let response = try await transport.sendAttribution(request: request)
            logDebug("Attribution recorded: model=\(response.attributionModel ?? "unknown")")

            return AttributionResult(
                linkId: response.linkId,
                confidence: response.attributionWeight ?? 0.0,
                method: response.attributionModel ?? "unknown"
            )
        } catch {
            logDebug("Attribution failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Records an install attribution event (called once at first launch).
    func recordInstallAttribution() async -> AttributionResult? {
        return await recordTouchpoint(
            touchpointType: "install",
            channel: "organic"
        )
    }

    /// Records attribution from a resolved deep link.
    func recordDeepLinkAttribution(deepLink: DeepLink) async -> AttributionResult? {
        let channel: String
        if deepLink.utmMedium != nil {
            channel = deepLink.utmMedium!
        } else if deepLink.isDeferred {
            channel = "deferred"
        } else {
            channel = "universal_link"
        }

        return await recordTouchpoint(
            linkId: deepLink.linkId,
            touchpointType: deepLink.isDeferred ? "deferred_open" : "link_click",
            channel: channel,
            source: deepLink.utmSource,
            medium: deepLink.utmMedium,
            campaignId: deepLink.utmCampaign
        )
    }

    // MARK: - Conversion Recording

    /// Records a conversion event for multi-touch attribution.
    ///
    /// Sends the conversion to `POST /api/v1/sdk/attribution/conversion`
    /// so that the backend can distribute credit across touchpoints.
    ///
    /// - Parameters:
    ///   - event: The conversion event name (e.g., "purchase_completed", "signup").
    ///   - value: Optional monetary value of the conversion.
    ///   - goalId: Optional conversion goal ID.
    ///   - model: Attribution model to use. Default: `.lastTouch`.
    func recordConversion(
        event: String,
        value: Double? = nil,
        goalId: String? = nil,
        model: AttributionModel = .lastTouch
    ) async {
        guard config.enableAttribution else {
            logDebug("Attribution disabled, skipping conversion")
            return
        }

        let visitorId = storage.getOrCreateAnonymousId()

        let request = ConversionRequestDTO(
            visitorId: visitorId,
            conversionEvent: event,
            conversionValue: value,
            goalId: goalId,
            attributionModel: model.rawValue
        )

        do {
            try await transport.sendConversion(request: request)
            logDebug("Conversion recorded: event=\(event), model=\(model.rawValue)")
        } catch {
            logDebug("Conversion recording failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Logging

    private func logDebug(_ message: String) {
        if debug {
            print("[SlnkaSDK:Attribution] \(message)")
        }
    }
}
