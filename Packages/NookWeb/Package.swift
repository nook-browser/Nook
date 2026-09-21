// Licensed under GPL-3.0. See LICENSE.
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookWeb",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NookWeb", targets: ["NookWeb"]),
    ],
    dependencies: [
        .package(path: "../NookTabsCore"),
        .package(path: "../NookSettings"),
        .package(path: "../NookBlocker"),
        .package(path: "../NookTweaks"),
        .package(url: "https://github.com/will-lumley/FaviconFinder.git", from: "5.1.5"),
    ],
    targets: [
        .target(name: "MuteableWKWebView", path: "Sources/MuteableWKWebView", publicHeadersPath: "include"),
        .target(
            name: "NookWeb",
            dependencies: [
                // Page muting reaches a private WebKit call through NSTask and nm; macOS only.
                .target(name: "MuteableWKWebView", condition: .when(platforms: [.macOS])),
                .product(name: "NookTabsCore", package: "NookTabsCore"),
                .product(name: "NookSettings", package: "NookSettings"),
                .product(name: "NookBlocker", package: "NookBlocker"),
                .product(name: "NookTweaks", package: "NookTweaks"),
                .product(name: "FaviconFinder", package: "FaviconFinder"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
