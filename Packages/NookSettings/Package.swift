// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookSettings",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NookSettings", targets: ["NookSettings"]),
    ],
    targets: [
        .target(name: "NookSettings", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
