package demo.smarthome.provider

import android.content.Context
import com.napaxi.android.ChatEvent
import com.napaxi.android.CustomToolDef
import com.napaxi.android.LlmConfig
import com.napaxi.android.McToolCallback
import com.napaxi.android.McToolExecutor
import com.napaxi.android.NapaxiEngine
import com.napaxi.android.SessionKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject

enum class HomeAgentOutcomeType {
    LOCAL_ACTION,
    SUGGESTION,
    CLARIFICATION,
    COLLABORATION_OFFER,
    STATUS,
}

data class HomeAgentCommand(
    val actionId: String,
    val argumentsJson: String,
    val label: String,
)

data class HomeAgentResponse(
    val type: HomeAgentOutcomeType,
    val message: String,
    val state: VirtualHomeState,
    val proposedAction: HomeAgentCommand? = null,
    val napaxiMessage: String = "",
    val eventType: String = "home_agent_message",
    val payloadJson: String = "{}",
)

data class HomeAgentSdkConfig(
    val provider: String,
    val apiKey: String,
    val model: String,
    val baseUrl: String,
) {
    val isReady: Boolean
        get() = provider.isNotBlank() && apiKey.isNotBlank() && model.isNotBlank()
}

object SmartHomeAgentRuntime {
    private const val PREFS = "smart_home_home_agent"
    private const val KEY_PROVIDER = "provider"
    private const val KEY_API_KEY = "api_key"
    private const val KEY_MODEL = "model"
    private const val KEY_BASE_URL = "base_url"
    private const val LOCAL_AGENT_ID = "demo.smart_home.local_agent"
    private const val TOOL_HOME_LIGHT_SET = "home_light_set"
    private const val TOOL_HOME_LIGHTS_SET_ALL = "home_lights_set_all"
    private const val TOOL_HOME_LIGHT_MATRIX_DRAW = "home_light_matrix_draw_20x5"
    private const val TOOL_REQUEST_COLLABORATION = "request_napaxi_collaboration"

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    @Volatile
    private var engine: NapaxiEngine? = null
    @Volatile
    private var engineConfigKey: String = ""
    @Volatile
    private var session: SessionKey? = null

    /**
     * Set by the local agent's [TOOL_REQUEST_COLLABORATION] tool when the model
     * decides a request is beyond local light control. Consumed by
     * [collectResponse] to produce a [HomeAgentOutcomeType.COLLABORATION_OFFER]
     * — this replaces the old keyword pre-routing, so the model itself decides
     * when to hand off to an external Napaxi Agent.
     */
    private val pendingCollaboration = AtomicReference<CollaborationRequest?>(null)

    private data class CollaborationRequest(val reason: String, val contextSummary: String)

    fun loadSdkConfig(context: Context): HomeAgentSdkConfig {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return HomeAgentSdkConfig(
            provider = prefs.getString(KEY_PROVIDER, "openai_compatible").orEmpty(),
            apiKey = prefs.getString(KEY_API_KEY, "").orEmpty(),
            model = prefs.getString(KEY_MODEL, "").orEmpty(),
            baseUrl = prefs.getString(KEY_BASE_URL, "").orEmpty(),
        )
    }

    fun saveSdkConfig(context: Context, config: HomeAgentSdkConfig) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PROVIDER, config.provider.trim())
            .putString(KEY_API_KEY, config.apiKey.trim())
            .putString(KEY_MODEL, config.model.trim())
            .putString(KEY_BASE_URL, config.baseUrl.trim())
            .apply()
        resetEngine()
    }

    fun isSdkConfigured(context: Context): Boolean =
        loadSdkConfig(context).isReady

    fun sdkSummary(context: Context): String {
        val config = loadSdkConfig(context)
        return if (config.isReady) {
            "${config.provider} · ${config.model}"
        } else {
            "未配置模型"
        }
    }

    fun handleUserMessage(
        context: Context,
        rawMessage: String,
        onResult: (HomeAgentResponse) -> Unit,
    ) {
        val appContext = context.applicationContext
        val message = rawMessage.trim()
        if (message.isEmpty()) {
            onResult(emptyMessageResponse(appContext))
            return
        }

        VirtualHomeStore.recordAgentNote(appContext, "家居助手", "用户：$message")

        val sdkConfig = loadSdkConfig(appContext)
        if (!sdkConfig.isReady) {
            val state = VirtualHomeStore.recordAgentNote(
                appContext,
                "家居助手",
                "还没有配置本地 Napaxi SDK 模型。",
            )
            onResult(
                response(
                    type = HomeAgentOutcomeType.CLARIFICATION,
                    message = "请先配置模型，然后我会通过本地 Napaxi SDK 理解并调用灯光工具。",
                    state = state,
                ),
            )
            return
        }

        // Every message goes through the local Napaxi engine. Whether the request
        // stays local or is handed off to an external Napaxi Agent is decided by
        // the model via the request_napaxi_collaboration tool, not by keywords.
        scope.launch {
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val localEngine = ensureEngine(appContext, sdkConfig)
                    val localSession = session ?: localEngine.createSession(
                        agentId = LOCAL_AGENT_ID,
                        channelType = "smart_home",
                        accountId = "local",
                    ).also { session = it }
                    collectResponse(appContext, localEngine, localSession, message)
                }.getOrElse { error ->
                    val state = VirtualHomeStore.recordAgentNote(
                        appContext,
                        "家居助手",
                        "Napaxi SDK 请求失败：${error.message ?: error::class.java.simpleName}",
                    )
                    response(
                        type = HomeAgentOutcomeType.CLARIFICATION,
                        message = "本地 Napaxi SDK 请求失败：${error.message ?: "未知错误"}",
                        state = state,
                    )
                }
            }
            onResult(result)
        }
    }

    fun emptyMessageResponse(context: Context): HomeAgentResponse {
        val state = VirtualHomeStore.recordAgentNote(
            context,
            "家居助手",
            "等待一句家居请求，例如“打开客厅落地灯”。",
        )
        return response(
            type = HomeAgentOutcomeType.CLARIFICATION,
            message = "可以说“打开客厅落地灯”。配置模型后，这句话会进入本地 Napaxi SDK。",
            state = state,
        )
    }

    fun handlePresenceDetected(context: Context): HomeAgentResponse {
        val args = JSONObject()
            .put("room", "living_room")
            .put("device", "floor_lamp")
            .put("on", true)
            .put("brightness", 60)
        val state = VirtualHomeStore.recordAgentNote(
            context,
            "家居助手",
            "门口有人，建议打开客厅落地灯到 60%。",
        )
        return response(
            type = HomeAgentOutcomeType.SUGGESTION,
            message = "检测到门口有人。建议打开客厅落地灯到 60%，你可以直接执行，也可以请求 Napaxi 协作判断。",
            state = state,
            proposedAction = HomeAgentCommand(
                actionId = SmartHomePackage.ACTION_LIGHT_SET,
                argumentsJson = args.toString(),
                label = "打开客厅落地灯 60%",
            ),
            napaxiMessage = "门口检测到有人。家居助手建议打开客厅落地灯到 60%，请协作判断是否合适。",
            eventType = "presence_detected",
        )
    }

    fun executeProposedAction(
        context: Context,
        response: HomeAgentResponse,
    ): HomeAgentResponse {
        val command = response.proposedAction
            ?: return response(
                type = HomeAgentOutcomeType.CLARIFICATION,
                message = "当前没有可执行的本地建议。",
                state = VirtualHomeStore.load(context),
            )
        val next = SmartHomeActionRunner.applyAction(
            context,
            command.actionId,
            command.argumentsJson,
            source = "home_agent",
        )
        return response(
            type = HomeAgentOutcomeType.LOCAL_ACTION,
            message = "已执行：${command.label}。",
            state = next,
        )
    }

    fun recordNapaxiProposal(
        context: Context,
        actionId: String,
        argumentsJson: String,
    ): VirtualHomeState =
        VirtualHomeStore.recordAgentNote(
            context,
            "Napaxi Agent",
            "请求家居助手执行：$actionId $argumentsJson",
        )

    fun recordNapaxiResult(context: Context, status: String): VirtualHomeState =
        VirtualHomeStore.recordAgentNote(
            context,
            "家居助手",
            "已向 Napaxi Agent 返回执行结果：$status",
        )

    @Synchronized
    private fun ensureEngine(context: Context, sdkConfig: HomeAgentSdkConfig): NapaxiEngine {
        // NOTE: the demo keys the cache on a redacted fingerprint, not the raw
        // API key, and stores credentials in plain SharedPreferences for brevity.
        // A production integration should use EncryptedSharedPreferences / Keystore.
        val key = "${sdkConfig.provider}|${sdkConfig.baseUrl}|${sdkConfig.model}|${sdkConfig.apiKey.hashCode()}"
        engine?.takeIf { engineConfigKey == key }?.let { return it }
        resetEngine()

        val config = LlmConfig(
            provider = sdkConfig.provider,
            apiKey = sdkConfig.apiKey,
            baseUrl = sdkConfig.baseUrl.ifBlank { null },
            model = sdkConfig.model,
            systemPrompt = localSystemPrompt(),
            maxToolIterations = 8,
        )
        val created = NapaxiEngine.create(
            context = context,
            config = config,
            toolExecutor = homeToolExecutor(context),
            enablePlatformTools = false,
        )
        created.ensureAgent(LOCAL_AGENT_ID)
        created.startToolRequestListener()
        val toolsUpdated = created.updateCustomTools(
            listOf(
                homeLightToolDef(),
                homeAllLightsToolDef(),
                homeMatrixDrawToolDef(),
                collaborationToolDef(),
            ),
        )
        if (!toolsUpdated) {
            created.dispose()
            error("Napaxi SDK custom tool registration failed")
        }
        engine = created
        engineConfigKey = key
        return created
    }

    @Synchronized
    private fun resetEngine() {
        runCatching { engine?.dispose() }
        engine = null
        engineConfigKey = ""
        session = null
    }

    /**
     * Collects the SDK event flow into a single [HomeAgentResponse]. The outcome
     * type is driven by what actually happened during the turn:
     * an error, a collaboration hand-off, a real tool result, or plain text.
     */
    private suspend fun collectResponse(
        context: Context,
        engine: NapaxiEngine,
        session: SessionKey,
        message: String,
    ): HomeAgentResponse {
        pendingCollaboration.set(null)
        val deltas = StringBuilder()
        var finalResponse = ""
        var lastError: String? = null
        var toolActed = false

        engine.sendToSessionFlow(
            session = session,
            message = homeContextMessage(context, message),
            agentId = LOCAL_AGENT_ID,
            maxIterations = 8,
        ).collect { event ->
            when (event) {
                is ChatEvent.ResponseDeltaEvent -> deltas.append(event.content)
                is ChatEvent.ResponseEvent -> finalResponse = event.content
                is ChatEvent.ToolResultEvent -> {
                    if (event.name != TOOL_REQUEST_COLLABORATION && !event.isError) {
                        toolActed = true
                    }
                    VirtualHomeStore.recordAgentNote(
                        context,
                        "家居助手",
                        "Napaxi SDK 已返回工具结果：${event.name}",
                    )
                }
                is ChatEvent.ErrorEvent -> lastError = event.message
                else -> Unit
            }
        }

        val finalText = finalResponse.ifBlank { deltas.toString() }.trim()
        val collaboration = pendingCollaboration.getAndSet(null)
        val state = VirtualHomeStore.load(context)
        return when {
            lastError != null -> response(
                type = HomeAgentOutcomeType.CLARIFICATION,
                message = "本地 Napaxi SDK 返回错误：$lastError",
                state = state,
            )
            collaboration != null -> collaborationResponse(context, finalText, collaboration)
            toolActed -> response(
                type = HomeAgentOutcomeType.LOCAL_ACTION,
                message = finalText.ifBlank { "已完成本地灯光操作。" },
                state = state,
            )
            else -> response(
                type = HomeAgentOutcomeType.STATUS,
                message = finalText.ifBlank { "本地 Napaxi SDK 已完成处理。" },
                state = state,
            )
        }
    }

    private fun collaborationResponse(
        context: Context,
        finalText: String,
        collaboration: CollaborationRequest,
    ): HomeAgentResponse {
        val reason = collaboration.reason.ifBlank { "需要进一步判断" }
        val state = VirtualHomeStore.recordAgentNote(
            context,
            "家居助手",
            "本地 Agent 请求与 Napaxi 协作：$reason",
        )
        val napaxiMessage = buildString {
            append("家居助手请求 Napaxi Agent 协作。")
            if (collaboration.reason.isNotBlank()) append("\n原因：").append(collaboration.reason)
            if (collaboration.contextSummary.isNotBlank()) {
                append("\n上下文：").append(collaboration.contextSummary)
            }
            append("\n当前家居状态：").append(state.toResultJson())
        }
        return response(
            type = HomeAgentOutcomeType.COLLABORATION_OFFER,
            message = finalText.ifBlank {
                "这个需求超出本地灯光能力，我可以把它交给 Napaxi Agent 一起判断。"
            },
            state = state,
            napaxiMessage = napaxiMessage,
            eventType = "home_agent_collaboration",
        )
    }

    private fun homeToolExecutor(context: Context): McToolExecutor =
        McToolExecutor { toolName: String, paramsJson: String, callback: McToolCallback ->
            runCatching {
                when (toolName) {
                    TOOL_HOME_LIGHT_SET -> applySingleLight(context, paramsJson).toResultJson()
                    TOOL_HOME_LIGHTS_SET_ALL -> applyAllLights(context, paramsJson).toResultJson()
                    TOOL_HOME_LIGHT_MATRIX_DRAW -> drawMatrix(context, paramsJson).toResultJson()
                    TOOL_REQUEST_COLLABORATION -> requestCollaboration(paramsJson)
                    else -> error("Unsupported smart home tool: $toolName")
                }
            }.fold(
                onSuccess = { resultJson -> callback.success(resultJson) },
                onFailure = { error ->
                    callback.error(error.message ?: error::class.java.simpleName)
                },
            )
        }

    private fun requestCollaboration(paramsJson: String): String {
        val args = runCatching { JSONObject(paramsJson) }.getOrElse { JSONObject() }
        pendingCollaboration.set(
            CollaborationRequest(
                reason = args.optString("reason"),
                contextSummary = args.optString("context_summary"),
            ),
        )
        return JSONObject()
            .put("status", "collaboration_requested")
            .put("note", "The Smart Home app will offer to hand this off to an external Napaxi Agent.")
            .toString()
    }

    private fun applySingleLight(context: Context, paramsJson: String): VirtualHomeState =
        SmartHomeActionRunner.applyAction(
            context,
            SmartHomePackage.ACTION_LIGHT_SET,
            validatedLightParameters(paramsJson),
            source = "home_agent",
        )

    private fun applyAllLights(context: Context, paramsJson: String): VirtualHomeState {
        val args = runCatching { JSONObject(paramsJson) }.getOrElse { JSONObject() }
        val on = if (args.has("on")) args.optBoolean("on") else true
        val brightness = if (args.has("brightness")) {
            args.optInt("brightness").coerceIn(0, 100)
        } else if (on) {
            75
        } else {
            0
        }
        var state = VirtualHomeStore.load(context)
        LightCatalog.lights.forEach { light ->
            val lightArgs = JSONObject()
                .put("room", light.room)
                .put("device", light.device)
                .put("on", on)
                .put("brightness", brightness)
            state = SmartHomeActionRunner.applyAction(
                context,
                SmartHomePackage.ACTION_LIGHT_SET,
                lightArgs.toString(),
                source = "home_agent",
            )
        }
        return state
    }

    private fun drawMatrix(context: Context, paramsJson: String): VirtualHomeState {
        val args = JSONObject(paramsJson)
        val pixels = args.optJSONArray("pixels")
            ?: error("pixels is required")
        val colors = mutableListOf<Int>()
        for (index in 0 until pixels.length()) {
            colors += parseColor(pixels.getString(index))
        }
        YeelightLanClient.drawMatrix100(context, colors)
        return VirtualHomeStore.recordAgentNote(
            context,
            "Yeelight Cube",
            "已发送 20 x 5 点阵图案。",
        )
    }

    private fun validatedLightParameters(rawJson: String): String {
        val args = runCatching { JSONObject(rawJson) }.getOrElse { JSONObject() }
        val room = args.optString("room")
        val device = args.optString("device")
        if (!LightCatalog.isSupported(room, device)) {
            error("Unsupported light: $room/$device")
        }
        return args.toString()
    }

    private fun homeLightToolDef(): CustomToolDef =
        CustomToolDef(
            name = TOOL_HOME_LIGHT_SET,
            description = "Control one supported virtual light in the Smart Home app. " +
                "Supported pairs: ${LightCatalog.pairsJoined()}.",
            parameters = JSONObject(LightCatalog.lightParamsSchemaJson()),
            effect = "write",
        )

    private fun homeAllLightsToolDef(): CustomToolDef =
        CustomToolDef(
            name = TOOL_HOME_LIGHTS_SET_ALL,
            description = "Control every supported virtual light in the Smart Home app at once: " +
                "${LightCatalog.labelsJoined()}. Use this when the user says all lights, every light, 全部灯, or 所有灯.",
            parameters = JSONObject(LightCatalog.allLightsParamsSchemaJson()),
            effect = "write",
        )

    private fun homeMatrixDrawToolDef(): CustomToolDef =
        CustomToolDef(
            name = TOOL_HOME_LIGHT_MATRIX_DRAW,
            description = "Draw a 20 x 5 RGB pixel matrix on the bound Yeelight Cube light. " +
                "Provide exactly ${LightCatalog.MATRIX_PIXEL_COUNT} #RRGGBB values. " +
                "Pixel order starts at the bottom-left, goes left-to-right for 20 pixels, then moves upward row by row.",
            parameters = JSONObject(LightCatalog.matrixParamsSchemaJson()),
            effect = "write",
        )

    private fun collaborationToolDef(): CustomToolDef =
        CustomToolDef(
            name = TOOL_REQUEST_COLLABORATION,
            description = "Hand the current request off to an external Napaxi Agent when it is beyond " +
                "local light control — for example cross-device automation, devices this app does not expose " +
                "(air conditioner, curtains, speakers, appliances, fridge), or judgement that needs a broader agent. " +
                "Do NOT call this for requests you can satisfy with the light tools.",
            parameters = JSONObject(
                """
                {
                  "type":"object",
                  "properties":{
                    "reason":{"type":"string","description":"Why this needs an external Napaxi Agent."},
                    "context_summary":{"type":"string","description":"Short summary of the user request and relevant home state."}
                  },
                  "required":["reason"]
                }
                """.trimIndent(),
            ),
            effect = "read",
        )

    private fun localSystemPrompt(): String =
        """
        You are the local HomeAgent embedded in the Smart Home Android app.
        The app UI is a smart-home dashboard, not a chat-first app.
        You have permission to call these Smart Home app tools:
        - $TOOL_HOME_LIGHT_SET: control exactly one supported light.
        - $TOOL_HOME_LIGHTS_SET_ALL: control all supported lights at once.
        - $TOOL_HOME_LIGHT_MATRIX_DRAW: draw a 20 x 5 RGB pixel pattern on the bound Yeelight Cube light.
        - $TOOL_REQUEST_COLLABORATION: hand off to an external Napaxi Agent.
        Supported lights:
        ${LightCatalog.promptLines()}
        When the user asks to turn on/off all lights, every light, 全部灯, or 所有灯, call $TOOL_HOME_LIGHTS_SET_ALL.
        When the user asks to control one supported light, call $TOOL_HOME_LIGHT_SET.
        When the user explicitly asks to draw a simple pixel/matrix pattern, call $TOOL_HOME_LIGHT_MATRIX_DRAW with exactly ${LightCatalog.MATRIX_PIXEL_COUNT} #RRGGBB values.
        For matrix drawing, the pixel order starts from the bottom row left-to-right, then moves upward row by row.
        For unsupported devices such as air conditioner, curtains, speakers, appliances, or fridge, or for cross-device
        automation and judgement beyond the local light tools, call $TOOL_REQUEST_COLLABORATION instead of refusing.
        Never say the light tools are unavailable, not exposed, or not permitted unless a tool call actually fails.
        If the user asks about entryway presence, prefer living_room/floor_lamp at 60%.
        Do not claim that you controlled a light unless the tool result confirms it.
        Keep responses short and in Chinese.
        """.trimIndent()

    private fun homeContextMessage(context: Context, message: String): String =
        """
        当前虚拟家居状态：
        ${VirtualHomeStore.load(context).toResultJson()}

        本地 HomeAgent 已注册工具：
        - $TOOL_HOME_LIGHT_SET：控制单个灯
        - $TOOL_HOME_LIGHTS_SET_ALL：控制全部灯
        - $TOOL_HOME_LIGHT_MATRIX_DRAW：向 Yeelight Cube 发送 20 x 5 图案
        - $TOOL_REQUEST_COLLABORATION：交给外部 Napaxi Agent

        用户请求：
        $message
        """.trimIndent()

    private fun response(
        type: HomeAgentOutcomeType,
        message: String,
        state: VirtualHomeState,
        proposedAction: HomeAgentCommand? = null,
        napaxiMessage: String = "",
        eventType: String = "home_agent_message",
    ): HomeAgentResponse {
        val collaborationMessage = napaxiMessage.ifBlank {
            "家居助手请求 Napaxi Agent 协作。当前状态：${state.toResultJson()}"
        }
        return HomeAgentResponse(
            type = type,
            message = message,
            state = state,
            proposedAction = proposedAction,
            napaxiMessage = collaborationMessage,
            eventType = eventType,
            payloadJson = JSONObject()
                .put("source", "smart_home_local_agent")
                .put("runtime", "napaxi_android_sdk")
                .put("local_outcome", type.name.lowercase())
                .put("local_message", message)
                .put("proposed_action", proposedAction?.let {
                    JSONObject()
                        .put("action_id", it.actionId)
                        .put("arguments", JSONObject(it.argumentsJson))
                        .put("label", it.label)
                } ?: JSONObject.NULL)
                .put("home_state", JSONObject(state.toResultJson()))
                .toString(),
        )
    }

    private fun parseColor(value: String): Int {
        val hex = value.trim().removePrefix("#")
        check(hex.length == 6) { "Color must be #RRGGBB: $value" }
        return hex.toInt(16) and 0xFFFFFF
    }
}
