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
    targets: [
        .executableTarget(
            name: "DimaSave",
            resources: [
                .copy("Resources/bootstrap_worker.sh"),
                .copy("Resources/worker"),
            ]
        ),
    ]
)
