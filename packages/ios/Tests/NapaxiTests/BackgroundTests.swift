import XCTest
@testable import Napaxi

final class BackgroundTests: XCTestCase {
    func testBackgroundConfigEncodesFlutterCompatibleMap() {
        let config = NapaxiBackgroundConfig(
            notificationConfig: NapaxiNotificationConfig(ongoingTitle: "Runner"),
            wakeLockTimeoutMilliseconds: 42
        )

        let map = config.toMap()
        var mutableConfig = config
        mutableConfig.wakeLockTimeout = 1.5

        guard case .object(let object) = config.jsonValue() else {
            return XCTFail("background config should encode as object")
        }
        XCTAssertEqual(map["enabled"], .bool(true))
        XCTAssertEqual(map["ongoingTitle"], .string("Runner"))
        XCTAssertEqual(map["wakeLockTimeoutMs"], .number(42))
        XCTAssertEqual(config.wakeLockTimeout, 0.042)
        XCTAssertEqual(mutableConfig.wakeLockTimeoutMilliseconds, 1_500)
        XCTAssertEqual(object["enabled"], .bool(true))
        XCTAssertEqual(object["ongoingTitle"], .string("Runner"))
        XCTAssertEqual(object["wakeLockTimeoutMs"], .number(42))
    }

    func testBackgroundConfigCodableUsesFlutterMapShape() throws {
        let config = try JSONDecoder().decode(
            NapaxiBackgroundConfig.self,
            from: Data(#"{"enabled":false,"channelName":"Agent Channel","ongoingTitle":"Runner","wakeLockTimeoutMs":1500}"#.utf8)
        )

        XCTAssertFalse(config.enabled)
        XCTAssertEqual(config.notificationConfig.channelName, "Agent Channel")
        XCTAssertEqual(config.notificationConfig.ongoingTitle, "Runner")
        XCTAssertEqual(config.notificationConfig.ongoingMessage, "Agent is running...")
        XCTAssertEqual(config.wakeLockTimeoutMilliseconds, 1_500)

        let encoded = try JSONDecoder().decode(
            NapaxiJSONValue.self,
            from: JSONEncoder().encode(config)
        )
        guard case .object(let object) = encoded else {
            return XCTFail("background config should encode as object")
        }
        XCTAssertEqual(object["enabled"], .bool(false))
        XCTAssertEqual(object["channelName"], .string("Agent Channel"))
        XCTAssertEqual(object["ongoingTitle"], .string("Runner"))
        XCTAssertEqual(object["ongoingMessage"], .string("Agent is running..."))
        XCTAssertEqual(object["wakeLockTimeoutMs"], .number(1_500))
        XCTAssertNil(object["notificationConfig"])
        XCTAssertNil(object["wakeLockTimeoutMilliseconds"])
    }

    func testBackgroundActionUnknownValueFallsBackToStopLikeFlutterEventChannel() throws {
        let event = try JSONDecoder().decode(
            NapaxiBackgroundActionEvent.self,
            from: Data(#"{"action":"mystery","requestId":"req-1","payload":"{}"}"#.utf8)
        )

        XCTAssertEqual(event.action, .stop)
        XCTAssertEqual(event.requestId, "req-1")
        XCTAssertEqual(event.payload, "{}")
    }

    func testBackgroundPermissionsMirrorFlutterIosDefaults() async {
        let notificationGranted = await NapaxiBackgroundPermissions.checkNotificationPermission()
        let requestGranted = await NapaxiBackgroundPermissions.requestNotificationPermission()
        let backgroundAvailable = await NapaxiBackgroundPermissions.canRunInBackground()

        XCTAssertFalse(isBackgroundExecutionSupported())
        XCTAssertFalse(NapaxiBackgroundPermissions.isSupported)
        XCTAssertTrue(notificationGranted)
        XCTAssertTrue(requestGranted)
        XCTAssertFalse(backgroundAvailable)
    }

    func testBackgroundPermissionsCanDelegateToHostPolicy() async {
        let host = RecordingBackgroundPermissionHost(
            notificationGranted: false,
            requestGranted: true,
            backgroundAvailable: true
        )
        let permissions = NapaxiBackgroundPermissions(host: host)
        let notificationGranted = await permissions.checkNotificationPermission()
        let requestGranted = await permissions.requestNotificationPermission()
        let backgroundAvailable = await permissions.canRunInBackground()

        XCTAssertFalse(permissions.isSupported)
        XCTAssertFalse(notificationGranted)
        XCTAssertTrue(requestGranted)
        XCTAssertTrue(backgroundAvailable)
        XCTAssertEqual(host.checkedCount, 1)
        XCTAssertEqual(host.requestedCount, 1)
        XCTAssertEqual(host.backgroundCheckedCount, 1)
    }

    func testBackgroundControllerNoOpsWithoutHostLikeFlutterIos() async throws {
        let controller = NapaxiBackgroundController(config: NapaxiBackgroundConfig())

        try await controller.start(NapaxiBackgroundConfig())
        try await controller.stop()

        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(controller.currentConfig, NapaxiBackgroundConfig())
    }

    func testBackgroundControllerDisabledStartNoOpsBeforeHostWorkLikeFlutter() async throws {
        let host = RecordingBackgroundHost()
        let controller = NapaxiBackgroundController(host: host)

        try await controller.start(NapaxiBackgroundConfig(enabled: false))

        XCTAssertFalse(controller.isRunning)
        XCTAssertNil(controller.currentConfig)
        XCTAssertEqual(host.startedCount, 0)
    }

    func testEngineBackgroundControllerCreationMirrorsFlutterIosDefaults() {
        let host = RecordingBackgroundHost()
        let config = NapaxiBackgroundConfig()

        let unsupportedController = NapaxiEngine.makeBackgroundController(config: config, host: nil)
        let hostBackedController = NapaxiEngine.makeBackgroundController(config: config, host: host)
        let hostBackedWithoutConfig = NapaxiEngine.makeBackgroundController(config: nil, host: host)
        let disabledController = NapaxiEngine.makeBackgroundController(
            config: NapaxiBackgroundConfig(enabled: false),
            host: host
        )

        XCTAssertNil(unsupportedController)
        XCTAssertNotNil(hostBackedController)
        XCTAssertEqual(hostBackedController?.currentConfig, config)
        XCTAssertNotNil(hostBackedWithoutConfig)
        XCTAssertNil(hostBackedWithoutConfig?.currentConfig)
        XCTAssertNil(disabledController)
    }

    func testEngineAutomationDefaultMirrorsFlutterBackgroundConfigRule() {
        let config = NapaxiBackgroundConfig()

        XCTAssertFalse(NapaxiEngine.resolveAutomationEnabled(enableAutomation: nil, backgroundConfig: nil))
        XCTAssertTrue(NapaxiEngine.resolveAutomationEnabled(enableAutomation: nil, backgroundConfig: config))
        XCTAssertFalse(NapaxiEngine.resolveAutomationEnabled(enableAutomation: false, backgroundConfig: config))
        XCTAssertTrue(NapaxiEngine.resolveAutomationEnabled(enableAutomation: true, backgroundConfig: nil))
    }

    func testBackgroundControllerUsesHostAndPublishesActions() async throws {
        let host = RecordingBackgroundHost()
        let controller = NapaxiBackgroundController(config: NapaxiBackgroundConfig(), host: host)
        var iterator = controller.onAction.makeAsyncIterator()

        try await controller.start(NapaxiBackgroundConfig())
        XCTAssertTrue(controller.isRunning)
        XCTAssertEqual(host.startedCount, 1)

        controller.emitAction(NapaxiBackgroundActionEvent(action: .agentTrigger, requestId: "req-1", payload: "{}"))
        let event = await iterator.next()
        XCTAssertEqual(event, NapaxiBackgroundActionEvent(action: .agentTrigger, requestId: "req-1", payload: "{}"))

        try await controller.stop()
        XCTAssertFalse(controller.isRunning)
        XCTAssertEqual(host.stoppedCount, 1)
    }

    func testBackgroundControllerMirrorsFlutterChatEventNotifications() async throws {
        let host = RecordingBackgroundHost()
        let controller = NapaxiBackgroundController(config: NapaxiBackgroundConfig(), host: host)
        try await controller.start(NapaxiBackgroundConfig())

        _ = await controller.handleChatEvent(NapaxiChatEvent(raw: .object([
            "type": .string("tool_call"),
            "name": .string("calendar.create"),
        ])))
        _ = await controller.handleChatEvent(NapaxiChatEvent(raw: .object([
            "type": .string("asking_human"),
            "request_id": .string("hitl-1"),
            "question": .string("Approve?"),
            "options": .array([.string("Yes")]),
        ])))
        await controller.finishChatStream(endedWithError: false, activeRunCount: 0)

        XCTAssertEqual(host.updateMessages, ["Running: calendar.create"])
        XCTAssertEqual(host.hitlRequests.map(\.requestId), ["hitl-1"])
        XCTAssertEqual(host.hitlRequests.map(\.question), ["Approve?"])
        XCTAssertEqual(host.completionMessages, ["Task completed"])
        XCTAssertEqual(host.stoppedCount, 1)
        XCTAssertFalse(controller.isRunning)
    }

    func testBackgroundControllerStopsOnErrorEvent() async throws {
        let host = RecordingBackgroundHost()
        let controller = NapaxiBackgroundController(config: NapaxiBackgroundConfig(), host: host)
        try await controller.start(NapaxiBackgroundConfig())

        let endedWithError = await controller.handleChatEvent(NapaxiChatEvent(raw: .object([
            "type": .string("error"),
            "message": .string("Network failed"),
        ])))

        XCTAssertTrue(endedWithError)
        XCTAssertEqual(host.errorMessages, ["Network failed"])
        XCTAssertEqual(host.stoppedCount, 1)
        XCTAssertFalse(controller.isRunning)
    }
}

private final class RecordingBackgroundHost: NapaxiBackgroundHost {
    var startedCount = 0
    var stoppedCount = 0
    var updateMessages: [String] = []
    var hitlRequests: [(requestId: String, question: String, options: [String]?)] = []
    var completionMessages: [String] = []
    var errorMessages: [String] = []

    func startBackgroundExecution(config: NapaxiBackgroundConfig) async throws {
        startedCount += 1
    }

    func stopBackgroundExecution() async throws {
        stoppedCount += 1
    }

    func updateBackgroundNotification(message: String?, progress: Int?) async throws {
        if let message {
            updateMessages.append(message)
        }
    }

    func showHitlNotification(requestId: String, question: String, options: [String]?) async throws {
        hitlRequests.append((requestId: requestId, question: question, options: options))
    }

    func showCompletionNotification(title: String, message: String) async throws {
        completionMessages.append(message)
    }

    func showErrorNotification(title: String, message: String) async throws {
        errorMessages.append(message)
    }

    func cancelBackgroundNotification(notificationId: Int?) async throws {}
}

private final class RecordingBackgroundPermissionHost: NapaxiBackgroundPermissionHost {
    let notificationGranted: Bool
    let requestGranted: Bool
    let backgroundAvailable: Bool
    var checkedCount = 0
    var requestedCount = 0
    var backgroundCheckedCount = 0

    init(notificationGranted: Bool, requestGranted: Bool, backgroundAvailable: Bool) {
        self.notificationGranted = notificationGranted
        self.requestGranted = requestGranted
        self.backgroundAvailable = backgroundAvailable
    }

    func checkNapaxiNotificationPermission() async -> Bool {
        checkedCount += 1
        return notificationGranted
    }

    func requestNapaxiNotificationPermission() async -> Bool {
        requestedCount += 1
        return requestGranted
    }

    func canRunNapaxiInBackground() async -> Bool {
        backgroundCheckedCount += 1
        return backgroundAvailable
    }
}
