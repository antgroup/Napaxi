package agent.provider.sdk

import org.json.JSONArray
import org.json.JSONObject

data class AgentPackage @JvmOverloads constructor(
    val providerId: String,
    val agentId: String,
    val displayName: String,
    val description: String,
    val systemPrompt: String,
    val actions: List<AgentAction>,
    val handoffJson: String = "{}",
    val resultJson: String = "{}",
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject =
        JSONObject()
            .put("provider_id", providerId)
            .put("agent_id", agentId)
            .put("display_name", displayName)
            .put("description", description)
            .put("system_prompt", systemPrompt)
            .put("actions", JSONArray(actions.map { it.toJsonObject() }))
            .put("handoff", JSONObject(handoffJson))
            .put("result", JSONObject(resultJson))

    companion object {
        @JvmStatic
        fun fromJson(json: String): AgentPackage = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): AgentPackage =
            AgentPackage(
                providerId = obj.optString("provider_id", ""),
                agentId = obj.optString("agent_id", ""),
                displayName = obj.optString("display_name", ""),
                description = obj.optString("description", ""),
                systemPrompt = obj.optString("system_prompt", ""),
                actions = obj.optJSONArray("actions")?.toObjectList { AgentAction.fromJsonObject(it) }
                    ?: emptyList(),
                handoffJson = obj.optJSONObject("handoff")?.toString() ?: "{}",
                resultJson = obj.optJSONObject("result")?.toString() ?: "{}",
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): AgentPackage =
            fromJsonObject(JSONObject(map))
    }
}

data class AgentAction @JvmOverloads constructor(
    val actionId: String,
    val toolName: String,
    val description: String,
    val parametersJson: String = "{}",
    val resultSchemaJson: String = "{}",
    val risk: String = ActionRisk.HIGH,
    val confirmationPolicy: String = ConfirmationPolicy.PROVIDER_REQUIRED,
    val executionModes: List<String> = listOf(ExecutionMode.APP_HANDOFF),
    val timeoutSeconds: Int = 600,
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject =
        JSONObject()
            .put("action_id", actionId)
            .put("tool_name", toolName)
            .put("description", description)
            .put("parameters", JSONObject(parametersJson))
            .put("result_schema", JSONObject(resultSchemaJson))
            .put("risk", risk)
            .put("confirmation_policy", confirmationPolicy)
            .put("execution_modes", JSONArray(executionModes))
            .put("timeout_seconds", timeoutSeconds)

    companion object {
        @JvmStatic
        fun fromJson(json: String): AgentAction = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): AgentAction =
            AgentAction(
                actionId = obj.optString("action_id", ""),
                toolName = obj.optString("tool_name", ""),
                description = obj.optString("description", ""),
                parametersJson = obj.optJSONObject("parameters")?.toString() ?: "{}",
                resultSchemaJson = obj.optJSONObject("result_schema")?.toString() ?: "{}",
                risk = obj.optString("risk", ActionRisk.HIGH),
                confirmationPolicy = obj.optString(
                    "confirmation_policy",
                    ConfirmationPolicy.PROVIDER_REQUIRED,
                ),
                executionModes = obj.optJSONArray("execution_modes")?.toStringList()
                    ?: emptyList(),
                timeoutSeconds = obj.optInt("timeout_seconds", 600),
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): AgentAction =
            fromJsonObject(JSONObject(map))
    }
}

data class ActionProposal @JvmOverloads constructor(
    val requestId: String,
    val providerId: String,
    val agentId: String,
    val actionId: String,
    val toolName: String,
    val argumentsJson: String = "{}",
    val userIntentSummary: String = "",
    val createdAt: String,
    val expiresAt: String,
    val nonce: String,
    val idempotencyKey: String,
    val callbackJson: String = "{}",
    val risk: String = ActionRisk.HIGH,
    val confirmationPolicy: String = ConfirmationPolicy.PROVIDER_REQUIRED,
    val hostInstanceId: String = "",
    val signatureAlgorithm: String = "",
    val signature: String? = null,
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject =
        JSONObject()
            .put("request_id", requestId)
            .put("provider_id", providerId)
            .put("agent_id", agentId)
            .put("action_id", actionId)
            .put("tool_name", toolName)
            .put("arguments", JSONObject(argumentsJson))
            .put("user_intent_summary", userIntentSummary)
            .put("created_at", createdAt)
            .put("expires_at", expiresAt)
            .put("nonce", nonce)
            .put("idempotency_key", idempotencyKey)
            .put("callback", JSONObject(callbackJson))
            .put("risk", risk)
            .put("confirmation_policy", confirmationPolicy)
            .apply {
                if (hostInstanceId.isNotBlank()) put("host_instance_id", hostInstanceId)
                if (signatureAlgorithm.isNotBlank()) put("signature_algorithm", signatureAlgorithm)
                signature?.let { put("signature", it) }
            }

    companion object {
        @JvmStatic
        fun fromJson(json: String): ActionProposal = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): ActionProposal =
            ActionProposal(
                requestId = obj.optString("request_id", ""),
                providerId = obj.optString("provider_id", ""),
                agentId = obj.optString("agent_id", ""),
                actionId = obj.optString("action_id", ""),
                toolName = obj.optString("tool_name", ""),
                argumentsJson = obj.optJSONObject("arguments")?.toString() ?: "{}",
                userIntentSummary = obj.optString("user_intent_summary", ""),
                createdAt = obj.optString("created_at", ""),
                expiresAt = obj.optString("expires_at", ""),
                nonce = obj.optString("nonce", ""),
                idempotencyKey = obj.optString("idempotency_key", ""),
                callbackJson = obj.optJSONObject("callback")?.toString() ?: "{}",
                risk = obj.optString("risk", ActionRisk.HIGH),
                confirmationPolicy = obj.optString(
                    "confirmation_policy",
                    ConfirmationPolicy.PROVIDER_REQUIRED,
                ),
                hostInstanceId = obj.optString("host_instance_id", ""),
                signatureAlgorithm = obj.optString("signature_algorithm", ""),
                signature = obj.optNullableString("signature"),
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): ActionProposal =
            fromJsonObject(JSONObject(map))
    }
}

data class ActionResult @JvmOverloads constructor(
    val requestId: String,
    val status: String,
    val resultJson: String = "{}",
    val error: ActionError? = null,
    val providerTraceId: String? = null,
    val completedAt: String,
    val signature: String? = null,
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject {
        val obj = JSONObject()
            .put("request_id", requestId)
            .put("status", status)
            .put("result", JSONObject(resultJson))
            .put("completed_at", completedAt)

        obj.put("error", error?.toJsonObject() ?: JSONObject.NULL)
        providerTraceId?.let { obj.put("provider_trace_id", it) }
        signature?.let { obj.put("signature", it) }
        return obj
    }

    companion object {
        @JvmStatic
        fun fromJson(json: String): ActionResult = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): ActionResult =
            ActionResult(
                requestId = obj.optString("request_id", ""),
                status = obj.optString("status", ""),
                resultJson = obj.optJSONObject("result")?.toString() ?: "{}",
                error = obj.optJSONObject("error")?.let { ActionError.fromJsonObject(it) },
                providerTraceId = obj.optNullableString("provider_trace_id"),
                completedAt = obj.optString("completed_at", ""),
                signature = obj.optNullableString("signature"),
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): ActionResult =
            fromJsonObject(JSONObject(map))
    }
}

data class ActionError @JvmOverloads constructor(
    val code: String,
    val message: String,
    val detailsJson: String = "{}",
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject =
        JSONObject()
            .put("code", code)
            .put("message", message)
            .put("details", JSONObject(detailsJson))

    companion object {
        @JvmStatic
        fun fromJson(json: String): ActionError = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): ActionError =
            ActionError(
                code = obj.optString("code", ""),
                message = obj.optString("message", ""),
                detailsJson = obj.optJSONObject("details")?.toString() ?: "{}",
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): ActionError =
            fromJsonObject(JSONObject(map))
    }
}

data class AgentInstallRequest @JvmOverloads constructor(
    val protocolVersion: Int = 1,
    val requestId: String,
    val nonce: String,
    val hostPackageName: String,
    val createdAt: String,
    val expiresAt: String,
    val hostSigningCertSha256: String = "",
    val hostInstanceId: String = "",
    val hostSharedSecret: String = "",
    val hostBundleId: String = "",
    val hostTeamId: String = "",
    val hostCallbackScheme: String = "",
    val callbackUrl: String = "",
    val backgroundTriggerSupported: Boolean = false,
    val hostBackgroundTriggerService: String = "",
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject =
        JSONObject()
            .put("protocol_version", protocolVersion)
            .put("request_id", requestId)
            .put("nonce", nonce)
            .put("host_package_name", hostPackageName)
            .put("created_at", createdAt)
            .put("expires_at", expiresAt)
            .put("host_signing_cert_sha256", hostSigningCertSha256)
            .put("host_instance_id", hostInstanceId)
            .put("host_shared_secret", hostSharedSecret)
            .apply {
                if (hostBundleId.isNotBlank()) put("host_bundle_id", hostBundleId)
                if (hostTeamId.isNotBlank()) put("host_team_id", hostTeamId)
                if (hostCallbackScheme.isNotBlank()) put("host_callback_scheme", hostCallbackScheme)
                if (callbackUrl.isNotBlank()) put("callback_url", callbackUrl)
                if (backgroundTriggerSupported) put("background_trigger_supported", true)
                if (hostBackgroundTriggerService.isNotBlank()) {
                    put("host_background_trigger_service", hostBackgroundTriggerService)
                }
            }

    companion object {
        @JvmStatic
        fun fromJson(json: String): AgentInstallRequest = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): AgentInstallRequest =
            AgentInstallRequest(
                protocolVersion = obj.optInt("protocol_version", 1),
                requestId = obj.getString("request_id"),
                nonce = obj.getString("nonce"),
                hostPackageName = obj.optString("host_package_name", ""),
                createdAt = obj.getString("created_at"),
                expiresAt = obj.getString("expires_at"),
                hostSigningCertSha256 = obj.optString("host_signing_cert_sha256", ""),
                hostInstanceId = obj.optString("host_instance_id", ""),
                hostSharedSecret = obj.optString("host_shared_secret", ""),
                hostBundleId = obj.optString("host_bundle_id", ""),
                hostTeamId = obj.optString("host_team_id", ""),
                hostCallbackScheme = obj.optString("host_callback_scheme", ""),
                callbackUrl = obj.optString("callback_url", ""),
                backgroundTriggerSupported = obj.optBoolean("background_trigger_supported", false),
                hostBackgroundTriggerService = obj.optString("host_background_trigger_service", ""),
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): AgentInstallRequest =
            fromJsonObject(JSONObject(map))
    }
}

data class AgentInstallResult @JvmOverloads constructor(
    val status: String,
    val requestId: String,
    val nonce: String,
    val packageJson: String? = null,
    val error: ActionError? = null,
    val completedAt: String,
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject {
        val obj = JSONObject()
            .put("status", status)
            .put("request_id", requestId)
            .put("nonce", nonce)
            .put("completed_at", completedAt)

        packageJson?.let { obj.put("package", JSONObject(it)) }
        obj.put("error", error?.toJsonObject() ?: JSONObject.NULL)
        return obj
    }

    companion object {
        @JvmStatic
        fun fromJson(json: String): AgentInstallResult = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): AgentInstallResult =
            AgentInstallResult(
                status = obj.optString("status", ""),
                requestId = obj.optString("request_id", ""),
                nonce = obj.optString("nonce", ""),
                packageJson = obj.optJSONObject("package")?.toString(),
                error = obj.optJSONObject("error")?.let { ActionError.fromJsonObject(it) },
                completedAt = obj.optString("completed_at", ""),
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): AgentInstallResult =
            fromJsonObject(JSONObject(map))
    }
}

data class AgentTriggerRequest @JvmOverloads constructor(
    val protocolVersion: Int = 2,
    val requestId: String,
    val providerId: String,
    val agentId: String,
    val message: String,
    val source: String = "",
    val eventType: String = "",
    val payloadJson: String = "{}",
    val createdAt: String,
    val expiresAt: String,
    val nonce: String,
    val idempotencyKey: String,
    val hostInstanceId: String = "",
    val signatureAlgorithm: String = "",
    val signature: String? = null,
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject =
        JSONObject()
            .put("protocol_version", protocolVersion)
            .put("request_id", requestId)
            .put("provider_id", providerId)
            .put("agent_id", agentId)
            .put("message", message)
            .put("source", source)
            .put("event_type", eventType)
            .put("payload", JSONObject(payloadJson))
            .put("created_at", createdAt)
            .put("expires_at", expiresAt)
            .put("nonce", nonce)
            .put("idempotency_key", idempotencyKey)
            .apply {
                if (hostInstanceId.isNotBlank()) put("host_instance_id", hostInstanceId)
                if (signatureAlgorithm.isNotBlank()) put("signature_algorithm", signatureAlgorithm)
                signature?.let { put("signature", it) }
            }

    companion object {
        @JvmStatic
        fun fromJson(json: String): AgentTriggerRequest = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): AgentTriggerRequest =
            AgentTriggerRequest(
                protocolVersion = obj.optInt("protocol_version", 2),
                requestId = obj.getString("request_id"),
                providerId = obj.getString("provider_id"),
                agentId = obj.getString("agent_id"),
                message = obj.optString("message", ""),
                source = obj.optString("source", ""),
                eventType = obj.optString("event_type", ""),
                payloadJson = obj.optJSONObject("payload")?.toString() ?: "{}",
                createdAt = obj.getString("created_at"),
                expiresAt = obj.getString("expires_at"),
                nonce = obj.optString("nonce", ""),
                idempotencyKey = obj.optString("idempotency_key", ""),
                hostInstanceId = obj.optString("host_instance_id", ""),
                signatureAlgorithm = obj.optString("signature_algorithm", ""),
                signature = obj.optNullableString("signature"),
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): AgentTriggerRequest =
            fromJsonObject(JSONObject(map))
    }
}

data class AgentTriggerSubmitResult @JvmOverloads constructor(
    val status: String,
    val requestId: String = "",
    val error: ActionError? = null,
) {
    fun toJson(): String = toJsonObject().toString()
    fun toJsonString(): String = toJson()

    fun toJsonObject(): JSONObject {
        val obj = JSONObject()
            .put("status", status)
            .put("request_id", requestId)
        obj.put("error", error?.toJsonObject() ?: JSONObject.NULL)
        return obj
    }

    companion object {
        const val ACCEPTED = "accepted"
        const val QUEUED = "queued"
        const val REJECTED = "rejected"
        const val HOST_UNAVAILABLE = "host_unavailable"
        const val UNSUPPORTED = "unsupported"

        @JvmStatic
        fun fromJson(json: String): AgentTriggerSubmitResult = fromJsonObject(JSONObject(json))

        @JvmStatic
        fun fromJsonObject(obj: JSONObject): AgentTriggerSubmitResult =
            AgentTriggerSubmitResult(
                status = obj.optString("status", ""),
                requestId = obj.optString("request_id", ""),
                error = obj.optJSONObject("error")?.let { ActionError.fromJsonObject(it) },
            )

        @JvmStatic
        fun fromMap(map: Map<String, *>): AgentTriggerSubmitResult =
            fromJsonObject(JSONObject(map))
    }
}

data class ProposalValidationResult(
    val isValid: Boolean,
    val code: String? = null,
    val message: String? = null,
) {
    companion object {
        @JvmStatic
        fun success(): ProposalValidationResult = ProposalValidationResult(isValid = true)

        @JvmStatic
        fun failure(code: String, message: String): ProposalValidationResult =
            ProposalValidationResult(isValid = false, code = code, message = message)
    }
}

private fun JSONArray.toStringList(): List<String> =
    List(length()) { index -> getString(index) }

private fun <T> JSONArray.toObjectList(transform: (JSONObject) -> T): List<T> =
    List(length()) { index -> transform(getJSONObject(index)) }

private fun JSONObject.optNullableString(name: String): String? =
    if (has(name) && !isNull(name)) getString(name) else null
