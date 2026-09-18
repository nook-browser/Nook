// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookDesign",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NookDesign", targets: ["NookDesign"]),
    ],
    targets: [
        .target(name: "NookDesign", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
