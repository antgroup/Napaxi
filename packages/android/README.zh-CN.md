# Napaxi Android SDK

`packages/android` 是 Napaxi runtime 的 native Android Kotlin adapter。它与 `packages/agent_provider/android` 分工不同：

- `packages/android`：把 Napaxi Agent runtime 嵌入 native Android app。
- `packages/agent_provider/android`：实现 provider-side install/action/trigger protocol helpers。

Android SDK 会加载 `libnapaxi_api_bridge.so`，构造 Android platform context，调用共享 JNI bridge，并通过 `McToolExecutor` 把 custom tool 请求交回 app code。

## 配置与创建 Engine

应用可以直接传 `LlmConfig`，也可以通过 `NapaxiConfigStore` 持久化 Flutter-compatible profiles。

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

需要内置 Agent Provider action handoff 时，建议从 Android `Activity` 创建 engine。非 Activity context 需要 provider actions 时，应传自定义 `AgentAppActionExecutor`。

```kotlin
val engine = NapaxiEngine.create(
    context = activity,
    config = config,
    toolExecutor = McToolExecutor { toolName, paramsJson, callback ->
        callback.success("""{"ok":true}""")
    },
    backgroundConfig = BackgroundConfig(enabled = true),
)
```

## Chat 与 tools

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

主要 facade：

- `chat`、`sessions`、`agents`、`workspace`、`skills`、`groups`
- `tools`、`capabilities`、`mcp`
- `background`、`automation`、`agentApp`、`agentProviders`
- `fileBridge`、`apkInstaller`

## 后台权限

Android 13+ 后台执行需要 notification permission：

```kotlin
if (!engine.background.canRunInBackground(activity)) {
    engine.background.requestNotificationPermission(activity)
}

engine.background.startService()
```

## 文件与 APK

File bridge 将 Napaxi sandbox path 映射到 app files，并通过 SDK `FileProvider` 安全打开本地文件。

APK installation helper 与 Flutter `NapaxiApkInstaller` 行为保持一致；如果缺少安装未知来源权限，应引导用户授权后重试。

## 验证

```sh
gradle testDebugUnitTest
./tools/scripts/build.sh check-android-parity
./tools/scripts/build.sh check-android-integration
./tools/scripts/build.sh check-android-integration-device
```

SDK-facing 变更请参考 [`../../docs/sdk-adapter-parity.zh-CN.md`](../../docs/sdk-adapter-parity.zh-CN.md)。
