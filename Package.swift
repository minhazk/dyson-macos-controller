// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "dyson-macos-controller",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DysonKit", targets: ["DysonKit"]),
        .executable(name: "DysonMenuBar", targets: ["DysonMenuBar"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "DysonKit",
            dependencies: [],
            path: "Sources/DysonKit"
        ),
        .executableTarget(
            name: "DysonMenuBar",
            dependencies: ["DysonKit"],
            path: "Sources/DysonMenuBar"
        ),
        .testTarget(
            name: "DysonKitTests",
            dependencies: ["DysonKit"],
            path: "Tests/DysonKitTests"
        )
    ]
)
