import ProjectDescription

let project = Project(
    name: "OIDCLite",
    targets: [
        .target(
            name: "OIDCLite",
            destinations: [.mac, .iPhone, .iPad],
            product: .framework,
            bundleId: "ca.hrndz.OIDCLite",
            deploymentTargets: .multiplatform(iOS: "14.0", macOS: "11.0"),
            sources: ["Sources/OIDCLite/**"]
        ),
        // ponytail: mac-only tests — `tuist test` rejects multi-platform test targets;
        // add an iOS test target if simulator coverage ever matters.
        .target(
            name: "OIDCLiteTests",
            destinations: [.mac],
            product: .unitTests,
            bundleId: "ca.hrndz.OIDCLiteTests",
            deploymentTargets: .macOS("11.0"),
            sources: ["Tests/OIDCLiteTests/**"],
            dependencies: [.target(name: "OIDCLite")]
        )
    ]
)
