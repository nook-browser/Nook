// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookTabsCore",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NookTabsCore", targets: ["NookTabsCore"]),
    ],
    targets: [
        .target(name: "NookTabsCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "NookTabsCoreTests", dependencies: ["NookTabsCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
