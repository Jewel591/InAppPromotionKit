// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "InAppPromotionKit",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "InAppPromotionKit", targets: ["InAppPromotionKit"]),
    ],
    targets: [
        .target(
            name: "InAppPromotionKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "InAppPromotionKitTests",
            dependencies: ["InAppPromotionKit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
