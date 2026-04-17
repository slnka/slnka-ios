// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SlnkaSDK",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "SlnkaSDK", targets: ["SlnkaSDK"]),
    ],
    targets: [
        .target(name: "SlnkaSDK", dependencies: []),
    ]
)
