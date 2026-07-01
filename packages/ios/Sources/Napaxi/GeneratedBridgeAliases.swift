import Foundation

private func napaxiBridgeJSON(_ value: NapaxiJSONValue) throws -> String {
    let data = try JSONEncoder().encode(value)
    return String(data: data, encoding: .utf8) ?? "null"
}

public func registerAgentAppPackage(handle: Int64, packageJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAppAPI(rawAPI: NapaxiRawAPI(handle: handle)).registerPackageJSON(packageJSON: packageJson))
}

public func listAgentAppPackages(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAppAPI(rawAPI: NapaxiRawAPI(handle: handle)).listPackagesJSON())
}

public func getAgentAppPackage(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAppAPI(rawAPI: NapaxiRawAPI(handle: handle)).getPackageJSON(agentId: agentId))
}

public func deleteAgentAppPackage(handle: Int64, agentId: String) throws -> Bool {
    try NapaxiAgentAppAPI(rawAPI: NapaxiRawAPI(handle: handle)).deletePackage(agentId: agentId)
}

public func submitAgentAppActionResult(handle: Int64, resultJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAppAPI(rawAPI: NapaxiRawAPI(handle: handle)).submitActionResultJSON(resultJSON: resultJson))
}

public func listAgentAppActionProposals(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAppAPI(rawAPI: NapaxiRawAPI(handle: handle)).listProposalsJSON(agentId: agentId))
}

public func getAgentAppActionProposal(handle: Int64, requestId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAppAPI(rawAPI: NapaxiRawAPI(handle: handle)).getProposalJSON(requestId: requestId))
}

public func acceptAgentAppTrigger(handle: Int64, triggerJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAppAPI(rawAPI: NapaxiRawAPI(handle: handle)).acceptTrigger(triggerJSON: triggerJson))
}

public func listCapabilityDefinitionsJson() throws -> String {
    try napaxiBridgeJSON(NapaxiNativeBridge.call(handle: 0, namespace: "capability", method: "list_definitions", payload: [:]))
}

public func listCapabilityStatusJson(handle: Int64, profileJson: String, selectionJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: handle)).listStatusJSON(
        profileJSON: profileJson,
        selectionJSON: selectionJson
    ))
}

public func listScenarioPacksJson(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: handle)).listScenarioPacksJSON())
}

public func installScenarioPackJson(handle: Int64, packJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: handle)).installScenarioPackJSON(packJSON: packJson))
}

public func removeScenarioPackJson(handle: Int64, scenarioId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: handle)).removeScenarioPackJSON(scenarioId: scenarioId))
}

public func listScenarioStatusJson(handle: Int64, profileJson: String, selectionJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: handle)).listScenarioStatusJSON(
        profileJSON: profileJson,
        selectionJSON: selectionJson
    ))
}

public func resolveScenarioJson(handle: Int64, profileJson: String, selectionJson: String, scenarioId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: handle)).resolveScenarioJSON(
        scenarioId: scenarioId,
        profileJSON: profileJson,
        selectionJSON: selectionJson
    ))
}

public func providerCapabilityId(provider: String) throws -> String {
    try NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: 0)).providerCapabilityId(provider)
}

public func agentEngineCapabilityId(engineId: String) throws -> String {
    try NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: 0)).agentEngineCapabilityId(engineId)
}

public func toolCapabilityId(toolName: String) throws -> String {
    try NapaxiCapabilityAPI(rawAPI: NapaxiRawAPI(handle: 0)).toolCapabilityId(toolName)
}

public func listChannels(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiChannelAPI(rawAPI: NapaxiRawAPI(handle: handle)).list())
}

public func registerChannel(handle: Int64, configJson: String) throws -> Bool {
    try NapaxiChannelAPI(rawAPI: NapaxiRawAPI(handle: handle)).registerChannel(configJSON: configJson)
}

public func unregisterChannel(handle: Int64, channelName: String) throws -> Bool {
    try NapaxiChannelAPI(rawAPI: NapaxiRawAPI(handle: handle)).unregisterChannel(channelName)
}

public func registerToolRequestStream() -> AsyncStream<String> {
    // Swift registers host tool routing during NapaxiEngine.create(...).
    AsyncStream { continuation in continuation.finish() }
}

public func toolBrokerListTools(handle: Int64, requestJson: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiNativeBridge.call(
        handle: handle,
        namespace: "tools",
        method: "tool_broker_list_tools",
        payload: ["request_json": .string(requestJson)]
    ))
}

public func toolBrokerCallTool(handle: Int64, requestJson: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiNativeBridge.call(
        handle: handle,
        namespace: "tools",
        method: "tool_broker_call_tool",
        payload: ["request_json": .string(requestJson)]
    ))
}

public func agentEngineRunEvent(requestJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiNativeBridge.call(
        handle: 0,
        namespace: "agent_engine",
        method: "run_event",
        payload: ["request_json": .string(requestJson)]
    ))
}

public func updateCustomTools(handle: Int64, toolsJson: String) throws -> Bool {
    try NapaxiNativeBridge.updateCustomTools(handle: handle, toolsJSON: toolsJson)
}

public func resolveToolExecution(requestId: UInt64, result: String, isError: Bool) throws -> Bool {
    try NapaxiNativeBridge.resolveToolExecution(requestId: requestId, resultJSON: result, isError: isError)
}

public func platformToolDescriptorsJson() throws -> String {
    try NapaxiCustomToolDefinition.jsonString(for: NapaxiPlatformToolProvider.getToolDefinitions())
}

public func isPlatformTool(name: String) -> Bool {
    NapaxiPlatformToolProvider.isPlatformTool(name)
}

public func browserToolDescriptorsJson() throws -> String {
    try NapaxiCustomToolDefinition.jsonString(for: NapaxiBrowserToolProvider.getToolDefinitions())
}

public func isBrowserTool(name: String) -> Bool {
    NapaxiBrowserToolProvider.isBrowserTool(name)
}

public func createEngine(configJson: String, platformContextJson: String) throws -> Int64 {
    try NapaxiNativeBridge.createEngine(configJSON: configJson, platformContextJSON: platformContextJson)
}

public func ensureAgentReady(handle: Int64, configJson: String) throws -> Bool {
    try NapaxiNativeBridge.ensureAgentReady(handle: handle, configJSON: configJson)
}

public func sendMessage(
    handle: Int64,
    configJson: String,
    message: String,
    attachmentsJson: String,
    maxIterations: Int
) async throws -> String {
    try napaxiBridgeJSON(NapaxiNativeBridge.sendMessage(
        handle: handle,
        configJSON: configJson,
        message: message,
        attachmentsJSON: attachmentsJson,
        maxIterations: NapaxiChatDefaults.bridgeMaxIterations(maxIterations)
    ))
}

public func sendToSession(
    handle: Int64,
    configJson: String,
    agentId: String,
    sessionKeyJson: String,
    message: String,
    attachmentsJson: String,
    maxIterations: Int
) async throws -> String {
    try napaxiBridgeJSON(NapaxiNativeBridge.sendToSession(
        handle: handle,
        configJSON: configJson,
        agentId: agentId,
        sessionKeyJSON: sessionKeyJson,
        message: message,
        attachmentsJSON: attachmentsJson,
        maxIterations: NapaxiChatDefaults.bridgeMaxIterations(maxIterations)
    ))
}

public func sendMessageStream(
    handle: Int64,
    configJson: String,
    message: String,
    attachmentsJson: String,
    maxIterations: Int
) -> AsyncThrowingStream<String, Error> {
    napaxiEventJSONStream(NapaxiNativeBridge.sendMessageStream(
        handle: handle,
        configJSON: configJson,
        message: message,
        attachmentsJSON: attachmentsJson,
        maxIterations: NapaxiChatDefaults.bridgeMaxIterations(maxIterations)
    ))
}

public func sendToSessionStream(
    handle: Int64,
    configJson: String,
    agentId: String,
    sessionKeyJson: String,
    message: String,
    attachmentsJson: String,
    maxIterations: Int
) -> AsyncThrowingStream<String, Error> {
    napaxiEventJSONStream(NapaxiNativeBridge.sendToSessionStream(
        handle: handle,
        configJSON: configJson,
        agentId: agentId,
        sessionKeyJSON: sessionKeyJson,
        message: message,
        attachmentsJSON: attachmentsJson,
        maxIterations: NapaxiChatDefaults.bridgeMaxIterations(maxIterations)
    ))
}

public func updateConfig(handle: Int64, configJson: String) throws -> Bool {
    try NapaxiNativeBridge.updateConfig(handle: handle, configJSON: configJson)
}

public func getConfig(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiNativeBridge.getConfig(handle: handle))
}

public func disposeEngine(handle: Int64) {
    NapaxiNativeBridge.disposeEngine(handle: handle)
}

public func mcpAddServer(
    handle: Int64,
    name: String,
    url: String,
    headersJson: String,
    userId: String
) async throws -> String {
    try napaxiBridgeJSON(NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: handle)).addServerJSON(
        name: name,
        url: url,
        headersJSON: headersJson,
        userId: userId
    ))
}

public func mcpRemoveServer(handle: Int64, name: String, userId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: handle)).removeServerJSON(name: name, userId: userId))
}

public func mcpListServers(handle: Int64, userId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: handle)).listServersJSON(userId: userId))
}

public func mcpActivateServer(handle: Int64, name: String, userId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: handle)).activateServerJSON(name: name, userId: userId))
}

public func mcpStartOauth(
    handle: Int64,
    name: String,
    userId: String,
    redirectUri: String,
    oauthJson: String
) async throws -> String {
    try napaxiBridgeJSON(NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: handle)).startOAuthJSON(
        name: name,
        userId: userId,
        redirectURI: redirectUri,
        oauthJSON: oauthJson
    ))
}

public func mcpFinishOauth(
    handle: Int64,
    name: String,
    userId: String,
    code: String,
    state: String
) async throws -> String {
    try napaxiBridgeJSON(NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: handle)).finishOAuthJSON(
        name: name,
        userId: userId,
        code: code,
        state: state
    ))
}

public func mcpDeactivateServer(handle: Int64, name: String, userId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: handle)).deactivateServerJSON(name: name, userId: userId))
}

public func mcpListTools(handle: Int64, serverName: String, userId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: handle)).listToolsJSON(
        serverName: serverName,
        userId: userId
    ))
}

public func listSessionRuns(handle: Int64, filterJson: String, limit: Int64, offset: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiSessionRunAPI(rawAPI: NapaxiRawAPI(handle: handle)).listJSON(
        filterJSON: filterJson,
        limit: Int(limit),
        offset: Int(offset)
    ))
}

public func getSessionRun(handle: Int64, runId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSessionRunAPI(rawAPI: NapaxiRawAPI(handle: handle)).getJSON(runId))
}

public func getActiveSessionRuns(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiSessionRunAPI(rawAPI: NapaxiRawAPI(handle: handle)).activeJSON())
}

public func getOrCreateAgent(handle: Int64, agentId: String, configJson: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAPI(rawAPI: NapaxiRawAPI(handle: handle)).getOrCreateJSON(agentId, configJSON: configJson))
}

public func listAgents(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAPI(rawAPI: NapaxiRawAPI(handle: handle)).listJSON())
}

public func deleteAgent(handle: Int64, agentId: String) throws -> Bool {
    try NapaxiAgentAPI(rawAPI: NapaxiRawAPI(handle: handle)).delete(agentId)
}

public func agentSend(
    handle: Int64,
    agentId: String,
    configJson: String,
    sessionKeyJson: String,
    message: String,
    maxIterations: Int
) async throws -> String {
    try napaxiBridgeJSON(NapaxiAgentAPI(rawAPI: NapaxiRawAPI(handle: handle)).sendJSON(
        agentId: agentId,
        configJSON: configJson,
        sessionKeyJSON: sessionKeyJson,
        message: message,
        maxIterations: maxIterations
    ))
}

public func createAgentDefinition(handle: Int64, defJson: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiAgentDefinitionAPI(rawAPI: NapaxiRawAPI(handle: handle)).createJSON(definitionJSON: defJson))
}

public func updateAgentDefinition(handle: Int64, defJson: String) async throws -> Bool {
    try NapaxiAgentDefinitionAPI(rawAPI: NapaxiRawAPI(handle: handle)).updateJSON(definitionJSON: defJson).requiredBool()
}

public func deleteAgentDefinition(handle: Int64, defId: String) async throws -> Bool {
    try NapaxiAgentDefinitionAPI(rawAPI: NapaxiRawAPI(handle: handle)).delete(defId)
}

public func listAgentDefinitions(handle: Int64) async throws -> String {
    try napaxiBridgeJSON(NapaxiAgentDefinitionAPI(rawAPI: NapaxiRawAPI(handle: handle)).listJSON())
}

public func getAgentDefinition(handle: Int64, defId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiAgentDefinitionAPI(rawAPI: NapaxiRawAPI(handle: handle)).getJSON(defId))
}

public func listAvailableTools(handle: Int64) async throws -> String {
    try napaxiBridgeJSON(NapaxiAgentDefinitionAPI(rawAPI: NapaxiRawAPI(handle: handle)).listAvailableToolsJSON())
}

public func createAgentFromDefinition(handle: Int64, defId: String, configJson: String) async throws -> Int64 {
    try NapaxiAgentDefinitionAPI(rawAPI: NapaxiRawAPI(handle: handle))
        .createFromDefinitionJSON(defId, configJSON: configJson)
        .requiredBool() ? 1 : 0
}

public func importAgentMd(handle: Int64, content: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiAgentDefinitionAPI(rawAPI: NapaxiRawAPI(handle: handle)).importMarkdownJSON(content))
}

public func createAutomationJob(handle: Int64, jobJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).createJobJSON(jobJSON: jobJson))
}

public func updateAutomationJob(handle: Int64, jobId: String, patchJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).updateJobJSON(jobId: jobId, patchJSON: patchJson))
}

public func deleteAutomationJob(handle: Int64, jobId: String) throws -> Bool {
    try NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).deleteJob(jobId)
}

public func listAutomationJobs(handle: Int64, filterJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).listJobsJSON(filterJSON: filterJson))
}

public func getAutomationJob(handle: Int64, jobId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).getJobJSON(jobId))
}

public func runAutomationJob(handle: Int64, jobId: String, mode: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).runJobJSON(jobId, mode: mode))
}

public func listAutomationRuns(handle: Int64, jobId: String? = nil, limit: Int64, offset: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).listRunsJSON(
        jobId: jobId,
        limit: Int(limit),
        offset: Int(offset)
    ))
}

public func getNextAutomationWake(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).nextWakeJSON())
}

public func recordAutomationWake(handle: Int64, jobId: String, source: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiAutomationAPI(rawAPI: NapaxiRawAPI(handle: handle)).recordWakeJSON(jobId: jobId, source: source))
}

public func listPendingEvolution(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiEvolutionAPI(rawAPI: NapaxiRawAPI(handle: handle)).listPendingJSON())
}

public func listEvolutionRuns(handle: Int64, runIdsJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiEvolutionAPI(rawAPI: NapaxiRawAPI(handle: handle)).listRunsJSON(runIdsJSON: runIdsJson))
}

public func listEvolutionDiagnostics(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiEvolutionAPI(rawAPI: NapaxiRawAPI(handle: handle)).listDiagnosticsJSON())
}

public func rejectPendingEvolution(handle: Int64, pendingId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiEvolutionAPI(rawAPI: NapaxiRawAPI(handle: handle)).rejectPendingJSON(pendingId))
}

public func applyPendingEvolution(handle: Int64, pendingId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiEvolutionAPI(rawAPI: NapaxiRawAPI(handle: handle)).applyPendingJSON(pendingId))
}

public func runSkillConsolidationReview(handle: Int64, agentId: String, configJson: String, dryRun: Bool) throws -> String {
    try napaxiBridgeJSON(NapaxiEvolutionAPI(rawAPI: NapaxiRawAPI(handle: handle)).runSkillConsolidationReviewJSON(
        agentId: agentId,
        configJSON: configJson,
        dryRun: dryRun
    ))
}

public func saveMessageAttachments(handle: Int64, threadId: String, userMsgIndex: Int, attachmentsJson: String) throws -> Bool {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).saveMessageAttachments(
        threadId: threadId,
        userMsgIndex: userMsgIndex,
        attachmentsJson: attachmentsJson
    )
}

public func loadThreadAttachments(handle: Int64, threadId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).loadThreadAttachmentsJSON(threadId))
}

public func deleteThreadAttachments(handle: Int64, threadId: String) throws -> Bool {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).deleteThreadAttachments(threadId)
}

public func initFileBridge(handle: Int64) throws -> Bool {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).initFileBridge()
}

public func initFileBridgeScoped(handle: Int64, accountId: String, agentId: String) throws -> Bool {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).initFileBridgeScoped(accountId: accountId, agentId: agentId)
}

public func sandboxToReal(handle: Int64, sandboxPath: String) throws -> String? {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).sandboxToReal(sandboxPath)
}

public func sandboxToRealScoped(handle: Int64, accountId: String, agentId: String, sandboxPath: String) throws -> String? {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).sandboxToRealScoped(
        sandboxPath,
        accountId: accountId,
        agentId: agentId
    )
}

public func realToSandbox(handle: Int64, realPath: String) throws -> String? {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).realToSandbox(realPath)
}

public func realToSandboxScoped(handle: Int64, accountId: String, agentId: String, realPath: String) throws -> String? {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).realToSandboxScoped(
        realPath,
        accountId: accountId,
        agentId: agentId
    )
}

public func detectFileReferences(handle: Int64, text: String) throws -> String {
    try napaxiBridgeJSON(NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).call(
        "file_bridge",
        "detect_file_references",
        ["text": .string(text)]
    ))
}

public func detectFileReferencesScoped(handle: Int64, accountId: String, agentId: String, text: String) throws -> String {
    try napaxiBridgeJSON(NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).call(
        "file_bridge",
        "detect_file_references_scoped",
        ["account_id": .string(accountId), "agent_id": .string(agentId), "text": .string(text)]
    ))
}

public func deleteSandboxFile(handle: Int64, sandboxPath: String) async throws -> Bool {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).deleteSandboxFile(sandboxPath)
}

public func deleteSandboxFileScoped(handle: Int64, accountId: String, agentId: String, sandboxPath: String) async throws -> Bool {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).deleteSandboxFileScoped(
        sandboxPath,
        accountId: accountId,
        agentId: agentId
    )
}

public func listWorkspaceFilesystem(handle: Int64, subdir: String? = nil, recursive: Bool) async throws -> String {
    try napaxiBridgeJSON(NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).listWorkspaceFilesystemJSON(
        subdir: subdir,
        recursive: recursive
    ))
}

public func listWorkspaceFilesystemScoped(
    handle: Int64,
    accountId: String,
    agentId: String,
    subdir: String? = nil,
    recursive: Bool
) async throws -> String {
    try napaxiBridgeJSON(NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).listWorkspaceFilesystemScopedJSON(
        accountId: accountId,
        agentId: agentId,
        subdir: subdir,
        recursive: recursive
    ))
}

public func workspaceSize(handle: Int64) throws -> Int64 {
    Int64(try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).workspaceSize())
}

public func workspaceSizeScoped(handle: Int64, accountId: String, agentId: String) throws -> Int64 {
    Int64(try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).workspaceSizeScoped(accountId: accountId, agentId: agentId))
}

public func workspaceDir(handle: Int64) throws -> String {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).workspaceDir().stringValue ?? ""
}

public func workspaceDirScoped(handle: Int64, accountId: String, agentId: String) throws -> String {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).workspaceDirScoped(
        accountId: accountId,
        agentId: agentId
    ).stringValue ?? ""
}

public func rootfsDir(handle: Int64) throws -> String {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).rootfsDir().stringValue ?? ""
}

public func skillsDir(handle: Int64) throws -> String {
    try NapaxiFileBridgeAPI(rawAPI: NapaxiRawAPI(handle: handle)).skillsDir().stringValue ?? ""
}

public func createGroup(handle: Int64, name: String, membersJson: String) async throws -> String {
    try NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).createJSON(name: name, membersJSON: membersJson).requiredString()
}

public func deleteGroup(handle: Int64, groupId: String) throws -> Bool {
    try NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).delete(groupId)
}

public func listGroups(handle: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).listJSON())
}

public func getGroup(handle: Int64, groupId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).getJSON(groupId))
}

public func renameGroup(handle: Int64, groupId: String, newName: String) throws -> Bool {
    try NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).rename(groupId, newName: newName)
}

public func updateGroupMembers(handle: Int64, groupId: String, membersJson: String) async throws -> Bool {
    try NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).updateMembersJSON(groupId, membersJSON: membersJson).requiredBool()
}

public func setGroupCustomPrompt(handle: Int64, groupId: String, prompt: String? = nil) throws -> Bool {
    try NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).setCustomPrompt(groupId, prompt: prompt)
}

public func getGroupMessages(handle: Int64, groupId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).messagesJSON(groupId))
}

public func clearGroupHistory(handle: Int64, groupId: String) throws -> Bool {
    try NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).clearHistory(groupId)
}

public func sendToGroup(handle: Int64, groupId: String, configJson: String, message: String, maxIterations: Int) async throws -> String {
    try napaxiBridgeJSON(NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).sendJSON(
        groupId: groupId,
        configJSON: configJson,
        message: message,
        maxIterations: maxIterations
    ))
}

public func sendToGroupAgent(
    handle: Int64,
    groupId: String,
    agentId: String,
    configJson: String,
    sessionKeyJson: String,
    message: String,
    maxIterations: Int
) async throws -> String {
    try napaxiBridgeJSON(NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).sendToAgentJSON(
        groupId: groupId,
        agentId: agentId,
        configJSON: configJson,
        sessionKeyJSON: sessionKeyJson,
        message: message,
        maxIterations: maxIterations
    ))
}

public func exportGroupState(handle: Int64) throws -> String {
    try NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).exportState()
}

public func importGroupState(handle: Int64, stateJson: String) async throws -> Bool {
    try NapaxiGroupAPI(rawAPI: NapaxiRawAPI(handle: handle)).importState(stateJSON: stateJson)
}

public func getA2AAgentCard(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).agentCardJSON(agentId: agentId))
}

public func createA2APeerInvite(handle: Int64, agentId: String, optionsJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).createPeerInviteJSON(
        agentId: agentId,
        optionsJSON: optionsJson
    ))
}

public func acceptA2APeerInvite(handle: Int64, envelopeJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).acceptPeerInviteJSON(
        envelopeJSON: envelopeJson
    ))
}

public func listA2APeers(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).listPeersJSON(agentId: agentId))
}

public func deleteA2APeer(handle: Int64, peerId: String) throws -> Bool {
    try NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).deletePeer(peerId)
}

public func openA2APeerSession(handle: Int64, peerJson: String, transport: String, endpoint: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).openPeerSessionJSON(
        peerJSON: peerJson,
        transport: transport,
        endpoint: endpoint
    ))
}

public func listA2APeerSessions(handle: Int64, peerId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).listPeerSessionsJSON(peerId: peerId))
}

public func createA2ATaskMessage(handle: Int64, sessionId: String, message: String, optionsJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).createTaskMessageJSON(
        sessionId: sessionId,
        message: message,
        optionsJSON: optionsJson
    ))
}

public func createA2ATaskProgressMessage(handle: Int64, sessionId: String, taskId: String, message: String, progressJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).createTaskProgressMessageJSON(
        sessionId: sessionId,
        taskId: taskId,
        message: message,
        progressJSON: progressJson
    ))
}

public func createA2ATaskResultMessage(handle: Int64, sessionId: String, taskId: String, resultJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).createTaskResultMessageJSON(
        sessionId: sessionId,
        taskId: taskId,
        resultJSON: resultJson
    ))
}

public func recordA2APeerMessage(handle: Int64, messageJson: String, source: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).recordPeerMessageJSON(
        messageJSON: messageJson,
        source: source
    ))
}

public func recordA2ADeliveryStatus(handle: Int64, messageJson: String, status: String, error: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).recordDeliveryStatusJSON(
        messageJSON: messageJson,
        status: status,
        error: error
    ))
}

public func listA2APeerMessages(handle: Int64, sessionId: String, limit: Int64, offset: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).listPeerMessagesJSON(
        sessionId: sessionId,
        limit: Int(limit),
        offset: Int(offset)
    ))
}

public func listA2ADeliveryRecords(handle: Int64, sessionId: String, limit: Int64, offset: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).listDeliveryRecordsJSON(
        sessionId: sessionId,
        limit: Int(limit),
        offset: Int(offset)
    ))
}

public func acceptA2ADeepLink(handle: Int64, envelopeJson: String, source: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).acceptDeepLinkJSON(
        envelopeJSON: envelopeJson,
        source: source
    ))
}

public func runA2ATask(handle: Int64, taskId: String, mode: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).runTaskJSON(taskId, mode: mode))
}

public func listA2ATasks(handle: Int64, filterJson: String, limit: Int64, offset: Int64) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).listTasksJSON(
        filterJSON: filterJson,
        limit: Int(limit),
        offset: Int(offset)
    ))
}

public func getA2ATask(handle: Int64, taskId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).getTaskJSON(taskId))
}

public func buildA2AResultLink(handle: Int64, taskId: String, callbackUrl: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).buildResultLinkJSON(
        taskId: taskId,
        callbackUrl: callbackUrl
    ))
}

public func recordA2AResultEnvelope(handle: Int64, envelopeJson: String) throws -> String {
    try napaxiBridgeJSON(NapaxiA2AAPI(rawAPI: NapaxiRawAPI(handle: handle)).recordResultEnvelopeJSON(
        envelopeJSON: envelopeJson
    ))
}

public func listSkills(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).listJSON(agentId: agentId))
}

public func listSkillStatus(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).statusJSON(agentId: agentId))
}

public func listSkillSources(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).sourcesJSON(agentId: agentId))
}

public func recordSkillSourceChanged(handle: Int64, agentId: String, sourceId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).recordSourceChangedJSON(
        agentId: agentId,
        sourceId: sourceId
    ))
}

public func getSkillStatus(handle: Int64, agentId: String, skillName: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).getStatusJSON(
        agentId: agentId,
        skillName: skillName
    ))
}

public func checkSkills(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).checkJSON(agentId: agentId))
}

public func listSkillCommands(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).commandsJSON(agentId: agentId))
}

public func resolveSkillCommand(handle: Int64, agentId: String, text: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).resolveCommandJSON(text, agentId: agentId))
}

public func runSkillCommand(
    handle: Int64,
    agentId: String,
    commandName: String,
    args: String? = nil,
    sessionKeyJson: String? = nil
) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).runCommandJSON(
        commandName,
        agentId: agentId,
        args: args,
        sessionKeyJSON: sessionKeyJson
    ))
}

public func setSkillEnabled(handle: Int64, agentId: String, skillName: String, enabled: Bool) async throws -> String {
    try NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).setEnabled(
        agentId: agentId,
        skillName: skillName,
        enabled: enabled
    )
}

public func updateSkillConfig(handle: Int64, agentId: String, skillKey: String, patchJson: String) async throws -> String {
    try NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).updateConfigJSON(
        agentId: agentId,
        skillKey: skillKey,
        patchJSON: patchJson
    ).requiredString()
}

public func listSkillRemediationActions(handle: Int64, agentId: String, skillName: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).remediationActionsJSON(
        agentId: agentId,
        skillName: skillName
    ))
}

public func listSkillSnapshots(handle: Int64, agentId: String, limit: Int, offset: Int) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).snapshotsJSON(
        agentId: agentId,
        limit: limit,
        offset: offset
    ))
}

public func getSkillSnapshot(handle: Int64, snapshotId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).snapshotJSON(snapshotId))
}

public func listSkillSecretRequirements(handle: Int64, agentId: String, skillName: String? = nil) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).secretRequirementsJSON(
        agentId: agentId,
        skillName: skillName
    ))
}

public func recordSkillSecretAvailability(
    handle: Int64,
    agentId: String,
    skillName: String,
    key: String,
    available: Bool,
    source: String
) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).recordSecretAvailabilityJSON(
        agentId: agentId,
        skillName: skillName,
        key: key,
        available: available,
        source: source
    ))
}

public func requestSkillRemediation(handle: Int64, agentId: String, skillName: String, actionId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).requestRemediationJSON(
        agentId: agentId,
        skillName: skillName,
        actionId: actionId
    ))
}

public func updateSkillRemediationRun(
    handle: Int64,
    agentId: String,
    runId: String,
    status: String,
    resultJson: String? = nil
) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).updateRemediationRunJSON(
        agentId: agentId,
        runId: runId,
        status: status,
        resultJSON: resultJson
    ))
}

public func listSkillRemediationRuns(
    handle: Int64,
    agentId: String,
    skillName: String? = nil,
    limit: Int,
    offset: Int
) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).remediationRunsJSON(
        agentId: agentId,
        skillName: skillName,
        limit: limit,
        offset: offset
    ))
}

public func recordSkillRequirementResolution(
    handle: Int64,
    agentId: String,
    skillName: String,
    actionId: String,
    resultJson: String
) async throws -> String {
    try NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).recordRequirementResolutionJSON(
        agentId: agentId,
        skillName: skillName,
        actionId: actionId,
        resultJSON: resultJson
    ).requiredString()
}

public func installSkill(handle: Int64, agentId: String, skillContent: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).installJSON(
        agentId: agentId,
        skillContent: skillContent
    ))
}

public func removeSkill(handle: Int64, agentId: String, skillName: String) async throws -> Bool {
    try NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).remove(
        agentId: agentId,
        skillName: skillName
    )
}

public func reloadSkills(handle: Int64, agentId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).reloadJSON(agentId: agentId))
}

public func getSkill(handle: Int64, agentId: String, skillName: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).getJSON(
        agentId: agentId,
        skillName: skillName
    ))
}

public func listSkillUsage(handle: Int64, agentId: String) throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).usageJSON(agentId: agentId))
}

public func pinSkill(handle: Int64, agentId: String, skillName: String, pinned: Bool) async throws -> String {
    try NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).pin(
        agentId: agentId,
        skillName: skillName,
        pinned: pinned
    )
}

public func archiveSkill(handle: Int64, agentId: String, skillName: String) async throws -> String {
    try NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).archive(
        agentId: agentId,
        skillName: skillName
    )
}

public func restoreSkill(handle: Int64, agentId: String, skillName: String) async throws -> String {
    try NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).restore(
        agentId: agentId,
        skillName: skillName
    )
}

public func runSkillCurator(handle: Int64, agentId: String, dryRun: Bool) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).runCuratorJSON(
        agentId: agentId,
        dryRun: dryRun
    ))
}

public func readSkillSupportFile(handle: Int64, agentId: String, skillName: String, filePath: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).readSupportFileJSON(
        agentId: agentId,
        skillName: skillName,
        filePath: filePath
    ))
}

public func searchCatalog(query: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: 0)).searchCatalogJSON(query: query))
}

public func getCatalogSkill(slug: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: 0)).getCatalogSkillJSON(slug: slug))
}

public func installFromCatalog(handle: Int64, agentId: String, slug: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSkillAPI(rawAPI: NapaxiRawAPI(handle: handle)).installFromCatalogJSON(
        agentId: agentId,
        slug: slug
    ))
}

public func readWorkspaceFile(handle: Int64, accountId: String, agentId: String, path: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).readFileJSON(
        accountId: accountId,
        agentId: agentId,
        path: path
    ))
}

public func writeWorkspaceFile(
    handle: Int64,
    accountId: String,
    agentId: String,
    path: String,
    content: String
) async throws -> Bool {
    try NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).writeFile(
        path,
        content: content,
        accountId: accountId,
        agentId: agentId
    )
}

public func appendWorkspaceFile(
    handle: Int64,
    accountId: String,
    agentId: String,
    path: String,
    content: String
) async throws -> Bool {
    try NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).appendFile(
        path,
        content: content,
        accountId: accountId,
        agentId: agentId
    )
}

public func deleteWorkspaceFile(handle: Int64, accountId: String, agentId: String, path: String) async throws -> Bool {
    try NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).deleteFile(
        path,
        accountId: accountId,
        agentId: agentId
    )
}

public func listWorkspaceFiles(handle: Int64, accountId: String, agentId: String, directory: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).listFilesJSON(
        accountId: accountId,
        agentId: agentId,
        directory: directory
    ))
}

public func getSystemPrompt(handle: Int64, accountId: String, agentId: String) async throws -> String {
    try NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).systemPrompt(
        accountId: accountId,
        agentId: agentId
    )
}

public func reseedWorkspace(handle: Int64, accountId: String, agentId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).reseedJSON(
        accountId: accountId,
        agentId: agentId
    ))
}

public func searchMemory(
    handle: Int64,
    accountId: String,
    agentId: String,
    query: String,
    limit: Int
) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).searchMemoryJSON(
        accountId: accountId,
        agentId: agentId,
        query: query,
        limit: limit
    ))
}

public func recallSessions(
    handle: Int64,
    configJson: String,
    accountId: String,
    agentId: String,
    currentThreadId: String,
    query: String,
    limit: Int
) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).recallSessionsJSON(
        configJSON: configJson,
        accountId: accountId,
        agentId: agentId,
        currentThreadId: currentThreadId,
        query: query,
        limit: limit
    ))
}

public func rebuildRecallIndex(handle: Int64, accountId: String, agentId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).rebuildRecallIndexJSON(
        accountId: accountId,
        agentId: agentId
    ))
}

public func recallIndexStats(handle: Int64, accountId: String, agentId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).recallIndexStatsJSON(
        accountId: accountId,
        agentId: agentId
    ))
}

public func listJournalDays(handle: Int64, accountId: String, agentId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).listJournalDaysJSON(
        accountId: accountId,
        agentId: agentId
    ))
}

public func readJournalDay(handle: Int64, accountId: String, agentId: String, date: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiWorkspaceAPI(rawAPI: NapaxiRawAPI(handle: handle)).readJournalDayJSON(
        accountId: accountId,
        agentId: agentId,
        date: date
    ))
}

public func createSession(
    handle: Int64,
    configJson: String,
    agentId: String,
    channelType: String,
    accountId: String,
    existingThreadId: String? = nil
) async throws -> String {
    try napaxiBridgeJSON(NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).createJSON(
        agentId: agentId,
        channelType: channelType,
        accountId: accountId,
        existingThreadId: existingThreadId
    ))
}

public func listSessions(handle: Int64, configJson: String, agentId: String, accountId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).listJSON(agentId: agentId, accountId: accountId))
}

public func deleteSession(handle: Int64, configJson: String, agentId: String, sessionKeyJson: String) async throws -> Bool {
    try NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).deleteJSON(sessionKeyJSON: sessionKeyJson).requiredBool()
}

public func clearSession(handle: Int64, configJson: String, agentId: String, sessionKeyJson: String) async throws -> Bool {
    try NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).clearJSON(sessionKeyJSON: sessionKeyJson).requiredBool()
}

public func getHistory(handle: Int64, configJson: String, agentId: String, threadId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).historyJSON(threadId: threadId, agentId: agentId))
}

public func getHistoryPage(
    handle: Int64,
    configJson: String,
    agentId: String,
    threadId: String,
    before: String? = nil,
    limit: Int64
) async throws -> String {
    try napaxiBridgeJSON(NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).historyPageJSON(
        threadId: threadId,
        agentId: agentId,
        before: before,
        limit: Int(limit)
    ))
}

public func compactContext(
    handle: Int64,
    configJson: String,
    agentId: String,
    sessionKeyJson: String,
    focus: String? = nil
) async throws -> String {
    try napaxiBridgeJSON(NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).compactContextJSON(
        configJSON: configJson,
        agentId: agentId,
        sessionKeyJSON: sessionKeyJson,
        focus: focus
    ))
}

public func contextStatus(handle: Int64, configJson: String, agentId: String, threadId: String) async throws -> String {
    try napaxiBridgeJSON(NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).contextStatusJSON(
        configJSON: configJson,
        threadId: threadId,
        agentId: agentId
    ))
}

public func injectMessage(
    handle: Int64,
    configJson: String,
    agentId: String,
    sessionKeyJson: String,
    message: String,
    attachmentsJson: String
) async throws -> Bool {
    try NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).injectMessageJSON(
        configJSON: configJson,
        agentId: agentId,
        sessionKeyJSON: sessionKeyJson,
        message: message,
        attachmentsJSON: attachmentsJson
    ).requiredBool()
}

public func retractInjectedMessage(handle: Int64, sessionKeyJson: String, message: String) async throws -> Bool {
    try NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).retractInjectedMessageJSON(
        sessionKeyJSON: sessionKeyJson,
        message: message
    ).requiredBool()
}

public func answerHumanRequest(handle: Int64, requestId: String, response: String) async throws -> Bool {
    try NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).answerHumanRequest(requestId: requestId, response: response)
}

public func cancelSession(handle: Int64, configJson: String, agentId: String, sessionKeyJson: String) async throws -> Bool {
    try NapaxiSessionAPI(rawAPI: NapaxiRawAPI(handle: handle)).cancelJSON(sessionKeyJSON: sessionKeyJson).requiredBool()
}

private func napaxiEventJSONStream(
    _ events: AsyncThrowingStream<NapaxiChatEvent, Error>
) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        Task {
            do {
                for try await event in events {
                    continuation.yield(try napaxiBridgeJSON(event.raw))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}
