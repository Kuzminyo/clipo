// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Clipo",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Clipo",
            path: "Sources/Clipo",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
