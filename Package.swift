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
            url: "https://github.com/slnka/slnka-ios/releases/download/1.0.0-beta.11/SlnkaSDK.xcframework.zip",
            checksum: "c0aa04cacd1ef82c47e5f74c5fcdacc72bda67d20e5bf50c7e6588712948d3e8"
        )
    ]
)
