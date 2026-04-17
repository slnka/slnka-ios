import Foundation

/// HTTP transport layer for communicating with the SLNK API.
/// Uses URLSession with no external dependencies.
final class Transport {

    private let apiKey: String
    private let baseURL: String
    private let session: URLSession
    private let debug: Bool

    // MARK: - Init

    init(apiKey: String, baseURL: String, debug: Bool = false) {
        self.apiKey = apiKey
        self.baseURL = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        self.debug = debug

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Event Ingestion

    /// Sends a single event to POST /api/v1/analytics/events
    func sendEvent(_ event: SlnkaEvent, workspaceId: String? = nil) async throws -> TransportResponse {
        let url = "\(baseURL)/api/v1/analytics/events"
        return try await post(url: url, body: event, workspaceId: workspaceId)
    }

    /// Sends a batch of events to POST /api/v1/analytics/events/batch
    func sendBatch(_ events: [SlnkaEvent], workspaceId: String? = nil) async throws -> TransportResponse {
        let url = "\(baseURL)/api/v1/analytics/events/batch"
        let payload = BatchPayload(events: events)
        return try await post(url: url, body: payload, workspaceId: workspaceId)
    }

    // MARK: - Consent

    /// Sends granular consent data to POST /api/v1/sdk/consent
    func sendConsentData(_ request: ConsentDataRequest) async throws {
        let url = "\(baseURL)/api/v1/sdk/consent"
        let response = try await post(url: url, body: request)
        if !response.success {
            logDebug("Consent sync failed: HTTP \(response.statusCode)")
        }
    }

    // MARK: - Deep Links

    /// Resolves a direct deep link via GET /api/v1/deeplinks/resolve/{shortCode}.
    /// Used when the app is already installed and receives a Universal Link / App Link.
    func resolveByShortCode(_ shortCode: String, platform: String = "ios") async throws -> DeepLinkResolveResponse? {
        let url = "\(baseURL)/api/v1/deeplinks/resolve/\(shortCode)?platform=\(platform)"
        let data = try await get(url: url)
        return try JSONDecoder().decode(DeepLinkResolveResponse.self, from: data)
    }

    /// Resolves a deferred deep link via POST /api/v1/deeplinks/resolve.
    /// Supports multiple resolution methods: CLIPBOARD_TOKEN, REFERRER, FINGERPRINT.
    func resolveDeepLink(request: DeepLinkResolveRequestDTO) async throws -> DeepLinkResolveResponse? {
        let url = "\(baseURL)/api/v1/deeplinks/resolve"

        guard let urlObj = URL(string: url) else {
            throw SlnkaError.invalidURL(url)
        }

        var urlRequest = buildRequest(url: urlObj, method: "POST")
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlnkaError.invalidResponse(statusCode: 0, body: nil)
        }

        // 204 No Content = no match
        if httpResponse.statusCode == 204 {
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 429 {
                throw SlnkaError.rateLimited
            }
            throw SlnkaError.invalidResponse(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(DeepLinkResolveResponse.self, from: data)
    }

    // MARK: - Deferred Deep Links

    /// Attempts fingerprint matching via POST /api/v1/deferred/match
    func matchDeferred(request: DeferredMatchRequestDTO) async throws -> DeferredMatchResponseDTO? {
        let url = "\(baseURL)/api/v1/deferred/match"

        guard let urlObj = URL(string: url) else {
            throw SlnkaError.invalidURL(url)
        }

        var urlRequest = buildRequest(url: urlObj, method: "POST")
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlnkaError.invalidResponse(statusCode: 0, body: nil)
        }

        // 204 No Content = no match
        if httpResponse.statusCode == 204 {
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            throw SlnkaError.invalidResponse(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(DeferredMatchResponseDTO.self, from: data)
    }

    // MARK: - Attribution

    /// Records a multi-touch attribution touchpoint via POST /api/v1/analytics/attribution/touchpoint
    func sendAttribution(request: AttributionRequestDTO) async throws -> AttributionResponseDTO {
        let url = "\(baseURL)/api/v1/analytics/attribution/touchpoint"
        let data = try await postReturningData(url: url, body: request)
        return try JSONDecoder().decode(AttributionResponseDTO.self, from: data)
    }

    /// Records a conversion event via POST /api/v1/analytics/attribution/conversion
    func sendConversion(request: ConversionRequestDTO) async throws {
        let url = "\(baseURL)/api/v1/analytics/attribution/conversion"
        let response = try await post(url: url, body: request)
        if !response.success {
            logDebug("Conversion request failed: HTTP \(response.statusCode)")
        }
    }

    /// Matches an install fingerprint to a previous click via POST /api/v1/attribution/match
    /// Returns nil if no match is found (204 No Content).
    func matchInstallAttribution(request: InstallAttributionRequestDTO) async throws -> InstallAttributionResponseDTO? {
        let url = "\(baseURL)/api/v1/attribution/match"

        guard let urlObj = URL(string: url) else {
            throw SlnkaError.invalidURL(url)
        }

        var urlRequest = buildRequest(url: urlObj, method: "POST")
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlnkaError.invalidResponse(statusCode: 0, body: nil)
        }

        // 204 No Content = no match found
        if httpResponse.statusCode == 204 {
            return nil
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 429 {
                throw SlnkaError.rateLimited
            }
            throw SlnkaError.invalidResponse(statusCode: httpResponse.statusCode, body: body)
        }

        return try JSONDecoder().decode(InstallAttributionResponseDTO.self, from: data)
    }

    // MARK: - Feedback

    /// Submits a single feedback response to POST /api/v1/feedback/responses.
    /// Returns `true` on success.
    func submitFeedbackResponse(_ payload: [String: Any]) async -> Bool {
        let url = "\(baseURL)/api/v1/feedback/responses"

        guard let urlObj = URL(string: url) else {
            logDebug("Invalid URL: \(url)")
            return false
        }

        var request = buildRequest(url: urlObj, method: "POST")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            logDebug("Failed to serialize feedback payload: \(error.localizedDescription)")
            return false
        }

        logDebug("POST \(url)")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            logDebug("Feedback response: HTTP \(httpResponse.statusCode)")
            if !(200...299).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8)
                logDebug("Feedback submit error: \(body ?? "no body")")
            }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            logDebug("Feedback network error: \(error.localizedDescription)")
            return false
        }
    }

    /// Starts a survey response via POST /api/v1/feedback/surveys/responses.
    /// Returns the server-assigned response ID, or `nil` on failure.
    func startSurveyResponse(_ payload: [String: Any]) async -> String? {
        let url = "\(baseURL)/api/v1/feedback/surveys/responses"

        guard let urlObj = URL(string: url) else {
            logDebug("Invalid URL: \(url)")
            return nil
        }

        var request = buildRequest(url: urlObj, method: "POST")
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            logDebug("Failed to serialize survey start payload: \(error.localizedDescription)")
            return nil
        }

        logDebug("POST \(url)")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                logDebug("Start survey response failed")
                return nil
            }

            // Parse "id" from response JSON
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? String {
                return id
            }
            return nil
        } catch {
            logDebug("Survey start network error: \(error.localizedDescription)")
            return nil
        }
    }

    /// Marks a survey response as complete via PUT /api/v1/feedback/surveys/responses/{responseId}/complete.
    /// Returns `true` on success.
    func completeSurveyResponse(responseId: String) async -> Bool {
        let url = "\(baseURL)/api/v1/feedback/surveys/responses/\(responseId)/complete"

        guard let urlObj = URL(string: url) else {
            logDebug("Invalid URL: \(url)")
            return false
        }

        let request = buildRequest(url: urlObj, method: "PUT")
        logDebug("PUT \(url)")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            logDebug("Complete survey response: HTTP \(httpResponse.statusCode)")
            if !(200...299).contains(httpResponse.statusCode) {
                let body = String(data: data, encoding: .utf8)
                logDebug("Complete survey error: \(body ?? "no body")")
            }
            return (200...299).contains(httpResponse.statusCode)
        } catch {
            logDebug("Complete survey network error: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Private Helpers

    private func post<T: Encodable>(url: String, body: T, workspaceId: String? = nil) async throws -> TransportResponse {
        guard let urlObj = URL(string: url) else {
            throw SlnkaError.invalidURL(url)
        }

        var request = buildRequest(url: urlObj, method: "POST", workspaceId: workspaceId)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        logDebug("POST \(url)")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return TransportResponse(success: false, retryable: true, statusCode: 0)
            }

            let statusCode = httpResponse.statusCode
            logDebug("Response: HTTP \(statusCode)")

            if (200...299).contains(statusCode) {
                return TransportResponse(success: true, retryable: false, statusCode: statusCode)
            }

            if statusCode == 429 {
                return TransportResponse(success: false, retryable: true, statusCode: statusCode)
            }

            if statusCode >= 400 && statusCode < 500 {
                let body = String(data: data, encoding: .utf8)
                logDebug("Client error: \(body ?? "no body")")
                return TransportResponse(success: false, retryable: false, statusCode: statusCode)
            }

            // 5xx = server error, retry
            return TransportResponse(success: false, retryable: true, statusCode: statusCode)
        } catch {
            logDebug("Network error: \(error.localizedDescription)")
            throw SlnkaError.networkError(underlying: error)
        }
    }

    private func postReturningData<T: Encodable>(url: String, body: T) async throws -> Data {
        guard let urlObj = URL(string: url) else {
            throw SlnkaError.invalidURL(url)
        }

        var request = buildRequest(url: urlObj, method: "POST")
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(body)

        logDebug("POST \(url)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlnkaError.invalidResponse(statusCode: 0, body: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 429 {
                throw SlnkaError.rateLimited
            }
            throw SlnkaError.invalidResponse(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }

    private func get(url: String) async throws -> Data {
        guard let urlObj = URL(string: url) else {
            throw SlnkaError.invalidURL(url)
        }

        let request = buildRequest(url: urlObj, method: "GET")
        logDebug("GET \(url)")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlnkaError.invalidResponse(statusCode: 0, body: nil)
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8)
            if httpResponse.statusCode == 404 {
                throw SlnkaError.deepLinkNotFound
            }
            if httpResponse.statusCode == 429 {
                throw SlnkaError.rateLimited
            }
            throw SlnkaError.invalidResponse(statusCode: httpResponse.statusCode, body: body)
        }

        return data
    }

    private func buildRequest(url: URL, method: String, workspaceId: String? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("SlnkaSDK-iOS/\(SlnkaConfig.sdkVersion)", forHTTPHeaderField: "User-Agent")

        if let workspaceId = workspaceId {
            request.setValue(workspaceId, forHTTPHeaderField: "X-Workspace-Id")
        }

        return request
    }

    private func logDebug(_ message: String) {
        if debug {
            print("[SlnkaSDK:Transport] \(message)")
        }
    }
}

// MARK: - Transport DTOs

struct TransportResponse {
    let success: Bool
    let retryable: Bool
    let statusCode: Int
}

/// Request DTO for POST /api/v1/deeplinks/resolve
struct DeepLinkResolveRequestDTO: Codable {
    let method: String   // "CLIPBOARD_TOKEN", "REFERRER", or "FINGERPRINT"
    let token: String?
    let referrerData: String?
    let deviceModel: String?
    let osVersion: String?
    let screenSize: String?
    let locale: String?
    let timezone: String?
    let carrier: String?
    let userAgentHash: String?
    let fingerprintHash: String?
    /// Source parameter forwarded from the original URL (e.g. "qr" for QR code scans).
    /// Allows the backend to differentiate QR scans from regular clicks.
    let src: String?
}

/// Response from POST /api/v1/deeplinks/resolve
struct DeepLinkResolveResponse: Codable {
    let resolved: Bool
    let screen: String?
    let params: [String: AnyCodable]?
    let utmSource: String?
    let utmMedium: String?
    let utmCampaign: String?
    let confidence: Double?
    let linkId: String?
    let method: String?
}

/// Request DTO for POST /api/v1/deferred/match
struct DeferredMatchRequestDTO: Codable {
    let fingerprint: FingerprintDTO
    let deviceId: String?
    let appVersion: String?
    let sdkVersion: String?
}

struct FingerprintDTO: Codable {
    let userAgent: String?
    let screenWidth: Int?
    let screenHeight: Int?
    let timezone: String?
    let language: String?
    let platform: String
}

/// Response DTO from POST /api/v1/deferred/match
struct DeferredMatchResponseDTO: Codable {
    let matched: Bool
    let confidence: Double?
    let deepLinkPath: String?
    let params: [String: AnyCodable]?
    let campaignId: String?
    let originalShortCode: String?
    let originalUrl: String?
    let contextId: String?
}

/// Request DTO for POST /api/v1/analytics/attribution/conversion
struct ConversionRequestDTO: Codable {
    let visitorId: String
    let conversionEvent: String
    let conversionValue: Double?
    let goalId: String?
    let attributionModel: String
}

/// Request DTO for POST /api/v1/analytics/attribution/touchpoint
struct AttributionRequestDTO: Codable {
    let visitorId: String
    let linkId: String?
    let touchpointType: String
    let channel: String
    let source: String?
    let medium: String?
    let campaignId: String?
    let fingerprint: FingerprintDTO?
}

/// Response DTO from POST /api/v1/analytics/attribution/touchpoint
struct AttributionResponseDTO: Codable {
    let id: String?
    let linkId: String?
    let visitorId: String?
    let attributionModel: String?
    let attributionWeight: Double?
}

/// Request DTO for POST /api/v1/attribution/match (install fingerprint matching)
struct InstallAttributionRequestDTO: Codable {
    let deviceModel: String?
    let osVersion: String?
    let screenSize: String?
    let locale: String?
    let timezone: String?
    let carrier: String?
    let userAgentHash: String?
    let fingerprintHash: String?
}

/// Response DTO from POST /api/v1/attribution/match
struct InstallAttributionResponseDTO: Codable {
    let linkId: String
    let confidence: Double
    let method: String
}
