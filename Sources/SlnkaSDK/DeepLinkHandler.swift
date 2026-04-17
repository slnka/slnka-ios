import Foundation

/// Handles Universal Link resolution for the SLNK platform.
///
/// When a user taps a SLNK short link (e.g., `https://slnk.ma/abc1234`),
/// iOS opens the app via a Universal Link. This handler:
/// 1. Extracts the short code from the URL
/// 2. Calls the SLNK API to resolve it to deep link parameters
/// 3. Returns a `DeepLink` object for the app to route
final class DeepLinkHandler {

    private let transport: Transport
    private let config: SlnkaConfig
    private let debug: Bool

    init(transport: Transport, config: SlnkaConfig) {
        self.transport = transport
        self.config = config
        self.debug = config.debug
    }

    /// Handles an incoming Universal Link `NSUserActivity`.
    ///
    /// - Parameters:
    ///   - userActivity: The `NSUserActivity` from `scene(_:continue:)` or
    ///     `application(_:continue:restorationHandler:)`.
    ///   - completion: Called with the resolved `DeepLink` or an error.
    func handleUniversalLink(
        _ userActivity: NSUserActivity,
        completion: @escaping (Result<DeepLink, SlnkaError>) -> Void
    ) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            completion(.failure(.sdkError("Not a browsing web activity")))
            return
        }

        handleURL(url, completion: completion)
    }

    /// Handles a URL directly (for custom URL scheme or manual invocation).
    ///
    /// - Parameters:
    ///   - url: The URL to resolve.
    ///   - completion: Called with the resolved `DeepLink` or an error.
    func handleURL(
        _ url: URL,
        completion: @escaping (Result<DeepLink, SlnkaError>) -> Void
    ) {
        guard let shortCode = extractShortCode(from: url) else {
            completion(.failure(.invalidURL(url.absoluteString)))
            return
        }

        logDebug("Resolving short code: \(shortCode)")

        // Extract src parameter from URL (e.g. src=qr for QR code scans)
        let srcParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "src" })?.value

        Task {
            do {
                guard let response = try await transport.resolveByShortCode(shortCode) else {
                    logDebug("No deep link match found for short code: \(shortCode)")
                    completion(.failure(.deepLinkNotFound))
                    return
                }
                let deepLink = DeepLink.from(response: response, shortCode: shortCode)
                logDebug("Resolved deep link: screen=\(deepLink.screen ?? "nil")")
                completion(.success(deepLink))
            } catch let error as SlnkaError {
                logDebug("Failed to resolve: \(error.description)")
                completion(.failure(error))
            } catch {
                logDebug("Unexpected error: \(error.localizedDescription)")
                completion(.failure(.networkError(underlying: error)))
            }
        }
    }

    /// Async variant of `handleUniversalLink`.
    func handleUniversalLink(_ userActivity: NSUserActivity) async throws -> DeepLink {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            throw SlnkaError.sdkError("Not a browsing web activity")
        }

        return try await handleURL(url)
    }

    /// Async variant of `handleURL`.
    func handleURL(_ url: URL) async throws -> DeepLink {
        guard let shortCode = extractShortCode(from: url) else {
            throw SlnkaError.invalidURL(url.absoluteString)
        }

        logDebug("Resolving short code: \(shortCode)")

        // Extract src parameter from URL (e.g. src=qr for QR code scans)
        let srcParam = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "src" })?.value

        guard let response = try await transport.resolveByShortCode(shortCode) else {
            throw SlnkaError.deepLinkNotFound
        }
        let deepLink = DeepLink.from(response: response, shortCode: shortCode)
        logDebug("Resolved deep link: screen=\(deepLink.screen ?? "nil")")
        return deepLink
    }

    // MARK: - Short Code Extraction

    /// Extracts the 7-character short code from a SLNK URL.
    ///
    /// Supports:
    /// - `https://slnk.ma/abc1234`
    /// - `https://api.slnk.ma/abc1234`
    /// - Custom domains: `https://go.company.com/abc1234`
    /// - With query parameters: `https://slnk.ma/abc1234?utm_source=twitter`
    private func extractShortCode(from url: URL) -> String? {
        let path = url.path

        // Remove leading slash and get the first path component
        let components = path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .components(separatedBy: "/")

        guard let firstComponent = components.first, !firstComponent.isEmpty else {
            return nil
        }

        // Validate short code format: 7 alphanumeric characters
        let shortCodePattern = "^[a-zA-Z0-9]{7}$"
        guard firstComponent.range(of: shortCodePattern, options: .regularExpression) != nil else {
            // Could also be a custom alias (3-50 alphanumeric + hyphens + underscores)
            let aliasPattern = "^[a-zA-Z0-9_-]{3,50}$"
            if firstComponent.range(of: aliasPattern, options: .regularExpression) != nil {
                return firstComponent
            }
            return nil
        }

        return firstComponent
    }

    // MARK: - Logging

    private func logDebug(_ message: String) {
        if debug {
            print("[SlnkaSDK:DeepLink] \(message)")
        }
    }
}
