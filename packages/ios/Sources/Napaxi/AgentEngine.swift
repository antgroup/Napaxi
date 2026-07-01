import Foundation

public let napaxiCoreAgentEngineId = "napaxi_core"
public let externalHostAgentEngineId = "external_host"

open class AgentEngineExecutor {
    public init() {}

    open func startTurn(
        _ request: AgentEngineTurnRequest,
        tools: AgentEngineToolBroker
    ) async throws -> AgentEngineTurnResult {
        throw NapaxiError.unavailable("iOS AgentEngineExecutor is unsupported in v1")
    }

    open func cancel(runId: String, sessionKeyJson: String) async throws -> Bool {
        false
    }

    open func resume(
        _ request: AgentEngineTurnRequest,
        tools: AgentEngineToolBroker
    ) async throws -> AgentEngineTurnResult {
        AgentEngineTurnResult.error("Agent engine resume is unsupported")
    }
}

public struct AgentEngineTurnRequest: Codable, Equatable, Sendable {
    public var raw: [String: NapaxiJSONValue]

    public init(raw: [String: NapaxiJSONValue] = [:]) {
        self.raw = raw
    }

    public init(map: [String: NapaxiJSONValue]) {
        self.init(raw: map)
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> AgentEngineTurnRequest {
        AgentEngineTurnRequest(map: map)
    }

    public var engineId: String { raw["engine_id"]?.stringValue ?? externalHostAgentEngineId }
    public var engineProfileId: String { raw["engine_profile_id"]?.stringValue ?? "" }
    public var engineConfig: [String: NapaxiJSONValue] {
        guard case .object(let object)? = raw["engine_config"] else { return [:] }
        return object
    }
    public var runId: String { raw["run_id"]?.stringValue ?? "" }
    public var filesDir: String { raw["files_dir"]?.stringValue ?? "" }
    public var workspaceFilesDir: String { raw["workspace_files_dir"]?.stringValue ?? "" }
    public var accountId: String { raw["account_id"]?.stringValue ?? "" }
    public var agentId: String { raw["agent_id"]?.stringValue ?? "" }
    public var sessionKeyJson: String { raw["session_key_json"]?.stringValue ?? "{}" }
    public var message: String { raw["message"]?.stringValue ?? "" }
    public var attachmentsJson: String { raw["attachments_json"]?.stringValue ?? "[]" }
    public var configJson: String { raw["config_json"]?.stringValue ?? "{}" }

    public func toMap() -> [String: NapaxiJSONValue] { raw }
}

public struct AgentEngineTurnResult: Codable, Equatable, Sendable {
    public var events: [[String: NapaxiJSONValue]]

    public init(events: [[String: NapaxiJSONValue]] = []) {
        self.events = events
    }

    public static func response(_ content: String) -> AgentEngineTurnResult {
        AgentEngineTurnResult(events: [["type": .string("response"), "content": .string(content)]])
    }

    public static func error(_ message: String) -> AgentEngineTurnResult {
        AgentEngineTurnResult(events: [["type": .string("error"), "message": .string(message)]])
    }

    public static func fromEvents(_ events: [NapaxiChatEvent]) -> AgentEngineTurnResult {
        AgentEngineTurnResult(events: events.map { $0.toMap() })
    }

    public func toMap() -> [String: NapaxiJSONValue] {
        ["events": .array(events.map { .object($0) })]
    }
}

public struct AgentEngineRunEventRequest: Codable, Equatable, Sendable {
    public var raw: [String: NapaxiJSONValue]

    public init(
        runId: String,
        sessionKeyJson: String = "",
        event: [String: NapaxiJSONValue]
    ) {
        self.raw = [
            "run_id": .string(runId),
            "session_key_json": .string(sessionKeyJson),
            "event": .object(event),
        ]
    }

    public init(raw: [String: NapaxiJSONValue] = [:]) {
        self.raw = raw
    }

    public var runId: String { raw["run_id"]?.stringValue ?? "" }
    public var sessionKeyJson: String { raw["session_key_json"]?.stringValue ?? "" }
    public var event: [String: NapaxiJSONValue] {
        guard case .object(let object)? = raw["event"] else { return [:] }
        return object
    }

    public func toMap() -> [String: NapaxiJSONValue] { raw }
}

public struct AgentEngineRunEventResult: Codable, Equatable, Sendable {
    public var raw: [String: NapaxiJSONValue]

    public init(raw: [String: NapaxiJSONValue] = [:]) {
        self.raw = raw
    }

    public static func fromMap(_ map: [String: NapaxiJSONValue]) -> AgentEngineRunEventResult {
        AgentEngineRunEventResult(raw: map)
    }

    public var event: [String: NapaxiJSONValue] {
        guard case .object(let object)? = raw["event"] else { return [:] }
        return object
    }
    public var finalContent: String { raw["final_content"]?.stringValue ?? "" }
    public var isError: Bool { raw["is_error"]?.boolValue ?? false }
    public var completed: Bool { raw["completed"]?.boolValue ?? false }
}

public final class AgentEngineToolBroker {
    public init() {}

    public func listTools(
        agentId: String,
        accountId: String,
        sessionKeyJson: String? = nil
    ) async throws -> [NapaxiCustomToolDefinition] {
        throw NapaxiError.unavailable("iOS AgentEngineToolBroker is unsupported in v1")
    }

    public func callTool(
        callId: String,
        name: String,
        arguments: [String: NapaxiJSONValue],
        agentId: String,
        accountId: String,
        sessionKeyJson: String? = nil
    ) async throws -> AgentEngineToolCallResult {
        throw NapaxiError.unavailable("iOS AgentEngineToolBroker is unsupported in v1")
    }
}

public struct AgentEngineToolCallResult: Codable, Equatable, Sendable {
    public var output: String
    public var isError: Bool
    public var events: [NapaxiChatEvent]
    public var effect: String

    public init(
        output: String = "",
        isError: Bool = false,
        events: [NapaxiChatEvent] = [],
        effect: String = "unknown"
    ) {
        self.output = output
        self.isError = isError
        self.events = events
        self.effect = effect
    }
}

public func chatEventToMap(_ event: NapaxiChatEvent) -> [String: NapaxiJSONValue] {
    event.toMap()
}

public func agentEngineRunEvent(
    runId: String,
    sessionKeyJson: String = "",
    event: [String: NapaxiJSONValue]
) throws -> AgentEngineRunEventResult {
    let request = AgentEngineRunEventRequest(
        runId: runId,
        sessionKeyJson: sessionKeyJson,
        event: event
    )
    let raw = try agentEngineRunEvent(requestJson: try request.toMap().jsonString())
    return AgentEngineRunEventResult.fromMap(try decodeJsonObject(raw))
}
