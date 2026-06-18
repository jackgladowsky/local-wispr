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
    dependencies: [
        .package(url: "https://github.com/moonshine-ai/moonshine-swift/", exact: "0.0.62")
    ],
    targets: [
        .target(
            name: "LocalWisprCore",
            dependencies: [
                .product(name: "MoonshineVoice", package: "moonshine-swift")
            ],
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
