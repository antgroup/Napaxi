package com.napaxi.android

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

private const val DEFAULT_LLM_SYSTEM_PROMPT_EN = "You are a helpful assistant."
private const val DEFAULT_LLM_SYSTEM_PROMPT_ZH = "你是一个有帮助的 AI 助手。"

public data class ScenePromptConfig(
    val enabled: Boolean = false,
    val hostPolicies: Map<String, String>? = null,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("enabled", enabled)
        .apply {
            hostPolicies?.let { put("host_policies", JSONObject(it)) }
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): ScenePromptConfig =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): ScenePromptConfig =
            ScenePromptConfig(
                enabled = obj.optBoolean("enabled", false),
                hostPolicies = obj.optJSONObject("host_policies")?.toStringMap(),
            )

        public fun fromMap(map: Map<String, *>): ScenePromptConfig =
            fromJsonObject(JSONObject(map))
    }
}

public data class ContextEngineConfig(
    val enabled: Boolean = true,
    val engine: String = "compressor",
    val triggerRatio: Double = 0.85,
    val targetRatio: Double = 0.45,
    val protectHeadMessages: Int = 2,
    val protectTailMessages: Int = 20,
    val contextWindowTokens: Int? = null,
    val nativeContextWindowTokens: Int? = null,
    val providerContextWindowTokens: Int? = null,
    val responseReserveTokens: Int? = null,
    val compactionStrategy: String = "llm_summary",
    val compactionModel: String? = null,
    val compactionTimeoutMs: Long = 60_000,
    val preCompactionMemoryFlush: Boolean = false,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("enabled", enabled)
        .put("engine", engine)
        .put("trigger_ratio", triggerRatio)
        .put("target_ratio", targetRatio)
        .put("protect_head_messages", protectHeadMessages)
        .put("protect_tail_messages", protectTailMessages)
        .apply {
            contextWindowTokens?.let { put("context_window_tokens", it) }
            nativeContextWindowTokens?.let { put("native_context_window_tokens", it) }
            providerContextWindowTokens?.let { put("provider_context_window_tokens", it) }
            responseReserveTokens?.let { put("response_reserve_tokens", it) }
            put("compaction_strategy", compactionStrategy)
            compactionModel?.takeIf { it.isNotBlank() }?.let { put("compaction_model", it) }
            put("compaction_timeout_ms", compactionTimeoutMs)
            put("pre_compaction_memory_flush", preCompactionMemoryFlush)
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): ContextEngineConfig =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): ContextEngineConfig =
            ContextEngineConfig(
                enabled = obj.optBoolean("enabled", true),
                engine = obj.optString("engine", "compressor"),
                triggerRatio = obj.optDouble("trigger_ratio", 0.85),
                targetRatio = obj.optDouble("target_ratio", 0.45),
                protectHeadMessages = obj.optInt("protect_head_messages", 2),
                protectTailMessages = obj.optInt("protect_tail_messages", 20),
                contextWindowTokens = obj.optNullableInt("context_window_tokens"),
                nativeContextWindowTokens = obj.optNullableInt("native_context_window_tokens"),
                providerContextWindowTokens = obj.optNullableInt("provider_context_window_tokens"),
                responseReserveTokens = obj.optNullableInt("response_reserve_tokens"),
                compactionStrategy = obj.optString("compaction_strategy", "llm_summary"),
                compactionModel = obj.optNullableString("compaction_model"),
                compactionTimeoutMs = obj.optLong("compaction_timeout_ms", 60_000),
                preCompactionMemoryFlush = obj.optBoolean("pre_compaction_memory_flush", false),
            )

        public fun fromMap(map: Map<String, *>): ContextEngineConfig =
            fromJsonObject(JSONObject(map))
    }
}

/**
 * Shell command approval posture. Mirrors the Rust `ShellApprovalMode`.
 *
 * The SDK provides the mechanism; the host selects the policy. Every mode
 * shares the same hard gate (destructive / data-exfiltration commands are
 * always rejected); the mode only decides what happens to commands that are
 * not in the known-safe allow-list.
 */
public enum class ShellApprovalMode(public val wireName: String) {
    READ_ONLY_ONLY("read_only_only"),
    ON_REQUEST("on_request"),
    TRUSTED_ALLOW("trusted_allow"),
    CUSTOM("custom");

    public companion object {
        public fun fromWire(value: String?): ShellApprovalMode =
            entries.firstOrNull { it.wireName == value } ?: ON_REQUEST
    }
}

/** Shell command security configuration. Mirrors the Rust `ShellSecurityConfig`. */
public data class ShellSecurityConfig(
    val approvalMode: ShellApprovalMode = ShellApprovalMode.ON_REQUEST,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("approval_mode", approvalMode.wireName)

    public fun toJson(): String = toJsonObject().toString()

    public companion object {
        public fun fromJson(rawJson: String): ShellSecurityConfig =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): ShellSecurityConfig =
            ShellSecurityConfig(
                approvalMode = ShellApprovalMode.fromWire(
                    obj.optNullableString("approval_mode"),
                ),
            )

        public fun fromMap(map: Map<String, *>): ShellSecurityConfig =
            fromJsonObject(JSONObject(map))
    }
}

public data class LlmCapabilityConfig(
    val provider: String,
    val apiKey: String,
    val model: String,
    val baseUrl: String? = null,
    val maxTokens: Int? = null,
    val extraHeaders: String? = null,
    val imageBase64UrlFormat: String? = null,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("provider", provider)
        .put("api_key", apiKey)
        .put("base_url", baseUrl)
        .put("model", model)
        .apply {
            maxTokens?.let { put("max_tokens", it) }
            extraHeaders?.let { put("extra_headers", it) }
            imageBase64UrlFormat?.let { put("image_base64_url_format", it) }
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): LlmCapabilityConfig =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): LlmCapabilityConfig =
            LlmCapabilityConfig(
                provider = obj.optString("provider"),
                apiKey = obj.optString("api_key"),
                baseUrl = obj.optNullableString("base_url"),
                model = obj.optString("model"),
                maxTokens = obj.optNullableInt("max_tokens"),
                extraHeaders = obj.optNullableString("extra_headers"),
                imageBase64UrlFormat = obj.optNullableString("image_base64_url_format"),
            )

        public fun fromMap(map: Map<String, *>): LlmCapabilityConfig =
            fromJsonObject(JSONObject(map))
    }
}

public data class LlmConfig(
    val provider: String,
    val apiKey: String,
    val model: String,
    val baseUrl: String? = null,
    val systemPrompt: String = "You are a helpful assistant.",
    val responseLanguage: String = "en",
    val maxTokens: Int = DEFAULT_MAX_TOKENS,
    val maxToolIterations: Int = 50,
    val extraHeaders: String? = null,
    val userTimezone: String? = null,
    val allowedModels: List<Map<String, String>>? = null,
    val imageModel: String? = null,
    val imageAnalysisModel: String? = null,
    val imageBase64UrlFormat: String? = null,
    val videoModel: String? = null,
    val audioModel: String? = null,
    val capabilityConfigs: Map<String, LlmCapabilityConfig>? = null,
    val scenePromptConfig: ScenePromptConfig? = null,
    val contextEngine: ContextEngineConfig = ContextEngineConfig(),
    val shellSecurity: ShellSecurityConfig = ShellSecurityConfig(),
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("provider", provider)
        .put("api_key", apiKey)
        .put("base_url", baseUrl)
        .put("model", model)
        .put("system_prompt", effectiveSystemPrompt(systemPrompt, responseLanguage))
        .put("response_language", responseLanguage)
        .put("max_tokens", maxTokens)
        .put("max_tool_iterations", maxToolIterations)
        .put("extra_headers", extraHeaders)
        .apply {
            userTimezone?.takeIf { it.trim().isNotEmpty() }?.let { put("user_timezone", it) }
            allowedModels?.let { models ->
                put(
                    "allowed_models",
                    JSONArray(
                        models.map { model ->
                            JSONObject().apply {
                                model.forEach { (key, value) -> put(key, value) }
                            }
                        },
                    ),
                )
            }
            imageModel?.let { put("image_model", it) }
            imageAnalysisModel?.let { put("image_analysis_model", it) }
            imageBase64UrlFormat?.let { put("image_base64_url_format", it) }
            videoModel?.let { put("video_model", it) }
            audioModel?.let { put("audio_model", it) }
            capabilityConfigs?.let { configs ->
                put(
                    "capability_configs",
                    JSONObject().apply {
                        configs.forEach { (key, value) -> put(key, value.toJsonObject()) }
                    },
                )
            }
            scenePromptConfig?.let { put("scene_prompt_config", it.toJsonObject()) }
            put("context_engine", contextEngine.toJsonObject())
            put("shell_security", shellSecurity.toJsonObject())
        }

    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    companion object {
        public const val DEFAULT_MAX_TOKENS: Int = 40960

        fun fromJson(json: String): LlmConfig {
            return fromJsonObject(JSONObject(json.ifBlank { "{}" }))
        }

        fun fromJsonObject(obj: JSONObject): LlmConfig {
            val responseLanguage = obj.optString("response_language", "en")
            return LlmConfig(
                provider = obj.optString("provider", "anthropic"),
                apiKey = obj.optString("api_key"),
                model = obj.optString("model"),
                baseUrl = obj.optNullableString("base_url"),
                systemPrompt = obj.optString(
                    "system_prompt",
                    defaultSystemPrompt(responseLanguage),
                ),
                responseLanguage = responseLanguage,
                maxTokens = obj.optInt("max_tokens", DEFAULT_MAX_TOKENS),
                maxToolIterations = obj.optInt("max_tool_iterations", 50),
                extraHeaders = obj.optNullableString("extra_headers"),
                userTimezone = obj.optNullableString("user_timezone")
                    ?: obj.optNullableString("userTimeZone")
                    ?: obj.optNullableString("timeZoneId"),
                allowedModels = obj.optJSONArray("allowed_models")?.toStringMapList(),
                imageModel = obj.optNullableString("image_model"),
                imageAnalysisModel = obj.optNullableString("image_analysis_model"),
                imageBase64UrlFormat = obj.optNullableString("image_base64_url_format"),
                videoModel = obj.optNullableString("video_model"),
                audioModel = obj.optNullableString("audio_model"),
                capabilityConfigs = obj.optJSONObject("capability_configs")?.let { configs ->
                    configs.keys().asSequence().associateWith { key ->
                        LlmCapabilityConfig.fromJsonObject(configs.optJSONObject(key) ?: JSONObject())
                    }
                },
                scenePromptConfig = obj.optJSONObject("scene_prompt_config")?.let(ScenePromptConfig::fromJsonObject),
                contextEngine = obj.optJSONObject("context_engine")?.let(ContextEngineConfig::fromJsonObject)
                    ?: ContextEngineConfig(),
                shellSecurity = obj.optJSONObject("shell_security")?.let(ShellSecurityConfig::fromJsonObject)
                    ?: ShellSecurityConfig(),
            )
        }

        fun fromMap(map: Map<String, *>): LlmConfig =
            fromJsonObject(JSONObject(map))

        private fun effectiveSystemPrompt(systemPrompt: String, responseLanguage: String): String =
            if (systemPrompt == DEFAULT_LLM_SYSTEM_PROMPT_EN && normalizedResponseLanguage(responseLanguage) == "zh") {
                DEFAULT_LLM_SYSTEM_PROMPT_ZH
            } else {
                systemPrompt
            }

        private fun defaultSystemPrompt(responseLanguage: String): String =
            if (normalizedResponseLanguage(responseLanguage) == "zh") {
                DEFAULT_LLM_SYSTEM_PROMPT_ZH
            } else {
                DEFAULT_LLM_SYSTEM_PROMPT_EN
            }

        private fun normalizedResponseLanguage(responseLanguage: String): String =
            when (responseLanguage.trim().lowercase()) {
                "zh", "zh-cn", "chinese" -> "zh"
                else -> "en"
            }
    }
}

public data class SessionKey(
    val channelType: String,
    val accountId: String,
    val threadId: String,
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("channel_type", channelType)
        .put("account_id", accountId)
        .put("thread_id", threadId)

    fun toJson(): String = toJsonObject().toString()

    companion object {
        fun fromJson(json: String): SessionKey {
            val obj = JSONObject(json)
            return SessionKey(
                channelType = obj.optString("channel_type", "app"),
                accountId = obj.optString("account_id"),
                threadId = obj.optString("thread_id"),
            )
        }
    }
}

public data class SessionInfo(
    val key: SessionKey,
    val title: String = "",
    val preview: String = "",
    val messageCount: Int = 0,
    val createdAt: String = "",
    val updatedAt: String = "",
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("key", key.toJsonObject())
        .put("title", title)
        .put("preview", preview)
        .put("message_count", messageCount)
        .put("created_at", createdAt)
        .put("updated_at", updatedAt)

    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    companion object {
        fun fromJson(rawJson: String): SessionInfo =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        fun fromJsonObject(obj: JSONObject): SessionInfo {
            val keyObj = obj.optJSONObject("key") ?: JSONObject()
            return SessionInfo(
                key = SessionKey(
                    channelType = keyObj.optString("channel_type", "app"),
                    accountId = keyObj.optString("account_id"),
                    threadId = keyObj.optString("thread_id"),
                ),
                title = obj.optString("title"),
                preview = obj.optString("preview"),
                messageCount = obj.optInt("message_count"),
                createdAt = obj.optString("created_at"),
                updatedAt = obj.optString("updated_at"),
            )
        }

        fun fromMap(map: Map<String, *>): SessionInfo =
            fromJsonObject(JSONObject(map))
    }
}

public data class AgentHandle(
    val agentId: String,
    val rawJson: String,
)

public data class CustomToolDef(
    val name: String,
    val description: String,
    val parameters: JSONObject = JSONObject("""{"type":"object","properties":{}}"""),
    val effect: String = "unknown",
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("name", name)
        .put("description", description)
        .put("parameters", parameters)
        .put("effect", effect)

    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): CustomToolDef =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): CustomToolDef =
            CustomToolDef(
                name = obj.optString("name"),
                description = obj.optString("description"),
                parameters = obj.optJSONObject("parameters") ?: JSONObject("""{"type":"object","properties":{}}"""),
                effect = obj.optString("effect", "unknown"),
            )

        public fun fromMap(map: Map<String, *>): CustomToolDef =
            fromJsonObject(JSONObject(map))
    }
}

public data class McAttachment(
    val kind: String,
    val mimeType: String,
    val filename: String? = null,
    val sandboxPath: String? = null,
    val localPath: String? = null,
    val dataBase64: String = "",
    val extractedText: String? = null,
) {
    fun toJsonObject(sandboxPathOverride: String? = null): JSONObject = JSONObject()
        .put("kind", kind)
        .put("mime_type", mimeType)
        .put("data_base64", dataBase64)
        .apply {
            val effectiveSandboxPath = sandboxPathOverride ?: sandboxPath
            filename?.let { put("filename", it) }
            effectiveSandboxPath?.let { put("sandbox_path", it) }
            localPath?.let { put("path", it) }
            extractedText?.let { put("extracted_text", it) }
        }
}

public open class NapaxiJsonModel(public open val rawJson: String) {
    public fun jsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
}

public data class NapaxiCapabilityProfile(
    val platform: String? = "android",
    val supportedCapabilities: List<String> = emptyList(),
    val disabledCapabilities: List<String> = emptyList(),
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("supported_capabilities", JSONArray(supportedCapabilities))
        .put("disabled_capabilities", JSONArray(disabledCapabilities))
        .apply {
            platform?.let { put("platform", it) }
        }

    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()
}

public data class NapaxiCapabilitySelection(
    val enabledCapabilities: List<String> = emptyList(),
    val disabledCapabilities: List<String> = emptyList(),
    val config: JSONObject = JSONObject(),
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("enabled_capabilities", JSONArray(enabledCapabilities))
        .put("disabled_capabilities", JSONArray(disabledCapabilities))
        .put("config", config)

    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()
}

public object NapaxiChannelSurfaceKind {
    public const val IM: String = "im"
    public const val DEVICE: String = "device"
    public const val APP: String = "app"
    public const val SYSTEM: String = "system"
    public const val CUSTOM: String = "custom"
}

public object NapaxiChannelEndpointKind {
    public const val DIRECT: String = "direct"
    public const val GROUP: String = "group"
    public const val ROOM: String = "room"
    public const val THREAD: String = "thread"
    public const val BROADCAST: String = "broadcast"
    public const val DEVICE: String = "device"
    public const val CUSTOM: String = "custom"
}

public object NapaxiChannelModality {
    public const val TEXT: String = "text"
    public const val AUDIO: String = "audio"
    public const val IMAGE: String = "image"
    public const val FILE: String = "file"
    public const val CONTROL: String = "control"
    public const val SENSOR: String = "sensor"
    public const val PRESENCE: String = "presence"
}

public object NapaxiChannelContentFormat {
    public const val PLAIN_TEXT: String = "plain_text"
    public const val MARKDOWN: String = "markdown"
}

public object NapaxiChannelCapability {
    public const val IM: String = "napaxi.channel.im"
    public const val DEVICE: String = "napaxi.channel.device"
}

public data class NapaxiChannelRegistration(
    val name: String,
    val type: String? = null,
    val accountId: String? = null,
    val surfaceKind: String? = null,
    val endpointKind: String? = null,
    val modalities: List<String> = emptyList(),
    val contentFormats: List<String> = emptyList(),
    val transport: String? = null,
    val config: JSONObject = JSONObject(),
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("name", name)
        .apply {
            type?.let { put("type", it) }
            accountId?.let { put("account_id", it) }
            surfaceKind?.let { put("surface_kind", it) }
            endpointKind?.let { put("endpoint_kind", it) }
            if (modalities.isNotEmpty()) put("modalities", JSONArray(modalities))
            if (contentFormats.isNotEmpty()) put("content_formats", JSONArray(contentFormats))
            transport?.let { put("transport", it) }
            if (config.length() > 0) put("config", config)
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun im(
            name: String,
            type: String,
            accountId: String? = null,
            endpointKind: String? = null,
            modalities: List<String> = listOf(NapaxiChannelModality.TEXT),
            contentFormats: List<String> = listOf(NapaxiChannelContentFormat.PLAIN_TEXT),
            transport: String? = null,
            config: JSONObject = JSONObject(),
        ): NapaxiChannelRegistration = NapaxiChannelRegistration(
            name = name,
            type = type,
            accountId = accountId,
            surfaceKind = NapaxiChannelSurfaceKind.IM,
            endpointKind = endpointKind,
            modalities = modalities,
            contentFormats = contentFormats,
            transport = transport,
            config = config,
        )
    }
}

public class NapaxiChannelRecord(rawJson: String) : NapaxiJsonModel(rawJson) {
    private val obj: JSONObject get() = jsonObject()
    public val name: String get() = obj.optString("name")
    public val type: String? get() = obj.optNullableString("type")
    public val surfaceKind: String? get() = obj.optNullableString("surface_kind")
    public val endpointKind: String? get() = obj.optNullableString("endpoint_kind")
    public val modalities: List<String> get() = obj.optJSONArray("modalities")?.toStringList().orEmpty()
    public val contentFormats: List<String> get() = (
        obj.optJSONArray("content_formats") ?: obj.optJSONArray("contentFormats")
        )?.toStringList().orEmpty()
    public val transport: String? get() = obj.optNullableString("transport")
    public val capabilityId: String? get() = obj.optNullableString("capability_id")
    public val config: JSONObject get() = obj.optJSONObject("config") ?: JSONObject()
    public val registeredAt: String get() = obj.optString("registered_at")
    public val updatedAt: String get() = obj.optString("updated_at")
    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()
}

public data class NapaxiChannelPeer(
    val kind: String = NapaxiChannelEndpointKind.DIRECT,
    val id: String,
    val displayName: String? = null,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("kind", kind)
        .put("id", id)
        .apply { displayName?.let { put("display_name", it) } }

    public companion object {
        public fun fromJsonObject(obj: JSONObject): NapaxiChannelPeer = NapaxiChannelPeer(
            kind = obj.optString("kind", NapaxiChannelEndpointKind.DIRECT),
            id = obj.optString("id"),
            displayName = obj.optNullableString("display_name"),
        )
    }
}

public data class NapaxiChannelActor(
    val id: String,
    val displayName: String? = null,
    val isBot: Boolean? = null,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("id", id)
        .apply {
            displayName?.let { put("display_name", it) }
            isBot?.let { put("is_bot", it) }
        }

    public companion object {
        public fun fromJsonObject(obj: JSONObject): NapaxiChannelActor = NapaxiChannelActor(
            id = obj.optString("id"),
            displayName = obj.optNullableString("display_name"),
            isBot = obj.optNullableBoolean("is_bot"),
        )
    }
}

public data class NapaxiChannelMedia(
    val kind: String,
    val uri: String? = null,
    val mimeType: String? = null,
    val name: String? = null,
    val sizeBytes: Long? = null,
    val raw: JSONObject? = null,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("kind", kind)
        .apply {
            uri?.let { put("uri", it) }
            mimeType?.let { put("mime_type", it) }
            name?.let { put("name", it) }
            sizeBytes?.let { put("size_bytes", it) }
            raw?.let { put("raw", it) }
        }

    public companion object {
        public fun fromJsonObject(obj: JSONObject): NapaxiChannelMedia = NapaxiChannelMedia(
            kind = obj.optString("kind", NapaxiChannelModality.FILE),
            uri = obj.optNullableString("uri"),
            mimeType = obj.optNullableString("mime_type"),
            name = obj.optNullableString("name"),
            sizeBytes = if (obj.has("size_bytes")) obj.optLong("size_bytes") else null,
            raw = obj.optJSONObject("raw"),
        )
    }
}

public data class NapaxiChannelInboundMessage(
    val channelName: String,
    val peer: NapaxiChannelPeer,
    val sender: NapaxiChannelActor,
    val accountId: String = "default",
    val id: String = "",
    val platformMessageId: String? = null,
    val threadId: String? = null,
    val text: String? = null,
    val media: List<NapaxiChannelMedia> = emptyList(),
    val raw: JSONObject? = null,
    val status: String = "",
    val receivedAt: String = "",
    val updatedAt: String = "",
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("channel_name", channelName)
        .put("account_id", accountId)
        .put("peer", peer.toJsonObject())
        .put("sender", sender.toJsonObject())
        .apply {
            if (id.isNotEmpty()) put("id", id)
            platformMessageId?.let { put("platform_message_id", it) }
            threadId?.let { put("thread_id", it) }
            text?.let { put("text", it) }
            if (media.isNotEmpty()) put("media", JSONArray(media.map { it.toJsonObject() }))
            raw?.let { put("raw", it) }
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): NapaxiChannelInboundMessage =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): NapaxiChannelInboundMessage = NapaxiChannelInboundMessage(
            id = obj.optString("id"),
            channelName = obj.optString("channel_name", obj.optString("channel")),
            accountId = obj.optString("account_id", "default"),
            peer = NapaxiChannelPeer.fromJsonObject(obj.optJSONObject("peer") ?: JSONObject()),
            sender = NapaxiChannelActor.fromJsonObject(obj.optJSONObject("sender") ?: JSONObject()),
            platformMessageId = obj.optNullableString("platform_message_id"),
            threadId = obj.optNullableString("thread_id"),
            text = obj.optNullableString("text"),
            media = obj.optJSONArray("media")?.toJsonObjectList()?.map {
                NapaxiChannelMedia.fromJsonObject(it)
            }.orEmpty(),
            raw = obj.optJSONObject("raw"),
            status = obj.optString("status"),
            receivedAt = obj.optString("received_at"),
            updatedAt = obj.optString("updated_at"),
        )
    }
}

public data class NapaxiChannelOutboundMessage(
    val channelName: String,
    val peer: NapaxiChannelPeer,
    val accountId: String = "default",
    val id: String = "",
    val replyToMessageId: String? = null,
    val threadId: String? = null,
    val text: String? = null,
    val format: String? = null,
    val media: List<NapaxiChannelMedia> = emptyList(),
    val raw: JSONObject? = null,
    val leaseId: String? = null,
    val platformReceipt: JSONObject? = null,
    val error: String? = null,
    val status: String = "",
    val createdAt: String = "",
    val updatedAt: String = "",
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("channel_name", channelName)
        .put("account_id", accountId)
        .put("peer", peer.toJsonObject())
        .apply {
            if (id.isNotEmpty()) put("id", id)
            replyToMessageId?.let { put("reply_to_message_id", it) }
            threadId?.let { put("thread_id", it) }
            text?.let { put("text", it) }
            format?.takeIf { it.isNotBlank() }?.let { put("format", it) }
            if (media.isNotEmpty()) put("media", JSONArray(media.map { it.toJsonObject() }))
            raw?.let { put("raw", it) }
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): NapaxiChannelOutboundMessage =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): NapaxiChannelOutboundMessage =
            NapaxiChannelOutboundMessage(
                id = obj.optString("id"),
                channelName = obj.optString("channel_name", obj.optString("channel")),
                accountId = obj.optString("account_id", "default"),
                peer = NapaxiChannelPeer.fromJsonObject(obj.optJSONObject("peer") ?: JSONObject()),
                replyToMessageId = obj.optNullableString("reply_to_message_id"),
                threadId = obj.optNullableString("thread_id"),
                text = obj.optNullableString("text"),
                format = obj.optNullableString("format")
                    ?: obj.optNullableString("content_format")
                    ?: obj.optNullableString("contentFormat"),
                media = obj.optJSONArray("media")?.toJsonObjectList()?.map {
                    NapaxiChannelMedia.fromJsonObject(it)
                }.orEmpty(),
                raw = obj.optJSONObject("raw"),
                leaseId = obj.optNullableString("lease_id"),
                platformReceipt = obj.optJSONObject("platform_receipt"),
                error = obj.optNullableString("error"),
                status = obj.optString("status"),
                createdAt = obj.optString("created_at"),
                updatedAt = obj.optString("updated_at"),
            )
    }
}

public data class NapaxiChannelAcceptedReceipt(
    val accepted: Boolean,
    val id: String,
    val duplicate: Boolean = false,
    val error: String? = null,
) {
    public companion object {
        public fun fromJson(rawJson: String): NapaxiChannelAcceptedReceipt =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): NapaxiChannelAcceptedReceipt =
            NapaxiChannelAcceptedReceipt(
                accepted = obj.optBoolean("accepted", false),
                id = obj.optString("id"),
                duplicate = obj.optBoolean("duplicate", false),
                error = obj.optNullableString("error"),
            )
    }
}

public data class NapaxiChannelAgentRoute(
    val channelName: String,
    val id: String = "",
    val channelAccountId: String? = null,
    val peerKind: String? = null,
    val peerId: String? = null,
    val threadId: String? = null,
    val sessionAccountId: String = "default",
    val agentId: String = "napaxi",
    val enabled: Boolean = true,
    val sessionPolicy: String = "stable_by_peer_or_thread",
    val createdAt: String = "",
    val updatedAt: String = "",
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .apply {
            if (id.isNotEmpty()) put("id", id)
            put("channel_name", channelName)
            channelAccountId?.let { put("channel_account_id", it) }
            peerKind?.let { put("peer_kind", it) }
            peerId?.let { put("peer_id", it) }
            threadId?.let { put("thread_id", it) }
            put("session_account_id", sessionAccountId)
            put("agent_id", agentId)
            put("enabled", enabled)
            put("session_policy", sessionPolicy)
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun channelDefault(
            channelName: String,
            channelAccountId: String? = null,
            sessionAccountId: String,
            agentId: String,
            enabled: Boolean = true,
        ): NapaxiChannelAgentRoute = NapaxiChannelAgentRoute(
            channelName = channelName,
            channelAccountId = channelAccountId,
            sessionAccountId = sessionAccountId,
            agentId = agentId,
            enabled = enabled,
        )

        public fun fromJson(rawJson: String): NapaxiChannelAgentRoute =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): NapaxiChannelAgentRoute =
            NapaxiChannelAgentRoute(
                id = obj.optString("id"),
                channelName = obj.optString("channel_name", obj.optString("channel")),
                channelAccountId = obj.optNullableString("channel_account_id"),
                peerKind = obj.optNullableString("peer_kind"),
                peerId = obj.optNullableString("peer_id"),
                threadId = obj.optNullableString("thread_id"),
                sessionAccountId = obj.optString("session_account_id", "default"),
                agentId = obj.optString("agent_id", "napaxi"),
                enabled = obj.optBoolean("enabled", true),
                sessionPolicy = obj.optString("session_policy", "stable_by_peer_or_thread"),
                createdAt = obj.optString("created_at"),
                updatedAt = obj.optString("updated_at"),
            )
    }
}

public data class NapaxiChannelAgentStatus(
    val routes: List<NapaxiChannelAgentRoute> = emptyList(),
    val pendingHuman: List<JSONObject> = emptyList(),
) {
    public companion object {
        public fun fromJson(rawJson: String): NapaxiChannelAgentStatus =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): NapaxiChannelAgentStatus =
            NapaxiChannelAgentStatus(
                routes = obj.optJSONArray("routes")?.toJsonObjectList()?.map {
                    NapaxiChannelAgentRoute.fromJsonObject(it)
                }.orEmpty(),
                pendingHuman = obj.optJSONArray("pending_human")?.toJsonObjectList().orEmpty(),
            )
    }
}

public data class NapaxiApkInstallResult(
    val success: Boolean,
    val installerOpened: Boolean = false,
    val permissionRequired: Boolean = false,
    val apkPath: String? = null,
    val error: String? = null,
    val code: String? = null,
    val rawJson: String = "",
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("success", success)
        .put("installerOpened", installerOpened)
        .put("permissionRequired", permissionRequired)
        .apply {
            apkPath?.let { put("apkPath", it) }
            error?.let { put("error", it) }
            code?.let { put("code", it) }
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): NapaxiApkInstallResult =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }), rawJson)

        public fun fromJsonObject(obj: JSONObject, rawJson: String = obj.toString()): NapaxiApkInstallResult =
            NapaxiApkInstallResult(
                success = obj.optBoolean("success", false),
                installerOpened = obj.optNullableBoolean("installerOpened")
                    ?: obj.optNullableBoolean("installer_opened")
                    ?: false,
                permissionRequired = obj.optNullableBoolean("permissionRequired")
                    ?: obj.optNullableBoolean("permission_required")
                    ?: false,
                apkPath = obj.optNullableString("apkPath")
                    ?: obj.optNullableString("apk_path")
                    ?: obj.optNullableString("path"),
                error = obj.optNullableString("error"),
                code = obj.optNullableString("code"),
                rawJson = rawJson,
            )

        public fun fromMap(map: Map<String, *>): NapaxiApkInstallResult =
            fromJsonObject(JSONObject(map))
    }
}

public open class RawJsonModel(override val rawJson: String) : NapaxiJsonModel(rawJson) {
    protected val obj: JSONObject get() = jsonObject()
}

public class ChatAttachment(rawJson: String) : RawJsonModel(rawJson) {
    private val rawPath: String? get() = obj.optNullableString("path")
    public val kind: String get() = obj.optString("kind")
    public val mimeType: String get() = obj.optString("mime_type", obj.optString("mimeType"))
    public val filename: String? get() = obj.optNullableString("filename") ?: obj.optNullableString("name")
    public val sandboxPath: String?
        get() = obj.optNullableString("sandbox_path")
            ?: rawPath?.takeIf { it.isWorkspaceSandboxPath() }
    public val localPath: String?
        get() = obj.optNullableString("local_path")
            ?: obj.optNullableString("localPath")
            ?: obj.optNullableString("host_path")
            ?: obj.optNullableString("hostPath")
            ?: rawPath?.takeUnless { it.isWorkspaceSandboxPath() }

    public fun toJsonObject(): JSONObject =
        JSONObject()
            .put("kind", kind)
            .put("mime_type", mimeType)
            .apply {
                filename?.let { put("filename", it) }
                sandboxPath?.let { put("sandbox_path", it) }
                localPath?.let { put("path", it) }
            }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): ChatAttachment =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): ChatAttachment =
            ChatAttachment(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): ChatAttachment =
            fromJsonObject(JSONObject(map))

        @JvmStatic
        public fun create(
            kind: String,
            mimeType: String,
            filename: String? = null,
            sandboxPath: String? = null,
            localPath: String? = null,
        ): ChatAttachment =
            ChatAttachment(
                JSONObject()
                    .put("kind", kind)
                    .put("mime_type", mimeType)
                    .apply {
                        filename?.let { put("filename", it) }
                        sandboxPath?.let { put("sandbox_path", it) }
                        localPath?.let { put("path", it) }
                    }
                    .toString(),
            )
    }
}

public class A2AAgentCard(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val agentId: String get() = obj.optString("agentId", obj.optString("agent_id"))
    public val displayName: String get() = obj.optString("displayName", obj.optString("display_name"))
    public val description: String get() = obj.optString("description")
    public val acceptedInputModes: List<String> get() = obj.optJSONArray("acceptedInputModes")?.toStringList().orEmpty()
    public val acceptedOutputModes: List<String> get() = obj.optJSONArray("acceptedOutputModes")?.toStringList().orEmpty()
    public val deepLinkUrl: String get() = obj.optString("deepLinkUrl", obj.optString("deep_link_url"))
    public val universalLinkUrl: String? get() = obj.optNullableString("universalLinkUrl") ?: obj.optNullableString("universal_link_url")
    public val capabilities: List<String> get() = obj.optJSONArray("capabilities")?.toStringList().orEmpty()
    public val requiresUserConfirmation: Boolean
        get() = obj.optNullableBoolean("requiresUserConfirmation")
            ?: obj.optNullableBoolean("requires_user_confirmation")
            ?: true

    public companion object {
        public fun fromJson(rawJson: String): A2AAgentCard = A2AAgentCard(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2AAgentCard = A2AAgentCard(obj.toString())
        public fun fromMap(map: Map<String, *>): A2AAgentCard = fromJsonObject(JSONObject(map))
    }
}

public class A2AParty(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val agentId: String get() = obj.optString("agentId", obj.optString("agent_id"))
    public val peerId: String get() = obj.optString("peerId", obj.optString("peer_id"))
    public val displayName: String get() = obj.optString("displayName", obj.optString("display_name"))
    public val deepLinkUrl: String get() = obj.optString("deepLinkUrl", obj.optString("deep_link_url"))

    public companion object {
        public fun fromJson(rawJson: String): A2AParty = A2AParty(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2AParty = A2AParty(obj.toString())
        public fun fromMap(map: Map<String, *>): A2AParty = fromJsonObject(JSONObject(map))
    }
}

public class A2ADeepLinkEnvelope(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val protocolVersion: Int get() = obj.optInt("protocolVersion", obj.optInt("protocol_version", 1))
    public val envelopeId: String get() = obj.optString("envelopeId", obj.optString("envelope_id"))
    public val kind: String get() = obj.optString("kind")
    public val sender: A2AParty get() = A2AParty(obj.optJSONObject("sender")?.toString() ?: "{}")
    public val recipient: A2AParty? get() = obj.optJSONObject("recipient")?.let { A2AParty(it.toString()) }
    public val task: A2ATaskRequest? get() = obj.optJSONObject("task")?.let { A2ATaskRequest(it.toString()) }
    public val result: A2ATaskResult? get() = obj.optJSONObject("result")?.let { A2ATaskResult(it.toString()) }
    public val callback: A2ACallback? get() = obj.optJSONObject("callback")?.let { A2ACallback(it.toString()) }
    public val createdAt: String get() = obj.optString("createdAt", obj.optString("created_at"))
    public val expiresAt: String get() = obj.optString("expiresAt", obj.optString("expires_at"))
    public val nonce: String get() = obj.optString("nonce")
    public val idempotencyKey: String get() = obj.optString("idempotencyKey", obj.optString("idempotency_key"))
    public val signatureAlgorithm: String get() = obj.optString("signatureAlgorithm", obj.optString("signature_algorithm"))
    public val signature: String? get() = obj.optNullableString("signature")

    public fun toJsonString(): String = rawJson

    public companion object {
        public fun fromJson(rawJson: String): A2ADeepLinkEnvelope = A2ADeepLinkEnvelope(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ADeepLinkEnvelope = A2ADeepLinkEnvelope(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ADeepLinkEnvelope = fromJsonObject(JSONObject(map))
    }
}

public class A2ATaskRequest(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val taskId: String get() = obj.optString("taskId", obj.optString("task_id"))
    public val message: String get() = obj.optString("message")
    public val artifacts: List<A2AArtifact> get() = obj.optJSONArray("artifacts")?.toJsonObjectList()?.map { A2AArtifact(it.toString()) }.orEmpty()
    public val context: JSONObject get() = obj.optJSONObject("context") ?: JSONObject()
    public val requestedOutputModes: List<String> get() = obj.optJSONArray("requestedOutputModes")?.toStringList().orEmpty()
    public val riskHint: String get() = obj.optString("riskHint", obj.optString("risk_hint"))
    public val sessionMode: String get() = obj.optString("sessionMode", obj.optString("session_mode", "isolated"))
    public val parentTaskId: String? get() = obj.optNullableString("parentTaskId") ?: obj.optNullableString("parent_task_id")

    public companion object {
        public fun fromJson(rawJson: String): A2ATaskRequest = A2ATaskRequest(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ATaskRequest = A2ATaskRequest(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ATaskRequest = fromJsonObject(JSONObject(map))
    }
}

public class A2AArtifact(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val artifactId: String get() = obj.optString("artifactId", obj.optString("artifact_id"))
    public val mimeType: String get() = obj.optString("mimeType", obj.optString("mime_type"))
    public val name: String get() = obj.optString("name")
    public val uri: String? get() = obj.optNullableString("uri")
    public val text: String? get() = obj.optNullableString("text")
    public val metadata: JSONObject get() = obj.optJSONObject("metadata") ?: JSONObject()

    public companion object {
        public fun fromJson(rawJson: String): A2AArtifact = A2AArtifact(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2AArtifact = A2AArtifact(obj.toString())
        public fun fromMap(map: Map<String, *>): A2AArtifact = fromJsonObject(JSONObject(map))
    }
}

public class A2ACallback(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val deepLinkUrl: String get() = obj.optString("deepLinkUrl", obj.optString("deep_link_url"))
    public val universalLinkUrl: String? get() = obj.optNullableString("universalLinkUrl") ?: obj.optNullableString("universal_link_url")

    public companion object {
        public fun fromJson(rawJson: String): A2ACallback = A2ACallback(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ACallback = A2ACallback(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ACallback = fromJsonObject(JSONObject(map))
    }
}

public class A2ATaskResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val taskId: String get() = obj.optString("taskId", obj.optString("task_id"))
    public val status: String get() = obj.optString("status")
    public val message: String? get() = obj.optNullableString("message")
    public val artifacts: List<A2AArtifact> get() = obj.optJSONArray("artifacts")?.toJsonObjectList()?.map { A2AArtifact(it.toString()) }.orEmpty()
    public val runId: String? get() = obj.optNullableString("runId") ?: obj.optNullableString("run_id")
    public val completedAt: String? get() = obj.optNullableString("completedAt") ?: obj.optNullableString("completed_at")
    public val error: String? get() = obj.optNullableString("error")

    public companion object {
        public fun fromJson(rawJson: String): A2ATaskResult = A2ATaskResult(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ATaskResult = A2ATaskResult(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ATaskResult = fromJsonObject(JSONObject(map))
    }
}

public class A2APeer(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val peerId: String get() = obj.optString("peerId", obj.optString("peer_id"))
    public val agentId: String get() = obj.optString("agentId", obj.optString("agent_id"))
    public val displayName: String get() = obj.optString("displayName", obj.optString("display_name"))
    public val deepLinkUrl: String get() = obj.optString("deepLinkUrl", obj.optString("deep_link_url"))
    public val trustLevel: String get() = obj.optString("trustLevel", obj.optString("trust_level"))
    public val sharedSecret: String get() = obj.optString("sharedSecret", obj.optString("shared_secret"))
    public val publicKey: String get() = obj.optString("publicKey", obj.optString("public_key"))
    public val endpoints: JSONArray get() = obj.optJSONArray("endpoints") ?: JSONArray()
    public val lastSeenAt: String get() = obj.optString("lastSeenAt", obj.optString("last_seen_at"))
    public val createdAt: String get() = obj.optString("createdAt", obj.optString("created_at"))
    public val updatedAt: String get() = obj.optString("updatedAt", obj.optString("updated_at"))

    public companion object {
        public fun fromJson(rawJson: String): A2APeer = A2APeer(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2APeer = A2APeer(obj.toString())
        public fun fromMap(map: Map<String, *>): A2APeer = fromJsonObject(JSONObject(map))
    }
}

public class A2ATaskRecord(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val taskId: String get() = obj.optString("taskId", obj.optString("task_id"))
    public val envelopeId: String get() = obj.optString("envelopeId", obj.optString("envelope_id"))
    public val idempotencyKey: String get() = obj.optString("idempotencyKey", obj.optString("idempotency_key"))
    public val agentId: String get() = obj.optString("agentId", obj.optString("agent_id"))
    public val sender: A2AParty get() = A2AParty(obj.optJSONObject("sender")?.toString() ?: "{}")
    public val callback: A2ACallback? get() = obj.optJSONObject("callback")?.let { A2ACallback(it.toString()) }
    public val request: A2ATaskRequest get() = A2ATaskRequest(obj.optJSONObject("request")?.toString() ?: "{}")
    public val status: String get() = obj.optString("status")
    public val trust: String get() = obj.optString("trust")
    public val source: String get() = obj.optString("source")
    public val createdAt: String get() = obj.optString("createdAt", obj.optString("created_at"))
    public val updatedAt: String get() = obj.optString("updatedAt", obj.optString("updated_at"))
    public val sessionId: String? get() = obj.optNullableString("sessionId") ?: obj.optNullableString("session_id")
    public val peerMessageId: String? get() = obj.optNullableString("peerMessageId") ?: obj.optNullableString("peer_message_id")
    public val sessionKey: String? get() = obj.optNullableString("sessionKey") ?: obj.optNullableString("session_key")
    public val runId: String? get() = obj.optNullableString("runId") ?: obj.optNullableString("run_id")
    public val summary: String? get() = obj.optNullableString("summary")
    public val resultArtifacts: List<A2AArtifact> get() = (obj.optJSONArray("resultArtifacts") ?: obj.optJSONArray("result_artifacts"))?.toJsonObjectList()?.map { A2AArtifact(it.toString()) }.orEmpty()
    public val error: String? get() = obj.optNullableString("error")

    public companion object {
        public fun fromJson(rawJson: String): A2ATaskRecord = A2ATaskRecord(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ATaskRecord = A2ATaskRecord(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ATaskRecord = fromJsonObject(JSONObject(map))
    }
}

public class A2APeerInvite(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val peerId: String get() = obj.optString("peerId")
    public val sharedSecret: String get() = obj.optString("sharedSecret")
    public val envelope: A2ADeepLinkEnvelope get() = A2ADeepLinkEnvelope(obj.optJSONObject("envelope")?.toString() ?: "{}")
    public val deepLinkUrl: String get() = obj.optString("deepLinkUrl")

    public companion object {
        public fun fromJson(rawJson: String): A2APeerInvite = A2APeerInvite(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2APeerInvite = A2APeerInvite(obj.toString())
        public fun fromMap(map: Map<String, *>): A2APeerInvite = fromJsonObject(JSONObject(map))
    }
}

public class A2AResultLink(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val taskId: String get() = obj.optString("taskId", obj.optString("task_id"))
    public val envelope: A2ADeepLinkEnvelope get() = A2ADeepLinkEnvelope(obj.optJSONObject("envelope")?.toString() ?: "{}")
    public val deepLinkUrl: String get() = obj.optString("deepLinkUrl", obj.optString("deep_link_url"))

    public companion object {
        public fun fromJson(rawJson: String): A2AResultLink = A2AResultLink(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2AResultLink = A2AResultLink(obj.toString())
        public fun fromMap(map: Map<String, *>): A2AResultLink = fromJsonObject(JSONObject(map))
    }
}

public class A2APeerEndpoint(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val transport: String get() = obj.optString("transport", "unknown")
    public val uri: String get() = obj.optString("uri")
    public val priority: Int get() = obj.optInt("priority")
    public val lastSeenAt: String? get() = obj.optNullableString("lastSeenAt") ?: obj.optNullableString("last_seen_at")

    public companion object {
        public fun fromJson(rawJson: String): A2APeerEndpoint = A2APeerEndpoint(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2APeerEndpoint = A2APeerEndpoint(obj.toString())
        public fun fromMap(map: Map<String, *>): A2APeerEndpoint = fromJsonObject(JSONObject(map))
    }
}

public class A2APeerSession(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val sessionId: String get() = obj.optString("sessionId", obj.optString("session_id"))
    public val localPeerId: String get() = obj.optString("localPeerId", obj.optString("local_peer_id"))
    public val remotePeerId: String get() = obj.optString("remotePeerId", obj.optString("remote_peer_id"))
    public val remoteAgentId: String get() = obj.optString("remoteAgentId", obj.optString("remote_agent_id"))
    public val status: String get() = obj.optString("status")
    public val transport: String get() = obj.optString("transport")
    public val endpoint: String get() = obj.optString("endpoint")
    public val createdAt: String get() = obj.optString("createdAt", obj.optString("created_at"))
    public val updatedAt: String get() = obj.optString("updatedAt", obj.optString("updated_at"))
    public val lastMessageAt: String? get() = obj.optNullableString("lastMessageAt") ?: obj.optNullableString("last_message_at")

    public companion object {
        public fun fromJson(rawJson: String): A2APeerSession = A2APeerSession(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2APeerSession = A2APeerSession(obj.toString())
        public fun fromMap(map: Map<String, *>): A2APeerSession = fromJsonObject(JSONObject(map))
    }
}

public class A2APeerMessage(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val messageId: String get() = obj.optString("messageId", obj.optString("message_id"))
    public val sessionId: String get() = obj.optString("sessionId", obj.optString("session_id"))
    public val fromPeerId: String get() = obj.optString("fromPeerId", obj.optString("from_peer_id"))
    public val toPeerId: String get() = obj.optString("toPeerId", obj.optString("to_peer_id"))
    public val kind: String get() = obj.optString("kind")
    public val createdAt: String get() = obj.optString("createdAt", obj.optString("created_at"))
    public val expiresAt: String get() = obj.optString("expiresAt", obj.optString("expires_at"))
    public val nonce: String get() = obj.optString("nonce")
    public val idempotencyKey: String get() = obj.optString("idempotencyKey", obj.optString("idempotency_key"))
    public val payload: JSONObject get() = obj.optJSONObject("payload") ?: JSONObject()
    public val signatureAlgorithm: String get() = obj.optString("signatureAlgorithm", obj.optString("signature_algorithm"))
    public val signature: String? get() = obj.optNullableString("signature")

    public fun toJsonString(): String = rawJson

    public companion object {
        public fun fromJson(rawJson: String): A2APeerMessage = A2APeerMessage(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2APeerMessage = A2APeerMessage(obj.toString())
        public fun fromMap(map: Map<String, *>): A2APeerMessage = fromJsonObject(JSONObject(map))
    }
}

public class A2ADeliveryRecord(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val messageId: String get() = obj.optString("messageId", obj.optString("message_id"))
    public val sessionId: String get() = obj.optString("sessionId", obj.optString("session_id"))
    public val direction: String get() = obj.optString("direction")
    public val kind: String get() = obj.optString("kind")
    public val status: String get() = obj.optString("status")
    public val createdAt: String get() = obj.optString("createdAt", obj.optString("created_at"))
    public val updatedAt: String get() = obj.optString("updatedAt", obj.optString("updated_at"))
    public val taskId: String? get() = obj.optNullableString("taskId") ?: obj.optNullableString("task_id")
    public val error: String? get() = obj.optNullableString("error")

    public companion object {
        public fun fromJson(rawJson: String): A2ADeliveryRecord = A2ADeliveryRecord(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ADeliveryRecord = A2ADeliveryRecord(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ADeliveryRecord = fromJsonObject(JSONObject(map))
    }
}

public class A2ALocalTransportStatus(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val supported: Boolean get() = obj.optBoolean("supported", false)
    public val running: Boolean get() = obj.optBoolean("running", false)
    public val transport: String get() = obj.optString("transport")
    public val serviceType: String get() = obj.optString("serviceType", obj.optString("service_type"))
    public val peerId: String get() = obj.optString("peerId", obj.optString("peer_id"))
    public val agentId: String get() = obj.optString("agentId", obj.optString("agent_id"))
    public val displayName: String get() = obj.optString("displayName", obj.optString("display_name"))
    public val endpoint: String get() = obj.optString("endpoint")
    public val listenerPort: Int get() = obj.optInt("listenerPort", obj.optInt("listener_port"))
    public val registeredName: String get() = obj.optString("registeredName", obj.optString("registered_name"))
    public val discoveredPeerCount: Int get() = obj.optInt("discoveredPeerCount", obj.optInt("discovered_peer_count"))
    public val activeDiscoveryCount: Int get() = obj.optInt("activeDiscoveryCount", obj.optInt("active_discovery_count"))
    public val sentMessageCount: Int get() = obj.optInt("sentMessageCount", obj.optInt("sent_message_count"))
    public val receivedMessageCount: Int get() = obj.optInt("receivedMessageCount", obj.optInt("received_message_count"))
    public val multicastLockHeld: Boolean get() = obj.optBoolean("multicastLockHeld", obj.optBoolean("multicast_lock_held"))
    public val lastError: String get() = obj.optString("lastError", obj.optString("last_error"))
    public val reason: String get() = obj.optString("reason")

    public companion object {
        public fun fromJson(rawJson: String): A2ALocalTransportStatus = A2ALocalTransportStatus(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ALocalTransportStatus = A2ALocalTransportStatus(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ALocalTransportStatus = fromJsonObject(JSONObject(map))
    }
}

public class A2ALocalPeerAdvertisement(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val peerId: String get() = obj.optString("peerId", obj.optString("peer_id"))
    public val agentId: String get() = obj.optString("agentId", obj.optString("agent_id"))
    public val displayName: String get() = obj.optString("displayName", obj.optString("display_name"))
    public val publicKey: String get() = obj.optString("publicKey", obj.optString("public_key"))
    public val transport: String get() = obj.optString("transport", "lan_tcp_jsonl")
    public val endpoint: String get() = obj.optString("endpoint")
    public val host: String get() = obj.optString("host")
    public val port: Int get() = obj.optInt("port")

    public fun toPeer(): A2APeer = A2APeer.fromMap(
        mapOf(
            "peerId" to peerId,
            "agentId" to agentId,
            "displayName" to displayName,
            "trustLevel" to "user_confirmed",
        ),
    )

    public companion object {
        public fun fromJson(rawJson: String): A2ALocalPeerAdvertisement = A2ALocalPeerAdvertisement(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ALocalPeerAdvertisement = A2ALocalPeerAdvertisement(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ALocalPeerAdvertisement = fromJsonObject(JSONObject(map))
    }
}

public class A2ALocalTransportEvent(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val action: String get() = obj.optString("action")
    public val peer: A2ALocalPeerAdvertisement?
        get() = obj.optJSONObject("peer")?.let { A2ALocalPeerAdvertisement.fromJsonObject(it) }
    public val message: A2APeerMessage?
        get() = obj.optJSONObject("message")?.let { A2APeerMessage.fromJsonObject(it) }
    public val messageJson: String get() = obj.optString("messageJson")
    public val payload: JSONObject get() = obj.optJSONObject("payload") ?: JSONObject()

    public companion object {
        public fun fromJson(rawJson: String): A2ALocalTransportEvent = A2ALocalTransportEvent(rawJson)
        public fun fromJsonObject(obj: JSONObject): A2ALocalTransportEvent = A2ALocalTransportEvent(obj.toString())
        public fun fromMap(map: Map<String, *>): A2ALocalTransportEvent = fromJsonObject(JSONObject(map))
        public fun fromEvent(rawJson: String): A2ALocalTransportEvent = A2ALocalTransportEvent(rawJson)
    }
}

public class ToolCallInfo(rawJson: String) : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name", "unknown")
    public val callId: String get() = obj.optString("call_id", obj.optString("tool_call_id"))
    public val arguments: JSONObject?
        get() {
            obj.optJSONObject("arguments")?.let { return it }
            obj.optJSONObject("parameters")?.let { return it }
            val raw = obj.optNullableString("arguments") ?: obj.optNullableString("parameters") ?: return null
            return runCatching { JSONObject(raw) }.getOrNull()
        }
    public val result: String? get() = obj.optNullableString("result") ?: obj.optNullableString("result_preview")
    public val error: String? get() = obj.optNullableString("error") ?: obj.optNullableString("error_preview")
    public val rationale: String? get() = obj.optNullableString("rationale")
    public val interrupted: Boolean get() = obj.optBoolean("interrupted", false)
    public val resultTruncated: Boolean get() = obj.optBoolean("result_truncated", false) || obj.has("result_preview")
    public val errorTruncated: Boolean get() = obj.optBoolean("error_truncated", false) || obj.has("error_preview")
    public val argumentsTruncated: Boolean
        get() = obj.optBoolean("arguments_truncated", false) || obj.optBoolean("parameters_truncated", false)

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): ToolCallInfo =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): ToolCallInfo =
            ToolCallInfo(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): ToolCallInfo =
            fromJsonObject(JSONObject(map))
    }
}

public class ChatMessage(rawJson: String) : RawJsonModel(rawJson) {
    public val role: String get() = obj.optString("role")
    public val content: String get() = obj.optString("content")
    public val attachments: List<ChatAttachment>
        get() = obj.optJSONArray("attachments")?.toJsonObjectList()?.map { ChatAttachment(it.toString()) }.orEmpty()
    public val id: String? get() = obj.optNullableString("id")
    public val createdAt: String? get() = obj.optNullableString("created_at") ?: obj.optNullableString("createdAt")
    public val thinkingContent: String?
        get() = obj.optNullableString("thinking_content")
            ?: obj.optNullableString("thinkingContent")
            ?: content.takeIf { role == "thinking" }
            ?: toolCallsEnvelope()?.optNullableString("narrative")
    public val reasoningContent: String?
        get() = obj.optNullableString("reasoning_content")
            ?: obj.optNullableString("reasoningContent")
            ?: content.takeIf { role == "reasoning" }
    public val toolCalls: List<ToolCallInfo>?
        get() {
            val direct = obj.optJSONArray("tool_calls") ?: obj.optJSONArray("toolCalls")
            direct?.toJsonObjectList()?.map { ToolCallInfo(it.toString()) }?.let { return it }
            if (role != "tool_calls") return null
            return toolCallsEnvelope()
                ?.optJSONArray("calls")
                ?.toJsonObjectList()
                ?.map { ToolCallInfo(it.toString()) }
        }
    public val humanRequestId: String?
        get() = obj.optNullableString("human_request_id")
            ?: obj.optNullableString("humanRequestId")
            ?: humanEnvelope()?.optNullableString("request_id")
    public val humanQuestion: String?
        get() = obj.optNullableString("human_question")
            ?: obj.optNullableString("humanQuestion")
            ?: humanEnvelope()?.optNullableString("question")
    public val humanOptions: List<String>
        get() = (
            obj.optJSONArray("human_options")
                ?: obj.optJSONArray("humanOptions")
                ?: humanEnvelope()?.optJSONArray("options")
            )?.toStringList().orEmpty()
    public val humanContext: String?
        get() = obj.optNullableString("human_context")
            ?: obj.optNullableString("humanContext")
            ?: humanEnvelope()?.optNullableString("context")
    public val interrupted: Boolean get() = obj.optBoolean("interrupted", false)

    private fun toolCallsEnvelope(): JSONObject? =
        runCatching { JSONObject(content.ifBlank { "{}" }) }.getOrNull()

    private fun humanEnvelope(): JSONObject? =
        if (role == "asking_human") runCatching { JSONObject(content.ifBlank { "{}" }) }.getOrNull() else null

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): ChatMessage =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): ChatMessage =
            ChatMessage(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): ChatMessage =
            fromJsonObject(JSONObject(map))
    }
}

public class HistoryPage(rawJson: String) : RawJsonModel(rawJson) {
    public val messages: List<ChatMessage>
        get() = obj.optJSONArray("messages")?.toJsonObjectList()?.map { ChatMessage(it.toString()) }.orEmpty()
    public val hasMore: Boolean get() = obj.optBoolean("has_more", obj.optBoolean("hasMore", false))
    public val nextBefore: String? get() = obj.optNullableString("next_before") ?: obj.optNullableString("nextBefore")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): HistoryPage =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): HistoryPage =
            HistoryPage(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): HistoryPage =
            fromJsonObject(JSONObject(map))
    }
}

public class ContextTokenBreakdown(rawJson: String) : RawJsonModel(rawJson) {
    public val systemPromptTokens: Int get() = obj.optInt("system_prompt_tokens", 0)
    public val summaryTokens: Int get() = obj.optInt("summary_tokens", 0)
    public val historyTokens: Int get() = obj.optInt("history_tokens", 0)
    public val toolDescriptorTokens: Int get() = obj.optInt("tool_descriptor_tokens", 0)
    public val toolResultTokens: Int get() = obj.optInt("tool_result_tokens", 0)
    public val toolCallTokens: Int get() = obj.optInt("tool_call_tokens", 0)
    public val attachmentTokens: Int get() = obj.optInt("attachment_tokens", 0)
    public val imageTokens: Int get() = obj.optInt("image_tokens", 0)
    public val responseReserveTokens: Int get() = obj.optInt("response_reserve_tokens", 0)
    public val totalTokens: Int get() = obj.optInt("total_tokens", 0)

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): ContextTokenBreakdown =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): ContextTokenBreakdown =
            ContextTokenBreakdown(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): ContextTokenBreakdown =
            fromJsonObject(JSONObject(map))
    }
}

public class ContextBudgetStatus(rawJson: String) : RawJsonModel(rawJson) {
    public val source: String get() = obj.optString("source")
    public val provider: String get() = obj.optString("provider")
    public val model: String get() = obj.optString("model")
    public val route: String get() = obj.optString("route", "fits")
    public val shouldCompact: Boolean get() = obj.optBoolean("should_compact", false)
    public val estimatedPromptTokens: Int get() = obj.optInt("estimated_prompt_tokens", 0)
    public val contextTokenBudget: Int get() = obj.optInt("context_token_budget", 0)
    public val nativeContextWindowTokens: Int
        get() = obj.optNullableInt("native_context_window_tokens") ?: contextTokenBudget
    public val nativeContextWindowSource: String get() = obj.optString("native_context_window_source", "unknown")
    public val effectiveContextWindowTokens: Int
        get() = obj.optNullableInt("effective_context_window_tokens") ?: contextTokenBudget
    public val effectiveContextWindowSource: String get() = obj.optString("effective_context_window_source", "unknown")
    public val responseReserveSource: String get() = obj.optString("response_reserve_source", "unknown")
    public val providerMetadataFetchedAt: String? get() = obj.optNullableString("provider_metadata_fetched_at")
    public val providerMetadataStale: Boolean get() = obj.optBoolean("provider_metadata_stale", false)
    public val providerMetadataError: String? get() = obj.optNullableString("provider_metadata_error")
    public val promptBudgetBeforeReserve: Int get() = obj.optInt("prompt_budget_before_reserve", 0)
    public val reserveTokens: Int get() = obj.optInt("reserve_tokens", 0)
    public val effectiveReserveTokens: Int get() = obj.optInt("effective_reserve_tokens", 0)
    public val remainingPromptBudgetTokens: Int get() = obj.optInt("remaining_prompt_budget_tokens", 0)
    public val overflowTokens: Int get() = obj.optInt("overflow_tokens", 0)
    public val toolResultReducibleChars: Int get() = obj.optInt("tool_result_reducible_chars", 0)
    public val toolResultReducibleTokens: Int get() = obj.optInt("tool_result_reducible_tokens", 0)
    public val contextGuardStatus: String get() = obj.optString("context_guard_status", "unknown")
    public val contextGuardReason: String get() = obj.optString("context_guard_reason", "")
    public val messageCount: Int get() = obj.optInt("message_count", 0)
    public val unwindowedMessageCount: Int get() = obj.optInt("unwindowed_message_count", 0)
    public val updatedAt: String get() = obj.optString("updated_at")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): ContextBudgetStatus =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): ContextBudgetStatus =
            ContextBudgetStatus(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): ContextBudgetStatus =
            fromJsonObject(JSONObject(map))
    }
}

public class ContextStatus(rawJson: String) : RawJsonModel(rawJson) {
    public val threadId: String get() = obj.optString("thread_id", obj.optString("threadId"))
    public val engine: String get() = obj.optString("engine", "compressor")
    public val summaryPresent: Boolean get() = obj.optBoolean("summary_present", obj.optBoolean("summaryPresent", false))
    public val compactionCount: Int get() = obj.optInt("compaction_count", 0)
    public val tokensBefore: Int get() = obj.optInt("tokens_before", 0)
    public val tokensAfter: Int get() = obj.optInt("tokens_after", 0)
    public val estimatedTokens: Int get() = obj.optInt("estimated_tokens", 0)
    public val contextWindowTokens: Int get() = obj.optInt("context_window_tokens", 0)
    public val triggerTokens: Int get() = obj.optInt("trigger_tokens", 0)
    public val targetTokens: Int get() = obj.optInt("target_tokens", 0)
    public val responseReserveTokens: Int get() = obj.optInt("response_reserve_tokens", 0)
    public val usagePercent: Double get() = obj.optDouble("usage_percent", 0.0)
    public val triggerRatio: Double get() = obj.optDouble("trigger_ratio", 0.0)
    public val targetRatio: Double get() = obj.optDouble("target_ratio", 0.0)
    public val lastCompactedAt: String? get() = obj.optNullableString("last_compacted_at")
    public val displayUsedTokens: Int get() = obj.optNullableInt("display_used_tokens") ?: estimatedTokens
    public val displaySource: String get() = obj.optString("display_source", "legacy")
    public val lastPromptTokens: Int? get() = obj.optNullableInt("last_prompt_tokens")
    public val preflightEstimatedTokens: Int? get() = obj.optNullableInt("preflight_estimated_tokens")
    public val cacheReadTokens: Int get() = obj.optInt("cache_read_tokens", 0)
    public val cacheWriteTokens: Int get() = obj.optInt("cache_write_tokens", 0)
    public val contextWindowSource: String get() = obj.optString("context_window_source", "unknown")
    public val nativeContextWindowTokens: Int
        get() = obj.optNullableInt("native_context_window_tokens") ?: contextWindowTokens
    public val nativeContextWindowSource: String get() = obj.optString("native_context_window_source", "unknown")
    public val effectiveContextWindowTokens: Int
        get() = obj.optNullableInt("effective_context_window_tokens") ?: contextWindowTokens
    public val effectiveContextWindowSource: String
        get() = obj.optNullableString("effective_context_window_source") ?: contextWindowSource
    public val responseReserveSource: String get() = obj.optString("response_reserve_source", "unknown")
    public val providerMetadataFetchedAt: String? get() = obj.optNullableString("provider_metadata_fetched_at")
    public val providerMetadataStale: Boolean get() = obj.optBoolean("provider_metadata_stale", false)
    public val providerMetadataError: String? get() = obj.optNullableString("provider_metadata_error")
    public val contextGuardStatus: String get() = obj.optString("context_guard_status", "unknown")
    public val contextGuardReason: String get() = obj.optString("context_guard_reason", "")
    public val contextRoute: String
        get() = obj.optNullableString("context_route")
            ?: obj.optJSONObject("context_budget_status")?.optNullableString("route")
            ?: "fits"
    public val overflowTokens: Int get() = obj.optInt("overflow_tokens", 0)
    public val breakdown: ContextTokenBreakdown?
        get() = obj.optJSONObject("breakdown")?.let { ContextTokenBreakdown(it.toString()) }
    public val contextBudgetStatus: ContextBudgetStatus?
        get() = obj.optJSONObject("context_budget_status")?.let { ContextBudgetStatus(it.toString()) }
    public val updatedAt: String? get() = obj.optNullableString("updated_at")
    public val fresh: Boolean get() = obj.optBoolean("fresh", false)
    public val currentWindowTokens: Int
        get() = obj.optNullableInt("current_window_tokens") ?: displayUsedTokens
    public val transcriptEstimatedTokens: Int
        get() = obj.optNullableInt("transcript_estimated_tokens") ?: estimatedTokens
    public val lastContextDeltaTokens: Int get() = obj.optInt("last_context_delta_tokens", 0)
    public val lastContextDeltaReason: String get() = obj.optString("last_context_delta_reason", "stable")
    public val toolResultPrunedTokens: Int get() = obj.optInt("tool_result_pruned_tokens", 0)
    public val toolResultPrunedChars: Int get() = obj.optInt("tool_result_pruned_chars", 0)
    public val contextDisplayLabel: String get() = obj.optString("context_display_label", "current_window")
    public val compactionStrategy: String get() = obj.optString("compaction_strategy", "llm_summary")
    public val lastCompactionDurationMs: Int? get() = obj.optNullableInt("last_compaction_duration_ms")
    public val adaptiveChunkCount: Int get() = obj.optInt("adaptive_chunk_count", 0)
    public val oversizedMessageCount: Int get() = obj.optInt("oversized_message_count", 0)
    public val protectedTailTokens: Int get() = obj.optInt("protected_tail_tokens", 0)
    public val overflowRetryAttemptedAt: String? get() = obj.optNullableString("overflow_retry_attempted_at")
    public val overflowRetrySucceeded: Boolean? get() = obj.optNullableBoolean("overflow_retry_succeeded")
    public val overflowRetryReason: String? get() = obj.optNullableString("overflow_retry_reason")
    public val overflowRetryError: String? get() = obj.optNullableString("overflow_retry_error")
    public val preCompactionMemoryFlushEnabled: Boolean
        get() = obj.optBoolean("pre_compaction_memory_flush_enabled", false)
    public val preCompactionMemoryFlushStatus: String?
        get() = obj.optNullableString("pre_compaction_memory_flush_status")
    public val error: String? get() = obj.optNullableString("error")
    public val hasError: Boolean get() = !error.isNullOrEmpty()
    public val isNearTrigger: Boolean get() = triggerTokens > 0 && displayUsedTokens >= triggerTokens
    public val usageFraction: Double get() =
        if (contextWindowTokens <= 0) 0.0 else displayUsedTokens.toDouble() / contextWindowTokens.toDouble()
    public val isProviderBacked: Boolean get() = displaySource == "provider"
    public val isPreflightEstimate: Boolean get() = displaySource == "preflight"
    public val isLegacyEstimate: Boolean get() = displaySource == "legacy"
    public val isBudgetBlocked: Boolean get() = contextGuardStatus == "blocked"
    public val isBudgetWarning: Boolean get() = contextGuardStatus == "warning"

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): ContextStatus =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): ContextStatus =
            ContextStatus(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): ContextStatus =
            fromJsonObject(JSONObject(map))
    }
}

public enum class SessionRunRecordStatus(public val wireName: String) {
    Running("running"),
    Succeeded("succeeded"),
    Failed("failed"),
    Cancelled("cancelled"),
    Stalled("stalled"),
    Lost("lost"),
    Unverified("unverified"),
    Unknown("unknown"),
    ;

    public companion object {
        public fun fromWire(value: String?): SessionRunRecordStatus =
            entries.firstOrNull { it.wireName == value } ?: Unknown

        public fun flutterParityWireNames(): Set<String> = entries.map { it.wireName }.toSet()
    }
}

public enum class RunEvidenceKind(public val wireName: String) {
    ReplyOnly("reply_only"),
    ToolObserved("tool_observed"),
    SideEffectObserved("side_effect_observed"),
    DetachedTaskObserved("detached_task_observed"),
    Unknown("unknown"),
    ;

    public companion object {
        public fun fromWire(value: String?): RunEvidenceKind =
            entries.firstOrNull { it.wireName == value } ?: Unknown

        public fun flutterParityWireNames(): Set<String> = entries.map { it.wireName }.toSet()
    }
}

public enum class RunVerification(public val wireName: String) {
    NotRequired("not_required"),
    Verified("verified"),
    Unverified("unverified"),
    Failed("failed"),
    Unknown("unknown"),
    ;

    public companion object {
        public fun fromWire(value: String?): RunVerification =
            entries.firstOrNull { it.wireName == value } ?: Unknown

        public fun flutterParityWireNames(): Set<String> = entries.map { it.wireName }.toSet()
    }
}

public data class RunEvidence(
    val kind: RunEvidenceKind,
    val source: String,
    val effect: String? = null,
    val isError: Boolean = false,
    val digest: String? = null,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("kind", kind.wireName)
        .put("source", source)
        .put("isError", isError)
        .apply {
            effect?.let { put("effect", it) }
            digest?.let { put("digest", it) }
        }

    public fun toJson(): String = toJsonObject().toString()

    public companion object {
        public fun fromJson(rawJson: String): RunEvidence =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): RunEvidence =
            RunEvidence(
                kind = RunEvidenceKind.fromWire(obj.optString("kind")),
                source = obj.optString("source"),
                effect = obj.optNullableString("effect"),
                isError = obj.optBoolean("isError", obj.optBoolean("is_error", false)),
                digest = obj.optNullableString("digest"),
            )
    }
}

public data class SessionRunRecord(
    val runId: String,
    val status: SessionRunRecordStatus,
    val agentId: String,
    val sessionKey: String,
    val threadId: String,
    val startedAt: Long,
    val completedAt: Long? = null,
    val durationMs: Long? = null,
    val evidenceKind: RunEvidenceKind,
    val verification: RunVerification,
    val toolCallCount: Int = 0,
    val evidence: List<RunEvidence> = emptyList(),
    val summary: String? = null,
    val error: String? = null,
    val parentRunId: String? = null,
    val childRunIds: List<String> = emptyList(),
    override val rawJson: String,
) : NapaxiJsonModel(rawJson) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("runId", runId)
        .put("status", status.wireName)
        .put("agentId", agentId)
        .put("sessionKey", sessionKey)
        .put("threadId", threadId)
        .put("startedAt", startedAt)
        .put("evidenceKind", evidenceKind.wireName)
        .put("verification", verification.wireName)
        .put("toolCallCount", toolCallCount)
        .put("evidence", JSONArray(evidence.map { it.toJsonObject() }))
        .apply {
            completedAt?.let { put("completedAt", it) }
            durationMs?.let { put("durationMs", it) }
            summary?.let { put("summary", it) }
            error?.let { put("error", it) }
            parentRunId?.let { put("parentRunId", it) }
            if (childRunIds.isNotEmpty()) put("childRunIds", JSONArray(childRunIds))
        }

    public fun toJson(): String = toJsonObject().toString()

    public companion object {
        public fun fromJson(rawJson: String): SessionRunRecord =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }), rawJson)

        public fun fromJsonOrNull(rawJson: String): SessionRunRecord? {
            val trimmed = rawJson.trim()
            if (trimmed.isEmpty() || trimmed == "null") return null
            val obj = runCatching { JSONObject(trimmed) }.getOrNull() ?: return null
            if (!obj.isNull("error")) return null
            return fromJsonObject(obj, trimmed)
        }

        public fun fromJsonObject(obj: JSONObject, rawJson: String = obj.toString()): SessionRunRecord =
            SessionRunRecord(
                runId = obj.optString("runId", obj.optString("run_id")),
                status = SessionRunRecordStatus.fromWire(obj.optString("status")),
                agentId = obj.optString("agentId", obj.optString("agent_id")),
                sessionKey = obj.optString("sessionKey", obj.optString("session_key")),
                threadId = obj.optString("threadId", obj.optString("thread_id")),
                startedAt = obj.optNullableLong("startedAt") ?: obj.optNullableLong("started_at") ?: 0L,
                completedAt = obj.optNullableLong("completedAt") ?: obj.optNullableLong("completed_at"),
                durationMs = obj.optNullableLong("durationMs") ?: obj.optNullableLong("duration_ms"),
                evidenceKind = RunEvidenceKind.fromWire(
                    obj.optString("evidenceKind", obj.optString("evidence_kind")),
                ),
                verification = RunVerification.fromWire(obj.optString("verification")),
                toolCallCount = obj.optInt("toolCallCount", obj.optInt("tool_call_count", 0)),
                evidence = obj.optJSONArray("evidence")
                    ?.toJsonObjectList()
                    ?.map(RunEvidence::fromJsonObject)
                    .orEmpty(),
                summary = obj.optNullableString("summary"),
                error = obj.optNullableString("error"),
                parentRunId = obj.optNullableString("parentRunId") ?: obj.optNullableString("parent_run_id"),
                childRunIds = (
                    obj.optJSONArray("childRunIds")
                        ?: obj.optJSONArray("child_run_ids")
                    )?.toStringList().orEmpty(),
                rawJson = rawJson,
            )
    }
}

public fun decodeSessionRunRecords(rawJson: String): List<SessionRunRecord> =
    rawJson.parseJsonArrayOrObjectList("runs").map { SessionRunRecord.fromJsonObject(it) }

public enum class SessionRunStatus(public val wireName: String) {
    Running("running"),
    WaitingForInput("waiting_for_input"),
    Cancelling("cancelling"),
    Completed("completed"),
    Failed("failed"),
    Cancelled("cancelled"),
    ;

    public companion object {
        public fun fromWire(value: String?): SessionRunStatus =
            entries.firstOrNull { it.wireName == value } ?: Running
    }
}

public class SessionRunInfo(rawJson: String) : RawJsonModel(rawJson) {
    public val key: SessionKey
        get() {
            val keyObj = obj.optJSONObject("key") ?: JSONObject()
            return SessionKey(
                channelType = keyObj.optString("channel_type", obj.optString("channel_type", "app")),
                accountId = keyObj.optString("account_id", obj.optString("account_id")),
                threadId = keyObj.optString("thread_id", obj.optString("thread_id")),
            )
        }
    public val agentId: String get() = obj.optString("agent_id", NapaxiEngine.DEFAULT_AGENT_ID)
    public val status: SessionRunStatus get() = SessionRunStatus.fromWire(obj.optString("status"))
    public val activity: String get() = obj.optString("activity", obj.optString("status"))
    public val humanRequestId: String? get() = obj.optNullableString("human_request_id")
    public val error: String? get() = obj.optNullableString("error")
    public val startedAt: Long get() = obj.optLong("started_at", 0L)
    public val updatedAt: Long get() = obj.optLong("updated_at", startedAt)
    public val runId: String get() = obj.optString("run_id", obj.optString("id", id))
    public val id: String get() = "$agentId:${key.channelType}:${key.accountId}:${key.threadId}"
    public val isTerminal: Boolean
        get() = status == SessionRunStatus.Completed ||
            status == SessionRunStatus.Failed ||
            status == SessionRunStatus.Cancelled
    public val needsInput: Boolean get() = obj.optBoolean("needs_input", false)

    public fun copyWith(
        status: SessionRunStatus? = null,
        activity: String? = null,
        humanRequestId: String? = null,
        clearHumanRequest: Boolean = false,
        error: String? = null,
        clearError: Boolean = false,
        updatedAt: Long = System.currentTimeMillis(),
    ): SessionRunInfo {
        val next = JSONObject(rawJson)
        status?.let { next.put("status", it.wireName) }
        activity?.let { next.put("activity", it) }
        when {
            clearHumanRequest -> next.remove("human_request_id")
            humanRequestId != null -> next.put("human_request_id", humanRequestId)
        }
        when {
            clearError -> next.remove("error")
            error != null -> next.put("error", error)
        }
        next.put("needs_input", (status ?: this.status) == SessionRunStatus.WaitingForInput)
        next.put("updated_at", updatedAt)
        return SessionRunInfo(next.toString())
    }

    public companion object {
        public fun create(
            key: SessionKey,
            agentId: String,
            status: SessionRunStatus = SessionRunStatus.Running,
            activity: String = "Starting",
            now: Long = System.currentTimeMillis(),
        ): SessionRunInfo {
            val id = "$agentId:${key.channelType}:${key.accountId}:${key.threadId}"
            return SessionRunInfo(
                JSONObject()
                    .put("id", id)
                    .put("run_id", id)
                    .put("agent_id", agentId)
                    .put("key", key.toJsonObject())
                    .put("status", status.wireName)
                    .put("activity", activity)
                    .put("needs_input", status == SessionRunStatus.WaitingForInput)
                    .put("started_at", now)
                    .put("updated_at", now)
                    .toString(),
            )
        }
    }
}
public enum class ToolFilter(public val wireName: String) {
    All("AllTools"),
    Allowlist("Allowlist"),
    Denylist("Denylist"),
    ;

    public companion object {
        public fun fromWire(value: String?): ToolFilter =
            entries.firstOrNull { it.wireName == value } ?: All
    }
}

public class AgentDefinition(rawJson: String) : RawJsonModel(rawJson) {
    private val toolFilterObject: JSONObject get() = obj.optJSONObject("tool_filter") ?: JSONObject()
    public val id: String get() = obj.optString("id")
    public val name: String get() = obj.optString("name")
    public val description: String get() = obj.optString("description")
    public val systemPrompt: String get() = obj.optString("system_prompt")
    public val provider: String? get() = obj.optNullableString("provider")
    public val model: String? get() = obj.optNullableString("model")
    public val modelProfileId: String? get() = obj.optNullableString("model_profile_id")
    public val engineId: String get() = obj.optString("engine_id", "napaxi_core")
    public val engineProfileId: String get() = obj.optString("engine_profile_id", "")
    public val engineConfig: JSONObject get() = obj.optJSONObject("engine_config") ?: JSONObject()
    public val toolFilter: ToolFilter get() = ToolFilter.fromWire(toolFilterObject.optString("type", "AllTools"))
    public val toolList: List<String>? get() = toolFilterObject.optJSONArray("tools")?.toStringList()
    public val icon: String? get() = obj.optNullableString("icon")
    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun create(
            id: String,
            name: String,
            description: String = "",
            systemPrompt: String = "",
            provider: String? = null,
            model: String? = null,
            modelProfileId: String? = null,
            engineId: String = "napaxi_core",
            engineProfileId: String = "",
            engineConfig: JSONObject? = null,
            toolFilter: ToolFilter = ToolFilter.All,
            toolList: List<String>? = null,
            icon: String? = null,
        ): AgentDefinition =
            AgentDefinition(
                JSONObject()
                    .put("id", id)
                    .put("name", name)
                    .put("description", description)
                    .put("system_prompt", systemPrompt)
                    .put(
                        "tool_filter",
                        JSONObject()
                            .put("type", toolFilter.wireName)
                            .apply {
                                toolList?.let { put("tools", JSONArray(it)) }
                            },
                    )
                    .apply {
                        provider?.takeIf { it.isNotBlank() }?.let { put("provider", it) }
                        model?.takeIf { it.isNotBlank() }?.let { put("model", it) }
                        modelProfileId?.takeIf { it.isNotBlank() }?.let { put("model_profile_id", it) }
                        put("engine_id", engineId.ifBlank { "napaxi_core" })
                        engineProfileId.takeIf { it.isNotBlank() }?.let { put("engine_profile_id", it) }
                        engineConfig?.takeIf { it.length() > 0 }?.let { put("engine_config", it) }
                        icon?.takeIf { it.isNotBlank() }?.let { put("icon", it) }
                    }
                    .toString(),
            )

        @JvmStatic
        public fun fromFields(
            id: String,
            name: String,
            description: String = "",
            systemPrompt: String = "",
            provider: String? = null,
            model: String? = null,
            modelProfileId: String? = null,
            engineId: String = "napaxi_core",
            engineProfileId: String = "",
            engineConfig: JSONObject? = null,
            toolFilter: ToolFilter = ToolFilter.All,
            toolList: List<String>? = null,
            icon: String? = null,
        ): AgentDefinition =
            create(
                id = id,
                name = name,
                description = description,
                systemPrompt = systemPrompt,
                provider = provider,
                model = model,
                modelProfileId = modelProfileId,
                engineId = engineId,
                engineProfileId = engineProfileId,
                engineConfig = engineConfig,
                toolFilter = toolFilter,
                toolList = toolList,
                icon = icon,
            )

        @JvmStatic
        public fun fromJson(rawJson: String): AgentDefinition =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AgentDefinition =
            AgentDefinition(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AgentDefinition =
            fromJsonObject(JSONObject(map))
    }
}
public const val NAPAXI_CORE_AGENT_ENGINE_ID: String = "napaxi_core"
public const val EXTERNAL_HOST_AGENT_ENGINE_ID: String = "external_host"

public interface AgentEngineExecutor {
    public suspend fun startTurn(
        request: AgentEngineTurnRequest,
        tools: AgentEngineToolBroker,
    ): AgentEngineTurnResult {
        throw UnsupportedOperationException("Android AgentEngineExecutor is unsupported in v1")
    }

    public suspend fun cancel(runId: String, sessionKeyJson: String): Boolean = false

    public suspend fun resume(
        request: AgentEngineTurnRequest,
        tools: AgentEngineToolBroker,
    ): AgentEngineTurnResult =
        AgentEngineTurnResult.error("Agent engine resume is unsupported")
}

public class AgentEngineTurnRequest(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val engineId: String get() = obj.optString("engine_id", EXTERNAL_HOST_AGENT_ENGINE_ID)
    public val engineProfileId: String get() = obj.optString("engine_profile_id", "")
    public val engineConfig: JSONObject get() = obj.optJSONObject("engine_config") ?: JSONObject()
    public val runId: String get() = obj.optString("run_id")
    public val filesDir: String get() = obj.optString("files_dir")
    public val workspaceFilesDir: String get() = obj.optString("workspace_files_dir")
    public val accountId: String get() = obj.optString("account_id")
    public val agentId: String get() = obj.optString("agent_id")
    public val sessionKeyJson: String get() = obj.optString("session_key_json", "{}")
    public val message: String get() = obj.optString("message")
    public val attachmentsJson: String get() = obj.optString("attachments_json", "[]")
    public val configJson: String get() = obj.optString("config_json", "{}")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AgentEngineTurnRequest =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AgentEngineTurnRequest =
            AgentEngineTurnRequest(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AgentEngineTurnRequest =
            fromJsonObject(JSONObject(map))
    }
}

public class AgentEngineTurnResult(rawJson: String = """{"events":[]}""") : RawJsonModel(rawJson) {
    public val events: JSONArray get() = obj.optJSONArray("events") ?: JSONArray()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun response(content: String): AgentEngineTurnResult =
            AgentEngineTurnResult(
                JSONObject()
                    .put("events", JSONArray().put(JSONObject().put("type", "response").put("content", content)))
                    .toString(),
            )

        @JvmStatic
        public fun error(message: String): AgentEngineTurnResult =
            AgentEngineTurnResult(
                JSONObject()
                    .put("events", JSONArray().put(JSONObject().put("type", "error").put("message", message)))
                    .toString(),
            )

        @JvmStatic
        public fun fromJson(rawJson: String): AgentEngineTurnResult =
            fromJsonObject(JSONObject(rawJson.ifBlank { """{"events":[]}""" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AgentEngineTurnResult =
            AgentEngineTurnResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AgentEngineTurnResult =
            fromJsonObject(JSONObject(map))
    }
}

public class AgentEngineRunEventRequest(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val runId: String get() = obj.optString("run_id")
    public val sessionKeyJson: String get() = obj.optString("session_key_json")
    public val event: JSONObject get() = obj.optJSONObject("event") ?: JSONObject()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun create(
            runId: String,
            sessionKeyJson: String = "",
            event: JSONObject = JSONObject(),
        ): AgentEngineRunEventRequest =
            fromJsonObject(
                JSONObject()
                    .put("run_id", runId)
                    .put("session_key_json", sessionKeyJson)
                    .put("event", event),
            )

        @JvmStatic
        public fun fromJson(rawJson: String): AgentEngineRunEventRequest =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AgentEngineRunEventRequest =
            AgentEngineRunEventRequest(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AgentEngineRunEventRequest =
            fromJsonObject(JSONObject(map))
    }
}

public class AgentEngineRunEventResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val event: JSONObject get() = obj.optJSONObject("event") ?: JSONObject()
    public val finalContent: String get() = obj.optString("final_content")
    public val isError: Boolean get() = obj.optBoolean("is_error", false)
    public val completed: Boolean get() = obj.optBoolean("completed", false)

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AgentEngineRunEventResult =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AgentEngineRunEventResult =
            AgentEngineRunEventResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AgentEngineRunEventResult =
            fromJsonObject(JSONObject(map))
    }
}

public class AgentEngineToolBroker {
    public suspend fun listTools(
        agentId: String,
        accountId: String,
        sessionKeyJson: String? = null,
    ): List<CustomToolDef> {
        throw UnsupportedOperationException("Android AgentEngineToolBroker is unsupported in v1")
    }

    public suspend fun callTool(
        callId: String,
        name: String,
        arguments: JSONObject,
        agentId: String,
        accountId: String,
        sessionKeyJson: String? = null,
    ): AgentEngineToolCallResult {
        throw UnsupportedOperationException("Android AgentEngineToolBroker is unsupported in v1")
    }
}

public class AgentEngineToolCallResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val output: String get() = obj.optString("output")
    public val isError: Boolean get() = obj.optBoolean("is_error", false)
    public val events: JSONArray get() = obj.optJSONArray("events") ?: JSONArray()
    public val effect: String get() = obj.optString("effect", "unknown")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AgentEngineToolCallResult =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AgentEngineToolCallResult =
            AgentEngineToolCallResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AgentEngineToolCallResult =
            fromJsonObject(JSONObject(map))
    }
}

public fun agentEngineRunEvent(
    runId: String,
    sessionKeyJson: String = "",
    event: JSONObject,
): AgentEngineRunEventResult {
    throw UnsupportedOperationException("Android agent engine run/event is unsupported in v1")
}
public class ToolInfo(rawJson: String) : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val description: String get() = obj.optString("description")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): ToolInfo = ToolInfo(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): ToolInfo = ToolInfo(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): ToolInfo = fromJsonObject(JSONObject(map))
    }
}
public class NapaxiCapabilityDefinition(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        id: String,
        kind: String,
        version: String,
        platforms: List<String>,
        configSchema: JSONObject,
        risk: String,
        requirements: List<String>,
        defaultEnabled: Boolean,
        activation: String,
    ) : this(
        JSONObject()
            .put("id", id)
            .put("kind", kind)
            .put("version", version)
            .put("platforms", JSONArray(platforms))
            .put("config_schema", configSchema)
            .put("risk", risk)
            .put("requirements", JSONArray(requirements))
            .put("default_enabled", defaultEnabled)
            .put("activation", activation)
            .toString(),
    )

    public val id: String get() = obj.optString("id")
    public val kind: String get() = obj.optString("kind")
    public val version: String get() = obj.optString("version")
    public val platforms: List<String> get() = obj.optJSONArray("platforms")?.toStringList().orEmpty()
    public val configSchema: JSONObject get() = obj.optJSONObject("config_schema") ?: JSONObject()
    public val risk: String get() = obj.optString("risk")
    public val requirements: List<String> get() = obj.optJSONArray("requirements")?.toStringList().orEmpty()
    public val defaultEnabled: Boolean get() = obj.optBoolean("default_enabled", false)
    public val activation: String get() = obj.optString("activation")

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("id", id)
        .put("kind", kind)
        .put("version", version)
        .put("platforms", JSONArray(platforms))
        .put("config_schema", configSchema)
        .put("risk", risk)
        .put("requirements", JSONArray(requirements))
        .put("default_enabled", defaultEnabled)
        .put("activation", activation)

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiCapabilityDefinition =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiCapabilityDefinition =
            NapaxiCapabilityDefinition(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiCapabilityDefinition =
            fromJsonObject(JSONObject(map))
    }
}
public class NapaxiCapabilityStatus(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        definition: NapaxiCapabilityDefinition,
        registered: Boolean,
        available: Boolean,
        enabled: Boolean,
        unavailableReason: String? = null,
    ) : this(
        JSONObject()
            .put("definition", definition.toJsonObject())
            .put("registered", registered)
            .put("available", available)
            .put("enabled", enabled)
            .apply {
                unavailableReason?.let { put("unavailable_reason", it) }
            }
            .toString(),
    )

    public val definition: NapaxiCapabilityDefinition
        get() = NapaxiCapabilityDefinition((obj.optJSONObject("definition") ?: JSONObject()).toString())
    public val registered: Boolean get() = obj.optBoolean("registered", false)
    public val available: Boolean get() = obj.optBoolean("available", false)
    public val enabled: Boolean get() = obj.optBoolean("enabled", false)
    public val unavailableReason: String? get() = obj.optNullableString("unavailable_reason")

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("definition", definition.toJsonObject())
        .put("registered", registered)
        .put("available", available)
        .put("enabled", enabled)
        .apply {
            unavailableReason?.let { put("unavailable_reason", it) }
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiCapabilityStatus =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiCapabilityStatus =
            NapaxiCapabilityStatus(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiCapabilityStatus =
            fromJsonObject(JSONObject(map))
    }
}
public fun decodeCapabilityDefinitions(rawJson: String): List<NapaxiCapabilityDefinition> =
    rawJson.parseJsonArrayOrObjectList("definitions").map { NapaxiCapabilityDefinition.fromJsonObject(it) }

public fun decodeCapabilityStatuses(rawJson: String): List<NapaxiCapabilityStatus> =
    rawJson.parseJsonArrayOrObjectList("statuses").map { NapaxiCapabilityStatus.fromJsonObject(it) }

public class NapaxiScenarioSettingsContribution(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        id: String,
        capabilityId: String,
        placement: String = "",
        title: String = "",
        description: String = "",
        schema: JSONObject = JSONObject(),
        actions: List<String> = emptyList(),
    ) : this(
        JSONObject()
            .put("id", id)
            .put("capability_id", capabilityId)
            .put("placement", placement)
            .put("title", title)
            .put("description", description)
            .put("schema", schema)
            .put("actions", JSONArray(actions))
            .toString(),
    )

    public val id: String get() = obj.optString("id")
    public val capabilityId: String get() = obj.optString("capability_id")
    public val placement: String get() = obj.optString("placement")
    public val title: String get() = obj.optString("title")
    public val description: String get() = obj.optString("description")
    public val schema: JSONObject get() = obj.optJSONObject("schema") ?: JSONObject()
    public val actions: List<String> get() = obj.optJSONArray("actions")?.toStringList().orEmpty()

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("id", id)
        .put("capability_id", capabilityId)
        .put("placement", placement)
        .put("title", title)
        .put("description", description)
        .put("schema", schema)
        .put("actions", JSONArray(actions))

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiScenarioSettingsContribution =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiScenarioSettingsContribution =
            NapaxiScenarioSettingsContribution(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiScenarioSettingsContribution =
            fromJsonObject(JSONObject(map))
    }
}

public class NapaxiScenarioUiContribution(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        id: String,
        capabilityId: String,
        placement: String = "",
        title: String = "",
        description: String = "",
        icon: String = "",
        renderer: String,
        dataSources: JSONObject = JSONObject(),
        actions: List<String> = emptyList(),
    ) : this(
        JSONObject()
            .put("id", id)
            .put("capability_id", capabilityId)
            .put("placement", placement)
            .put("title", title)
            .put("description", description)
            .put("icon", icon)
            .put("renderer", renderer)
            .put("data_sources", dataSources)
            .put("actions", JSONArray(actions))
            .toString(),
    )

    public val id: String get() = obj.optString("id")
    public val capabilityId: String get() = obj.optString("capability_id")
    public val placement: String get() = obj.optString("placement")
    public val title: String get() = obj.optString("title")
    public val description: String get() = obj.optString("description")
    public val icon: String get() = obj.optString("icon")
    public val renderer: String get() = obj.optString("renderer")
    public val dataSources: JSONObject get() = obj.optJSONObject("data_sources") ?: JSONObject()
    public val actions: List<String> get() = obj.optJSONArray("actions")?.toStringList().orEmpty()

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("id", id)
        .put("capability_id", capabilityId)
        .put("placement", placement)
        .put("title", title)
        .put("description", description)
        .put("icon", icon)
        .put("renderer", renderer)
        .put("data_sources", dataSources)
        .put("actions", JSONArray(actions))

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiScenarioUiContribution =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiScenarioUiContribution =
            NapaxiScenarioUiContribution(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiScenarioUiContribution =
            fromJsonObject(JSONObject(map))
    }
}

public class NapaxiScenarioPack(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        id: String,
        version: String,
        label: String,
        description: String,
        risk: String,
        activation: String,
        executionPlanes: List<String> = emptyList(),
        requiredCapabilities: List<String> = emptyList(),
        recommendedCapabilities: List<String> = emptyList(),
        optionalCapabilities: List<String> = emptyList(),
        uiSurfaces: List<String> = emptyList(),
        settingsContributions: List<NapaxiScenarioSettingsContribution> = emptyList(),
        uiContributions: List<NapaxiScenarioUiContribution> = emptyList(),
        memoryScopes: List<String> = emptyList(),
        tags: List<String> = emptyList(),
    ) : this(
        JSONObject()
            .put("id", id)
            .put("version", version)
            .put("label", label)
            .put("description", description)
            .put("risk", risk)
            .put("activation", activation)
            .put("execution_planes", JSONArray(executionPlanes))
            .put("required_capabilities", JSONArray(requiredCapabilities))
            .put("recommended_capabilities", JSONArray(recommendedCapabilities))
            .put("optional_capabilities", JSONArray(optionalCapabilities))
            .put("ui_surfaces", JSONArray(uiSurfaces))
            .put("settings_contributions", JSONArray(settingsContributions.map { it.toJsonObject() }))
            .put("ui_contributions", JSONArray(uiContributions.map { it.toJsonObject() }))
            .put("memory_scopes", JSONArray(memoryScopes))
            .put("tags", JSONArray(tags))
            .toString(),
    )

    public val id: String get() = obj.optString("id")
    public val version: String get() = obj.optString("version")
    public val label: String get() = obj.optString("label")
    public val description: String get() = obj.optString("description")
    public val risk: String get() = obj.optString("risk")
    public val activation: String get() = obj.optString("activation")
    public val executionPlanes: List<String> get() = obj.optJSONArray("execution_planes")?.toStringList().orEmpty()
    public val requiredCapabilities: List<String> get() = obj.optJSONArray("required_capabilities")?.toStringList().orEmpty()
    public val recommendedCapabilities: List<String> get() = obj.optJSONArray("recommended_capabilities")?.toStringList().orEmpty()
    public val optionalCapabilities: List<String> get() = obj.optJSONArray("optional_capabilities")?.toStringList().orEmpty()
    public val uiSurfaces: List<String> get() = obj.optJSONArray("ui_surfaces")?.toStringList().orEmpty()
    public val settingsContributions: List<NapaxiScenarioSettingsContribution>
        get() = obj.optJSONArray("settings_contributions")
            ?.toJsonObjectList()
            ?.map { NapaxiScenarioSettingsContribution.fromJsonObject(it) }
            .orEmpty()
    public val uiContributions: List<NapaxiScenarioUiContribution>
        get() = obj.optJSONArray("ui_contributions")
            ?.toJsonObjectList()
            ?.map { NapaxiScenarioUiContribution.fromJsonObject(it) }
            .orEmpty()
    public val memoryScopes: List<String> get() = obj.optJSONArray("memory_scopes")?.toStringList().orEmpty()
    public val tags: List<String> get() = obj.optJSONArray("tags")?.toStringList().orEmpty()

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("id", id)
        .put("version", version)
        .put("label", label)
        .put("description", description)
        .put("risk", risk)
        .put("activation", activation)
        .put("execution_planes", JSONArray(executionPlanes))
        .put("required_capabilities", JSONArray(requiredCapabilities))
        .put("recommended_capabilities", JSONArray(recommendedCapabilities))
        .put("optional_capabilities", JSONArray(optionalCapabilities))
        .put("ui_surfaces", JSONArray(uiSurfaces))
        .put("settings_contributions", JSONArray(settingsContributions.map { it.toJsonObject() }))
        .put("ui_contributions", JSONArray(uiContributions.map { it.toJsonObject() }))
        .put("memory_scopes", JSONArray(memoryScopes))
        .put("tags", JSONArray(tags))

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiScenarioPack =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiScenarioPack =
            NapaxiScenarioPack(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiScenarioPack =
            fromJsonObject(JSONObject(map))
    }
}

public class NapaxiScenarioStatus(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        definition: NapaxiScenarioPack,
        registered: Boolean,
        available: Boolean,
        enabled: Boolean,
        missingRequiredCapabilities: List<String> = emptyList(),
        disabledRequiredCapabilities: List<String> = emptyList(),
        unavailableReasons: List<String> = emptyList(),
    ) : this(
        JSONObject()
            .put("definition", definition.toJsonObject())
            .put("registered", registered)
            .put("available", available)
            .put("enabled", enabled)
            .put("missing_required_capabilities", JSONArray(missingRequiredCapabilities))
            .put("disabled_required_capabilities", JSONArray(disabledRequiredCapabilities))
            .put("unavailable_reasons", JSONArray(unavailableReasons))
            .toString(),
    )

    public val definition: NapaxiScenarioPack
        get() = NapaxiScenarioPack((obj.optJSONObject("definition") ?: JSONObject()).toString())
    public val registered: Boolean get() = obj.optBoolean("registered", false)
    public val available: Boolean get() = obj.optBoolean("available", false)
    public val enabled: Boolean get() = obj.optBoolean("enabled", false)
    public val missingRequiredCapabilities: List<String> get() = obj.optJSONArray("missing_required_capabilities")?.toStringList().orEmpty()
    public val disabledRequiredCapabilities: List<String> get() = obj.optJSONArray("disabled_required_capabilities")?.toStringList().orEmpty()
    public val unavailableReasons: List<String> get() = obj.optJSONArray("unavailable_reasons")?.toStringList().orEmpty()

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("definition", definition.toJsonObject())
        .put("registered", registered)
        .put("available", available)
        .put("enabled", enabled)
        .put("missing_required_capabilities", JSONArray(missingRequiredCapabilities))
        .put("disabled_required_capabilities", JSONArray(disabledRequiredCapabilities))
        .put("unavailable_reasons", JSONArray(unavailableReasons))

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiScenarioStatus =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiScenarioStatus =
            NapaxiScenarioStatus(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiScenarioStatus =
            fromJsonObject(JSONObject(map))
    }
}

public class NapaxiScenarioActivationPlan(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        supportedCapabilities: List<String> = emptyList(),
        enabledCapabilities: List<String> = emptyList(),
        disabledCapabilities: List<String> = emptyList(),
        hostRequiredCapabilities: List<String> = emptyList(),
        remoteRequiredCapabilities: List<String> = emptyList(),
        policyRequiredCapabilities: List<String> = emptyList(),
        warnings: List<String> = emptyList(),
    ) : this(
        JSONObject()
            .put("supported_capabilities", JSONArray(supportedCapabilities))
            .put("enabled_capabilities", JSONArray(enabledCapabilities))
            .put("disabled_capabilities", JSONArray(disabledCapabilities))
            .put("host_required_capabilities", JSONArray(hostRequiredCapabilities))
            .put("remote_required_capabilities", JSONArray(remoteRequiredCapabilities))
            .put("policy_required_capabilities", JSONArray(policyRequiredCapabilities))
            .put("warnings", JSONArray(warnings))
            .toString(),
    )

    public val supportedCapabilities: List<String> get() = obj.optJSONArray("supported_capabilities")?.toStringList().orEmpty()
    public val enabledCapabilities: List<String> get() = obj.optJSONArray("enabled_capabilities")?.toStringList().orEmpty()
    public val disabledCapabilities: List<String> get() = obj.optJSONArray("disabled_capabilities")?.toStringList().orEmpty()
    public val hostRequiredCapabilities: List<String> get() = obj.optJSONArray("host_required_capabilities")?.toStringList().orEmpty()
    public val remoteRequiredCapabilities: List<String> get() = obj.optJSONArray("remote_required_capabilities")?.toStringList().orEmpty()
    public val policyRequiredCapabilities: List<String> get() = obj.optJSONArray("policy_required_capabilities")?.toStringList().orEmpty()
    public val warnings: List<String> get() = obj.optJSONArray("warnings")?.toStringList().orEmpty()

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("supported_capabilities", JSONArray(supportedCapabilities))
        .put("enabled_capabilities", JSONArray(enabledCapabilities))
        .put("disabled_capabilities", JSONArray(disabledCapabilities))
        .put("host_required_capabilities", JSONArray(hostRequiredCapabilities))
        .put("remote_required_capabilities", JSONArray(remoteRequiredCapabilities))
        .put("policy_required_capabilities", JSONArray(policyRequiredCapabilities))
        .put("warnings", JSONArray(warnings))

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiScenarioActivationPlan =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiScenarioActivationPlan =
            NapaxiScenarioActivationPlan(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiScenarioActivationPlan =
            fromJsonObject(JSONObject(map))
    }
}

public class NapaxiScenarioResolution(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        status: NapaxiScenarioStatus,
        activationPlan: NapaxiScenarioActivationPlan,
    ) : this(
        JSONObject()
            .put("status", status.toJsonObject())
            .put("activation_plan", activationPlan.toJsonObject())
            .toString(),
    )

    public val status: NapaxiScenarioStatus
        get() = NapaxiScenarioStatus((obj.optJSONObject("status") ?: JSONObject()).toString())
    public val activationPlan: NapaxiScenarioActivationPlan
        get() = NapaxiScenarioActivationPlan((obj.optJSONObject("activation_plan") ?: JSONObject()).toString())

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("status", status.toJsonObject())
        .put("activation_plan", activationPlan.toJsonObject())

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiScenarioResolution =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiScenarioResolution =
            NapaxiScenarioResolution(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiScenarioResolution =
            fromJsonObject(JSONObject(map))
    }
}

public class NapaxiScenarioPackInstallResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        definition: NapaxiScenarioPack,
        installed: Boolean,
        replaced: Boolean,
        warnings: List<String> = emptyList(),
    ) : this(
        JSONObject()
            .put("definition", definition.toJsonObject())
            .put("installed", installed)
            .put("replaced", replaced)
            .put("warnings", JSONArray(warnings))
            .toString(),
    )

    public val definition: NapaxiScenarioPack
        get() = NapaxiScenarioPack((obj.optJSONObject("definition") ?: JSONObject()).toString())
    public val installed: Boolean get() = obj.optBoolean("installed", false)
    public val replaced: Boolean get() = obj.optBoolean("replaced", false)
    public val warnings: List<String> get() = obj.optJSONArray("warnings")?.toStringList().orEmpty()

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("definition", definition.toJsonObject())
        .put("installed", installed)
        .put("replaced", replaced)
        .put("warnings", JSONArray(warnings))

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiScenarioPackInstallResult =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiScenarioPackInstallResult =
            NapaxiScenarioPackInstallResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiScenarioPackInstallResult =
            fromJsonObject(JSONObject(map))
    }
}

public class NapaxiScenarioPackRemovalResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public constructor(
        scenarioId: String,
        removed: Boolean,
    ) : this(
        JSONObject()
            .put("scenario_id", scenarioId)
            .put("removed", removed)
            .toString(),
    )

    public val scenarioId: String get() = obj.optString("scenario_id")
    public val removed: Boolean get() = obj.optBoolean("removed", false)

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("scenario_id", scenarioId)
        .put("removed", removed)

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiScenarioPackRemovalResult =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiScenarioPackRemovalResult =
            NapaxiScenarioPackRemovalResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiScenarioPackRemovalResult =
            fromJsonObject(JSONObject(map))
    }
}

public fun decodeScenarioPacks(rawJson: String): List<NapaxiScenarioPack> =
    rawJson.parseJsonArrayOrObjectList("scenarios").map { NapaxiScenarioPack.fromJsonObject(it) }

public fun decodeScenarioStatuses(rawJson: String): List<NapaxiScenarioStatus> =
    rawJson.parseJsonArrayOrObjectList("statuses").map { NapaxiScenarioStatus.fromJsonObject(it) }

public fun decodeScenarioResolution(rawJson: String): NapaxiScenarioResolution? {
    val obj = runCatching { JSONObject(rawJson.ifBlank { "{}" }) }.getOrNull() ?: return null
    if (obj.has("error")) return null
    return NapaxiScenarioResolution.fromJsonObject(obj)
}

public fun decodeScenarioPackInstallResult(rawJson: String): NapaxiScenarioPackInstallResult? {
    val obj = runCatching { JSONObject(rawJson.ifBlank { "{}" }) }.getOrNull() ?: return null
    if (obj.has("error")) return null
    return NapaxiScenarioPackInstallResult.fromJsonObject(obj)
}

public fun decodeScenarioPackRemovalResult(rawJson: String): NapaxiScenarioPackRemovalResult? {
    val obj = runCatching { JSONObject(rawJson.ifBlank { "{}" }) }.getOrNull() ?: return null
    if (obj.has("error")) return null
    return NapaxiScenarioPackRemovalResult.fromJsonObject(obj)
}

public class WorkspaceFile(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val path: String get() = obj.optString("path")
    public val content: String get() = obj.optString("content")
    public val updatedAt: String? get() = obj.optNullableString("updatedAt") ?: obj.optNullableString("updated_at")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): WorkspaceFile = WorkspaceFile(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): WorkspaceFile = WorkspaceFile(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): WorkspaceFile = fromJsonObject(JSONObject(map))
    }
}

public class WorkspaceEntry(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val path: String get() = obj.optString("path")
    public val isDirectory: Boolean get() = obj.optBoolean("isDirectory", obj.optBoolean("is_directory", false))
    public val updatedAt: String? get() = obj.optNullableString("updatedAt") ?: obj.optNullableString("updated_at")
    public val preview: String? get() = obj.optNullableString("preview")
    public val name: String get() = path.substringAfterLast("/")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): WorkspaceEntry = WorkspaceEntry(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): WorkspaceEntry = WorkspaceEntry(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): WorkspaceEntry = fromJsonObject(JSONObject(map))
    }
}

public class MemorySearchResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val source: String get() = obj.optString("source")
    public val path: String get() = obj.optString("path")
    public val content: String get() = obj.optString("content")
    public val score: Double get() = obj.optDouble("score", 0.0)
    public val isHybridMatch: Boolean get() = obj.optBoolean("isHybridMatch", obj.optBoolean("is_hybrid_match", false))
    public val updatedAt: String? get() = obj.optNullableString("updatedAt") ?: obj.optNullableString("updated_at")
    public val threadId: String? get() = obj.optNullableString("threadId") ?: obj.optNullableString("thread_id")
    public val turnId: String? get() = obj.optNullableString("turnId") ?: obj.optNullableString("turn_id")
    public val createdAt: String? get() = obj.optNullableString("createdAt") ?: obj.optNullableString("created_at")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): MemorySearchResult = MemorySearchResult(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): MemorySearchResult = MemorySearchResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): MemorySearchResult = fromJsonObject(JSONObject(map))
    }
}

public class MemoryRecallSnippet(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val source: String get() = obj.optString("source")
    public val path: String get() = obj.optString("path")
    public val content: String get() = obj.optString("content")
    public val score: Double get() = obj.optDouble("score", 0.0)
    public val turnId: String? get() = obj.optNullableString("turnId") ?: obj.optNullableString("turn_id")
    public val createdAt: String? get() = obj.optNullableString("createdAt") ?: obj.optNullableString("created_at")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): MemoryRecallSnippet = MemoryRecallSnippet(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): MemoryRecallSnippet = MemoryRecallSnippet(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): MemoryRecallSnippet = fromJsonObject(JSONObject(map))
    }
}

public class MemoryRecallSession(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val threadId: String get() = obj.optString("threadId", obj.optString("thread_id"))
    public val title: String get() = obj.optString("title")
    public val summary: String get() = obj.optString("summary")
    public val snippets: List<MemoryRecallSnippet>
        get() = obj.optJSONArray("snippets")?.toJsonObjectList()?.map { MemoryRecallSnippet(it.toString()) }.orEmpty()
    public val score: Double get() = obj.optDouble("score", 0.0)
    public val source: String get() = obj.optString("source")
    public val startedAt: String? get() = obj.optNullableString("startedAt") ?: obj.optNullableString("started_at")
    public val lastActiveAt: String? get() = obj.optNullableString("lastActiveAt") ?: obj.optNullableString("last_active_at")
    public val cached: Boolean get() = obj.optBoolean("cached", false)
    public val fallback: Boolean get() = obj.optBoolean("fallback", false)
    public val sourceDocIds: List<String>
        get() = (
            obj.optJSONArray("sourceDocIds")
                ?: obj.optJSONArray("source_doc_ids")
            )?.toStringList().orEmpty()
    public val systemNote: String get() = obj.optString("systemNote", obj.optString("system_note"))

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): MemoryRecallSession = MemoryRecallSession(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): MemoryRecallSession = MemoryRecallSession(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): MemoryRecallSession = fromJsonObject(JSONObject(map))
    }
}

public class RecallIndexStats(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val status: String get() = obj.optString("status")
    public val dbPath: String get() = obj.optString("dbPath", obj.optString("db_path"))
    public val schemaVersion: Int get() = obj.optInt("schemaVersion", obj.optInt("schema_version", 0))
    public val indexedDocs: Int get() = obj.optInt("indexedDocs", obj.optInt("indexed_docs", 0))
    public val memoryDocs: Int get() = obj.optInt("memoryDocs", obj.optInt("memory_docs", 0))
    public val journalDocs: Int get() = obj.optInt("journalDocs", obj.optInt("journal_docs", 0))
    public val legacyDailyDocs: Int get() = obj.optInt("legacyDailyDocs", obj.optInt("legacy_daily_docs", 0))
    public val cachedSummaries: Int get() = obj.optInt("cachedSummaries", obj.optInt("cached_summaries", 0))
    public val lastRebuildAt: String? get() = obj.optNullableString("lastRebuildAt") ?: obj.optNullableString("last_rebuild_at")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): RecallIndexStats = RecallIndexStats(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): RecallIndexStats = RecallIndexStats(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): RecallIndexStats = fromJsonObject(JSONObject(map))
    }
}

public class JournalDay(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val date: String get() = obj.optString("date")
    public val path: String get() = obj.optString("path")
    public val turnCount: Int get() = obj.optInt("turnCount", obj.optInt("turn_count", 0))
    public val updatedAt: String? get() = obj.optNullableString("updatedAt") ?: obj.optNullableString("updated_at")
    public val legacy: Boolean get() = obj.optBoolean("legacy", false)

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): JournalDay = JournalDay(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): JournalDay = JournalDay(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): JournalDay = fromJsonObject(JSONObject(map))
    }
}

public class JournalTurnRecord(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val turnId: String get() = obj.optString("turnId", obj.optString("turn_id"))
    public val createdAt: String? get() = obj.optNullableString("createdAt") ?: obj.optNullableString("created_at")
    public val agentId: String get() = obj.optString("agentId", obj.optString("agent_id"))
    public val threadId: String get() = obj.optString("threadId", obj.optString("thread_id"))
    public val user: String get() = obj.optString("user")
    public val assistant: String get() = obj.optString("assistant")
    public val kind: String get() = obj.optString("kind", "turn")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): JournalTurnRecord = JournalTurnRecord(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): JournalTurnRecord = JournalTurnRecord(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): JournalTurnRecord = fromJsonObject(JSONObject(map))
    }
}

public object WorkspacePaths {
    public const val SOUL: String = "SOUL.md"
    public const val IDENTITY: String = "IDENTITY.md"
    public const val AGENTS: String = "AGENTS.md"
    public const val USER: String = "USER.md"
    public const val MEMORY: String = "MEMORY.md"
    public const val PROJECT: String = "PROJECT.md"
    public const val HEARTBEAT: String = "HEARTBEAT.md"
    public const val TOOLS: String = "TOOLS.md"
    public const val BOOTSTRAP: String = "BOOTSTRAP.md"
    public const val PROFILE: String = "context/profile.json"
    public const val DAILY_DIR: String = "daily/"

    public const val soul: String = SOUL
    public const val identity: String = IDENTITY
    public const val agents: String = AGENTS
    public const val user: String = USER
    public const val memory: String = MEMORY
    public const val project: String = PROJECT
    public const val heartbeat: String = HEARTBEAT
    public const val tools: String = TOOLS
    public const val bootstrap: String = BOOTSTRAP
    public const val profile: String = PROFILE
    public const val dailyDir: String = DAILY_DIR
}
public class SkillLifecycleSummary(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val state: String get() = obj.optString("state", "active")
    public val pinned: Boolean get() = obj.optBoolean("pinned", false)
    public val createdBy: String? get() = obj.optNullableString("created_by") ?: obj.optNullableString("createdBy")
    public val useCount: Int get() = obj.optInt("use_count", obj.optInt("useCount", 0))
    public val viewCount: Int get() = obj.optInt("view_count", obj.optInt("viewCount", 0))
    public val patchCount: Int get() = obj.optInt("patch_count", obj.optInt("patchCount", 0))
    public val lastUsedAt: String? get() = obj.optNullableString("last_used_at") ?: obj.optNullableString("lastUsedAt")
    public val lastViewedAt: String? get() = obj.optNullableString("last_viewed_at") ?: obj.optNullableString("lastViewedAt")
    public val lastPatchedAt: String? get() = obj.optNullableString("last_patched_at") ?: obj.optNullableString("lastPatchedAt")
    public val archivedAt: String? get() = obj.optNullableString("archived_at") ?: obj.optNullableString("archivedAt")
    public val absorbedInto: String? get() = obj.optNullableString("absorbed_into") ?: obj.optNullableString("absorbedInto")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillLifecycleSummary = SkillLifecycleSummary(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillLifecycleSummary = SkillLifecycleSummary(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillLifecycleSummary = fromJsonObject(JSONObject(map))
    }
}

public class SkillInfo(rawJson: String) : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val version: String get() = obj.optString("version")
    public val description: String get() = obj.optString("description")
    public val always: Boolean get() = obj.optBoolean("always", false)
    public val allowedAgents: List<String> get() = obj.optJSONArray("allowed_agents")?.toStringList().orEmpty()
    public val trust: String get() = obj.optString("trust", "Trusted")
    public val source: String get() = obj.optString("source")
    public val keywords: List<String> get() = obj.optJSONArray("keywords")?.toStringList().orEmpty()
    public val tags: List<String> get() = obj.optJSONArray("tags")?.toStringList().orEmpty()
    public val promptContent: String? get() = obj.optNullableString("prompt_content")
    public val contentHash: String? get() = obj.optNullableString("content_hash")
    public val lifecycle: SkillLifecycleSummary
        get() = SkillLifecycleSummary((obj.optJSONObject("lifecycle") ?: JSONObject()).toString())
    public val supportFiles: List<String> get() = obj.optJSONArray("support_files")?.toStringList().orEmpty()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillInfo = SkillInfo(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillInfo = SkillInfo(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillInfo = fromJsonObject(JSONObject(map))
    }
}

public class SkillStatusReport(rawJson: String) : RawJsonModel(rawJson) {
    public val entries: List<SkillStatusEntry>
        get() = obj.optJSONArray("entries")?.toJsonObjectList()?.map { SkillStatusEntry(it.toString()) }.orEmpty()
    public val ready: Int get() = obj.optInt("ready", 0)
    public val disabled: Int get() = obj.optInt("disabled", 0)
    public val blocked: Int get() = obj.optInt("blocked", 0)
    public val missingRequirements: Int get() = obj.optInt("missing_requirements", 0)
    public val parseError: Int get() = obj.optInt("parse_error", 0)
    public val securityBlocked: Int get() = obj.optInt("security_blocked", 0)
    public val tooLarge: Int get() = obj.optInt("too_large", 0)
    public val topBlockers: List<SkillStatusEntry>
        get() = obj.optJSONArray("top_blockers")?.toJsonObjectList()?.map { SkillStatusEntry(it.toString()) }.orEmpty()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillStatusReport = SkillStatusReport(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillStatusReport = SkillStatusReport(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillStatusReport = fromJsonObject(JSONObject(map))
    }
}

public class SkillStatusEntry(rawJson: String) : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val description: String get() = obj.optString("description")
    public val sourceKind: String get() = obj.optString("source_kind", obj.optString("sourceKind"))
    public val source: String get() = obj.optString("source")
    public val trust: String get() = obj.optString("trust")
    public val enabled: Boolean get() = obj.optBoolean("enabled", true)
    public val eligible: Boolean get() = obj.optBoolean("eligible", false)
    public val status: String get() = obj.optString("status")
    public val requirements: SkillRequirementSummary
        get() = SkillRequirementSummary((obj.optJSONObject("requirements") ?: JSONObject()).toString())
    public val missing: SkillRequirementSummary
        get() = SkillRequirementSummary((obj.optJSONObject("missing") ?: JSONObject()).toString())
    public val installOptions: List<JSONObject> get() = obj.optJSONArray("install_options")?.toJsonObjectList().orEmpty()
    public val warnings: List<String> get() = obj.optJSONArray("warnings")?.toStringList().orEmpty()
    public val error: String? get() = obj.optNullableString("error")
    public val lifecycle: SkillLifecycleSummary
        get() = SkillLifecycleSummary((obj.optJSONObject("lifecycle") ?: JSONObject()).toString())
    public val metadata: SkillOpenClawMetadata
        get() = SkillOpenClawMetadata((obj.optJSONObject("metadata") ?: JSONObject()).toString())
    public val provenance: SkillProvenance
        get() = SkillProvenance((obj.optJSONObject("provenance") ?: JSONObject()).toString())
    public val remediationActions: List<SkillRemediationAction>
        get() = (
            obj.optJSONArray("remediation_actions")
                ?: obj.optJSONArray("remediationActions")
            )?.toJsonObjectList()?.map(SkillRemediationAction::fromJsonObject).orEmpty()
    public val isReady: Boolean get() = status == "ready"
    public val isBlocked: Boolean
        get() = status == "missing_requirements" ||
            status == "parse_error" ||
            status == "security_blocked" ||
            status == "too_large" ||
            status == "blocked"

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillStatusEntry = SkillStatusEntry(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillStatusEntry = SkillStatusEntry(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillStatusEntry = fromJsonObject(JSONObject(map))
    }
}

public class SkillProvenance(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val sourceKind: String get() = obj.optString("source_kind", obj.optString("sourceKind"))
    public val trust: String get() = obj.optString("trust")
    public val managedBy: String get() = obj.optString("managed_by", obj.optString("managedBy"))
    public val legacy: Boolean get() = obj.optBoolean("legacy", false)

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillProvenance = SkillProvenance(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillProvenance = SkillProvenance(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillProvenance = fromJsonObject(JSONObject(map))
    }
}

public class SkillRequirementSummary(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val bins: List<String> get() = obj.optJSONArray("bins")?.toStringList().orEmpty()
    public val anyBins: List<String>
        get() = (obj.optJSONArray("any_bins") ?: obj.optJSONArray("anyBins"))?.toStringList().orEmpty()
    public val env: List<String> get() = obj.optJSONArray("env")?.toStringList().orEmpty()
    public val config: List<String> get() = obj.optJSONArray("config")?.toStringList().orEmpty()
    public val os: List<String> get() = obj.optJSONArray("os")?.toStringList().orEmpty()
    public val capabilities: List<String> get() = obj.optJSONArray("capabilities")?.toStringList().orEmpty()
    public val skills: List<String> get() = obj.optJSONArray("skills")?.toStringList().orEmpty()
    public val isEmpty: Boolean
        get() = bins.isEmpty() &&
            anyBins.isEmpty() &&
            env.isEmpty() &&
            config.isEmpty() &&
            os.isEmpty() &&
            capabilities.isEmpty() &&
            skills.isEmpty()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillRequirementSummary = SkillRequirementSummary(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillRequirementSummary = SkillRequirementSummary(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillRequirementSummary = fromJsonObject(JSONObject(map))
    }
}

public class SkillOpenClawMetadata(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val userInvocable: Boolean get() = obj.optBoolean("user_invocable", true)
    public val disableModelInvocation: Boolean get() = obj.optBoolean("disable_model_invocation", false)
    public val commandDispatch: String? get() = obj.optNullableString("command_dispatch")
    public val commandTool: String? get() = obj.optNullableString("command_tool")
    public val commandArgMode: String? get() = obj.optNullableString("command_arg_mode")
    public val primaryEnv: String? get() = obj.optNullableString("primary_env")
    public val skillKey: String? get() = obj.optNullableString("skill_key")
    public val homepage: String? get() = obj.optNullableString("homepage")
    public val emoji: String? get() = obj.optNullableString("emoji")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillOpenClawMetadata = SkillOpenClawMetadata(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillOpenClawMetadata = SkillOpenClawMetadata(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillOpenClawMetadata = fromJsonObject(JSONObject(map))
    }
}

public class SkillSourceReport(rawJson: String) : RawJsonModel(rawJson) {
    public val agentId: String get() = obj.optString("agent_id", obj.optString("agentId"))
    public val sources: List<SkillSourceEntry>
        get() = obj.optJSONArray("sources")?.toJsonObjectList()?.map { SkillSourceEntry(it.toString()) }.orEmpty()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSourceReport = SkillSourceReport(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSourceReport = SkillSourceReport(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSourceReport = fromJsonObject(JSONObject(map))
    }
}

public class SkillSourceEntry(rawJson: String) : RawJsonModel(rawJson) {
    public val id: String get() = obj.optString("id")
    public val kind: String get() = obj.optString("kind")
    public val root: String get() = obj.optString("root")
    public val priority: Int get() = obj.optInt("priority", 0)
    public val trust: String get() = obj.optString("trust")
    public val exists: Boolean get() = obj.optBoolean("exists", false)
    public val version: Int get() = obj.optInt("version", 0)
    public val updatedAt: String? get() = obj.optNullableString("updated_at") ?: obj.optNullableString("updatedAt")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSourceEntry = SkillSourceEntry(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSourceEntry = SkillSourceEntry(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSourceEntry = fromJsonObject(JSONObject(map))
    }
}

public class SkillRefreshResult(rawJson: String) : RawJsonModel(rawJson) {
    public val success: Boolean get() = obj.optBoolean("success", false)
    public val agentId: String get() = obj.optString("agent_id", obj.optString("agentId"))
    public val sourceId: String get() = obj.optString("source_id", obj.optString("sourceId"))
    public val version: Int get() = obj.optInt("version", 0)
    public val recordedAt: String get() = obj.optString("recorded_at", obj.optString("recordedAt"))
    public val error: String? get() = obj.optNullableString("error")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillRefreshResult = SkillRefreshResult(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillRefreshResult = SkillRefreshResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillRefreshResult = fromJsonObject(JSONObject(map))
    }
}

public class SkillCommandReport(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val commands: List<SkillCommand>
        get() = obj.optJSONArray("commands")?.toJsonObjectList()?.map { SkillCommand(it.toString()) }.orEmpty()
    public val total: Int get() = obj.optNullableInt("total") ?: commands.size
    public val snapshotId: String? get() = obj.optNullableString("snapshot_id") ?: obj.optNullableString("snapshotId")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillCommandReport = SkillCommandReport(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillCommandReport = SkillCommandReport(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillCommandReport = fromJsonObject(JSONObject(map))
    }
}

public class SkillCommand(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val skillName: String get() = obj.optString("skill_name", obj.optString("skillName"))
    public val description: String get() = obj.optString("description")
    public val dispatch: SkillCommandDispatch?
        get() = obj.optJSONObject("dispatch")?.let { SkillCommandDispatch(it.toString()) }
    public val argMode: String? get() = obj.optNullableString("arg_mode") ?: obj.optNullableString("argMode")
    public val eligible: Boolean get() = obj.optBoolean("eligible", false)
    public val disabledReason: String? get() = obj.optNullableString("disabled_reason") ?: obj.optNullableString("disabledReason")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillCommand = SkillCommand(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillCommand = SkillCommand(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillCommand = fromJsonObject(JSONObject(map))
    }
}

public class SkillCommandDispatch(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val kind: String get() = obj.optString("kind")
    public val toolName: String? get() = obj.optNullableString("tool_name") ?: obj.optNullableString("toolName")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillCommandDispatch = SkillCommandDispatch(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillCommandDispatch = SkillCommandDispatch(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillCommandDispatch = fromJsonObject(JSONObject(map))

        @JvmStatic
        public fun fromMapOrNull(map: Map<String, *>?): SkillCommandDispatch? =
            map?.let(::fromMap)
    }
}

public class SkillCommandResolution(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val matched: Boolean get() = obj.optBoolean("matched", false)
    public val command: SkillCommand?
        get() = obj.optJSONObject("command")?.let { SkillCommand(it.toString()) }
    public val args: String? get() = obj.optNullableString("args")
    public val error: String? get() = obj.optNullableString("error")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillCommandResolution = SkillCommandResolution(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillCommandResolution = SkillCommandResolution(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillCommandResolution = fromJsonObject(JSONObject(map))
    }
}

public class SkillCommandRun(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val success: Boolean get() = obj.optBoolean("success", false)
    public val status: String get() = obj.optString("status")
    public val commandName: String get() = obj.optString("command_name", obj.optString("commandName"))
    public val skillName: String? get() = obj.optNullableString("skill_name") ?: obj.optNullableString("skillName")
    public val args: String? get() = obj.optNullableString("args")
    public val sessionKey: String? get() = obj.optNullableString("session_key") ?: obj.optNullableString("sessionKey")
    public val message: String? get() = obj.optNullableString("message")
    public val dispatch: SkillCommandDispatch?
        get() = obj.optJSONObject("dispatch")?.let { SkillCommandDispatch(it.toString()) }
    public val error: String? get() = obj.optNullableString("error")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillCommandRun = SkillCommandRun(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillCommandRun = SkillCommandRun(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillCommandRun = fromJsonObject(JSONObject(map))
    }
}
public class SkillInstallResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val success: Boolean get() = obj.optBoolean("success", false)
    public val error: String? get() = obj.optNullableString("error")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillInstallResult = SkillInstallResult(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillInstallResult = SkillInstallResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillInstallResult = fromJsonObject(JSONObject(map))
    }
}
public class SkillUsageRecord(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val skillName: String get() = obj.optString("skill_name", obj.optString("skillName"))
    public val createdAt: String? get() = obj.optNullableString("created_at") ?: obj.optNullableString("createdAt")
    public val lifecycle: SkillLifecycleSummary get() = SkillLifecycleSummary(rawJson)
    public val state: String get() = lifecycle.state
    public val pinned: Boolean get() = lifecycle.pinned
    public val createdBy: String? get() = lifecycle.createdBy
    public val useCount: Int get() = lifecycle.useCount
    public val viewCount: Int get() = lifecycle.viewCount
    public val patchCount: Int get() = lifecycle.patchCount
    public val lastUsedAt: String? get() = lifecycle.lastUsedAt
    public val lastViewedAt: String? get() = lifecycle.lastViewedAt
    public val lastPatchedAt: String? get() = lifecycle.lastPatchedAt
    public val archivedAt: String? get() = lifecycle.archivedAt
    public val absorbedInto: String? get() = lifecycle.absorbedInto

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillUsageRecord = SkillUsageRecord(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillUsageRecord = SkillUsageRecord(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillUsageRecord = fromJsonObject(JSONObject(map))
    }
}
public class SkillSnapshotList(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val snapshots: List<SkillSnapshotIndexEntry>
        get() = obj.optJSONArray("snapshots")?.toJsonObjectList()?.map { SkillSnapshotIndexEntry(it.toString()) }.orEmpty()
    public val total: Int get() = obj.optNullableInt("total") ?: snapshots.size

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSnapshotList = SkillSnapshotList(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSnapshotList = SkillSnapshotList(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSnapshotList = fromJsonObject(JSONObject(map))
    }
}
public open class SkillSnapshotIndexEntry(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val snapshotId: String get() = obj.optString("snapshot_id", obj.optString("snapshotId"))
    public val agentId: String get() = obj.optString("agent_id", obj.optString("agentId"))
    public val purpose: String get() = obj.optString("purpose")
    public val createdAt: String get() = obj.optString("created_at", obj.optString("createdAt"))

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSnapshotIndexEntry = SkillSnapshotIndexEntry(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSnapshotIndexEntry = SkillSnapshotIndexEntry(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSnapshotIndexEntry = fromJsonObject(JSONObject(map))
    }
}
public class SkillSnapshot(rawJson: String = "{}") : SkillSnapshotIndexEntry(rawJson) {
    public val sourceVersions: Map<String, Int>
        get() = (obj.optJSONObject("source_versions") ?: obj.optJSONObject("sourceVersions"))?.toIntMap().orEmpty()
    public val catalogEntries: List<SkillSnapshotCatalogEntry>
        get() = (
            obj.optJSONArray("catalog_entries")
                ?: obj.optJSONArray("catalogEntries")
            )?.toJsonObjectList()?.map { SkillSnapshotCatalogEntry(it.toString()) }.orEmpty()
    public val commandEntries: List<SkillCommand>
        get() = (
            obj.optJSONArray("command_entries")
                ?: obj.optJSONArray("commandEntries")
            )?.toJsonObjectList()?.map { SkillCommand(it.toString()) }.orEmpty()
    public val statusCounts: JSONObject
        get() = obj.optJSONObject("status_counts") ?: obj.optJSONObject("statusCounts") ?: JSONObject()
    public val catalogPlan: JSONObject
        get() = obj.optJSONObject("catalog_plan") ?: obj.optJSONObject("catalogPlan") ?: JSONObject()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSnapshot = SkillSnapshot(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSnapshot = SkillSnapshot(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSnapshot = fromJsonObject(JSONObject(map))
    }
}
public class SkillSnapshotCatalogEntry(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val version: String get() = obj.optString("version")
    public val description: String get() = obj.optString("description")
    public val trust: String get() = obj.optString("trust")
    public val activationHint: String get() = obj.optString("activation_hint", obj.optString("activationHint"))
    public val contentHash: String get() = obj.optString("content_hash", obj.optString("contentHash"))

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSnapshotCatalogEntry = SkillSnapshotCatalogEntry(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSnapshotCatalogEntry = SkillSnapshotCatalogEntry(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSnapshotCatalogEntry = fromJsonObject(JSONObject(map))
    }
}
public class SkillSecretRequirementReport(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val requirements: List<SkillSecretRequirement>
        get() = obj.optJSONArray("requirements")?.toJsonObjectList()?.map { SkillSecretRequirement(it.toString()) }.orEmpty()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSecretRequirementReport = SkillSecretRequirementReport(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSecretRequirementReport = SkillSecretRequirementReport(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSecretRequirementReport = fromJsonObject(JSONObject(map))
    }
}
public class SkillSecretRequirement(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val skillName: String get() = obj.optString("skill_name", obj.optString("skillName"))
    public val skillKey: String get() = obj.optString("skill_key", obj.optString("skillKey"))
    public val key: String get() = obj.optString("key")
    public val source: String get() = obj.optString("source")
    public val available: Boolean get() = obj.optBoolean("available", false)

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSecretRequirement = SkillSecretRequirement(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSecretRequirement = SkillSecretRequirement(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSecretRequirement = fromJsonObject(JSONObject(map))
    }
}
public class SkillRemediationRun(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val runId: String get() = obj.optString("run_id", obj.optString("runId"))
    public val agentId: String get() = obj.optString("agent_id", obj.optString("agentId"))
    public val skillName: String get() = obj.optString("skill_name", obj.optString("skillName"))
    public val actionId: String get() = obj.optString("action_id", obj.optString("actionId"))
    public val status: String get() = obj.optString("status")
    public val requestedAt: String get() = obj.optString("requested_at", obj.optString("requestedAt"))
    public val updatedAt: String get() = obj.optString("updated_at", obj.optString("updatedAt"))
    public val result: JSONObject? get() = obj.optJSONObject("result")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillRemediationRun = SkillRemediationRun(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillRemediationRun = SkillRemediationRun(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillRemediationRun = fromJsonObject(JSONObject(map))
    }
}
public class SkillRemediationRunList(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val runs: List<SkillRemediationRun>
        get() = obj.optJSONArray("runs")?.toJsonObjectList()?.map { SkillRemediationRun(it.toString()) }.orEmpty()
    public val total: Int get() = obj.optNullableInt("total") ?: runs.size

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillRemediationRunList = SkillRemediationRunList(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillRemediationRunList = SkillRemediationRunList(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillRemediationRunList = fromJsonObject(JSONObject(map))
    }
}
public class CuratorRunSummary(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val dryRun: Boolean get() = obj.optBoolean("dry_run", true)
    public val checked: Int get() = obj.optInt("checked", 0)
    public val markedStale: Int get() = obj.optInt("marked_stale", 0)
    public val archived: Int get() = obj.optInt("archived", 0)
    public val restoredActive: Int get() = obj.optInt("restored_active", 0)
    public val actions: List<String> get() = obj.optJSONArray("actions")?.toStringList().orEmpty()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): CuratorRunSummary = CuratorRunSummary(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): CuratorRunSummary = CuratorRunSummary(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): CuratorRunSummary = fromJsonObject(JSONObject(map))
    }
}
public class SkillConsolidationReviewResult(rawJson: String) : RawJsonModel(rawJson) {
    public val reviewed: Boolean get() = obj.optBoolean("reviewed", false)
    public val dryRun: Boolean get() = obj.optBoolean("dry_run", true)
    public val suggestionsCount: Int get() = obj.optInt("suggestions_count", 0)
    public val pendingCount: Int get() = obj.optInt("pending_count", 0)
    public val pendingId: String? get() = obj.optNullableString("pending_id")
    public val actions: List<JSONObject> get() = obj.optJSONArray("actions")?.toJsonObjectList().orEmpty()
    public val warnings: List<String> get() = obj.optJSONArray("warnings")?.toStringList().orEmpty()
    public val error: String? get() = obj.optNullableString("error")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillConsolidationReviewResult = SkillConsolidationReviewResult(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillConsolidationReviewResult =
            SkillConsolidationReviewResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillConsolidationReviewResult = fromJsonObject(JSONObject(map))
    }
}
public class SkillSupportFileReadResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val success: Boolean get() = obj.optBoolean("success", false)
    public val skillName: String? get() = obj.optNullableString("skill_name") ?: obj.optNullableString("skillName")
    public val filePath: String? get() = obj.optNullableString("file_path") ?: obj.optNullableString("filePath")
    public val content: String? get() = obj.optNullableString("content")
    public val error: String? get() = obj.optNullableString("error")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): SkillSupportFileReadResult = SkillSupportFileReadResult(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): SkillSupportFileReadResult = SkillSupportFileReadResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): SkillSupportFileReadResult = fromJsonObject(JSONObject(map))
    }
}
public class CatalogSearchResult(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val results: List<CatalogSkillInfo>
        get() = obj.optJSONArray("results")?.toJsonObjectList()?.map { CatalogSkillInfo(it.toString()) }.orEmpty()
    public val error: String? get() = obj.optNullableString("error")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): CatalogSearchResult = CatalogSearchResult(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): CatalogSearchResult = CatalogSearchResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): CatalogSearchResult = fromJsonObject(JSONObject(map))
    }
}
public class CatalogPackagePage(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val items: List<CatalogSkillInfo>
        get() = obj.optJSONArray("items")?.toJsonObjectList()?.map { CatalogSkillInfo(it.toString()) }.orEmpty()
    public val nextCursor: String? get() = obj.optNullableString("nextCursor") ?: obj.optNullableString("next_cursor")
    public val error: String? get() = obj.optNullableString("error")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): CatalogPackagePage = CatalogPackagePage(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): CatalogPackagePage = CatalogPackagePage(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): CatalogPackagePage = fromJsonObject(JSONObject(map))
    }
}
public class CatalogSkillInfo(rawJson: String = "{}") : RawJsonModel(rawJson) {
    private val latestVersion: JSONObject? get() = obj.optJSONObject("latestVersion")
    private val stats: JSONObject? get() = obj.optJSONObject("stats")
    private val ownerObject: JSONObject? get() = obj.optJSONObject("owner")
    public val slug: String get() = obj.optString("slug", obj.optString("name"))
    public val name: String
        get() = obj.optString("displayName")
            .takeIf { it.isNotEmpty() }
            ?: obj.optString("name").takeIf { it.isNotEmpty() }
            ?: obj.optString("slug")
    public val description: String
        get() = obj.optString("description")
            .takeIf { it.isNotEmpty() }
            ?: obj.optString("summary")
    public val version: String
        get() = obj.optString("version")
            .takeIf { it.isNotEmpty() }
            ?: latestVersion?.optString("version").orEmpty()
    public val score: Double get() = obj.optDouble("score", 0.0)
    public val stars: Int? get() = obj.optNullableInt("stars") ?: stats?.optNullableInt("stars")
    public val downloads: Int? get() = obj.optNullableInt("downloads") ?: stats?.optNullableInt("downloads")
    public val installsCurrent: Int? get() = obj.optNullableInt("installsCurrent") ?: stats?.optNullableInt("installsCurrent")
    public val installsAllTime: Int? get() = obj.optNullableInt("installsAllTime") ?: stats?.optNullableInt("installsAllTime")
    public val owner: String?
        get() = obj.optNullableScalarString("owner")
            ?: obj.optNullableString("ownerHandle")
            ?: ownerObject?.optNullableString("handle")
    public val ownerName: String? get() = obj.optNullableString("ownerName") ?: ownerObject?.optNullableString("displayName")
    public val summary: String? get() = obj.optNullableString("summary")
    public val tags: List<String>
        get() = obj.optJSONArray("tags")?.toStringList()?.takeIf { it.isNotEmpty() }
            ?: obj.optJSONArray("capabilityTags")?.toStringList()
            ?: emptyList()
    public val updatedAtMs: Long? get() = obj.optNullableLong("updatedAt")
    public val updatedAt: Long? get() = updatedAtMs

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): CatalogSkillInfo = CatalogSkillInfo(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): CatalogSkillInfo = CatalogSkillInfo(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): CatalogSkillInfo = fromJsonObject(JSONObject(map))
    }
}
public enum class EvolutionRunStatus(public val wireName: String) {
    Queued("queued"),
    Running("running"),
    Completed("completed"),
    Failed("failed"),
    Unknown("unknown"),
    ;

    public companion object {
        public fun fromWire(value: String?): EvolutionRunStatus =
            entries.firstOrNull { it.wireName == value } ?: Unknown
    }
}

public class EvolutionRun(rawJson: String) : RawJsonModel(rawJson) {
    public val id: String get() = obj.optString("id")
    public val agentId: String get() = obj.optString("agent_id")
    public val threadId: String get() = obj.optString("thread_id")
    public val reviewType: String get() = obj.optString("review_type")
    public val status: EvolutionRunStatus get() = EvolutionRunStatus.fromWire(obj.optString("status"))
    public val queuedAt: String get() = obj.optString("queued_at")
    public val startedAt: String? get() = obj.optNullableString("started_at")
    public val completedAt: String? get() = obj.optNullableString("completed_at")
    public val suggestionsCount: Int get() = obj.optInt("suggestions_count", 0)
    public val autoAppliedCount: Int get() = obj.optInt("auto_applied_count", 0)
    public val pendingCount: Int get() = obj.optInt("pending_count", 0)
    public val error: String? get() = obj.optNullableString("error")
    public val isFinished: Boolean
        get() = status == EvolutionRunStatus.Completed || status == EvolutionRunStatus.Failed

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): EvolutionRun = EvolutionRun(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): EvolutionRun = EvolutionRun(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): EvolutionRun = fromJsonObject(JSONObject(map))
    }
}

public class EvolutionDiagnostic(rawJson: String) : RawJsonModel(rawJson) {
    public val id: String get() = obj.optString("id")
    public val createdAt: String get() = obj.optString("created_at")
    public val agentId: String get() = obj.optString("agent_id")
    public val threadId: String get() = obj.optString("thread_id")
    public val reviewType: String get() = obj.optString("review_type")
    public val triggerReason: String get() = obj.optString("trigger_reason")
    public val inputSummary: JSONObject get() = obj.optJSONObject("input_summary") ?: JSONObject()
    public val toolCalls: List<String> get() = obj.optJSONArray("tool_calls")?.toStringList().orEmpty()
    public val suggestionsCount: Int get() = obj.optInt("suggestions_count", 0)
    public val pendingCount: Int get() = obj.optInt("pending_count", 0)
    public val autoAppliedCount: Int get() = obj.optInt("auto_applied_count", 0)
    public val applyResult: String? get() = obj.optNullableString("apply_result")
    public val failureReason: String? get() = obj.optNullableString("failure_reason")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): EvolutionDiagnostic = EvolutionDiagnostic(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): EvolutionDiagnostic = EvolutionDiagnostic(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): EvolutionDiagnostic = fromJsonObject(JSONObject(map))
    }
}

public enum class GroupMessageType(public val wireName: String) {
    Text("text"),
    ToolCall("tool_call"),
    ToolResult("tool_result"),
    System("system"),
    ;

    public companion object {
        public fun fromWire(value: String?): GroupMessageType =
            entries.firstOrNull { it.wireName == value } ?: Text
    }
}

public class GroupInfo(rawJson: String) : RawJsonModel(rawJson) {
    public val id: String get() = obj.optString("id")
    public val name: String get() = obj.optString("name")
    public val members: List<String> get() = obj.optJSONArray("members")?.toStringList().orEmpty()
    public val coordinator: String get() = obj.optString("coordinator", "napaxi")
    public val createdAt: String get() = obj.optString("created_at")
    public val messageCount: Int get() = obj.optInt("message_count", 0)
    public val lastMessagePreview: String? get() = obj.optNullableString("last_message_preview")
    public val lastMessageTime: String? get() = obj.optNullableString("last_message_time")
    public val customPrompt: String? get() = obj.optNullableString("custom_prompt")

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): GroupInfo = GroupInfo(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): GroupInfo = GroupInfo(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): GroupInfo = fromJsonObject(JSONObject(map))
    }
}

public class GroupMessage(rawJson: String) : RawJsonModel(rawJson) {
    public val id: String get() = obj.optString("id")
    public val groupId: String get() = obj.optString("group_id")
    public val sender: String get() = obj.optString("sender")
    public val content: String get() = obj.optString("content")
    public val messageType: GroupMessageType get() = GroupMessageType.fromWire(obj.optString("type", "text"))
    public val timestamp: String get() = obj.optString("timestamp")
    public val toolCallId: String? get() = obj.optNullableString("tool_call_id")
    public val toolName: String? get() = obj.optNullableString("tool_name")
    public val targetAgent: String? get() = obj.optNullableString("target_agent")
    public val isUser: Boolean get() = sender == "user"
    public val isSystem: Boolean get() = sender == "system"
    public val isDelegation: Boolean get() = targetAgent != null

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): GroupMessage = GroupMessage(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): GroupMessage = GroupMessage(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): GroupMessage = fromJsonObject(JSONObject(map))
    }
}
public enum class McpConnectionState {
    Disconnected,
    Connecting,
    Connected,
    Error,
}

public class McpServerInfo(rawJson: String) : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val url: String get() = obj.optString("url")
    public val connected: Boolean get() = obj.optBoolean("connected", false)
    public val tools: List<String> get() = obj.optJSONArray("tools")?.toStringList().orEmpty()
    public val error: String? get() = obj.optNullableString("error")
    public val authRequired: Boolean
        get() = obj.optBoolean("authRequired", obj.optBoolean("auth_required", false))
    public val oauthConnected: Boolean
        get() = obj.optBoolean("oauthConnected", obj.optBoolean("oauth_connected", false))
    public val oauthPending: Boolean
        get() = obj.optBoolean("oauthPending", obj.optBoolean("oauth_pending", false))
    public val connectionState: McpConnectionState
        get() = when {
            !error.isNullOrEmpty() -> McpConnectionState.Error
            oauthPending -> McpConnectionState.Connecting
            connected -> McpConnectionState.Connected
            else -> McpConnectionState.Disconnected
        }

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): McpServerInfo = McpServerInfo(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): McpServerInfo = McpServerInfo(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): McpServerInfo = fromJsonObject(JSONObject(map))
    }
}

public class McpServerActionResult(rawJson: String) : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val toolsLoaded: List<String> get() = obj.optJSONArray("tools_loaded")?.toStringList().orEmpty()
    public val message: String? get() = obj.optNullableString("message")
    public val error: String? get() = obj.optNullableString("error")
    public val isSuccess: Boolean get() = error.isNullOrEmpty()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): McpServerActionResult = McpServerActionResult(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): McpServerActionResult = McpServerActionResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): McpServerActionResult = fromJsonObject(JSONObject(map))
    }
}

public class McpOAuthStartResult(rawJson: String) : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val authorizationUrl: String get() = obj.optString("authorization_url")
    public val state: String get() = obj.optString("state")
    public val redirectUri: String get() = obj.optString("redirect_uri")
    public val error: String? get() = obj.optNullableString("error")
    public val isSuccess: Boolean get() = error.isNullOrEmpty()

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): McpOAuthStartResult = McpOAuthStartResult(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): McpOAuthStartResult = McpOAuthStartResult(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): McpOAuthStartResult = fromJsonObject(JSONObject(map))
    }
}

public class McpToolInfo(rawJson: String) : RawJsonModel(rawJson) {
    public val name: String get() = obj.optString("name")
    public val serverName: String get() = obj.optString("serverName", obj.optString("server_name"))

    public fun toJsonObject(): JSONObject = jsonObject()
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): McpToolInfo = McpToolInfo(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): McpToolInfo = McpToolInfo(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): McpToolInfo = fromJsonObject(JSONObject(map))
    }
}

public class AutomationTrigger(rawJson: String) : RawJsonModel(rawJson) {
    public val kind: String get() = obj.optString("kind", "manual")
    public val atMs: Long? get() = obj.optNullableLong("atMs") ?: obj.optNullableLong("at_ms")
    public val timezone: String? get() = obj.optNullableString("timezone")
    public val everyMs: Long? get() = obj.optNullableLong("everyMs") ?: obj.optNullableLong("every_ms")
    public val anchorMs: Long? get() = obj.optNullableLong("anchorMs") ?: obj.optNullableLong("anchor_ms")
    public val eventType: String? get() = obj.optNullableString("eventType") ?: obj.optNullableString("event_type")
    public val source: String? get() = obj.optNullableString("source")

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AutomationTrigger = AutomationTrigger(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AutomationTrigger = AutomationTrigger(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AutomationTrigger = fromJsonObject(JSONObject(map))

        @JvmStatic
        public fun oneShotAt(atMs: Long, timezone: String? = null): AutomationTrigger =
            AutomationTrigger(
                JSONObject()
                    .put("kind", "oneShotAt")
                    .put("atMs", atMs)
                    .apply { timezone?.let { put("timezone", it) } }
                    .toString(),
            )

        @JvmStatic
        public fun interval(everyMs: Long, anchorMs: Long? = null): AutomationTrigger =
            AutomationTrigger(
                JSONObject()
                    .put("kind", "interval")
                    .put("everyMs", everyMs)
                    .apply { anchorMs?.let { put("anchorMs", it) } }
                    .toString(),
            )

        @JvmStatic
        public fun manual(): AutomationTrigger =
            AutomationTrigger(JSONObject().put("kind", "manual").toString())

        @JvmStatic
        public fun hostEvent(eventType: String, source: String? = null): AutomationTrigger =
            AutomationTrigger(
                JSONObject()
                    .put("kind", "hostEvent")
                    .put("eventType", eventType)
                    .apply { source?.let { put("source", it) } }
                    .toString(),
            )
    }
}

public class AutomationPayload(rawJson: String) : RawJsonModel(rawJson) {
    public val kind: String get() = obj.optString("kind", "systemEvent")
    public val text: String? get() = obj.optNullableString("text")
    public val sessionKeyJson: String? get() = obj.optNullableString("sessionKey") ?: obj.optNullableString("session_key")
    public val wakeMode: String? get() = obj.optNullableString("wakeMode") ?: obj.optNullableString("wake_mode")
    public val message: String? get() = obj.optNullableString("message")
    public val sessionMode: String? get() = obj.optNullableString("sessionMode") ?: obj.optNullableString("session_mode")
    public val modelProfileId: String? get() = obj.optNullableString("modelProfileId") ?: obj.optNullableString("model_profile_id")
    public val maxIterations: Int? get() = obj.optNullableInt("maxIterations") ?: obj.optNullableInt("max_iterations")

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AutomationPayload = AutomationPayload(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AutomationPayload = AutomationPayload(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AutomationPayload = fromJsonObject(JSONObject(map))

        @JvmStatic
        public fun systemEvent(
            text: String,
            sessionKeyJson: String? = null,
            wakeMode: String = "next_foreground_or_host_wake",
        ): AutomationPayload =
            AutomationPayload(
                JSONObject()
                    .put("kind", "systemEvent")
                    .put("text", text)
                    .put("wakeMode", wakeMode)
                    .apply { sessionKeyJson?.let { put("sessionKey", it) } }
                    .toString(),
            )

        @JvmStatic
        public fun agentTurn(
            message: String,
            sessionMode: String = "isolated",
            modelProfileId: String? = null,
            maxIterations: Int? = null,
        ): AutomationPayload =
            AutomationPayload(
                JSONObject()
                    .put("kind", "agentTurn")
                    .put("message", message)
                    .put("sessionMode", sessionMode)
                    .apply {
                        modelProfileId?.let { put("modelProfileId", it) }
                        maxIterations?.let { put("maxIterations", it) }
                    }
                    .toString(),
            )
    }
}

public class AutomationPolicy(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val requiresUserVisibleNotification: Boolean
        get() = obj.optBoolean(
            "requiresUserVisibleNotification",
            obj.optBoolean("requires_user_visible_notification", true),
        )
    public val allowHighRiskTools: Boolean
        get() = obj.optBoolean("allowHighRiskTools", obj.optBoolean("allow_high_risk_tools", false))
    public val maxRunDurationMs: Long
        get() = obj.optNullableLong("maxRunDurationMs") ?: obj.optNullableLong("max_run_duration_ms") ?: 600_000L
    public val maxRetries: Int
        get() = obj.optNullableInt("maxRetries") ?: obj.optNullableInt("max_retries") ?: 2
    public val retryBackoffMs: List<Long>
        get() = (
            obj.optJSONArray("retryBackoffMs")
                ?: obj.optJSONArray("retry_backoff_ms")
            )?.toLongList()?.filter { it > 0 }.orEmpty().ifEmpty { listOf(30_000L, 300_000L) }
    public val deleteAfterSuccess: Boolean?
        get() = obj.optNullableBoolean("deleteAfterSuccess") ?: obj.optNullableBoolean("delete_after_success")

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AutomationPolicy = AutomationPolicy(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AutomationPolicy = AutomationPolicy(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AutomationPolicy = fromJsonObject(JSONObject(map))
    }
}

public class AutomationJobState(rawJson: String = "{}") : RawJsonModel(rawJson) {
    public val nextRunAtMs: Long? get() = obj.optNullableLong("nextRunAtMs") ?: obj.optNullableLong("next_run_at_ms")
    public val lastRunAtMs: Long? get() = obj.optNullableLong("lastRunAtMs") ?: obj.optNullableLong("last_run_at_ms")
    public val lastRunStatus: String? get() = obj.optNullableString("lastRunStatus") ?: obj.optNullableString("last_run_status")
    public val lastError: String? get() = obj.optNullableString("lastError") ?: obj.optNullableString("last_error")
    public val consecutiveErrors: Int
        get() = obj.optNullableInt("consecutiveErrors") ?: obj.optNullableInt("consecutive_errors") ?: 0
    public val runningRunId: String? get() = obj.optNullableString("runningRunId") ?: obj.optNullableString("running_run_id")
    public val runningAtMs: Long? get() = obj.optNullableLong("runningAtMs") ?: obj.optNullableLong("running_at_ms")
    public val lastWakeSource: String? get() = obj.optNullableString("lastWakeSource") ?: obj.optNullableString("last_wake_source")
    public val lastWakeAtMs: Long? get() = obj.optNullableLong("lastWakeAtMs") ?: obj.optNullableLong("last_wake_at_ms")

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AutomationJobState = AutomationJobState(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AutomationJobState = AutomationJobState(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AutomationJobState = fromJsonObject(JSONObject(map))
    }
}

public class AutomationJob(rawJson: String) : RawJsonModel(rawJson) {
    public val id: String get() = obj.optString("id")
    public val name: String get() = obj.optString("name")
    public val enabled: Boolean get() = obj.optBoolean("enabled", true)
    public val accountId: String get() = obj.optString("accountId", obj.optString("account_id"))
    public val agentId: String get() = obj.optString("agentId", obj.optString("agent_id"))
    public val trigger: AutomationTrigger get() = AutomationTrigger((obj.optJSONObject("trigger") ?: JSONObject()).toString())
    public val payload: AutomationPayload get() = AutomationPayload((obj.optJSONObject("payload") ?: JSONObject()).toString())
    public val policy: AutomationPolicy get() = AutomationPolicy((obj.optJSONObject("policy") ?: JSONObject()).toString())
    public val state: AutomationJobState get() = AutomationJobState((obj.optJSONObject("state") ?: JSONObject()).toString())
    public val createdAt: Long get() = obj.optNullableLong("createdAt") ?: obj.optNullableLong("created_at") ?: 0L
    public val updatedAt: Long get() = obj.optNullableLong("updatedAt") ?: obj.optNullableLong("updated_at") ?: 0L

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AutomationJob = AutomationJob(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AutomationJob = AutomationJob(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AutomationJob = fromJsonObject(JSONObject(map))

        @JvmStatic
        public fun create(
            name: String,
            trigger: AutomationTrigger,
            payload: AutomationPayload,
            enabled: Boolean = true,
            accountId: String = "",
            agentId: String = "",
            policy: AutomationPolicy = AutomationPolicy(),
        ): AutomationJob =
            AutomationJob(
                JSONObject()
                    .put("name", name)
                    .put("enabled", enabled)
                    .put("trigger", trigger.toJsonObject())
                    .put("payload", payload.toJsonObject())
                    .put("policy", policy.toJsonObject())
                    .apply {
                        if (accountId.isNotBlank()) put("accountId", accountId)
                        if (agentId.isNotBlank()) put("agentId", agentId)
                    }
                    .toString(),
            )
    }
}

public class AutomationRun(rawJson: String) : RawJsonModel(rawJson) {
    public val runId: String get() = obj.optString("runId", obj.optString("run_id"))
    public val jobId: String get() = obj.optString("jobId", obj.optString("job_id"))
    public val status: String get() = obj.optString("status")
    public val triggerSource: String get() = obj.optString("triggerSource", obj.optString("trigger_source"))
    public val startedAt: Long get() = obj.optNullableLong("startedAt") ?: obj.optNullableLong("started_at") ?: 0L
    public val completedAt: Long? get() = obj.optNullableLong("completedAt") ?: obj.optNullableLong("completed_at")
    public val durationMs: Long? get() = obj.optNullableLong("durationMs") ?: obj.optNullableLong("duration_ms")
    public val sessionKeyJson: String? get() = obj.optNullableString("sessionKey") ?: obj.optNullableString("session_key")
    public val summary: String? get() = obj.optNullableString("summary")
    public val error: String? get() = obj.optNullableString("error")
    public val toolCallCount: Int get() = obj.optNullableInt("toolCallCount") ?: obj.optNullableInt("tool_call_count") ?: 0
    public val deliveryStatus: String get() = obj.optString("deliveryStatus", obj.optString("delivery_status", "unknown"))

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AutomationRun = AutomationRun(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AutomationRun = AutomationRun(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AutomationRun = fromJsonObject(JSONObject(map))
    }
}

public class AutomationWake(rawJson: String) : RawJsonModel(rawJson) {
    public val jobId: String get() = obj.optString("jobId", obj.optString("job_id"))
    public val atMs: Long get() = obj.optNullableLong("atMs") ?: obj.optNullableLong("at_ms") ?: 0L
    public val trigger: AutomationTrigger get() = AutomationTrigger((obj.optJSONObject("trigger") ?: JSONObject()).toString())

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AutomationWake = AutomationWake(rawJson)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AutomationWake = AutomationWake(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AutomationWake = fromJsonObject(JSONObject(map))
    }
}

public fun decodeJsonObjectOrNull(rawJson: String): JSONObject? =
    runCatching {
        JSONObject(rawJson).takeUnless { it.has("error") && !it.isNull("error") }
    }.getOrNull()

public fun decodeAutomationJobs(rawJson: String): List<AutomationJob> =
    rawJson.parseJsonArrayOrObjectList("jobs").map { AutomationJob(it.toString()) }

public fun decodeAutomationRuns(rawJson: String): List<AutomationRun> =
    rawJson.parseJsonArrayOrObjectList("runs").map { AutomationRun(it.toString()) }

public data class ResolvedFile(
    val sandboxPath: String,
    val realPath: String,
    val filename: String,
    val mimeType: String,
    val isImage: Boolean,
    val isDirectory: Boolean = false,
    val exists: Boolean,
    val sizeBytes: Long? = null,
    override val rawJson: String,
) : NapaxiJsonModel(rawJson) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("sandbox_path", sandboxPath)
        .put("real_path", realPath)
        .put("filename", filename)
        .put("mime_type", mimeType)
        .put("is_image", isImage)
        .put("is_directory", isDirectory)
        .put("exists", exists)
        .apply {
            sizeBytes?.let { put("size_bytes", it) }
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): ResolvedFile =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }), rawJson)

        public fun fromJsonObject(obj: JSONObject, rawJson: String = obj.toString()): ResolvedFile =
            ResolvedFile(
                sandboxPath = obj.optString("sandbox_path", obj.optString("sandboxPath")),
                realPath = obj.optString("real_path", obj.optString("realPath")),
                filename = obj.optString("filename"),
                mimeType = obj.optString("mime_type", obj.optString("mimeType", "application/octet-stream")),
                isImage = obj.optBoolean("is_image", obj.optBoolean("isImage", false)),
                isDirectory = obj.optBoolean("is_directory", obj.optBoolean("isDirectory", false)),
                exists = obj.optBoolean("exists", false),
                sizeBytes = obj.optNullableLong("size_bytes") ?: obj.optNullableLong("sizeBytes"),
                rawJson = rawJson,
            )

        public fun fromMap(map: Map<String, *>): ResolvedFile =
            fromJsonObject(JSONObject(map))
    }
}

public data class WorkspaceFileInfo(
    val name: String,
    val sandboxPath: String,
    val realPath: String,
    val mimeType: String,
    val isDirectory: Boolean,
    val sizeBytes: Long,
    val modified: Long,
    override val rawJson: String,
) : NapaxiJsonModel(rawJson) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("name", name)
        .put("sandbox_path", sandboxPath)
        .put("real_path", realPath)
        .put("mime_type", mimeType)
        .put("is_directory", isDirectory)
        .put("size_bytes", sizeBytes)
        .put("modified", modified)

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): WorkspaceFileInfo =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }), rawJson)

        public fun fromJsonObject(obj: JSONObject, rawJson: String = obj.toString()): WorkspaceFileInfo =
            WorkspaceFileInfo(
                name = obj.optString("name"),
                sandboxPath = obj.optString("sandbox_path", obj.optString("sandboxPath")),
                realPath = obj.optString("real_path", obj.optString("realPath")),
                mimeType = obj.optString("mime_type", obj.optString("mimeType", "application/octet-stream")),
                isDirectory = obj.optBoolean("is_directory", obj.optBoolean("isDirectory", false)),
                sizeBytes = obj.optLong("size_bytes", obj.optLong("sizeBytes", 0L)),
                modified = obj.optLong("modified", 0L),
                rawJson = rawJson,
            )

        public fun fromMap(map: Map<String, *>): WorkspaceFileInfo =
            fromJsonObject(JSONObject(map))
    }
}

public data class SkillRemediationAction(
    val id: String,
    val kind: String = "",
    val label: String = "",
    val requirement: String = "",
    val hostHandled: Boolean = true,
    val dangerLevel: String = "low",
    val title: String = label,
    val rawJson: String = "{}",
) {
    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" }).takeIf { it.length() > 0 }
        ?: JSONObject()
            .put("id", id)
            .put("kind", kind)
            .put("label", label)
            .put("requirement", requirement)
            .put("host_handled", hostHandled)
            .put("danger_level", dangerLevel)

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): SkillRemediationAction =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): SkillRemediationAction =
            SkillRemediationAction(
                id = obj.optString("id"),
                kind = obj.optString("kind"),
                label = obj.optString("label", obj.optString("title")),
                requirement = obj.optString("requirement"),
                hostHandled = obj.optBoolean("host_handled", obj.optBoolean("hostHandled", true)),
                dangerLevel = obj.optString("danger_level", obj.optString("dangerLevel", "low")),
                rawJson = obj.toString(),
            )

        public fun fromMap(map: Map<String, *>): SkillRemediationAction =
            fromJsonObject(JSONObject(map))
    }
}

public data class SkillInstallExtraFile(
    val path: String,
    val content: String,
    val contentBase64: String = java.util.Base64.getEncoder().encodeToString(content.toByteArray(Charsets.UTF_8)),
) {
    public constructor(path: String, bytes: ByteArray) : this(
        path = path,
        content = bytes.toString(Charsets.UTF_8),
        contentBase64 = java.util.Base64.getEncoder().encodeToString(bytes),
    )

    public val bytes: ByteArray
        get() = java.util.Base64.getDecoder().decode(contentBase64)

    fun toJsonObject(): JSONObject = JSONObject()
        .put("path", path)
        .put("content_base64", contentBase64)

    public companion object {
        @JvmStatic
        public fun fromBytes(path: String, bytes: ByteArray): SkillInstallExtraFile =
            SkillInstallExtraFile(path, bytes)
    }
}

public data class SkillInstallInput(
    val skillMd: String,
    val extraFiles: List<SkillInstallExtraFile> = emptyList(),
) {
    val skillContent: String get() = skillMd

    fun toInstallPayloadJson(): String = JSONObject()
        .put("skill_md", skillMd)
        .put("extra_files", JSONArray(extraFiles.map { it.toJsonObject() }))
        .toString()
}

public data class AgentAppInstallBinding(
    val platform: String = "android",
    val appPackageName: String,
    val activityName: String,
    val signingCertSha256: String,
    val installedAt: String,
    val installRequestId: String,
    val protocolVersion: Int = 2,
    val hostPackageName: String = "",
    val hostSigningCertSha256: String = "",
    val hostInstanceId: String = "",
    val hostSharedSecret: String = "",
    val backgroundTriggerSupported: Boolean = false,
    val hostBackgroundTriggerService: String = "",
    val iosBundleId: String = "",
    val iosTeamId: String = "",
    val installUrl: String = "",
    val actionUrl: String = "",
    val universalLinkDomain: String = "",
    val hostBundleId: String = "",
    val hostTeamId: String = "",
    val hostCallbackScheme: String = "",
) {
    fun toJsonObject(): JSONObject = JSONObject()
        .put("platform", platform)
        .put("app_package_name", appPackageName)
        .put("activity_name", activityName)
        .put("signing_cert_sha256", signingCertSha256)
        .put("installed_at", installedAt)
        .put("install_request_id", installRequestId)
        .put("protocol_version", protocolVersion)
        .apply {
            if (hostPackageName.isNotBlank()) put("host_package_name", hostPackageName)
            if (hostSigningCertSha256.isNotBlank()) put("host_signing_cert_sha256", hostSigningCertSha256)
            if (hostInstanceId.isNotBlank()) put("host_instance_id", hostInstanceId)
            if (hostSharedSecret.isNotBlank()) put("host_shared_secret", hostSharedSecret)
            if (backgroundTriggerSupported) put("background_trigger_supported", true)
            if (hostBackgroundTriggerService.isNotBlank()) {
                put("host_background_trigger_service", hostBackgroundTriggerService)
            }
            if (iosBundleId.isNotBlank()) put("ios_bundle_id", iosBundleId)
            if (iosTeamId.isNotBlank()) put("ios_team_id", iosTeamId)
            if (installUrl.isNotBlank()) put("install_url", installUrl)
            if (actionUrl.isNotBlank()) put("action_url", actionUrl)
            if (universalLinkDomain.isNotBlank()) put("universal_link_domain", universalLinkDomain)
            if (hostBundleId.isNotBlank()) put("host_bundle_id", hostBundleId)
            if (hostTeamId.isNotBlank()) put("host_team_id", hostTeamId)
            if (hostCallbackScheme.isNotBlank()) put("host_callback_scheme", hostCallbackScheme)
        }

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJson(rawJson: String): AgentAppInstallBinding =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        public fun fromJsonObject(obj: JSONObject): AgentAppInstallBinding =
            AgentAppInstallBinding(
                platform = obj.optString("platform"),
                appPackageName = obj.optString("app_package_name"),
                activityName = obj.optString("activity_name"),
                signingCertSha256 = obj.optString("signing_cert_sha256"),
                installedAt = obj.optString("installed_at"),
                installRequestId = obj.optString("install_request_id"),
                protocolVersion = obj.optInt("protocol_version", 1),
                hostPackageName = obj.optString("host_package_name"),
                hostSigningCertSha256 = obj.optString("host_signing_cert_sha256"),
                hostInstanceId = obj.optString("host_instance_id"),
                hostSharedSecret = obj.optString("host_shared_secret"),
                backgroundTriggerSupported = obj.optBoolean("background_trigger_supported", false),
                hostBackgroundTriggerService = obj.optString("host_background_trigger_service"),
                iosBundleId = obj.optString("ios_bundle_id"),
                iosTeamId = obj.optString("ios_team_id"),
                installUrl = obj.optString("install_url"),
                actionUrl = obj.optString("action_url"),
                universalLinkDomain = obj.optString("universal_link_domain"),
                hostBundleId = obj.optString("host_bundle_id"),
                hostTeamId = obj.optString("host_team_id"),
                hostCallbackScheme = obj.optString("host_callback_scheme"),
            )

        public fun fromMap(map: Map<String, *>): AgentAppInstallBinding =
            fromJsonObject(JSONObject(map))
    }
}

public class AgentAppPackage(rawJson: String) : RawJsonModel(rawJson) {
    public constructor(
        providerId: String,
        agentId: String,
        displayName: String,
        description: String = "",
        systemPrompt: String = "",
        actions: List<AgentAppActionManifest> = emptyList(),
        handoff: JSONObject = JSONObject(),
        result: JSONObject = JSONObject(),
        installBinding: AgentAppInstallBinding? = null,
        createdAt: String = "",
        updatedAt: String = "",
    ) : this(
        JSONObject()
            .put("provider_id", providerId)
            .put("agent_id", agentId)
            .put("display_name", displayName)
            .put("description", description)
            .put("system_prompt", systemPrompt)
            .put("actions", JSONArray(actions.map { it.toJsonObject() }))
            .put("handoff", handoff)
            .put("result", result)
            .apply {
                installBinding?.let { put("install_binding", it.toJsonObject()) }
                if (createdAt.isNotBlank()) put("created_at", createdAt)
                if (updatedAt.isNotBlank()) put("updated_at", updatedAt)
            }
            .toString(),
    )

    public val providerId: String get() = obj.optString("provider_id")
    public val agentId: String get() = obj.optString("agent_id")
    public val displayName: String get() = obj.optString("display_name")
    public val description: String get() = obj.optString("description")
    public val systemPrompt: String get() = obj.optString("system_prompt")
    public val handoffJson: String get() = (obj.optJSONObject("handoff") ?: JSONObject()).toString()
    public val handoff: JSONObject get() = JSONObject(handoffJson)
    public val result: JSONObject get() = obj.optJSONObject("result") ?: JSONObject()
    public val actions: List<AgentAppPackageAction>
        get() = obj.optJSONArray("actions")?.toJsonObjectList()?.map { AgentAppPackageAction(it.toString()) }.orEmpty()
    public val installBinding: AgentAppInstallBinding?
        get() = obj.optJSONObject("install_binding")?.let {
            AgentAppInstallBinding.fromJsonObject(it)
        }
    public val createdAt: String get() = obj.optString("created_at")
    public val updatedAt: String get() = obj.optString("updated_at")

    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = rawJson
    public fun toJsonString(): String = rawJson

    public companion object {
        public fun fromJsonObject(obj: JSONObject): AgentAppPackage =
            AgentAppPackage(obj.toString())

        public fun fromMap(map: Map<String, *>): AgentAppPackage =
            fromJsonObject(JSONObject(map))
    }
}

public class AgentAppActionManifest(rawJson: String) : RawJsonModel(rawJson) {
    public constructor(
        actionId: String,
        toolName: String,
        description: String,
        parameters: JSONObject = JSONObject("""{"type":"object","properties":{}}"""),
        resultSchema: JSONObject = JSONObject("""{"type":"object"}"""),
        risk: String = "high",
        confirmationPolicy: String = "provider_required",
        executionModes: List<String> = emptyList(),
        timeoutSeconds: Int = 600,
    ) : this(
        JSONObject()
            .put("action_id", actionId)
            .put("tool_name", toolName)
            .put("description", description)
            .put("parameters", parameters)
            .put("result_schema", resultSchema)
            .put("risk", risk)
            .put("confirmation_policy", confirmationPolicy)
            .put("execution_modes", JSONArray(executionModes))
            .put("timeout_seconds", timeoutSeconds)
            .toString(),
    )

    public val actionId: String get() = obj.optString("action_id")
    public val toolName: String get() = obj.optString("tool_name")
    public val description: String get() = obj.optString("description")
    public val parameters: JSONObject get() = obj.optJSONObject("parameters") ?: JSONObject("""{"type":"object","properties":{}}""")
    public val resultSchema: JSONObject get() = obj.optJSONObject("result_schema") ?: JSONObject("""{"type":"object"}""")
    public val risk: String get() = obj.optString("risk", "high")
    public val confirmationPolicy: String get() = obj.optString("confirmation_policy", "provider_required")
    public val executionModes: List<String> get() = obj.optJSONArray("execution_modes")?.toStringList().orEmpty()
    public val timeoutSeconds: Int get() = obj.optInt("timeout_seconds", 600)

    public fun toJsonObject(): JSONObject = JSONObject()
        .put("action_id", actionId)
        .put("tool_name", toolName)
        .put("description", description)
        .put("parameters", parameters)
        .put("result_schema", resultSchema)
        .put("risk", risk)
        .put("confirmation_policy", confirmationPolicy)
        .put("execution_modes", JSONArray(executionModes))
        .put("timeout_seconds", timeoutSeconds)

    public fun toJson(): String = toJsonObject().toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        public fun fromJsonObject(obj: JSONObject): AgentAppActionManifest =
            AgentAppActionManifest(obj.toString())

        public fun fromMap(map: Map<String, *>): AgentAppActionManifest =
            fromJsonObject(JSONObject(map))
    }
}

public typealias AgentAppPackageAction = AgentAppActionManifest

public class AgentAppActionProposal(rawJson: String) : RawJsonModel(rawJson) {
    public constructor(
        requestId: String,
        providerId: String,
        agentId: String,
        actionId: String,
        toolName: String,
        arguments: JSONObject = JSONObject(),
        userIntentSummary: String = "",
        createdAt: String = "",
        expiresAt: String = "",
        nonce: String = "",
        idempotencyKey: String = "",
        callback: JSONObject = JSONObject(),
        risk: String = "high",
        confirmationPolicy: String = "provider_required",
        hostInstanceId: String = "",
        signatureAlgorithm: String = "",
        signature: String? = null,
    ) : this(
        JSONObject()
            .put("request_id", requestId)
            .put("provider_id", providerId)
            .put("agent_id", agentId)
            .put("action_id", actionId)
            .put("tool_name", toolName)
            .put("arguments", arguments)
            .put("user_intent_summary", userIntentSummary)
            .put("created_at", createdAt)
            .put("expires_at", expiresAt)
            .put("nonce", nonce)
            .put("idempotency_key", idempotencyKey)
            .put("callback", callback)
            .put("risk", risk)
            .put("confirmation_policy", confirmationPolicy)
            .apply {
                if (hostInstanceId.isNotBlank()) put("host_instance_id", hostInstanceId)
                if (signatureAlgorithm.isNotBlank()) put("signature_algorithm", signatureAlgorithm)
                signature?.let { put("signature", it) }
            }
            .toString(),
    )

    public val requestId: String get() = obj.optString("request_id")
    public val providerId: String get() = obj.optString("provider_id")
    public val agentId: String get() = obj.optString("agent_id")
    public val actionId: String get() = obj.optString("action_id")
    public val toolName: String get() = obj.optString("tool_name")
    public val arguments: JSONObject get() = obj.optJSONObject("arguments") ?: JSONObject()
    public val userIntentSummary: String get() = obj.optString("user_intent_summary")
    public val createdAt: String get() = obj.optString("created_at")
    public val nonce: String get() = obj.optString("nonce")
    public val idempotencyKey: String get() = obj.optString("idempotency_key")
    public val expiresAt: String get() = obj.optString("expires_at")
    public val callback: JSONObject get() = obj.optJSONObject("callback") ?: JSONObject()
    public val risk: String get() = obj.optString("risk", "high")
    public val confirmationPolicy: String get() = obj.optString("confirmation_policy", "provider_required")
    public val hostInstanceId: String get() = obj.optString("host_instance_id")
    public val signatureAlgorithm: String get() = obj.optString("signature_algorithm")
    public val signature: String? get() = obj.optNullableString("signature")
    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = rawJson
    public fun toJsonString(): String = rawJson

    public companion object {
        public fun fromJsonObject(obj: JSONObject): AgentAppActionProposal =
            AgentAppActionProposal(obj.toString())

        public fun fromMap(map: Map<String, *>): AgentAppActionProposal =
            fromJsonObject(JSONObject(map))
    }
}

public class AgentAppActionResult(rawJson: String) : RawJsonModel(rawJson) {
    public constructor(
        requestId: String,
        status: String,
        result: JSONObject = JSONObject(),
        error: String? = null,
        providerTraceId: String? = null,
        completedAt: String = "",
        signature: String? = null,
    ) : this(
        JSONObject()
            .put("request_id", requestId)
            .put("status", status)
            .put("result", result)
            .apply {
                error?.let { put("error", it) }
                providerTraceId?.let { put("provider_trace_id", it) }
                put("completed_at", completedAt)
                signature?.let { put("signature", it) }
            }
            .toString(),
    )

    public val requestId: String get() = obj.optString("request_id")
    public val status: String get() = obj.optString("status")
    public val result: JSONObject get() = obj.optJSONObject("result") ?: JSONObject()
    public val error: String? get() = obj.optNullableString("error")
    public val providerTraceId: String? get() = obj.optNullableString("provider_trace_id")
    public val completedAt: String get() = obj.optString("completed_at")
    public val signature: String? get() = obj.optNullableString("signature")
    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = rawJson
    public fun toJsonString(): String = rawJson

    public companion object {
        public fun fromJsonObject(obj: JSONObject): AgentAppActionResult =
            AgentAppActionResult(obj.toString())

        public fun fromMap(map: Map<String, *>): AgentAppActionResult =
            fromJsonObject(JSONObject(map))
    }
}

public class AgentAppActionRecord(rawJson: String) : RawJsonModel(rawJson) {
    public constructor(
        proposal: AgentAppActionProposal,
        status: String,
        result: AgentAppActionResult? = null,
        createdAt: String = "",
        updatedAt: String = "",
    ) : this(
        JSONObject()
            .put("proposal", proposal.toJsonObject())
            .put("status", status)
            .apply {
                result?.let { put("result", it.toJsonObject()) }
                put("created_at", createdAt)
                put("updated_at", updatedAt)
            }
            .toString(),
    )

    public val proposal: AgentAppActionProposal
        get() = AgentAppActionProposal((obj.optJSONObject("proposal") ?: JSONObject()).toString())
    public val status: String get() = obj.optString("status")
    public val result: AgentAppActionResult?
        get() = obj.optJSONObject("result")?.let { AgentAppActionResult(it.toString()) }
    public val createdAt: String get() = obj.optString("created_at")
    public val updatedAt: String get() = obj.optString("updated_at")
    public fun toJsonObject(): JSONObject = JSONObject(rawJson.ifBlank { "{}" })
    public fun toJson(): String = rawJson
    public fun toJsonString(): String = rawJson

    public companion object {
        public fun fromJsonObject(obj: JSONObject): AgentAppActionRecord =
            AgentAppActionRecord(obj.toString())

        public fun fromMap(map: Map<String, *>): AgentAppActionRecord =
            fromJsonObject(JSONObject(map))
    }
}

public fun decodeAgentAppPackages(rawJson: String): List<AgentAppPackage> =
    rawJson.parseJsonArrayOrObjectList("packages").map { AgentAppPackage.fromJsonObject(it) }

public fun decodeAgentAppActionRecords(rawJson: String): List<AgentAppActionRecord> =
    rawJson.parseJsonArrayOrObjectList("proposals").map { AgentAppActionRecord.fromJsonObject(it) }

public class AcceptedAgentTrigger(rawJson: String) : RawJsonModel(rawJson) {
    private val trigger: JSONObject get() = obj.optJSONObject("trigger") ?: JSONObject()
    public val request: AgentTriggerRequest? get() = runCatching { AgentTriggerRequest.fromJson(requestJson) }.getOrNull()
    public val requestJson: String get() = trigger.toString()
    public val requestId: String get() = trigger.optString("request_id")
    public val providerId: String get() = trigger.optString("provider_id")
    public val agentId: String get() = trigger.optString("agent_id")
    public val message: String get() = trigger.optString("message")
    public val source: String get() = trigger.optString("source")
    public val eventType: String get() = trigger.optString("event_type")
    public val status: String get() = obj.optString("status")
    public val displayName: String
        get() = obj.optString("display_name")
            .takeIf { it.isNotBlank() }
            ?: obj.optString("displayName").takeIf { it.isNotBlank() }
            ?: agentId
}

public sealed class ChatEvent {
    abstract val type: String
    abstract val rawJson: String

    public data class RunStartedEvent(
        override val rawJson: String,
        val runId: String,
        val sessionKey: String,
        val agentId: String,
    ) : ChatEvent() {
        override val type: String = "run_started"
    }

    public data class RunProgressEvent(
        override val rawJson: String,
        val runId: String,
        val kind: String,
        val message: String,
    ) : ChatEvent() {
        override val type: String = "run_progress"
    }

    public data class RunCompletedEvent(
        override val rawJson: String,
        val runId: String,
        val status: String,
        val evidenceKind: String,
        val verification: String,
        val toolCallCount: Int = 0,
    ) : ChatEvent() {
        override val type: String = "run_completed"
        public val isUnverified: Boolean get() = status == "unverified" || verification == "unverified"
    }

    public data class ResponseEvent(
        override val rawJson: String,
        val content: String,
    ) : ChatEvent() {
        override val type: String = "response"
    }

    public data class ResponseDeltaEvent(
        override val rawJson: String,
        val content: String,
    ) : ChatEvent() {
        override val type: String = "response_delta"
    }

    public data class ReasoningDeltaEvent(
        override val rawJson: String,
        val content: String,
    ) : ChatEvent() {
        override val type: String = "reasoning_delta"
    }

    public data class ThinkingEvent(
        override val rawJson: String,
        val content: String,
    ) : ChatEvent() {
        override val type: String = "thinking"
    }

    public data class ToolCallEvent(
        override val rawJson: String,
        val callId: String,
        val name: String,
        val argumentsJson: String,
    ) : ChatEvent() {
        override val type: String = "tool_call"
        public val toolName: String get() = name
        public val arguments: String get() = argumentsJson
    }

    public data class ToolCallDeltaEvent(
        override val rawJson: String,
        val callId: String,
        val name: String,
        val argumentsDelta: String,
        val argumentsSoFar: String,
    ) : ChatEvent() {
        override val type: String = "tool_call_delta"
    }

    public data class ToolResultEvent(
        override val rawJson: String,
        val callId: String,
        val name: String,
        val output: String,
        val isError: Boolean,
    ) : ChatEvent() {
        override val type: String = "tool_result"
        public val toolName: String get() = name
        public val result: String get() = output
    }

    public data class ErrorEvent(
        override val rawJson: String,
        val message: String,
    ) : ChatEvent() {
        override val type: String = "error"
    }

    public data class AgentDelegationEvent(
        override val rawJson: String,
        val fromAgent: String,
        val toAgent: String,
        val message: String,
    ) : ChatEvent() {
        override val type: String = "agent_delegation"
    }

    public data class AgentDelegationResultEvent(
        override val rawJson: String,
        val fromAgent: String,
        val toAgent: String,
        val content: String,
        val isError: Boolean,
    ) : ChatEvent() {
        override val type: String = "agent_delegation_result"
    }

    public data class AgentToolCallEvent(
        override val rawJson: String,
        val callId: String,
        val name: String,
        val argumentsJson: String,
        val agentId: String,
    ) : ChatEvent() {
        override val type: String = "agent_tool_call"
        public val toolName: String get() = name
        public val arguments: String get() = argumentsJson
    }

    public data class AgentToolCallDeltaEvent(
        override val rawJson: String,
        val callId: String,
        val name: String,
        val argumentsDelta: String,
        val argumentsSoFar: String,
        val agentId: String,
    ) : ChatEvent() {
        override val type: String = "agent_tool_call_delta"
    }

    public data class AgentToolResultEvent(
        override val rawJson: String,
        val callId: String,
        val name: String,
        val output: String,
        val isError: Boolean,
        val agentId: String,
    ) : ChatEvent() {
        override val type: String = "agent_tool_result"
        public val toolName: String get() = name
        public val result: String get() = output
    }

    public data class GroupDelegationEvent(
        override val rawJson: String,
        val groupId: String,
        val fromAgent: String,
        val toAgent: String,
        val task: String,
    ) : ChatEvent() {
        override val type: String = "group_delegation"
    }

    public data class GroupDelegationResultEvent(
        override val rawJson: String,
        val groupId: String,
        val fromAgent: String,
        val toAgent: String,
        val result: String,
        val isError: Boolean,
    ) : ChatEvent() {
        override val type: String = "group_delegation_result"
    }

    public data class ImageGeneratedEvent(
        override val rawJson: String,
        val dataUrl: String,
        val path: String?,
    ) : ChatEvent() {
        override val type: String = "image_generated"
    }

    public data class ToolOutputChunkEvent(
        override val rawJson: String,
        val callId: String,
        val content: String,
        val stream: String,
    ) : ChatEvent() {
        override val type: String = "tool_output_chunk"
    }

    public data class MessageInjectedEvent(
        override val rawJson: String,
        val content: String,
    ) : ChatEvent() {
        override val type: String = "message_injected"
    }

    public data class AskingHumanEvent(
        override val rawJson: String,
        val question: String,
        val requestId: String,
        val options: List<String> = emptyList(),
        val context: String? = null,
    ) : ChatEvent() {
        override val type: String = "asking_human"
    }

    public data class HumanResponseEvent(
        override val rawJson: String,
        val requestId: String,
        val response: String,
    ) : ChatEvent() {
        override val type: String = "human_response"
    }

    public data class ContextCompactingEvent(
        override val rawJson: String,
        val usagePercent: Double,
        val strategy: String,
    ) : ChatEvent() {
        override val type: String = "context_compacting"
    }

    public data class ContextCompactedEvent(
        override val rawJson: String,
        val turnsRemoved: Int,
        val tokensBefore: Int,
        val tokensAfter: Int,
    ) : ChatEvent() {
        override val type: String = "context_compacted"
    }

    public data class MemoryEvolvedEvent(
        override val rawJson: String,
        val target: String,
        val content: String,
    ) : ChatEvent() {
        override val type: String = "memory_evolved"
    }

    public data class SkillEvolvedEvent(
        override val rawJson: String,
        val skillName: String,
        val action: String,
        val summary: String,
    ) : ChatEvent() {
        override val type: String = "skill_evolved"
    }

    public data class EvolutionQueuedRun(
        val id: String,
        val reviewType: String,
    ) {
        public companion object {
            @JvmStatic
            public fun fromJsonObject(obj: JSONObject): EvolutionQueuedRun =
                EvolutionQueuedRun(
                    id = obj.str("id"),
                    reviewType = obj.str("review_type").ifBlank { obj.str("reviewType") },
                )

            @JvmStatic
            public fun fromMap(map: Map<String, *>): EvolutionQueuedRun =
                fromJsonObject(JSONObject(map))
        }
    }

    public data class EvolutionQueuedEvent(
        override val rawJson: String,
        val reviewTypes: List<String>,
        val runs: List<EvolutionQueuedRun> = emptyList(),
    ) : ChatEvent() {
        override val type: String = "evolution_queued"
        public val runIds: List<String> get() = runs.map { it.id }
    }

    public data class ActivatedSkillInfo(
        val name: String,
        val version: String = "",
        val description: String = "",
        val trust: String = "",
        val reason: String = "",
    ) {
        public companion object {
            @JvmStatic
            public fun fromJsonObject(obj: JSONObject): ActivatedSkillInfo =
                ActivatedSkillInfo(
                    name = obj.str("name"),
                    version = obj.str("version"),
                    description = obj.str("description"),
                    trust = obj.str("trust"),
                    reason = obj.str("reason"),
                )

            @JvmStatic
            public fun fromMap(map: Map<String, *>): ActivatedSkillInfo =
                fromJsonObject(JSONObject(map))
        }
    }

    public data class SkillActivatedEvent(
        override val rawJson: String,
        val agentId: String,
        val skills: List<ActivatedSkillInfo>,
    ) : ChatEvent() {
        override val type: String = "skill_activated"
    }

    public data class ActionProposalCreatedEvent(
        override val rawJson: String,
        val requestId: String,
        val providerId: String,
        val agentId: String,
        val actionId: String,
        val toolName: String,
        val risk: String,
        val expiresAt: String,
    ) : ChatEvent() {
        override val type: String = "action_proposal_created"
    }

    public data class ActionHandoffStartedEvent(
        override val rawJson: String,
        val requestId: String,
        val mode: String,
    ) : ChatEvent() {
        override val type: String = "action_handoff_started"
    }

    public data class ActionWaitingForProviderEvent(
        override val rawJson: String,
        val requestId: String,
        val providerId: String,
    ) : ChatEvent() {
        override val type: String = "action_waiting_for_provider"
    }

    public data class ActionResultReceivedEvent(
        override val rawJson: String,
        val requestId: String,
        val status: String,
        val providerTraceId: String?,
    ) : ChatEvent() {
        override val type: String = "action_result_received"
    }

    public data class ActionExpiredEvent(
        override val rawJson: String,
        val requestId: String,
    ) : ChatEvent() {
        override val type: String = "action_expired"
    }

    public data class ActionFailedEvent(
        override val rawJson: String,
        val requestId: String,
        val message: String,
    ) : ChatEvent() {
        override val type: String = "action_failed"
    }

    public data class InterruptedEvent(
        override val rawJson: String,
    ) : ChatEvent() {
        override val type: String = "interrupted"
    }

    /**
     * The in-flight LLM stream dropped or stalled and is being retried. The UI
     * should discard any partial assistant content/reasoning streamed so far
     * for the current turn and wait for the reconnected stream to repopulate
     * it. No history side effects have occurred yet.
     */
    public data class StreamResetEvent(
        override val rawJson: String,
        val reason: String,
    ) : ChatEvent() {
        override val type: String = "stream_reset"
    }

    public data class RawEvent(
        override val type: String,
        override val rawJson: String,
    ) : ChatEvent()

    public companion object {
        public fun flutterParityEventTypes(): Set<String> = setOf(
            "run_started",
            "run_progress",
            "run_completed",
            "tool_call",
            "tool_call_delta",
            "tool_result",
            "response",
            "response_delta",
            "reasoning_delta",
            "thinking",
            "error",
            "agent_delegation",
            "agent_delegation_result",
            "agent_tool_call",
            "agent_tool_call_delta",
            "agent_tool_result",
            "group_delegation",
            "group_delegation_result",
            "image_generated",
            "tool_output_chunk",
            "message_injected",
            "asking_human",
            "human_response",
            "context_compacting",
            "context_compacted",
            "memory_evolved",
            "skill_evolved",
            "evolution_queued",
            "skill_activated",
            "action_proposal_created",
            "action_handoff_started",
            "action_waiting_for_provider",
            "action_result_received",
            "action_expired",
            "action_failed",
            "interrupted",
            "stream_reset",
        )

        @JvmStatic
        public fun fromJsonString(json: String): ChatEvent = fromJson(json)

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): ChatEvent =
            fromJson(obj.toString())

        @JvmStatic
        public fun fromMap(map: Map<String, *>): ChatEvent =
            fromJsonObject(JSONObject(map))

        @JvmStatic
        public fun fromJson(json: String): ChatEvent {
            val obj = JSONObject(json.ifBlank { "{}" })
            val type = obj.optString("type", "unknown")
            return when (type) {
                "run_started" -> RunStartedEvent(json, obj.str("run_id"), obj.str("session_key"), obj.str("agent_id"))
                "run_progress" -> RunProgressEvent(json, obj.str("run_id"), obj.str("kind"), obj.str("message"))
                "run_completed" -> RunCompletedEvent(
                    json,
                    obj.str("run_id"),
                    obj.str("status"),
                    obj.str("evidence_kind"),
                    obj.str("verification"),
                    obj.optInt("tool_call_count", 0),
                )
                "tool_call" -> ToolCallEvent(json, obj.str("call_id"), obj.toolName(), obj.argumentsString())
                "tool_call_delta" -> ToolCallDeltaEvent(
                    json,
                    obj.str("call_id"),
                    obj.toolName(),
                    obj.str("arguments_delta"),
                    obj.str("arguments_so_far"),
                )
                "tool_result" -> ToolResultEvent(json, obj.str("call_id"), obj.toolName(), obj.outputString(), obj.optBoolean("is_error"))
                "response" -> ResponseEvent(json, obj.contentString())
                "response_delta" -> ResponseDeltaEvent(json, obj.contentString())
                "reasoning_delta" -> ReasoningDeltaEvent(json, obj.contentString())
                "thinking" -> ThinkingEvent(json, obj.contentString())
                "error" -> ErrorEvent(json, obj.optString("message", obj.optString("error")))
                "agent_delegation" -> AgentDelegationEvent(json, obj.str("from_agent"), obj.str("to_agent"), obj.str("message"))
                "agent_delegation_result" -> AgentDelegationResultEvent(
                    json,
                    obj.str("from_agent"),
                    obj.str("to_agent"),
                    obj.contentString(),
                    obj.optBoolean("is_error"),
                )
                "agent_tool_call" -> AgentToolCallEvent(
                    json,
                    obj.str("call_id"),
                    obj.toolName(),
                    obj.argumentsString(),
                    obj.str("agent_id"),
                )
                "agent_tool_call_delta" -> AgentToolCallDeltaEvent(
                    json,
                    obj.str("call_id"),
                    obj.toolName(),
                    obj.str("arguments_delta"),
                    obj.str("arguments_so_far"),
                    obj.str("agent_id"),
                )
                "agent_tool_result" -> AgentToolResultEvent(
                    json,
                    obj.str("call_id"),
                    obj.toolName(),
                    obj.outputString(),
                    obj.optBoolean("is_error"),
                    obj.str("agent_id"),
                )
                "group_delegation" -> GroupDelegationEvent(
                    json,
                    obj.str("group_id"),
                    obj.str("from_agent"),
                    obj.str("to_agent"),
                    obj.str("task"),
                )
                "group_delegation_result" -> GroupDelegationResultEvent(
                    json,
                    obj.str("group_id"),
                    obj.str("from_agent"),
                    obj.str("to_agent"),
                    obj.str("result"),
                    obj.optBoolean("is_error"),
                )
                "image_generated" -> ImageGeneratedEvent(json, obj.str("data_url"), obj.optNullableString("path"))
                "tool_output_chunk" -> ToolOutputChunkEvent(json, obj.str("call_id"), obj.contentString(), obj.str("stream"))
                "message_injected" -> MessageInjectedEvent(json, obj.contentString())
                "asking_human" -> AskingHumanEvent(
                    json,
                    obj.str("question"),
                    obj.str("request_id"),
                    obj.optJSONArray("options")?.toStringList().orEmpty(),
                    obj.optNullableString("context"),
                )
                "human_response" -> HumanResponseEvent(json, obj.str("request_id"), obj.str("response"))
                "context_compacting" -> ContextCompactingEvent(
                    json,
                    obj.optDouble("usage_percent"),
                    obj.str("strategy"),
                )
                "context_compacted" -> ContextCompactedEvent(
                    json,
                    obj.optInt("turns_removed"),
                    obj.optInt("tokens_before"),
                    obj.optInt("tokens_after"),
                )
                "memory_evolved" -> MemoryEvolvedEvent(json, obj.str("target"), obj.contentString())
                "skill_evolved" -> SkillEvolvedEvent(json, obj.str("skill_name"), obj.str("action"), obj.str("summary"))
                "evolution_queued" -> EvolutionQueuedEvent(
                    json,
                    obj.optJSONArray("review_types")?.toStringList().orEmpty(),
                    obj.optJSONArray("runs")?.toJsonObjectList()?.map {
                        EvolutionQueuedRun.fromJsonObject(it)
                    }.orEmpty(),
                )
                "skill_activated" -> SkillActivatedEvent(
                    json,
                    obj.str("agent_id"),
                    obj.optJSONArray("skills")?.toJsonObjectList()?.map {
                        ActivatedSkillInfo.fromJsonObject(it)
                    }.orEmpty(),
                )
                "action_proposal_created" -> ActionProposalCreatedEvent(
                    json,
                    obj.str("request_id"),
                    obj.str("provider_id"),
                    obj.str("agent_id"),
                    obj.str("action_id"),
                    obj.str("tool_name"),
                    obj.str("risk"),
                    obj.str("expires_at"),
                )
                "action_handoff_started" -> ActionHandoffStartedEvent(json, obj.str("request_id"), obj.str("mode"))
                "action_waiting_for_provider" -> ActionWaitingForProviderEvent(json, obj.str("request_id"), obj.str("provider_id"))
                "action_result_received" -> ActionResultReceivedEvent(
                    json,
                    obj.str("request_id"),
                    obj.str("status"),
                    obj.optNullableString("provider_trace_id"),
                )
                "action_expired" -> ActionExpiredEvent(json, obj.str("request_id"))
                "action_failed" -> ActionFailedEvent(json, obj.str("request_id"), obj.str("message"))
                "interrupted" -> InterruptedEvent(json)
                "stream_reset" -> StreamResetEvent(json, obj.str("reason"))
                else -> RawEvent(type = type, rawJson = json)
            }
        }
    }
}

private fun JSONObject.str(name: String): String = optString(name)

private fun JSONObject.toolName(): String = optString("tool_name", optString("name"))

private fun JSONObject.contentString(): String = optString("content", optString("delta"))

private fun JSONObject.argumentsString(): String {
    optString("arguments", "").takeIf { it.isNotEmpty() }?.let { return it }
    optString("arguments_json", "").takeIf { it.isNotEmpty() }?.let { return it }
    return optJSONObject("arguments")?.toString() ?: ""
}

private fun JSONObject.outputString(): String = optString("output", optString("result"))

internal fun JSONArray.toStringList(): List<String> {
    val values = ArrayList<String>(length())
    for (index in 0 until length()) {
        values += optString(index)
    }
    return values
}

internal fun JSONArray.toJsonObjectList(): List<JSONObject> {
    val values = ArrayList<JSONObject>(length())
    for (index in 0 until length()) {
        optJSONObject(index)?.let { values += it }
    }
    return values
}

internal fun JSONArray.toLongList(): List<Long> {
    val values = ArrayList<Long>(length())
    for (index in 0 until length()) {
        val value = opt(index)
        when (value) {
            is Number -> values += value.toLong()
            is String -> value.toLongOrNull()?.let(values::add)
        }
    }
    return values
}

internal fun String.parseJsonArrayOrObjectList(key: String): List<JSONObject> {
    return try {
        val trimmed = trim()
        when {
            trimmed.startsWith("[") -> JSONArray(trimmed).toJsonObjectList()
            trimmed.startsWith("{") -> {
                val obj = JSONObject(trimmed)
                obj.optJSONArray(key)?.toJsonObjectList() ?: emptyList()
            }
            else -> emptyList()
        }
    } catch (_: JSONException) {
        emptyList()
    }
}

internal fun JSONArray.toStringMapList(): List<Map<String, String>> {
    val values = ArrayList<Map<String, String>>(length())
    for (index in 0 until length()) {
        val obj = optJSONObject(index) ?: continue
        values += obj.keys().asSequence().associateWith { key -> obj.optString(key) }
    }
    return values
}

internal fun JSONObject.toStringMap(): Map<String, String> =
    keys().asSequence().associateWith { key -> optString(key) }

internal fun JSONObject.toIntMap(): Map<String, Int> =
    keys().asSequence().associateWith { key -> optInt(key, 0) }

internal fun JSONObject.optNullableInt(name: String): Int? {
    if (!has(name) || isNull(name)) return null
    return optInt(name)
}

internal fun JSONObject.optNullableLong(name: String): Long? {
    if (!has(name) || isNull(name)) return null
    return optLong(name)
}

internal fun JSONObject.optNullableBoolean(name: String): Boolean? {
    if (!has(name) || isNull(name)) return null
    return optBoolean(name)
}

internal fun JSONObject.optNullableString(name: String): String? {
    if (!has(name) || isNull(name)) return null
    return optString(name)
}

internal fun JSONObject.optNullableScalarString(name: String): String? {
    if (!has(name) || isNull(name)) return null
    return when (val value = opt(name)) {
        is String -> value
        is Number, is Boolean -> value.toString()
        else -> null
    }
}

private fun String.isWorkspaceSandboxPath(): Boolean {
    val value = trim()
    return value == "/workspace" ||
        value.startsWith("/workspace/") ||
        value == "/skills" ||
        value.startsWith("/skills/")
}
