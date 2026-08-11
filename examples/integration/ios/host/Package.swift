// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NapaxiIOSHostIntegration",
    platforms: [
        .iOS(.v16),
        .macOS(.v12),
    ],
    products: [
        .library(name: "NapaxiIOSIntegrationHost", targets: ["NapaxiIOSIntegrationHost"]),
    ],
    dependencies: [
        .package(name: "Napaxi", path: "../../../../packages/ios"),
    ],
    targets: [
        .target(
            name: "NapaxiIOSIntegrationHost",
            dependencies: [
                .product(name: "Napaxi", package: "Napaxi"),
            ]
        ),
        .testTarget(
            name: "NapaxiIOSIntegrationHostTests",
            dependencies: ["NapaxiIOSIntegrationHost"]
        ),
    ]
)
