// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "apple-llm",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "apple-llm",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/apple-llm"
        ),
    ],
    swiftLanguageModes: [.v6]
)
