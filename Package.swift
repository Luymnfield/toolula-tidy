// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ToolulaCleaner",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ToolulaCleaner", path: "Sources/ToolulaCleaner"),
        .testTarget(name: "ToolulaCleanerTests", dependencies: ["ToolulaCleaner"], path: "Tests/ToolulaCleanerTests")
    ]
)
