// swift-tools-version:6.2
// `.macOS(.v26)` requires PackageDescription 6.2 — it is unavailable at 6.1.

import PackageDescription

let package = Package(
    name: "Pippin",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "PippinApp", targets: ["PippinApp"]),
        .executable(name: "pippin-shim", targets: ["pippin-shim"]),
    ],
    dependencies: [
        // Pinned exactly: the SDK is pre-1.0 and this task mapped 0.12.1's
        // transport contract in detail (see the skeleton task's
        // research/swift-sdk-surface.md). A minor bump can move that contract,
        // so upgrades are a deliberate act, not a resolution side effect.
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk", exact: "0.12.1"),
        // The MCP SDK ships no HTTP listener; we supply one. Parent decision O4.
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.101.3"),
    ],
    targets: [
        // Transport- and UI-independent core. Imports nothing from the SDK, NIO,
        // SwiftUI, or AppKit — enforced by the dependency graph for the packages
        // and by ImportBoundaryTests for the system frameworks.
        .target(name: "PippinCore"),

        .target(name: "PippinModules", dependencies: ["PippinCore"]),

        .target(
            name: "PippinServer",
            dependencies: [
                "PippinCore",
                "PippinModules",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOHTTP1", package: "swift-nio"),
            ]
        ),

        .executableTarget(name: "PippinApp", dependencies: ["PippinServer"]),

        .target(
            name: "PippinShim",
            dependencies: [.product(name: "MCP", package: "swift-sdk")]
        ),

        .executableTarget(name: "pippin-shim", dependencies: ["PippinShim"]),

        .testTarget(name: "PippinCoreTests", dependencies: ["PippinCore"]),
        .testTarget(name: "PippinServerTests", dependencies: ["PippinServer"]),
        .testTarget(
            name: "PippinShimTests",
            dependencies: ["PippinShim", "PippinServer", "PippinCore", .product(name: "MCP", package: "swift-sdk")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
