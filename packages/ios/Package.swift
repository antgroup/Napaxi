// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path

let package = Package(
    name: "Napaxi",
    platforms: [
        .iOS(.v16),
        .macOS(.v12),
    ],
    products: [
        .library(name: "Napaxi", targets: ["Napaxi"]),
    ],
    targets: [
        .binaryTarget(
            name: "NapaxiApiBridge",
            path: "Frameworks/napaxi_api_bridge.xcframework"
        ),
        .target(
            name: "Napaxi",
            dependencies: [
                .target(name: "NapaxiApiBridge", condition: .when(platforms: [.iOS])),
                .target(name: "NapaxiIsh", condition: .when(platforms: [.iOS])),
            ],
            resources: [
                .copy("Resources"),
            ]
        ),
        .target(
            name: "NapaxiIsh",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("../../Vendor/iSHCore/include"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-L", "\(packageRoot)/Vendor/iSHCore/lib",
                    "-lish",
                    "-lish_emu",
                    "-lfakefs",
                    "-lfakefsify",
                    "-larchive",
                    "-lz",
                    "-lbz2",
                    "-lsqlite3",
                    "-liconv",
                ], .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(name: "NapaxiTests", dependencies: ["Napaxi"]),
    ]
)
