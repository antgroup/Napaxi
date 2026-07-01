import Foundation

protocol NapaxiToolExecutionResolver: AnyObject {
    func resolveToolExecution(requestId: UInt64, resultJSON: String, isError: Bool) throws -> Bool
}

private final class NapaxiNativeToolExecutionResolver: NapaxiToolExecutionResolver {
    func resolveToolExecution(requestId: UInt64, resultJSON: String, isError: Bool) throws -> Bool {
        try NapaxiNativeBridge.resolveToolExecution(
            requestId: requestId,
            resultJSON: resultJSON,
            isError: isError
        )
    }
}

public final class NapaxiToolRequestRouter: @unchecked Sendable {
    private let platformExecutor: NapaxiPlatformToolExecutor?
    private weak var customExecutor: NapaxiToolExecutor?
    private weak var approvalHandler: NapaxiToolApprovalHandler?
    private weak var structuredApprovalHandler: NapaxiStructuredToolApprovalHandler?
    private weak var agentAppActionExecutor: NapaxiAgentAppActionExecutor?
    private weak var browserController: NapaxiBrowserController?
    private let resolver: NapaxiToolExecutionResolver

    init(
        platformExecutor: NapaxiPlatformToolExecutor?,
        customExecutor: NapaxiToolExecutor?,
        approvalHandler: NapaxiToolApprovalHandler?,
        structuredApprovalHandler: NapaxiStructuredToolApprovalHandler?,
        agentAppActionExecutor: NapaxiAgentAppActionExecutor?,
        browserController: NapaxiBrowserController?,
        resolver: NapaxiToolExecutionResolver = NapaxiNativeToolExecutionResolver()
    ) {
        self.platformExecutor = platformExecutor
        self.customExecutor = customExecutor
        self.approvalHandler = approvalHandler
        self.structuredApprovalHandler = structuredApprovalHandler
        self.agentAppActionExecutor = agentAppActionExecutor
        self.browserController = browserController
        self.resolver = resolver
    }

    func handle(requestJSON: String) async {
        let request: ToolRequest
        do {
            request = try JSONDecoder().decode(ToolRequest.self, from: Data(requestJSON.utf8))
        } catch {
            return
        }

        do {
            let result = try await execute(request)
            _ = try resolver.resolveToolExecution(
                requestId: request.requestId,
                resultJSON: result,
                isError: false
            )
        } catch {
            let errorJSON = #"{"error":"\#(String(describing: error).replacingOccurrences(of: "\"", with: "\\\""))"}"#
            _ = try? resolver.resolveToolExecution(
                requestId: request.requestId,
                resultJSON: errorJSON,
                isError: true
            )
        }
    }

    func executeForTesting(requestJSON: String) async throws -> String {
        let request = try JSONDecoder().decode(ToolRequest.self, from: Data(requestJSON.utf8))
        return try await execute(request)
    }

    private func execute(_ request: ToolRequest) async throws -> String {
        if request.toolName == "__napaxi_approval__" {
            return try await handleApprovalRequest(request)
        }

        if request.toolName == "ask_human", let approvalHandler {
            let approved = await approvalHandler.approve(
                toolName: request.toolName,
                requestJSON: request.paramsJSON
            )
            return try ["approved": NapaxiJSONValue.bool(approved)].jsonString()
        }

        if isBrowserTool(request.toolName), let browserController {
            return try await browserController.executeBrowserTool(
                toolName: request.toolName,
                paramsJSON: request.paramsJSON
            )
        }

        if isAgentAppActionDispatchTool(request.toolName), let agentAppActionExecutor {
            return await agentAppActionExecutor.executeAgentAppAction(requestJSON: request.paramsJSON)
        }

        if isPlatformTool(request.toolName), let platformExecutor {
            let params = try NapaxiDefaultPlatformToolExecutor.params(
                from: request.paramsJSON,
                forTool: request.toolName
            )
            let value = try await platformExecutor.executePlatformTool(
                name: request.toolName,
                params: params
            )
            return try NapaxiRawJSON(value).jsonString()
        }

        if let customExecutor {
            let result = await customExecutor.execute(
                toolName: request.toolName,
                paramsJSON: request.paramsJSON,
                context: request.context
            )
            switch result {
            case .success(let output):
                return output
            case .failure(let error):
                throw error
            }
        }

        throw NapaxiError.unavailable("No host executor registered for tool \(request.toolName)")
    }

    private func handleApprovalRequest(_ request: ToolRequest) async throws -> String {
        let approvalRequest = try decodeApprovalRequest(request)
        if let structuredApprovalHandler {
            return try await structuredApprovalHandler.approve(approvalRequest).jsonString()
        }
        if let approvalHandler {
            let approved = await approvalHandler.approve(
                toolName: approvalRequest.toolName,
                requestJSON: approvalRequest.parametersJSON
            )
            return try NapaxiHostToolApprovalResponse(
                approved: approved,
                message: approved ? nil : "Tool execution denied by user"
            ).jsonString()
        }
        return try NapaxiHostToolApprovalResponse(
            approved: false,
            message: "No tool approval handler registered"
        ).jsonString()
    }

    private func decodeApprovalRequest(_ request: ToolRequest) throws -> NapaxiHostToolApprovalRequest {
        let value = try NapaxiRawJSON(jsonString: request.paramsJSON).value
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Approval request parameters must be a JSON object")
        }
        return NapaxiHostToolApprovalRequest(
            requestId: request.requestId,
            toolName: object["tool_name"]?.stringValue ?? "",
            description: object["description"]?.stringValue ?? "",
            parametersJSON: object["parameters"]?.stringValue ?? "{}",
            allowAlways: object["allow_always"]?.boolValue ?? false
        )
    }

    private func isAgentAppActionDispatchTool(_ name: String) -> Bool {
        name == "__napaxi_agent_app_action__" || name.hasPrefix("app_action_")
    }

    private func isBrowserTool(_ name: String) -> Bool {
        NapaxiBrowserToolProvider.isBrowserTool(name)
    }

    private func isPlatformTool(_ name: String) -> Bool {
        [
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
        ].contains(name)
    }

    private struct ToolRequest: Decodable {
        var requestId: UInt64
        var toolName: String
        var paramsJSON: String
        var context: NapaxiJSONValue?

        enum CodingKeys: String, CodingKey {
            case requestId = "request_id"
            case toolName = "tool_name"
            case paramsJSON = "params_json"
            case context
        }
    }
}
