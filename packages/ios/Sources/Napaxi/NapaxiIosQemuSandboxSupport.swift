import Foundation

/// iOS QEMU sandbox integration point.
///
/// Android treats the aarch64 Alpine image as a full development runtime asset.
/// iOS uses a separate lightweight Alpine rootfs profile and links Napaxi's
/// vendored lower-level QEMU C/static-library backend; it does not package
/// Codex CLI, OpenJDK, Android SDK/build-tools, qemu-x86_64, or the adjacent
/// sandbox SDK wrapper.
public enum NapaxiIosQemuSandboxSupport {
    public static let shellCapabilityId = "napaxi.tool.shell"
    public static let codexCapabilityId = "napaxi.agent_engine.codex"
    public static let sandboxCapabilityId = "napaxi.platform.ios_qemu"

    /// Keep the artifact name stable while allowing the iOS package to ship a
    /// lightweight rootfs that differs from Android's full APK-build profile.
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
        var disabled = [codexCapabilityId]
        if !(rootfsAvailable && runtimeLinked) {
            disabled.append(shellCapabilityId)
            disabled.append(sandboxCapabilityId)
        }
        return disabled
    }
}
