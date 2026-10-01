// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dryp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "dryp", targets: ["dryp"]),
        .executable(name: "DrypApp", targets: ["DrypApp"]),
        .executable(name: "dryp-icon", targets: ["dryp-icon"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "DrypCore"),
        .target(
            name: "DrypCLI",
            dependencies: ["DrypCore", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .executableTarget(name: "dryp", dependencies: ["DrypCLI"]),
        .target(name: "DrypIcon"),
        .executableTarget(name: "dryp-icon", dependencies: ["DrypIcon"]),
        .executableTarget(name: "DrypApp", dependencies: ["DrypCore", "DrypIcon"]),
        .testTarget(name: "DrypCoreTests", dependencies: ["DrypCore"]),
        .testTarget(name: "DrypCLITests", dependencies: ["DrypCLI", "DrypCore"]),
        .testTarget(name: "DrypIconTests", dependencies: ["DrypIcon"]),
    ],
    swiftLanguageModes: [.v5]
)
