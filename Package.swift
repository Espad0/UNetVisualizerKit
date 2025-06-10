// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UNetVisualizerKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "UNetVisualizerKit",
            targets: ["UNetVisualizerKit"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-collections", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "UNetVisualizerKit",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Collections", package: "swift-collections")
            ],
            path: "Sources/UNetVisualizerKit",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "UNetVisualizerKitTests",
            dependencies: ["UNetVisualizerKit"],
            path: "Tests/UNetVisualizerKitTests",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PerformanceTests",
            dependencies: ["UNetVisualizerKit"],
            path: "Tests/PerformanceTests"
        )
    ]
)