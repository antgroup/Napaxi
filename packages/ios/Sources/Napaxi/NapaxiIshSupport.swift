import Foundation

public enum NapaxiIshSupport {
    public static let shellCapabilityId = "napaxi.tool.shell"

    public static func bundledRootfsArchiveURL() -> URL? {
        Bundle.module.url(forResource: "alpine-rootfs", withExtension: "tar.gz")
            ?? Bundle.module.url(forResource: "alpine-rootfs", withExtension: "tar.gz", subdirectory: "Resources")
            ?? Bundle.main.url(forResource: "alpine-rootfs", withExtension: "tar.gz")
    }

    public static var isBundledRootfsAvailable: Bool {
        bundledRootfsArchiveURL() != nil
    }

    @discardableResult
    public static func registerBundledRootfsArchive() -> Bool {
        guard let rootfs = bundledRootfsArchiveURL() else {
            return false
        }
        NapaxiNativeBridge.registerIshRootfsArchive(path: rootfs.path)
        return true
    }

    public static func isReady(filesDir: String) -> Bool {
        NapaxiNativeBridge.isIshReady(filesDir: filesDir)
    }

    public static func disabledCapabilities(rootfsAvailable: Bool = isBundledRootfsAvailable) -> [String] {
        rootfsAvailable ? [] : [shellCapabilityId]
    }
}
