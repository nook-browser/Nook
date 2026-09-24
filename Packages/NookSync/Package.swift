// Licensed under GPL-3.0. See LICENSE.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookSync",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NookSync", targets: ["NookSync"]),
    ],
    dependencies: [
        .package(path: "../NookTabsCore"),
    ],
    targets: [
        .target(
            name: "NookSync",
            dependencies: [.product(name: "NookTabsCore", package: "NookTabsCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "NookSyncTests", dependencies: ["NookSync"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
