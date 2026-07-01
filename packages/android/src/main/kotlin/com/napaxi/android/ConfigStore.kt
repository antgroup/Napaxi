package com.napaxi.android

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

public data class NapaxiConfigProfile(
    val id: String,
    val name: String,
    val provider: String,
    val model: String,
    val baseUrl: String? = null,
    val systemPrompt: String = "",
    val maxTokens: Int = LlmConfig.DEFAULT_MAX_TOKENS,
    val maxToolIterations: Int = 50,
    val extraHeaders: String? = null,
    val userTimezone: String? = null,
    val allowedModels: List<Map<String, String>>? = null,
    val imageModel: String? = null,
    val imageAnalysisModel: String? = null,
    val videoModel: String? = null,
    val audioModel: String? = null,
    val contextEngine: ContextEngineConfig = ContextEngineConfig(),
    val shellSecurity: ShellSecurityConfig = ShellSecurityConfig(),
    val metadata: JSONObject = JSONObject(),
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("id", id)
        .put("name", name)
        .put("provider", provider)
        .put("base_url", baseUrl)
        .put("model", model)
        .put("max_tokens", maxTokens)
        .put("max_tool_iterations", maxToolIterations)
        .put("extra_headers", extraHeaders)
        .apply {
            if (systemPrompt.trim().isNotEmpty()) put("system_prompt", systemPrompt)
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
            videoModel?.let { put("video_model", it) }
            audioModel?.let { put("audio_model", it) }
            put("context_engine", contextEngine.toJsonObject())
            put("shell_security", shellSecurity.toJsonObject())
            if (metadata.length() > 0) put("metadata", metadata)
        }

    public fun toJson(): String = toJsonObject().toString()

    public fun toMap(): Map<String, Any?> = toJsonObject().toPlainMap()

    public fun toConfig(apiKey: String): LlmConfig =
        LlmConfig(
            provider = provider,
            apiKey = apiKey,
            baseUrl = baseUrl,
            model = model,
            systemPrompt = systemPrompt,
            maxTokens = maxTokens,
            maxToolIterations = maxToolIterations,
            extraHeaders = extraHeaders,
            userTimezone = userTimezone,
            allowedModels = allowedModels,
            imageModel = imageModel,
            imageAnalysisModel = imageAnalysisModel,
            videoModel = videoModel,
            audioModel = audioModel,
            contextEngine = contextEngine,
            shellSecurity = shellSecurity,
        )

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiConfigProfile =
            fromJsonObject(JSONObject(rawJson))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiConfigProfile =
            NapaxiConfigProfile(
                id = obj.optString("id"),
                name = obj.optString("name"),
                provider = obj.optString("provider"),
                baseUrl = obj.optNullableString("base_url"),
                model = obj.optString("model"),
                systemPrompt = obj.optString("system_prompt"),
                maxTokens = obj.optInt("max_tokens", LlmConfig.DEFAULT_MAX_TOKENS),
                maxToolIterations = obj.optInt("max_tool_iterations", 50),
                extraHeaders = obj.optNullableString("extra_headers"),
                userTimezone = obj.optNullableString("user_timezone")
                    ?: obj.optNullableString("userTimeZone")
                    ?: obj.optNullableString("timeZoneId"),
                allowedModels = obj.optJSONArray("allowed_models")?.toStringMapList(),
                imageModel = obj.optNullableString("image_model"),
                imageAnalysisModel = obj.optNullableString("image_analysis_model"),
                videoModel = obj.optNullableString("video_model"),
                audioModel = obj.optNullableString("audio_model"),
                contextEngine = obj.optJSONObject("context_engine")?.let(ContextEngineConfig::fromJsonObject)
                    ?: ContextEngineConfig(),
                shellSecurity = obj.optJSONObject("shell_security")?.let(ShellSecurityConfig::fromJsonObject)
                    ?: ShellSecurityConfig(),
                metadata = obj.optJSONObject("metadata") ?: JSONObject(),
            )

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiConfigProfile =
            fromJsonObject(JSONObject(map))
    }
}

public data class NapaxiConfigSelection(
    val selectedProfileId: String? = null,
    val selectedProfileIdByCapability: Map<String, String> = emptyMap(),
    val systemPrompt: String = "",
    val maxToolIterations: Int = 50,
) {
    public fun toJsonObject(): JSONObject = JSONObject()
        .put("selected_profile_id", selectedProfileId)
        .put("selected_profile_id_by_capability", JSONObject(selectedProfileIdByCapability))
        .put("system_prompt", systemPrompt)
        .put("max_tool_iterations", maxToolIterations)

    public fun toJson(): String = toJsonObject().toString()

    public fun toMap(): Map<String, Any?> = toJsonObject().toPlainMap()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): NapaxiConfigSelection =
            fromJsonObject(JSONObject(rawJson))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): NapaxiConfigSelection {
            val byCapability = obj.optJSONObject("selected_profile_id_by_capability")
            return NapaxiConfigSelection(
                selectedProfileId = obj.optNullableString("selected_profile_id"),
                selectedProfileIdByCapability = byCapability?.keys()?.asSequence()
                    ?.associateWith { key -> byCapability.optString(key) }
                    .orEmpty(),
                systemPrompt = obj.optString("system_prompt"),
                maxToolIterations = obj.optInt("max_tool_iterations", 50),
            )
        }

        @JvmStatic
        public fun fromMap(map: Map<String, *>): NapaxiConfigSelection =
            fromJsonObject(JSONObject(map))
    }
}

public interface NapaxiConfigKeyValueStore {
    public fun read(key: String): String?
    public fun write(key: String, value: String)
    public fun delete(key: String)
}

public interface NapaxiConfigSecretStore {
    public fun read(key: String): String?
    public fun write(key: String, value: String)
    public fun delete(key: String)
}

public class NapaxiConfigStore(
    private val keyValueStore: NapaxiConfigKeyValueStore,
    private val secretStore: NapaxiConfigSecretStore,
) {
    public fun loadProfiles(): List<NapaxiConfigProfile> {
        val raw = keyValueStore.read(PROFILES_KEY)?.takeIf { it.trim().isNotEmpty() } ?: return emptyList()
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index -> array.optJSONObject(index) }
                .mapNotNull { it?.let(NapaxiConfigProfile::fromJsonObject) }
                .filter { it.id.trim().isNotEmpty() }
        }.getOrDefault(emptyList())
    }

    @JvmOverloads
    public fun saveProfile(profile: NapaxiConfigProfile, apiKey: String? = null) {
        val nextProfiles = loadProfiles()
            .filterNot { it.id == profile.id }
            .plus(profile)
        saveProfiles(nextProfiles)
        if (apiKey != null) {
            if (apiKey.isEmpty()) {
                secretStore.delete(apiKeyKey(profile.id))
            } else {
                secretStore.write(apiKeyKey(profile.id), apiKey)
            }
        }
    }

    public fun deleteProfile(profileId: String) {
        saveProfiles(loadProfiles().filterNot { it.id == profileId })
        secretStore.delete(apiKeyKey(profileId))
        val selection = loadSelection()
        val nextByCapability = selection.selectedProfileIdByCapability
            .filterValues { selectedId -> selectedId != profileId }
        saveSelection(
            NapaxiConfigSelection(
                selectedProfileId = selection.selectedProfileId.takeIf { it != profileId },
                selectedProfileIdByCapability = nextByCapability,
                systemPrompt = selection.systemPrompt,
                maxToolIterations = selection.maxToolIterations,
            ),
        )
    }

    public fun loadSelection(): NapaxiConfigSelection {
        val profileIds = loadProfiles().map { it.id }.toSet()
        val raw = keyValueStore.read(SELECTION_KEY)?.takeIf { it.trim().isNotEmpty() }
            ?: return NapaxiConfigSelection()
        val selection = runCatching {
            NapaxiConfigSelection.fromJson(raw)
        }.getOrDefault(NapaxiConfigSelection())
        return normalizeSelection(selection, profileIds)
    }

    public fun saveSelection(selection: NapaxiConfigSelection) {
        val profileIds = loadProfiles().map { it.id }.toSet()
        keyValueStore.write(SELECTION_KEY, normalizeSelection(selection, profileIds).toJson())
    }

    public fun resolveConfig(profileId: String): LlmConfig? {
        val profile = loadProfiles().firstOrNull { it.id == profileId } ?: return null
        return profile.toConfig(apiKey = readApiKey(profileId))
    }

    @JvmOverloads
    public fun resolveSelectedConfig(capabilityId: String? = null): LlmConfig? {
        val selection = loadSelection()
        val selectedProfileId = capabilityId
            ?.let { selection.selectedProfileIdByCapability[it] }
            ?: selection.selectedProfileId
            ?: return null
        return resolveConfig(selectedProfileId)
    }

    public fun readApiKey(profileId: String): String =
        runCatching { secretStore.read(apiKeyKey(profileId)).orEmpty() }.getOrDefault("")

    private fun saveProfiles(profiles: List<NapaxiConfigProfile>) {
        keyValueStore.write(
            PROFILES_KEY,
            JSONArray(profiles.map { it.toJsonObject() }).toString(),
        )
    }

    private fun normalizeSelection(
        selection: NapaxiConfigSelection,
        profileIds: Set<String>,
    ): NapaxiConfigSelection {
        val selectedProfileId = selection.selectedProfileId.takeIf { it != null && profileIds.contains(it) }
        val selectedByCapability = selection.selectedProfileIdByCapability
            .filterValues { profileIds.contains(it) }
        return NapaxiConfigSelection(
            selectedProfileId = selectedProfileId,
            selectedProfileIdByCapability = selectedByCapability,
            systemPrompt = selection.systemPrompt,
            maxToolIterations = selection.maxToolIterations,
        )
    }

    private fun apiKeyKey(profileId: String): String = "$API_KEY_PREFIX$profileId"

    public companion object {
        private const val PROFILES_KEY = "napaxi.config.profiles.v1"
        private const val SELECTION_KEY = "napaxi.config.selection.v1"
        private const val API_KEY_PREFIX = "napaxi.config.api_key."

        @JvmStatic
        public fun memory(): NapaxiConfigStore {
            val store = NapaxiMemoryConfigStore()
            return NapaxiConfigStore(keyValueStore = store, secretStore = store)
        }

        @JvmStatic
        public fun sharedPreferences(context: Context): NapaxiConfigStore =
            NapaxiConfigStore(
                keyValueStore = NapaxiSharedPreferencesConfigStore(context, "napaxi_config"),
                secretStore = NapaxiSharedPreferencesConfigStore(context, "napaxi_config_secrets"),
            )
    }
}

public class NapaxiSharedPreferencesConfigStore(
    context: Context,
    name: String,
) : NapaxiConfigKeyValueStore, NapaxiConfigSecretStore {
    private val preferences = context.applicationContext.getSharedPreferences(name, Context.MODE_PRIVATE)

    override fun read(key: String): String? = preferences.getString(key, null)

    override fun write(key: String, value: String) {
        preferences.edit().putString(key, value).apply()
    }

    override fun delete(key: String) {
        preferences.edit().remove(key).apply()
    }
}

public class NapaxiMemoryConfigStore : NapaxiConfigKeyValueStore, NapaxiConfigSecretStore {
    private val values = LinkedHashMap<String, String>()

    override fun read(key: String): String? = values[key]

    override fun write(key: String, value: String) {
        values[key] = value
    }

    override fun delete(key: String) {
        values.remove(key)
    }
}

private fun JSONObject.toPlainMap(): Map<String, Any?> {
    val values = LinkedHashMap<String, Any?>()
    val keys = keys()
    while (keys.hasNext()) {
        val key = keys.next()
        values[key] = opt(key).toPlainValue()
    }
    return values
}

private fun JSONArray.toPlainList(): List<Any?> =
    List(length()) { index -> opt(index).toPlainValue() }

private fun Any?.toPlainValue(): Any? =
    when (this) {
        null, JSONObject.NULL -> null
        is JSONObject -> this.toPlainMap()
        is JSONArray -> this.toPlainList()
        else -> this
    }
