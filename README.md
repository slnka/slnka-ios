# SLNK iOS SDK

Native iOS SDK for the **SLNK** sovereign Moroccan URL shortening platform. Provides deep linking, deferred deep links, attribution tracking, and event analytics.

**Requirements**: iOS 15+ | Swift 5.9+ | No external dependencies

## Installation

### Swift Package Manager

Add the package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/slnka/slnka-ios.git", from: "1.0.0-beta.5")
]
```

Or in Xcode: **File > Add Package Dependencies** and enter `https://github.com/slnka/slnka-ios`.

> **Note**: This is a private repository. You may need to authenticate via Xcode > Settings > Accounts > GitHub, or add credentials to `~/.netrc`:
> ```
> machine github.com
> login YOUR_GITHUB_USERNAME
> password YOUR_GITHUB_PAT
> ```

## Quick Start

### 1. Configure the SDK

Call `configure` in your `AppDelegate` or SwiftUI `App` init:

```swift
import SlnkaSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        SlnkaSDK.configure(
            apiKey: "lsk_live_your_api_key_here",
            config: SlnkaConfig(
                serverUrl: "https://your-instance.slnk.ma",  // Required
                debug: true // Set false in production
            )
        )

        // Check for deferred deep links (first launch after install)
        SlnkaSDK.shared.checkDeferredDeepLink { deepLink in
            if let deepLink = deepLink {
                print("Deferred deep link: \(deepLink.screen ?? "none")")
                // Navigate to the deep link destination
            }
        }

        return true
    }
}
```

### 2. Handle Universal Links

In your `SceneDelegate`:

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    SlnkaSDK.shared.handleUniversalLink(userActivity) { result in
        switch result {
        case .success(let deepLink):
            print("Deep link screen: \(deepLink.screen ?? "none")")
            print("UTM source: \(deepLink.utmSource ?? "none")")
            // Navigate to the appropriate screen
            self.navigate(to: deepLink)
        case .failure(let error):
            print("Deep link error: \(error)")
        }
    }
}
```

Or with async/await:

```swift
func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    Task {
        do {
            let deepLink = try await SlnkaSDK.shared.handleUniversalLink(userActivity)
            await MainActor.run {
                navigate(to: deepLink)
            }
        } catch {
            print("Deep link error: \(error)")
        }
    }
}
```

### 3. Track Events

```swift
// Track a custom event
SlnkaSDK.shared.track(event: "product_viewed", properties: [
    "product_id": "prod_123",
    "category": "electronics",
    "price": 299.99
])

// Track a purchase
SlnkaSDK.shared.track(event: "purchase_completed", properties: [
    "order_id": "order_456",
    "amount": 599.99,
    "currency": "MAD"
])
```

### 4. Identify Users

```swift
// After login
SlnkaSDK.shared.identify(userId: "user_abc123", traits: [
    "name": "Ahmed",
    "email": "ahmed@example.com",
    "plan": "professional"
])

// On logout
SlnkaSDK.shared.reset()
```

## Deep Linking

### Universal Links Setup

1. Add your SLNK domain to your Associated Domains entitlement:
   ```
   applinks:slnk.ma
   applinks:your-custom-domain.com
   ```

2. The AASA file is **automatically generated and hosted by SLNK** on your project's subdomain (e.g., `https://yourproject.slnk.ma/.well-known/apple-app-site-association`). Register your app's Bundle ID and Team ID in the SLNK dashboard under **Settings > Deep Links > Platforms**.

3. Handle the Universal Link in SceneDelegate as shown above.

### Deferred Deep Links

Deferred deep links resolve the original link destination even when the user installs the app after clicking the link:

```swift
// In AppDelegate didFinishLaunchingWithOptions
SlnkaSDK.shared.checkDeferredDeepLink { deepLink in
    guard let deepLink = deepLink else { return }

    print("Screen: \(deepLink.screen ?? "none")")
    print("Confidence: \(deepLink.confidence)")
    print("Is deferred: \(deepLink.isDeferred)")
    print("Params: \(deepLink.params)")
}
```

Resolution strategies (in order):
1. **Clipboard** (iOS 16+): Checks for SLNK URLs using privacy-preserving detection patterns
2. **Fingerprint**: Matches device characteristics against stored click contexts

### DeepLink Properties

| Property | Type | Description |
|----------|------|-------------|
| `screen` | `String?` | Target screen/route |
| `params` | `[String: Any]` | Custom parameters |
| `utmSource` | `String?` | UTM source |
| `utmMedium` | `String?` | UTM medium |
| `utmCampaign` | `String?` | UTM campaign |
| `linkId` | `String?` | SLNK link ID |
| `shortCode` | `String?` | Short code |
| `confidence` | `Double` | Match confidence (0.0-1.0) |
| `isDeferred` | `Bool` | Whether resolved via deferred matching |

## Attribution

Attribution is handled automatically when deep links are resolved. The SDK sends device fingerprint data to the SLNK server for matching.

To disable attribution:

```swift
let config = SlnkaConfig(enableAttribution: false)
SlnkaSDK.configure(apiKey: "lsk_live_...", config: config)
```

## Event Queue & Offline Support

Events are buffered in memory and flushed automatically:
- Every 30 seconds (configurable via `flushIntervalMs`, default `30_000`)
- When the buffer reaches 10 events (configurable via `flushSize`)
- When the app goes to background or terminates

Failed events are persisted to `UserDefaults` and retried on next launch.

Manual flush:

```swift
SlnkaSDK.shared.flush()
```

## CNDP Compliance

The SDK is designed for compliance with CNDP Law 09-08 (Morocco's data protection regulation):

- **No IDFA collection**: The SDK never requests the Advertising Identifier
- **No raw IP storage**: IPs are only visible server-side and hashed with daily-rotating salt
- **Non-PII fingerprinting**: Only device model, OS version, screen size, locale, and timezone
- **User consent**: Events can be deferred until user consent is obtained
- **Data minimization**: Only essential data is collected

CNDP compliance is enabled by default:

```swift
let config = SlnkaConfig(cndpCompliant: true) // default
```

## Configuration Reference

| Parameter | Default | Description |
|-----------|---------|-------------|
| `serverUrl` | **Required** | API base URL (e.g., `https://api.slnk.ma`) |
| `enableDeepLinks` | `true` | Enable deep link handling |
| `enableAttribution` | `true` | Enable attribution tracking |
| `cndpCompliant` | `true` | CNDP compliance mode |
| `flushIntervalMs` | `30_000` | Milliseconds between auto-flushes (aligned with Android/Web/RN) |
| `flushSize` | `10` | Events triggering auto-flush |
| `maxQueueSize` | `1000` | Max persisted retry events |
| `maxRetries` | `3` | Retry attempts per batch |
| `debug` | `false` | Enable console logging |

## API Key Format

API keys follow the format: `lsk_{environment}_{key}`

- `lsk_live_*` - Production keys
- `lsk_test_*` - Test/development keys

## Thread Safety

The SDK is thread-safe. All public methods can be called from any thread. Completions are dispatched to the main thread.

## Architecture

```
SlnkaSDK (singleton)
  |-- SlnkaConfig            Configuration
  |-- Transport              HTTP client (URLSession)
  |-- SlnkaStorage            UserDefaults persistence
  |-- DeviceFingerprint      Non-PII device characteristics
  |-- EventTracker           track(), identify(), reset()
  |-- EventQueue             Offline queue + batch flush
  |-- DeepLinkHandler        Universal Links resolution
  |-- DeferredDeepLinkResolver  Post-install deep link matching
  |-- Attribution            Attribution touchpoint recording
```
