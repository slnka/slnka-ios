// swift-tools-version: 5.9
// Manifest for the PUBLIC distribution repo: github.com/slnka/slnka-ios
// The actual SlnkaSDK source lives privately in SLNK-MA/sdk/ios/SlnkaSDK.
// This manifest references a pre-built XCFramework attached to a GitHub Release.
//
// Before each tag:
//   1. Run  sdk/ios/scripts/build-xcframework.sh <VERSION>
//   2. Update the url + checksum below with the values it prints
//   3. Create the GitHub Release on slnka/slnka-ios, attach SlnkaSDK.xcframework.zip
//   4. Tag the commit on slnka/slnka-ios

import PackageDescription

let package = Package(
    name: "SlnkaSDK",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SlnkaSDK",
            targets: ["SlnkaSDK"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "SlnkaSDK",
            url: "https://github.com/slnka/slnka-ios/releases/download/1.0.0-beta.4/SlnkaSDK.xcframework.zip",
            checksum: "e2fa78304b5117599d8f5755c5f6e92bbc6a9a46ee607a409c0510fb3d0c06c4"
        )
    ]
)
