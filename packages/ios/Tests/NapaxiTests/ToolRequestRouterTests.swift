import XCTest
@testable import Napaxi

final class ToolRequestRouterTests: XCTestCase {
    func testRoutesCoreApprovalToolToStructuredHandler() async throws {
        let handler = CapturingApprovalHandler(response: NapaxiHostToolApprovalResponse(
            approved: true,
            always: true,
            message: "remember"
        ))
        let router = NapaxiToolRequestRouter(
            platformExecutor: nil,
            customExecutor: nil,
            approvalHandler: nil,
            structuredApprovalHandler: handler,
            agentAppActionExecutor: nil,
            browserController: nil
        )
        let requestJSON = try jsonString([
            "request_id": 42,
            "tool_name": "__napaxi_approval__",
            "params_json": try jsonString([
                "tool_name": "shell",
                "description": "Approve shell command execution",
                "parameters": #"{"command":"git status"}"#,
                "allow_always": true,
            ]),
        ])

        let result = try await router.executeForTesting(requestJSON: requestJSON)
        let decoded = try XCTUnwrap(try decodeObject(result))

        XCTAssertEqual(handler.lastRequest?.requestId, 42)
        XCTAssertEqual(handler.lastRequest?.toolName, "shell")
        XCTAssertEqual(handler.lastRequest?.description, "Approve shell command execution")
        XCTAssertEqual(handler.lastRequest?.allowAlways, true)
        XCTAssertEqual(handler.lastRequest?.parameters["command"], .string("git status"))
        XCTAssertEqual(decoded["approved"] as? Bool, true)
        XCTAssertEqual(decoded["always"] as? Bool, true)
        XCTAssertEqual(decoded["message"] as? String, "remember")
    }

    func testRoutesCoreApprovalToolToLegacyBoolHandler() async throws {
        let handler = LegacyApprovalHandler(approved: false)
        let router = NapaxiToolRequestRouter(
            platformExecutor: nil,
            customExecutor: nil,
            approvalHandler: handler,
            structuredApprovalHandler: nil,
            agentAppActionExecutor: nil,
            browserController: nil
        )
        let paramsJSON = try jsonString([
            "tool_name": "http",
            "description": "Approve mutating HTTP request",
            "parameters": #"{"method":"POST"}"#,
            "allow_always": false,
        ])
        let requestJSON = try jsonString([
            "request_id": 7,
            "tool_name": "__napaxi_approval__",
            "params_json": paramsJSON,
        ])

        let result = try await router.executeForTesting(requestJSON: requestJSON)
        let decoded = try XCTUnwrap(try decodeObject(result))

        XCTAssertEqual(handler.lastToolName, "http")
        XCTAssertEqual(handler.lastRequestJSON, #"{"method":"POST"}"#)
        XCTAssertEqual(decoded["approved"] as? Bool, false)
        XCTAssertEqual(decoded["message"] as? String, "Tool execution denied by user")
    }

    func testRoutesCoreAgentAppDispatchToolToActionExecutor() async throws {
        let executor = CapturingActionExecutor(resultJSON: #"{"request_id":"r1","status":"succeeded","result":{},"completed_at":"1970-01-01T00:00:00Z"}"#)
        let router = NapaxiToolRequestRouter(
            platformExecutor: nil,
            customExecutor: nil,
            approvalHandler: nil,
            structuredApprovalHandler: nil,
            agentAppActionExecutor: executor,
            browserController: nil
        )
        let payload = try jsonString([
            "proposal": ["request_id": "r1"],
            "action": ["tool_name": "app_action_pay"],
            "package": ["agent_id": "wallet-agent"],
        ])
        let requestJSON = try jsonString([
            "request_id": 99,
            "tool_name": "__napaxi_agent_app_action__",
            "params_json": payload,
        ])

        let result = try await router.executeForTesting(requestJSON: requestJSON)

        XCTAssertEqual(executor.lastRequestJSON, payload)
        XCTAssertTrue(result.contains(#""status":"succeeded""#))
    }

    func testTypedAgentAppActionExecutorAdapterRoutesStructuredRequest() async throws {
        let executor = CapturingTypedActionExecutor()
        let adapter = NapaxiAgentAppActionExecutorAdapter(executor: executor)
        let router = NapaxiToolRequestRouter(
            platformExecutor: nil,
            customExecutor: nil,
            approvalHandler: nil,
            structuredApprovalHandler: nil,
            agentAppActionExecutor: adapter,
            browserController: nil
        )
        let payload = try jsonString([
            "proposal": [
                "request_id": "typed-r1",
                "agent_id": "wallet-agent",
                "tool_name": "app_action_pay",
            ],
            "action": [
                "action_id": "pay",
                "tool_name": "app_action_pay",
                "description": "Send a payment",
            ],
            "package": [
                "agent_id": "wallet-agent",
                "display_name": "Wallet",
            ],
        ])
        let requestJSON = try jsonString([
            "request_id": 100,
            "tool_name": "__napaxi_agent_app_action__",
            "params_json": payload,
        ])

        let result = try await router.executeForTesting(requestJSON: requestJSON)
        let decoded = try XCTUnwrap(try decodeObject(result))

        XCTAssertEqual(executor.lastRequest?.proposal.requestId, "typed-r1")
        XCTAssertEqual(executor.lastRequest?.proposal.agentId, "wallet-agent")
        XCTAssertEqual(executor.lastRequest?.action.toolName, "app_action_pay")
        XCTAssertEqual(executor.lastRequest?.package["display_name"], .string("Wallet"))
        XCTAssertEqual(decoded["request_id"] as? String, "typed-r1")
        XCTAssertEqual(decoded["status"] as? String, "succeeded")
    }

    func testRoutesFlutterStyleMcToolExecutorThroughAdapter() async throws {
        let executor = CapturingMcToolExecutor()
        let adapter = NapaxiToolExecutorAdapter(executor: executor)
        let router = NapaxiToolRequestRouter(
            platformExecutor: nil,
            customExecutor: adapter,
            approvalHandler: nil,
            structuredApprovalHandler: nil,
            agentAppActionExecutor: nil,
            browserController: nil
        )
        let paramsJSON = try jsonString(["query": "weather"])
        let requestJSON = try jsonString([
            "request_id": 123,
            "tool_name": "custom_search",
            "params_json": paramsJSON,
            "context": ["session": "s1"],
        ])

        let result = try await router.executeForTesting(requestJSON: requestJSON)

        XCTAssertEqual(result, #"{"ok":true}"#)
        XCTAssertEqual(executor.calls.map(\.toolName), ["custom_search"])
        XCTAssertEqual(executor.calls.map(\.paramsJSON), [paramsJSON])
    }

    func testRoutesFlutterPlatformToolSetToPlatformExecutor() async throws {
        let executor = CapturingPlatformExecutor()
        let router = NapaxiToolRequestRouter(
            platformExecutor: executor,
            customExecutor: nil,
            approvalHandler: nil,
            structuredApprovalHandler: nil,
            agentAppActionExecutor: nil,
            browserController: nil
        )
        let toolNames = [
            "open_url",
            "make_call",
            "send_sms",
            "get_clipboard",
            "set_clipboard",
            "get_device_info",
            "get_location",
            "send_notification",
            "get_contacts",
            "create_calendar_event",
            "list_calendar_events",
            "take_photo",
            "media_library",
            "record_audio",
            "set_alarm",
            "install_apk",
        ]

        for (index, toolName) in toolNames.enumerated() {
            let paramsJSON = try jsonString(["marker": toolName])
            let requestJSON = try jsonString([
                "request_id": UInt64(index + 1),
                "tool_name": toolName,
                "params_json": paramsJSON,
            ])

            let result = try await router.executeForTesting(requestJSON: requestJSON)

            XCTAssertTrue(result.contains(#""handled":true"#), "Expected \(toolName) to be handled by platform executor")
            XCTAssertEqual(executor.calls.last?.name, toolName)
            XCTAssertEqual(executor.calls.last?.params["marker"], .string(toolName))
        }
    }

    func testPlatformToolRequestRejectsNonObjectParamsForParsingToolsLikeFlutter() async throws {
        let executor = CapturingPlatformExecutor()
        let resolver = CapturingToolExecutionResolver()
        let router = NapaxiToolRequestRouter(
            platformExecutor: executor,
            customExecutor: nil,
            approvalHandler: nil,
            structuredApprovalHandler: nil,
            agentAppActionExecutor: nil,
            browserController: nil,
            resolver: resolver
        )
        let requestJSON = try jsonString([
            "request_id": 124,
            "tool_name": "set_clipboard",
            "params_json": "[]",
        ])

        await router.handle(requestJSON: requestJSON)

        XCTAssertTrue(executor.calls.isEmpty)
        XCTAssertEqual(resolver.calls.count, 1)
        XCTAssertEqual(resolver.calls.first?.requestId, 124)
        XCTAssertTrue(resolver.calls.first?.isError == true)
        XCTAssertTrue(resolver.calls.first?.resultJSON.contains("Platform tool parameters must be a JSON object") == true)
    }

    func testDefaultPlatformExecutorIsExplicitlyUnavailableOffIOS() async {
        #if !os(iOS)
        let executor = NapaxiDefaultPlatformToolExecutor()
        do {
            _ = try await executor.executePlatformTool(name: "open_url", params: ["url": .string("https://example.com")])
            XCTFail("Expected non-iOS default platform executor to throw")
        } catch let error as NapaxiError {
            XCTAssertEqual(error, .unavailable("Platform tools are only available on iOS"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        #endif
    }

    func testMalformedToolRequestIsDroppedLikeFlutter() async {
        let resolver = CapturingToolExecutionResolver()
        let router = NapaxiToolRequestRouter(
            platformExecutor: nil,
            customExecutor: nil,
            approvalHandler: nil,
            structuredApprovalHandler: nil,
            agentAppActionExecutor: nil,
            browserController: nil,
            resolver: resolver
        )

        await router.handle(requestJSON: "{")
        await router.handle(requestJSON: #"{"tool_name":"custom","params_json":"{}"}"#)

        XCTAssertTrue(resolver.calls.isEmpty)
    }

    func testDecodedToolRequestExecutionFailureResolvesOriginalRequestId() async throws {
        let resolver = CapturingToolExecutionResolver()
        let router = NapaxiToolRequestRouter(
            platformExecutor: nil,
            customExecutor: nil,
            approvalHandler: nil,
            structuredApprovalHandler: nil,
            agentAppActionExecutor: nil,
            browserController: nil,
            resolver: resolver
        )
        let requestJSON = try jsonString([
            "request_id": 88,
            "tool_name": "missing_tool",
            "params_json": "{}",
        ])

        await router.handle(requestJSON: requestJSON)

        XCTAssertEqual(resolver.calls.count, 1)
        XCTAssertEqual(resolver.calls.first?.requestId, 88)
        XCTAssertTrue(resolver.calls.first?.isError == true)
        XCTAssertTrue(resolver.calls.first?.resultJSON.contains("No host executor registered for tool missing_tool") == true)
    }
}

private final class CapturingApprovalHandler: NapaxiStructuredToolApprovalHandler {
    private let response: NapaxiHostToolApprovalResponse
    private(set) var lastRequest: NapaxiHostToolApprovalRequest?

    init(response: NapaxiHostToolApprovalResponse) {
        self.response = response
    }

    func approve(_ request: NapaxiHostToolApprovalRequest) async -> NapaxiHostToolApprovalResponse {
        lastRequest = request
        return response
    }
}

private final class LegacyApprovalHandler: NapaxiToolApprovalHandler {
    private let approved: Bool
    private(set) var lastToolName: String?
    private(set) var lastRequestJSON: String?

    init(approved: Bool) {
        self.approved = approved
    }

    func approve(toolName: String, requestJSON: String) async -> Bool {
        lastToolName = toolName
        lastRequestJSON = requestJSON
        return approved
    }
}

private final class CapturingActionExecutor: NapaxiAgentAppActionExecutor {
    private let resultJSON: String
    private(set) var lastRequestJSON: String?

    init(resultJSON: String) {
        self.resultJSON = resultJSON
    }

    func executeAgentAppAction(requestJSON: String) async -> String {
        lastRequestJSON = requestJSON
        return resultJSON
    }
}

private final class CapturingTypedActionExecutor: AgentAppActionExecutor {
    private(set) var lastRequest: NapaxiAgentAppActionRequest?

    func execute(_ request: NapaxiAgentAppActionRequest) async throws -> NapaxiAgentAppActionResult {
        lastRequest = request
        return NapaxiAgentAppActionResult(
            requestId: request.proposal.requestId,
            status: "succeeded",
            result: ["handled_by": .string("typed")],
            completedAt: "1970-01-01T00:00:00Z"
        )
    }
}

private final class CapturingMcToolExecutor: McToolExecutor {
    private(set) var calls: [(toolName: String, paramsJSON: String)] = []

    func execute(_ toolName: String, _ paramsJSON: String) async throws -> String {
        calls.append((toolName: toolName, paramsJSON: paramsJSON))
        return #"{"ok":true}"#
    }
}

private final class CapturingPlatformExecutor: NapaxiPlatformToolExecutor {
    private(set) var calls: [(name: String, params: [String: NapaxiJSONValue])] = []

    func executePlatformTool(name: String, params: [String: NapaxiJSONValue]) async throws -> NapaxiJSONValue {
        calls.append((name: name, params: params))
        return .object(["handled": .bool(true), "tool_name": .string(name)])
    }
}

private final class CapturingToolExecutionResolver: NapaxiToolExecutionResolver {
    private(set) var calls: [(requestId: UInt64, resultJSON: String, isError: Bool)] = []

    func resolveToolExecution(requestId: UInt64, resultJSON: String, isError: Bool) throws -> Bool {
        calls.append((requestId: requestId, resultJSON: resultJSON, isError: isError))
        return true
    }
}

private func jsonString(_ value: Any) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

private func decodeObject(_ value: String) throws -> [String: Any]? {
    let decoded = try JSONSerialization.jsonObject(with: Data(value.utf8))
    return decoded as? [String: Any]
}
