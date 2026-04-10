// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SaveMe",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "SaveMe",
            targets: ["SaveMe"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SaveMe",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/SaveStories",
            resources: [
                .copy("Resources/bootstrap_worker.sh"),
                .copy("Resources/update_config.json"),
                .copy("Resources/worker"),
            ]
        ),
        .testTarget(
            name: "SaveStoriesTests",
            dependencies: [
                "SaveMe",
            ],
            path: "Tests/SaveStoriesTests"
        ),
    ]
)
