// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MetriBarKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "MetriBarKit", targets: ["MetriBarKit"])
    ],
    targets: [
        .target(
            name: "MetriBarKit",
            resources: [.copy("Resources/Demo")]
        ),
        .testTarget(
            name: "MetriBarKitTests",
            dependencies: ["MetriBarKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
