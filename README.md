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
3. Dependency Rule: Exact Version, `1.0.0-beta.13`
4. Add the `SlnkaSDK` product to your target

### Via Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/slnka/slnka-ios.git", exact: "1.0.0-beta.13")
]
```

## Quick start

```swift
import SwiftUI
import SlnkaSDK

@main
struct MyApp: App {
    init() {
        Slnka.configure(
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
                .onOpenURL { Slnka.handleURL($0) }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) {
                    Slnka.handleUserActivity($0)
                }
                .task {
                    Slnka.onDeepLink { deepLink in
                        // route to the right screen
                    }
                }
        }
    }
}
```

Full integration guide: SLNK developer documentation (iOS guide).

## Versions

See the [GitHub Releases](https://github.com/slnka/slnka-ios/releases). Pin an exact
version during the beta. `1.0.0-beta.4` and `1.0.0-beta.11` must not be used: their
XCFramework has no module interface (`import SlnkaSDK` fails); use `1.0.0-beta.13` or later.
