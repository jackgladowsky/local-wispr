// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LocalWispr",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LocalWispr", targets: ["LocalWispr"]),
        .executable(name: "LocalWisprPasteHelper", targets: ["LocalWisprPasteHelper"])
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
        .executableTarget(
            name: "LocalWisprRewriteBench",
            dependencies: ["LocalWisprCore"]
        ),
        .executableTarget(
            name: "LocalWisprPasteHelper",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(
            name: "LocalWisprCoreTests",
            dependencies: ["LocalWisprCore"]
        )
    ]
)
