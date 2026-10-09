// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "MontaseStudio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MontaseStudio",
            path: "Sources/MontaseStudio"
        ),
        .testTarget(
            name: "MontaseStudioTests",
            dependencies: ["MontaseStudio"],
            path: "Tests/MontaseStudioTests"
        ),
    ]
)
