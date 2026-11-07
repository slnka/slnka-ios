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
            url: "https://github.com/slnka/slnka-ios/releases/download/1.1.0-beta.2/SlnkaSDK.xcframework.zip",
            checksum: "414ccf33d2d78f0148e146312f87765de1197ad1784f254a7f7bdae236a1156c"
        )
    ]
)
