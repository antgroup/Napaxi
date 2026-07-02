import Foundation

public protocol NapaxiCoreAPI {
    var rawAPI: NapaxiRawAPI { get }
}

extension NapaxiCoreAPI {
    func call(_ namespace: String, _ method: String, _ payload: [String: NapaxiJSONValue] = [:]) throws -> NapaxiJSONValue {
        try rawAPI.call(namespace: namespace, method: method, payload: payload)
    }
}

public struct NapaxiToolAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    public func updateCustomTools(_ tools: [NapaxiCustomToolDefinition]) throws -> Bool {
        try NapaxiNativeBridge.updateCustomTools(
            handle: rawAPI.handle,
            toolsJSON: NapaxiCustomToolDefinition.jsonString(for: tools)
        )
    }
    public func updateCustomToolsJSON(_ toolsJSON: String) throws -> Bool {
        try NapaxiNativeBridge.updateCustomTools(handle: rawAPI.handle, toolsJSON: toolsJSON)
    }
    public func startRequestListener() {
        // Swift registers host tool routing during NapaxiEngine.create(...).
    }
    public func mobilePlatformToolDescriptors() throws -> NapaxiJSONValue { try call("tools", "mobile_platform_tool_descriptors") }
    public func isMobilePlatformTool(_ name: String) throws -> NapaxiJSONValue { try call("tools", "is_mobile_platform_tool", ["name": .string(name)]) }
    public func browserToolDescriptors() throws -> NapaxiJSONValue { try call("tools", "browser_tool_descriptors") }
    public func isBrowserTool(_ name: String) throws -> NapaxiJSONValue { try call("tools", "is_browser_tool", ["name": .string(name)]) }
    public func mobilePlatformToolDefinitions() throws -> [NapaxiCustomToolDefinition] {
        try Self.toolDefinitions(from: mobilePlatformToolDescriptors())
    }
    public func isMobilePlatformToolBool(_ name: String) throws -> Bool {
        try isMobilePlatformTool(name).requiredBool()
    }
    public func browserToolDefinitions() throws -> [NapaxiCustomToolDefinition] {
        try Self.toolDefinitions(from: browserToolDescriptors())
    }
    public func isBrowserToolBool(_ name: String) throws -> Bool {
        try isBrowserTool(name).requiredBool()
    }
    public func answerHumanRequest(requestId: String, response: String) throws -> NapaxiJSONValue {
        try call("tools", "answer_human_request", ["request_id": .string(requestId), "response": .string(response)])
    }

    public static func toolDefinitions(from value: NapaxiJSONValue) throws -> [NapaxiCustomToolDefinition] {
        try decodeJsonObjectListFromValue(value) { object in
            try object.validateCustomToolDefinitionObject()
            return NapaxiCustomToolDefinition.fromJson(object)
        }
        .filter { !$0.name.isEmpty }
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func validateCustomToolDefinitionObject() throws {
        try validateCustomToolOptionalString("name")
        try validateCustomToolOptionalString("description")
        try validateCustomToolOptionalString("effect")
    }

    func validateCustomToolOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected custom tool field '\(key)' to be a string")
        }
    }
}

public struct NapaxiChatAPI: Sendable {
    private let engine: NapaxiEngine

    init(engine: NapaxiEngine) {
        self.engine = engine
    }

    public func send(
        _ message: String,
        attachments: [NapaxiAttachment] = [],
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        try engine.sendStream(message, attachments: attachments, maxIterations: maxIterations)
    }

    public func sendToSession(
        _ sessionKey: NapaxiSessionKey,
        _ message: String,
        attachments: [NapaxiAttachment] = [],
        maxIterations: Int = NapaxiChatDefaults.maxIterations,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> {
        try engine.sendToSessionStream(
            agentId: agentId,
            sessionKey: sessionKey,
            message: message,
            attachments: attachments,
            maxIterations: maxIterations
        )
    }
}

public struct NapaxiCapabilityAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    public let defaultProfile: NapaxiCapabilityProfile?

    public init(rawAPI: NapaxiRawAPI, defaultProfile: NapaxiCapabilityProfile? = nil) {
        self.rawAPI = rawAPI
        self.defaultProfile = defaultProfile
    }

    public func listDefinitions() throws -> [NapaxiCapabilityDefinition] {
        try Self.decodeDefinitions(from: listDefinitionsJSON())
    }
    public func listDefinitionsJSON() throws -> NapaxiJSONValue { try call("capability", "list_definitions") }
    public func listStatuses(
        profile: NapaxiCapabilityProfile? = nil,
        selection: NapaxiCapabilitySelection? = nil
    ) throws -> [NapaxiCapabilityStatus] {
        try Self.decodeStatuses(from: listStatusJSON(
            profileJSON: try statusProfileJSON(profile),
            selectionJSON: selection?.jsonString() ?? "{}"
        ))
    }
    func statusProfileJSON(_ profile: NapaxiCapabilityProfile?) throws -> String {
        try (profile ?? defaultProfile)?.jsonString() ?? "{}"
    }
    public func listStatusJSON(profileJSON: String, selectionJSON: String) throws -> NapaxiJSONValue {
        try call("capability", "list_status", ["profile_json": .string(profileJSON), "selection_json": .string(selectionJSON)])
    }
    public func listStatusesJSON(profileJSON: String, selectionJSON: String) throws -> NapaxiJSONValue {
        try listStatusJSON(profileJSON: profileJSON, selectionJSON: selectionJSON)
    }
    public func listStatusesJSON(
        profile: NapaxiCapabilityProfile? = nil,
        selection: NapaxiCapabilitySelection? = nil
    ) throws -> NapaxiJSONValue {
        try listStatusJSON(
            profileJSON: try statusProfileJSON(profile),
            selectionJSON: selection?.jsonString() ?? "{}"
        )
    }
    public func listScenarioPacks() throws -> [NapaxiScenarioPack] {
        try Self.decodeScenarioPacks(from: listScenarioPacksJSON())
    }
    public func listScenarioPacksJSON() throws -> NapaxiJSONValue {
        try call("capability", "list_scenarios")
    }
    public func installScenarioPack(_ pack: NapaxiScenarioPack) throws -> NapaxiScenarioPackInstallResult? {
        try installScenarioPackJSON(packJSON: pack.jsonString()).decodedScenarioPackInstallResult()
    }
    public func installScenarioPackJSON(packJSON: String) throws -> NapaxiJSONValue {
        try call("capability", "install_scenario", ["pack_json": .string(packJSON)])
    }
    public func removeScenarioPack(_ scenarioId: String) throws -> NapaxiScenarioPackRemovalResult? {
        try removeScenarioPackJSON(scenarioId: scenarioId).decodedScenarioPackRemovalResult()
    }
    public func removeScenarioPackJSON(scenarioId: String) throws -> NapaxiJSONValue {
        try call("capability", "remove_scenario", ["scenario_id": .string(scenarioId)])
    }
    public func listScenarioStatuses(
        profile: NapaxiCapabilityProfile? = nil,
        selection: NapaxiCapabilitySelection? = nil
    ) throws -> [NapaxiScenarioStatus] {
        try Self.decodeScenarioStatuses(from: listScenarioStatusJSON(
            profileJSON: try statusProfileJSON(profile),
            selectionJSON: selection?.jsonString() ?? "{}"
        ))
    }
    public func listScenarioStatusJSON(profileJSON: String, selectionJSON: String) throws -> NapaxiJSONValue {
        try call("capability", "list_scenario_status", ["profile_json": .string(profileJSON), "selection_json": .string(selectionJSON)])
    }
    public func resolveScenario(
        _ scenarioId: String,
        profile: NapaxiCapabilityProfile? = nil,
        selection: NapaxiCapabilitySelection? = nil
    ) throws -> NapaxiScenarioResolution? {
        try resolveScenarioJSON(
            scenarioId: scenarioId,
            profileJSON: try statusProfileJSON(profile),
            selectionJSON: selection?.jsonString() ?? "{}"
        ).decodedScenarioResolution()
    }
    public func resolveScenarioJSON(
        scenarioId: String,
        profileJSON: String,
        selectionJSON: String
    ) throws -> NapaxiJSONValue {
        try call("capability", "resolve_scenario", ["scenario_id": .string(scenarioId), "profile_json": .string(profileJSON), "selection_json": .string(selectionJSON)])
    }
    public func providerCapabilityId(_ provider: String) throws -> String {
        try call("capability", "provider_capability_id", ["provider": .string(provider)]).requiredString()
    }
    public func agentEngineCapabilityId(_ engineId: String) throws -> String {
        try call("capability", "agent_engine_capability_id", ["engine_id": .string(engineId)]).requiredString()
    }
    public func toolCapabilityId(_ toolName: String) throws -> String {
        try call("capability", "tool_capability_id", ["tool_name": .string(toolName)]).requiredString()
    }

    static func decodeDefinitions(from value: NapaxiJSONValue) throws -> [NapaxiCapabilityDefinition] {
        guard case .array = value else { return [] }
        return try decodeJsonObjectListFromValue(value) { object in
            try object.validateCapabilityDefinitionObject()
            return NapaxiCapabilityDefinition.fromJson(object)
        }
    }

    static func decodeStatuses(from value: NapaxiJSONValue) throws -> [NapaxiCapabilityStatus] {
        guard case .array = value else { return [] }
        return try decodeJsonObjectListFromValue(value) { object in
            try object.validateCapabilityStatusObject()
            return NapaxiCapabilityStatus.fromJson(object)
        }
    }

    static func decodeScenarioPacks(from value: NapaxiJSONValue) throws -> [NapaxiScenarioPack] {
        guard case .array = value else { return [] }
        return try decodeJsonObjectListFromValue(value) { object in
            try NapaxiJSONValue.object(object).decodedObject(of: NapaxiScenarioPack.self)
        }
    }

    static func decodeScenarioStatuses(from value: NapaxiJSONValue) throws -> [NapaxiScenarioStatus] {
        guard case .array = value else { return [] }
        return try decodeJsonObjectListFromValue(value) { object in
            try NapaxiJSONValue.object(object).decodedObject(of: NapaxiScenarioStatus.self)
        }
    }
}

private extension NapaxiJSONValue {
    func channelReceiptObject() throws -> [String: NapaxiJSONValue] {
        guard case .object(let object) = self else {
            throw NapaxiError.invalidJSON("Expected channel receipt object")
        }
        return object
    }

    func decodedScenarioResolution() throws -> NapaxiScenarioResolution? {
        guard case .object(let object) = self, object["error"] == nil else { return nil }
        return try decodedObject(of: NapaxiScenarioResolution.self)
    }

    func decodedScenarioPackInstallResult() throws -> NapaxiScenarioPackInstallResult? {
        guard case .object(let object) = self, object["error"] == nil else { return nil }
        return try decodedObject(of: NapaxiScenarioPackInstallResult.self)
    }

    func decodedScenarioPackRemovalResult() throws -> NapaxiScenarioPackRemovalResult? {
        guard case .object(let object) = self, object["error"] == nil else { return nil }
        return try decodedObject(of: NapaxiScenarioPackRemovalResult.self)
    }
}

private extension Dictionary where Key == String, Value == NapaxiJSONValue {
    func validateCapabilityDefinitionObject() throws {
        try validateCapabilityOptionalString("id")
        try validateCapabilityOptionalString("kind")
        try validateCapabilityOptionalString("version")
        try validateCapabilityOptionalArray("platforms")
        try validateCapabilityOptionalString("risk")
        try validateCapabilityOptionalArray("requirements")
        try validateCapabilityOptionalBool("default_enabled")
        try validateCapabilityOptionalString("activation")
    }

    func validateCapabilityStatusObject() throws {
        if let value = self["definition"], value != .null {
            guard case .object(let definition) = value else {
                throw NapaxiError.invalidJSON("Expected capability field 'definition' to be an object")
            }
            try definition.validateCapabilityDefinitionObject()
        }
        try validateCapabilityOptionalBool("registered")
        try validateCapabilityOptionalBool("available")
        try validateCapabilityOptionalBool("enabled")
        try validateCapabilityOptionalString("unavailable_reason")
    }

    func validateCapabilityOptionalString(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .string = value else {
            throw NapaxiError.invalidJSON("Expected capability field '\(key)' to be a string")
        }
    }

    func validateCapabilityOptionalBool(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .bool = value else {
            throw NapaxiError.invalidJSON("Expected capability field '\(key)' to be a bool")
        }
    }

    func validateCapabilityOptionalArray(_ key: String) throws {
        guard let value = self[key], value != .null else { return }
        guard case .array = value else {
            throw NapaxiError.invalidJSON("Expected capability field '\(key)' to be an array")
        }
    }
}

public struct NapaxiAutomationAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    public func createJob(_ job: NapaxiAutomationJob) throws -> NapaxiAutomationJob {
        try Self.decodeJob(from: createJobJSON(jobJSON: job.jsonString()))
    }
    public func createAutomationJob(_ job: NapaxiAutomationJob) throws -> NapaxiAutomationJob { try createJob(job) }
    public func createJobJSON(jobJSON: String) throws -> NapaxiJSONValue { try call("automation", "create_job", ["job_json": .string(jobJSON)]) }
    public func updateJob(jobId: String, patch: [String: NapaxiJSONValue]) throws -> NapaxiAutomationJob {
        try Self.decodeJob(from: updateJobJSON(jobId: jobId, patchJSON: patch.jsonString()))
    }
    public func updateAutomationJob(_ jobId: String, _ patch: [String: NapaxiJSONValue]) throws -> NapaxiAutomationJob {
        try updateJob(jobId: jobId, patch: patch)
    }
    public func updateJobJSON(jobId: String, patchJSON: String) throws -> NapaxiJSONValue {
        try call("automation", "update_job", ["job_id": .string(jobId), "patch_json": .string(patchJSON)])
    }
    public func deleteJob(_ jobId: String) throws -> Bool {
        try call("automation", "delete_job", ["job_id": .string(jobId)]).requiredBool()
    }
    public func deleteAutomationJob(_ jobId: String) throws -> Bool { try deleteJob(jobId) }
    public func listJobs(accountId: String? = nil, agentId: String? = nil, enabled: Bool? = nil) throws -> [NapaxiAutomationJob] {
        var filter: [String: NapaxiJSONValue] = [:]
        if let accountId { filter["accountId"] = .string(accountId) }
        if let agentId { filter["agentId"] = .string(agentId) }
        if let enabled { filter["enabled"] = .bool(enabled) }
        return try Self.decodeJobs(from: listJobsJSON(filterJSON: filter.jsonString()))
    }
    public func listAutomationJobs(accountId: String? = nil, agentId: String? = nil, enabled: Bool? = nil) throws -> [NapaxiAutomationJob] {
        try listJobs(accountId: accountId, agentId: agentId, enabled: enabled)
    }
    public func listJobsJSON(filterJSON: String = "{}") throws -> NapaxiJSONValue { try call("automation", "list_jobs", ["filter_json": .string(filterJSON)]) }
    public func getJob(_ jobId: String) throws -> NapaxiAutomationJob? {
        try Self.decodeJobOrNil(from: getJobJSON(jobId))
    }
    public func getAutomationJob(_ jobId: String) throws -> NapaxiAutomationJob? { try getJob(jobId) }
    public func getJobJSON(_ jobId: String) throws -> NapaxiJSONValue { try call("automation", "get_job", ["job_id": .string(jobId)]) }
    public func runJob(_ jobId: String, mode: String = "manual") throws -> NapaxiAutomationRun {
        try Self.decodeRun(from: runJobJSON(jobId, mode: mode))
    }
    public func runAutomationJob(_ jobId: String, mode: String = "manual") throws -> NapaxiAutomationRun {
        try runJob(jobId, mode: mode)
    }
    public func runJobJSON(_ jobId: String, mode: String = "manual") throws -> NapaxiJSONValue {
        try call("automation", "run_job", ["job_id": .string(jobId), "mode": .string(mode)])
    }
    public func listRuns(jobId: String? = nil, limit: Int = 200, offset: Int = 0) throws -> [NapaxiAutomationRun] {
        try Self.decodeRuns(from: listRunsJSON(jobId: jobId, limit: limit, offset: offset))
    }
    public func listRunsJSON(jobId: String? = nil, limit: Int = 200, offset: Int = 0) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["limit": .number(Double(limit)), "offset": .number(Double(offset))]
        if let jobId { payload["job_id"] = .string(jobId) }
        return try call("automation", "list_runs", payload)
    }
    public func listAutomationRuns(jobId: String? = nil, limit: Int = 200, offset: Int = 0) throws -> [NapaxiAutomationRun] {
        try listRuns(jobId: jobId, limit: limit, offset: offset)
    }
    public func nextWake() throws -> NapaxiAutomationWake? {
        try Self.decodeWakeOrNil(from: nextWakeJSON())
    }
    public func getNextAutomationWake() throws -> NapaxiAutomationWake? { try nextWake() }
    public func nextWakeJSON() throws -> NapaxiJSONValue { try call("automation", "next_wake") }
    public func recordWake(jobId: String, source: String) throws -> NapaxiAutomationRun {
        try Self.decodeRun(from: recordWakeJSON(jobId: jobId, source: source))
    }
    public func recordAutomationWake(_ jobId: String, _ source: String) throws -> NapaxiAutomationRun {
        try recordWake(jobId: jobId, source: source)
    }
    public func recordAutomationWake(jobId: String, source: String) throws -> NapaxiAutomationRun {
        try recordWake(jobId: jobId, source: source)
    }
    public func recordWakeJSON(jobId: String, source: String) throws -> NapaxiJSONValue {
        try call("automation", "record_wake", ["job_id": .string(jobId), "source": .string(source)])
    }

    static func decodeJob(from value: NapaxiJSONValue) throws -> NapaxiAutomationJob {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected automation job object")
        }
        return try value.decodedObject(of: NapaxiAutomationJob.self)
    }

    static func decodeJobOrNil(from value: NapaxiJSONValue) throws -> NapaxiAutomationJob? {
        guard case .object(let object) = value, object["error"] == nil else {
            return nil
        }
        return try value.decodedObject(of: NapaxiAutomationJob.self)
    }

    static func decodeRun(from value: NapaxiJSONValue) throws -> NapaxiAutomationRun {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected automation run object")
        }
        return try value.decodedObject(of: NapaxiAutomationRun.self)
    }

    static func decodeJobs(from value: NapaxiJSONValue) throws -> [NapaxiAutomationJob] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiAutomationJob.self)
    }

    static func decodeRuns(from value: NapaxiJSONValue) throws -> [NapaxiAutomationRun] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiAutomationRun.self)
    }

    static func decodeWakeOrNil(from value: NapaxiJSONValue) throws -> NapaxiAutomationWake? {
        guard case .object = value else { return nil }
        return try value.decodedObject(of: NapaxiAutomationWake.self)
    }
}

public struct NapaxiA2AAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI

    public func generateLocalPairingSecret(byteLength: Int = 16) -> String {
        NapaxiA2APairing.generateLocalPairingSecret(byteLength: byteLength)
    }

    public func normalizePairingSecret(_ value: String) -> String {
        NapaxiA2APairing.normalizePairingSecret(value)
    }

    public func formatPairingSecret(_ value: String) -> String {
        NapaxiA2APairing.formatPairingSecret(value)
    }

    public func pairingCodeFromIdentity(peerId: String, publicKey: String) -> String {
        NapaxiA2APairing.pairingCodeFromIdentity(peerId: peerId, publicKey: publicKey)
    }

    public func pairingKey(_ peer: NapaxiA2ALocalPeerAdvertisement) -> String {
        NapaxiA2APairing.pairingKey(peerId: peer.peerId, publicKey: peer.publicKey)
    }

    public func deriveLocalSharedSecret(
        localPeerId: String,
        localPublicKey: String,
        localPairingSecret: String,
        peer: NapaxiA2ALocalPeerAdvertisement,
        remotePairingSecret: String
    ) -> String {
        NapaxiA2APairing.deriveLocalSharedSecret(
            localPeerId: localPeerId,
            localPublicKey: localPublicKey,
            localPairingSecret: localPairingSecret,
            remotePeerId: peer.peerId,
            remotePublicKey: peer.publicKey,
            remotePairingSecret: remotePairingSecret
        )
    }

    public func agentCard(agentId: String = "") throws -> NapaxiA2AAgentCard {
        try Self.decodeAgentCard(from: agentCardJSON(agentId: agentId))
    }

    public func agentCardJSON(agentId: String = "") throws -> NapaxiJSONValue {
        try call("a2a", "agent_card", ["agent_id": .string(agentId)])
    }

    public func createPeerInvite(
        _ agentId: String,
        options: [String: NapaxiJSONValue] = [:]
    ) throws -> NapaxiA2APeerInvite {
        try Self.decodePeerInvite(from: createPeerInviteJSON(agentId: agentId, optionsJSON: options.jsonString()))
    }

    public func createPeerInviteJSON(agentId: String, optionsJSON: String = "{}") throws -> NapaxiJSONValue {
        try call("a2a", "create_peer_invite", [
            "agent_id": .string(agentId),
            "options_json": .string(optionsJSON),
        ])
    }

    public func acceptPeerInvite(_ envelope: NapaxiA2ADeepLinkEnvelope) throws -> NapaxiA2APeer {
        try Self.decodePeer(from: acceptPeerInviteJSON(envelopeJSON: envelope.jsonString()))
    }

    public func acceptPeerInviteJSON(envelopeJSON: String) throws -> NapaxiJSONValue {
        try call("a2a", "accept_peer_invite", ["envelope_json": .string(envelopeJSON)])
    }

    public func listPeers(agentId: String = "") throws -> [NapaxiA2APeer] {
        try Self.decodePeers(from: listPeersJSON(agentId: agentId))
    }

    public func listPeersJSON(agentId: String = "") throws -> NapaxiJSONValue {
        try call("a2a", "list_peers", ["agent_id": .string(agentId)])
    }

    public func deletePeer(_ peerId: String) throws -> Bool {
        try deletePeerJSON(peerId).requiredBool()
    }

    public func deletePeerJSON(_ peerId: String) throws -> NapaxiJSONValue {
        try call("a2a", "delete_peer", ["peer_id": .string(peerId)])
    }

    public func openPeerSession(
        peer: NapaxiA2APeer,
        transport: String = "lan_websocket",
        endpoint: String = ""
    ) throws -> NapaxiA2APeerSession {
        let peerJSON = try peer.toJson().jsonString()
        return try Self.decodePeerSession(from: openPeerSessionJSON(
            peerJSON: peerJSON,
            transport: transport,
            endpoint: endpoint
        ))
    }

    public func openPeerSessionJSON(peerJSON: String, transport: String = "lan_websocket", endpoint: String = "") throws -> NapaxiJSONValue {
        try call("a2a", "open_peer_session", [
            "peer_json": .string(peerJSON),
            "transport": .string(transport),
            "endpoint": .string(endpoint),
        ])
    }

    public func listPeerSessions(peerId: String = "") throws -> [NapaxiA2APeerSession] {
        try Self.decodePeerSessions(from: listPeerSessionsJSON(peerId: peerId))
    }

    public func listPeerSessionsJSON(peerId: String = "") throws -> NapaxiJSONValue {
        try call("a2a", "list_peer_sessions", ["peer_id": .string(peerId)])
    }

    public func createTaskMessage(
        sessionId: String,
        message: String,
        options: [String: NapaxiJSONValue] = [:]
    ) throws -> NapaxiA2APeerMessage {
        try Self.decodePeerMessage(from: createTaskMessageJSON(
            sessionId: sessionId,
            message: message,
            optionsJSON: options.jsonString()
        ))
    }

    public func createTaskMessageJSON(sessionId: String, message: String, optionsJSON: String = "{}") throws -> NapaxiJSONValue {
        try call("a2a", "create_task_message", [
            "session_id": .string(sessionId),
            "message": .string(message),
            "options_json": .string(optionsJSON),
        ])
    }

    public func createTaskProgressMessage(
        sessionId: String,
        taskId: String,
        message: String,
        progress: [String: NapaxiJSONValue] = [:]
    ) throws -> NapaxiA2APeerMessage {
        try Self.decodePeerMessage(from: createTaskProgressMessageJSON(
            sessionId: sessionId,
            taskId: taskId,
            message: message,
            progressJSON: progress.jsonString()
        ))
    }

    public func createTaskProgressMessageJSON(
        sessionId: String,
        taskId: String,
        message: String,
        progressJSON: String = "{}"
    ) throws -> NapaxiJSONValue {
        try call("a2a", "create_task_progress_message", [
            "session_id": .string(sessionId),
            "task_id": .string(taskId),
            "message": .string(message),
            "progress_json": .string(progressJSON),
        ])
    }

    public func createTaskResultMessage(
        sessionId: String,
        taskId: String,
        result: [String: NapaxiJSONValue] = [:]
    ) throws -> NapaxiA2APeerMessage {
        try Self.decodePeerMessage(from: createTaskResultMessageJSON(
            sessionId: sessionId,
            taskId: taskId,
            resultJSON: result.jsonString()
        ))
    }

    public func createTaskResultMessageJSON(
        sessionId: String,
        taskId: String,
        resultJSON: String = "{}"
    ) throws -> NapaxiJSONValue {
        try call("a2a", "create_task_result_message", [
            "session_id": .string(sessionId),
            "task_id": .string(taskId),
            "result_json": .string(resultJSON),
        ])
    }

    public func recordPeerMessage(
        _ message: NapaxiA2APeerMessage,
        source: String = "local_transport"
    ) throws -> NapaxiA2ADeliveryRecord {
        try Self.decodeDeliveryRecord(from: recordPeerMessageJSON(messageJSON: message.jsonString(), source: source))
    }

    public func recordPeerMessageJSON(messageJSON: String, source: String = "local_transport") throws -> NapaxiJSONValue {
        try call("a2a", "record_peer_message", [
            "message_json": .string(messageJSON),
            "source": .string(source),
        ])
    }

    public func recordDeliveryStatus(
        _ message: NapaxiA2APeerMessage,
        status: String,
        error: String = ""
    ) throws -> NapaxiA2ADeliveryRecord {
        try Self.decodeDeliveryRecord(from: recordDeliveryStatusJSON(
            messageJSON: message.jsonString(),
            status: status,
            error: error
        ))
    }

    public func recordDeliveryStatusJSON(
        messageJSON: String,
        status: String,
        error: String = ""
    ) throws -> NapaxiJSONValue {
        try call("a2a", "record_delivery_status", [
            "message_json": .string(messageJSON),
            "status": .string(status),
            "error": .string(error),
        ])
    }

    public func listPeerMessages(sessionId: String, limit: Int = 100, offset: Int = 0) throws -> [NapaxiA2APeerMessage] {
        try Self.decodePeerMessages(from: listPeerMessagesJSON(sessionId: sessionId, limit: limit, offset: offset))
    }

    public func listPeerMessagesJSON(sessionId: String, limit: Int = 100, offset: Int = 0) throws -> NapaxiJSONValue {
        try call("a2a", "list_peer_messages", [
            "session_id": .string(sessionId),
            "limit": .number(Double(limit)),
            "offset": .number(Double(offset)),
        ])
    }

    public func listDeliveryRecords(sessionId: String, limit: Int = 100, offset: Int = 0) throws -> [NapaxiA2ADeliveryRecord] {
        try Self.decodeDeliveryRecords(from: listDeliveryRecordsJSON(sessionId: sessionId, limit: limit, offset: offset))
    }

    public func listDeliveryRecordsJSON(sessionId: String, limit: Int = 100, offset: Int = 0) throws -> NapaxiJSONValue {
        try call("a2a", "list_delivery_records", [
            "session_id": .string(sessionId),
            "limit": .number(Double(limit)),
            "offset": .number(Double(offset)),
        ])
    }

    public var localTransportEvents: [NapaxiA2ALocalTransportEvent] {
        NapaxiA2ALocalTransport.shared(for: rawAPI).localTransportEvents()
    }

    public func localTransportStatus() throws -> NapaxiA2ALocalTransportStatus {
        NapaxiA2ALocalTransport.shared(for: rawAPI).status()
    }

    public func checkLocalTransportPermission() throws -> Bool {
        NapaxiA2ALocalTransport.shared(for: rawAPI).checkPermission()
    }

    public func requestLocalTransportPermission() async throws -> Bool {
        await NapaxiA2ALocalTransport.shared(for: rawAPI).requestPermission()
    }

    public func startLocalTransport(
        peerId: String = "",
        agentId: String = "",
        displayName: String = "",
        publicKey: String = ""
    ) throws -> NapaxiA2ALocalTransportStatus {
        NapaxiA2ALocalTransport.shared(for: rawAPI).start(
            peerId: peerId,
            agentId: agentId,
            displayName: displayName,
            publicKey: publicKey
        )
    }

    public func stopLocalTransport() throws -> NapaxiA2ALocalTransportStatus {
        NapaxiA2ALocalTransport.shared(for: rawAPI).stop()
    }

    public func discoverLocalPeers(timeoutMs: Int = 5000) throws -> [NapaxiA2ALocalPeerAdvertisement] {
        NapaxiA2ALocalTransport.shared(for: rawAPI).discover(timeoutMs: timeoutMs)
    }

    public func sendPeerMessage(
        _ message: NapaxiA2APeerMessage,
        endpoint: String
    ) throws -> Bool {
        let sent = NapaxiA2ALocalTransport.shared(for: rawAPI).send(message, endpoint: endpoint)
        _ = try recordDeliveryStatus(
            message,
            status: sent ? "sent" : "failed",
            error: sent ? "" : "local transport send failed"
        )
        return sent
    }

    /// Send a peer message over the local transport WITHOUT recording a
    /// delivery status. For loopback/diagnostic self-tests only. Mirrors the
    /// Flutter `A2AApi.sendDiagnosticPeerMessage`.
    public func sendDiagnosticPeerMessage(
        _ message: NapaxiA2APeerMessage,
        endpoint: String
    ) throws -> Bool {
        NapaxiA2ALocalTransport.shared(for: rawAPI).send(message, endpoint: endpoint)
    }

    public func acceptDeepLink(
        _ envelope: NapaxiA2ADeepLinkEnvelope,
        source: String = "deep_link"
    ) throws -> NapaxiA2ATaskRecord {
        try Self.decodeTaskRecord(from: acceptDeepLinkJSON(envelopeJSON: envelope.jsonString(), source: source))
    }

    public func acceptDeepLinkJSON(envelopeJSON: String, source: String = "deep_link") throws -> NapaxiJSONValue {
        try call("a2a", "accept_deep_link", [
            "envelope_json": .string(envelopeJSON),
            "source": .string(source),
        ])
    }

    public func runTask(_ taskId: String, mode: String = "confirm") async throws -> NapaxiA2ATaskRecord {
        try Self.decodeTaskRecord(from: runTaskJSON(taskId, mode: mode))
    }

    public func runTaskJSON(_ taskId: String, mode: String = "confirm") throws -> NapaxiJSONValue {
        try call("a2a", "run_task", [
            "task_id": .string(taskId),
            "mode": .string(mode),
        ])
    }

    public func listTasks(
        filter: [String: NapaxiJSONValue] = [:],
        limit: Int = 100,
        offset: Int = 0
    ) throws -> [NapaxiA2ATaskRecord] {
        try Self.decodeTasks(from: listTasksJSON(
            filterJSON: filter.jsonString(),
            limit: limit,
            offset: offset
        ))
    }

    public func listTasksJSON(filterJSON: String = "{}", limit: Int = 100, offset: Int = 0) throws -> NapaxiJSONValue {
        try call("a2a", "list_tasks", [
            "filter_json": .string(filterJSON),
            "limit": .number(Double(limit)),
            "offset": .number(Double(offset)),
        ])
    }

    public func getTask(_ taskId: String) throws -> NapaxiA2ATaskRecord? {
        try Self.decodeTaskRecordOrNil(from: getTaskJSON(taskId))
    }

    public func getTaskJSON(_ taskId: String) throws -> NapaxiJSONValue {
        try call("a2a", "get_task", ["task_id": .string(taskId)])
    }

    public func buildResultLink(_ taskId: String, callbackUrl: String) throws -> NapaxiA2AResultLink {
        try Self.decodeResultLink(from: buildResultLinkJSON(taskId: taskId, callbackUrl: callbackUrl))
    }

    public func buildResultLinkJSON(taskId: String, callbackUrl: String) throws -> NapaxiJSONValue {
        try call("a2a", "build_result_link", [
            "task_id": .string(taskId),
            "callback_url": .string(callbackUrl),
        ])
    }

    public func recordResultEnvelope(_ envelope: NapaxiA2ADeepLinkEnvelope) throws -> NapaxiJSONValue {
        try recordResultEnvelopeJSON(envelopeJSON: envelope.jsonString())
    }

    public func recordResultEnvelopeJSON(envelopeJSON: String) throws -> NapaxiJSONValue {
        try call("a2a", "record_result", ["envelope_json": .string(envelopeJSON)])
    }

    public func consumePendingDeepLink() async throws -> NapaxiA2ADeepLinkEnvelope? {
        throw NapaxiError.unavailable("iOS Swift adapter does not own pending deep link launch state; pass opened URLs to acceptDeepLink instead")
    }

    public func clearPendingDeepLink() async throws {
        throw NapaxiError.unavailable("iOS Swift adapter does not own pending deep link launch state")
    }

    static func decodeAgentCard(from value: NapaxiJSONValue) throws -> NapaxiA2AAgentCard {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected A2A agent card object")
        }
        return try value.decodedObject(of: NapaxiA2AAgentCard.self)
    }

    static func decodePeerInvite(from value: NapaxiJSONValue) throws -> NapaxiA2APeerInvite {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected A2A peer invite object")
        }
        return try value.decodedObject(of: NapaxiA2APeerInvite.self)
    }

    static func decodePeer(from value: NapaxiJSONValue) throws -> NapaxiA2APeer {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected A2A peer object")
        }
        return try value.decodedObject(of: NapaxiA2APeer.self)
    }

    static func decodePeers(from value: NapaxiJSONValue) throws -> [NapaxiA2APeer] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiA2APeer.self)
    }

    static func decodePeerSession(from value: NapaxiJSONValue) throws -> NapaxiA2APeerSession {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected A2A peer session object")
        }
        return try value.decodedObject(of: NapaxiA2APeerSession.self)
    }

    static func decodePeerSessions(from value: NapaxiJSONValue) throws -> [NapaxiA2APeerSession] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiA2APeerSession.self)
    }

    static func decodePeerMessage(from value: NapaxiJSONValue) throws -> NapaxiA2APeerMessage {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected A2A peer message object")
        }
        return try value.decodedObject(of: NapaxiA2APeerMessage.self)
    }

    static func decodePeerMessages(from value: NapaxiJSONValue) throws -> [NapaxiA2APeerMessage] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiA2APeerMessage.self)
    }

    static func decodeDeliveryRecord(from value: NapaxiJSONValue) throws -> NapaxiA2ADeliveryRecord {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected A2A delivery record object")
        }
        return try value.decodedObject(of: NapaxiA2ADeliveryRecord.self)
    }

    static func decodeDeliveryRecords(from value: NapaxiJSONValue) throws -> [NapaxiA2ADeliveryRecord] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiA2ADeliveryRecord.self)
    }

    static func decodeTaskRecord(from value: NapaxiJSONValue) throws -> NapaxiA2ATaskRecord {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected A2A task record object")
        }
        return try value.decodedObject(of: NapaxiA2ATaskRecord.self)
    }

    static func decodeTaskRecordOrNil(from value: NapaxiJSONValue) throws -> NapaxiA2ATaskRecord? {
        guard case .object(let object) = value, object["error"] == nil else {
            return nil
        }
        return try value.decodedObject(of: NapaxiA2ATaskRecord.self)
    }

    static func decodeTasks(from value: NapaxiJSONValue) throws -> [NapaxiA2ATaskRecord] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiA2ATaskRecord.self)
    }

    static func decodeResultLink(from value: NapaxiJSONValue) throws -> NapaxiA2AResultLink {
        try throwIfJsonError(value)
        guard case .object = value else {
            throw NapaxiError.invalidJSON("Expected A2A result link object")
        }
        return try value.decodedObject(of: NapaxiA2AResultLink.self)
    }

}

public struct NapaxiSessionRunAPI: NapaxiCoreAPI, Sendable {
    public static let defaultListLimit = 100

    public let rawAPI: NapaxiRawAPI
    public func list(
        agentId: String? = nil,
        threadId: String? = nil,
        status: NapaxiSessionRunRecordStatus? = nil,
        limit: Int = Self.defaultListLimit,
        offset: Int = 0
    ) throws -> [NapaxiSessionRunRecord] {
        var filter: [String: NapaxiJSONValue] = [:]
        if let agentId { filter["agentId"] = .string(agentId) }
        if let threadId { filter["threadId"] = .string(threadId) }
        if let status, status != .unknown { filter["status"] = .string(status.rawValue) }
        return try Self.decodeRecords(from: listJSON(filterJSON: filter.jsonString(), limit: limit, offset: offset))
    }
    public func listJSON(filterJSON: String = "{}", limit: Int = Self.defaultListLimit, offset: Int = 0) throws -> NapaxiJSONValue {
        try call("session_runs", "list", ["filter_json": .string(filterJSON), "limit": .number(Double(limit)), "offset": .number(Double(offset))])
    }
    public func get(_ runId: String) throws -> NapaxiSessionRunRecord? {
        try Self.decodeRecordOrNil(from: getJSON(runId))
    }
    public func getJSON(_ runId: String) throws -> NapaxiJSONValue { try call("session_runs", "get", ["run_id": .string(runId)]) }
    public func active() throws -> [NapaxiSessionRunRecord] {
        try Self.decodeRecords(from: activeJSON())
    }
    public func activeJSON() throws -> NapaxiJSONValue { try call("session_runs", "active") }

    static func decodeRecords(from value: NapaxiJSONValue) throws -> [NapaxiSessionRunRecord] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiSessionRunRecord.self)
    }

    static func decodeRecordOrNil(from value: NapaxiJSONValue) throws -> NapaxiSessionRunRecord? {
        guard case .object(let object) = value else { return nil }
        if object["error"] != nil { return nil }
        return try value.decodedObject(of: NapaxiSessionRunRecord.self)
    }
}

public struct NapaxiAgentAppAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    public func registerPackage(_ package: NapaxiAgentAppPackage) throws -> NapaxiAgentAppPackage {
        try Self.decodePackage(from: registerPackageJSON(packageJSON: package.jsonString()))
    }
    public func registerPackageJSON(packageJSON: String) throws -> NapaxiJSONValue { try call("agent_app", "register_package", ["package_json": .string(packageJSON)]) }
    public func listPackages() throws -> [NapaxiAgentAppPackage] { try Self.decodePackages(from: listPackagesJSON()) }
    public func listPackagesJSON() throws -> NapaxiJSONValue { try call("agent_app", "list_packages") }
    public func getPackage(agentId: String) throws -> NapaxiAgentAppPackage? {
        let value = try getPackageJSON(agentId: agentId)
        guard value != .null else { return nil }
        return try value.decodedObject(of: NapaxiAgentAppPackage.self)
    }
    public func getPackage(_ agentId: String) throws -> NapaxiAgentAppPackage? {
        try getPackage(agentId: agentId)
    }
    public func getPackageJSON(agentId: String) throws -> NapaxiJSONValue { try call("agent_app", "get_package", ["agent_id": .string(agentId)]) }
    public func getPackageJSON(_ agentId: String) throws -> NapaxiJSONValue { try getPackageJSON(agentId: agentId) }
    public func deletePackage(agentId: String) throws -> Bool { try deletePackageJSON(agentId: agentId).requiredBool() }
    public func deletePackage(_ agentId: String) throws -> Bool { try deletePackage(agentId: agentId) }
    public func deletePackageJSON(agentId: String) throws -> NapaxiJSONValue { try call("agent_app", "delete_package", ["agent_id": .string(agentId)]) }
    public func deletePackageJSON(_ agentId: String) throws -> NapaxiJSONValue { try deletePackageJSON(agentId: agentId) }
    public func submitActionResult(_ result: NapaxiAgentAppActionResult) throws -> NapaxiAgentAppActionRecord {
        try Self.decodeActionRecord(from: submitActionResultJSON(resultJSON: result.jsonString()))
    }
    public func submitActionResultJSON(resultJSON: String) throws -> NapaxiJSONValue { try call("agent_app", "submit_action_result", ["result_json": .string(resultJSON)]) }
    public func submitResult(_ result: NapaxiAgentAppActionResult) throws -> NapaxiAgentAppActionRecord {
        try submitActionResult(result)
    }
    public func submitResultJSON(resultJSON: String) throws -> NapaxiJSONValue {
        try submitActionResultJSON(resultJSON: resultJSON)
    }
    public func listProposals(agentId: String = "") throws -> [NapaxiAgentAppActionRecord] {
        try Self.decodeActionRecords(from: listProposalsJSON(agentId: agentId))
    }
    public func listProposalsJSON(agentId: String = "") throws -> NapaxiJSONValue { try call("agent_app", "list_proposals", ["agent_id": .string(agentId)]) }
    public func getProposal(requestId: String) throws -> NapaxiAgentAppActionRecord? {
        let value = try getProposalJSON(requestId: requestId)
        guard value != .null else { return nil }
        return try Self.decodeActionRecord(from: value)
    }
    public func getProposal(_ requestId: String) throws -> NapaxiAgentAppActionRecord? {
        try getProposal(requestId: requestId)
    }
    public func getProposalJSON(requestId: String) throws -> NapaxiJSONValue { try call("agent_app", "get_proposal", ["request_id": .string(requestId)]) }
    public func getProposalJSON(_ requestId: String) throws -> NapaxiJSONValue { try getProposalJSON(requestId: requestId) }
    public func acceptTrigger(triggerJSON: String) throws -> NapaxiJSONValue { try call("agent_app", "accept_trigger", ["trigger_json": .string(triggerJSON)]) }

    static func decodePackage(from value: NapaxiJSONValue) throws -> NapaxiAgentAppPackage {
        try throwIfJsonError(value)
        return try value.decodedObject(of: NapaxiAgentAppPackage.self)
    }

    static func decodeActionRecord(from value: NapaxiJSONValue) throws -> NapaxiAgentAppActionRecord {
        try throwIfJsonError(value)
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected agent app action record object")
        }
        try validateAgentAppActionRecordObject(object)
        return try value.decodedObject(of: NapaxiAgentAppActionRecord.self)
    }

    static func decodePackages(from value: NapaxiJSONValue) throws -> [NapaxiAgentAppPackage] {
        guard case .array = value else { return [] }
        return try value.decodedObjectList(of: NapaxiAgentAppPackage.self)
    }

    static func decodeActionRecords(from value: NapaxiJSONValue) throws -> [NapaxiAgentAppActionRecord] {
        guard case .array = value else { return [] }
        return try decodeJsonObjectListFromValue(value) { object in
            try validateAgentAppActionRecordObject(object)
            return try NapaxiJSONValue.object(object).decodedObject(of: NapaxiAgentAppActionRecord.self)
        }
    }
}

public struct NapaxiAgentAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    private let engine: NapaxiEngine?

    public init(rawAPI: NapaxiRawAPI) {
        self.rawAPI = rawAPI
        self.engine = nil
    }

    init(rawAPI: NapaxiRawAPI, engine: NapaxiEngine) {
        self.rawAPI = rawAPI
        self.engine = engine
    }

    public func getOrCreate(_ agentId: String) throws -> NapaxiAgentHandle {
        try Self.decodeAgentHandle(from: getOrCreateJSON(agentId))
    }
    public func getOrCreate(_ agentId: String, config: NapaxiConfig?) throws -> NapaxiAgentHandle {
        try Self.decodeAgentHandle(from: getOrCreateJSON(agentId, configJSON: config?.jsonString()))
    }
    public func getOrCreateJSON(_ agentId: String) throws -> NapaxiJSONValue { try call("agent", "get_or_create", ["agent_id": .string(agentId)]) }
    public func getOrCreateJSON(_ agentId: String, configJSON: String?) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["agent_id": .string(agentId)]
        if let configJSON { payload["config_json"] = .string(configJSON) }
        return try call("agent", "get_or_create", payload)
    }

    public func list() throws -> [String] { try listJSON().decodedArray(of: String.self) }
    public func listJSON() throws -> NapaxiJSONValue { try call("agent", "list") }

    public func delete(_ agentId: String) throws -> Bool {
        try deleteJSON(agentId).requiredBool()
    }
    public func deleteJSON(_ agentId: String) throws -> NapaxiJSONValue {
        if agentId == NapaxiEngine.defaultAgentId {
            return .bool(false)
        }
        return try call("agent", "delete", ["agent_id": .string(agentId)])
    }

    static func decodeAgentHandle(from value: NapaxiJSONValue) throws -> NapaxiAgentHandle {
        try throwIfJsonError(value)
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected agent handle object")
        }
        guard let agentId = object["agent_id"]?.stringValue else {
            throw NapaxiError.invalidJSON("Expected agent_id string")
        }
        return NapaxiAgentHandle(agentId: agentId)
    }

    public func send(
        agent: NapaxiAgentHandle,
        sessionKey: NapaxiSessionKey,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        try send(agentId: agent.agentId, sessionKey: sessionKey, message: message, maxIterations: maxIterations)
    }

    public func send(
        _ agent: NapaxiAgentHandle,
        _ sessionKey: NapaxiSessionKey,
        _ message: String,
        config: NapaxiConfig? = nil,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        if let config {
            return try send(
                agentId: agent.agentId,
                config: config,
                sessionKey: sessionKey,
                message: message,
                maxIterations: maxIterations
            )
        }
        return try send(agent: agent, sessionKey: sessionKey, message: message, maxIterations: maxIterations)
    }

    public func send(
        agentId: String,
        sessionKey: NapaxiSessionKey,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        guard let engine else {
            throw NapaxiError.invalidState("Agent send requires an engine-backed NapaxiAgentAPI or explicit configJSON")
        }
        return try send(agentId: agentId, config: engine.config, sessionKey: sessionKey, message: message, maxIterations: maxIterations)
    }

    public func send(
        agentId: String,
        config: NapaxiConfig,
        sessionKey: NapaxiSessionKey,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        try chatEvents(from: sendJSON(agentId: agentId, configJSON: config.jsonString(), sessionKeyJSON: sessionKey.jsonString(), message: message, maxIterations: maxIterations))
    }

    public func sendJSON(
        agentId: String,
        configJSON: String,
        sessionKeyJSON: String,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> NapaxiJSONValue {
        try call("agent", "send", [
            "agent_id": .string(agentId),
            "config_json": .string(configJSON),
            "session_key_json": .string(sessionKeyJSON),
            "message": .string(message),
            "max_iterations": .number(Double(maxIterations)),
        ])
    }

    private func chatEvents(from value: NapaxiJSONValue) throws -> [NapaxiChatEvent] {
        try decodeChatEventsFromValue(value, expectedArrayMessage: "Expected agent send to return a JSON array")
    }

    public func createDefinition(_ definition: NapaxiAgentDefinition) throws -> NapaxiAgentDefinition {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).create(definition)
    }

    public func createDefinitionJSON(definitionJSON: String) throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).createJSON(definitionJSON: definitionJSON)
    }

    public func listDefinitions() throws -> [NapaxiAgentDefinition] {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).list()
    }

    public func listDefinitionsJSON() throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).listJSON()
    }

    public func getDefinition(_ definitionId: String) throws -> NapaxiAgentDefinition? {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).get(definitionId)
    }

    public func getDefinitionJSON(_ definitionId: String) throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).getJSON(definitionId)
    }

    public func updateDefinition(_ definition: NapaxiAgentDefinition) throws -> Bool {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).update(definition)
    }

    public func updateDefinitionJSON(definitionJSON: String) throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).updateJSON(definitionJSON: definitionJSON)
    }

    public func deleteDefinition(_ definitionId: String) throws -> Bool {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).delete(definitionId)
    }

    public func deleteDefinitionJSON(_ definitionId: String) throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).deleteJSON(definitionId)
    }

    public func importMarkdown(_ content: String) throws -> NapaxiAgentDefinition {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).importMarkdown(content)
    }

    public func importMarkdownJSON(_ content: String) throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).importMarkdownJSON(content)
    }

    public func listAvailableTools() throws -> [NapaxiToolInfo] {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).listAvailableTools()
    }

    public func listAvailableToolsJSON() throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).listAvailableToolsJSON()
    }

    public func createFromDefinition(_ definitionId: String) throws -> Bool {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).createFromDefinition(definitionId)
    }

    public func createFromDefinition(_ definitionId: String, config: NapaxiConfig?) throws -> Bool {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).createFromDefinition(definitionId, config: config)
    }

    public func createFromDefinitionJSON(_ definitionId: String) throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).createFromDefinitionJSON(definitionId)
    }

    public func createFromDefinitionJSON(_ definitionId: String, configJSON: String?) throws -> NapaxiJSONValue {
        try NapaxiAgentDefinitionAPI(rawAPI: rawAPI).createFromDefinitionJSON(definitionId, configJSON: configJSON)
    }
}

public struct NapaxiAgentDefinitionAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    public func create(_ definition: NapaxiAgentDefinition) throws -> NapaxiAgentDefinition {
        try Self.decodeAgentDefinition(from: createJSON(definitionJSON: definition.jsonString()))
    }
    public func createJSON(definitionJSON: String) throws -> NapaxiJSONValue { try call("agent_defs", "create", ["definition_json": .string(definitionJSON)]) }

    public func update(_ definition: NapaxiAgentDefinition) throws -> Bool {
        try updateJSON(definitionJSON: definition.jsonString()).requiredBool()
    }
    public func updateJSON(definitionJSON: String) throws -> NapaxiJSONValue { try call("agent_defs", "update", ["definition_json": .string(definitionJSON)]) }

    public func delete(_ definitionId: String) throws -> Bool { try deleteJSON(definitionId).requiredBool() }
    public func deleteJSON(_ definitionId: String) throws -> NapaxiJSONValue { try call("agent_defs", "delete", ["definition_id": .string(definitionId)]) }

    public func list() throws -> [NapaxiAgentDefinition] { try Self.decodeAgentDefinitions(from: listJSON()) }
    public func listJSON() throws -> NapaxiJSONValue { try call("agent_defs", "list") }

    public func get(_ definitionId: String) throws -> NapaxiAgentDefinition? {
        let value = try getJSON(definitionId)
        guard value != .null else { return nil }
        return try Self.decodeAgentDefinition(from: value)
    }
    public func getJSON(_ definitionId: String) throws -> NapaxiJSONValue { try call("agent_defs", "get", ["definition_id": .string(definitionId)]) }

    public func listAvailableTools() throws -> [NapaxiToolInfo] {
        try Self.decodeToolInfos(from: listAvailableToolsJSON())
    }
    public func listAvailableToolsJSON() throws -> NapaxiJSONValue { try call("agent_defs", "list_available_tools") }

    public func createFromDefinition(_ definitionId: String) throws -> Bool {
        try createFromDefinitionJSON(definitionId).requiredBool()
    }
    public func createFromDefinition(_ definitionId: String, config: NapaxiConfig?) throws -> Bool {
        try createFromDefinitionJSON(definitionId, configJSON: config?.jsonString()).requiredBool()
    }
    public func createFromDefinitionJSON(_ definitionId: String) throws -> NapaxiJSONValue {
        try call("agent_defs", "create_from_definition", ["definition_id": .string(definitionId)])
    }
    public func createFromDefinitionJSON(_ definitionId: String, configJSON: String?) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["definition_id": .string(definitionId)]
        if let configJSON { payload["config_json"] = .string(configJSON) }
        return try call("agent_defs", "create_from_definition", payload)
    }

    public func importMarkdown(_ content: String) throws -> NapaxiAgentDefinition {
        try Self.decodeAgentDefinition(from: importMarkdownJSON(content))
    }
    public func importMarkdownJSON(_ content: String) throws -> NapaxiJSONValue { try call("agent_defs", "import_markdown", ["content": .string(content)]) }

    static func decodeAgentDefinition(from value: NapaxiJSONValue) throws -> NapaxiAgentDefinition {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected agent definition object")
        }
        try validateAgentDefinitionObject(object)
        return NapaxiAgentDefinition.fromMap(object)
    }

    static func decodeAgentDefinitions(from value: NapaxiJSONValue) throws -> [NapaxiAgentDefinition] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateAgentDefinitionObject(object)
            return NapaxiAgentDefinition.fromMap(object)
        }
    }

    static func decodeToolInfos(from value: NapaxiJSONValue) throws -> [NapaxiToolInfo] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateToolInfoObject(object)
            return NapaxiToolInfo.fromMap(object)
        }
    }
}

public struct NapaxiSessionAPI: NapaxiCoreAPI, Sendable {
    public static let defaultHistoryPageLimit = 50

    public let rawAPI: NapaxiRawAPI
    private let engine: NapaxiEngine?

    public init(rawAPI: NapaxiRawAPI) {
        self.rawAPI = rawAPI
        self.engine = nil
    }

    init(rawAPI: NapaxiRawAPI, engine: NapaxiEngine) {
        self.rawAPI = rawAPI
        self.engine = engine
    }

    public func create(
        agentId: String = NapaxiEngine.defaultAgentId,
        channelType: String = "app",
        accountId: String = NapaxiEngine.defaultAccountId,
        existingThreadId: String? = nil
    ) throws -> NapaxiSessionKey {
        try createJSON(agentId: agentId, channelType: channelType, accountId: accountId, existingThreadId: existingThreadId)
            .decodedObject(of: NapaxiSessionKey.self)
    }
    public func createJSON(agentId: String, channelType: String, accountId: String, existingThreadId: String? = nil) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["agent_id": .string(agentId), "channel_type": .string(channelType), "account_id": .string(accountId)]
        if let existingThreadId { payload["existing_thread_id"] = .string(existingThreadId) }
        return try call("session", "create", payload)
    }
    public func create(
        agentId: String = NapaxiEngine.defaultAgentId,
        channelType: String = "app",
        accountId: String = NapaxiEngine.defaultAccountId,
        threadId: String?
    ) throws -> NapaxiSessionKey {
        try create(agentId: agentId, channelType: channelType, accountId: accountId, existingThreadId: threadId)
    }
    public func createJSON(agentId: String, channelType: String, accountId: String, threadId: String?) throws -> NapaxiJSONValue {
        try createJSON(agentId: agentId, channelType: channelType, accountId: accountId, existingThreadId: threadId)
    }
    static func decodeSessionInfos(from value: NapaxiJSONValue) throws -> [NapaxiSessionInfo] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateSessionInfoObject(object)
            return try NapaxiSessionInfo.fromMap(object)
        }
    }
    static func decodeChatMessages(from value: NapaxiJSONValue) throws -> [NapaxiChatMessage] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateChatMessageObject(object)
            return try NapaxiChatMessage.fromMap(object)
        }
    }
    static func decodeHistoryPage(from value: NapaxiJSONValue) throws -> NapaxiHistoryPage {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected session history page object")
        }
        return try NapaxiHistoryPage.fromMap(normalizedHistoryPageObject(object))
    }
    static func decodeContextStatus(from value: NapaxiJSONValue) throws -> NapaxiContextStatus {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected session context status object")
        }
        try validateContextStatusObject(object)
        return try NapaxiContextStatus.fromMap(object)
    }
    public func list(
        agentId: String = NapaxiEngine.defaultAgentId,
        accountId: String = NapaxiEngine.defaultAccountId
    ) throws -> [NapaxiSessionInfo] {
        try Self.decodeSessionInfos(from: listJSON(agentId: agentId, accountId: accountId))
    }
    public func listJSON(agentId: String, accountId: String) throws -> NapaxiJSONValue {
        try call("session", "list", ["agent_id": .string(agentId), "account_id": .string(accountId)])
    }
    public func delete(_ sessionKey: NapaxiSessionKey) throws -> Bool {
        try deleteJSON(sessionKeyJSON: sessionKey.jsonString()).requiredBool()
    }
    public func deleteJSON(sessionKeyJSON: String) throws -> NapaxiJSONValue { try call("session", "delete", ["session_key_json": .string(sessionKeyJSON)]) }
    public func clear(_ sessionKey: NapaxiSessionKey) throws -> Bool {
        try clearJSON(sessionKeyJSON: sessionKey.jsonString()).requiredBool()
    }
    public func clearJSON(sessionKeyJSON: String) throws -> NapaxiJSONValue { try call("session", "clear", ["session_key_json": .string(sessionKeyJSON)]) }
    public func history(
        threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> [NapaxiChatMessage] {
        try Self.decodeChatMessages(from: historyJSON(threadId: threadId, agentId: agentId))
    }
    public func history(
        _ threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> [NapaxiChatMessage] {
        try history(threadId: threadId, agentId: agentId)
    }
    public func historyJSON(
        threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> NapaxiJSONValue {
        try call("session", "history", ["thread_id": .string(threadId), "agent_id": .string(agentId)])
    }
    public func historyJSON(
        _ threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> NapaxiJSONValue {
        try historyJSON(threadId: threadId, agentId: agentId)
    }
    public func historyPage(
        threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        before: String? = nil,
        limit: Int = Self.defaultHistoryPageLimit
    ) throws -> NapaxiHistoryPage {
        try Self.decodeHistoryPage(from: historyPageJSON(threadId: threadId, agentId: agentId, before: before, limit: limit))
    }
    public func historyPage(
        _ threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        before: String? = nil,
        limit: Int = Self.defaultHistoryPageLimit
    ) throws -> NapaxiHistoryPage {
        try historyPage(threadId: threadId, agentId: agentId, before: before, limit: limit)
    }
    public func historyPageJSON(
        threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        before: String? = nil,
        limit: Int = Self.defaultHistoryPageLimit
    ) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = [
            "thread_id": .string(threadId),
            "agent_id": .string(agentId),
            "limit": .number(Double(limit)),
        ]
        if let before { payload["before"] = .string(before) }
        return try call("session", "history_page", payload)
    }
    public func historyPageJSON(
        _ threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        before: String? = nil,
        limit: Int = Self.defaultHistoryPageLimit
    ) throws -> NapaxiJSONValue {
        try historyPageJSON(threadId: threadId, agentId: agentId, before: before, limit: limit)
    }
    public func compactContext(
        _ sessionKey: NapaxiSessionKey,
        agentId: String = NapaxiEngine.defaultAgentId,
        focus: String? = nil
    ) throws -> NapaxiContextStatus {
        guard let engine else {
            throw NapaxiError.invalidState("NapaxiSessionAPI.compactContext requires an engine-backed session API or explicit configJSON")
        }
        return try compactContext(configJSON: engine.config.jsonString(), sessionKey: sessionKey, agentId: agentId, focus: focus)
    }
    public func compactContext(
        configJSON: String,
        sessionKey: NapaxiSessionKey,
        agentId: String = NapaxiEngine.defaultAgentId,
        focus: String? = nil
    ) throws -> NapaxiContextStatus {
        try Self.decodeContextStatus(from: compactContextJSON(
            configJSON: configJSON,
            agentId: agentId,
            sessionKeyJSON: sessionKey.jsonString(),
            focus: focus
        ))
    }
    public func compactContextJSON(
        configJSON: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        sessionKeyJSON: String,
        focus: String? = nil
    ) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = [
            "config_json": .string(configJSON),
            "agent_id": .string(agentId),
            "session_key_json": .string(sessionKeyJSON),
        ]
        if let focus { payload["focus"] = .string(focus) }
        return try call("session", "compact_context", payload)
    }
    public func contextStatus(
        threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> NapaxiContextStatus {
        guard let engine else {
            throw NapaxiError.invalidState("NapaxiSessionAPI.contextStatus requires an engine-backed session API or explicit configJSON")
        }
        return try contextStatus(configJSON: engine.config.jsonString(), threadId: threadId, agentId: agentId)
    }
    public func contextStatus(
        _ threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> NapaxiContextStatus {
        try contextStatus(threadId: threadId, agentId: agentId)
    }
    public func contextStatus(
        configJSON: String,
        threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> NapaxiContextStatus {
        try Self.decodeContextStatus(from: contextStatusJSON(configJSON: configJSON, threadId: threadId, agentId: agentId))
    }
    public func contextStatusJSON(
        configJSON: String,
        threadId: String,
        agentId: String = NapaxiEngine.defaultAgentId
    ) throws -> NapaxiJSONValue {
        try call("session", "context_status", [
            "config_json": .string(configJSON),
            "thread_id": .string(threadId),
            "agent_id": .string(agentId),
        ])
    }
    public func injectMessage(
        _ sessionKey: NapaxiSessionKey,
        _ message: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        attachments: [NapaxiAttachment] = []
    ) throws -> Bool {
        guard let engine else {
            throw NapaxiError.invalidState("NapaxiSessionAPI.injectMessage requires an engine-backed session API")
        }
        return try injectMessage(
            configJSON: engine.config.jsonString(),
            agentId: agentId,
            sessionKey: sessionKey,
            message: message,
            attachments: attachments
        )
    }
    public func injectMessage(
        configJSON: String,
        agentId: String = NapaxiEngine.defaultAgentId,
        sessionKey: NapaxiSessionKey,
        message: String,
        attachments: [NapaxiAttachment] = []
    ) throws -> Bool {
        try injectMessageJSON(
            configJSON: configJSON,
            agentId: agentId,
            sessionKeyJSON: sessionKey.jsonString(),
            message: message,
            attachmentsJSON: NapaxiAttachment.jsonString(for: attachments)
        ).requiredBool()
    }
    public func injectMessageJSON(configJSON: String, agentId: String, sessionKeyJSON: String, message: String, attachmentsJSON: String = "[]") throws -> NapaxiJSONValue {
        try call("session", "inject_message", [
            "config_json": .string(configJSON),
            "agent_id": .string(agentId),
            "session_key_json": .string(sessionKeyJSON),
            "message": .string(message),
            "attachments_json": .string(attachmentsJSON),
        ])
    }
    public func retractInjectedMessage(_ sessionKey: NapaxiSessionKey, message: String) throws -> Bool {
        try retractInjectedMessageJSON(sessionKeyJSON: sessionKey.jsonString(), message: message).requiredBool()
    }
    public func retractInjectedMessageJSON(sessionKeyJSON: String, message: String) throws -> NapaxiJSONValue {
        try call("session", "retract_injected_message", ["session_key_json": .string(sessionKeyJSON), "message": .string(message)])
    }
    public func answerHumanRequest(requestId: String, response: String) throws -> Bool {
        try call("tools", "answer_human_request", ["request_id": .string(requestId), "response": .string(response)]).requiredBool()
    }
    public func answerHumanRequest(_ requestId: String, _ response: String) throws -> Bool {
        try answerHumanRequest(requestId: requestId, response: response)
    }
    public func cancel(_ sessionKey: NapaxiSessionKey, agentId: String = NapaxiEngine.defaultAgentId) throws -> Bool {
        if let engine {
            return try engine.cancelSession(sessionKey, agentId: agentId)
        }
        return try cancelJSON(sessionKeyJSON: sessionKey.jsonString()).requiredBool()
    }
    public func cancelJSON(sessionKeyJSON: String) throws -> NapaxiJSONValue { try call("session", "cancel", ["session_key_json": .string(sessionKeyJSON)]) }
}

public struct NapaxiSkillAPI: NapaxiCoreAPI, Sendable {
    public static let defaultCatalogPackageLimit = 24

    public let rawAPI: NapaxiRawAPI
    private let engine: NapaxiEngine?

    public init(rawAPI: NapaxiRawAPI) {
        self.rawAPI = rawAPI
        self.engine = nil
    }

    init(rawAPI: NapaxiRawAPI, engine: NapaxiEngine) {
        self.rawAPI = rawAPI
        self.engine = engine
    }

    public func list(agentId: String = "") throws -> [NapaxiSkillInfo] {
        try Self.decodeSkillInfos(from: listJSON(agentId: agentId))
    }
    public func listJSON(agentId: String = "") throws -> NapaxiJSONValue { try call("skill", "list", ["agent_id": .string(agentId)]) }
    public func status(agentId: String = "") throws -> NapaxiSkillStatusReport {
        try Self.decodeSkillStatusReport(from: statusJSON(agentId: agentId))
    }
    public func statusJSON(agentId: String = "") throws -> NapaxiJSONValue { try call("skill", "status", ["agent_id": .string(agentId)]) }
    public func sources(agentId: String = "") throws -> NapaxiSkillSourceReport {
        try Self.decodeSkillSourceReport(from: sourcesJSON(agentId: agentId))
    }
    public func sourcesJSON(agentId: String = "") throws -> NapaxiJSONValue {
        try call("skill", "sources", ["agent_id": .string(agentId)])
    }
    public func recordSourceChanged(agentId: String = "", sourceId: String) throws -> NapaxiSkillRefreshResult {
        try Self.decodeSkillRefreshResult(from: recordSourceChangedJSON(agentId: agentId, sourceId: sourceId))
    }
    public func recordSourceChanged(_ sourceId: String, agentId: String = "") throws -> NapaxiSkillRefreshResult {
        try recordSourceChanged(agentId: agentId, sourceId: sourceId)
    }
    public func recordSourceChangedJSON(agentId: String = "", sourceId: String) throws -> NapaxiJSONValue {
        try call("skill", "record_source_changed", [
            "agent_id": .string(agentId),
            "source_id": .string(sourceId),
        ])
    }
    public func recordSourceChangedJSON(_ sourceId: String, agentId: String = "") throws -> NapaxiJSONValue {
        try recordSourceChangedJSON(agentId: agentId, sourceId: sourceId)
    }
    public func getStatus(agentId: String = "", skillName: String) throws -> NapaxiSkillStatusEntry? {
        let value = try getStatusJSON(agentId: agentId, skillName: skillName)
        guard value != .null else { return nil }
        return try Self.decodeSkillStatusEntry(from: value)
    }
    public func getStatus(_ skillName: String, agentId: String = "") throws -> NapaxiSkillStatusEntry? {
        try getStatus(agentId: agentId, skillName: skillName)
    }
    public func getStatusJSON(agentId: String = "", skillName: String) throws -> NapaxiJSONValue {
        try call("skill", "get_status", ["agent_id": .string(agentId), "skill_name": .string(skillName)])
    }
    public func getStatusJSON(_ skillName: String, agentId: String = "") throws -> NapaxiJSONValue {
        try getStatusJSON(agentId: agentId, skillName: skillName)
    }
    public func check(agentId: String = "") throws -> NapaxiSkillStatusReport {
        try Self.decodeSkillStatusReport(from: checkJSON(agentId: agentId))
    }
    public func checkJSON(agentId: String = "") throws -> NapaxiJSONValue { try call("skill", "check", ["agent_id": .string(agentId)]) }
    public func commands(agentId: String = "") throws -> NapaxiSkillCommandReport {
        try Self.decodeSkillCommandReport(from: commandsJSON(agentId: agentId))
    }
    public func commandsJSON(agentId: String = "") throws -> NapaxiJSONValue {
        try call("skill", "commands", ["agent_id": .string(agentId)])
    }
    public func resolveCommand(_ text: String, agentId: String = "") throws -> NapaxiSkillCommandResolution {
        try Self.decodeSkillCommandResolution(from: resolveCommandJSON(text, agentId: agentId))
    }
    public func resolveCommandJSON(_ text: String, agentId: String = "") throws -> NapaxiJSONValue {
        try call("skill", "resolve_command", ["agent_id": .string(agentId), "text": .string(text)])
    }
    public func runCommand(
        _ commandName: String,
        agentId: String = "",
        args: String? = nil,
        sessionKey: NapaxiSessionKey? = nil
    ) throws -> NapaxiSkillCommandRun {
        try Self.decodeSkillCommandRun(from: runCommandJSON(
            commandName,
            agentId: agentId,
            args: args,
            sessionKeyJSON: try sessionKey?.jsonString()
        ))
    }
    public func runCommandJSON(
        _ commandName: String,
        agentId: String = "",
        args: String? = nil,
        sessionKeyJSON: String? = nil
    ) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = [
            "agent_id": .string(agentId),
            "command_name": .string(commandName),
        ]
        if let args { payload["args"] = .string(args) }
        if let sessionKeyJSON { payload["session_key_json"] = .string(sessionKeyJSON) }
        return try call("skill", "run_command", payload)
    }
    public func setEnabled(agentId: String = "", skillName: String, enabled: Bool) throws -> String {
        try setEnabledJSON(agentId: agentId, skillName: skillName, enabled: enabled).requiredString()
    }
    public func setEnabled(_ skillName: String, agentId: String = "", enabled: Bool) throws -> String {
        try setEnabled(agentId: agentId, skillName: skillName, enabled: enabled)
    }
    public func setEnabledJSON(agentId: String = "", skillName: String, enabled: Bool) throws -> NapaxiJSONValue {
        try call("skill", "set_enabled", ["agent_id": .string(agentId), "skill_name": .string(skillName), "enabled": .bool(enabled)])
    }
    public func setEnabledJSON(_ skillName: String, agentId: String = "", enabled: Bool) throws -> NapaxiJSONValue {
        try setEnabledJSON(agentId: agentId, skillName: skillName, enabled: enabled)
    }
    public func updateConfig(agentId: String = "", skillKey: String, patch: [String: NapaxiJSONValue]) throws -> String {
        try updateConfigJSON(agentId: agentId, skillKey: skillKey, patchJSON: patch.jsonString()).requiredString()
    }
    public func updateConfig(_ skillKey: String, _ patch: [String: NapaxiJSONValue], agentId: String = "") throws -> String {
        try updateConfig(agentId: agentId, skillKey: skillKey, patch: patch)
    }
    public func updateConfigJSON(agentId: String = "", skillKey: String, patchJSON: String) throws -> NapaxiJSONValue {
        try call("skill", "update_config", ["agent_id": .string(agentId), "skill_key": .string(skillKey), "patch_json": .string(patchJSON)])
    }
    public func updateConfigJSON(_ skillKey: String, patchJSON: String, agentId: String = "") throws -> NapaxiJSONValue {
        try updateConfigJSON(agentId: agentId, skillKey: skillKey, patchJSON: patchJSON)
    }
    public func remediationActions(agentId: String = "", skillName: String) throws -> [NapaxiSkillRemediationAction] {
        try Self.decodeSkillRemediationActions(from: remediationActionsJSON(agentId: agentId, skillName: skillName))
    }
    public func remediationActions(_ skillName: String, agentId: String = "") throws -> [NapaxiSkillRemediationAction] {
        try remediationActions(agentId: agentId, skillName: skillName)
    }
    public func remediationActionsJSON(agentId: String = "", skillName: String) throws -> NapaxiJSONValue {
        try call("skill", "remediation_actions", ["agent_id": .string(agentId), "skill_name": .string(skillName)])
    }
    public func remediationActionsJSON(_ skillName: String, agentId: String = "") throws -> NapaxiJSONValue {
        try remediationActionsJSON(agentId: agentId, skillName: skillName)
    }
    public func snapshots(agentId: String = "", limit: Int = 50, offset: Int = 0) throws -> NapaxiSkillSnapshotList {
        try Self.decodeSkillSnapshotList(from: snapshotsJSON(agentId: agentId, limit: limit, offset: offset))
    }
    public func snapshotsJSON(agentId: String = "", limit: Int = 50, offset: Int = 0) throws -> NapaxiJSONValue {
        try call("skill", "snapshots", [
            "agent_id": .string(agentId),
            "limit": .number(Double(limit)),
            "offset": .number(Double(offset)),
        ])
    }
    public func snapshot(_ snapshotId: String) throws -> NapaxiSkillSnapshot? {
        let value = try snapshotJSON(snapshotId)
        guard value != .null else { return nil }
        return try Self.decodeSkillSnapshot(from: value)
    }
    public func snapshotJSON(_ snapshotId: String) throws -> NapaxiJSONValue {
        try call("skill", "get_snapshot", ["snapshot_id": .string(snapshotId)])
    }
    public func secretRequirements(
        agentId: String = "",
        skillName: String? = nil
    ) throws -> NapaxiSkillSecretRequirementReport {
        try Self.decodeSkillSecretRequirementReport(from: secretRequirementsJSON(agentId: agentId, skillName: skillName))
    }
    public func secretRequirementsJSON(agentId: String = "", skillName: String? = nil) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["agent_id": .string(agentId)]
        if let skillName { payload["skill_name"] = .string(skillName) }
        return try call("skill", "secret_requirements", payload)
    }
    public func recordSecretAvailability(
        agentId: String = "",
        skillName: String,
        key: String,
        available: Bool,
        source: String = "host"
    ) throws -> NapaxiSkillStatusReport {
        let value = try recordSecretAvailabilityJSON(
            agentId: agentId,
            skillName: skillName,
            key: key,
            available: available,
            source: source
        )
        return try Self.decodeSkillStatusReport(from: value)
    }
    public func recordSecretAvailability(
        _ skillName: String,
        _ key: String,
        agentId: String = "",
        available: Bool,
        source: String = "host"
    ) throws -> NapaxiSkillStatusReport {
        try recordSecretAvailability(
            agentId: agentId,
            skillName: skillName,
            key: key,
            available: available,
            source: source
        )
    }
    public func recordSecretAvailabilityJSON(
        agentId: String = "",
        skillName: String,
        key: String,
        available: Bool,
        source: String = "host"
    ) throws -> NapaxiJSONValue {
        try call("skill", "record_secret_availability", [
            "agent_id": .string(agentId),
            "skill_name": .string(skillName),
            "key": .string(key),
            "available": .bool(available),
            "source": .string(source),
        ])
    }
    public func recordSecretAvailabilityJSON(
        _ skillName: String,
        _ key: String,
        agentId: String = "",
        available: Bool,
        source: String = "host"
    ) throws -> NapaxiJSONValue {
        try recordSecretAvailabilityJSON(
            agentId: agentId,
            skillName: skillName,
            key: key,
            available: available,
            source: source
        )
    }
    public func requestRemediation(
        agentId: String = "",
        skillName: String,
        actionId: String
    ) throws -> NapaxiSkillRemediationRun {
        try Self.decodeSkillRemediationRun(from: requestRemediationJSON(agentId: agentId, skillName: skillName, actionId: actionId))
    }
    public func requestRemediation(
        _ skillName: String,
        _ actionId: String,
        agentId: String = ""
    ) throws -> NapaxiSkillRemediationRun {
        try requestRemediation(agentId: agentId, skillName: skillName, actionId: actionId)
    }
    public func requestRemediationJSON(agentId: String = "", skillName: String, actionId: String) throws -> NapaxiJSONValue {
        try call("skill", "request_remediation", [
            "agent_id": .string(agentId),
            "skill_name": .string(skillName),
            "action_id": .string(actionId),
        ])
    }
    public func requestRemediationJSON(_ skillName: String, _ actionId: String, agentId: String = "") throws -> NapaxiJSONValue {
        try requestRemediationJSON(agentId: agentId, skillName: skillName, actionId: actionId)
    }
    public func updateRemediationRun(
        agentId: String = "",
        runId: String,
        status: String,
        result: [String: NapaxiJSONValue]? = nil
    ) throws -> NapaxiSkillRemediationRun {
        try Self.decodeSkillRemediationRun(from: updateRemediationRunJSON(
            agentId: agentId,
            runId: runId,
            status: status,
            resultJSON: try result?.jsonString()
        ))
    }
    public func updateRemediationRun(
        _ runId: String,
        _ status: String,
        agentId: String = "",
        result: [String: NapaxiJSONValue]? = nil
    ) throws -> NapaxiSkillRemediationRun {
        try updateRemediationRun(agentId: agentId, runId: runId, status: status, result: result)
    }
    public func updateRemediationRunJSON(
        agentId: String = "",
        runId: String,
        status: String,
        resultJSON: String? = nil
    ) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = [
            "agent_id": .string(agentId),
            "run_id": .string(runId),
            "status": .string(status),
        ]
        if let resultJSON { payload["result_json"] = .string(resultJSON) }
        return try call("skill", "update_remediation_run", payload)
    }
    public func updateRemediationRunJSON(
        _ runId: String,
        _ status: String,
        agentId: String = "",
        resultJSON: String? = nil
    ) throws -> NapaxiJSONValue {
        try updateRemediationRunJSON(agentId: agentId, runId: runId, status: status, resultJSON: resultJSON)
    }
    public func remediationRuns(
        agentId: String = "",
        skillName: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> NapaxiSkillRemediationRunList {
        try Self.decodeSkillRemediationRunList(from: remediationRunsJSON(agentId: agentId, skillName: skillName, limit: limit, offset: offset))
    }
    public func remediationRunsJSON(
        agentId: String = "",
        skillName: String? = nil,
        limit: Int = 50,
        offset: Int = 0
    ) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = [
            "agent_id": .string(agentId),
            "limit": .number(Double(limit)),
            "offset": .number(Double(offset)),
        ]
        if let skillName { payload["skill_name"] = .string(skillName) }
        return try call("skill", "remediation_runs", payload)
    }
    public func recordRequirementResolution(
        agentId: String = "",
        skillName: String,
        actionId: String,
        result: [String: NapaxiJSONValue]
    ) throws -> String {
        try recordRequirementResolutionJSON(
            agentId: agentId,
            skillName: skillName,
            actionId: actionId,
            resultJSON: result.jsonString()
        ).requiredString()
    }
    public func recordRequirementResolution(
        _ skillName: String,
        _ actionId: String,
        _ result: [String: NapaxiJSONValue],
        agentId: String = ""
    ) throws -> String {
        try recordRequirementResolution(agentId: agentId, skillName: skillName, actionId: actionId, result: result)
    }
    public func recordRequirementResolutionJSON(
        agentId: String = "",
        skillName: String,
        actionId: String,
        resultJSON: String
    ) throws -> NapaxiJSONValue {
        try call("skill", "record_requirement_resolution", [
            "agent_id": .string(agentId),
            "skill_name": .string(skillName),
            "action_id": .string(actionId),
            "result_json": .string(resultJSON),
        ])
    }
    public func recordRequirementResolutionJSON(
        _ skillName: String,
        _ actionId: String,
        resultJSON: String,
        agentId: String = ""
    ) throws -> NapaxiJSONValue {
        try recordRequirementResolutionJSON(
            agentId: agentId,
            skillName: skillName,
            actionId: actionId,
            resultJSON: resultJSON
        )
    }
    public func install(agentId: String = "", skillContent: String) throws -> NapaxiSkillInstallResult {
        try Self.decodeSkillInstallResult(from: installJSON(agentId: agentId, skillContent: skillContent))
    }
    public func install(_ skillContent: String, agentId: String = "") throws -> NapaxiSkillInstallResult {
        try install(agentId: agentId, skillContent: skillContent)
    }
    public func install(agentId: String = "", input: NapaxiSkillInstallInput) throws -> NapaxiSkillInstallResult {
        try install(agentId: agentId, skillContent: input.installPayloadJSON())
    }
    public func install(_ input: NapaxiSkillInstallInput, agentId: String = "") throws -> NapaxiSkillInstallResult {
        try install(agentId: agentId, input: input)
    }
    public func installJSON(agentId: String = "", skillContent: String) throws -> NapaxiJSONValue {
        try call("skill", "install", ["agent_id": .string(agentId), "skill_content": .string(skillContent)])
    }
    public func installJSON(_ skillContent: String, agentId: String = "") throws -> NapaxiJSONValue {
        try installJSON(agentId: agentId, skillContent: skillContent)
    }
    public func remove(agentId: String = "", skillName: String) throws -> Bool {
        try removeJSON(agentId: agentId, skillName: skillName).requiredBool()
    }
    public func remove(_ skillName: String, agentId: String = "") throws -> Bool {
        try remove(agentId: agentId, skillName: skillName)
    }
    public func removeJSON(agentId: String = "", skillName: String) throws -> NapaxiJSONValue {
        try call("skill", "remove", ["agent_id": .string(agentId), "skill_name": .string(skillName)])
    }
    public func removeJSON(_ skillName: String, agentId: String = "") throws -> NapaxiJSONValue {
        try removeJSON(agentId: agentId, skillName: skillName)
    }
    public func reload(agentId: String = "") throws -> [String] {
        try reloadJSON(agentId: agentId).decodedArray(of: String.self)
    }
    public func reloadJSON(agentId: String = "") throws -> NapaxiJSONValue { try call("skill", "reload", ["agent_id": .string(agentId)]) }
    public func get(agentId: String = "", skillName: String) throws -> NapaxiSkillInfo? {
        let value = try getJSON(agentId: agentId, skillName: skillName)
        guard value != .null else { return nil }
        return try Self.decodeSkillInfo(from: value)
    }
    public func get(_ skillName: String, agentId: String = "") throws -> NapaxiSkillInfo? {
        try get(agentId: agentId, skillName: skillName)
    }
    public func getJSON(agentId: String = "", skillName: String) throws -> NapaxiJSONValue {
        try call("skill", "get", ["agent_id": .string(agentId), "skill_name": .string(skillName)])
    }
    public func getJSON(_ skillName: String, agentId: String = "") throws -> NapaxiJSONValue {
        try getJSON(agentId: agentId, skillName: skillName)
    }
    static func decodeSkillInfo(from value: NapaxiJSONValue) throws -> NapaxiSkillInfo {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill info object")
        }
        try validateSkillInfoObject(object)
        return NapaxiSkillInfo(raw: object)
    }
    static func decodeSkillInfos(from value: NapaxiJSONValue) throws -> [NapaxiSkillInfo] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateSkillInfoObject(object)
            return NapaxiSkillInfo(raw: object)
        }
    }
    static func decodeSkillStatusReport(from value: NapaxiJSONValue) throws -> NapaxiSkillStatusReport {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill status report object")
        }
        return NapaxiSkillStatusReport(raw: try normalizedSkillStatusReportObject(object))
    }
    static func decodeSkillStatusEntry(from value: NapaxiJSONValue) throws -> NapaxiSkillStatusEntry {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill status entry object")
        }
        return NapaxiSkillStatusEntry(raw: try normalizedSkillStatusEntryObject(object))
    }
    static func decodeSkillSourceReport(from value: NapaxiJSONValue) throws -> NapaxiSkillSourceReport {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill source report object")
        }
        return NapaxiSkillSourceReport(raw: try normalizedSkillSourceReportObject(object))
    }
    static func decodeSkillRefreshResult(from value: NapaxiJSONValue) throws -> NapaxiSkillRefreshResult {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill refresh result object")
        }
        return NapaxiSkillRefreshResult(raw: try normalizedSkillRefreshResultObject(object))
    }
    static func decodeSkillCommandReport(from value: NapaxiJSONValue) throws -> NapaxiSkillCommandReport {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill command report object")
        }
        return NapaxiSkillCommandReport(raw: try normalizedSkillCommandReportObject(object))
    }
    static func decodeSkillCommandResolution(from value: NapaxiJSONValue) throws -> NapaxiSkillCommandResolution {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill command resolution object")
        }
        return NapaxiSkillCommandResolution(raw: try normalizedSkillCommandResolutionObject(object))
    }
    static func decodeSkillCommandRun(from value: NapaxiJSONValue) throws -> NapaxiSkillCommandRun {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill command run object")
        }
        return NapaxiSkillCommandRun(raw: try normalizedSkillCommandRunObject(object))
    }
    static func decodeSkillRemediationActions(from value: NapaxiJSONValue) throws -> [NapaxiSkillRemediationAction] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateSkillRemediationActionObject(object)
            return NapaxiSkillRemediationAction(raw: object)
        }
    }
    static func decodeSkillSnapshotList(from value: NapaxiJSONValue) throws -> NapaxiSkillSnapshotList {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill snapshot list object")
        }
        return NapaxiSkillSnapshotList(raw: try normalizedSkillSnapshotListObject(object))
    }
    static func decodeSkillSnapshot(from value: NapaxiJSONValue) throws -> NapaxiSkillSnapshot {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill snapshot object")
        }
        return NapaxiSkillSnapshot(raw: try normalizedSkillSnapshotObject(object))
    }
    static func decodeSkillSecretRequirementReport(from value: NapaxiJSONValue) throws -> NapaxiSkillSecretRequirementReport {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill secret requirement report object")
        }
        return NapaxiSkillSecretRequirementReport(raw: try normalizedSkillSecretRequirementReportObject(object))
    }
    static func decodeSkillRemediationRun(from value: NapaxiJSONValue) throws -> NapaxiSkillRemediationRun {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill remediation run object")
        }
        return NapaxiSkillRemediationRun(raw: object)
    }
    static func decodeSkillRemediationRunList(from value: NapaxiJSONValue) throws -> NapaxiSkillRemediationRunList {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill remediation run list object")
        }
        return NapaxiSkillRemediationRunList(raw: try normalizedSkillRemediationRunListObject(object))
    }
    static func decodeSkillInstallResult(from value: NapaxiJSONValue) throws -> NapaxiSkillInstallResult {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill install result object")
        }
        try validateSkillInstallResultObject(object)
        return NapaxiSkillInstallResult(raw: object)
    }
    static func decodeSkillUsageRecords(from value: NapaxiJSONValue) throws -> [NapaxiSkillUsageRecord] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateSkillUsageRecordObject(object)
            return NapaxiSkillUsageRecord(raw: object)
        }
    }
    static func decodeSkillCuratorRunSummary(from value: NapaxiJSONValue) throws -> NapaxiCuratorRunSummary {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill curator run summary object")
        }
        try validateSkillCuratorRunSummaryObject(object)
        return NapaxiCuratorRunSummary(raw: object)
    }
    static func decodeSkillSupportFileReadResult(from value: NapaxiJSONValue) throws -> NapaxiSkillSupportFileReadResult {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill support file read result object")
        }
        try validateSkillSupportFileReadResultObject(object)
        return NapaxiSkillSupportFileReadResult(raw: object)
    }
    static func decodeCatalogSearchResult(from value: NapaxiJSONValue) throws -> NapaxiCatalogSearchResult {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill catalog search result object")
        }
        return NapaxiCatalogSearchResult(raw: try normalizedSkillCatalogSearchResultObject(object))
    }
    static func decodeCatalogPackagePage(from value: NapaxiJSONValue) throws -> NapaxiCatalogPackagePage {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected skill catalog package page object")
        }
        return NapaxiCatalogPackagePage(raw: try normalizedSkillCatalogPackagePageObject(object))
    }
    public func usage(agentId: String = "") throws -> [NapaxiSkillUsageRecord] {
        try Self.decodeSkillUsageRecords(from: usageJSON(agentId: agentId))
    }
    public func usageJSON(agentId: String = "") throws -> NapaxiJSONValue { try call("skill", "usage", ["agent_id": .string(agentId)]) }
    public func pin(agentId: String = "", skillName: String, pinned: Bool) throws -> String {
        try pinJSON(agentId: agentId, skillName: skillName, pinned: pinned).requiredString()
    }
    public func pin(_ skillName: String, agentId: String = "", pinned: Bool = true) throws -> String {
        try pin(agentId: agentId, skillName: skillName, pinned: pinned)
    }
    public func pinJSON(agentId: String = "", skillName: String, pinned: Bool) throws -> NapaxiJSONValue {
        try call("skill", "pin", ["agent_id": .string(agentId), "skill_name": .string(skillName), "pinned": .bool(pinned)])
    }
    public func pinJSON(_ skillName: String, agentId: String = "", pinned: Bool = true) throws -> NapaxiJSONValue {
        try pinJSON(agentId: agentId, skillName: skillName, pinned: pinned)
    }
    public func unpin(agentId: String = "", skillName: String) throws -> String {
        try pin(agentId: agentId, skillName: skillName, pinned: false)
    }
    public func unpin(_ skillName: String, agentId: String = "") throws -> String {
        try unpin(agentId: agentId, skillName: skillName)
    }
    public func unpinJSON(agentId: String = "", skillName: String) throws -> NapaxiJSONValue {
        try pinJSON(agentId: agentId, skillName: skillName, pinned: false)
    }
    public func unpinJSON(_ skillName: String, agentId: String = "") throws -> NapaxiJSONValue {
        try unpinJSON(agentId: agentId, skillName: skillName)
    }
    public func archive(agentId: String = "", skillName: String) throws -> String {
        try archiveJSON(agentId: agentId, skillName: skillName).requiredString()
    }
    public func archive(_ skillName: String, agentId: String = "") throws -> String {
        try archive(agentId: agentId, skillName: skillName)
    }
    public func archiveJSON(agentId: String = "", skillName: String) throws -> NapaxiJSONValue {
        try call("skill", "archive", ["agent_id": .string(agentId), "skill_name": .string(skillName)])
    }
    public func archiveJSON(_ skillName: String, agentId: String = "") throws -> NapaxiJSONValue {
        try archiveJSON(agentId: agentId, skillName: skillName)
    }
    public func restore(agentId: String = "", skillName: String) throws -> String {
        try restoreJSON(agentId: agentId, skillName: skillName).requiredString()
    }
    public func restore(_ skillName: String, agentId: String = "") throws -> String {
        try restore(agentId: agentId, skillName: skillName)
    }
    public func restoreJSON(agentId: String = "", skillName: String) throws -> NapaxiJSONValue {
        try call("skill", "restore", ["agent_id": .string(agentId), "skill_name": .string(skillName)])
    }
    public func restoreJSON(_ skillName: String, agentId: String = "") throws -> NapaxiJSONValue {
        try restoreJSON(agentId: agentId, skillName: skillName)
    }
    public func runCurator(agentId: String = "", dryRun: Bool = true) throws -> NapaxiCuratorRunSummary {
        try Self.decodeSkillCuratorRunSummary(from: runCuratorJSON(agentId: agentId, dryRun: dryRun))
    }
    public func runCuratorJSON(agentId: String = "", dryRun: Bool = true) throws -> NapaxiJSONValue {
        try call("skill", "run_curator", ["agent_id": .string(agentId), "dry_run": .bool(dryRun)])
    }
    public func runConsolidationReview(
        agentId: String = NapaxiEngine.defaultAgentId,
        dryRun: Bool = true
    ) throws -> NapaxiSkillConsolidationReviewResult {
        guard let engine else {
            throw NapaxiError.invalidState("Skill consolidation review requires an engine-backed NapaxiSkillAPI or explicit configJSON")
        }
        return try runConsolidationReview(agentId: agentId, config: engine.config, dryRun: dryRun)
    }
    public func runConsolidationReview(
        agentId: String,
        config: NapaxiConfig,
        dryRun: Bool = true
    ) throws -> NapaxiSkillConsolidationReviewResult {
        try NapaxiEvolutionAPI.decodeSkillConsolidationReviewResult(
            from: runConsolidationReviewJSON(agentId: agentId, configJSON: config.jsonString(), dryRun: dryRun)
        )
    }
    public func runConsolidationReviewJSON(agentId: String, configJSON: String, dryRun: Bool = true) throws -> NapaxiJSONValue {
        try call("evolution", "run_skill_consolidation_review", [
            "agent_id": .string(agentId),
            "config_json": .string(configJSON),
            "dry_run": .bool(dryRun),
        ])
    }
    public func readSupportFile(agentId: String = "", skillName: String, filePath: String) throws -> NapaxiSkillSupportFileReadResult {
        try Self.decodeSkillSupportFileReadResult(from: readSupportFileJSON(agentId: agentId, skillName: skillName, filePath: filePath))
    }
    public func readSupportFile(_ skillName: String, _ filePath: String, agentId: String = "") throws -> NapaxiSkillSupportFileReadResult {
        try readSupportFile(agentId: agentId, skillName: skillName, filePath: filePath)
    }
    public func readSupportFileJSON(agentId: String = "", skillName: String, filePath: String) throws -> NapaxiJSONValue {
        try call("skill", "read_support_file", ["agent_id": .string(agentId), "skill_name": .string(skillName), "file_path": .string(filePath)])
    }
    public func readSupportFileJSON(_ skillName: String, _ filePath: String, agentId: String = "") throws -> NapaxiJSONValue {
        try readSupportFileJSON(agentId: agentId, skillName: skillName, filePath: filePath)
    }
    public func searchCatalog(query: String) throws -> NapaxiCatalogSearchResult {
        try Self.decodeCatalogSearchResult(from: searchCatalogJSON(query: query))
    }
    public func searchCatalog(_ query: String) throws -> NapaxiCatalogSearchResult {
        try searchCatalog(query: query)
    }
    public func searchCatalogJSON(query: String) throws -> NapaxiJSONValue { try call("skill", "search_catalog", ["query": .string(query)]) }
    public func searchCatalogJSON(_ query: String) throws -> NapaxiJSONValue {
        try searchCatalogJSON(query: query)
    }
    public func listCatalogPackages(
        limit: Int = Self.defaultCatalogPackageLimit,
        cursor: String? = nil,
        catalogClient: NapaxiClawHubSkillCatalogClient = NapaxiClawHubSkillCatalogClient()
    ) async throws -> NapaxiCatalogPackagePage {
        try await catalogClient.listPackages(limit: limit, cursor: cursor)
    }
    public func listCatalogPackagesJSON(
        limit: Int = Self.defaultCatalogPackageLimit,
        cursor: String? = nil,
        catalogClient: NapaxiClawHubSkillCatalogClient = NapaxiClawHubSkillCatalogClient()
    ) async throws -> NapaxiJSONValue {
        try await catalogClient.listPackagesJSON(limit: limit, cursor: cursor)
    }
    public func getCatalogSkill(slug: String) throws -> NapaxiCatalogSkillInfo {
        try decodeSkillCatalogInfo(from: getCatalogSkillJSON(slug: slug))
    }
    public func getCatalogSkill(_ slug: String) throws -> NapaxiCatalogSkillInfo {
        try getCatalogSkill(slug: slug)
    }
    public func getCatalogSkillJSON(slug: String) throws -> NapaxiJSONValue { try call("skill", "get_catalog_skill", ["slug": .string(slug)]) }
    public func getCatalogSkillJSON(_ slug: String) throws -> NapaxiJSONValue {
        try getCatalogSkillJSON(slug: slug)
    }
    public func installFromCatalog(agentId: String = "", slug: String) throws -> NapaxiSkillInstallResult {
        try Self.decodeSkillInstallResult(from: installFromCatalogJSON(agentId: agentId, slug: slug))
    }
    public func installFromCatalog(_ slug: String, agentId: String = "") throws -> NapaxiSkillInstallResult {
        try installFromCatalog(agentId: agentId, slug: slug)
    }
    public func installFromCatalogJSON(agentId: String = "", slug: String) throws -> NapaxiJSONValue {
        try call("skill", "install_from_catalog", ["agent_id": .string(agentId), "slug": .string(slug)])
    }
    public func installFromCatalogJSON(_ slug: String, agentId: String = "") throws -> NapaxiJSONValue {
        try installFromCatalogJSON(agentId: agentId, slug: slug)
    }
}

public struct NapaxiEvolutionAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    private let engine: NapaxiEngine?

    public init(rawAPI: NapaxiRawAPI) {
        self.rawAPI = rawAPI
        self.engine = nil
    }

    init(rawAPI: NapaxiRawAPI, engine: NapaxiEngine) {
        self.rawAPI = rawAPI
        self.engine = engine
    }

    public func listPending() throws -> [[String: NapaxiJSONValue]] {
        guard case .array(let values) = try listPendingJSON() else {
            throw NapaxiError.invalidJSON("Expected evolution pending list")
        }
        return values.compactMap { value in
            guard case .object(let object) = value else { return nil }
            return object
        }
    }
    public func listPendingJSON() throws -> NapaxiJSONValue { try call("evolution", "list_pending") }

    public func listRuns(runIds: [String] = []) throws -> [NapaxiEvolutionRun] {
        let runIdsJSON = try NapaxiRawJSON(.array(runIds.map { .string($0) })).jsonString()
        return try Self.decodeEvolutionRuns(from: listRunsJSON(runIdsJSON: runIdsJSON))
    }
    public func listRunsJSON(runIdsJSON: String = "[]") throws -> NapaxiJSONValue {
        try call("evolution", "list_runs", ["run_ids_json": .string(runIdsJSON)])
    }

    public func listDiagnostics() throws -> [NapaxiEvolutionDiagnostic] {
        try Self.decodeEvolutionDiagnostics(from: listDiagnosticsJSON())
    }
    public func listDiagnosticsJSON() throws -> NapaxiJSONValue { try call("evolution", "list_diagnostics") }

    public func rejectPending(_ pendingId: String) throws -> [String: NapaxiJSONValue] {
        try Self.decodePendingEvolutionResponse(
            from: rejectPendingJSON(pendingId),
            fallbackError: "unexpected reject response"
        )
    }
    public func rejectPendingJSON(_ pendingId: String) throws -> NapaxiJSONValue {
        try call("evolution", "reject_pending", ["pending_id": .string(pendingId)])
    }

    public func applyPending(_ pendingId: String) throws -> [String: NapaxiJSONValue] {
        try Self.decodePendingEvolutionResponse(
            from: applyPendingJSON(pendingId),
            fallbackError: "unexpected apply response"
        )
    }
    public func applyPendingJSON(_ pendingId: String) throws -> NapaxiJSONValue {
        try call("evolution", "apply_pending", ["pending_id": .string(pendingId)])
    }

    public func runSkillConsolidationReview(
        agentId: String = NapaxiEngine.defaultAgentId,
        dryRun: Bool = true
    ) throws -> NapaxiSkillConsolidationReviewResult {
        guard let engine else {
            throw NapaxiError.invalidState("Evolution review requires an engine-backed NapaxiEvolutionAPI or explicit configJSON")
        }
        return try runSkillConsolidationReview(agentId: agentId, config: engine.config, dryRun: dryRun)
    }

    public func runSkillConsolidationReview(
        agentId: String,
        config: NapaxiConfig,
        dryRun: Bool = true
    ) throws -> NapaxiSkillConsolidationReviewResult {
        try Self.decodeSkillConsolidationReviewResult(
            from: runSkillConsolidationReviewJSON(agentId: agentId, configJSON: config.jsonString(), dryRun: dryRun)
        )
    }

    public func runSkillConsolidationReviewJSON(agentId: String, configJSON: String, dryRun: Bool = true) throws -> NapaxiJSONValue {
        try call("evolution", "run_skill_consolidation_review", [
            "agent_id": .string(agentId),
            "config_json": .string(configJSON),
            "dry_run": .bool(dryRun),
        ])
    }

    static func decodePendingEvolutionResponse(
        from value: NapaxiJSONValue,
        fallbackError: String
    ) throws -> [String: NapaxiJSONValue] {
        do {
            return try object(from: value)
        } catch {
            return ["error": .string(fallbackError)]
        }
    }

    static func decodeSkillConsolidationReviewResult(
        from value: NapaxiJSONValue
    ) throws -> NapaxiSkillConsolidationReviewResult {
        do {
            return try value.decodedObject(of: NapaxiSkillConsolidationReviewResult.self)
        } catch {
            return NapaxiSkillConsolidationReviewResult(raw: [
                "reviewed": .bool(false),
                "dry_run": .bool(true),
                "error": .string("unexpected consolidation review response"),
            ])
        }
    }

    static func decodeEvolutionRuns(from value: NapaxiJSONValue) throws -> [NapaxiEvolutionRun] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateEvolutionRunObject(object)
            return NapaxiEvolutionRun(raw: object)
        }
    }

    static func decodeEvolutionDiagnostics(from value: NapaxiJSONValue) throws -> [NapaxiEvolutionDiagnostic] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateEvolutionDiagnosticObject(object)
            return NapaxiEvolutionDiagnostic(raw: object)
        }
    }

    private static func object(from value: NapaxiJSONValue) throws -> [String: NapaxiJSONValue] {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected evolution response object")
        }
        return object
    }
}

public struct NapaxiGroupAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    private let engine: NapaxiEngine?

    public init(rawAPI: NapaxiRawAPI) {
        self.rawAPI = rawAPI
        self.engine = nil
    }

    init(rawAPI: NapaxiRawAPI, engine: NapaxiEngine) {
        self.rawAPI = rawAPI
        self.engine = engine
    }

    public func create(name: String, members: [String]) throws -> String {
        let membersJSON = try NapaxiRawJSON(.array(members.map { .string($0) })).jsonString()
        return try createJSON(name: name, membersJSON: membersJSON).requiredString()
    }

    public func create(_ name: String, _ memberAgentIds: [String]) throws -> String {
        try create(name: name, members: memberAgentIds)
    }

    public func createJSON(name: String, membersJSON: String) throws -> NapaxiJSONValue {
        try call("group", "create", ["name": .string(name), "members_json": .string(membersJSON)])
    }

    public func delete(_ groupId: String) throws -> Bool { try deleteJSON(groupId).requiredBool() }
    public func deleteJSON(_ groupId: String) throws -> NapaxiJSONValue { try call("group", "delete", ["group_id": .string(groupId)]) }

    public func list() throws -> [NapaxiGroupInfo] { try Self.decodeGroupInfos(from: listJSON()) }
    public func listJSON() throws -> NapaxiJSONValue { try call("group", "list") }

    public func get(_ groupId: String) throws -> NapaxiGroupInfo? {
        let value = try getJSON(groupId)
        guard value != .null else { return nil }
        return try Self.decodeGroupInfo(from: value)
    }
    public func getJSON(_ groupId: String) throws -> NapaxiJSONValue { try call("group", "get", ["group_id": .string(groupId)]) }

    public func rename(_ groupId: String, newName: String) throws -> Bool {
        try renameJSON(groupId, newName: newName).requiredBool()
    }
    public func rename(_ groupId: String, _ newName: String) throws -> Bool {
        try rename(groupId, newName: newName)
    }
    public func renameJSON(_ groupId: String, newName: String) throws -> NapaxiJSONValue {
        try call("group", "rename", ["group_id": .string(groupId), "new_name": .string(newName)])
    }

    public func updateMembers(_ groupId: String, members: [String]) throws -> Bool {
        let membersJSON = try NapaxiRawJSON(.array(members.map { .string($0) })).jsonString()
        return try updateMembersJSON(groupId, membersJSON: membersJSON).requiredBool()
    }
    public func updateMembers(_ groupId: String, _ memberAgentIds: [String]) throws -> Bool {
        try updateMembers(groupId, members: memberAgentIds)
    }
    public func updateMembersJSON(_ groupId: String, membersJSON: String) throws -> NapaxiJSONValue {
        try call("group", "update_members", ["group_id": .string(groupId), "members_json": .string(membersJSON)])
    }

    public func setCustomPrompt(_ groupId: String, prompt: String?) throws -> Bool {
        try setCustomPromptJSON(groupId, prompt: prompt).requiredBool()
    }
    public func setCustomPromptJSON(_ groupId: String, prompt: String?) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["group_id": .string(groupId)]
        if let prompt { payload["prompt"] = .string(prompt) }
        return try call("group", "set_custom_prompt", payload)
    }

    public func messages(_ groupId: String) throws -> [NapaxiGroupMessage] {
        try Self.decodeGroupMessages(from: messagesJSON(groupId))
    }
    public func messagesJSON(_ groupId: String) throws -> NapaxiJSONValue { try call("group", "messages", ["group_id": .string(groupId)]) }

    public func clearHistory(_ groupId: String) throws -> Bool { try clearHistoryJSON(groupId).requiredBool() }
    public func clearHistoryJSON(_ groupId: String) throws -> NapaxiJSONValue { try call("group", "clear_history", ["group_id": .string(groupId)]) }

    public func send(
        groupId: String,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        guard let engine else {
            throw NapaxiError.invalidState("Group send requires an engine-backed NapaxiGroupAPI or explicit configJSON")
        }
        return try send(groupId: groupId, config: engine.config, message: message, maxIterations: maxIterations)
    }

    public func send(
        _ groupId: String,
        _ message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        try send(groupId: groupId, message: message, maxIterations: maxIterations)
    }

    public func send(
        groupId: String,
        config: NapaxiConfig,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        try chatEvents(from: sendJSON(groupId: groupId, configJSON: config.jsonString(), message: message, maxIterations: maxIterations))
    }

    public func sendJSON(
        groupId: String,
        configJSON: String,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> NapaxiJSONValue {
        try call("group", "send", ["group_id": .string(groupId), "config_json": .string(configJSON), "message": .string(message), "max_iterations": .number(Double(maxIterations))])
    }

    public func sendToAgent(
        groupId: String,
        agentId: String,
        sessionKey: NapaxiSessionKey,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        guard let engine else {
            throw NapaxiError.invalidState("Group sendToAgent requires an engine-backed NapaxiGroupAPI or explicit configJSON")
        }
        return try sendToAgent(groupId: groupId, agentId: agentId, config: engine.config, sessionKey: sessionKey, message: message, maxIterations: maxIterations)
    }

    public func sendToAgent(
        _ groupId: String,
        _ agentId: String,
        _ sessionKey: NapaxiSessionKey,
        _ message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        try sendToAgent(groupId: groupId, agentId: agentId, sessionKey: sessionKey, message: message, maxIterations: maxIterations)
    }

    public func sendToAgent(
        groupId: String,
        agentId: String,
        config: NapaxiConfig,
        sessionKey: NapaxiSessionKey,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> [NapaxiChatEvent] {
        try chatEvents(from: sendToAgentJSON(
            groupId: groupId,
            agentId: agentId,
            configJSON: config.jsonString(),
            sessionKeyJSON: sessionKey.jsonString(),
            message: message,
            maxIterations: maxIterations
        ), propagatingJSONError: true)
    }

    public func sendToAgentJSON(
        groupId: String,
        agentId: String,
        configJSON: String,
        sessionKeyJSON: String,
        message: String,
        maxIterations: Int = NapaxiChatDefaults.maxIterations
    ) throws -> NapaxiJSONValue {
        try call("group", "send_to_agent", [
            "group_id": .string(groupId),
            "agent_id": .string(agentId),
            "config_json": .string(configJSON),
            "session_key_json": .string(sessionKeyJSON),
            "message": .string(message),
            "max_iterations": .number(Double(maxIterations)),
        ])
    }

    public func exportState() throws -> String { try exportStateJSON().requiredString() }
    public func exportStateJSON() throws -> NapaxiJSONValue { try call("group", "export_state") }

    public func importState(stateJSON: String) throws -> Bool { try importStateJSON(stateJSON: stateJSON).requiredBool() }
    public func importState(_ stateJSON: String) throws -> Bool { try importState(stateJSON: stateJSON) }
    public func importStateJSON(stateJSON: String) throws -> NapaxiJSONValue { try call("group", "import_state", ["state_json": .string(stateJSON)]) }

    static func decodeChatEvents(from value: NapaxiJSONValue, propagatingJSONError: Bool = false) throws -> [NapaxiChatEvent] {
        try decodeChatEventsFromValue(
            value,
            expectedArrayMessage: "Expected group send to return a JSON array",
            propagatingJSONError: propagatingJSONError
        )
    }

    static func decodeGroupInfo(from value: NapaxiJSONValue) throws -> NapaxiGroupInfo {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected group info object")
        }
        try validateGroupInfoObject(object)
        return NapaxiGroupInfo.fromMap(object)
    }

    static func decodeGroupInfos(from value: NapaxiJSONValue) throws -> [NapaxiGroupInfo] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateGroupInfoObject(object)
            return NapaxiGroupInfo.fromMap(object)
        }
    }

    static func decodeGroupMessages(from value: NapaxiJSONValue) throws -> [NapaxiGroupMessage] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateGroupMessageObject(object)
            return NapaxiGroupMessage.fromMap(object)
        }
    }

    private func chatEvents(from value: NapaxiJSONValue, propagatingJSONError: Bool = false) throws -> [NapaxiChatEvent] {
        try Self.decodeChatEvents(from: value, propagatingJSONError: propagatingJSONError)
    }
}

public struct NapaxiChannelAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    public func list() throws -> NapaxiJSONValue { try call("channel", "list") }
    public func register(configJSON: String) throws -> NapaxiJSONValue { try call("channel", "register", ["config_json": .string(configJSON)]) }
    public func unregister(channelName: String) throws -> NapaxiJSONValue { try call("channel", "unregister", ["channel_name": .string(channelName)]) }
    public func submitInbound(envelopeJSON: String) throws -> NapaxiJSONValue {
        try call("channel", "submit_inbound", ["envelope_json": .string(envelopeJSON)])
    }
    public func takeInbound(channelName: String, limit: Int = 20) throws -> NapaxiJSONValue {
        try call("channel", "take_inbound", ["channel_name": .string(channelName), "limit": .number(Double(limit))])
    }
    public func ackInbound(inboundId: String) throws -> NapaxiJSONValue {
        try call("channel", "ack_inbound", ["inbound_id": .string(inboundId)])
    }
    public func enqueueOutbound(outboundJSON: String) throws -> NapaxiJSONValue {
        try call("channel", "enqueue_outbound", ["outbound_json": .string(outboundJSON)])
    }
    public func replyInbound(inboundId: String, replyJSON: String) throws -> NapaxiJSONValue {
        try call("channel", "reply_inbound", ["inbound_id": .string(inboundId), "reply_json": .string(replyJSON)])
    }
    public func leaseOutbound(channelName: String, accountId: String? = nil, limit: Int = 20) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["channel_name": .string(channelName), "limit": .number(Double(limit))]
        if let accountId {
            payload["account_id"] = .string(accountId)
        }
        return try call("channel", "lease_outbound", payload)
    }
    public func ackOutbound(outboundId: String, receiptJSON: String = "{}") throws -> NapaxiJSONValue {
        try call("channel", "ack_outbound", ["outbound_id": .string(outboundId), "receipt_json": .string(receiptJSON)])
    }
    public func failOutbound(outboundId: String, error: String) throws -> NapaxiJSONValue {
        try call("channel", "fail_outbound", ["outbound_id": .string(outboundId), "error": .string(error)])
    }
    public func listChannels() throws -> [NapaxiChannelRecord] {
        try decodeJsonObjectListFromValue(list()) { object in
            NapaxiChannelRecord.fromJson(object)
        }
    }
    public func register(_ registration: NapaxiChannelRegistration) throws -> Bool {
        try registerChannel(configJSON: registration.jsonString())
    }
    public func registerChannel(configJSON: String) throws -> Bool {
        try register(configJSON: configJSON).requiredBool()
    }
    public func unregisterChannel(_ channelName: String) throws -> Bool {
        try unregister(channelName: channelName).requiredBool()
    }
    public func submitInbound(_ message: NapaxiChannelInboundMessage) throws -> NapaxiChannelAcceptedReceipt {
        try submitInboundJSON(message.jsonString())
    }
    public func submitInboundJSON(_ envelopeJSON: String) throws -> NapaxiChannelAcceptedReceipt {
        NapaxiChannelAcceptedReceipt.fromJson(try submitInbound(envelopeJSON: envelopeJSON).channelReceiptObject())
    }
    public func takeInboundMessages(channelName: String, limit: Int = 20) throws -> [NapaxiChannelInboundMessage] {
        try decodeJsonObjectListFromValue(takeInbound(channelName: channelName, limit: limit)) { object in
            NapaxiChannelInboundMessage.fromJson(object)
        }
    }
    public func ackInboundMessage(_ inboundId: String) throws -> Bool {
        try ackInbound(inboundId: inboundId).requiredBool()
    }
    public func enqueueOutbound(_ message: NapaxiChannelOutboundMessage) throws -> NapaxiChannelAcceptedReceipt {
        try enqueueOutboundJSON(message.jsonString())
    }
    public func enqueueOutboundJSON(_ outboundJSON: String) throws -> NapaxiChannelAcceptedReceipt {
        NapaxiChannelAcceptedReceipt.fromJson(try enqueueOutbound(outboundJSON: outboundJSON).channelReceiptObject())
    }
    public func replyInbound(_ inboundId: String, message: NapaxiChannelOutboundMessage) throws -> NapaxiChannelAcceptedReceipt {
        try replyInboundJSON(inboundId, replyJSON: message.jsonString())
    }
    public func replyInboundJSON(_ inboundId: String, replyJSON: String) throws -> NapaxiChannelAcceptedReceipt {
        NapaxiChannelAcceptedReceipt.fromJson(try replyInbound(inboundId: inboundId, replyJSON: replyJSON).channelReceiptObject())
    }
    public func leaseOutboundMessages(channelName: String, accountId: String? = nil, limit: Int = 20) throws -> [NapaxiChannelOutboundMessage] {
        try decodeJsonObjectListFromValue(leaseOutbound(channelName: channelName, accountId: accountId, limit: limit)) { object in
            NapaxiChannelOutboundMessage.fromJson(object)
        }
    }
    public func ackOutboundMessage(_ outboundId: String, receiptJSON: String = "{}") throws -> Bool {
        try ackOutbound(outboundId: outboundId, receiptJSON: receiptJSON).requiredBool()
    }
    public func failOutboundMessage(_ outboundId: String, error: String) throws -> Bool {
        try failOutbound(outboundId: outboundId, error: error).requiredBool()
    }
}

public struct NapaxiChannelAgentAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI

    public func registerRouteJSON(_ routeJSON: String) throws -> NapaxiJSONValue {
        try call("channel_agent", "register_route", ["route_json": .string(routeJSON)])
    }

    public func registerRoute(_ route: NapaxiChannelAgentRoute) throws -> NapaxiChannelAgentRoute {
        try NapaxiChannelAgentRoute.fromJson(requiredChannelAgentObject(registerRouteJSON(try route.jsonString())))
    }

    public func listRoutes(channelName: String? = nil) throws -> [NapaxiChannelAgentRoute] {
        var payload: [String: NapaxiJSONValue] = [:]
        if let channelName {
            payload["channel_name"] = .string(channelName)
        }
        return try decodeJsonObjectListFromValue(call("channel_agent", "list_routes", payload)) {
            NapaxiChannelAgentRoute.fromJson($0)
        }
    }

    public func removeRoute(_ routeId: String) throws -> Bool {
        try call("channel_agent", "remove_route", ["route_id": .string(routeId)]).requiredBool()
    }

    public func resolveRouteJSON(bridgeConfigJSON: String, inboundJSON: String) throws -> NapaxiJSONValue {
        try call("channel_agent", "resolve_route", [
            "bridge_config_json": .string(bridgeConfigJSON),
            "inbound_json": .string(inboundJSON),
        ])
    }

    public func status(channelName: String? = nil) throws -> NapaxiChannelAgentStatus {
        var payload: [String: NapaxiJSONValue] = [:]
        if let channelName {
            payload["channel_name"] = .string(channelName)
        }
        return try NapaxiChannelAgentStatus.fromJson(requiredChannelAgentObject(call("channel_agent", "status", payload)))
    }

    public func streamPump(configJSON _: String, bridgeConfigJSON _: String) throws -> AsyncThrowingStream<String, Error> {
        throw NapaxiError.unavailable(
            "iOS ChannelAgent streamPump is unavailable in v1; use Flutter bridge or call core route/status plus channel queue APIs."
        )
    }
}

private func requiredChannelAgentObject(_ value: NapaxiJSONValue) throws -> [String: NapaxiJSONValue] {
    guard let object = value.objectValue else {
        throw NapaxiError.invalidJSON("Expected channel-agent JSON object")
    }
    return object
}

public struct NapaxiQqBotProtocolAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI

    public func buildOutboundPayload(messageJSON: String, markdownEndpointKindsJSON: String = "") throws -> NapaxiJSONValue {
        try call("channel_qqbot", "build_outbound_payload", [
            "message_json": .string(messageJSON),
            "markdown_endpoint_kinds_json": .string(markdownEndpointKindsJSON),
        ])
    }

    public func buildOutboundPayloadPlain(messageJSON: String) throws -> NapaxiJSONValue {
        try call("channel_qqbot", "build_outbound_payload_plain", ["message_json": .string(messageJSON)])
    }

    public func shouldFallbackFromMarkdown(status: Int) throws -> Bool {
        try call("channel_qqbot", "should_fallback_from_markdown", ["status": .number(Double(status))]).requiredBool()
    }

    public func outboundEndpointPath(peerKind: String, peerId: String) throws -> String {
        try call("channel_qqbot", "outbound_endpoint_path", [
            "peer_kind": .string(peerKind),
            "peer_id": .string(peerId),
        ]).requiredString()
    }

    public func apiBase(sandbox: Bool) throws -> String {
        try call("channel_qqbot", "api_base", ["sandbox": .bool(sandbox)]).requiredString()
    }

    public func isMessageEvent(_ eventType: String) throws -> Bool {
        try call("channel_qqbot", "is_message_event", ["event_type": .string(eventType)]).requiredBool()
    }

    public func normalizeInbound(eventType: String, dataJSON: String) throws -> NapaxiJSONValue {
        try call("channel_qqbot", "normalize_inbound", [
            "event_type": .string(eventType),
            "data_json": .string(dataJSON),
        ])
    }

    public func gatewayStep(stateJSON: String, eventJSON: String) throws -> NapaxiJSONValue {
        try call("channel_qqbot", "gateway_step", [
            "state_json": .string(stateJSON),
            "event_json": .string(eventJSON),
        ])
    }
}

public struct NapaxiWorkspaceAPI: NapaxiCoreAPI, Sendable {
    public static let defaultMemorySearchLimit = 5
    public static let defaultRecallSessionLimit = 3
    public static let defaultAgentId = NapaxiEngine.defaultAgentId

    public let rawAPI: NapaxiRawAPI
    private let engine: NapaxiEngine?

    public init(rawAPI: NapaxiRawAPI) {
        self.rawAPI = rawAPI
        self.engine = nil
    }

    init(rawAPI: NapaxiRawAPI, engine: NapaxiEngine) {
        self.rawAPI = rawAPI
        self.engine = engine
    }

    public func readFile(
        _ path: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> NapaxiWorkspaceFile? {
        let value = try readFileJSON(accountId: accountId, agentId: agentId, path: path)
        return try Self.decodeWorkspaceFile(from: value)
    }
    public func readFileJSON(accountId: String, agentId: String, path: String) throws -> NapaxiJSONValue {
        try call("workspace", "read_file", ["account_id": .string(accountId), "agent_id": .string(agentId), "path": .string(path)])
    }

    static func decodeWorkspaceFile(from value: NapaxiJSONValue) throws -> NapaxiWorkspaceFile? {
        guard value != .null else { return nil }
        try throwIfJsonError(value)
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected workspace file object")
        }
        try validateWorkspaceFileObject(object)
        return NapaxiWorkspaceFile.fromMap(object)
    }

    public func writeFile(
        _ path: String,
        content: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> Bool {
        try writeFileJSON(accountId: accountId, agentId: agentId, path: path, content: content).requiredBool()
    }
    public func writeFile(
        _ path: String,
        _ content: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> Bool {
        try writeFile(path, content: content, accountId: accountId, agentId: agentId)
    }
    public func writeFileJSON(accountId: String, agentId: String, path: String, content: String) throws -> NapaxiJSONValue {
        try call("workspace", "write_file", ["account_id": .string(accountId), "agent_id": .string(agentId), "path": .string(path), "content": .string(content)])
    }
    public func appendFile(
        _ path: String,
        content: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> Bool {
        try appendFileJSON(accountId: accountId, agentId: agentId, path: path, content: content).requiredBool()
    }
    public func appendFile(
        _ path: String,
        _ content: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> Bool {
        try appendFile(path, content: content, accountId: accountId, agentId: agentId)
    }
    public func appendFileJSON(accountId: String, agentId: String, path: String, content: String) throws -> NapaxiJSONValue {
        try call("workspace", "append_file", ["account_id": .string(accountId), "agent_id": .string(agentId), "path": .string(path), "content": .string(content)])
    }
    public func deleteFile(
        _ path: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> Bool {
        try deleteFileJSON(accountId: accountId, agentId: agentId, path: path).requiredBool()
    }
    public func deleteFileJSON(accountId: String, agentId: String, path: String) throws -> NapaxiJSONValue {
        try call("workspace", "delete_file", ["account_id": .string(accountId), "agent_id": .string(agentId), "path": .string(path)])
    }
    public func listFiles(
        directory: String = "",
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> [NapaxiWorkspaceEntry] {
        try Self.decodeWorkspaceEntries(from: listFilesJSON(accountId: accountId, agentId: agentId, directory: directory))
    }
    public func listFiles(
        _ directory: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> [NapaxiWorkspaceEntry] {
        try listFiles(directory: directory, accountId: accountId, agentId: agentId)
    }
    public func listFilesJSON(accountId: String, agentId: String, directory: String = ".") throws -> NapaxiJSONValue {
        try call("workspace", "list_files", ["account_id": .string(accountId), "agent_id": .string(agentId), "directory": .string(directory)])
    }
    public func systemPrompt(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> String {
        try systemPromptJSON(accountId: accountId, agentId: agentId).requiredString()
    }
    public func systemPromptJSON(accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("workspace", "system_prompt", ["account_id": .string(accountId), "agent_id": .string(agentId)])
    }
    public func reseed(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> Int {
        try Self.decodeReseedCount(from: reseedJSON(accountId: accountId, agentId: agentId))
    }
    public func reseedJSON(accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("workspace", "reseed", ["account_id": .string(accountId), "agent_id": .string(agentId)])
    }
    public func searchMemory(
        _ query: String,
        limit: Int = Self.defaultMemorySearchLimit,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> [NapaxiMemorySearchResult] {
        try Self.decodeMemorySearchResults(
            from: searchMemoryJSON(accountId: accountId, agentId: agentId, query: query, limit: limit)
        )
    }
    public func searchMemoryJSON(
        accountId: String,
        agentId: String,
        query: String,
        limit: Int = Self.defaultMemorySearchLimit
    ) throws -> NapaxiJSONValue {
        try call("workspace", "search_memory", [
            "account_id": .string(accountId),
            "agent_id": .string(agentId),
            "query": .string(query),
            "limit": .number(Double(Self.clampedMemorySearchLimit(limit))),
        ])
    }
    public func search(
        _ query: String,
        limit: Int = Self.defaultMemorySearchLimit,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> [NapaxiMemorySearchResult] {
        try searchMemory(query, limit: limit, accountId: accountId, agentId: agentId)
    }
    public func searchJSON(
        accountId: String,
        agentId: String,
        query: String,
        limit: Int = Self.defaultMemorySearchLimit
    ) throws -> NapaxiJSONValue {
        try searchMemoryJSON(accountId: accountId, agentId: agentId, query: query, limit: limit)
    }
    public func recallSessions(
        _ query: String,
        limit: Int = Self.defaultRecallSessionLimit,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId,
        currentThreadId: String = ""
    ) throws -> [NapaxiMemoryRecallSession] {
        guard let engine else {
            throw NapaxiError.invalidState("NapaxiWorkspaceAPI.recallSessions requires an engine-backed workspace API")
        }
        return try recallSessions(
            configJSON: engine.config.jsonString(),
            accountId: accountId,
            agentId: agentId,
            currentThreadId: currentThreadId,
            query: query,
            limit: limit
        )
    }
    public func recallSessions(
        configJSON: String,
        accountId: String,
        agentId: String,
        currentThreadId: String,
        query: String,
        limit: Int = Self.defaultRecallSessionLimit
    ) throws -> [NapaxiMemoryRecallSession] {
        try Self.decodeMemoryRecallSessions(
            from: recallSessionsJSON(
                configJSON: configJSON,
                accountId: accountId,
                agentId: agentId,
                currentThreadId: currentThreadId,
                query: query,
                limit: limit
            )
        )
    }
    public func recallSessionsJSON(
        configJSON: String,
        accountId: String,
        agentId: String,
        currentThreadId: String,
        query: String,
        limit: Int = Self.defaultRecallSessionLimit
    ) throws -> NapaxiJSONValue {
        try call("workspace", "recall_sessions", [
            "config_json": .string(configJSON),
            "account_id": .string(accountId),
            "agent_id": .string(agentId),
            "current_thread_id": .string(currentThreadId),
            "query": .string(query),
            "limit": .number(Double(Self.clampedRecallSessionLimit(limit))),
        ])
    }
    public func rebuildRecallIndex(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> NapaxiRecallIndexStats {
        try Self.decodeRecallIndexStats(from: rebuildRecallIndexJSON(accountId: accountId, agentId: agentId))
    }
    public func rebuildRecallIndexJSON(accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("workspace", "rebuild_recall_index", ["account_id": .string(accountId), "agent_id": .string(agentId)])
    }
    public func recallIndexStats(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> NapaxiRecallIndexStats {
        try Self.decodeRecallIndexStats(from: recallIndexStatsJSON(accountId: accountId, agentId: agentId))
    }
    public func recallIndexStatsJSON(accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("workspace", "recall_index_stats", ["account_id": .string(accountId), "agent_id": .string(agentId)])
    }
    public func listJournalDays(
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> [NapaxiJournalDay] {
        try Self.decodeJournalDays(from: listJournalDaysJSON(accountId: accountId, agentId: agentId))
    }
    public func listJournalDaysJSON(accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("workspace", "list_journal_days", ["account_id": .string(accountId), "agent_id": .string(agentId)])
    }
    public func readJournalDay(
        _ date: String,
        accountId: String = NapaxiEngine.defaultAccountId,
        agentId: String = Self.defaultAgentId
    ) throws -> [NapaxiJournalTurnRecord] {
        try Self.decodeJournalTurns(from: readJournalDayJSON(accountId: accountId, agentId: agentId, date: date))
    }
    public func readJournalDayJSON(accountId: String, agentId: String, date: String) throws -> NapaxiJSONValue {
        try call("workspace", "read_journal_day", ["account_id": .string(accountId), "agent_id": .string(agentId), "date": .string(date)])
    }

    public static func clampedMemorySearchLimit(_ limit: Int) -> Int {
        min(20, max(1, limit))
    }

    public static func clampedRecallSessionLimit(_ limit: Int) -> Int {
        min(5, max(1, limit))
    }

    static func decodeMemorySearchResults(from value: NapaxiJSONValue) throws -> [NapaxiMemorySearchResult] {
        try throwIfJsonError(value)
        return try workspaceResultsArray(from: value).decodedArray(of: NapaxiMemorySearchResult.self)
    }

    static func decodeWorkspaceEntries(from value: NapaxiJSONValue) throws -> [NapaxiWorkspaceEntry] {
        try throwIfJsonError(value)
        return try decodeJsonObjectListFromValue(value) { object in
            try validateWorkspaceEntryObject(object)
            return NapaxiWorkspaceEntry.fromMap(object)
        }
    }

    static func decodeMemoryRecallSessions(from value: NapaxiJSONValue) throws -> [NapaxiMemoryRecallSession] {
        try throwIfJsonError(value)
        return try workspaceResultsArray(from: value).decodedArray(of: NapaxiMemoryRecallSession.self)
    }

    static func decodeReseedCount(from value: NapaxiJSONValue) throws -> Int {
        if case .object(let object) = value {
            return object["seeded"]?.intValue ?? 0
        }
        throw NapaxiError.invalidJSON("Expected reseed result object")
    }

    static func decodeRecallIndexStats(from value: NapaxiJSONValue) throws -> NapaxiRecallIndexStats {
        try throwIfJsonError(value)
        guard case .object = value else {
            return NapaxiRecallIndexStats(raw: [:])
        }
        return try value.decodedObject(of: NapaxiRecallIndexStats.self)
    }

    static func decodeJournalDays(from value: NapaxiJSONValue) throws -> [NapaxiJournalDay] {
        try throwIfJsonError(value)
        return try value.decodedObjectList(of: NapaxiJournalDay.self)
    }

    static func decodeJournalTurns(from value: NapaxiJSONValue) throws -> [NapaxiJournalTurnRecord] {
        try throwIfJsonError(value)
        return try value.decodedObjectList(of: NapaxiJournalTurnRecord.self)
    }

    private static func workspaceResultsArray(from value: NapaxiJSONValue) -> NapaxiJSONValue {
        if case .array = value {
            return value
        }
        if case .object(let object) = value,
           case .array? = object["results"] {
            return object["results"] ?? .array([])
        }
        return .array([])
    }
}

public struct NapaxiFileBridgeAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    public let filesDir: String?

    public init(rawAPI: NapaxiRawAPI, filesDir: String? = nil) {
        self.rawAPI = rawAPI
        self.filesDir = filesDir
    }

    public static var instance: NapaxiFileBridgeAPI? {
        NapaxiFileBridgeState.shared.instance
    }

    public static var isInitialized: Bool {
        instance != nil
    }

    public static func initFileBridge(filesDir: String, handle: Int64?) throws -> Bool {
        guard let handle else { return false }
        let api = NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle), filesDir: filesDir)
        let initialized = try api.initFileBridge()
        if initialized {
            NapaxiFileBridgeState.shared.instance = api
        }
        return initialized
    }

    public static func requireInstance() throws -> NapaxiFileBridgeAPI {
        guard let instance else {
            throw NapaxiError.invalidState("NapaxiFileBridge is not initialized")
        }
        return instance
    }

    static func registerInitialized(filesDir: String, handle: Int64) {
        NapaxiFileBridgeState.shared.instance = NapaxiFileBridgeAPI(
            rawAPI: NapaxiRawAPI(handle: handle),
            filesDir: filesDir
        )
    }

    static func clearInstance(handle: Int64? = nil) {
        NapaxiFileBridgeState.shared.clear(handle: handle)
    }

    public func initBridge() throws -> NapaxiJSONValue { try call("file_bridge", "init") }
    public func initFileBridge() throws -> Bool {
        try initBridge().requiredBool()
    }
    public func initScoped(accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "init_scoped", ["account_id": .string(accountId), "agent_id": .string(agentId)])
    }
    public func initFileBridgeScoped(accountId: String, agentId: String) throws -> Bool {
        try initScoped(accountId: accountId, agentId: agentId).requiredBool()
    }
    public func sandboxToReal(_ sandboxPath: String) throws -> String? {
        try sandboxToRealJSON(sandboxPath).stringValue
    }
    public func sandboxToRealJSON(_ sandboxPath: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "sandbox_to_real", ["sandbox_path": .string(sandboxPath)])
    }
    public func sandboxToRealScoped(_ sandboxPath: String, accountId: String, agentId: String) throws -> String? {
        try sandboxToRealScopedJSON(sandboxPath, accountId: accountId, agentId: agentId).stringValue
    }
    public func sandboxToRealScopedJSON(_ sandboxPath: String, accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "sandbox_to_real_scoped", ["account_id": .string(accountId), "agent_id": .string(agentId), "sandbox_path": .string(sandboxPath)])
    }
    public func realToSandbox(_ realPath: String) throws -> String? {
        try realToSandboxJSON(realPath).stringValue
    }
    public func realToSandboxJSON(_ realPath: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "real_to_sandbox", ["real_path": .string(realPath)])
    }
    public func realToSandboxScoped(_ realPath: String, accountId: String, agentId: String) throws -> String? {
        try realToSandboxScopedJSON(realPath, accountId: accountId, agentId: agentId).stringValue
    }
    public func realToSandboxScopedJSON(_ realPath: String, accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "real_to_sandbox_scoped", ["account_id": .string(accountId), "agent_id": .string(agentId), "real_path": .string(realPath)])
    }
    public func deleteFile(_ sandboxPath: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "delete_sandbox_file", ["sandbox_path": .string(sandboxPath)])
    }
    public func deleteSandboxFile(_ sandboxPath: String) throws -> Bool {
        try deleteFile(sandboxPath).requiredBool()
    }
    public func deleteFileScoped(_ sandboxPath: String, accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "delete_sandbox_file_scoped", ["account_id": .string(accountId), "agent_id": .string(agentId), "sandbox_path": .string(sandboxPath)])
    }
    public func deleteSandboxFileScoped(_ sandboxPath: String, accountId: String, agentId: String) throws -> Bool {
        try deleteFileScoped(sandboxPath, accountId: accountId, agentId: agentId).requiredBool()
    }
    public func detectFileReferences(_ text: String) throws -> [NapaxiResolvedFile] {
        try Self.decodeResolvedFiles(
            from: call("file_bridge", "detect_file_references", ["text": .string(text)])
        )
    }
    public func detectFileReferencesScoped(_ text: String, accountId: String, agentId: String) throws -> [NapaxiResolvedFile] {
        try Self.decodeResolvedFiles(
            from: call("file_bridge", "detect_file_references_scoped", ["account_id": .string(accountId), "agent_id": .string(agentId), "text": .string(text)])
        )
    }
    public func listFiles(subdir: String? = nil, recursive: Bool = false) throws -> [NapaxiWorkspaceFileInfo] {
        var payload: [String: NapaxiJSONValue] = ["recursive": .bool(recursive)]
        if let subdir { payload["subdir"] = .string(subdir) }
        return try Self.decodeWorkspaceFileInfos(
            from: call("file_bridge", "list_workspace_filesystem", payload)
        )
    }
    public func listWorkspaceFilesystem(subdir: String? = nil, recursive: Bool = false) throws -> [NapaxiWorkspaceFileInfo] {
        try listFiles(subdir: subdir, recursive: recursive)
    }
    public func listWorkspaceFilesystemJSON(subdir: String? = nil, recursive: Bool = false) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["recursive": .bool(recursive)]
        if let subdir { payload["subdir"] = .string(subdir) }
        return try call("file_bridge", "list_workspace_filesystem", payload)
    }
    public func listFilesScoped(accountId: String, agentId: String, subdir: String? = nil, recursive: Bool = false) throws -> [NapaxiWorkspaceFileInfo] {
        try Self.listFilesScopedAfterInit(
            initScoped: {
                _ = try initFileBridgeScoped(accountId: accountId, agentId: agentId)
            },
            listScopedJSON: {
                try listWorkspaceFilesystemScopedJSON(
                    accountId: accountId,
                    agentId: agentId,
                    subdir: subdir,
                    recursive: recursive
                )
            }
        )
    }
    public func listWorkspaceFilesystemScoped(accountId: String, agentId: String, subdir: String? = nil, recursive: Bool = false) throws -> [NapaxiWorkspaceFileInfo] {
        try listFilesScoped(accountId: accountId, agentId: agentId, subdir: subdir, recursive: recursive)
    }
    public func listWorkspaceFilesystemScopedJSON(accountId: String, agentId: String, subdir: String? = nil, recursive: Bool = false) throws -> NapaxiJSONValue {
        var payload: [String: NapaxiJSONValue] = ["account_id": .string(accountId), "agent_id": .string(agentId), "recursive": .bool(recursive)]
        if let subdir { payload["subdir"] = .string(subdir) }
        return try call("file_bridge", "list_workspace_filesystem_scoped", payload)
    }
    static func listFilesScopedAfterInit(
        initScoped: () throws -> Void,
        listScopedJSON: () throws -> NapaxiJSONValue
    ) throws -> [NapaxiWorkspaceFileInfo] {
        try initScoped()
        return try decodeWorkspaceFileInfos(from: listScopedJSON())
    }
    public func workspaceSize() throws -> Int {
        try call("file_bridge", "workspace_size").napaxiIntValue ?? 0
    }
    public func workspaceSizeScoped(accountId: String, agentId: String) throws -> Int {
        try call("file_bridge", "workspace_size_scoped", ["account_id": .string(accountId), "agent_id": .string(agentId)]).napaxiIntValue ?? 0
    }
    public func workspaceDir() throws -> NapaxiJSONValue { try call("file_bridge", "workspace_dir") }
    public func workspaceDirScoped(accountId: String, agentId: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "workspace_dir_scoped", ["account_id": .string(accountId), "agent_id": .string(agentId)])
    }
    public func rootfsDir() throws -> NapaxiJSONValue { try call("file_bridge", "rootfs_dir") }
    public func skillsDir() throws -> NapaxiJSONValue { try call("file_bridge", "skills_dir") }

    public func saveMessageAttachments(
        threadId: String,
        userMessageIndex: Int,
        attachments: [NapaxiChatAttachment]
    ) throws -> Bool {
        if attachments.isEmpty {
            return true
        }
        return try saveMessageAttachmentsJSON(
            threadId: threadId,
            userMessageIndex: userMessageIndex,
            attachmentsJSON: NapaxiChatAttachment.jsonString(for: attachments)
        ).requiredBool()
    }

    public func saveMessageAttachments(
        threadId: String,
        userMsgIndex: Int,
        attachmentsJson: String
    ) throws -> Bool {
        try saveMessageAttachmentsJSON(
            threadId: threadId,
            userMessageIndex: userMsgIndex,
            attachmentsJSON: attachmentsJson
        ).requiredBool()
    }

    public func saveMessageAttachmentsJSON(
        threadId: String,
        userMessageIndex: Int,
        attachmentsJSON: String
    ) throws -> NapaxiJSONValue {
        try call("file_bridge", "save_message_attachments", [
            "thread_id": .string(threadId),
            "user_msg_index": .number(Double(userMessageIndex)),
            "attachments_json": .string(attachmentsJSON),
        ])
    }

    public func loadThreadAttachments(_ threadId: String) throws -> [Int: [NapaxiChatAttachment]] {
        try Self.threadAttachments(from: loadThreadAttachmentsJSON(threadId))
    }

    public func loadThreadAttachmentsJSON(_ threadId: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "load_thread_attachments", ["thread_id": .string(threadId)])
    }

    public func deleteThreadAttachments(_ threadId: String) throws -> Bool {
        try deleteThreadAttachmentsJSON(threadId).requiredBool()
    }

    public func deleteThreadAttachmentsJSON(_ threadId: String) throws -> NapaxiJSONValue {
        try call("file_bridge", "delete_thread_attachments", ["thread_id": .string(threadId)])
    }

    public func sandboxToRealPath(_ sandboxPath: String) throws -> String? {
        try sandboxToReal(sandboxPath)
    }

    public func resolveFile(_ sandboxPath: String) async throws -> URL? {
        guard let realPath = try sandboxToReal(sandboxPath) else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: realPath) else {
            return nil
        }
        return URL(fileURLWithPath: realPath)
    }

    public func sandboxToRealPath(_ sandboxPath: String, accountId: String, agentId: String) throws -> String? {
        try sandboxToRealScoped(sandboxPath, accountId: accountId, agentId: agentId)
    }

    public func realToSandboxPath(_ realPath: String) throws -> String? {
        try realToSandbox(realPath)
    }

    public func realToSandboxPath(_ realPath: String, accountId: String, agentId: String) throws -> String? {
        try realToSandboxScoped(realPath, accountId: accountId, agentId: agentId)
    }

    public func workspaceDirPath() throws -> String? {
        try workspaceDir().stringValue
    }

    public func workspaceDirPath(accountId: String, agentId: String) throws -> String? {
        try workspaceDirScoped(accountId: accountId, agentId: agentId).stringValue
    }

    public func rootfsDirPath() throws -> String? {
        try rootfsDir().stringValue
    }

    public func skillsDirPath() throws -> String? {
        try skillsDir().stringValue
    }

    public static func openLocalFile(_ path: String, mimeType: String = "application/octet-stream") async -> NapaxiOpenFileResult {
        NapaxiOpenFileResult(success: false, error: "Opening local files is only implemented on Android.")
    }

    static func decodeResolvedFiles(from value: NapaxiJSONValue) throws -> [NapaxiResolvedFile] {
        try decodeJsonObjectListFromValue(value, NapaxiResolvedFile.fromMap)
    }

    static func decodeWorkspaceFileInfos(from value: NapaxiJSONValue) throws -> [NapaxiWorkspaceFileInfo] {
        try decodeJsonObjectListFromValue(value, NapaxiWorkspaceFileInfo.fromMap)
    }

    static func threadAttachments(from value: NapaxiJSONValue) throws -> [Int: [NapaxiChatAttachment]] {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected thread attachment map")
        }
        var result: [Int: [NapaxiChatAttachment]] = [:]
        for (key, rawAttachments) in object {
            guard let index = Int(key) else { continue }
            guard case .array = rawAttachments else { continue }
            result[index] = try rawAttachments.decodedArray(of: NapaxiChatAttachment.self)
        }
        return result
    }
}

private final class NapaxiFileBridgeState: @unchecked Sendable {
    static let shared = NapaxiFileBridgeState()

    private let lock = NSLock()
    private var storage: NapaxiFileBridgeAPI?

    var instance: NapaxiFileBridgeAPI? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }

    func clear(handle: Int64?) {
        lock.lock()
        if handle == nil || storage?.rawAPI.handle == handle {
            storage = nil
        }
        lock.unlock()
    }
}

public struct NapaxiMcpAPI: NapaxiCoreAPI, Sendable {
    public let rawAPI: NapaxiRawAPI
    public let defaultUserId: String

    public init(rawAPI: NapaxiRawAPI, defaultUserId: String = NapaxiEngine.defaultAccountId) {
        self.rawAPI = rawAPI
        self.defaultUserId = defaultUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? NapaxiEngine.defaultAccountId
            : defaultUserId.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func addServer(
        name: String,
        url: String,
        headers: [String: String] = [:],
        transport: String? = nil,
        userId: String? = nil
    ) throws -> NapaxiMcpServerActionResult {
        do {
            var effectiveHeaders = headers
            if let transport, !transport.isEmpty {
                effectiveHeaders["__napaxi_transport"] = transport
            }
            return try Self.decodeMcpServerActionResult(from: addServerJSON(
                name: name,
                url: url,
                headersJSON: stringMapJSON(effectiveHeaders),
                userId: userId
            ))
        } catch {
            return NapaxiMcpServerActionResult(name: name, error: mcpFailureMessage("addServer", error))
        }
    }

    public func addServer(
        _ name: String,
        _ url: String,
        headers: [String: String] = [:],
        transport: String? = nil,
        userId: String? = nil
    ) throws -> NapaxiMcpServerActionResult {
        try addServer(name: name, url: url, headers: headers, transport: transport, userId: userId)
    }

    public func addServerJSON(name: String, url: String, headersJSON: String = "{}", userId: String? = nil) throws -> NapaxiJSONValue {
        try call("mcp", "add_server", ["name": .string(name), "url": .string(url), "headers_json": .string(headersJSON), "user_id": .string(effectiveUserId(userId))])
    }

    public func addServerJSON(_ name: String, _ url: String, headersJSON: String = "{}", userId: String? = nil) throws -> NapaxiJSONValue {
        try addServerJSON(name: name, url: url, headersJSON: headersJSON, userId: userId)
    }

    public func addServerOrError(
        name: String,
        url: String,
        headers: [String: String] = [:],
        transport: String? = nil,
        userId: String? = nil
    ) -> NapaxiMcpServerActionResult {
        do {
            return try addServer(name: name, url: url, headers: headers, transport: transport, userId: userId)
        } catch {
            return NapaxiMcpServerActionResult(name: name, error: mcpFailureMessage("addServer", error))
        }
    }

    public func addServerOrError(
        _ name: String,
        _ url: String,
        headers: [String: String] = [:],
        transport: String? = nil,
        userId: String? = nil
    ) -> NapaxiMcpServerActionResult {
        addServerOrError(name: name, url: url, headers: headers, transport: transport, userId: userId)
    }

    public func removeServer(name: String, userId: String? = nil) throws -> Bool {
        do {
            return try success(from: removeServerJSON(name: name, userId: userId))
        } catch {
            return false
        }
    }

    public func removeServer(_ name: String, userId: String? = nil) throws -> Bool {
        try removeServer(name: name, userId: userId)
    }

    public func removeServerJSON(name: String, userId: String? = nil) throws -> NapaxiJSONValue {
        try call("mcp", "remove_server", ["name": .string(name), "user_id": .string(effectiveUserId(userId))])
    }

    public func removeServerJSON(_ name: String, userId: String? = nil) throws -> NapaxiJSONValue {
        try removeServerJSON(name: name, userId: userId)
    }

    public func removeServerOrFalse(name: String, userId: String? = nil) -> Bool {
        (try? removeServer(name: name, userId: userId)) ?? false
    }

    public func removeServerOrFalse(_ name: String, userId: String? = nil) -> Bool {
        removeServerOrFalse(name: name, userId: userId)
    }

    public func listServers(userId: String? = nil) throws -> [NapaxiMcpServerInfo] {
        do {
            return try Self.decodeMcpServerInfos(from: listServersJSON(userId: userId))
        } catch {
            return []
        }
    }

    public func listServersJSON(userId: String? = nil) throws -> NapaxiJSONValue {
        try call("mcp", "list_servers", ["user_id": .string(effectiveUserId(userId))])
    }

    public func listServersOrEmpty(userId: String? = nil) -> [NapaxiMcpServerInfo] {
        (try? listServers(userId: userId)) ?? []
    }

    public func activateServer(name: String, userId: String? = nil) throws -> NapaxiMcpServerActionResult {
        do {
            return try Self.decodeMcpServerActionResult(from: activateServerJSON(name: name, userId: userId))
        } catch {
            return NapaxiMcpServerActionResult(name: name, error: mcpFailureMessage("activate", error))
        }
    }

    public func activateServerJSON(name: String, userId: String? = nil) throws -> NapaxiJSONValue {
        try call("mcp", "activate_server", ["name": .string(name), "user_id": .string(effectiveUserId(userId))])
    }

    public func activate(_ name: String, userId: String? = nil) throws -> NapaxiMcpServerActionResult {
        try activateServer(name: name, userId: userId)
    }

    public func activateJSON(_ name: String, userId: String? = nil) throws -> NapaxiJSONValue {
        try activateServerJSON(name: name, userId: userId)
    }

    public func activateServerOrError(name: String, userId: String? = nil) -> NapaxiMcpServerActionResult {
        do {
            return try activateServer(name: name, userId: userId)
        } catch {
            return NapaxiMcpServerActionResult(name: name, error: mcpFailureMessage("activate", error))
        }
    }

    public func activateOrError(_ name: String, userId: String? = nil) -> NapaxiMcpServerActionResult {
        activateServerOrError(name: name, userId: userId)
    }

    public func deactivateServer(name: String, userId: String? = nil) throws -> Bool {
        do {
            return try success(from: deactivateServerJSON(name: name, userId: userId))
        } catch {
            return false
        }
    }

    public func deactivateServerJSON(name: String, userId: String? = nil) throws -> NapaxiJSONValue {
        try call("mcp", "deactivate_server", ["name": .string(name), "user_id": .string(effectiveUserId(userId))])
    }

    public func deactivate(_ name: String, userId: String? = nil) throws -> Bool {
        try deactivateServer(name: name, userId: userId)
    }

    public func deactivateJSON(_ name: String, userId: String? = nil) throws -> NapaxiJSONValue {
        try deactivateServerJSON(name: name, userId: userId)
    }

    public func deactivateServerOrFalse(name: String, userId: String? = nil) -> Bool {
        (try? deactivateServer(name: name, userId: userId)) ?? false
    }

    public func deactivateOrFalse(_ name: String, userId: String? = nil) -> Bool {
        deactivateServerOrFalse(name: name, userId: userId)
    }

    public func listTools(serverName: String? = nil, userId: String? = nil) throws -> [NapaxiMcpToolInfo] {
        do {
            return try Self.decodeMcpToolInfos(from: listToolsJSON(serverName: serverName, userId: userId))
        } catch {
            return []
        }
    }

    public func listToolsJSON(serverName: String? = nil, userId: String? = nil) throws -> NapaxiJSONValue {
        try call("mcp", "list_tools", ["server_name": .string(serverName ?? ""), "user_id": .string(effectiveUserId(userId))])
    }

    public func listToolsOrEmpty(serverName: String? = nil, userId: String? = nil) -> [NapaxiMcpToolInfo] {
        (try? listTools(serverName: serverName, userId: userId)) ?? []
    }

    public func startOAuth(
        name: String,
        userId: String? = nil,
        redirectURI: String = "napaxi://oauth/mcp",
        clientId: String? = nil,
        clientSecret: String? = nil,
        authorizationUrl: String? = nil,
        tokenUrl: String? = nil,
        scopes: [String] = [],
        usePKCE: Bool? = nil,
        extraParams: [String: String] = [:],
        resource: String? = nil
    ) throws -> NapaxiMcpOAuthStartResult {
        do {
            var oauth: [String: NapaxiJSONValue] = [:]
            setNonEmpty(&oauth, "client_id", clientId)
            setNonEmpty(&oauth, "client_secret", clientSecret)
            setNonEmpty(&oauth, "authorization_url", authorizationUrl)
            setNonEmpty(&oauth, "token_url", tokenUrl)
            if !scopes.isEmpty {
                oauth["scopes"] = .array(scopes.map { .string($0) })
            }
            if let usePKCE {
                oauth["use_pkce"] = .bool(usePKCE)
            }
            if !extraParams.isEmpty {
                oauth["extra_params"] = .object(extraParams.mapValues { .string($0) })
            }
            setNonEmpty(&oauth, "resource", resource)
            return try Self.decodeMcpOAuthStartResult(from: startOAuthJSON(
                name: name,
                userId: userId,
                redirectURI: redirectURI,
                oauthJSON: try oauth.jsonString()
            ))
        } catch {
            return NapaxiMcpOAuthStartResult(
                name: name,
                authorizationUrl: "",
                state: "",
                redirectUri: redirectURI,
                error: mcpFailureMessage("startOAuth", error)
            )
        }
    }

    public func startOAuth(
        _ name: String,
        userId: String? = nil,
        redirectUri: String = "napaxi://oauth/mcp",
        clientId: String? = nil,
        clientSecret: String? = nil,
        authorizationUrl: String? = nil,
        tokenUrl: String? = nil,
        scopes: [String] = [],
        usePkce: Bool? = nil,
        extraParams: [String: String] = [:],
        resource: String? = nil
    ) throws -> NapaxiMcpOAuthStartResult {
        try startOAuth(
            name: name,
            userId: userId,
            redirectURI: redirectUri,
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationUrl: authorizationUrl,
            tokenUrl: tokenUrl,
            scopes: scopes,
            usePKCE: usePkce,
            extraParams: extraParams,
            resource: resource
        )
    }

    public func startOAuthJSON(name: String, userId: String? = nil, redirectURI: String = "napaxi://oauth/mcp", oauthJSON: String = "{}") throws -> NapaxiJSONValue {
        try call("mcp", "start_oauth", ["name": .string(name), "user_id": .string(effectiveUserId(userId)), "redirect_uri": .string(redirectURI), "oauth_json": .string(oauthJSON)])
    }

    public func startOAuthJSON(_ name: String, userId: String? = nil, redirectUri: String = "napaxi://oauth/mcp", oauthJSON: String = "{}") throws -> NapaxiJSONValue {
        try startOAuthJSON(name: name, userId: userId, redirectURI: redirectUri, oauthJSON: oauthJSON)
    }

    public func startOAuthOrError(
        name: String,
        userId: String? = nil,
        redirectURI: String = "napaxi://oauth/mcp",
        clientId: String? = nil,
        clientSecret: String? = nil,
        authorizationUrl: String? = nil,
        tokenUrl: String? = nil,
        scopes: [String] = [],
        usePKCE: Bool? = nil,
        extraParams: [String: String] = [:],
        resource: String? = nil
    ) -> NapaxiMcpOAuthStartResult {
        do {
            return try startOAuth(
                name: name,
                userId: userId,
                redirectURI: redirectURI,
                clientId: clientId,
                clientSecret: clientSecret,
                authorizationUrl: authorizationUrl,
                tokenUrl: tokenUrl,
                scopes: scopes,
                usePKCE: usePKCE,
                extraParams: extraParams,
                resource: resource
            )
        } catch {
            return NapaxiMcpOAuthStartResult(
                name: name,
                authorizationUrl: "",
                state: "",
                redirectUri: redirectURI,
                error: mcpFailureMessage("startOAuth", error)
            )
        }
    }

    public func startOAuthOrError(
        _ name: String,
        userId: String? = nil,
        redirectUri: String = "napaxi://oauth/mcp",
        clientId: String? = nil,
        clientSecret: String? = nil,
        authorizationUrl: String? = nil,
        tokenUrl: String? = nil,
        scopes: [String] = [],
        usePkce: Bool? = nil,
        extraParams: [String: String] = [:],
        resource: String? = nil
    ) -> NapaxiMcpOAuthStartResult {
        startOAuthOrError(
            name: name,
            userId: userId,
            redirectURI: redirectUri,
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationUrl: authorizationUrl,
            tokenUrl: tokenUrl,
            scopes: scopes,
            usePKCE: usePkce,
            extraParams: extraParams,
            resource: resource
        )
    }

    public func finishOAuth(name: String, userId: String? = nil, code: String, state: String) throws -> NapaxiMcpServerActionResult {
        do {
            return try Self.decodeMcpServerActionResult(from: finishOAuthJSON(name: name, userId: userId, code: code, state: state))
        } catch {
            return NapaxiMcpServerActionResult(name: name, error: mcpFailureMessage("finishOAuth", error))
        }
    }

    public func finishOAuth(_ name: String, userId: String? = nil, code: String, state: String) throws -> NapaxiMcpServerActionResult {
        try finishOAuth(name: name, userId: userId, code: code, state: state)
    }

    public func finishOAuthJSON(name: String, userId: String? = nil, code: String, state: String) throws -> NapaxiJSONValue {
        try call("mcp", "finish_oauth", ["name": .string(name), "user_id": .string(effectiveUserId(userId)), "code": .string(code), "state": .string(state)])
    }

    public func finishOAuthJSON(_ name: String, userId: String? = nil, code: String, state: String) throws -> NapaxiJSONValue {
        try finishOAuthJSON(name: name, userId: userId, code: code, state: state)
    }

    public func finishOAuthOrError(name: String, userId: String? = nil, code: String, state: String) -> NapaxiMcpServerActionResult {
        do {
            return try finishOAuth(name: name, userId: userId, code: code, state: state)
        } catch {
            return NapaxiMcpServerActionResult(name: name, error: mcpFailureMessage("finishOAuth", error))
        }
    }

    public func finishOAuthOrError(_ name: String, userId: String? = nil, code: String, state: String) -> NapaxiMcpServerActionResult {
        finishOAuthOrError(name: name, userId: userId, code: code, state: state)
    }

    static func decodeMcpServerInfos(from value: NapaxiJSONValue) throws -> [NapaxiMcpServerInfo] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateMcpServerInfoObject(object)
            return NapaxiMcpServerInfo.fromMap(object)
        }
    }

    static func decodeMcpToolInfos(from value: NapaxiJSONValue) throws -> [NapaxiMcpToolInfo] {
        try decodeJsonObjectListFromValue(value) { object in
            try validateMcpToolInfoObject(object)
            return NapaxiMcpToolInfo.fromMap(object)
        }
    }

    static func decodeMcpServerActionResult(from value: NapaxiJSONValue) throws -> NapaxiMcpServerActionResult {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected MCP server action result object")
        }
        try validateMcpServerActionResultObject(object)
        return NapaxiMcpServerActionResult.fromMap(object)
    }

    static func decodeMcpOAuthStartResult(from value: NapaxiJSONValue) throws -> NapaxiMcpOAuthStartResult {
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected MCP OAuth start result object")
        }
        try validateMcpOAuthStartResultObject(object)
        return NapaxiMcpOAuthStartResult.fromMap(object)
    }

    private func effectiveUserId(_ userId: String?) -> String {
        let trimmed = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? defaultUserId : trimmed
    }

    private func success(from value: NapaxiJSONValue) throws -> Bool {
        if case .bool(let success) = value {
            return success
        }
        guard case .object(let object) = value else {
            throw NapaxiError.invalidJSON("Expected MCP success JSON object")
        }
        return object["success"]?.boolValue ?? false
    }

    private func stringMapJSON(_ map: [String: String]) throws -> String {
        try map.mapValues { NapaxiJSONValue.string($0) }.jsonString()
    }

    private func setNonEmpty(_ object: inout [String: NapaxiJSONValue], _ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        object[key] = .string(value)
    }

    private func mcpFailureMessage(_ operation: String, _ error: Error) -> String {
        "\(operation) failed: \(String(describing: error))"
    }
}
