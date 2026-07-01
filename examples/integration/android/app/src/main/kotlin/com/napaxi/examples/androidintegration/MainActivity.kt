package com.napaxi.examples.androidintegration

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.text.TextUtils
import android.view.Gravity
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.napaxi.android.A2ALocalPeerAdvertisement
import com.napaxi.android.AgentAppActionManifest
import com.napaxi.android.AgentAppActionProposal
import com.napaxi.android.AgentAppActionResult
import com.napaxi.android.AgentAppPackage
import com.napaxi.android.AgentDefinition
import com.napaxi.android.AgentProviderHostApi
import com.napaxi.android.AndroidPlatformMediaToolHandler
import com.napaxi.android.AndroidPlatformMediaToolRequest
import com.napaxi.android.AutomationJob
import com.napaxi.android.AutomationPayload
import com.napaxi.android.AutomationTrigger
import com.napaxi.android.BackgroundConfig
import com.napaxi.android.ChatEvent
import com.napaxi.android.ChatEventListener
import com.napaxi.android.ContextEngineConfig
import com.napaxi.android.CustomToolDef
import com.napaxi.android.LlmConfig
import com.napaxi.android.McAttachment
import com.napaxi.android.McToolCallback
import com.napaxi.android.McToolExecutor
import com.napaxi.android.NapaxiBackgroundPermissions
import com.napaxi.android.NapaxiBrowserController
import com.napaxi.android.NapaxiConfigProfile
import com.napaxi.android.NapaxiConfigSelection
import com.napaxi.android.NapaxiConfigStore
import com.napaxi.android.NapaxiEngine
import com.napaxi.android.NapaxiFileBridge
import com.napaxi.android.PendingAgentProviderInstall
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

class MainActivity : Activity() {
    private val hostScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private lateinit var statusView: TextView
    private lateinit var actionContainer: LinearLayout
    private lateinit var rootContainer: LinearLayout
    private var engine: NapaxiEngine? = null
    private var pendingProviderInstall: PendingAgentProviderInstall? = null
    private var runSmokeAfterProviderInstall: Boolean = false
    private var lastInstalledProviderName: String? = null
    private var pendingProviderActionRequestId: String? = null
    private var runSmokeAfterProviderAction: Boolean = false
    private var lastProviderActionStatus: String = "none"
    private var runSmokeAfterNotificationPermission: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        statusView = TextView(this).apply {
            text = "Ready. Pick a section below; results stay here."
            textSize = 14f
            maxLines = 8
            ellipsize = TextUtils.TruncateAt.END
            setTextIsSelectable(true)
            setTextColor(Color.rgb(28, 32, 36))
            setBackgroundColor(Color.rgb(238, 243, 255))
            setPadding(20, 16, 20, 16)
        }

        rootContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(250, 250, 250))
            setPadding(0, 0, 0, 0)
            setOnApplyWindowInsetsListener { view, insets ->
                val (topInset, bottomInset) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    val bars = insets.getInsets(WindowInsets.Type.systemBars())
                    bars.top to bars.bottom
                } else {
                    @Suppress("DEPRECATION")
                    insets.systemWindowInsetTop to insets.systemWindowInsetBottom
                }
                view.setPadding(0, topInset, 0, bottomInset)
                insets
            }
        }

        rootContainer.addView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(24, 18, 24, 12)
                setBackgroundColor(Color.WHITE)
                addView(label("Napaxi Android Native Demo", size = 22f, bold = true))
                addView(
                    label(
                        "Native SDK host surface. Tap an action; progress and results appear immediately below.",
                        size = 13f,
                    ),
                )
                addView(statusView)
            },
        )

        actionContainer = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(24, 16, 24, 32)
        }
        buildDemoUi()
        rootContainer.addView(
            ScrollView(this).apply { addView(actionContainer) },
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f,
            ),
        )
        setContentView(rootContainer)
        maybeRunRequestedSmoke(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        maybeRunRequestedSmoke(intent)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (engine?.onActivityResult(requestCode, resultCode, data) == true) return

        if (requestCode == AgentProviderHostApi.REQUEST_HANDLE_PROPOSAL) {
            handleProviderActionResult(resultCode, data)
            return
        }

        val pending = pendingProviderInstall
        if (pending == null || requestCode != pending.requestCode) {
            super.onActivityResult(requestCode, resultCode, data)
            return
        }

        hostScope.launch {
            val result = runCatching {
                requireNotNull(engine).onAgentProviderInstallActivityResult(
                    requestCode = requestCode,
                    resultCode = resultCode,
                    data = data,
                    pending = pending,
                )
            }
            result.onSuccess { installed ->
                if (installed != null) {
                    pendingProviderInstall = null
                    lastInstalledProviderName = installed.displayName
                }
                val shouldContinueSmoke = runSmokeAfterProviderInstall && installed != null
                runSmokeAfterProviderInstall = false
                if (shouldContinueSmoke) {
                    runProviderActionSmoke(installed)
                } else {
                    setStatus("Provider install result: ${installed?.displayName ?: "none"}")
                }
            }.onFailure { error ->
                runSmokeAfterProviderInstall = false
                setStatus("Provider install failed: ${error.message}")
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NapaxiBackgroundPermissions.REQUEST_POST_NOTIFICATIONS) return

        val shouldContinueSmoke = runSmokeAfterNotificationPermission
        runSmokeAfterNotificationPermission = false
        if (!shouldContinueSmoke) return

        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) {
            runSdkSmoke()
        } else {
            setStatus("Smoke failed: notification permission denied")
        }
    }

    override fun onDestroy() {
        engine?.dispose()
        hostScope.cancel()
        super.onDestroy()
    }

    private fun buildDemoUi() {
        actionContainer.removeAllViews()
        addFullWidthButton("Run Full Interface Tour") { runFullInterfaceTour() }
        addFullWidthButton("Run SDK Smoke") { runSdkSmoke() }

        addSection(
            "Runtime",
            "Create Engine" to { createEngine() },
            "Config + Engine" to { runDemo("Config + Engine") { runEngineDemo() } },
            "Capabilities" to { runDemo("Capabilities") { runCapabilityDemo() } },
            "Tools + Browser" to { runDemo("Tools + Browser") { runToolDemo() } },
        )
        addSection(
            "Conversation",
            "Sessions + Chat" to { runDemo("Sessions + Chat") { runSessionChatDemo() } },
            "Agents + Groups" to { runDemo("Agents + Groups") { runAgentGroupDemo() } },
            "Session Runs" to { runDemo("Session Runs") { runSessionRunDemo() } },
        )
        addSection(
            "Knowledge",
            "Workspace + Memory" to { runDemo("Workspace + Memory") { runWorkspaceDemo() } },
            "File Bridge" to { runDemo("File Bridge") { runFileBridgeDemo() } },
            "Skills + Evolution" to { runDemo("Skills + Evolution") { runSkillEvolutionDemo() } },
        )
        addSection(
            "Host Integration",
            "Background" to { runDemo("Background") { runBackgroundDemo() } },
            "Automation" to { runDemo("Automation") { runAutomationDemo() } },
            "MCP" to { runDemo("MCP") { runMcpDemo() } },
            "A2A" to { runDemo("A2A") { runA2ADemo() } },
            "Agent App" to { runDemo("Agent App") { runAgentAppDemo() } },
            "Provider Discovery" to { runDemo("Provider Discovery") { runProviderDiscoveryDemo() } },
            "Install First Provider" to { installFirstProvider() },
            "APK Installer" to { runDemo("APK Installer") { runApkInstallerDemo() } },
        )
    }

    private fun addSection(title: String, vararg actions: Pair<String, () -> Unit>) {
        actionContainer.addView(label(title, size = 18f, bold = true))
        actions.asList().chunked(2).forEach { rowActions ->
            actionContainer.addView(
                LinearLayout(this).apply {
                    orientation = LinearLayout.HORIZONTAL
                    rowActions.forEach { (label, action) ->
                        addView(
                            button(label, action).apply {
                                layoutParams = LinearLayout.LayoutParams(
                                    0,
                                    LinearLayout.LayoutParams.WRAP_CONTENT,
                                    1f,
                                ).apply {
                                    marginStart = 4
                                    marginEnd = 4
                                    topMargin = 6
                                    bottomMargin = 6
                                }
                            },
                        )
                    }
                    if (rowActions.size == 1) {
                        addView(
                            View(this@MainActivity).apply {
                                layoutParams = LinearLayout.LayoutParams(
                                    0,
                                    1,
                                    1f,
                                )
                            },
                        )
                    }
                },
                LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ),
            )
        }
    }

    private fun addFullWidthButton(label: String, onClick: () -> Unit) {
        actionContainer.addView(
            button(label, onClick).apply {
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                ).apply {
                    topMargin = 8
                    bottomMargin = 8
                }
            },
        )
    }

    private fun createEngine(): NapaxiEngine {
        engine?.let { return it }
        val configStore = NapaxiConfigStore.sharedPreferences(this)
        configStore.saveProfile(
            NapaxiConfigProfile(
                id = "local-dev",
                name = "Local Dev",
                provider = "openai",
                model = "gpt-4.1",
                systemPrompt = "You are a helpful Android-native Napaxi agent.",
                metadata = JSONObject().put("response_language", "zh"),
            ),
            apiKey = "",
        )
        configStore.saveSelection(NapaxiConfigSelection(selectedProfileId = "local-dev"))
        val config = configStore.resolveSelectedConfig() ?: LlmConfig(
            provider = "openai",
            apiKey = "",
            model = "gpt-4.1",
            systemPrompt = "You are a helpful Android-native Napaxi agent.",
            responseLanguage = "zh",
            contextEngine = ContextEngineConfig(preCompactionMemoryFlush = true),
        )

        return NapaxiEngine.create(
            context = this,
            config = config,
            toolExecutor = McToolExecutor { toolName, paramsJson, callback ->
                val result = JSONObject()
                    .put("success", true)
                    .put("tool", toolName)
                    .put("params", JSONObject(paramsJson.ifBlank { "{}" }))
                    .put("handled_by", "android_native_demo")
                callback.success(result.toString())
            },
            browserController = NapaxiBrowserController { toolName, paramsJson, callback ->
                callback.success(
                    JSONObject()
                        .put("success", true)
                        .put("tool", toolName)
                        .put("params", JSONObject(paramsJson.ifBlank { "{}" }))
                        .put("note", "Demo browser controller accepted the request.")
                        .toString(),
                )
            },
            platformMediaToolHandler = object : AndroidPlatformMediaToolHandler {
                override fun takePhoto(request: AndroidPlatformMediaToolRequest, callback: McToolCallback) {
                    callback.success(request.context.errorJson("Camera flow is host-owned; demo returns a stable error shape."))
                }

                override fun recordAudio(request: AndroidPlatformMediaToolRequest, callback: McToolCallback) {
                    callback.success(request.context.errorJson("Audio flow is host-owned; demo returns a stable error shape."))
                }
            },
            backgroundConfig = BackgroundConfig(enabled = true),
            enablePlatformTools = true,
        ).also {
            engine = it
            setStatus("Engine created: filesDir=${it.filesDir}")
        }
    }

    private suspend fun runEngineDemo(): String {
        val sdk = createEngine()
        val store = NapaxiConfigStore.sharedPreferences(this)
        val profiles = store.loadProfiles()
        val selection = store.loadSelection()
        val resolved = store.resolveSelectedConfig()
        val updated = resolved?.let { sdk.updateConfig(it) } ?: false
        val ensured = runCatching { sdk.ensureAgent() }.getOrDefault(false)
        return listOf(
            "profiles=${profiles.map { it.id }}",
            "selected=${selection.selectedProfileId}",
            "provider=${resolved?.provider}",
            "model=${resolved?.model}",
            "updateConfig=$updated",
            "ensureAgent=$ensured",
            "filesDir=${sdk.filesDir}",
        ).joinToString("\n")
    }

    private suspend fun runCapabilityDemo(): String {
        val sdk = createEngine()
        val definitions = sdk.capabilities.definitions()
        val statuses = sdk.capabilities.status()
        val providerId = sdk.capabilities.providerCapabilityId("openai")
        val toolId = sdk.capabilities.toolCapabilityId("android_integration_ping")
        val enabled = statuses.count { it.enabled }
        val unavailable = statuses.filter { !it.available }.take(4).joinToString { status ->
            "${status.definition.id}:${status.unavailableReason ?: "unavailable"}"
        }
        return listOf(
            "registered=${definitions.size}",
            "enabled=$enabled",
            "provider(openai)=$providerId",
            "tool(android_integration_ping)=$toolId",
            "sample=${definitions.take(8).joinToString { it.id }}",
            "unavailable=${unavailable.ifBlank { "none" }}",
        ).joinToString("\n")
    }

    private suspend fun runToolDemo(): String {
        val sdk = createEngine()
        val customTools = listOf(
            CustomToolDef(
                name = "android_integration_ping",
                description = "Return Android native demo host state.",
                parameters = JSONObject("""{"type":"object","properties":{"message":{"type":"string"}}}"""),
                effect = "read",
            ),
            CustomToolDef(
                name = "android_demo_device_note",
                description = "Record a mock device note in the host app.",
                effect = "mutates_user_data",
            ),
        )
        val customUpdated = sdk.tools.updateCustomTools(customTools)
        sdk.tools.startRequestListener()
        val available = sdk.tools.availableTools()
        val platform = sdk.tools.platformToolDescriptors()
        val browser = sdk.tools.browserToolDescriptors()
        return listOf(
            "customUpdated=$customUpdated",
            "available=${available.size}",
            "platform=${platform.size}, open_url=${sdk.tools.isPlatformTool("open_url")}",
            "browser=${browser.size}, browser_open=${sdk.tools.isBrowserTool("browser_open")}",
            "custom=${customTools.joinToString { it.name }}",
            "platformSample=${platform.take(8).joinToString { it.name }}",
        ).joinToString("\n")
    }

    private suspend fun runSessionChatDemo(): String {
        val sdk = createEngine()
        val session = sdk.sessions.create(agentId = NapaxiEngine.DEFAULT_AGENT_ID)
        val injected = sdk.sessions.injectMessage(
            session,
            "Android native demo injected host context.",
            agentId = NapaxiEngine.DEFAULT_AGENT_ID,
        )
        val history = sdk.sessions.history(session.threadId)
        val page = sdk.sessions.historyPage(session.threadId, limit = 10)
        val context = sdk.sessions.contextStatus(session.threadId)
        val chatEvents = mutableListOf<String>()
        runCatching {
            sdk.chat.sendToSession(
                session,
                "Reply with a one-line Android SDK demo greeting.",
                maxIterations = 1,
            ).collect { event ->
                chatEvents += event.type
                if (chatEvents.size >= 8) return@collect
            }
        }.onFailure { error ->
            chatEvents += "chat_error:${error.message ?: error::class.java.simpleName}"
        }
        return listOf(
            "thread=${session.threadId}",
            "injectMessage=$injected",
            "history=${history.size}",
            "historyPage=${page.messages.size}",
            "contextTokens=${context.displayUsedTokens}/${context.effectiveContextWindowTokens}",
            "chatEvents=${chatEvents.joinToString()}",
        ).joinToString("\n")
    }

    private suspend fun runSessionRunDemo(): String {
        val sdk = createEngine()
        val active = sdk.sessionRuns.active()
        val runs = sdk.sessionRuns.list(limit = 10)
        return listOf(
            "active=${active.size}",
            "stored=${runs.size}",
            "activeEngineSnapshot=${sdk.activeSessionRuns.size}",
            "latest=${runs.firstOrNull()?.runId ?: "none"}",
        ).joinToString("\n")
    }

    private suspend fun runAgentGroupDemo(): String {
        val sdk = createEngine()
        val agentId = "android-native-demo-agent"
        val handle = sdk.agents.getOrCreate(agentId)
        val definition = sdk.agents.createDefinition(
            AgentDefinition.create(
                id = "android-native-demo-definition",
                name = "Android Native Demo Agent",
                description = "Demo-only agent definition from the Android native app.",
                systemPrompt = "You are demonstrating the native Android SDK.",
            ),
        )
        val definitions = sdk.agents.listDefinitions()
        val createdFromDefinition = runCatching { sdk.agents.createFromDefinition(definition.id) }.getOrDefault(false)
        val groupId = sdk.groups.create("Android Demo Group", listOf(agentId, NapaxiEngine.DEFAULT_AGENT_ID))
        val group = sdk.groups.get(groupId)
        val renamed = sdk.groups.rename(groupId, "Android Demo Group Updated")
        val memberUpdated = sdk.groups.updateMembers(groupId, listOf(agentId))
        val groups = sdk.groups.list()
        val messages = sdk.groups.messages(groupId)
        val exported = sdk.groups.exportState()
        sdk.groups.delete(groupId)
        return listOf(
            "agent=${handle.agentId}",
            "definition=${definition.id}, totalDefinitions=${definitions.size}",
            "createFromDefinition=$createdFromDefinition",
            "group=${group?.name ?: groupId}",
            "rename=$renamed, members=$memberUpdated",
            "groups=${groups.size}, messages=${messages.size}, exportBytes=${exported.length}",
        ).joinToString("\n")
    }

    private suspend fun runWorkspaceDemo(): String {
        val sdk = createEngine()
        val path = "/workspace/android-native-demo.txt"
        val write = sdk.workspace.writeFile(path, "hello from Android native demo\n")
        val append = sdk.workspace.appendFile(path, "updated=${Instant.now()}\n")
        val read = sdk.workspace.readFile(path)
        val entries = sdk.workspace.listFiles("/workspace")
        val search = sdk.workspace.search("Android native demo", limit = 3)
        val recallStats = sdk.workspace.recallIndexStats()
        val journalDays = sdk.workspace.listJournalDays()
        val systemPrompt = sdk.workspace.systemPrompt()
        return listOf(
            "write=$write, append=$append",
            "readBytes=${read?.content?.length ?: 0}",
            "entries=${entries.size}",
            "search=${search.size}",
            "recallIndexed=${recallStats.indexedDocs}",
            "journalDays=${journalDays.size}",
            "systemPromptBytes=${systemPrompt.length}",
        ).joinToString("\n")
    }

    private suspend fun runFileBridgeDemo(): String {
        val sdk = createEngine()
        val init = sdk.fileBridge.init()
        val path = "/workspace/android-native-file-bridge.txt"
        sdk.workspace.writeFile(path, "file bridge demo")
        val real = sdk.fileBridge.sandboxToReal(path)
        val sandbox = real?.let { sdk.fileBridge.realToSandbox(it) }
        val refs = sdk.fileBridge.detectFileReferences("Please inspect $path")
        val files = sdk.fileBridge.listFiles(recursive = true)
        val size = sdk.fileBridge.workspaceSize()
        val dir = sdk.fileBridge.workspaceDir()
        val attachmentSaved = sdk.fileBridge.saveMessageAttachments(
            threadId = "android-native-demo-thread",
            userMessageIndex = 0,
            attachments = listOf(
                McAttachment(
                    kind = "document",
                    mimeType = "text/plain",
                    filename = "android-native-file-bridge.txt",
                    sandboxPath = path,
                ),
            ),
        )
        val attachmentJson = sdk.fileBridge.loadThreadAttachments("android-native-demo-thread")
        val openShape = NapaxiFileBridge.openLocalFileResult(this, "", "text/plain")
        return listOf(
            "init=$init",
            "workspaceDir=$dir",
            "sandboxToReal=${real ?: "none"}",
            "realToSandbox=${sandbox ?: "none"}",
            "refs=${refs.size}, files=${files.size}, size=$size",
            "attachments=$attachmentSaved/${attachmentJson.length} bytes",
            "openBlankSuccess=${openShape.optBoolean("success")}",
        ).joinToString("\n")
    }

    private suspend fun runSkillEvolutionDemo(): String {
        val sdk = createEngine()
        val skills = sdk.skills.list()
        val status = sdk.skills.status()
        val sources = sdk.skills.sources()
        val commands = sdk.skills.commands()
        val resolved = sdk.skills.resolveCommand("/help")
        val usage = sdk.skills.usage()
        val snapshots = sdk.skills.snapshots(limit = 5)
        val pending = sdk.evolution.listPending()
        val runs = sdk.evolution.runs()
        val diagnostics = sdk.evolution.diagnostics()
        return listOf(
            "skills=${skills.size}",
            "statusReady=${status.ready}/${status.entries.size}",
            "sources=${sources.sources.size}",
            "commands=${commands.commands.size}, /help=${resolved.command?.name ?: "none"}",
            "usage=${usage.size}, snapshots=${snapshots.snapshots.size}",
            "evolutionPending=${pending.size}, runs=${runs.size}, diagnostics=${diagnostics.size}",
        ).joinToString("\n")
    }

    private suspend fun runBackgroundDemo(): String {
        val sdk = createEngine()
        val allowed = sdk.background.checkNotificationPermission(this)
        val canRun = sdk.background.canRunInBackground(this)
        sdk.background.startService()
        delay(250)
        sdk.background.updateNotification("Android native demo background surface is running", progress = 40)
        sdk.background.showCompletionNotification(
            title = "Napaxi Android Native Demo",
            message = "Background notification API exercised",
        )
        val running = sdk.background.controller?.isRunning == true
        sdk.background.stopService()
        return listOf(
            "notificationAllowed=$allowed",
            "canRun=$canRun",
            "controllerPresent=${sdk.background.controller != null}",
            "runningAfterStart=$running",
        ).joinToString("\n")
    }

    private suspend fun runAutomationDemo(): String {
        val sdk = createEngine()
        val job = sdk.automation.createJob(
            AutomationJob.create(
                name = "Android native demo wake",
                trigger = AutomationTrigger.hostEvent("android_demo_opened", source = "native_demo"),
                payload = AutomationPayload.systemEvent("Android native demo host event"),
                enabled = true,
                accountId = NapaxiEngine.DEFAULT_ACCOUNT_ID,
                agentId = NapaxiEngine.DEFAULT_AGENT_ID,
            ),
        )
        val listed = sdk.automation.listAutomationJobs(
            accountId = NapaxiEngine.DEFAULT_ACCOUNT_ID,
            agentId = NapaxiEngine.DEFAULT_AGENT_ID,
        )
        val updated = sdk.automation.updateJob(job.id, JSONObject().put("enabled", false))
        val wake = sdk.automation.recordWake(job.id, "native_demo")
        val runs = sdk.automation.listRuns(job.id, limit = 5)
        val next = sdk.automation.nextWake()
        val deleted = sdk.automation.deleteJob(job.id)
        return listOf(
            "created=${job.id}",
            "listed=${listed.size}",
            "updatedEnabled=${updated.enabled}",
            "wake=${wake.status}",
            "runs=${runs.size}",
            "next=${next?.jobId ?: "none"}",
            "deleted=$deleted",
        ).joinToString("\n")
    }

    private suspend fun runMcpDemo(): String {
        val sdk = createEngine()
        val serverName = "android-native-demo"
        sdk.mcp.removeServer(serverName)
        val added = sdk.mcp.addServer(
            name = serverName,
            url = "https://example.test/mcp",
            headers = mapOf("X-Napaxi-Demo" to "android"),
            transport = "streamable_http",
        )
        val servers = sdk.mcp.listServers()
        val activated = sdk.mcp.activate(serverName)
        val tools = sdk.mcp.listTools(serverName = serverName)
        val oauth = sdk.mcp.startOAuth(
            name = serverName,
            clientId = "demo-client",
            authorizationUrl = "https://example.test/oauth/authorize",
            tokenUrl = "https://example.test/oauth/token",
            scopes = listOf("demo.read"),
            usePkce = true,
        )
        val deactivated = sdk.mcp.deactivate(serverName)
        val removed = sdk.mcp.removeServer(serverName)
        return listOf(
            "addSuccess=${added.isSuccess}",
            "servers=${servers.size}",
            "activate=${activated.isSuccess}",
            "tools=${tools.size}",
            "oauthState=${oauth.state.ifBlank { "none" }}",
            "deactivated=$deactivated, removed=$removed",
        ).joinToString("\n")
    }

    private suspend fun runA2ADemo(): String {
        val sdk = createEngine()
        val card = sdk.a2a.agentCard()
        val invite = sdk.a2a.createPeerInvite(
            agentId = NapaxiEngine.DEFAULT_AGENT_ID,
            optionsJson = JSONObject().put("display_name", "Android Native Demo").toString(),
        )
        val peers = sdk.a2a.listPeers()
        val secret = sdk.a2a.generateLocalPairingSecret()
        val formatted = sdk.a2a.formatPairingSecret(secret)
        val peer = A2ALocalPeerAdvertisement.fromMap(
            mapOf(
                "peerId" to "android-peer",
                "agentId" to NapaxiEngine.DEFAULT_AGENT_ID,
                "displayName" to "Android Peer",
                "publicKey" to "android-public-key",
                "endpoint" to "127.0.0.1:0",
            ),
        )
        val pairingKey = sdk.a2a.pairingKey(peer)
        val transport = sdk.a2a.localTransportStatus()
        val tasks = sdk.a2a.listTasks(limit = 5)
        return listOf(
            "card=${card.agentId.ifBlank { "default" }}",
            "invite=${invite.peerId.ifBlank { invite.envelope.envelopeId.ifBlank { "created" } }}",
            "peers=${peers.size}",
            "pairing=$formatted",
            "pairingKey=${pairingKey.take(12)}...",
            "transportSupported=${transport.supported}",
            "tasks=${tasks.size}",
        ).joinToString("\n")
    }

    private suspend fun runAgentAppDemo(): String {
        val sdk = createEngine()
        val action = AgentAppActionManifest(
            actionId = "android.demo.echo",
            toolName = "android_demo_echo",
            description = "Echo a safe Android demo payload.",
            risk = "low",
            confirmationPolicy = "host_optional",
            timeoutSeconds = 60,
        )
        val packageDef = sdk.agentApp.registerPackage(
            AgentAppPackage(
                providerId = "com.napaxi.examples.androidintegration",
                agentId = "android-native-agent-app",
                displayName = "Android Native Demo Agent App",
                description = "Demo-only Agent App registration.",
                actions = listOf(action),
            ),
        )
        val requestId = UUID.randomUUID().toString()
        val proposal = AgentAppActionProposal(
            requestId = requestId,
            providerId = packageDef.providerId,
            agentId = packageDef.agentId,
            actionId = action.actionId,
            toolName = action.toolName,
            arguments = JSONObject().put("message", "hello"),
            userIntentSummary = "Exercise Agent App result APIs",
            createdAt = Instant.now().toString(),
            expiresAt = Instant.now().plusSeconds(60).toString(),
            nonce = UUID.randomUUID().toString(),
            idempotencyKey = requestId,
            risk = action.risk,
            confirmationPolicy = action.confirmationPolicy,
        )
        val result = sdk.agentApp.submitResult(
            AgentAppActionResult(
                requestId = proposal.requestId,
                status = "succeeded",
                result = JSONObject().put("echo", "hello"),
                completedAt = Instant.now().toString(),
            ),
        )
        val packages = sdk.agentApp.listPackages()
        val proposals = sdk.agentApp.listProposals(packageDef.agentId)
        val fetched = sdk.agentApp.getPackage(packageDef.agentId)
        val deleted = sdk.agentApp.deletePackage(packageDef.agentId)
        return listOf(
            "registered=${packageDef.displayName}",
            "packages=${packages.size}",
            "result=${result.status}",
            "proposals=${proposals.size}",
            "fetched=${fetched?.agentId ?: "none"}",
            "deleted=$deleted",
        ).joinToString("\n")
    }

    private suspend fun runProviderDiscoveryDemo(): String {
        val sdk = createEngine()
        val providers = sdk.agentProviderInstall.discoverProviders()
        val packages = sdk.agentApp.listPackages()
        val trigger = sdk.agentProviderTrigger.peekQueuedTrigger()
        return listOf(
            "discovered=${providers.size}",
            "providers=${providers.take(5).joinToString { it.displayName }}",
            "installedPackages=${packages.size}",
            "queuedTrigger=${trigger?.requestId ?: "none"}",
            "lastInstalled=${lastInstalledProviderName ?: "none"}",
            "lastAction=$lastProviderActionStatus",
        ).joinToString("\n")
    }

    private suspend fun runApkInstallerDemo(): String {
        val sdk = createEngine()
        val result = sdk.apkInstaller.installResult("")
        return listOf(
            "success=${result.success}",
            "installerOpened=${result.installerOpened}",
            "permissionRequired=${result.permissionRequired}",
            "code=${result.code ?: "none"}",
            "error=${result.error ?: "none"}",
        ).joinToString("\n")
    }

    private fun runFullInterfaceTour() {
        hostScope.launch {
            val sections: List<Pair<String, suspend () -> String>> = listOf(
                "Config + Engine" to { runEngineDemo() },
                "Capabilities" to { runCapabilityDemo() },
                "Tools + Browser" to { runToolDemo() },
                "Sessions + Chat" to { runSessionChatDemo() },
                "Agents + Groups" to { runAgentGroupDemo() },
                "Session Runs" to { runSessionRunDemo() },
                "Workspace + Memory" to { runWorkspaceDemo() },
                "File Bridge" to { runFileBridgeDemo() },
                "Skills + Evolution" to { runSkillEvolutionDemo() },
                "Background" to { runBackgroundDemo() },
                "Automation" to { runAutomationDemo() },
                "MCP" to { runMcpDemo() },
                "A2A" to { runA2ADemo() },
                "Agent App" to { runAgentAppDemo() },
                "Provider Discovery" to { runProviderDiscoveryDemo() },
                "APK Installer" to { runApkInstallerDemo() },
            )
            val output = StringBuilder("Running full Android SDK interface tour...")
            setStatus(output.toString())
            sections.forEachIndexed { index, (name, block) ->
                setStatus("Running full Android SDK interface tour...\n${index + 1}/${sections.size}: $name")
                val result = runCatching {
                    withTimeoutOrNull(DEMO_ACTION_TIMEOUT_MS) { block() }
                        ?: "Timed out after ${DEMO_ACTION_TIMEOUT_MS / 1_000}s; external service or model input may be missing."
                }
                    .getOrElse { error -> "failed=${error.message ?: error::class.java.simpleName}" }
                output.append("\n\n[").append(name).append("]\n").append(result)
                setStatus(output.toString())
            }
        }
    }

    private fun runDemo(title: String, block: suspend () -> String) {
        setStatus("Running $title...")
        hostScope.launch {
            val result = runCatching {
                withTimeoutOrNull(DEMO_ACTION_TIMEOUT_MS) { block() }
                    ?: "Timed out after ${DEMO_ACTION_TIMEOUT_MS / 1_000}s; external service or model input may be missing."
            }
                .getOrElse { error -> "Failed: ${error.message ?: error::class.java.simpleName}" }
            setStatus("[$title]\n$result")
        }
    }

    private fun runSdkSmoke() {
        val sdk = createEngine()
        if (!sdk.background.checkNotificationPermission(this)) {
            runSmokeAfterNotificationPermission = true
            sdk.background.requestNotificationPermission(this)
            setStatus("Notification permission requested")
            return
        }
        hostScope.launch {
            val result = runCatching {
                sdk.updateCustomTools(
                    listOf(
                        CustomToolDef(
                            name = "android_integration_ping",
                            description = "Return an Android integration ping result.",
                        ),
                    ),
                )
                sdk.initFileBridge()
                NapaxiFileBridge.init(sdk)
                val platformTools = sdk.tools.platformToolDescriptors()
                val providers = sdk.agentProviderInstall.discoverProviders()
                val packages = sdk.agentApp.listPackages()
                val workspaceSize = sdk.workspaceSize()
                val apkResult = sdk.apkInstaller.installResult("")
                sdk.background.startService()
                delay(500)
                val backgroundRunning = sdk.background.controller?.isRunning == true
                val notificationAllowed = sdk.background.checkNotificationPermission(this@MainActivity)
                sdk.background.showCompletionNotification(
                    title = "Napaxi Android Integration Smoke",
                    message = "Android SDK background smoke completed",
                )
                val session = sdk.createSession(agentId = NapaxiEngine.DEFAULT_AGENT_ID)
                sdk.sendToSession(
                    session = session,
                    message = "Say hello from the Android integration check app.",
                    agentId = NapaxiEngine.DEFAULT_AGENT_ID,
                    listener = object : ChatEventListener {
                        override fun onEvent(event: ChatEvent) = Unit
                    },
                )
                "tools=${platformTools.size}, providers=${providers.size}, packages=${packages.size}, " +
                    "installed=${lastInstalledProviderName ?: "none"}, action=$lastProviderActionStatus, " +
                    "background=$backgroundRunning, notifications=$notificationAllowed, " +
                    "workspaceSize=$workspaceSize, apkCode=${apkResult.code}"
            }
            setStatus(result.getOrElse { "Smoke failed: ${it.message}" })
        }
    }

    private fun maybeRunRequestedSmoke(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_RUN_SMOKE, false) == true) {
            if (intent.getBooleanExtra(EXTRA_INSTALL_FIRST_PROVIDER, false)) {
                installFirstProvider(runSmokeAfterInstall = true)
            } else {
                runSdkSmoke()
            }
        }
    }

    private fun installFirstProvider(runSmokeAfterInstall: Boolean = false) {
        val sdk = createEngine()
        val provider = sdk.agentProviderInstall.discoverProviders().firstOrNull()
        if (provider == null) {
            setStatus(
                if (runSmokeAfterInstall) {
                    "Smoke failed: no provider app found"
                } else {
                    "No provider app found"
                },
            )
            return
        }
        val request = sdk.agentProviderInstall.buildInstallRequest()
        val requestCode = AgentProviderHostApi.REQUEST_INSTALL_AGENT
        runSmokeAfterProviderInstall = runSmokeAfterInstall
        sdk.agentProviderInstall.requestInstall(this, provider, request, requestCode)
        pendingProviderInstall = PendingAgentProviderInstall(provider, request, requestCode)
        setStatus("Install requested for ${provider.displayName}")
    }

    private fun runProviderActionSmoke(packageDef: AgentAppPackage) {
        val sdk = createEngine()
        val action = packageDef.actions.firstOrNull { it.actionId == "desk.status.get" }
            ?: packageDef.actions.firstOrNull()
        if (action == null) {
            runSmokeAfterProviderAction = false
            lastProviderActionStatus = "missing_action"
            setStatus("Smoke failed: installed provider has no actions")
            return
        }

        val requestId = UUID.randomUUID().toString()
        val now = Instant.now()
        val proposal = AgentAppActionProposal(
            JSONObject()
                .put("request_id", requestId)
                .put("provider_id", packageDef.providerId)
                .put("agent_id", packageDef.agentId)
                .put("action_id", action.actionId)
                .put("tool_name", action.toolName)
                .put("arguments", JSONObject())
                .put("user_intent_summary", "Android integration smoke action")
                .put("created_at", now.toString())
                .put("expires_at", now.plusSeconds(action.timeoutSeconds.toLong()).toString())
                .put("nonce", UUID.randomUUID().toString())
                .put("idempotency_key", requestId)
                .put("callback", JSONObject().put("type", "android_integration_smoke"))
                .put("risk", action.risk)
                .put("confirmation_policy", action.confirmationPolicy)
                .put("host_instance_id", packageDef.installBinding?.hostInstanceId ?: "")
                .put("signature_algorithm", "")
                .toString(),
        )
        val intent = runCatching {
            sdk.agentProviders.buildTrustedActionIntent(packageDef, proposal)
                .putExtra(EXTRA_PROVIDER_AUTO_EXECUTE, true)
        }.getOrElse { error ->
            runSmokeAfterProviderAction = false
            lastProviderActionStatus = "handoff_failed"
            setStatus("Smoke failed: ${error.message}")
            return
        }

        pendingProviderActionRequestId = requestId
        runSmokeAfterProviderAction = true
        lastProviderActionStatus = "started"
        startActivityForResult(intent, AgentProviderHostApi.REQUEST_HANDLE_PROPOSAL)
    }

    private fun handleProviderActionResult(resultCode: Int, data: Intent?) {
        val expectedRequestId = pendingProviderActionRequestId
        pendingProviderActionRequestId = null
        val shouldContinueSmoke = runSmokeAfterProviderAction
        runSmokeAfterProviderAction = false
        val result = engine?.agentProviders?.parseActionResult(data)
        lastProviderActionStatus = when {
            resultCode != RESULT_OK -> "canceled"
            result == null -> "missing_result"
            expectedRequestId != null && result.requestId != expectedRequestId -> "request_mismatch"
            else -> result.status
        }
        if (shouldContinueSmoke && lastProviderActionStatus == "succeeded") {
            runSdkSmoke()
        } else if (shouldContinueSmoke) {
            setStatus("Smoke failed: provider action $lastProviderActionStatus")
        } else {
            setStatus("Provider action result: $lastProviderActionStatus")
        }
    }

    private fun button(label: String, onClick: () -> Unit): Button =
        Button(this).apply {
            text = label
            setAllCaps(false)
            minHeight = 48
            setOnClickListener { onClick() }
        }

    private fun label(text: String, size: Float = 14f, bold: Boolean = false): TextView =
        TextView(this).apply {
            this.text = text
            textSize = size
            setTextColor(Color.rgb(28, 32, 36))
            if (bold) typeface = Typeface.DEFAULT_BOLD
            setPadding(4, if (bold) 16 else 4, 4, 8)
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            )
        }

    private fun setStatus(message: String) {
        runOnUiThread {
            statusView.text = message
            statusView.visibility = View.VISIBLE
        }
    }

    private companion object {
        const val EXTRA_RUN_SMOKE = "run_smoke"
        const val EXTRA_INSTALL_FIRST_PROVIDER = "install_first_provider"
        const val EXTRA_PROVIDER_AUTO_EXECUTE = "napaxi_auto_execute"
        const val DEMO_ACTION_TIMEOUT_MS = 15_000L
    }
}
