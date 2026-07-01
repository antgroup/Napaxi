import Napaxi
@testable import NapaxiIOSIntegrationSmoke
import XCTest

final class SmokeHostTests: XCTestCase {
    func testSnapshotUsesNativeIosPlatformContextShape() throws {
        let snapshot = try NapaxiIOSIntegrationSmoke.makeSnapshot(filesDir: "/tmp/napaxi-ios-host-smoke")
        let context = try decodeJsonObject(snapshot.platformContextJSON)

        XCTAssertEqual(snapshot.filesDir, "/tmp/napaxi-ios-host-smoke")
        XCTAssertEqual(context["platform"]?.stringValue, "ios")
        XCTAssertEqual(context["files_dir"]?.stringValue, "/tmp/napaxi-ios-host-smoke")
        XCTAssertEqual(snapshot.enabledCapabilities, [
            "napaxi.tool.custom_host",
            "napaxi.platform_tool.open_url",
        ])
        XCTAssertTrue(snapshot.supportedCapabilities.contains("napaxi.platform_tool.*"))
    }

    func testHostPackageCanCreateNativeEngine() throws {
        let filesDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("napaxi-ios-host-engine-smoke", isDirectory: true)
            .path

        #if os(iOS)
        let engine = try NapaxiIOSIntegrationSmoke.createEngineForSmoke(filesDir: filesDir)

        XCTAssertGreaterThan(engine.handle, 0)
        XCTAssertEqual(engine.filesDir, filesDir)
        XCTAssertEqual(engine.capabilityProfile?.platform, "ios")
        XCTAssertTrue(engine.capabilityProfile?.supportedCapabilities.contains("napaxi.platform_tool.*") ?? false)
        #else
        XCTAssertThrowsError(try NapaxiIOSIntegrationSmoke.createEngineForSmoke(filesDir: filesDir)) { error in
            XCTAssertTrue(String(describing: error).contains("Napaxi native engine is only available on iOS"))
        }
        #endif
    }

    func testHostExecutorsReturnPublicJsonShapes() async throws {
        let toolExecutor = SmokeToolExecutor()
        let toolResult = await toolExecutor.execute(
            toolName: "ios_integration_ping",
            paramsJSON: #"{"input":"hello"}"#,
            context: nil
        )
        let toolJSON = try decodeJsonObject(try toolResult.get())
        XCTAssertEqual(toolJSON["tool"]?.stringValue, "ios_integration_ping")
        XCTAssertEqual(toolJSON["params_json"]?.stringValue, #"{"input":"hello"}"#)
        XCTAssertEqual(toolJSON["ok"]?.boolValue, true)

        let approval = await SmokeApprovalHandler().approve(NapaxiHostToolApprovalRequest(
            requestId: 7,
            toolName: "open_url",
            description: "Open a test URL",
            parametersJSON: #"{"url":"https://example.com"}"#
        ))
        XCTAssertTrue(approval.approved)
        XCTAssertEqual(approval.always, false)

        let platformResult = try await SmokePlatformToolExecutor().executePlatformTool(
            name: "open_url",
            params: ["url": .string("https://example.com")]
        )
        let platformJSON = try XCTUnwrap(platformResult.objectValue)
        XCTAssertEqual(platformJSON["success"]?.boolValue, true)
        XCTAssertEqual(platformJSON["tool"]?.stringValue, "open_url")
        XCTAssertEqual(platformJSON["params"]?.objectValue?["url"]?.stringValue, "https://example.com")
    }
}
