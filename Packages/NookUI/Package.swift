// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookUI",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NookUI", targets: ["NookUI"]),
    ],
    dependencies: [
        .package(path: "../NookBlocker"),
        .package(path: "../NookDesign"),
        .package(path: "../NookSettings"),
        .package(path: "../NookTabsCore"),
        .package(path: "../NookTweaks"),
        .package(path: "../NookWeb"),
    ],
    targets: [
        .target(
            name: "NookUI",
            dependencies: [
                .product(name: "NookBlocker", package: "NookBlocker"),
                .product(name: "NookDesign", package: "NookDesign"),
                .product(name: "NookSettings", package: "NookSettings"),
                .product(name: "NookTabsCore", package: "NookTabsCore"),
                .product(name: "NookTweaks", package: "NookTweaks"),
                .product(name: "NookWeb", package: "NookWeb"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
