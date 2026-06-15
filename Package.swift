// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalWispr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LocalWispr", targets: ["LocalWispr"])
    ],
    targets: [
        .target(
            name: "LocalWisprCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .executableTarget(
            name: "LocalWispr",
            dependencies: ["LocalWisprCore"]
        ),
        .testTarget(
            name: "LocalWisprCoreTests",
            dependencies: ["LocalWisprCore"]
        )
    ]
)
