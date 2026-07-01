import Foundation

public struct NapaxiRawAPI: Sendable {
    let handle: Int64

    public func call(
        namespace: String,
        method: String,
        payload: [String: NapaxiJSONValue] = [:]
    ) throws -> NapaxiJSONValue {
        try NapaxiNativeBridge.call(handle: handle, namespace: namespace, method: method, payload: payload)
    }

    public func listCapabilityDefinitions() throws -> NapaxiJSONValue {
        try call(namespace: "capability", method: "list_definitions")
    }

    public func listCapabilityStatus(profileJSON: String, selectionJSON: String) throws -> NapaxiJSONValue {
        try call(
            namespace: "capability",
            method: "list_status",
            payload: ["profile_json": .string(profileJSON), "selection_json": .string(selectionJSON)]
        )
    }

    public func listScenarioPacks() throws -> NapaxiJSONValue {
        try call(namespace: "capability", method: "list_scenarios")
    }

    public func installScenarioPack(packJSON: String) throws -> NapaxiJSONValue {
        try call(namespace: "capability", method: "install_scenario", payload: ["pack_json": .string(packJSON)])
    }

    public func removeScenarioPack(scenarioId: String) throws -> NapaxiJSONValue {
        try call(namespace: "capability", method: "remove_scenario", payload: ["scenario_id": .string(scenarioId)])
    }

    public func listScenarioStatus(profileJSON: String, selectionJSON: String) throws -> NapaxiJSONValue {
        try call(
            namespace: "capability",
            method: "list_scenario_status",
            payload: ["profile_json": .string(profileJSON), "selection_json": .string(selectionJSON)]
        )
    }

    public func resolveScenario(profileJSON: String, selectionJSON: String, scenarioId: String) throws -> NapaxiJSONValue {
        try call(
            namespace: "capability",
            method: "resolve_scenario",
            payload: ["profile_json": .string(profileJSON), "selection_json": .string(selectionJSON), "scenario_id": .string(scenarioId)]
        )
    }

    public func createSession(
        agentId: String = NapaxiEngine.defaultAgentId,
        channelType: String = "app",
        accountId: String = NapaxiEngine.defaultAccountId,
        existingThreadId: String? = nil
    ) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = [
            "agent_id": .string(agentId),
            "channel_type": .string(channelType),
            "account_id": .string(accountId),
        ]
        if let existingThreadId {
            payload["existing_thread_id"] = .string(existingThreadId)
        }
        return try call(namespace: "session", method: "create", payload: payload)
    }

    public func listSessions(
        agentId: String = NapaxiEngine.defaultAgentId,
        accountId: String = NapaxiEngine.defaultAccountId
    ) throws -> NapaxiJSONValue {
        try call(
            namespace: "session",
            method: "list",
            payload: ["agent_id": .string(agentId), "account_id": .string(accountId)]
        )
    }

    public func listAgents() throws -> NapaxiJSONValue {
        try call(namespace: "agent", method: "list")
    }

    public func getOrCreateAgent(_ agentId: String) throws -> NapaxiJSONValue {
        try call(namespace: "agent", method: "get_or_create", payload: ["agent_id": .string(agentId)])
    }

    public func listAutomationJobs(filterJSON: String = "{}") throws -> NapaxiJSONValue {
        try call(namespace: "automation", method: "list_jobs", payload: ["filter_json": .string(filterJSON)])
    }

    public func listAgentAppPackages() throws -> NapaxiJSONValue {
        try call(namespace: "agent_app", method: "list_packages")
    }

    public func registerAgentAppPackage(packageJSON: String) throws -> NapaxiJSONValue {
        try call(namespace: "agent_app", method: "register_package", payload: ["package_json": .string(packageJSON)])
    }
}
