import Foundation

public struct NapaxiPlatformContext: Codable, Equatable, Sendable {
    public var filesDir: String
    public var platformContextJSON: String
    public var platformContextJson: String {
        get { platformContextJSON }
        set { platformContextJSON = newValue }
    }

    public init(filesDir: String, platformContextJSON: String) {
        self.filesDir = filesDir
        self.platformContextJSON = platformContextJSON
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: NapaxiJSONValue].self)
        self.init(
            filesDir: object["filesDir"]?.stringValue ?? "",
            platformContextJSON: object["platformContextJson"]?.stringValue
                ?? object["platformContextJSON"]?.stringValue
                ?? ""
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(NapaxiJSONValue.object([
            "filesDir": .string(filesDir),
            "platformContextJson": .string(platformContextJSON),
        ]))
    }
}

public enum NapaxiPlatformContextResolver {
    public static func resolve(
        filesDir: String? = nil,
        platform: String? = nil,
        nativeLibraryDir: String? = nil,
        capabilityProfile: NapaxiCapabilityProfile? = nil,
        capabilitySelection: NapaxiCapabilitySelection? = nil
    ) throws -> NapaxiPlatformContext {
        let resolvedFilesDir = filesDir ?? defaultFilesDir
        let resolvedPlatform = platform ?? defaultPlatform
        var object: [String: NapaxiJSONValue] = [
            "platform": .string(resolvedPlatform),
            "files_dir": .string(resolvedFilesDir),
        ]
        if let nativeLibraryDir {
            object["native_library_dir"] = .string(nativeLibraryDir)
        }
        if let capabilityProfile {
            object["capability_profile"] = capabilityProfile.jsonValue()
            object["skill_readiness"] = .object([
                "platform": .string(resolvedPlatform),
                "capabilities": .array(capabilityProfile.supportedCapabilities.map { .string($0) }),
                "use_process_fallback": .bool(false),
            ])
        }
        if let capabilitySelection {
            object["capability_selection"] = capabilitySelection.jsonValue()
        }
        return NapaxiPlatformContext(
            filesDir: resolvedFilesDir,
            platformContextJSON: try object.jsonString()
        )
    }

    public static var defaultFilesDir: String {
        #if os(iOS)
        let documentDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentDir.appendingPathComponent("napaxi_data", isDirectory: true).path
        #else
        return FileManager.default.temporaryDirectory.appendingPathComponent("napaxi_data", isDirectory: true).path
        #endif
    }

    public static var defaultPlatform: String {
        #if os(iOS)
        return "ios"
        #else
        return "other"
        #endif
    }
}
