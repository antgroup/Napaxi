import Foundation

/// iOS QEMU sandbox integration point.
///
/// Android treats the aarch64 Alpine image as a baked runtime asset and loads
/// it through the Android PRoot backend. iOS uses the same baked rootfs artifact
/// and swaps only the outer runner to Napaxi's vendored lower-level QEMU
/// C/static-library backend; it does not link the adjacent sandbox SDK
/// wrapper.
public enum NapaxiIosQemuSandboxSupport {
    public static let shellCapabilityId = "napaxi.tool.shell"
    public static let codexCapabilityId = "napaxi.agent_engine.codex"
    public static let sandboxCapabilityId = "napaxi.platform.ios_qemu"

    /// Keep the Android artifact name exactly so Android/iOS package the same
    /// baked Alpine aarch64 rootfs.
    public static let bundledRootfsCandidates: [(name: String, extension: String)] = [
        ("alpine-rootfs", "bin"),
    ]

    public static func bundledRootfsArchiveURL() -> URL? {
        for candidate in bundledRootfsCandidates {
            if let url = Bundle.module.url(forResource: candidate.name, withExtension: candidate.extension)
                ?? Bundle.module.url(forResource: candidate.name, withExtension: candidate.extension, subdirectory: "Resources")
                ?? Bundle.main.url(forResource: candidate.name, withExtension: candidate.extension) {
                return url
            }
        }
        return nil
    }

    public static var isBundledRootfsAvailable: Bool {
        bundledRootfsArchiveURL() != nil
    }

    /// True for iOS builds that link Napaxi's vendored QEMU C bridge/static
    /// libraries through the `NapaxiIosQemu` target. Builds without those
    /// artifacts keep the stable API surface but report the sandbox as not
    /// ready.
    public static var isRuntimeLinked: Bool {
        #if os(iOS) && NAPAXI_IOS_QEMU
        true
        #else
        false
        #endif
    }

    public static var isBundledSandboxAvailable: Bool {
        isRuntimeLinked && isBundledRootfsAvailable
    }

    @discardableResult
    public static func registerBundledRootfsArchive() -> Bool {
        guard isRuntimeLinked, let rootfs = bundledRootfsArchiveURL() else {
            return false
        }
        NapaxiNativeBridge.registerIosQemuRootfsArchive(path: rootfs.path)
        return true
    }

    public static func isReady(filesDir: String) -> Bool {
        guard isRuntimeLinked else { return false }
        return NapaxiNativeBridge.isIosQemuReady(filesDir: filesDir)
    }

    public static func disabledCapabilities(
        rootfsAvailable: Bool = isBundledRootfsAvailable,
        runtimeLinked: Bool = isRuntimeLinked
    ) -> [String] {
        rootfsAvailable && runtimeLinked ? [] : [shellCapabilityId, codexCapabilityId, sandboxCapabilityId]
    }
}
