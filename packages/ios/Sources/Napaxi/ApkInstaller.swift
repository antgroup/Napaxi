import Foundation

public struct NapaxiApkInstallResult: Codable, Equatable, Sendable {
    public var success: Bool
    public var installerOpened: Bool
    public var permissionRequired: Bool
    public var apkPath: String?
    public var error: String?
    public var code: String?

    public init(
        success: Bool,
        installerOpened: Bool = false,
        permissionRequired: Bool = false,
        apkPath: String? = nil,
        error: String? = nil,
        code: String? = nil
    ) {
        self.success = success
        self.installerOpened = installerOpened
        self.permissionRequired = permissionRequired
        self.apkPath = apkPath
        self.error = error
        self.code = code
    }

    public init(map: [String: NapaxiJSONValue]) {
        self = Self.fromMap(map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> Self {
        Self(
            success: map["success"]?.boolValue ?? false,
            installerOpened: map["installerOpened"]?.boolValue ?? false,
            permissionRequired: map["permissionRequired"]?.boolValue ?? false,
            apkPath: map["apkPath"]?.stringValue,
            error: map["error"]?.stringValue,
            code: map["code"]?.stringValue
        )
    }

    enum CodingKeys: String, CodingKey {
        case success
        case installerOpened
        case permissionRequired
        case apkPath
        case error
        case code
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "success": .bool(success),
            "installerOpened": .bool(installerOpened),
            "permissionRequired": .bool(permissionRequired),
        ]
        if let apkPath {
            object["apkPath"] = .string(apkPath)
        }
        if let error {
            object["error"] = .string(error)
        }
        if let code {
            object["code"] = .string(code)
        }
        return object
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toMap())
    }
}


public enum NapaxiApkInstaller {
    public static var isSupported: Bool { false }

    public static func installApk(_ apkPath: String) async -> NapaxiApkInstallResult {
        NapaxiApkInstallResult(
            success: false,
            apkPath: apkPath.isEmpty ? nil : apkPath,
            error: "APK installation is only supported on Android."
        )
    }
}

