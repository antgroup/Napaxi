import XCTest
@testable import Napaxi

final class ApkInstallerTests: XCTestCase {
    func testApkInstallerIsExplicitlyUnsupportedOnIOS() async {
        XCTAssertFalse(NapaxiApkInstaller.isSupported)
        XCTAssertFalse(NapaxiApkInstaller.isSupported)

        let result = await NapaxiApkInstaller.installApk("/tmp/app.apk")

        XCTAssertFalse(result.success)
        XCTAssertFalse(result.installerOpened)
        XCTAssertFalse(result.permissionRequired)
        XCTAssertEqual(result.apkPath, "/tmp/app.apk")
        XCTAssertEqual(result.error, "APK installation is only supported on Android.")
        XCTAssertNil(result.code)
    }

    func testFlutterNamedApkInstallerAliasesCompile() async {
        let result: NapaxiApkInstallResult = await NapaxiApkInstaller.installApk("")

        XCTAssertFalse(result.success)
        XCTAssertNil(result.apkPath)
    }

    func testApkInstallResultUsesFlutterCompatibleKeys() {
        let result = NapaxiApkInstallResult(
            success: false,
            installerOpened: true,
            permissionRequired: true,
            apkPath: "/tmp/app.apk",
            error: "Nope",
            code: "ERR"
        )
        let expected: [String: NapaxiJSONValue] = [
            "success": .bool(false),
            "installerOpened": .bool(true),
            "permissionRequired": .bool(true),
            "apkPath": .string("/tmp/app.apk"),
            "error": .string("Nope"),
            "code": .string("ERR"),
        ]

        XCTAssertEqual(result.toMap(), expected)
        XCTAssertEqual(result.jsonValue(), .object(expected))
        XCTAssertEqual(NapaxiApkInstallResult.fromMap([
            "success": .bool(false),
            "installerOpened": .bool(true),
            "permissionRequired": .bool(true),
            "apkPath": .string("/tmp/app.apk"),
            "error": .string("Nope"),
            "code": .string("ERR"),
        ]), result)
        XCTAssertEqual(NapaxiApkInstallResult.fromMap([:]), NapaxiApkInstallResult(success: false))
    }

    func testApkInstallResultCarriesBuildIdAndFailureStageAndInstallerStatusCode() {
        let result = NapaxiApkInstallResult(
            success: false,
            installerOpened: false,
            permissionRequired: false,
            apkPath: "/tmp/app.apk",
            error: "Install blocked.",
            code: "signature_or_version_blocked",
            installState: "failed",
            canceled: false,
            failedReason: "signature_or_version_blocked",
            buildId: "abcdef0123456789",
            failureStage: "post_install",
            installerStatusCode: 7
        )
        let map = result.toMap()
        XCTAssertEqual(map["buildId"], .string("abcdef0123456789"))
        XCTAssertEqual(map["failureStage"], .string("post_install"))
        XCTAssertEqual(map["installerStatusCode"], .number(Double(7)))

        let parsed = NapaxiApkInstallResult.fromMap(map)
        XCTAssertEqual(parsed, result)
    }

    func testVerifyArtifactAlwaysReturnsUnsupportedOnIOS() {
        // DIMA 2026110400120316848: iOS cannot install APKs; verifyArtifact
        // returns an explicit `unsupported_ios` state instead of a silent gap
        // so cross-adapter parity checks see a deliberate "not supported"
        // answer rather than a missing surface.
        let verification = NapaxiApkInstaller.verifyArtifact("/tmp/project")
        XCTAssertFalse(verification.verified)
        XCTAssertEqual(verification.state, "unsupported_ios")
        XCTAssertEqual(verification.reason, "APK install verification is not supported on iOS")
    }
}
