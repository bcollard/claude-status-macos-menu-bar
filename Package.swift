// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeStatus",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeStatus",
            path: "Sources/ClaudeStatus"
        )
    ]
)
