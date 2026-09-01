// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BallastCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BallastCore", targets: ["BallastCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "BallastCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            resources: [
                .copy("AI/Resources")
            ]
        ),
        .testTarget(
            name: "BallastCoreTests",
            dependencies: ["BallastCore"]
        ),
    ]
)
