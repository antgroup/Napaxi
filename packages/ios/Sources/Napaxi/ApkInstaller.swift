import Foundation

public struct NapaxiApkInstallResult: Codable, Equatable, Sendable {
    public var success: Bool
    public var installerOpened: Bool
    public var permissionRequired: Bool
    public var apkPath: String?
    public var error: String?
    public var code: String?
    /// Wire value from the install-state machine shared across Flutter, Android,
    /// and iOS. iOS always reports `unsupported_ios` because the platform
    /// cannot install APKs; the field exists so parity checks across adapters
    /// do not see silent gaps.
    public var installState: String
    public var artifactSha256: String?
    public var artifactSize: Int?
    public var versionCode: Int?
    public var versionName: String?
    public var packageName: String?
    public var canceled: Bool
    public var failedReason: String?

    public init(
        success: Bool,
        installerOpened: Bool = false,
        permissionRequired: Bool = false,
        apkPath: String? = nil,
        error: String? = nil,
        code: String? = nil,
        installState: String = "unsupported_ios",
        artifactSha256: String? = nil,
        artifactSize: Int? = nil,
        versionCode: Int? = nil,
        versionName: String? = nil,
        packageName: String? = nil,
        canceled: Bool = false,
        failedReason: String? = nil
    ) {
        self.success = success
        self.installerOpened = installerOpened
        self.permissionRequired = permissionRequired
        self.apkPath = apkPath
        self.error = error
        self.code = code
        self.installState = installState
        self.artifactSha256 = artifactSha256
        self.artifactSize = artifactSize
        self.versionCode = versionCode
        self.versionName = versionName
        self.packageName = packageName
        self.canceled = canceled
        self.failedReason = failedReason
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
            code: map["code"]?.stringValue,
            installState: map["installState"]?.stringValue
                ?? map["install_state"]?.stringValue
                ?? "unsupported_ios",
            artifactSha256: map["artifactSha256"]?.stringValue,
            artifactSize: map["artifactSize"]?.intValue,
            versionCode: map["versionCode"]?.intValue,
            versionName: map["versionName"]?.stringValue,
            packageName: map["packageName"]?.stringValue,
            canceled: map["canceled"]?.boolValue ?? false,
            failedReason: map["failedReason"]?.stringValue
        )
    }

    enum CodingKeys: String, CodingKey {
        case success
        case installerOpened
        case permissionRequired
        case apkPath
        case error
        case code
        case installState
        case artifactSha256
        case artifactSize
        case versionCode
        case versionName
        case packageName
        case canceled
        case failedReason
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "success": .bool(success),
            "installerOpened": .bool(installerOpened),
            "permissionRequired": .bool(permissionRequired),
            "installState": .string(installState),
            "canceled": .bool(canceled),
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
        if let artifactSha256 {
            object["artifactSha256"] = .string(artifactSha256)
        }
        if let artifactSize {
            object["artifactSize"] = .number(Double(artifactSize))
        }
        if let versionCode {
            object["versionCode"] = .number(Double(versionCode))
        }
        if let versionName {
            object["versionName"] = .string(versionName)
        }
        if let packageName {
            object["packageName"] = .string(packageName)
        }
        if let failedReason {
            object["failedReason"] = .string(failedReason)
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
            error: "APK installation is only supported on Android.",
            code: "unsupported_ios",
            installState: "unsupported_ios",
            failedReason: "APK installation is not supported on iOS.",
            canceled: false
        )
    }
}

