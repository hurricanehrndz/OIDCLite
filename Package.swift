// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OIDCLite",
    platforms: [
        .macOS(.v15), .iOS(.v14)
    ],
    products: [
        .library(
            name: "OIDCLite",
            targets: ["OIDCLite"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "OIDCLite",
            dependencies: []
        ),
        .testTarget(
            name: "OIDCLiteTests",
            dependencies: ["OIDCLite"]
        )
    ],
    swiftLanguageModes: [.v6]
)
