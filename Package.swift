// swift-tools-version: 5.9
// Manifest for the PUBLIC distribution repo: github.com/slnka/slnka-ios
// The SlnkaSDK source lives privately in SLNK-MA/sdk/ios/SlnkaSDK and is never
// published. This manifest references the pre-built XCFramework attached to
// the GitHub Release of the same version.
//
// Template: sdk/ios/scripts/release-spm.sh fills in the version and the checksum.

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
            url: "https://github.com/slnka/slnka-ios/releases/download/1.0.0-beta.13/SlnkaSDK.xcframework.zip",
            checksum: "f626cf5d15f0207ac8365ada676cfa7d27cd1a43c718733a0565060f84f97e5c"
        )
    ]
)
