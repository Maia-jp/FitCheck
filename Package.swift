// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FitCheck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FitCheck",
            targets: ["FitCheck"]
        ),
    ],
    targets: [
        .target(
            name: "FitCheck",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "FitCheckTests",
            dependencies: ["FitCheck"]
        ),
        .executableTarget(
            name: "CatalogGenerator",
            path: "Sources/CatalogGenerator"
        ),
    ]
)
