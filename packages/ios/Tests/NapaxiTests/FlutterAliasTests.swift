import XCTest
@testable import Napaxi

final class FlutterAliasTests: XCTestCase {
    func testPrimaryEngineAndFacadeAliasesCompile() {
        let chat: (NapaxiEngine) -> ChatApi = { $0.chat }
        let tools: (NapaxiEngine) -> ToolApi = { $0.tools }
        let capabilities: (NapaxiEngine) -> CapabilityApi = { $0.capabilities }
        let automation: (NapaxiEngine) -> AutomationApi = { $0.automation }
        let sessionRuns: (NapaxiEngine) -> SessionRunApi = { $0.sessionRuns }
        let agentApp: (NapaxiEngine) -> AgentAppApi = { $0.agentApp }
        let agents: (NapaxiEngine) -> AgentApi = { $0.agents }
        let sessions: (NapaxiEngine) -> SessionApi = { $0.sessions }
        let skills: (NapaxiEngine) -> SkillApi = { $0.skills }
        let evolution: (NapaxiEngine) -> EvolutionApi = { $0.evolution }
        let groups: (NapaxiEngine) -> GroupApi = { $0.groups }
        let workspace: (NapaxiEngine) -> WorkspaceApi = { $0.workspace }
        let background: (NapaxiEngine) -> BackgroundApi = { $0.background }
        let mcp: (NapaxiEngine) -> McpApi = { $0.mcp }

        XCTAssertNotNil(chat)
        XCTAssertNotNil(tools)
        XCTAssertNotNil(capabilities)
        XCTAssertNotNil(automation)
        XCTAssertNotNil(sessionRuns)
        XCTAssertNotNil(agentApp)
        XCTAssertNotNil(agents)
        XCTAssertNotNil(sessions)
        XCTAssertNotNil(skills)
        XCTAssertNotNil(evolution)
        XCTAssertNotNil(groups)
        XCTAssertNotNil(workspace)
        XCTAssertNotNil(background)
        XCTAssertNotNil(mcp)
    }

    func testFlutterModelAliasesCompileAndPreserveBehavior() throws {
        let key = SessionKey(threadId: "thread")
        let attachment = McAttachment(kind: "text", mimeType: "text/plain", dataBase64: "aGVsbG8=")
        let run = SessionRunInfo(
            key: key,
            agentId: "napaxi",
            status: .running,
            activity: "Starting",
            humanRequestId: "human-1",
            error: "old error",
            startedAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
        let copiedRun = run.copyWith(
            status: .waitingForInput,
            activity: "Waiting",
            clearHumanRequest: true,
            clearError: true,
            updatedAt: Date(timeIntervalSince1970: 1)
        )
        let copiedWithoutUpdatedAt = run.copyWith(activity: "Still starting")
        let event = ChatEvent(raw: .object(["type": .string("response"), "message": .string("hi")]))
        let backgroundConfig = BackgroundConfig(enabled: false)
        let notificationConfig = NotificationConfig(ongoingTitle: "Agent")
        let actionEvent = BackgroundActionEvent(action: .viewResult, requestId: "r1")

        XCTAssertEqual(key.threadId, "thread")
        XCTAssertEqual(attachment.mimeType, "text/plain")
        XCTAssertEqual(run.status, SessionRunStatus.running)
        XCTAssertEqual(copiedRun.status, .waitingForInput)
        XCTAssertEqual(copiedRun.activity, "Waiting")
        XCTAssertNil(copiedRun.humanRequestId)
        XCTAssertNil(copiedRun.error)
        XCTAssertEqual(copiedRun.startedAt, run.startedAt)
        XCTAssertEqual(copiedRun.updatedAt, Date(timeIntervalSince1970: 1))
        XCTAssertEqual(copiedWithoutUpdatedAt.activity, "Still starting")
        XCTAssertEqual(copiedWithoutUpdatedAt.updatedAt, run.updatedAt)
        XCTAssertEqual(event.type, "response")
        XCTAssertFalse(backgroundConfig.enabled)
        XCTAssertEqual(notificationConfig.ongoingTitle, "Agent")
        XCTAssertEqual(actionEvent.action, BackgroundAction.viewResult)
    }

    func testAttachmentMapHelpersMirrorFlutterMcAttachment() throws {
        let attachment = McAttachment(
            kind: "document",
            mimeType: "text/plain",
            filename: "notes.txt",
            sandboxPath: "/workspace/original.txt",
            localPath: "/tmp/notes.txt",
            data: Data("hello".utf8),
            extractedText: "hello"
        )

        XCTAssertEqual(attachment.data, Data("hello".utf8))
        XCTAssertEqual(attachment.toMap(sandboxPath: "/workspace/restored.txt"), [
            "kind": .string("document"),
            "mime_type": .string("text/plain"),
            "filename": .string("notes.txt"),
            "sandbox_path": .string("/workspace/restored.txt"),
            "path": .string("/tmp/notes.txt"),
            "data_base64": .string("aGVsbG8="),
            "extracted_text": .string("hello"),
        ])

        let raw = try NapaxiRawJSON(jsonString: McAttachment.jsonString(for: [attachment])).value
        XCTAssertEqual(raw, .array([
            .object([
                "kind": .string("document"),
                "mime_type": .string("text/plain"),
                "filename": .string("notes.txt"),
                "sandbox_path": .string("/workspace/original.txt"),
                "path": .string("/tmp/notes.txt"),
                "data_base64": .string("aGVsbG8="),
                "extracted_text": .string("hello"),
            ]),
        ]))
    }

    func testFlutterChatEventNameAliasesCompile() {
        let runCompleted: RunCompletedEvent = .fromMap(["type": .string("run_completed"), "status": .string("completed")])
        let toolCall: ToolCallEvent = .fromMap(["type": .string("tool_call"), "name": .string("shell")])
        let response: ResponseEvent = .fromMap(["type": .string("response"), "content": .string("done")])
        let askingHuman: AskingHumanEvent = .fromMap(["type": .string("asking_human"), "question": .string("Continue?")])
        let actionResult: ActionResultReceivedEvent = .fromMap(["type": .string("action_result_received"), "status": .string("succeeded")])
        let interrupted: InterruptedEvent = .fromMap(["type": .string("interrupted")])
        let streamReset: StreamResetEvent = .fromMap(["type": .string("stream_reset"), "reason": .string("dropped")])

        XCTAssertEqual(runCompleted.status, "completed")
        XCTAssertEqual(toolCall.name, "shell")
        XCTAssertEqual(response.content, "done")
        XCTAssertEqual(askingHuman.question, "Continue?")
        XCTAssertEqual(actionResult.status, "succeeded")
        XCTAssertEqual(interrupted.type, "interrupted")
        XCTAssertEqual(streamReset.type, "stream_reset")
        XCTAssertEqual(streamReset.reason, "dropped")
    }

    func testFlutterStableModelAliasesCompile() {
        let agent: AgentHandle = AgentHandle(raw: ["id": .string("napaxi")])
        let definition: AgentDefinition = AgentDefinition(raw: ["id": .string("planner")])
        let workspaceFile: WorkspaceFile = WorkspaceFile(raw: ["path": .string("/workspace/a.txt")])
        let skill: SkillInfo = SkillInfo(raw: ["name": .string("search")])
        let package: AgentAppPackage = AgentAppPackage(raw: ["agent_id": .string("provider")])
        let mcpTool: McpToolInfo = McpToolInfo(raw: ["name": .string("lookup")])
        let runRecord: SessionRunRecord = SessionRunRecord(raw: ["id": .string("run-1")])
        let customTool = CustomToolDef(name: "lookup", description: "Look up data")

        XCTAssertEqual(agent.string("id"), "napaxi")
        XCTAssertEqual(definition.string("id"), "planner")
        XCTAssertEqual(workspaceFile.string("path"), "/workspace/a.txt")
        XCTAssertEqual(skill.string("name"), "search")
        XCTAssertEqual(package.string("agent_id"), "provider")
        XCTAssertEqual(mcpTool.string("name"), "lookup")
        XCTAssertEqual(runRecord.string("id"), "run-1")
        XCTAssertEqual(customTool.name, "lookup")
    }

    func testFlutterCapabilityConfigAndProviderAliasesCompile() {
        let profile = NapaxiConfigProfile(id: "default", name: "Default", provider: "openai", model: "gpt")
        let selection = NapaxiConfigSelection(selectedProfileId: "default")
        let capabilityProfile = NapaxiCapabilityProfile(platform: "ios", supportedCapabilities: ["napaxi.platform_tool.*"])
        let capabilitySelection = NapaxiCapabilitySelection(enabledCapabilities: ["napaxi.platform_tool.*"])
        let provider = AgentProviderDescriptor(
            label: "Provider",
            installUrl: "napaxi-provider://install",
            actionUrl: "napaxi-provider://action",
            universalLinkDomain: "example.com"
        )

        XCTAssertEqual(profile.id, "default")
        XCTAssertEqual(selection.selectedProfileId, "default")
        XCTAssertEqual(capabilityProfile.platform, "ios")
        XCTAssertEqual(capabilitySelection.enabledCapabilities, ["napaxi.platform_tool.*"])
        XCTAssertEqual(provider.label, "Provider")
    }

    func testFlutterStatusStringAliasesCompile() {
        let toolFilter: ToolFilter = "all"
        let evolutionStatus: EvolutionRunStatus = "completed"
        let groupMessageType: GroupMessageType = "assistant"
        let runEvidenceKind: RunEvidenceKind = "log"
        let runVerification: RunVerification = "passed"
        let mcpState: McpConnectionState = "connected"

        XCTAssertEqual(toolFilter.rawValue, "all")
        XCTAssertEqual(evolutionStatus.rawValue, "completed")
        XCTAssertEqual(groupMessageType.rawValue, "assistant")
        XCTAssertEqual(runEvidenceKind.rawValue, "log")
        XCTAssertEqual(runVerification.rawValue, "passed")
        XCTAssertEqual(mcpState.rawValue, "connected")
    }

    func testFlutterGeneratedBridgeFunctionAliasesCompile() {
        let registerAgentAppPackageAlias: (Int64, String) throws -> String = registerAgentAppPackage
        let listAgentAppPackagesAlias: (Int64) throws -> String = listAgentAppPackages
        let getAgentAppPackageAlias: (Int64, String) throws -> String = getAgentAppPackage
        let deleteAgentAppPackageAlias: (Int64, String) throws -> Bool = deleteAgentAppPackage
        let submitAgentAppActionResultAlias: (Int64, String) throws -> String = submitAgentAppActionResult
        let listAgentAppActionProposalsAlias: (Int64, String) throws -> String = listAgentAppActionProposals
        let getAgentAppActionProposalAlias: (Int64, String) throws -> String = getAgentAppActionProposal
        let acceptAgentAppTriggerAlias: (Int64, String) throws -> String = acceptAgentAppTrigger
        let listCapabilityDefinitionsJsonAlias: () throws -> String = listCapabilityDefinitionsJson
        let listCapabilityStatusJsonAlias: (Int64, String, String) throws -> String = listCapabilityStatusJson
        let providerCapabilityIdAlias: (String) throws -> String = providerCapabilityId
        let agentEngineCapabilityIdAlias: (String) throws -> String = agentEngineCapabilityId
        let toolCapabilityIdAlias: (String) throws -> String = toolCapabilityId
        let listChannelsAlias: (Int64) throws -> String = listChannels
        let registerToolRequestStreamAlias: () -> AsyncStream<String> = registerToolRequestStream
        let updateCustomToolsAlias: (Int64, String) throws -> Bool = updateCustomTools
        let resolveToolExecutionAlias: (UInt64, String, Bool) throws -> Bool = resolveToolExecution
        let platformToolDescriptorsJsonAlias: () throws -> String = platformToolDescriptorsJson
        let isPlatformToolAlias: (String) -> Bool = isPlatformTool
        let browserToolDescriptorsJsonAlias: () throws -> String = browserToolDescriptorsJson
        let isBrowserToolAlias: (String) -> Bool = isBrowserTool
        let createEngineAlias: (String, String) throws -> Int64 = createEngine
        let ensureAgentReadyAlias: (Int64, String) throws -> Bool = ensureAgentReady
        let sendMessageAlias: (Int64, String, String, String, Int) async throws -> String = sendMessage
        let sendToSessionAlias: (Int64, String, String, String, String, String, Int) async throws -> String = sendToSession
        let sendMessageStreamAlias: (Int64, String, String, String, Int) -> AsyncThrowingStream<String, Error> = sendMessageStream
        let sendToSessionStreamAlias: (Int64, String, String, String, String, String, Int) -> AsyncThrowingStream<String, Error> = sendToSessionStream
        let updateConfigAlias: (Int64, String) throws -> Bool = updateConfig
        let getConfigAlias: (Int64) throws -> String = getConfig
        let disposeEngineAlias: (Int64) -> Void = disposeEngine
        let mcpAddServerAlias: (Int64, String, String, String, String) async throws -> String = mcpAddServer
        let mcpRemoveServerAlias: (Int64, String, String) async throws -> String = mcpRemoveServer
        let mcpListServersAlias: (Int64, String) async throws -> String = mcpListServers
        let mcpActivateServerAlias: (Int64, String, String) async throws -> String = mcpActivateServer
        let mcpStartOauthAlias: (Int64, String, String, String, String) async throws -> String = mcpStartOauth
        let mcpFinishOauthAlias: (Int64, String, String, String, String) async throws -> String = mcpFinishOauth
        let mcpDeactivateServerAlias: (Int64, String, String) async throws -> String = mcpDeactivateServer
        let mcpListToolsAlias: (Int64, String, String) async throws -> String = mcpListTools
        let listSessionRunsAlias: (Int64, String, Int64, Int64) throws -> String = listSessionRuns
        let getSessionRunAlias: (Int64, String) throws -> String = getSessionRun
        let getActiveSessionRunsAlias: (Int64) throws -> String = getActiveSessionRuns
        let getOrCreateAgentAlias: (Int64, String, String) async throws -> String = getOrCreateAgent
        let listAgentsAlias: (Int64) throws -> String = listAgents
        let deleteAgentAlias: (Int64, String) throws -> Bool = deleteAgent
        let agentSendAlias: (Int64, String, String, String, String, Int) async throws -> String = agentSend
        let createAgentDefinitionAlias: (Int64, String) async throws -> String = createAgentDefinition
        let updateAgentDefinitionAlias: (Int64, String) async throws -> Bool = updateAgentDefinition
        let deleteAgentDefinitionAlias: (Int64, String) async throws -> Bool = deleteAgentDefinition
        let listAgentDefinitionsAlias: (Int64) async throws -> String = listAgentDefinitions
        let getAgentDefinitionAlias: (Int64, String) async throws -> String = getAgentDefinition
        let listAvailableToolsAlias: (Int64) async throws -> String = listAvailableTools
        let createAgentFromDefinitionAlias: (Int64, String, String) async throws -> Int64 = createAgentFromDefinition
        let importAgentMdAlias: (Int64, String) async throws -> String = importAgentMd
        let createAutomationJobAlias: (Int64, String) throws -> String = createAutomationJob
        let updateAutomationJobAlias: (Int64, String, String) throws -> String = updateAutomationJob
        let deleteAutomationJobAlias: (Int64, String) throws -> Bool = deleteAutomationJob
        let listAutomationJobsAlias: (Int64, String) throws -> String = listAutomationJobs
        let getAutomationJobAlias: (Int64, String) throws -> String = getAutomationJob
        let runAutomationJobAlias: (Int64, String, String) async throws -> String = runAutomationJob
        let listAutomationRunsAlias: (Int64, String?, Int64, Int64) throws -> String = listAutomationRuns
        let getNextAutomationWakeAlias: (Int64) throws -> String = getNextAutomationWake
        let recordAutomationWakeAlias: (Int64, String, String) async throws -> String = recordAutomationWake
        let listPendingEvolutionAlias: (Int64) throws -> String = listPendingEvolution
        let listEvolutionRunsAlias: (Int64, String) throws -> String = listEvolutionRuns
        let listEvolutionDiagnosticsAlias: (Int64) throws -> String = listEvolutionDiagnostics
        let rejectPendingEvolutionAlias: (Int64, String) throws -> String = rejectPendingEvolution
        let applyPendingEvolutionAlias: (Int64, String) throws -> String = applyPendingEvolution
        let runSkillConsolidationReviewAlias: (Int64, String, String, Bool) throws -> String = runSkillConsolidationReview
        let saveMessageAttachmentsAlias: (Int64, String, Int, String) throws -> Bool = saveMessageAttachments
        let loadThreadAttachmentsAlias: (Int64, String) throws -> String = loadThreadAttachments
        let deleteThreadAttachmentsAlias: (Int64, String) throws -> Bool = deleteThreadAttachments
        let initFileBridgeAlias: (Int64) throws -> Bool = initFileBridge
        let initFileBridgeScopedAlias: (Int64, String, String) throws -> Bool = initFileBridgeScoped
        let sandboxToRealAlias: (Int64, String) throws -> String? = sandboxToReal
        let sandboxToRealScopedAlias: (Int64, String, String, String) throws -> String? = sandboxToRealScoped
        let realToSandboxAlias: (Int64, String) throws -> String? = realToSandbox
        let realToSandboxScopedAlias: (Int64, String, String, String) throws -> String? = realToSandboxScoped
        let detectFileReferencesAlias: (Int64, String) throws -> String = detectFileReferences
        let detectFileReferencesScopedAlias: (Int64, String, String, String) throws -> String = detectFileReferencesScoped
        let deleteSandboxFileAlias: (Int64, String) async throws -> Bool = deleteSandboxFile
        let deleteSandboxFileScopedAlias: (Int64, String, String, String) async throws -> Bool = deleteSandboxFileScoped
        let listWorkspaceFilesystemAlias: (Int64, String?, Bool) async throws -> String = listWorkspaceFilesystem
        let listWorkspaceFilesystemScopedAlias: (Int64, String, String, String?, Bool) async throws -> String = listWorkspaceFilesystemScoped
        let workspaceSizeAlias: (Int64) throws -> Int64 = workspaceSize
        let workspaceSizeScopedAlias: (Int64, String, String) throws -> Int64 = workspaceSizeScoped
        let workspaceDirAlias: (Int64) throws -> String = workspaceDir
        let workspaceDirScopedAlias: (Int64, String, String) throws -> String = workspaceDirScoped
        let rootfsDirAlias: (Int64) throws -> String = rootfsDir
        let skillsDirAlias: (Int64) throws -> String = skillsDir
        let createGroupAlias: (Int64, String, String) async throws -> String = createGroup
        let deleteGroupAlias: (Int64, String) throws -> Bool = deleteGroup
        let listGroupsAlias: (Int64) throws -> String = listGroups
        let getGroupAlias: (Int64, String) throws -> String = getGroup
        let renameGroupAlias: (Int64, String, String) throws -> Bool = renameGroup
        let updateGroupMembersAlias: (Int64, String, String) async throws -> Bool = updateGroupMembers
        let setGroupCustomPromptAlias: (Int64, String, String?) throws -> Bool = setGroupCustomPrompt
        let getGroupMessagesAlias: (Int64, String) throws -> String = getGroupMessages
        let clearGroupHistoryAlias: (Int64, String) throws -> Bool = clearGroupHistory
        let sendToGroupAlias: (Int64, String, String, String, Int) async throws -> String = sendToGroup
        let sendToGroupAgentAlias: (Int64, String, String, String, String, String, Int) async throws -> String = sendToGroupAgent
        let exportGroupStateAlias: (Int64) throws -> String = exportGroupState
        let importGroupStateAlias: (Int64, String) async throws -> Bool = importGroupState
        let listSkillsAlias: (Int64, String) throws -> String = listSkills
        let listSkillStatusAlias: (Int64, String) throws -> String = listSkillStatus
        let listSkillSourcesAlias: (Int64, String) throws -> String = listSkillSources
        let recordSkillSourceChangedAlias: (Int64, String, String) async throws -> String = recordSkillSourceChanged
        let getSkillStatusAlias: (Int64, String, String) throws -> String = getSkillStatus
        let checkSkillsAlias: (Int64, String) throws -> String = checkSkills
        let listSkillCommandsAlias: (Int64, String) throws -> String = listSkillCommands
        let resolveSkillCommandAlias: (Int64, String, String) throws -> String = resolveSkillCommand
        let runSkillCommandAlias: (Int64, String, String, String?, String?) async throws -> String = runSkillCommand
        let setSkillEnabledAlias: (Int64, String, String, Bool) async throws -> String = setSkillEnabled
        let updateSkillConfigAlias: (Int64, String, String, String) async throws -> String = updateSkillConfig
        let listSkillRemediationActionsAlias: (Int64, String, String) throws -> String = listSkillRemediationActions
        let listSkillSnapshotsAlias: (Int64, String, Int, Int) throws -> String = listSkillSnapshots
        let getSkillSnapshotAlias: (Int64, String) throws -> String = getSkillSnapshot
        let listSkillSecretRequirementsAlias: (Int64, String, String?) throws -> String = listSkillSecretRequirements
        let recordSkillSecretAvailabilityAlias: (Int64, String, String, String, Bool, String) async throws -> String = recordSkillSecretAvailability
        let requestSkillRemediationAlias: (Int64, String, String, String) async throws -> String = requestSkillRemediation
        let updateSkillRemediationRunAlias: (Int64, String, String, String, String?) async throws -> String = updateSkillRemediationRun
        let listSkillRemediationRunsAlias: (Int64, String, String?, Int, Int) throws -> String = listSkillRemediationRuns
        let recordSkillRequirementResolutionAlias: (Int64, String, String, String, String) async throws -> String = recordSkillRequirementResolution
        let installSkillAlias: (Int64, String, String) async throws -> String = installSkill
        let removeSkillAlias: (Int64, String, String) async throws -> Bool = removeSkill
        let reloadSkillsAlias: (Int64, String) async throws -> String = reloadSkills
        let getSkillAlias: (Int64, String, String) throws -> String = getSkill
        let listSkillUsageAlias: (Int64, String) throws -> String = listSkillUsage
        let pinSkillAlias: (Int64, String, String, Bool) async throws -> String = pinSkill
        let archiveSkillAlias: (Int64, String, String) async throws -> String = archiveSkill
        let restoreSkillAlias: (Int64, String, String) async throws -> String = restoreSkill
        let runSkillCuratorAlias: (Int64, String, Bool) async throws -> String = runSkillCurator
        let readSkillSupportFileAlias: (Int64, String, String, String) async throws -> String = readSkillSupportFile
        let searchCatalogAlias: (String) async throws -> String = searchCatalog
        let getCatalogSkillAlias: (String) async throws -> String = getCatalogSkill
        let installFromCatalogAlias: (Int64, String, String) async throws -> String = installFromCatalog
        let readWorkspaceFileAlias: (Int64, String, String, String) async throws -> String = readWorkspaceFile
        let writeWorkspaceFileAlias: (Int64, String, String, String, String) async throws -> Bool = writeWorkspaceFile
        let appendWorkspaceFileAlias: (Int64, String, String, String, String) async throws -> Bool = appendWorkspaceFile
        let deleteWorkspaceFileAlias: (Int64, String, String, String) async throws -> Bool = deleteWorkspaceFile
        let listWorkspaceFilesAlias: (Int64, String, String, String) async throws -> String = listWorkspaceFiles
        let getSystemPromptAlias: (Int64, String, String) async throws -> String = getSystemPrompt
        let reseedWorkspaceAlias: (Int64, String, String) async throws -> String = reseedWorkspace
        let searchMemoryAlias: (Int64, String, String, String, Int) async throws -> String = searchMemory
        let recallSessionsAlias: (Int64, String, String, String, String, String, Int) async throws -> String = recallSessions
        let rebuildRecallIndexAlias: (Int64, String, String) async throws -> String = rebuildRecallIndex
        let recallIndexStatsAlias: (Int64, String, String) async throws -> String = recallIndexStats
        let listJournalDaysAlias: (Int64, String, String) async throws -> String = listJournalDays
        let readJournalDayAlias: (Int64, String, String, String) async throws -> String = readJournalDay
        let createSessionAlias: (Int64, String, String, String, String, String?) async throws -> String = createSession
        let listSessionsAlias: (Int64, String, String, String) async throws -> String = listSessions
        let deleteSessionAlias: (Int64, String, String, String) async throws -> Bool = deleteSession
        let clearSessionAlias: (Int64, String, String, String) async throws -> Bool = clearSession
        let getHistoryAlias: (Int64, String, String, String) async throws -> String = getHistory
        let getHistoryPageAlias: (Int64, String, String, String, String?, Int64) async throws -> String = getHistoryPage
        let compactContextAlias: (Int64, String, String, String, String?) async throws -> String = compactContext
        let contextStatusAlias: (Int64, String, String, String) async throws -> String = contextStatus
        let injectMessageAlias: (Int64, String, String, String, String, String) async throws -> Bool = injectMessage
        let retractInjectedMessageAlias: (Int64, String, String) async throws -> Bool = retractInjectedMessage
        let answerHumanRequestAlias: (Int64, String, String) async throws -> Bool = answerHumanRequest
        let cancelSessionAlias: (Int64, String, String, String) async throws -> Bool = cancelSession
        let registerChannelAlias: (Int64, String) throws -> Bool = registerChannel
        let unregisterChannelAlias: (Int64, String) throws -> Bool = unregisterChannel

        XCTAssertNotNil(registerAgentAppPackageAlias)
        XCTAssertNotNil(listAgentAppPackagesAlias)
        XCTAssertNotNil(getAgentAppPackageAlias)
        XCTAssertNotNil(deleteAgentAppPackageAlias)
        XCTAssertNotNil(submitAgentAppActionResultAlias)
        XCTAssertNotNil(listAgentAppActionProposalsAlias)
        XCTAssertNotNil(getAgentAppActionProposalAlias)
        XCTAssertNotNil(acceptAgentAppTriggerAlias)
        XCTAssertNotNil(listCapabilityDefinitionsJsonAlias)
        XCTAssertNotNil(listCapabilityStatusJsonAlias)
        XCTAssertNotNil(providerCapabilityIdAlias)
        XCTAssertNotNil(agentEngineCapabilityIdAlias)
        XCTAssertNotNil(toolCapabilityIdAlias)
        XCTAssertNotNil(listChannelsAlias)
        XCTAssertNotNil(registerToolRequestStreamAlias)
        XCTAssertNotNil(updateCustomToolsAlias)
        XCTAssertNotNil(resolveToolExecutionAlias)
        XCTAssertNotNil(platformToolDescriptorsJsonAlias)
        XCTAssertNotNil(isPlatformToolAlias)
        XCTAssertNotNil(browserToolDescriptorsJsonAlias)
        XCTAssertNotNil(isBrowserToolAlias)
        XCTAssertNotNil(createEngineAlias)
        XCTAssertNotNil(ensureAgentReadyAlias)
        XCTAssertNotNil(sendMessageAlias)
        XCTAssertNotNil(sendToSessionAlias)
        XCTAssertNotNil(sendMessageStreamAlias)
        XCTAssertNotNil(sendToSessionStreamAlias)
        XCTAssertNotNil(updateConfigAlias)
        XCTAssertNotNil(getConfigAlias)
        XCTAssertNotNil(disposeEngineAlias)
        XCTAssertNotNil(mcpAddServerAlias)
        XCTAssertNotNil(mcpRemoveServerAlias)
        XCTAssertNotNil(mcpListServersAlias)
        XCTAssertNotNil(mcpActivateServerAlias)
        XCTAssertNotNil(mcpStartOauthAlias)
        XCTAssertNotNil(mcpFinishOauthAlias)
        XCTAssertNotNil(mcpDeactivateServerAlias)
        XCTAssertNotNil(mcpListToolsAlias)
        XCTAssertNotNil(listSessionRunsAlias)
        XCTAssertNotNil(getSessionRunAlias)
        XCTAssertNotNil(getActiveSessionRunsAlias)
        XCTAssertNotNil(getOrCreateAgentAlias)
        XCTAssertNotNil(listAgentsAlias)
        XCTAssertNotNil(deleteAgentAlias)
        XCTAssertNotNil(agentSendAlias)
        XCTAssertNotNil(createAgentDefinitionAlias)
        XCTAssertNotNil(updateAgentDefinitionAlias)
        XCTAssertNotNil(deleteAgentDefinitionAlias)
        XCTAssertNotNil(listAgentDefinitionsAlias)
        XCTAssertNotNil(getAgentDefinitionAlias)
        XCTAssertNotNil(listAvailableToolsAlias)
        XCTAssertNotNil(createAgentFromDefinitionAlias)
        XCTAssertNotNil(importAgentMdAlias)
        XCTAssertNotNil(createAutomationJobAlias)
        XCTAssertNotNil(updateAutomationJobAlias)
        XCTAssertNotNil(deleteAutomationJobAlias)
        XCTAssertNotNil(listAutomationJobsAlias)
        XCTAssertNotNil(getAutomationJobAlias)
        XCTAssertNotNil(runAutomationJobAlias)
        XCTAssertNotNil(listAutomationRunsAlias)
        XCTAssertNotNil(getNextAutomationWakeAlias)
        XCTAssertNotNil(recordAutomationWakeAlias)
        XCTAssertNotNil(listPendingEvolutionAlias)
        XCTAssertNotNil(listEvolutionRunsAlias)
        XCTAssertNotNil(listEvolutionDiagnosticsAlias)
        XCTAssertNotNil(rejectPendingEvolutionAlias)
        XCTAssertNotNil(applyPendingEvolutionAlias)
        XCTAssertNotNil(runSkillConsolidationReviewAlias)
        XCTAssertNotNil(saveMessageAttachmentsAlias)
        XCTAssertNotNil(loadThreadAttachmentsAlias)
        XCTAssertNotNil(deleteThreadAttachmentsAlias)
        XCTAssertNotNil(initFileBridgeAlias)
        XCTAssertNotNil(initFileBridgeScopedAlias)
        XCTAssertNotNil(sandboxToRealAlias)
        XCTAssertNotNil(sandboxToRealScopedAlias)
        XCTAssertNotNil(realToSandboxAlias)
        XCTAssertNotNil(realToSandboxScopedAlias)
        XCTAssertNotNil(detectFileReferencesAlias)
        XCTAssertNotNil(detectFileReferencesScopedAlias)
        XCTAssertNotNil(deleteSandboxFileAlias)
        XCTAssertNotNil(deleteSandboxFileScopedAlias)
        XCTAssertNotNil(listWorkspaceFilesystemAlias)
        XCTAssertNotNil(listWorkspaceFilesystemScopedAlias)
        XCTAssertNotNil(workspaceSizeAlias)
        XCTAssertNotNil(workspaceSizeScopedAlias)
        XCTAssertNotNil(workspaceDirAlias)
        XCTAssertNotNil(workspaceDirScopedAlias)
        XCTAssertNotNil(rootfsDirAlias)
        XCTAssertNotNil(skillsDirAlias)
        XCTAssertNotNil(createGroupAlias)
        XCTAssertNotNil(deleteGroupAlias)
        XCTAssertNotNil(listGroupsAlias)
        XCTAssertNotNil(getGroupAlias)
        XCTAssertNotNil(renameGroupAlias)
        XCTAssertNotNil(updateGroupMembersAlias)
        XCTAssertNotNil(setGroupCustomPromptAlias)
        XCTAssertNotNil(getGroupMessagesAlias)
        XCTAssertNotNil(clearGroupHistoryAlias)
        XCTAssertNotNil(sendToGroupAlias)
        XCTAssertNotNil(sendToGroupAgentAlias)
        XCTAssertNotNil(exportGroupStateAlias)
        XCTAssertNotNil(importGroupStateAlias)
        XCTAssertNotNil(listSkillsAlias)
        XCTAssertNotNil(listSkillStatusAlias)
        XCTAssertNotNil(listSkillSourcesAlias)
        XCTAssertNotNil(recordSkillSourceChangedAlias)
        XCTAssertNotNil(getSkillStatusAlias)
        XCTAssertNotNil(checkSkillsAlias)
        XCTAssertNotNil(listSkillCommandsAlias)
        XCTAssertNotNil(resolveSkillCommandAlias)
        XCTAssertNotNil(runSkillCommandAlias)
        XCTAssertNotNil(setSkillEnabledAlias)
        XCTAssertNotNil(updateSkillConfigAlias)
        XCTAssertNotNil(listSkillRemediationActionsAlias)
        XCTAssertNotNil(listSkillSnapshotsAlias)
        XCTAssertNotNil(getSkillSnapshotAlias)
        XCTAssertNotNil(listSkillSecretRequirementsAlias)
        XCTAssertNotNil(recordSkillSecretAvailabilityAlias)
        XCTAssertNotNil(requestSkillRemediationAlias)
        XCTAssertNotNil(updateSkillRemediationRunAlias)
        XCTAssertNotNil(listSkillRemediationRunsAlias)
        XCTAssertNotNil(recordSkillRequirementResolutionAlias)
        XCTAssertNotNil(installSkillAlias)
        XCTAssertNotNil(removeSkillAlias)
        XCTAssertNotNil(reloadSkillsAlias)
        XCTAssertNotNil(getSkillAlias)
        XCTAssertNotNil(listSkillUsageAlias)
        XCTAssertNotNil(pinSkillAlias)
        XCTAssertNotNil(archiveSkillAlias)
        XCTAssertNotNil(restoreSkillAlias)
        XCTAssertNotNil(runSkillCuratorAlias)
        XCTAssertNotNil(readSkillSupportFileAlias)
        XCTAssertNotNil(searchCatalogAlias)
        XCTAssertNotNil(getCatalogSkillAlias)
        XCTAssertNotNil(installFromCatalogAlias)
        XCTAssertNotNil(readWorkspaceFileAlias)
        XCTAssertNotNil(writeWorkspaceFileAlias)
        XCTAssertNotNil(appendWorkspaceFileAlias)
        XCTAssertNotNil(deleteWorkspaceFileAlias)
        XCTAssertNotNil(listWorkspaceFilesAlias)
        XCTAssertNotNil(getSystemPromptAlias)
        XCTAssertNotNil(reseedWorkspaceAlias)
        XCTAssertNotNil(searchMemoryAlias)
        XCTAssertNotNil(recallSessionsAlias)
        XCTAssertNotNil(rebuildRecallIndexAlias)
        XCTAssertNotNil(recallIndexStatsAlias)
        XCTAssertNotNil(listJournalDaysAlias)
        XCTAssertNotNil(readJournalDayAlias)
        XCTAssertNotNil(createSessionAlias)
        XCTAssertNotNil(listSessionsAlias)
        XCTAssertNotNil(deleteSessionAlias)
        XCTAssertNotNil(clearSessionAlias)
        XCTAssertNotNil(getHistoryAlias)
        XCTAssertNotNil(getHistoryPageAlias)
        XCTAssertNotNil(compactContextAlias)
        XCTAssertNotNil(contextStatusAlias)
        XCTAssertNotNil(injectMessageAlias)
        XCTAssertNotNil(retractInjectedMessageAlias)
        XCTAssertNotNil(answerHumanRequestAlias)
        XCTAssertNotNil(cancelSessionAlias)
        XCTAssertNotNil(registerChannelAlias)
        XCTAssertNotNil(unregisterChannelAlias)
    }
}
