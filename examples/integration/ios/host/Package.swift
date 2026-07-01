// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NapaxiIOSHostIntegration",
    platforms: [
        .iOS(.v16),
        .macOS(.v12),
    ],
    products: [
        .library(name: "NapaxiIOSIntegrationSmoke", targets: ["NapaxiIOSIntegrationSmoke"]),
    ],
    dependencies: [
        .package(name: "Napaxi", path: "../../../../packages/ios"),
    ],
    targets: [
        .target(
            name: "NapaxiIOSIntegrationSmoke",
            dependencies: [
                .product(name: "Napaxi", package: "Napaxi"),
            ]
        ),
        .testTarget(
            name: "NapaxiIOSIntegrationSmokeTests",
            dependencies: ["NapaxiIOSIntegrationSmoke"]
        ),
    ]
)
