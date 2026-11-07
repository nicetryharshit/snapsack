// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapSack",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SnapSack",
            path: "Sources/SnapSack"
        ),
        .testTarget(
            name: "SnapSackTests",
            dependencies: ["SnapSack"],
            path: "Tests/SnapSackTests"
        ),
    ]
)
