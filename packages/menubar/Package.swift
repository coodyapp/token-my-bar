// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenMyBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "TokenMyBarCore", targets: ["TokenMyBarCore"]),
        .executable(name: "TokenMyBar", targets: ["TokenMyBar"]),
        .executable(name: "token-my-bar", targets: ["TokenMyBarCLI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite3"),
        .target(
            name: "TokenMyBarCore",
            dependencies: ["CSQLite3"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "TokenMyBar",
            dependencies: ["TokenMyBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "TokenMyBarCLI",
            dependencies: [
                "TokenMyBarCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .testTarget(
            name: "TokenMyBarCoreTests",
            dependencies: ["TokenMyBarCore"]),
    ])
