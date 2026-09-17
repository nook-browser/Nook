// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookBlocker",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [
        .library(name: "NookBlocker", targets: ["NookBlocker"]),
    ],
    dependencies: [
        .package(path: "../NookSettings"),
    ],
    targets: [
        .binaryTarget(
            name: "NookAdblockFFI",
            path: "../../Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework"
        ),
        .target(
            name: "NookBlocker",
            dependencies: [
                "NookAdblockFFI",
                .product(name: "NookSettings", package: "NookSettings"),
            ],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
