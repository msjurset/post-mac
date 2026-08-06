// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Post",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Post", targets: ["Post"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Post",
            dependencies: [],
            path: "Sources/Post",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "PostTests",
            dependencies: ["Post"],
            path: "Tests/PostTests"
        ),
    ]
)
