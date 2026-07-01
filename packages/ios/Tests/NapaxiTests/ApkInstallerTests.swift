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
}
