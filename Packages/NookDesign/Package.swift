// Licensed under GPL-3.0. See LICENSE.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookDesign",
    platforms: [.macOS("15.5"), .iOS("26.0")],
    products: [
        .library(name: "NookDesign", targets: ["NookDesign"]),
    ],
    targets: [
        .target(name: "NookDesign", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
