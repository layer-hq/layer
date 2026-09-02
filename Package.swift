// swift-tools-version: 6.0

// Layer is released under the MIT License. See LICENSE for the full text and
// THIRD-PARTY-NOTICES.md for the licenses of the dependencies declared below.
// (SwiftPM's manifest format has no license field, so this comment stands in as
// the manifest-level record.)

import PackageDescription

let package = Package(
    name: "Layer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Layer", targets: ["Layer"])
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/JohnSundell/Splash", from: "0.16.0"),
        .package(url: "https://github.com/stasel/WebRTC.git", from: "152.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Layer",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Splash", package: "Splash"),
                .product(name: "WebRTC", package: "WebRTC")
            ],
            path: "Sources/Layer",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LayerTests",
            dependencies: ["Layer"],
            path: "Tests/LayerTests"
        )
    ]
)
