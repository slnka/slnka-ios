# SlnkaSDK for iOS

Swift SDK for integrating SLNK (Moroccan sovereign URL shortening & deep linking)
into iOS apps.

- **Platform**: iOS 15+
- **Language**: Swift 5.9+
- **Distribution**: Swift Package Manager (binary XCFramework)
- **License**: Proprietary -- see LICENSE

## Installation

### Via Xcode

1. File > Add Package Dependencies
2. Paste: `https://github.com/slnka/slnka-ios.git`
3. Dependency Rule: Up to Next Major Version, `1.0.0-beta.4`
4. Add the `SlnkaSDK` product to your target

### Via Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/slnka/slnka-ios.git", from: "1.0.0-beta.4")
]
```

## Quick start

```swift
import SwiftUI
import SlnkaSDK

@main
struct MyApp: App {
    init() {
        SlnkaSDK.configure(
            apiKey: "lsk_test_...",
            config: SlnkaConfig(
                serverUrl: "https://api.recette.slnk.ma",
                debug: true
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { SlnkaSDK.handleURL($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) {
                    SlnkaSDK.handleUserActivity($0)
                }
                .task {
                    SlnkaSDK.onDeepLink { deepLink in
                        // route to the right screen
                    }
                }
        }
    }
}
```

Full integration guide: see `docs/guides/04-ios-sdk-integration-swiftui.md` in the
SLNK documentation bundle.

## Versions

| Version | Date | Notes |
|---------|------|-------|
| 1.0.0-beta.4 | TBD | Initial binary release of SlnkaSDK (new API) |
