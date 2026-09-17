// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookTweaks",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NookTweaks", targets: ["NookTweaks"]),
    ],
    dependencies: [
        .package(path: "../NookSettings"),
        .package(path: "../NookBlocker"),
    ],
    targets: [
        .target(
            name: "NookTweaks",
            dependencies: [
                .product(name: "NookSettings", package: "NookSettings"),
                .product(name: "NookBlocker", package: "NookBlocker"),
            ],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
