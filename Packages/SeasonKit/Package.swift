// swift-tools-version: 6.0
import PackageDescription

/// Platform-independent simulation code for SeasonMyMac.
///
/// Nothing in here knows about AppKit or Metal, which keeps the physics
/// fast to unit test (`swift test`) and easy to reason about.
let package = Package(
    name: "SeasonKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SeasonKit", targets: ["SeasonKit"])
    ],
    targets: [
        .target(name: "SeasonKit"),
        .testTarget(name: "SeasonKitTests", dependencies: ["SeasonKit"]),
    ]
)
