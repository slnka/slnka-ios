import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Collects device fingerprint data WITHOUT any PII.
/// Used for deferred deep link matching and attribution.
///
/// CNDP Compliance (Law 09-08):
///   - No IDFA collection
///   - No raw IP collection (IP is only ever seen server-side)
///   - Only non-identifying device characteristics
struct DeviceFingerprint {

    let deviceModel: String
    let osVersion: String
    let screenWidth: Int
    let screenHeight: Int
    let locale: String
    let timezone: String
    let language: String
    let userAgent: String

    /// Collects the current device fingerprint.
    static func collect() -> DeviceFingerprint {
        let model = Self.getDeviceModel()
        let osVersion = Self.getOSVersion()
        let screenSize = Self.getScreenSize()
        let locale = Locale.current.identifier
        let timezone = TimeZone.current.identifier
        let language: String
        if #available(macOS 13, iOS 16, *) {
            language = Locale.current.language.languageCode?.identifier ?? "unknown"
        } else {
            language = Locale.current.languageCode ?? "unknown"
        }
        let userAgent = Self.buildUserAgent(model: model, osVersion: osVersion)

        return DeviceFingerprint(
            deviceModel: model,
            osVersion: osVersion,
            screenWidth: screenSize.width,
            screenHeight: screenSize.height,
            locale: locale,
            timezone: timezone,
            language: language,
            userAgent: userAgent
        )
    }

    /// Converts to the DTO used in API requests.
    func toDTO() -> FingerprintDTO {
        return FingerprintDTO(
            userAgent: userAgent,
            screenWidth: screenWidth,
            screenHeight: screenHeight,
            timezone: timezone,
            language: language,
            platform: "ios"
        )
    }

    /// Returns a dictionary representation for event context.
    func toContext() -> [String: Any] {
        return [
            "device": [
                "model": deviceModel,
                "os": "iOS",
                "osVersion": osVersion
            ],
            "screen": [
                "width": screenWidth,
                "height": screenHeight
            ],
            "locale": locale,
            "timezone": timezone,
            "library": [
                "name": "SlnkaSDK-iOS",
                "version": SlnkaConfig.sdkVersion
            ]
        ]
    }

    // MARK: - Private

    /// Gets the hardware model string (e.g., "iPhone15,2").
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { ptr in
                String(validatingUTF8: ptr) ?? "unknown"
            }
        }
        return machine
    }

    /// Gets the current iOS version string.
    private static func getOSVersion() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #endif
    }

    /// Gets the main screen size in points.
    private static func getScreenSize() -> (width: Int, height: Int) {
        #if canImport(UIKit)
        let bounds = UIScreen.main.bounds
        let scale = UIScreen.main.scale
        return (
            width: Int(bounds.width * scale),
            height: Int(bounds.height * scale)
        )
        #else
        return (width: 0, height: 0)
        #endif
    }

    /// Builds a user agent string similar to what Safari sends.
    private static func buildUserAgent(model: String, osVersion: String) -> String {
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App"
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "\(bundleName)/\(appVersion) (iOS \(osVersion); \(model)) SlnkaSDK/\(SlnkaConfig.sdkVersion)"
    }
}
