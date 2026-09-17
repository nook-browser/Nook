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
        .package(path: "../NookDesign"),
        .package(path: "../NookBlocker"),
        .package(path: "../NookTweaks"),
        .package(url: "https://github.com/will-lumley/FaviconFinder.git", from: "5.1.5"),
    ],
    targets: [
        .target(name: "MuteableWKWebView", path: "Sources/MuteableWKWebView", publicHeadersPath: "include"),
        .target(
            name: "NookWeb",
            dependencies: [
                "MuteableWKWebView",
                .product(name: "NookTabsCore", package: "NookTabsCore"),
                .product(name: "NookSettings", package: "NookSettings"),
                .product(name: "NookDesign", package: "NookDesign"),
                .product(name: "NookBlocker", package: "NookBlocker"),
                .product(name: "NookTweaks", package: "NookTweaks"),
                .product(name: "FaviconFinder", package: "FaviconFinder"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
