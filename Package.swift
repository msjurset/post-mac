// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Post",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Post", targets: ["Post"])
    ],
    dependencies: [
        .package(url: "https://github.com/msjurset/swift-vim-engine.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Post",
            dependencies: [
                .product(name: "VimEngine", package: "swift-vim-engine"),
            ],
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
