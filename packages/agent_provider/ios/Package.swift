// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AgentProvider",
    platforms: [
        .iOS(.v13),
        .macOS(.v12),
    ],
    products: [
        .library(name: "AgentProvider", targets: ["AgentProvider"]),
    ],
    targets: [
        .target(name: "AgentProvider"),
        .testTarget(name: "AgentProviderTests", dependencies: ["AgentProvider"]),
    ]
)
