import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Handles deferred deep link resolution for the SLNK platform.
///
/// A deferred deep link is one where a user clicks a SLNK link in a browser,
/// is redirected to the App Store to install the app, and upon first launch,
/// the SDK resolves the original deep link parameters.
///
/// Resolution strategy:
/// 1. Check if already resolved (idempotent - only resolves once per install)
/// 2. Check clipboard for SLNK URLs (iOS 16+ with UIPasteboard.DetectionPattern)
/// 3. Fallback to fingerprint-based matching via POST /api/v1/deferred/match
final class DeferredDeepLinkResolver {

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

    /// Checks for a deferred deep link. Should be called at first app launch.
    ///
    /// - Parameter completion: Called with the resolved `DeepLink` or `nil` if no match.
    func checkDeferredDeepLink(completion: @escaping (DeepLink?) -> Void) {
        // Only attempt once per install
        guard !storage.isDeferredResolved() else {
            logDebug("Deferred deep link already resolved, skipping")
            completion(nil)
            return
        }

        logDebug("Checking for deferred deep link...")

        Task {
            let result = await resolve()
            if result != nil {
                storage.markDeferredResolved()
            }
            completion(result)
        }
    }

    /// Async variant of `checkDeferredDeepLink`.
    func checkDeferredDeepLink() async -> DeepLink? {
        guard !storage.isDeferredResolved() else {
            logDebug("Deferred deep link already resolved, skipping")
            return nil
        }

        logDebug("Checking for deferred deep link...")

        let result = await resolve()
        if result != nil {
            storage.markDeferredResolved()
        }
        return result
    }

    // MARK: - Resolution

    private func resolve() async -> DeepLink? {
        // Strategy 1: Clipboard-based resolution (iOS 16+)
        if let clipboardLink = await checkClipboard() {
            logDebug("Found SLNK URL on clipboard")
            return clipboardLink
        }

        // Strategy 2: Fingerprint-based matching
        return await matchByFingerprint()
    }

    // MARK: - Clipboard Strategy

    /// Checks the clipboard for SLNK URLs using privacy-preserving detection.
    private func checkClipboard() async -> DeepLink? {
        #if canImport(UIKit)
        if #available(iOS 16.0, *) {
            return await checkClipboardiOS16()
        }
        #endif
        // On iOS 15, clipboard access shows a notification toast.
        // We skip clipboard strategy to avoid confusing the user.
        return nil
    }

    #if canImport(UIKit)
    @available(iOS 16.0, *)
    private func checkClipboardiOS16() async -> DeepLink? {
        let pasteboard = UIPasteboard.general

        // Use detection pattern to check if clipboard has a URL
        // without actually reading it (no toast shown)
        do {
            // Check if clipboard contains a URL without reading it
            guard pasteboard.hasURLs else {
                logDebug("No URL found on clipboard")
                return nil
            }

            // Read the actual URL (shows paste notification banner on iOS 16+)
            guard let clipboardString = pasteboard.string,
                  let url = URL(string: clipboardString),
                  isSlnkURL(url) else {
                return nil
            }

            logDebug("Found SLNK URL on clipboard: \(url.absoluteString)")

            // Extract short code and resolve via clipboard token method
            guard let shortCode = extractShortCode(from: url) else {
                return nil
            }

            let resolveRequest = DeepLinkResolveRequestDTO(
                method: "CLIPBOARD_TOKEN",
                token: shortCode,
                referrerData: nil,
                deviceModel: nil,
                osVersion: nil,
                screenSize: nil,
                locale: nil,
                timezone: nil,
                carrier: nil,
                userAgentHash: nil,
                fingerprintHash: nil,
                src: nil
            )
            guard let response = try await transport.resolveDeepLink(request: resolveRequest) else {
                logDebug("No deep link match found for clipboard short code: \(shortCode)")
                return nil
            }
            var deepLink = DeepLink.from(response: response, shortCode: shortCode)
            // Override to mark as deferred
            deepLink = DeepLink(
                screen: deepLink.screen,
                params: deepLink.params,
                utmSource: deepLink.utmSource,
                utmMedium: deepLink.utmMedium,
                utmCampaign: deepLink.utmCampaign,
                linkId: deepLink.linkId,
                shortCode: deepLink.shortCode,
                originalUrl: deepLink.originalUrl,
                confidence: response.confidence ?? 0.95,
                isDeferred: true
            )

            // Clear the clipboard so we do not resolve again
            pasteboard.string = ""

            return deepLink
        } catch {
            logDebug("Clipboard check failed: \(error.localizedDescription)")
            return nil
        }
    }
    #endif

    // MARK: - Fingerprint Strategy

    private func matchByFingerprint() async -> DeepLink? {
        logDebug("Attempting fingerprint-based deferred match")

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        let request = DeferredMatchRequestDTO(
            fingerprint: fingerprint.toDTO(),
            deviceId: getVendorId(),
            appVersion: appVersion,
            sdkVersion: SlnkaConfig.sdkVersion
        )

        do {
            guard let response = try await transport.matchDeferred(request: request) else {
                logDebug("No deferred match found")
                return nil
            }

            guard response.matched else {
                logDebug("Server returned no match")
                return nil
            }

            let deepLink = DeepLink.from(deferred: response)
            logDebug("Deferred match found: screen=\(deepLink.screen ?? "nil"), confidence=\(deepLink.confidence)")
            return deepLink
        } catch {
            logDebug("Deferred match failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    /// Checks if a URL belongs to the SLNK domain or the configured server URL.
    private func isSlnkURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let serverHost = URL(string: config.serverUrl)?.host?.lowercased() ?? "slnk.ma"

        let slnkDomains = ["slnk.ma", serverHost]
        return slnkDomains.contains(where: { host.hasSuffix($0) })
    }

    /// Extracts the short code from a SLNK URL.
    private func extractShortCode(from url: URL) -> String? {
        let path = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .components(separatedBy: "/")

        guard let first = path.first, !first.isEmpty else { return nil }

        let pattern = "^[a-zA-Z0-9_-]{3,50}$"
        guard first.range(of: pattern, options: .regularExpression) != nil else { return nil }

        return first
    }

    /// Returns the vendor identifier (IDFV) which is per-vendor and not PII.
    private func getVendorId() -> String? {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }

    private func logDebug(_ message: String) {
        if debug {
            print("[SlnkaSDK:DeferredDeepLink] \(message)")
        }
    }
}
