// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NuoDesignSystem",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "NuoDesignSystem", targets: ["NuoDesignSystem"])
    ],
    targets: [
        .target(
            name: "NuoDesignSystem",
            path: "Sources/NuoDesignSystem"
        )
    ]
)
