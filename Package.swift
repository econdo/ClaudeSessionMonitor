// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ClaudeSessionMonitor",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeSessionMonitor",
            path: "Sources/ClaudeSessionMonitor",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
