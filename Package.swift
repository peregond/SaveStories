// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DimaSave",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "DimaSave",
            targets: ["DimaSave"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "DimaSave",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .copy("Resources/bootstrap_worker.sh"),
                .copy("Resources/update_config.json"),
                .copy("Resources/worker"),
            ]
        ),
    ]
)
