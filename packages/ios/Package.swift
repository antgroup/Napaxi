// swift-tools-version: 5.9
import Foundation
import PackageDescription

let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let qemuLibDir = "\(packageRoot)/Vendor/IosQemu/Vendor/QEMU/lib/iphoneos"

let qemuLinkerFlags = [
    "-L\(qemuLibDir)",
    "-Xlinker", "-force_load", "-Xlinker", "\(qemuLibDir)/libqemu-aarch64-linux-user.a",
    "-Xlinker", "-force_load", "-Xlinker", "\(qemuLibDir)/libhwcore.a",
    "-lqemuutil",
    "-lqom",
    "-levent-loop-base",
    "-lglib-2.0",
    "-lpcre2-8",
    "-lintl",
    "-lffi",
    "-lz",
    "-lm",
    "-liconv",
]

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
            name: "NapaxiIosQemu",
            path: "Vendor/IosQemu/Sources/QEMU",
            sources: [
                "qemu_bridge.c",
                "qemu_runner.c",
            ],
            publicHeadersPath: ".",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("../../Vendor/QEMU/include"),
                .headerSearchPath("../../Vendor/QEMU/include/glib-2.0"),
                .headerSearchPath("../../Vendor/QEMU/lib/glib-2.0/include"),
                .define("NAPAXI_IOS_QEMU", .when(platforms: [.iOS])),
            ],
            linkerSettings: [
                .unsafeFlags(qemuLinkerFlags, .when(platforms: [.iOS])),
            ]
        ),
        .target(
            name: "Napaxi",
            dependencies: [
                .target(name: "NapaxiApiBridge", condition: .when(platforms: [.iOS])),
                .target(name: "NapaxiIosQemu", condition: .when(platforms: [.iOS])),
            ],
            resources: [
                .copy("Resources"),
            ],
            swiftSettings: [
                .define("NAPAXI_IOS_QEMU", .when(platforms: [.iOS])),
            ]
        ),
        .testTarget(name: "NapaxiTests", dependencies: ["Napaxi"]),
    ]
)
