// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CastKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CastCore", targets: ["CastCore"]),
        .library(name: "CastNet", targets: ["CastNet"]),
    ],
    targets: [
        .target(name: "CastCore"),
        .target(name: "CastNet", dependencies: ["CastCore"]),
        .testTarget(name: "CastCoreTests", dependencies: ["CastCore"]),
        .testTarget(name: "CastNetTests", dependencies: ["CastNet", "CastCore"]),
    ]
)
