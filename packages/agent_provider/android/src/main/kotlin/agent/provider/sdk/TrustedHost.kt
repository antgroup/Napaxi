package agent.provider.sdk

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.time.Instant
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

private const val SIGNATURE_ALGORITHM_HMAC_SHA256_V1 = "hmac-sha256-v1"

data class TrustedHostBinding @JvmOverloads constructor(
    val hostPackageName: String,
    val hostSigningCertSha256: String,
    val hostInstanceId: String,
    val hostSharedSecret: String,
    val installedAt: String,
    val protocolVersion: Int = 2,
    val backgroundTriggerSupported: Boolean = false,
    val hostBackgroundTriggerService: String = "",
) {
    fun toJsonObject(): JSONObject =
        JSONObject()
            .put("host_package_name", hostPackageName)
            .put("host_signing_cert_sha256", hostSigningCertSha256)
            .put("host_instance_id", hostInstanceId)
            .put("host_shared_secret", hostSharedSecret)
            .put("installed_at", installedAt)
            .put("protocol_version", protocolVersion)
            .put("background_trigger_supported", backgroundTriggerSupported)
            .put("host_background_trigger_service", hostBackgroundTriggerService)

    companion object {
        fun fromJsonObject(obj: JSONObject): TrustedHostBinding =
            TrustedHostBinding(
                hostPackageName = obj.optString("host_package_name", ""),
                hostSigningCertSha256 = obj.optString("host_signing_cert_sha256", ""),
                hostInstanceId = obj.optString("host_instance_id", ""),
                hostSharedSecret = obj.optString("host_shared_secret", ""),
                installedAt = obj.optString("installed_at", ""),
                protocolVersion = obj.optInt("protocol_version", 1),
                backgroundTriggerSupported = obj.optBoolean("background_trigger_supported", false),
                hostBackgroundTriggerService = obj.optString("host_background_trigger_service", ""),
            )
    }
}

class TrustedHostStore @JvmOverloads constructor(
    context: Context,
    namespace: String = "agent_provider_trust",
) {
    private val prefs = context.applicationContext.getSharedPreferences(namespace, Context.MODE_PRIVATE)

    fun saveBinding(binding: TrustedHostBinding) {
        prefs.edit()
            .putString("binding_${binding.hostInstanceId}", binding.toJsonObject().toString())
            .putString("latest_host_instance_id", binding.hostInstanceId)
            .apply()
    }

    fun loadBinding(hostInstanceId: String): TrustedHostBinding? {
        if (hostInstanceId.isBlank()) return null
        val json = prefs.getString("binding_$hostInstanceId", null) ?: return null
        return runCatching { TrustedHostBinding.fromJsonObject(JSONObject(json)) }.getOrNull()
    }

    fun loadLatestBinding(): TrustedHostBinding? {
        val hostInstanceId = prefs.getString("latest_host_instance_id", null) ?: return null
        return loadBinding(hostInstanceId)
    }

    fun isProposalConsumed(requestId: String): Boolean =
        prefs.getStringSet("consumed_request_ids", emptySet())?.contains(requestId) == true

    fun markProposalConsumed(requestId: String) {
        if (requestId.isBlank()) return
        val next = (prefs.getStringSet("consumed_request_ids", emptySet()) ?: emptySet()).toMutableSet()
        next.add(requestId)
        prefs.edit().putStringSet("consumed_request_ids", next).apply()
    }
}

data class TrustedProposalValidationResult(
    val status: String,
    val isValid: Boolean,
    val isTrusted: Boolean,
    val code: String? = null,
    val message: String? = null,
) {
    companion object {
        fun trusted(): TrustedProposalValidationResult =
            TrustedProposalValidationResult(
                status = TrustedProposalStatus.TRUSTED,
                isValid = true,
                isTrusted = true,
            )

        fun failure(status: String, code: String, message: String): TrustedProposalValidationResult =
            TrustedProposalValidationResult(
                status = status,
                isValid = false,
                isTrusted = false,
                code = code,
                message = message,
            )
    }
}

object TrustedProposalStatus {
    const val TRUSTED = "trusted"
    const val UNTRUSTED = "untrusted"
    const val REPLAYED = "replayed"
    const val EXPIRED = "expired"
    const val SIGNATURE_INVALID = "signature_invalid"
}

object AgentProviderSecurity {
    @JvmStatic
    fun signTriggerRequest(
        request: AgentTriggerRequest,
        binding: TrustedHostBinding,
    ): AgentTriggerRequest {
        val unsigned = request.copy(
            hostInstanceId = binding.hostInstanceId,
            signatureAlgorithm = SIGNATURE_ALGORITHM_HMAC_SHA256_V1,
            signature = null,
        )
        return unsigned.copy(
            signature = hmacSha256Base64NoPad(
                binding.hostSharedSecret.toByteArray(Charsets.UTF_8),
                triggerSignaturePayload(unsigned).toByteArray(Charsets.UTF_8),
            ),
        )
    }

    @JvmStatic
    fun handleTrustedInstallRequest(
        activity: Activity,
        packageDef: AgentPackage,
        store: TrustedHostStore,
    ): Intent {
        val request = AgentProvider.parseInstallRequest(activity.intent)
            ?: return Intent().also {
                // No request is available, so there is no request id/nonce to echo.
            }
        val validation = validateInstallCaller(activity, request)
        if (validation != null) {
            return AgentProvider.buildInstallFailureIntent(request, validation.first, validation.second)
        }
        store.saveBinding(
            TrustedHostBinding(
                hostPackageName = request.hostPackageName,
                hostSigningCertSha256 = request.hostSigningCertSha256,
                hostInstanceId = request.hostInstanceId,
                hostSharedSecret = request.hostSharedSecret,
                installedAt = Instant.now().toString(),
                protocolVersion = request.protocolVersion,
                backgroundTriggerSupported = request.backgroundTriggerSupported,
                hostBackgroundTriggerService = request.hostBackgroundTriggerService,
            ),
        )
        return AgentProvider.buildInstallResultIntent(packageDef, request)
    }

    @JvmStatic
    fun validateTrustedProposal(
        activity: Activity,
        proposal: ActionProposal,
        packageDef: AgentPackage,
        store: TrustedHostStore,
        nowMillis: Long,
    ): TrustedProposalValidationResult {
        val basic = AgentProvider.validateProposal(proposal, packageDef, nowMillis)
        if (!basic.isValid) {
            val status = if (basic.code == "expired") {
                TrustedProposalStatus.EXPIRED
            } else {
                TrustedProposalStatus.UNTRUSTED
            }
            return TrustedProposalValidationResult.failure(
                status,
                basic.code ?: "invalid_proposal",
                basic.message ?: "Invalid proposal",
            )
        }
        if (store.isProposalConsumed(proposal.requestId)) {
            return TrustedProposalValidationResult.failure(
                TrustedProposalStatus.REPLAYED,
                "replayed",
                "Proposal request has already been consumed.",
            )
        }
        if (
            proposal.hostInstanceId.isBlank() ||
            proposal.signatureAlgorithm != SIGNATURE_ALGORITHM_HMAC_SHA256_V1 ||
            proposal.signature.isNullOrBlank()
        ) {
            return TrustedProposalValidationResult.failure(
                TrustedProposalStatus.UNTRUSTED,
                "missing_trust_fields",
                "Proposal is missing trusted host signature fields.",
            )
        }
        val binding = store.loadBinding(proposal.hostInstanceId)
            ?: return TrustedProposalValidationResult.failure(
                TrustedProposalStatus.UNTRUSTED,
                "host_not_bound",
                "No trusted host binding exists for this proposal.",
            )
        val callerPackage = activity.callingPackage
            ?: return TrustedProposalValidationResult.failure(
                TrustedProposalStatus.UNTRUSTED,
                "missing_calling_package",
                "Unable to verify the calling package.",
            )
        if (callerPackage != binding.hostPackageName) {
            return TrustedProposalValidationResult.failure(
                TrustedProposalStatus.UNTRUSTED,
                "caller_mismatch",
                "Calling package does not match the trusted host.",
            )
        }
        val digest = signingCertSha256(activity, callerPackage)
        if (digest == null || !digest.equals(binding.hostSigningCertSha256, ignoreCase = true)) {
            return TrustedProposalValidationResult.failure(
                TrustedProposalStatus.UNTRUSTED,
                "caller_signature_mismatch",
                "Calling package signature does not match the trusted host.",
            )
        }
        val expected = hmacSha256Base64NoPad(
            binding.hostSharedSecret.toByteArray(Charsets.UTF_8),
            proposalSignaturePayload(proposal).toByteArray(Charsets.UTF_8),
        )
        if (expected != proposal.signature) {
            return TrustedProposalValidationResult.failure(
                TrustedProposalStatus.SIGNATURE_INVALID,
                "signature_invalid",
                "Proposal signature is invalid.",
            )
        }
        return TrustedProposalValidationResult.trusted()
    }

    @JvmStatic
    fun markProposalConsumed(store: TrustedHostStore, proposal: ActionProposal) {
        store.markProposalConsumed(proposal.requestId)
    }

    private fun validateInstallCaller(
        activity: Activity,
        request: AgentInstallRequest,
    ): Pair<String, String>? {
        if (
            request.protocolVersion < 2 ||
            request.hostPackageName.isBlank() ||
            request.hostSigningCertSha256.isBlank() ||
            request.hostInstanceId.isBlank() ||
            request.hostSharedSecret.isBlank()
        ) {
            return "missing_trust_fields" to "Trusted install fields are required."
        }
        val callerPackage = activity.callingPackage
            ?: return "missing_calling_package" to "Unable to verify the calling package."
        if (callerPackage != request.hostPackageName) {
            return "caller_mismatch" to "Calling package does not match install request."
        }
        val digest = signingCertSha256(activity, callerPackage)
            ?: return "caller_signature_unavailable" to "Unable to read calling package signature."
        if (!digest.equals(request.hostSigningCertSha256, ignoreCase = true)) {
            return "caller_signature_mismatch" to "Calling package signature does not match install request."
        }
        return null
    }
}

private fun proposalSignaturePayload(proposal: ActionProposal): String {
    val argumentsHash = sha256Base64NoPad(canonicalJson(JSONObject(proposal.argumentsJson)).toByteArray(Charsets.UTF_8))
    return listOf(
        "request_id=${proposal.requestId}",
        "provider_id=${proposal.providerId}",
        "agent_id=${proposal.agentId}",
        "action_id=${proposal.actionId}",
        "tool_name=${proposal.toolName}",
        "arguments_sha256=$argumentsHash",
        "created_at=${proposal.createdAt}",
        "expires_at=${proposal.expiresAt}",
        "nonce=${proposal.nonce}",
        "idempotency_key=${proposal.idempotencyKey}",
        "risk=${proposal.risk}",
        "confirmation_policy=${proposal.confirmationPolicy}",
        "host_instance_id=${proposal.hostInstanceId}",
    ).joinToString("\n")
}

private fun triggerSignaturePayload(request: AgentTriggerRequest): String {
    val payloadHash = sha256Base64NoPad(canonicalJson(JSONObject(request.payloadJson)).toByteArray(Charsets.UTF_8))
    return listOf(
        "request_id=${request.requestId}",
        "provider_id=${request.providerId}",
        "agent_id=${request.agentId}",
        "message=${request.message}",
        "source=${request.source}",
        "event_type=${request.eventType}",
        "payload_sha256=$payloadHash",
        "created_at=${request.createdAt}",
        "expires_at=${request.expiresAt}",
        "nonce=${request.nonce}",
        "idempotency_key=${request.idempotencyKey}",
        "host_instance_id=${request.hostInstanceId}",
    ).joinToString("\n")
}

private fun canonicalJson(value: Any?): String =
    when (value) {
        null, JSONObject.NULL -> "null"
        is Boolean, is Number -> value.toString()
        is String -> JSONObject.quote(value)
        is JSONArray -> {
            val parts = List(value.length()) { index -> canonicalJson(value.get(index)) }
            parts.joinToString(prefix = "[", postfix = "]", separator = ",")
        }
        is JSONObject -> {
            val keys = value.keys().asSequence().toList().sorted()
            keys.joinToString(prefix = "{", postfix = "}", separator = ",") { key ->
                "${JSONObject.quote(key)}:${canonicalJson(value.get(key))}"
            }
        }
        else -> JSONObject.quote(value.toString())
    }

private fun sha256Base64NoPad(bytes: ByteArray): String =
    Base64.getEncoder().withoutPadding().encodeToString(MessageDigest.getInstance("SHA-256").digest(bytes))

private fun hmacSha256Base64NoPad(secret: ByteArray, payload: ByteArray): String {
    val mac = Mac.getInstance("HmacSHA256")
    mac.init(SecretKeySpec(secret, "HmacSHA256"))
    return Base64.getEncoder().withoutPadding().encodeToString(mac.doFinal(payload))
}

private fun signingCertSha256(context: Context, packageName: String): String? {
    return try {
        val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            context.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
        }
        val signatures = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            packageInfo.signatures
        }
        val signature = signatures?.firstOrNull() ?: return null
        MessageDigest.getInstance("SHA-256")
            .digest(signature.toByteArray())
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
    } catch (_: Exception) {
        null
    }
}
