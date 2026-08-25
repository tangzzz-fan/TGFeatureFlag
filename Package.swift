// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TGFeatureFlag",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .tvOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(
            name: "TGFeatureFlag",
            targets: ["TGFeatureFlag"]
        ),
    ],
    targets: [
        .target(
            name: "TGFeatureFlag"
        ),
        .testTarget(
            name: "TGFeatureFlagTests",
            dependencies: ["TGFeatureFlag"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
