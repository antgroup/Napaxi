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
    /// Build attempt identifier from `artifact.json.build_id`. iOS cannot
    /// install APKs but still carries the field through wire parity so a
    /// cross-adapter result comparing build_id does not see a silent gap on
    /// iOS. DIMA 2026110400120316848.
    public var buildId: String?
    public var failureStage: String?
    public var installerStatusCode: Int?

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
        failedReason: String? = nil,
        buildId: String? = nil,
        failureStage: String? = nil,
        installerStatusCode: Int? = nil
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
        self.buildId = buildId
        self.failureStage = failureStage
        self.installerStatusCode = installerStatusCode
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
            failedReason: map["failedReason"]?.stringValue,
            buildId: map["buildId"]?.stringValue,
            failureStage: map["failureStage"]?.stringValue,
            installerStatusCode: map["installerStatusCode"]?.intValue
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
        case buildId
        case failureStage
        case installerStatusCode
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
        if let buildId {
            object["buildId"] = .string(buildId)
        }
        if let failureStage {
            object["failureStage"] = .string(failureStage)
        }
        if let installerStatusCode {
            object["installerStatusCode"] = .number(Double(installerStatusCode))
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
            canceled: false,
            failedReason: "APK installation is not supported on iOS."
        )
    }
}

/// iOS-side artifact verification parity for DIMA 2026110400120316848.
/// iOS cannot install APKs but must expose the same surface as the Flutter
/// `NapaxiApkInstaller.verifyArtifact` and Android
/// `NapaxiApkInstaller.verifyArtifact`, returning an explicit
/// `unsupported_ios` state. This prevents the parity checker from seeing a
/// silent method gap on iOS rather than a deliberate "this platform does not
/// support this operation" answer.
public struct NapaxiArtifactVerification: Codable, Equatable, Sendable {
    public var verified: Bool
    public var state: String
    public var apkPath: String?
    public var expectedSha256: String?
    public var actualSha256: String?
    public var size: Int?
    public var packageName: String?
    public var versionCode: String?
    public var versionName: String?
    public var buildId: String?
    public var targetSdk: Int?
    public var reason: String?

    public init(
        verified: Bool = false,
        state: String = "unsupported_ios",
        apkPath: String? = nil,
        expectedSha256: String? = nil,
        actualSha256: String? = nil,
        size: Int? = nil,
        packageName: String? = nil,
        versionCode: String? = nil,
        versionName: String? = nil,
        buildId: String? = nil,
        targetSdk: Int? = nil,
        reason: String? = nil
    ) {
        self.verified = verified
        self.state = state
        self.apkPath = apkPath
        self.expectedSha256 = expectedSha256
        self.actualSha256 = actualSha256
        self.size = size
        self.packageName = packageName
        self.versionCode = versionCode
        self.versionName = versionName
        self.buildId = buildId
        self.targetSdk = targetSdk
        self.reason = reason
    }

    public init(map: [String: NapaxiJSONValue]) {
        self.verified = map["verified"]?.boolValue ?? false
        self.state = map["state"]?.stringValue ?? "unsupported_ios"
        self.apkPath = map["apkPath"]?.stringValue
        self.expectedSha256 = map["expectedSha256"]?.stringValue
        self.actualSha256 = map["actualSha256"]?.stringValue
        self.size = map["size"]?.intValue
        self.packageName = map["packageName"]?.stringValue
        self.versionCode = map["versionCode"]?.stringValue
        self.versionName = map["versionName"]?.stringValue
        self.buildId = map["buildId"]?.stringValue
        self.targetSdk = map["targetSdk"]?.intValue
        self.reason = map["reason"]?.stringValue
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        var object: [String: NapaxiJSONValue] = [
            "verified": .bool(verified),
            "state": .string(state),
        ]
        if let apkPath { object["apkPath"] = .string(apkPath) }
        if let expectedSha256 { object["expectedSha256"] = .string(expectedSha256) }
        if let actualSha256 { object["actualSha256"] = .string(actualSha256) }
        if let size { object["size"] = .number(Double(size)) }
        if let packageName { object["packageName"] = .string(packageName) }
        if let versionCode { object["versionCode"] = .string(versionCode) }
        if let versionName { object["versionName"] = .string(versionName) }
        if let buildId { object["buildId"] = .string(buildId) }
        if let targetSdk { object["targetSdk"] = .number(Double(targetSdk)) }
        if let reason { object["reason"] = .string(reason) }
        return object
    }

    public func jsonValue() -> NapaxiJSONValue {
        .object(toMap())
    }

    enum CodingKeys: String, CodingKey {
        case verified, state, apkPath, expectedSha256, actualSha256, size
        case packageName, versionCode, versionName, buildId, targetSdk, reason
    }
}

public extension NapaxiApkInstaller {
    /// iOS explicitly returns `unsupported_ios` for APK artifact verification.
    /// The method exists so cross-adapter parity checks do not surface APK
    /// verification as a "silent gap" on iOS, mirroring the
    /// `unsupported_platform` contract for install-related operations.
    static func verifyArtifact(_ androidProjectRoot: String) -> NapaxiArtifactVerification {
        NapaxiArtifactVerification(
            verified: false,
            state: "unsupported_ios",
            reason: "APK install verification is not supported on iOS"
        )
    }
}

