# Napaxi Android SDK

Native Android Kotlin adapter for the Napaxi runtime.

This package is intentionally separate from `packages/agent_provider/android`:

- `packages/android` embeds the Napaxi Agent runtime in a native Android app.
- `packages/agent_provider/android` implements provider-side install/action/trigger protocol helpers.

The Kotlin API loads `libnapaxi_api_bridge.so`, builds Android platform context, calls the shared `packages/api_bridge` JNI surface, and routes custom tool requests back to app code through `McToolExecutor`.

## Configure And Create

Apps can pass `LlmConfig` directly or persist Flutter-compatible profiles with
`NapaxiConfigStore`.
`LlmConfig.userTimezone` accepts an optional IANA timezone such as
`Asia/Shanghai` for user-local date intent in prompts. Runtime storage, wire
values, and timestamps remain UTC/epoch based; the SDK does not infer this
field automatically for host apps.

```kotlin
val configStore = NapaxiConfigStore.sharedPreferences(context)
configStore.saveProfile(
    NapaxiConfigProfile(
        id = "openai",
        name = "OpenAI",
        provider = "openai",
        model = "gpt-4.1",
        userTimezone = "Asia/Shanghai",
        systemPrompt = "You are a smart home agent.",
    ),
    apiKey = apiKey,
)
configStore.saveSelection(NapaxiConfigSelection(selectedProfileId = "openai"))

val config = checkNotNull(configStore.resolveSelectedConfig())
```

Create the engine from an Android `Activity` when the app wants built-in Agent
Provider action handoff support. Passing an `Activity` lets the SDK install the
default `AndroidAgentProviderActionExecutor`; non-Activity contexts should pass
a custom `AgentAppActionExecutor` when provider actions are needed.

```kotlin
val engine = NapaxiEngine.create(
    context = activity,
    config = config,
    toolExecutor = McToolExecutor { toolName, paramsJson, callback ->
        if (toolName == "home_light_set") {
            callback.success("""{"ok":true}""")
        } else {
            callback.error("Unknown tool: $toolName")
        }
    },
    backgroundConfig = BackgroundConfig(enabled = true),
)
```

## Chat And Tools

Register app-owned tools through the engine, then stream typed chat events.

```kotlin
engine.updateCustomTools(
    listOf(
        CustomToolDef(
            name = "home_light_set",
            description = "Control a virtual light.",
        ),
    ),
)

val session = engine.createSession(agentId = "home")
engine.sendToSession(session, "Turn on the living room lamp", agentId = "home", listener = object : ChatEventListener {
    override fun onEvent(event: ChatEvent) {
        // Render events or collect the final response.
    }
})
```

The main public facades are available from the engine:

- `chat`, `sessions`, `sessionRuns`, `agents`, `workspace`, `skills`,
  `evolution`, `groups`, `tools`, `capabilities`, `mcp`
- `background`, `automation`, `agentApp`, `agentProviders`,
  `agentProviderInstall`, `agentProviderTrigger`, `fileBridge`, `apkInstaller`

Most Flutter-style convenience methods are also available directly on
`NapaxiEngine`, including session lifecycle, workspace, skills, automation, file
bridge, APK install, background service, and Agent Provider helpers.

## Sessions And Context

Use `sessions` or the matching engine convenience methods for lifecycle,
history, human approval, injected messages, and context compaction.

```kotlin
val session = engine.createSession(agentId = "home")
val messages = engine.getHistory(session.threadId, agentId = "home")
val page = engine.getHistoryPage(session.threadId, agentId = "home", limit = 80)
val status = engine.contextStatus(session.threadId, agentId = "home")

engine.injectMessage(session, "Host note: user is at home", agentId = "home")
engine.saveAttachmentMetadata(
    threadId = session.threadId,
    userMsgIndex = 0,
    attachments = listOf(
        ChatAttachment.create(
            kind = "document",
            mimeType = "application/pdf",
            filename = "report.pdf",
            sandboxPath = "/workspace/report.pdf",
        ),
    ),
)
engine.answerHumanRequest(requestId, "approved")
engine.compactContext(session, agentId = "home", focus = "Keep device state")
engine.clearSession(session, agentId = "home")
```

## Background Permissions

Android background execution requires notification permission on Android 13+.
Check it before starting long-running agent work.

```kotlin
if (!engine.background.canRunInBackground(activity)) {
    engine.background.requestNotificationPermission(activity)
}

engine.background.startService()
engine.background.controller?.showCompletionNotification(message = "Ready")
```

## Automation And Files

Automation jobs mirror the Flutter adapter surface and can be reached through
`engine.automation` or top-level `NapaxiEngine` methods.

```kotlin
val job = engine.createAutomationJob(
    AutomationJob.create(
        name = "Morning check",
        accountId = NapaxiEngine.DEFAULT_ACCOUNT_ID,
        agentId = "home",
        trigger = AutomationTrigger("""{"kind":"interval","every_ms":86400000}"""),
        payload = AutomationPayload("""{"kind":"prompt","text":"Check the house status"}"""),
    ),
)
engine.runAutomationJob(job.id)
```

The file bridge maps Napaxi sandbox paths to app files and exposes Android-safe
file opening through the SDK `FileProvider`.

```kotlin
engine.initFileBridge()
val realPath = engine.sandboxToReal("/workspace/report.pdf")
val files = engine.listFiles(subdir = "reports", recursive = true)
val sizeBytes = engine.workspaceSize()
if (realPath != null) {
    engine.openLocalFile(realPath, mimeType = "application/pdf")
}

// Flutter-style standalone advanced entry point.
NapaxiFileBridge.init(engine)
NapaxiFileBridge.openLocalFileResult(
    context,
    realPath ?: "/sdcard/Download/report.pdf",
    mimeType = "application/pdf",
)
```

APK installation helpers match the Flutter `NapaxiApkInstaller` behavior:

```kotlin
val result = engine.installApkResult("/sdcard/Download/plugin.apk")
if (result.permissionRequired) {
    // Prompt the user to allow installs from this app, then retry.
}

val standaloneResult = NapaxiApkInstaller.installApk(
    context,
    "/sdcard/Download/plugin.apk",
)
```

## MCP Servers

`engine.mcp` mirrors the Flutter adapter and accepts typed headers and OAuth
configuration instead of requiring callers to hand-build JSON.

```kotlin
val added = engine.mcp.addServer(
    name = "github",
    url = "https://example.test/mcp",
    headers = mapOf("Authorization" to "Bearer $token"),
)

val oauth = engine.mcp.startOAuth(
    name = "github",
    clientId = "client-id",
    authorizationUrl = "https://example.test/oauth/authorize",
    tokenUrl = "https://example.test/oauth/token",
    scopes = listOf("repo", "read:user"),
    usePkce = true,
)

val tools = engine.mcp.listTools(serverName = added.name)
```

## Platform Tools And Browser Tools

Enable platform tools at engine creation to expose Android capabilities such as
URL open, clipboard, notifications, device info, camera, location, contacts,
calendar, alarm, audio, phone, and APK install through the core tool registry.
Unlike Flutter, native Android hosts must provide an
`AndroidPlatformMediaToolHandler` for `take_photo`, `media_library`, and
`record_audio`. Without a handler, the SDK advertises the platform tool wildcard but disables those
media capabilities in the host capability selection so the core can avoid
calling unsupported native UI flows.

```kotlin
val engine = NapaxiEngine.create(
    context = activity,
    config = config,
    enablePlatformTools = true,
    platformMediaToolHandler = object : AndroidPlatformMediaToolHandler {
        override fun takePhoto(
            request: AndroidPlatformMediaToolRequest,
            callback: McToolCallback,
        ) {
            // Launch the host camera flow, save into request.context.ensureAttachmentDir("camera"),
            // then return request.context.attachmentResultJson(...).
        }

        override fun recordAudio(
            request: AndroidPlatformMediaToolRequest,
            callback: McToolCallback,
        ) {
            // Record audio for request.durationSeconds and return an attachment result.
        }
    },
    browserController = myBrowserController,
)

val platformTools = engine.tools.platformToolDescriptors()
val browserTools = engine.tools.browserToolDescriptors()
```

Media tool handlers should return the same attachment result shape as Flutter:
`sandbox_path`, `file_path`, `kind`, `filename`, `mime_type`, and `size_bytes`.
Use `request.context.attachmentResultJson(...)` to keep that shape stable.

## Agent Providers

Provider install starts from provider discovery and an Activity result. Keep
the returned `PendingAgentProviderInstall`, then hand the Activity result back
to the SDK so it can validate the install envelope, attach the Android install
binding, and register the `AgentAppPackage`.

Forward activity results to `engine.onActivityResult(...)` first so the default
provider action executor can receive action results. If it returns `false`, try
the pending install result.

```kotlin
private var pendingProviderInstall: PendingAgentProviderInstall? = null

fun installFirstProvider(activity: Activity) {
    val provider = engine.agentProviderInstall.discoverProviders().firstOrNull() ?: return
    val request = engine.agentProviderInstall.buildInstallRequest()
    val requestCode = AgentProviderHostApi.REQUEST_INSTALL_AGENT
    engine.agentProviderInstall.requestInstall(activity, provider, request, requestCode)
    pendingProviderInstall = PendingAgentProviderInstall(provider, request, requestCode)
}

override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
    if (engine.onActivityResult(requestCode, resultCode, data)) return
    val pending = pendingProviderInstall
    if (pending == null || requestCode != pending.requestCode) {
        super.onActivityResult(requestCode, resultCode, data)
        return
    }
    lifecycleScope.launch {
        runCatching {
            engine.onAgentProviderInstallActivityResult(
                requestCode,
                resultCode,
                data,
                pending,
            )
        }.onSuccess { installed ->
            if (installed != null) pendingProviderInstall = null
        }.onFailure { error ->
            // Surface the install error to the host UI.
        }
    }
}
```

For provider-initiated installs, use `installFromLaunchIntent(...)`; it returns
the same pending install handle for the later Activity result.

```kotlin
pendingProviderInstall = engine.agentProviderInstall.installFromLaunchIntent(activity)
```

Background provider triggers are delivered through `AgentTriggerIngressService`
and can be consumed on app launch or resume:

```kotlin
val trigger = engine.agentProviderTrigger.consumePendingTrigger(intent)
if (trigger != null) {
    lifecycleScope.launch {
        engine.agentProviderTrigger.acceptTrigger(trigger)
        engine.agentProviderTrigger.clearPendingAgentTriggerRequest(activity)
    }
}
```

## Build And Verify

Build with Gradle from this package:

```sh
gradle assembleDebug
```

Run Android unit tests from this package:

```sh
gradle testDebugUnitTest
```

If the native bridge library is missing or stale, run the repository Android native build first:

```sh
./tools/scripts/build.sh fast android
```
