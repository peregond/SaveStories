// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SaveStories",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "SaveStories",
            targets: ["SaveStories"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "SaveStories",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .copy("Resources/bootstrap_worker.sh"),
                .copy("Resources/update_config.json"),
                .copy("Resources/worker"),
            ]
        ),
        .testTarget(
            name: "SaveStoriesTests",
            dependencies: [
                "SaveStories",
            ]
        ),
    ]
)
