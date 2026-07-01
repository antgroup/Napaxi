package com.napaxi.android

import android.app.Activity
import android.content.Context
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.callbackFlow
import kotlinx.coroutines.flow.flow

public class NapaxiEngine private constructor(
    private val appContext: Context,
    private val handle: Long,
    public var config: LlmConfig,
    private val toolExecutor: McToolExecutor?,
    private val agentAppActionExecutor: AgentAppActionExecutor?,
    private val toolApprovalHandler: McToolApprovalHandler?,
    private val browserController: NapaxiBrowserController?,
    private val platformToolExecutor: AndroidPlatformToolExecutor?,
    public val backgroundController: NapaxiBackgroundController?,
    private val automationEnabled: Boolean,
    private val streamExecutor: Executor,
    private val hasPlatformMediaToolHandler: Boolean,
    private var toolDispatcherRegistered: Boolean,
) {
    @Volatile
    private var disposed: Boolean = false

    public val chat: ChatApi = ChatApi(this)
    public val sessions: SessionApi = SessionApi(this)
    public val sessionRuns: SessionRunApi = SessionRunApi(this)
    public val agents: AgentApi = AgentApi(this)
    public val workspace: WorkspaceApi = WorkspaceApi(this)
    public val skills: SkillApi = SkillApi(this)
    public val evolution: EvolutionApi = EvolutionApi(this)
    public val groups: GroupApi = GroupApi(this)
    public val tools: ToolApi = ToolApi(this)
    public val capabilities: CapabilityApi = CapabilityApi(this)
    public val channels: ChannelApi = ChannelApi(this)
    public val channelAgents: ChannelAgentApi = ChannelAgentApi(this)
    public val mcp: McpApi = McpApi(this, DEFAULT_ACCOUNT_ID)
    public val background: BackgroundApi = BackgroundApi(this)
    public val automation: AutomationApi = AutomationApi(this)
    public val a2a: A2AApi = A2AApi(this)
    public val channelProviders: NapaxiChannelProviderHost = NapaxiChannelProviderHost(channels)
    public val qqbotProtocol: QqBotProtocolApi = QqBotProtocolApi(this)
    public val agentApp: AgentAppApi = AgentAppApi(this)
    public val agentProviders: AgentProviderHostApi = AgentProviderHostApi(this, appContext)
    public val agentProviderInstall: AgentProviderInstallApi = AgentProviderInstallApi(agentProviders)
    public val agentProviderTrigger: AgentProviderTriggerApi = AgentProviderTriggerApi(agentProviders)
    public val fileBridge: FileBridgeApi = FileBridgeApi(this, appContext)
    public val apkInstaller: ApkInstallerApi = ApkInstallerApi(this, appContext)
    public val backgroundRuntime: NapaxiBackgroundController? get() = backgroundController
    public val filesDir: String = appContext.filesDir.absolutePath

    private val activeSessionRunsById = LinkedHashMap<String, SessionRunInfo>()
    private val sessionRunEvents = MutableSharedFlow<SessionRunInfo>(extraBufferCapacity = 32)
    public val activeSessionRuns: List<SessionRunInfo>
        get() = synchronized(activeSessionRunsById) { activeSessionRunsById.values.toList() }
    public val onBackgroundAction: Flow<BackgroundActionEvent>
        get() = backgroundController?.onAction ?: NapaxiActionReceiver.events
    public val sessionRunUpdates: Flow<SessionRunInfo> = sessionRunEvents.asSharedFlow()

    public fun updateConfig(config: LlmConfig): Boolean {
        checkNotDisposed()
        val ok = NapaxiNative.updateConfig(handle, config.toJson())
        if (ok) this.config = config
        return ok
    }

    public fun ensureAgent(agentId: String = DEFAULT_AGENT_ID): Boolean {
        checkNotDisposed()
        return if (agentId == DEFAULT_AGENT_ID) {
            NapaxiNative.ensureAgentReady(handle, config.toJson())
        } else {
            getOrCreateAgent(agentId) != null
        }
    }

    public fun getOrCreateAgent(
        agentId: String,
        config: LlmConfig? = null,
    ): AgentHandle? {
        checkNotDisposed()
        val rawJson = NapaxiNative.getOrCreateAgent(handle, agentId, (config ?: this.config).toJson())
        if (rawJson.isBlank()) return null
        val obj = runCatching { JSONObject(rawJson) }.getOrNull()
        val id = obj?.optString("agent_id", obj.optString("id", agentId)) ?: agentId
        return AgentHandle(agentId = id, rawJson = rawJson)
    }

    public fun listAgents(): List<String> {
        checkNotDisposed()
        return NapaxiNative.listAgents(handle).parseJsonArrayOrObjectList("agents").map { agent ->
            agent.optString("agent_id", agent.optString("id", agent.toString()))
        }
    }

    public suspend fun deleteAgent(agentId: String): Boolean =
        agents.delete(agentId)

    public suspend fun createAgentDefinition(definition: AgentDefinition): AgentDefinition =
        agents.createDefinition(definition)

    public suspend fun listAgentDefinitions(): List<AgentDefinition> =
        agents.listDefinitions()

    public suspend fun getAgentDefinition(defId: String): AgentDefinition? =
        agents.getDefinition(defId)

    public suspend fun updateAgentDefinition(definition: AgentDefinition): Boolean =
        agents.updateDefinition(definition)

    public suspend fun deleteAgentDefinition(defId: String): Boolean =
        agents.deleteDefinition(defId)

    public suspend fun importAgentMd(content: String): AgentDefinition =
        agents.importMarkdown(content)

    public suspend fun listAvailableTools(): List<ToolInfo> =
        agents.listAvailableTools()

    public suspend fun createAgentFromDefinition(
        defId: String,
        config: LlmConfig? = null,
    ): Boolean =
        agents.createFromDefinition(defId, config)

    public suspend fun listSkills(agentId: String = ""): List<SkillInfo> =
        skills.list(agentId)

    public suspend fun getSkill(skillName: String, agentId: String = ""): SkillInfo? =
        skills.get(skillName, agentId)

    public suspend fun listSkillStatus(agentId: String = ""): SkillStatusReport =
        skills.status(agentId)

    public suspend fun listSkillSources(agentId: String = ""): SkillSourceReport =
        skills.sources(agentId)

    public suspend fun recordSkillSourceChanged(sourceId: String, agentId: String = ""): SkillRefreshResult =
        skills.recordSourceChanged(sourceId, agentId)

    public suspend fun getSkillStatus(skillName: String, agentId: String = ""): SkillStatusEntry =
        skills.getStatus(skillName, agentId)

    public suspend fun checkSkills(agentId: String = ""): SkillStatusReport =
        skills.check(agentId)

    public suspend fun listSkillCommands(agentId: String = ""): SkillCommandReport =
        skills.commands(agentId)

    public suspend fun resolveSkillCommand(text: String, agentId: String = ""): SkillCommandResolution =
        skills.resolveCommand(text, agentId)

    public suspend fun runSkillCommand(
        commandName: String,
        agentId: String = "",
        args: String? = null,
        sessionKey: SessionKey? = null,
    ): SkillCommandRun =
        skills.runCommand(commandName, agentId, args, sessionKey)

    public suspend fun setSkillEnabled(skillName: String, agentId: String = "", enabled: Boolean): String =
        skills.setEnabled(skillName, agentId, enabled)

    public suspend fun updateSkillConfig(skillKey: String, patchJson: String, agentId: String = ""): String =
        skills.updateConfig(skillKey, patchJson, agentId)

    public suspend fun updateSkillConfig(skillKey: String, patch: JSONObject, agentId: String = ""): String =
        updateSkillConfig(skillKey, patch.toString(), agentId)

    public suspend fun updateSkillConfig(skillKey: String, patch: Map<String, Any?>, agentId: String = ""): String =
        updateSkillConfig(skillKey, JSONObject(patch), agentId)

    public suspend fun listSkillRemediationActions(skillName: String, agentId: String = ""): List<SkillRemediationAction> =
        skills.remediationActions(skillName, agentId)

    public suspend fun listSkillSnapshots(
        agentId: String = "",
        limit: Int = 50,
        offset: Int = 0,
    ): SkillSnapshotList =
        skills.snapshots(agentId, limit, offset)

    public suspend fun getSkillSnapshot(snapshotId: String): SkillSnapshot? =
        skills.snapshot(snapshotId)

    public suspend fun listSkillSecretRequirements(
        agentId: String = "",
        skillName: String? = null,
    ): SkillSecretRequirementReport =
        skills.secretRequirements(agentId, skillName)

    public suspend fun recordSkillSecretAvailability(
        skillName: String,
        key: String,
        agentId: String = "",
        available: Boolean,
        source: String = "host",
    ): SkillStatusReport =
        skills.recordSecretAvailability(skillName, key, agentId, available, source)

    public suspend fun requestSkillRemediation(
        skillName: String,
        actionId: String,
        agentId: String = "",
    ): SkillRemediationRun =
        skills.requestRemediation(skillName, actionId, agentId)

    public suspend fun updateSkillRemediationRun(
        runId: String,
        status: String,
        agentId: String = "",
        resultJson: String? = null,
    ): SkillRemediationRun =
        skills.updateRemediationRun(runId, status, agentId, resultJson)

    public suspend fun updateSkillRemediationRun(
        runId: String,
        status: String,
        agentId: String = "",
        result: JSONObject,
    ): SkillRemediationRun =
        updateSkillRemediationRun(runId, status, agentId, result.toString())

    public suspend fun listSkillRemediationRuns(
        agentId: String = "",
        skillName: String? = null,
        limit: Int = 50,
        offset: Int = 0,
    ): SkillRemediationRunList =
        skills.remediationRuns(agentId, skillName, limit, offset)

    public suspend fun recordSkillRequirementResolution(
        skillName: String,
        actionId: String,
        resultJson: String,
        agentId: String = "",
    ): String =
        skills.recordRequirementResolution(skillName, actionId, resultJson, agentId)

    public suspend fun recordSkillRequirementResolution(
        skillName: String,
        actionId: String,
        result: JSONObject,
        agentId: String = "",
    ): String =
        recordSkillRequirementResolution(skillName, actionId, result.toString(), agentId)

    public suspend fun installSkill(skillContent: String, agentId: String = ""): SkillInstallResult =
        skills.install(skillContent, agentId)

    public suspend fun installSkill(skill: SkillInstallInput, agentId: String = ""): SkillInstallResult =
        skills.install(skill, agentId)

    public suspend fun removeSkill(skillName: String, agentId: String = ""): Boolean =
        skills.remove(skillName, agentId)

    public suspend fun reloadSkills(agentId: String = ""): List<String> =
        skills.reload(agentId)

    public suspend fun listSkillUsage(agentId: String = ""): List<SkillUsageRecord> =
        skills.usage(agentId)

    public suspend fun pinSkill(skillName: String, agentId: String = "", pinned: Boolean = true): String =
        if (pinned) skills.pin(skillName, agentId) else skills.unpin(skillName, agentId)

    public suspend fun archiveSkill(skillName: String, agentId: String = ""): String =
        skills.archive(skillName, agentId)

    public suspend fun restoreSkill(skillName: String, agentId: String = ""): String =
        skills.restore(skillName, agentId)

    public suspend fun runSkillCurator(agentId: String = "", dryRun: Boolean = true): CuratorRunSummary =
        skills.runCurator(agentId, dryRun)

    public suspend fun runSkillConsolidationReview(
        agentId: String = "",
        config: LlmConfig? = null,
        dryRun: Boolean = true,
    ): SkillConsolidationReviewResult =
        skills.runConsolidationReview(agentId, config, dryRun)

    public suspend fun readSkillSupportFile(
        skillName: String,
        filePath: String,
        agentId: String = "",
    ): SkillSupportFileReadResult =
        skills.readSupportFile(skillName, filePath, agentId)

    public suspend fun searchCatalog(query: String): String =
        skills.searchCatalog(query)

    public suspend fun listCatalogPackages(limit: Int = 50, cursor: String? = null): CatalogPackagePage =
        skills.listCatalogPackages(limit, cursor)

    public suspend fun getCatalogSkill(slug: String): String =
        skills.getCatalogSkill(slug)

    public suspend fun installFromCatalog(slug: String, agentId: String = ""): String =
        skills.installFromCatalog(slug, agentId)

    public suspend fun listPendingEvolution(): List<NapaxiJsonModel> =
        evolution.listPending()

    public suspend fun applyPendingEvolution(pendingId: String): String =
        evolution.applyPending(pendingId)

    public suspend fun rejectPendingEvolution(pendingId: String): String =
        evolution.rejectPending(pendingId)

    public suspend fun listEvolutionRuns(runIds: List<String>? = null): List<EvolutionRun> =
        evolution.runs(JSONArray(runIds ?: emptyList<String>()).toString())

    public suspend fun listEvolutionDiagnostics(): List<EvolutionDiagnostic> =
        evolution.diagnostics()

    public suspend fun createAutomationJob(jobJson: String): AutomationJob =
        automation.createAutomationJob(jobJson)

    public suspend fun createAutomationJob(job: AutomationJob): AutomationJob =
        automation.createAutomationJob(job)

    public suspend fun updateAutomationJob(jobId: String, patchJson: String): AutomationJob =
        automation.updateAutomationJob(jobId, patchJson)

    public suspend fun updateAutomationJob(jobId: String, patch: JSONObject): AutomationJob =
        automation.updateAutomationJob(jobId, patch)

    public suspend fun updateAutomationJob(jobId: String, patch: Map<String, Any?>): AutomationJob =
        automation.updateAutomationJob(jobId, patch)

    public suspend fun deleteAutomationJob(jobId: String): Boolean =
        automation.deleteAutomationJob(jobId)

    public suspend fun listAutomationJobs(
        accountId: String? = null,
        agentId: String? = null,
        enabled: Boolean? = null,
    ): List<AutomationJob> =
        automation.listAutomationJobs(accountId, agentId, enabled)

    public suspend fun getAutomationJob(jobId: String): AutomationJob? =
        automation.getAutomationJob(jobId)

    public suspend fun runAutomationJob(jobId: String, mode: String = "manual"): AutomationRun =
        automation.runAutomationJob(jobId, mode)

    public suspend fun listAutomationRuns(
        jobId: String? = null,
        limit: Long = 200,
        offset: Long = 0,
    ): List<AutomationRun> =
        automation.listAutomationRuns(jobId, limit, offset)

    public suspend fun getNextAutomationWake(): AutomationWake? =
        automation.getNextAutomationWake()

    public suspend fun recordAutomationWake(jobId: String, source: String): AutomationRun =
        automation.recordAutomationWake(jobId, source)

    public suspend fun initFileBridge(accountId: String? = null, agentId: String? = null): Boolean =
        fileBridge.init(accountId, agentId)

    public suspend fun saveMessageAttachments(
        threadId: String,
        userMessageIndex: Int,
        attachments: List<McAttachment>,
    ): Boolean =
        fileBridge.saveMessageAttachments(threadId, userMessageIndex, attachments)

    public fun saveAttachmentMetadata(
        threadId: String,
        userMsgIndex: Int,
        attachments: List<ChatAttachment>,
    ): Boolean {
        if (attachments.isEmpty()) return true
        return bridgeBool(
            "file_bridge.save_attachments",
            JSONObject()
                .put("thread_id", threadId)
                .put("user_msg_index", userMsgIndex)
                .put("attachments_json", JSONArray(attachments.map { it.toJsonObject() }).toString()),
        )
    }

    public suspend fun loadThreadAttachments(threadId: String): String =
        fileBridge.loadThreadAttachments(threadId)

    public suspend fun deleteThreadAttachments(threadId: String): Boolean =
        fileBridge.deleteThreadAttachments(threadId)

    public suspend fun sandboxToReal(
        sandboxPath: String,
        accountId: String? = null,
        agentId: String? = null,
    ): String? =
        fileBridge.sandboxToReal(sandboxPath, accountId, agentId)

    public suspend fun sandboxToRealScoped(
        sandboxPath: String,
        accountId: String,
        agentId: String,
    ): String? =
        fileBridge.sandboxToReal(sandboxPath, accountId, agentId)

    public suspend fun realToSandbox(
        realPath: String,
        accountId: String? = null,
        agentId: String? = null,
    ): String? =
        fileBridge.realToSandbox(realPath, accountId, agentId)

    public suspend fun realToSandboxScoped(
        realPath: String,
        accountId: String,
        agentId: String,
    ): String? =
        fileBridge.realToSandbox(realPath, accountId, agentId)

    public suspend fun resolveFile(sandboxPath: String): File? =
        fileBridge.resolveFile(sandboxPath)

    public suspend fun resolveFileScoped(
        sandboxPath: String,
        accountId: String,
        agentId: String,
    ): File? =
        fileBridge.resolveFileScoped(sandboxPath, accountId, agentId)

    public suspend fun deleteFile(sandboxPath: String): Boolean =
        fileBridge.deleteFile(sandboxPath)

    public suspend fun deleteFileScoped(
        sandboxPath: String,
        accountId: String,
        agentId: String,
    ): Boolean =
        fileBridge.deleteFileScoped(sandboxPath, accountId, agentId)

    public suspend fun deleteSandboxFile(
        sandboxPath: String,
        accountId: String? = null,
        agentId: String? = null,
    ): Boolean =
        fileBridge.deleteSandboxFile(sandboxPath, accountId, agentId)

    public suspend fun detectFileReferences(text: String): List<ResolvedFile> =
        fileBridge.detectFileReferences(text)

    public suspend fun detectFileReferencesScoped(
        text: String,
        accountId: String,
        agentId: String,
    ): List<ResolvedFile> =
        fileBridge.detectFileReferencesScoped(text, accountId, agentId)

    public suspend fun detectFileReferencesJson(
        text: String,
        accountId: String? = null,
        agentId: String? = null,
    ): String =
        fileBridge.detectFileReferencesJson(text, accountId, agentId)

    public suspend fun listFiles(
        subdir: String? = null,
        recursive: Boolean = false,
    ): List<WorkspaceFileInfo> =
        fileBridge.listFiles(subdir, recursive)

    public suspend fun listFilesScoped(
        accountId: String,
        agentId: String,
        subdir: String? = null,
        recursive: Boolean = false,
    ): List<WorkspaceFileInfo> =
        fileBridge.listFilesScoped(accountId, agentId, subdir, recursive)

    public suspend fun listWorkspaceFilesystem(
        subdir: String? = null,
        recursive: Boolean = false,
        accountId: String? = null,
        agentId: String? = null,
    ): String =
        fileBridge.listWorkspaceFilesystem(subdir, recursive, accountId, agentId)

    public suspend fun workspaceSize(accountId: String? = null, agentId: String? = null): Long =
        fileBridge.workspaceSize(accountId, agentId)

    public suspend fun workspaceSizeScoped(accountId: String, agentId: String): Long =
        fileBridge.workspaceSizeScoped(accountId, agentId)

    public suspend fun workspaceDir(accountId: String? = null, agentId: String? = null): String =
        fileBridge.workspaceDir(accountId, agentId)

    public suspend fun workspaceDirScoped(accountId: String, agentId: String): String =
        fileBridge.workspaceDirScoped(accountId, agentId)

    public suspend fun rootfsDir(): String =
        fileBridge.rootfsDir()

    public suspend fun skillsDir(): String =
        fileBridge.skillsDir()

    public suspend fun openLocalFile(
        path: String,
        mimeType: String = "application/octet-stream",
    ): String =
        fileBridge.openLocalFile(path, mimeType)

    public suspend fun openLocalFileResult(
        path: String,
        mimeType: String = "application/octet-stream",
    ): JSONObject =
        fileBridge.openLocalFileResult(path, mimeType)

    public suspend fun installApk(path: String): String =
        apkInstaller.install(path)

    public suspend fun installApkResult(path: String): NapaxiApkInstallResult =
        apkInstaller.installResult(path)

    public fun createSession(
        agentId: String = DEFAULT_AGENT_ID,
        channelType: String = "app",
        accountId: String = DEFAULT_ACCOUNT_ID,
        threadId: String? = null,
    ): SessionKey {
        checkNotDisposed()
        val rawJson = NapaxiNative.createSession(
            handle,
            config.toJson(),
            agentId,
            channelType,
            accountId,
            threadId.orEmpty(),
        )
        return SessionKey.fromJson(rawJson)
    }

    public fun sendToSession(
        session: SessionKey,
        message: String,
        agentId: String = DEFAULT_AGENT_ID,
        attachments: List<McAttachment> = emptyList(),
        maxIterations: Int = 0,
        listener: ChatEventListener,
        sandboxPaths: List<String>? = null,
        requestConfig: LlmConfig = config,
    ) {
        checkNotDisposed()
        val configJson = requestConfig.toJson()
        val sessionJson = session.toJson()
        val attachmentsJson = attachments.toJsonArrayString(sandboxPaths)
        streamExecutor.execute {
            try {
                NapaxiNative.sendToSessionStream(
                    handle,
                    configJson,
                    agentId,
                    sessionJson,
                    message,
                    attachmentsJson,
                    maxIterations,
                    object : NativeStreamCallback {
                        override fun onEvent(eventJson: String) {
                            try {
                                listener.onEvent(ChatEvent.fromJson(eventJson))
                            } catch (error: Throwable) {
                                listener.onError(error)
                            }
                        }

                        override fun onComplete() {
                            listener.onComplete()
                        }
                    },
                )
            } catch (error: Throwable) {
                listener.onError(error)
            }
        }
    }

    public fun send(
        message: String,
        attachments: List<McAttachment> = emptyList(),
        maxIterations: Int = 0,
    ): Flow<ChatEvent> {
        val session = createSession()
        return sendToSessionFlow(session, message, DEFAULT_AGENT_ID, attachments, maxIterations)
    }

    public fun sendToSessionFlow(
        session: SessionKey,
        message: String,
        agentId: String = DEFAULT_AGENT_ID,
        attachments: List<McAttachment> = emptyList(),
        maxIterations: Int = 0,
        sandboxPaths: List<String>? = null,
        requestConfig: LlmConfig = config,
    ): Flow<ChatEvent> {
        check(!hasActiveSessionRun(session, agentId)) { "Session is already running: ${session.threadId}" }
        return callbackFlow {
            var currentRun = SessionRunInfo.create(session, agentId)
            startBackgroundForRun()
            emitSessionRun(currentRun)
            sendToSession(
                session = session,
                message = message,
                agentId = agentId,
                attachments = attachments,
                maxIterations = maxIterations,
                listener = object : ChatEventListener {
                    override fun onEvent(event: ChatEvent) {
                        currentRun = sessionRunForEvent(currentRun, event)
                        trySend(event)
                    }

                    override fun onComplete() {
                        if (!currentRun.isTerminal) {
                            currentRun = updateSessionRun(
                                currentRun,
                                status = SessionRunStatus.Completed,
                                activity = "Completed",
                                clearHumanRequest = true,
                            )
                        }
                        maybeShowCompletionNotification()
                        close()
                    }

                    override fun onError(error: Throwable) {
                        currentRun = updateSessionRun(
                            currentRun,
                            status = SessionRunStatus.Failed,
                            activity = error.message ?: error.toString(),
                            error = error.message ?: error.toString(),
                        )
                        backgroundController?.showErrorNotification(message = error.message ?: error.toString())
                        close(error)
                    }
                },
                sandboxPaths = sandboxPaths,
                requestConfig = requestConfig,
            )
            awaitClose {}
        }
    }

    public fun agentSend(
        agentId: String,
        session: SessionKey,
        message: String,
        config: LlmConfig? = null,
        maxIterations: Int = 0,
    ): Flow<ChatEvent> = flow {
        checkNotDisposed()
        val rawJson = bridge(
            "agent.send",
            JSONObject()
                .put("agent_id", agentId)
                .put("config_json", (config ?: this@NapaxiEngine.config).toJson())
                .put("session_key_json", session.toJson())
                .put("message", message)
                .put("max_iterations", maxIterations),
        )
        rawJson.parseJsonArrayOrObjectList("events").forEach { event ->
            emit(ChatEvent.fromJson(event.toString()))
        }
    }

    public fun agentSend(
        agent: AgentHandle,
        session: SessionKey,
        message: String,
        config: LlmConfig? = null,
        maxIterations: Int = 0,
    ): Flow<ChatEvent> = agentSend(agent.agentId, session, message, config, maxIterations)

    public suspend fun createGroup(name: String, memberAgentIds: List<String>): String =
        groups.create(name, memberAgentIds)

    public suspend fun deleteGroup(groupId: String): Boolean =
        groups.delete(groupId)

    public suspend fun listGroups(): List<GroupInfo> =
        groups.list()

    public suspend fun getGroup(groupId: String): GroupInfo? =
        groups.get(groupId)

    public suspend fun renameGroup(groupId: String, newName: String): Boolean =
        groups.rename(groupId, newName)

    public suspend fun updateGroupMembers(groupId: String, memberAgentIds: List<String>): Boolean =
        groups.updateMembers(groupId, memberAgentIds)

    public suspend fun setGroupCustomPrompt(groupId: String, prompt: String?): Boolean =
        groups.setCustomPrompt(groupId, prompt)

    public suspend fun getGroupMessages(groupId: String): List<GroupMessage> =
        groups.messages(groupId)

    public suspend fun clearGroupHistory(groupId: String): Boolean =
        groups.clearHistory(groupId)

    public suspend fun exportGroupState(): String =
        groups.exportState()

    public suspend fun importGroupState(stateJson: String): Boolean =
        groups.importState(stateJson)

    public fun sendToGroup(groupId: String, message: String, maxIterations: Int = 0): Flow<ChatEvent> =
        send(message, maxIterations = maxIterations)

    public fun sendToGroupAgent(
        groupId: String,
        agentId: String,
        session: SessionKey,
        message: String,
        maxIterations: Int = 0,
    ): Flow<ChatEvent> = sendToSessionFlow(session, message, agentId, emptyList(), maxIterations)

    public fun sendToSessionBlocking(
        session: SessionKey,
        message: String,
        agentId: String = DEFAULT_AGENT_ID,
        attachments: List<McAttachment> = emptyList(),
        maxIterations: Int = 0,
        sandboxPaths: List<String>? = null,
        requestConfig: LlmConfig = config,
    ): List<ChatEvent> {
        checkNotDisposed()
        val rawJson = NapaxiNative.sendToSession(
            handle,
            requestConfig.toJson(),
            agentId,
            session.toJson(),
            message,
            attachments.toJsonArrayString(sandboxPaths),
            maxIterations,
        )
        return rawJson.parseJsonArrayOrObjectList("events").map { ChatEvent.fromJson(it.toString()) }
    }

    public fun cancelSession(
        session: SessionKey,
        agentId: String = DEFAULT_AGENT_ID,
    ): Boolean {
        checkNotDisposed()
        val ok = NapaxiNative.cancelSession(handle, config.toJson(), agentId, session.toJson())
        if (ok) {
            activeSessionRun(session, agentId)?.let {
                updateSessionRun(
                    it,
                    status = SessionRunStatus.Cancelled,
                    activity = "Cancelled",
                    clearHumanRequest = true,
                )
            }
        }
        return ok
    }

    public suspend fun deleteSession(
        sessionKey: SessionKey,
        agentId: String = DEFAULT_AGENT_ID,
    ): Boolean =
        bridgeBool(
            "session.delete",
            JSONObject()
                .put("config_json", config.toJson())
                .put("agent_id", agentId)
                .put("session_key_json", sessionKey.toJson()),
        )

    public suspend fun clearSession(
        sessionKey: SessionKey,
        agentId: String = DEFAULT_AGENT_ID,
    ): Boolean =
        bridgeBool(
            "session.clear",
            JSONObject()
                .put("config_json", config.toJson())
                .put("agent_id", agentId)
                .put("session_key_json", sessionKey.toJson()),
        )

    public suspend fun answerHumanRequest(requestId: String, response: String): Boolean =
        bridgeBool(
            "session.answer_human_request",
            JSONObject().put("request_id", requestId).put("response", response),
        )

    public suspend fun injectMessage(
        sessionKey: SessionKey,
        message: String,
        attachments: List<McAttachment> = emptyList(),
        agentId: String = DEFAULT_AGENT_ID,
    ): Boolean =
        bridgeBool(
            "session.inject_message",
            JSONObject()
                .put("config_json", config.toJson())
                .put("agent_id", agentId)
                .put("session_key_json", sessionKey.toJson())
                .put("message", message)
                .put("attachments_json", attachments.toJsonArrayString()),
        )

    public suspend fun retractInjectedMessage(sessionKey: SessionKey, message: String): Boolean =
        bridgeBool(
            "session.retract_injected_message",
            JSONObject()
                .put("session_key_json", sessionKey.toJson())
                .put("message", message),
        )

    public fun listSessions(
        agentId: String = DEFAULT_AGENT_ID,
        accountId: String = DEFAULT_ACCOUNT_ID,
    ): List<SessionInfo> {
        checkNotDisposed()
        return NapaxiNative
            .listSessions(handle, config.toJson(), agentId, accountId)
            .parseJsonArrayOrObjectList("sessions")
            .map(SessionInfo::fromJsonObject)
    }

    public fun getHistoryJson(
        threadId: String,
        agentId: String = DEFAULT_AGENT_ID,
    ): String {
        checkNotDisposed()
        return NapaxiNative.getHistory(handle, config.toJson(), agentId, threadId)
    }

    public suspend fun getHistory(
        threadId: String,
        agentId: String = DEFAULT_AGENT_ID,
    ): List<ChatMessage> =
        sessions.history(threadId, agentId)

    public suspend fun getHistoryPage(
        threadId: String,
        agentId: String = DEFAULT_AGENT_ID,
        before: String? = null,
        limit: Long = 80,
    ): HistoryPage =
        sessions.historyPage(threadId, before, limit, agentId)

    public suspend fun compactContext(
        sessionKey: SessionKey,
        agentId: String = DEFAULT_AGENT_ID,
        focus: String? = null,
    ): ContextStatus =
        sessions.compactContext(sessionKey, focus, agentId)

    public suspend fun contextStatus(
        threadId: String,
        agentId: String = DEFAULT_AGENT_ID,
    ): ContextStatus =
        sessions.contextStatus(threadId, agentId)

    public suspend fun readWorkspaceFile(
        path: String,
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): WorkspaceFile? =
        workspace.readFile(path, accountId, agentId)

    public suspend fun writeWorkspaceFile(
        path: String,
        content: String,
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): Boolean =
        workspace.writeFile(path, content, accountId, agentId)

    public suspend fun appendWorkspaceFile(
        path: String,
        content: String,
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): Boolean =
        workspace.appendFile(path, content, accountId, agentId)

    public suspend fun deleteWorkspaceFile(
        path: String,
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): Boolean =
        workspace.deleteFile(path, accountId, agentId)

    public suspend fun listWorkspaceFiles(
        directory: String = "",
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): List<WorkspaceEntry> =
        workspace.listFiles(directory, accountId, agentId)

    public suspend fun searchMemory(
        query: String,
        limit: Int = 5,
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): List<MemorySearchResult> =
        workspace.search(query, limit, accountId, agentId)

    public suspend fun recallSessions(
        query: String,
        limit: Int = 3,
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
        currentThreadId: String = "",
    ): List<MemoryRecallSession> =
        workspace.recallSessions(query, limit, accountId, agentId, currentThreadId)

    public suspend fun recallSessionsForThread(
        currentThreadId: String,
        query: String,
        limit: Int = 5,
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): List<MemoryRecallSession> =
        workspace.recallSessionsForThread(currentThreadId, query, limit, accountId, agentId)

    public suspend fun rebuildRecallIndex(
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): RecallIndexStats =
        workspace.rebuildRecallIndex(accountId, agentId)

    public suspend fun recallIndexStats(
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): RecallIndexStats =
        workspace.recallIndexStats(accountId, agentId)

    public suspend fun listJournalDays(
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): List<JournalDay> =
        workspace.listJournalDays(accountId, agentId)

    public suspend fun readJournalDay(
        date: String,
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): List<JournalTurnRecord> =
        workspace.readJournalDay(date, accountId, agentId)

    public suspend fun getSystemPrompt(
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): String =
        workspace.systemPrompt(accountId, agentId)

    public suspend fun reseedWorkspace(
        accountId: String = DEFAULT_ACCOUNT_ID,
        agentId: String = DEFAULT_AGENT_ID,
    ): Int =
        workspace.reseed(accountId, agentId)

    public fun updateCustomTools(tools: List<CustomToolDef>): Boolean {
        checkNotDisposed()
        val arr = JSONArray()
        tools.forEach { arr.put(it.toJsonObject()) }
        return NapaxiNative.updateCustomTools(handle, arr.toString())
    }

    public fun startToolRequestListener() {
        checkNotDisposed()
        if (
            toolExecutor == null &&
            agentAppActionExecutor == null &&
            toolApprovalHandler == null &&
            browserController == null &&
            platformToolExecutor == null
        ) {
            return
        }
        registerToolDispatcher(
            toolExecutor,
            agentAppActionExecutor,
            toolApprovalHandler,
            browserController,
            platformToolExecutor,
        )
        toolDispatcherRegistered = true
    }

    public fun dispose() {
        if (disposed) return
        disposed = true
        if (toolDispatcherRegistered) {
            NapaxiNative.registerToolRequestCallback(null)
        }
        NapaxiNative.disposeEngine(handle)
    }

    public fun mcpForAccount(accountId: String): McpApi =
        McpApi(this, accountId.ifBlank { DEFAULT_ACCOUNT_ID })

    public fun updateBackgroundConfig(config: BackgroundConfig) {
        backgroundController?.updateConfig(config)
    }

    public fun startBackgroundService() {
        backgroundController?.start()
    }

    public fun stopBackgroundService() {
        backgroundController?.stop()
    }

    public fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean =
        (agentAppActionExecutor as? AndroidAgentProviderActionExecutor)
            ?.onActivityResult(requestCode, resultCode, data)
            ?: false

    public suspend fun onAgentProviderInstallActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
        pending: PendingAgentProviderInstall,
        now: java.time.Instant = java.time.Instant.now(),
    ): AgentAppPackage? =
        agentProviderInstall.handleActivityResult(requestCode, resultCode, data, pending, now)

    public suspend fun onAgentProviderInstallActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
        descriptor: AgentProviderDescriptor,
        request: AgentInstallRequest,
        expectedRequestCode: Int = AgentProviderHostApi.REQUEST_INSTALL_AGENT,
        now: java.time.Instant = java.time.Instant.now(),
    ): AgentAppPackage? =
        agentProviderInstall.handleActivityResult(requestCode, resultCode, data, descriptor, request, expectedRequestCode, now)

    public fun hasActiveSessionRun(session: SessionKey, agentId: String = DEFAULT_AGENT_ID): Boolean =
        synchronized(activeSessionRunsById) { activeSessionRunsById.containsKey(sessionRunId(session, agentId)) }

    public fun activeSessionRun(session: SessionKey, agentId: String = DEFAULT_AGENT_ID): SessionRunInfo? =
        synchronized(activeSessionRunsById) { activeSessionRunsById[sessionRunId(session, agentId)] }

    private fun sessionRunId(session: SessionKey, agentId: String): String =
        "$agentId:${session.channelType}:${session.accountId}:${session.threadId}"

    private fun emitSessionRun(info: SessionRunInfo) {
        synchronized(activeSessionRunsById) {
            if (info.isTerminal) {
                activeSessionRunsById.remove(info.id)
            } else {
                activeSessionRunsById[info.id] = info
            }
        }
        sessionRunEvents.tryEmit(info)
        updateBackgroundRunSummary()
    }

    private fun updateSessionRun(
        info: SessionRunInfo,
        status: SessionRunStatus? = null,
        activity: String? = null,
        humanRequestId: String? = null,
        clearHumanRequest: Boolean = false,
        error: String? = null,
        clearError: Boolean = false,
    ): SessionRunInfo {
        val updated = info.copyWith(
            status = status,
            activity = activity,
            humanRequestId = humanRequestId,
            clearHumanRequest = clearHumanRequest,
            error = error,
            clearError = clearError,
        )
        emitSessionRun(updated)
        return updated
    }

    private fun sessionRunForEvent(run: SessionRunInfo, event: ChatEvent): SessionRunInfo {
        if (run.isTerminal) return run
        return when (event.type) {
            "tool_call" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Running: ${(event as? ChatEvent.ToolCallEvent)?.toolName.orEmpty()}".trim(),
                clearHumanRequest = true,
                clearError = true,
            )
            "tool_call_delta" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Preparing tool call",
                clearHumanRequest = true,
                clearError = true,
            )
            "agent_tool_call", "agent_tool_call_delta" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Agent tool call",
                clearHumanRequest = true,
                clearError = true,
            )
            "tool_output_chunk" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Reading output",
                clearHumanRequest = true,
                clearError = true,
            )
            "reasoning_delta", "thinking" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Thinking",
                clearHumanRequest = true,
                clearError = true,
            )
            "response", "response_delta" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Writing response",
                clearHumanRequest = true,
                clearError = true,
            )
            "asking_human" -> {
                val obj = JSONObject(event.rawJson)
                val question = obj.optString("question", "Agent needs confirmation")
                val requestId = obj.optString("request_id")
                backgroundController?.showHitlNotification(requestId, question)
                updateSessionRun(
                    run,
                    status = SessionRunStatus.WaitingForInput,
                    activity = "Waiting for input",
                    humanRequestId = requestId,
                    clearError = true,
                )
            }
            "human_response", "message_injected" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Continuing",
                clearHumanRequest = true,
                clearError = true,
            )
            "stream_reset" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Reconnecting",
                clearHumanRequest = true,
                clearError = true,
            )
            "error" -> {
                val message = (event as? ChatEvent.ErrorEvent)?.message ?: JSONObject(event.rawJson).optString("message")
                backgroundController?.showErrorNotification(message = message)
                updateSessionRun(
                    run,
                    status = SessionRunStatus.Failed,
                    activity = message,
                    error = message,
                )
            }
            "evolution_queued" -> updateSessionRun(
                run,
                status = SessionRunStatus.Completed,
                activity = "Queued learning",
                clearHumanRequest = true,
            )
            "skill_activated" -> updateSessionRun(
                run,
                status = SessionRunStatus.Running,
                activity = "Using skill",
                clearHumanRequest = true,
                clearError = true,
            )
            else -> run
        }
    }

    private fun updateBackgroundRunSummary() {
        val bg = backgroundController ?: return
        if (!bg.isRunning) return
        val runs = activeSessionRuns
        if (runs.isEmpty()) return
        if (runs.size == 1) {
            bg.updateNotification(runs.single().activity)
            return
        }
        val waitingCount = runs.count { it.needsInput }
        val suffix = if (waitingCount == 0) "" else " - $waitingCount waiting"
        bg.updateNotification("${runs.size} sessions running$suffix")
    }

    private fun maybeShowCompletionNotification() {
        val bg = backgroundController ?: return
        if (bg.isRunning && activeSessionRuns.isEmpty()) {
            bg.showCompletionNotification()
            bg.stop()
        }
    }

    private fun startBackgroundForRun() {
        val bg = backgroundController ?: return
        if (!bg.isRunning) {
            runCatching { bg.start() }
        }
    }

    internal fun defaultCapabilityProfile(): NapaxiCapabilityProfile =
        buildHostCapabilityProfile(
            hasCustomToolExecutor = toolExecutor != null,
            hasAgentAppActionExecutor = agentAppActionExecutor != null,
            hasBrowserController = browserController != null,
            enablePlatformTools = platformToolExecutor != null,
            hasPlatformMediaToolHandler = hasPlatformMediaToolHandler,
            enableAutomation = automationEnabled,
        )

    internal fun defaultCapabilitySelection(): NapaxiCapabilitySelection =
        buildHostCapabilitySelection(
            hasCustomToolExecutor = toolExecutor != null,
            hasAgentAppActionExecutor = agentAppActionExecutor != null,
            hasBrowserController = browserController != null,
            enablePlatformTools = platformToolExecutor != null,
            hasPlatformMediaToolHandler = hasPlatformMediaToolHandler,
            enableAutomation = automationEnabled,
        )

    private fun checkNotDisposed() {
        check(!disposed) { "NapaxiEngine is already disposed" }
    }

    public companion object {
        public const val DEFAULT_AGENT_ID: String = "napaxi"
        public const val DEFAULT_ACCOUNT_ID: String = "default"

        @JvmStatic
        @JvmOverloads
        public fun create(
            context: Context,
            config: LlmConfig,
            toolExecutor: McToolExecutor? = null,
            agentAppActionExecutor: AgentAppActionExecutor? = null,
            toolApprovalHandler: McToolApprovalHandler? = null,
            browserController: NapaxiBrowserController? = null,
            platformMediaToolHandler: AndroidPlatformMediaToolHandler? = null,
            enablePlatformTools: Boolean = AndroidPlatformToolExecutor.isSupported,
            backgroundConfig: BackgroundConfig? = null,
            enableAutomation: Boolean = backgroundConfig != null,
            capabilityProfile: NapaxiCapabilityProfile? = null,
            capabilitySelection: NapaxiCapabilitySelection? = null,
            streamExecutor: Executor = Executors.newSingleThreadExecutor(),
        ): NapaxiEngine {
            val appContext = context.applicationContext
            val effectiveAgentAppActionExecutor =
                agentAppActionExecutor ?: (context as? Activity)?.let(::AndroidAgentProviderActionExecutor)
            NapaxiNative.registerAssetManager(appContext.assets)
            val platformTools = if (enablePlatformTools) {
                AndroidPlatformToolExecutor(appContext, platformMediaToolHandler)
            } else {
                null
            }
            val toolDispatcherRegistered =
                toolExecutor != null ||
                effectiveAgentAppActionExecutor != null ||
                toolApprovalHandler != null ||
                browserController != null ||
                platformTools != null
            if (toolDispatcherRegistered) {
                registerToolDispatcher(
                    toolExecutor,
                    effectiveAgentAppActionExecutor,
                    toolApprovalHandler,
                    browserController,
                    platformTools,
                )
            }
            val profile = capabilityProfile ?: buildHostCapabilityProfile(
                hasCustomToolExecutor = toolExecutor != null,
                hasAgentAppActionExecutor = effectiveAgentAppActionExecutor != null,
                hasBrowserController = browserController != null,
                enablePlatformTools = platformTools != null,
                hasPlatformMediaToolHandler = platformMediaToolHandler != null,
                enableAutomation = enableAutomation,
            )
            val selection = capabilitySelection ?: buildHostCapabilitySelection(
                hasCustomToolExecutor = toolExecutor != null,
                hasAgentAppActionExecutor = effectiveAgentAppActionExecutor != null,
                hasBrowserController = browserController != null,
                enablePlatformTools = platformTools != null,
                hasPlatformMediaToolHandler = platformMediaToolHandler != null,
                enableAutomation = enableAutomation,
            )
            val platformContextJson = buildPlatformContextJson(appContext, profile, selection)
            val handle = NapaxiNative.createEngine(config.toJson(), platformContextJson)
            check(handle != 0L) { "Failed to create Napaxi engine" }
            val backgroundController = backgroundConfig
                ?.takeIf { it.enabled }
                ?.let { NapaxiBackgroundController(appContext, it) }
            return NapaxiEngine(
                appContext,
                handle,
                config,
                toolExecutor,
                effectiveAgentAppActionExecutor,
                toolApprovalHandler,
                browserController,
                platformTools,
                backgroundController,
                enableAutomation,
                streamExecutor,
                hasPlatformMediaToolHandler = platformMediaToolHandler != null,
                toolDispatcherRegistered = toolDispatcherRegistered,
            )
        }

        private fun registerToolDispatcher(
            toolExecutor: McToolExecutor?,
            agentAppActionExecutor: AgentAppActionExecutor?,
            toolApprovalHandler: McToolApprovalHandler?,
            browserController: NapaxiBrowserController?,
            platformToolExecutor: AndroidPlatformToolExecutor?,
        ) {
            NapaxiNative.registerToolRequestCallback(object : ToolRequestCallback {
                override fun onToolRequest(requestJson: String) {
                    val request = JSONObject(requestJson)
                    val requestId = request.optLong("request_id")
                    val toolName = request.optString("tool_name")
                    val paramsJson = request.optString("params_json", "{}")
                    val contextJson = request.optJSONObject("context")?.toString() ?: "{}"
                    try {
                        val callback = nativeToolCallback(requestId)
                        when {
                            toolName == "__napaxi_approval__" || toolName == "approval_request" ->
                                toolApprovalHandler?.requestApproval(
                                    McToolApprovalRequest.fromToolRequest(requestId, paramsJson, contextJson),
                                    callback,
                                ) ?: callback.success(McToolApprovalResponse(false, message = "No tool approval handler registered").toJson())
                            toolName == "__napaxi_agent_app_action__" || toolName.startsWith("app_action_") ->
                                runCatching { AgentAppActionRequest(paramsJson) }
                                    .fold(
                                        onSuccess = { actionRequest ->
                                            agentAppActionExecutor?.execute(actionRequest, object : AgentAppActionCallback {
                                                override fun success(result: AgentAppActionResult) {
                                                    callback.success(result.rawJson)
                                                }

                                                override fun error(code: String, message: String) {
                                                    callback.success(
                                                        AndroidAgentProviderActionExecutor.failedActionResult(
                                                            actionRequest.requestId,
                                                            "$code: $message",
                                                        ).rawJson,
                                                    )
                                                }
                                            }) ?: callback.success(
                                                AndroidAgentProviderActionExecutor.failedActionResult(
                                                    actionRequest.requestId,
                                                    "No agent app action executor registered",
                                                ).rawJson,
                                            )
                                        },
                                        onFailure = { error ->
                                            callback.success(
                                                AndroidAgentProviderActionExecutor.failedActionResult(
                                                    requestId = "",
                                                    message = error.message ?: "Invalid agent app action request JSON",
                                                ).rawJson,
                                            )
                                        },
                                    )
                            platformToolExecutor?.canHandle(toolName) == true ->
                                platformToolExecutor.execute(toolName, paramsJson, contextJson, callback)
                            browserController?.canHandle(toolName) == true ->
                                browserController.execute(toolName, paramsJson, callback)
                            toolExecutor != null ->
                                toolExecutor.execute(toolName, paramsJson, callback)
                            else -> callback.error("No Android host executor registered for tool: $toolName")
                        }
                    } catch (error: Throwable) {
                        NapaxiNative.resolveToolExecution(
                            requestId,
                            error.message ?: error::class.java.simpleName,
                            true,
                        )
                    }
                }
            })
        }

        private fun nativeToolCallback(requestId: Long): McToolCallback =
            object : McToolCallback {
                override fun success(resultJson: String) {
                    NapaxiNative.resolveToolExecution(requestId, resultJson, false)
                }

                override fun error(message: String) {
                    NapaxiNative.resolveToolExecution(requestId, message, true)
                }
            }

        private fun buildPlatformContextJson(
            context: Context,
            profile: NapaxiCapabilityProfile,
            selection: NapaxiCapabilitySelection,
        ): String {
            return JSONObject(NapaxiPlatformContextResolver.resolve(context).platformContextJson)
                .put("capability_profile", profile.toJsonObject())
                .put(
                    "skill_readiness",
                    JSONObject()
                        .put("platform", profile.platform ?: "android")
                        .put("capabilities", JSONArray(profile.supportedCapabilities))
                        .put("use_process_fallback", false),
                )
                .put("capability_selection", selection.toJsonObject())
                .toString()
        }

        private fun buildHostCapabilityProfile(
            hasCustomToolExecutor: Boolean,
            hasAgentAppActionExecutor: Boolean,
            hasBrowserController: Boolean,
            enablePlatformTools: Boolean,
            hasPlatformMediaToolHandler: Boolean,
            enableAutomation: Boolean,
        ): NapaxiCapabilityProfile = NapaxiCapabilityProfile(
            platform = "android",
            supportedCapabilities = listOfNotNull(
                NapaxiChannelCapability.IM,
                NapaxiChannelCapability.DEVICE,
                "napaxi.tool.custom_host".takeIf { hasCustomToolExecutor },
                "napaxi.tool.agent_app_action".takeIf { hasAgentAppActionExecutor },
                "napaxi.platform_tool.*".takeIf { enablePlatformTools },
                "napaxi.tool.browser".takeIf { hasBrowserController },
                "napaxi.service.automation".takeIf { enableAutomation },
            ),
            disabledCapabilities = listOfNotNull(
                "napaxi.platform_tool.take_photo".takeIf { enablePlatformTools && !hasPlatformMediaToolHandler },
                "napaxi.platform_tool.media_library".takeIf { enablePlatformTools && !hasPlatformMediaToolHandler },
                "napaxi.platform_tool.record_audio".takeIf { enablePlatformTools && !hasPlatformMediaToolHandler },
            ),
        )

        private fun buildHostCapabilitySelection(
            hasCustomToolExecutor: Boolean,
            hasAgentAppActionExecutor: Boolean,
            hasBrowserController: Boolean,
            enablePlatformTools: Boolean,
            hasPlatformMediaToolHandler: Boolean,
            enableAutomation: Boolean,
        ): NapaxiCapabilitySelection = NapaxiCapabilitySelection(
            enabledCapabilities = listOfNotNull(
                NapaxiChannelCapability.IM,
                NapaxiChannelCapability.DEVICE,
                "napaxi.tool.custom_host".takeIf { hasCustomToolExecutor },
                "napaxi.tool.agent_app_action".takeIf { hasAgentAppActionExecutor },
                "napaxi.tool.browser".takeIf { hasBrowserController },
                "napaxi.service.automation".takeIf { enableAutomation },
            ),
            disabledCapabilities = listOfNotNull(
                "napaxi.platform_tool.take_photo".takeIf { enablePlatformTools && !hasPlatformMediaToolHandler },
                "napaxi.platform_tool.media_library".takeIf { enablePlatformTools && !hasPlatformMediaToolHandler },
                "napaxi.platform_tool.record_audio".takeIf { enablePlatformTools && !hasPlatformMediaToolHandler },
            ),
        )
    }

    internal fun bridge(method: String, args: JSONObject = JSONObject(), handle: Long = this.handle): String {
        checkNotDisposed()
        return unwrapBridgeResult(NapaxiNative.callBridge(method, handle, args.toString()))
    }

    internal fun bridgeBool(method: String, args: JSONObject = JSONObject(), handle: Long = this.handle): Boolean {
        val raw = bridge(method, args, handle)
        return raw == "true" || runCatching { JSONObject(raw).optBoolean("success", false) }.getOrDefault(false)
    }

    internal fun bridgeLong(method: String, args: JSONObject = JSONObject(), handle: Long = this.handle): Long =
        bridge(method, args, handle).trim().toLongOrNull()
            ?: runCatching { JSONObject(bridge(method, args, handle)).optLong("value", 0L) }.getOrDefault(0L)
}

internal fun unwrapBridgeResult(raw: String): String {
    val obj = runCatching { JSONObject(raw.trim()) }.getOrNull() ?: return raw
    if (!obj.has("ok")) return raw
    if (!obj.optBoolean("ok", false)) return raw
    if (!obj.has("value") || obj.isNull("value")) return "null"
    val value = obj.get("value")
    return when (value) {
        is JSONObject -> value.toString()
        is JSONArray -> value.toString()
        else -> value.toString()
    }
}

private fun List<McAttachment>.toJsonArrayString(sandboxPaths: List<String>? = null): String {
    val arr = JSONArray()
    forEachIndexed { index, attachment -> arr.put(attachment.toJsonObject(sandboxPaths?.getOrNull(index))) }
    return arr.toString()
}
