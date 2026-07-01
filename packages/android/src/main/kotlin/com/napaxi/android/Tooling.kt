package com.napaxi.android

import org.json.JSONArray
import org.json.JSONObject

public fun interface McToolExecutor {
    fun execute(toolName: String, paramsJson: String, callback: McToolCallback)
}

public fun interface McToolApprovalHandler {
    fun requestApproval(request: McToolApprovalRequest, callback: McToolCallback)
}

public fun interface AgentAppActionExecutor {
    fun execute(request: AgentAppActionRequest, callback: AgentAppActionCallback)
}

@Deprecated("Use AgentAppActionExecutor instead.")
public typealias McAgentAppActionExecutor = AgentAppActionExecutor

public interface AgentAppActionCallback {
    fun success(result: AgentAppActionResult)
    fun error(code: String, message: String)
}

public fun interface NapaxiBrowserController {
    fun execute(toolName: String, paramsJson: String, callback: McToolCallback)

    fun canHandle(toolName: String): Boolean = BrowserToolProvider.isBrowserTool(toolName)
}

public enum class BrowserMutationPolicy {
    RequireApproval,
    AllowAll,
}

public object BrowserToolProvider {
    public const val CAPABILITY_ID: String = "napaxi.tool.browser"

    private val fallbackToolNames: Set<String> = setOf(
        "browser_open",
        "browser_snapshot",
        "browser_click",
        "browser_type",
        "browser_scroll",
        "browser_wait",
        "browser_find_text",
        "browser_keys",
        "browser_back",
        "browser_close",
    )

    @JvmStatic
    public fun isBrowserTool(name: String): Boolean {
        if (name in fallbackToolNames) return true
        return runCatching {
            val raw = unwrapBridgeResult(
                NapaxiNative.callBridge("tools.is_browser_tool", 0L, JSONObject().put("name", name).toString()),
            )
            raw == "true"
        }.getOrDefault(false)
    }

    @JvmStatic
    public fun toolNames(): Set<String> = fallbackToolNames

    @JvmStatic
    public fun getToolDefinitions(): List<CustomToolDef> {
        val raw = runCatching {
            unwrapBridgeResult(NapaxiNative.callBridge("tools.browser_tool_descriptors", 0L, "{}"))
        }.getOrDefault("")
        val fromCore = raw.parseCustomToolDefs()
        return fromCore.ifEmpty { fallbackToolDefinitions() }
    }

    private fun String.parseCustomToolDefs(): List<CustomToolDef> {
        if (isBlank()) return emptyList()
        return runCatching {
            val trimmed = trim()
            val array = if (trimmed.startsWith("[")) {
                JSONArray(trimmed)
            } else {
                JSONObject(trimmed).optJSONArray("tools") ?: JSONArray()
            }
            array.toJsonObjectList()
                .map(CustomToolDef::fromJsonObject)
                .filter { it.name.isNotBlank() }
        }.getOrDefault(emptyList())
    }

    private fun fallbackToolDefinitions(): List<CustomToolDef> =
        fallbackToolNames.map { name ->
            CustomToolDef(
                name = name,
                description = when (name) {
                    "browser_open" -> "Open an absolute http:// or https:// URL in the visible in-app browser session."
                    "browser_snapshot" -> "Read the current browser page state."
                    "browser_click" -> "Click an element in the current browser page."
                    "browser_type" -> "Type text into the current browser page."
                    "browser_scroll" -> "Scroll the current browser page."
                    "browser_wait" -> "Wait for the browser page to load or contain text."
                    "browser_find_text" -> "Find visible text and scroll it into view."
                    "browser_keys" -> "Send simple keyboard keys to the focused browser element."
                    "browser_back" -> "Navigate the browser session back if possible."
                    "browser_close" -> "Close or clear the persistent browser session."
                    else -> "Browser tool."
                },
                effect = if (name in setOf("browser_snapshot", "browser_wait", "browser_find_text")) "read" else "external",
            )
        }
}

public class AndroidBrowserToolHost(
    private val controller: NapaxiBrowserController,
    private val approvalHandler: McToolApprovalHandler? = null,
    private val mutationPolicy: BrowserMutationPolicy = BrowserMutationPolicy.RequireApproval,
) : NapaxiBrowserController {
    override fun canHandle(toolName: String): Boolean =
        BrowserToolProvider.isBrowserTool(toolName) && controller.canHandle(toolName)

    override fun execute(toolName: String, paramsJson: String, callback: McToolCallback) {
        val approvalReason = approvalReason(toolName, paramsJson)
        if (approvalReason == null) {
            controller.execute(toolName, paramsJson, callback)
            return
        }
        val handler = approvalHandler
        if (handler == null) {
            callback.success(blockedResult(toolName))
            return
        }
        handler.requestApproval(
            McToolApprovalRequest(
                requestId = System.currentTimeMillis(),
                toolName = toolName,
                description = approvalReason,
                parametersJson = paramsJson.ifBlank { "{}" },
                allowAlways = false,
            ),
            object : McToolCallback {
                override fun success(resultJson: String) {
                    val approved = runCatching { JSONObject(resultJson).optBoolean("approved", false) }
                        .getOrDefault(false)
                    if (approved) {
                        controller.execute(toolName, paramsJson, callback)
                    } else {
                        callback.success(blockedResult(toolName))
                    }
                }

                override fun error(message: String) {
                    callback.success(blockedResult(toolName, message))
                }
            },
        )
    }

    private fun approvalReason(toolName: String, paramsJson: String): String? {
        if (mutationPolicy == BrowserMutationPolicy.AllowAll) return null
        val params = runCatching { JSONObject(paramsJson.ifBlank { "{}" }) }.getOrDefault(JSONObject())
        if (toolName == "browser_type" && params.optBoolean("submit", false)) {
            return "Approve browser typing and submit"
        }
        if (toolName != "browser_click") return null
        if (params.has("click_point") && !params.has("element_id")) {
            return "Approve coordinate browser click"
        }
        val target = listOf(
            params.optString("text"),
            params.optString("label"),
            params.optString("selector"),
            params.optString("risk_hint"),
        ).joinToString(" ").lowercase()
        val riskyTerms = listOf(
            "pay",
            "purchase",
            "buy",
            "order",
            "delete",
            "remove",
            "submit",
            "send",
            "post",
            "confirm",
            "checkout",
            "login",
            "sign in",
        )
        return if (riskyTerms.any { target.contains(it) }) {
            "Approve high-risk browser click"
        } else {
            null
        }
    }

    private fun blockedResult(toolName: String, message: String = "Browser action requires user approval"): String =
        JSONObject()
            .put("success", false)
            .put("action", toolName)
            .put("blocked_or_approval_reason", message)
            .toString()
}

public interface McToolCallback {
    fun success(resultJson: String)
    fun error(message: String)
}

public interface ChatEventListener {
    fun onEvent(event: ChatEvent)
    fun onComplete() {}
    fun onError(error: Throwable) {}
}

public data class McToolApprovalRequest(
    val requestId: Long,
    val toolName: String,
    val description: String = "",
    val parametersJson: String = "{}",
    val contextJson: String = "{}",
    val allowAlways: Boolean = false,
) {
    public val parameters: org.json.JSONObject
        get() = runCatching { org.json.JSONObject(parametersJson.ifBlank { "{}" }) }
            .getOrDefault(org.json.JSONObject())

    public companion object {
        public fun fromToolRequest(requestId: Long, paramsJson: String, contextJson: String = "{}"): McToolApprovalRequest {
            val params = org.json.JSONObject(paramsJson.ifBlank { "{}" })
            return McToolApprovalRequest(
                requestId = requestId,
                toolName = params.optString("tool_name"),
                description = params.optString("description"),
                parametersJson = params.optJSONObject("parameters")?.toString() ?: "{}",
                contextJson = contextJson,
                allowAlways = params.optBoolean("allow_always", false),
            )
        }

        public fun fromJson(rawJson: String): McToolApprovalRequest =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): McToolApprovalRequest =
            McToolApprovalRequest(
                requestId = obj.optLong("request_id", obj.optLong("requestId", 0L)),
                toolName = obj.optString("tool_name", obj.optString("toolName")),
                description = obj.optString("description"),
                parametersJson = obj.optJSONObject("parameters")?.toString()
                    ?: obj.optNullableString("parameters_json")
                    ?: obj.optNullableString("parametersJson")
                    ?: "{}",
                contextJson = obj.optJSONObject("context")?.toString()
                    ?: obj.optNullableString("context_json")
                    ?: obj.optNullableString("contextJson")
                    ?: "{}",
                allowAlways = obj.optBoolean("allow_always", obj.optBoolean("allowAlways", false)),
            )

        public fun fromMap(map: Map<String, *>): McToolApprovalRequest =
            fromJsonObject(JSONObject(map))
    }
}

public data class McToolApprovalResponse(
    val approved: Boolean,
    val always: Boolean = false,
    val message: String? = null,
) {
    public fun toJsonObject(): org.json.JSONObject =
        org.json.JSONObject()
            .put("approved", approved)
            .put("always", always)
            .apply {
                message?.let { put("message", it) }
            }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): McToolApprovalResponse =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): McToolApprovalResponse =
            McToolApprovalResponse(
                approved = obj.optBoolean("approved", false),
                always = obj.optBoolean("always", false),
                message = obj.optNullableString("message"),
            )

        public fun fromMap(map: Map<String, *>): McToolApprovalResponse =
            fromJsonObject(JSONObject(map))
    }
}

public data class AgentAppActionRequest(
    val rawJson: String,
) {
    public constructor(
        proposal: AgentAppActionProposal,
        action: AgentAppActionManifest,
        `package`: JSONObject,
    ) : this(
        JSONObject()
            .put("proposal", proposal.toJsonObject())
            .put("action", action.toJsonObject())
            .put("package", `package`)
            .toString(),
    )

    private val json = org.json.JSONObject(rawJson.ifBlank { "{}" })
    public val proposal: AgentAppActionProposal =
        AgentAppActionProposal((json.optJSONObject("proposal") ?: json).toString())
    public val action: AgentAppPackageAction =
        AgentAppPackageAction((json.optJSONObject("action") ?: org.json.JSONObject()).toString())
    public val packageJson: org.json.JSONObject =
        json.optJSONObject("package") ?: org.json.JSONObject()
    public val `package`: org.json.JSONObject get() = packageJson
    public val requestId: String get() = proposal.requestId
    public val providerId: String get() = proposal.providerId
    public val agentId: String get() = proposal.agentId
    public val actionId: String get() = proposal.actionId
    public val toolName: String get() = proposal.toolName
    public val argumentsJson: String get() = proposal.arguments.toString()

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AgentAppActionRequest =
            AgentAppActionRequest(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AgentAppActionRequest =
            AgentAppActionRequest(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AgentAppActionRequest =
            fromJsonObject(JSONObject(map))
    }
}
