package com.napaxi.flutter

import agent.provider.sdk.IAgentTriggerIngress
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.json.JSONArray
import org.json.JSONObject

class AgentTriggerIngressService : Service() {
    companion object {
        const val SERVICE_CLASS_NAME = "com.napaxi.flutter.AgentTriggerIngressService"
        private const val SIGNATURE_ALGORITHM = "hmac-sha256-v1"

        private var dispatchCallback: ((String) -> Boolean)? = null

        fun setDispatchCallback(callback: ((String) -> Boolean)?) {
            dispatchCallback = callback
        }

        fun dispatchToFlutter(triggerJson: String): Boolean =
            dispatchCallback?.invoke(triggerJson) == true
    }

    private val binder = object : IAgentTriggerIngress.Stub() {
        override fun submitTrigger(triggerJson: String): String =
            handleSubmit(triggerJson, Binder.getCallingUid()).toString()
    }

    override fun onBind(intent: Intent?): IBinder? {
        val component = intent?.component ?: return null
        if (component.packageName != packageName || component.className != SERVICE_CLASS_NAME) {
            return null
        }
        return binder
    }

    private fun handleSubmit(triggerJson: String, callingUid: Int): JSONObject {
        val trigger = runCatching { JSONObject(triggerJson) }.getOrNull()
            ?: return response("rejected", "", "invalid_json", "Trigger JSON is invalid.")
        val requestId = trigger.optString("request_id", "")
        val validation = validateTrigger(trigger, callingUid)
        if (validation != null) {
            return response("rejected", requestId, validation.first, validation.second)
        }
        if (!persistTriggerRecord(trigger)) {
            return response("rejected", requestId, "persist_failed", "Unable to persist trigger.")
        }
        AgentTriggerStore.enqueue(this, trigger.toString())
        val delivered = dispatchToFlutter(trigger.toString())
        if (!delivered) {
            startBackgroundServiceForQueuedTrigger(trigger)
        }
        return response(if (delivered) "accepted" else "queued", requestId)
    }

    private fun validateTrigger(trigger: JSONObject, callingUid: Int): Pair<String, String>? {
        if (trigger.optInt("protocol_version", 1) < 2) {
            return "invalid_protocol" to "Agent trigger protocol v2 is required."
        }
        val requestId = trigger.optString("request_id", "")
        val providerId = trigger.optString("provider_id", "")
        val agentId = trigger.optString("agent_id", "")
        if (
            requestId.isBlank() ||
            providerId.isBlank() ||
            agentId.isBlank() ||
            trigger.optString("message", "").isBlank() ||
            trigger.optString("nonce", "").isBlank() ||
            trigger.optString("idempotency_key", "").isBlank()
        ) {
            return "missing_fields" to "Agent trigger is missing required fields."
        }
        val expiresAt = runCatching { Instant.parse(trigger.optString("expires_at", "")) }.getOrNull()
            ?: return "invalid_expiry" to "Trigger expiry is invalid."
        if (!expiresAt.isAfter(Instant.now())) {
            return "expired" to "Trigger has expired."
        }
        if (triggerRecordFile(requestId).exists()) {
            return "replayed" to "Trigger request has already been accepted."
        }
        val pkg = loadInstalledAgentPackage(agentId)
            ?: return "agent_not_installed" to "Triggered Agent package is not installed."
        if (pkg.optString("provider_id", "") != providerId) {
            return "provider_mismatch" to "Trigger provider does not match installed Agent."
        }
        val binding = pkg.optJSONObject("install_binding")
            ?: return "missing_binding" to "Installed Agent has no trusted binding."
        if (binding.optString("platform", "") != "android") {
            return "unsupported_platform" to "Background trigger is Android-only."
        }
        val providerPackage = binding.optString("app_package_name", "")
        val expectedProviderDigest = binding.optString("signing_cert_sha256", "")
        val callerPackages = packageManager.getPackagesForUid(callingUid)?.toSet().orEmpty()
        if (providerPackage.isBlank() || !callerPackages.contains(providerPackage)) {
            return "caller_mismatch" to "Calling package does not match installed Provider."
        }
        val currentProviderDigest = signingCertSha256(providerPackage)
        if (currentProviderDigest == null ||
            !currentProviderDigest.equals(expectedProviderDigest, ignoreCase = true)
        ) {
            return "caller_signature_mismatch" to "Calling package signature does not match installed Provider."
        }
        val hostInstanceId = binding.optString("host_instance_id", "")
        val hostSharedSecret = binding.optString("host_shared_secret", "")
        if (
            hostInstanceId.isBlank() ||
            hostSharedSecret.isBlank() ||
            trigger.optString("host_instance_id", "") != hostInstanceId
        ) {
            return "host_binding_mismatch" to "Trigger is not bound to this Host."
        }
        if (
            trigger.optString("signature_algorithm", "") != SIGNATURE_ALGORITHM ||
            trigger.optString("signature", "").isBlank()
        ) {
            return "missing_signature" to "Trigger is missing trusted signature fields."
        }
        val expectedSignature = hmacSha256Base64NoPad(
            hostSharedSecret.toByteArray(Charsets.UTF_8),
            triggerSignaturePayload(trigger).toByteArray(Charsets.UTF_8),
        )
        if (trigger.optString("signature", "") != expectedSignature) {
            return "signature_invalid" to "Trigger signature is invalid."
        }
        return null
    }

    private fun persistTriggerRecord(trigger: JSONObject): Boolean {
        val file = triggerRecordFile(trigger.optString("request_id", ""))
        val parent = file.parentFile ?: return false
        if (!parent.exists() && !parent.mkdirs()) return false
        val now = Instant.now().toString()
        val record = JSONObject()
            .put("trigger", trigger)
            .put("status", "queued")
            .put("created_at", now)
            .put("updated_at", now)
        return runCatching { file.writeText(record.toString(2)) }.isSuccess
    }

    private fun loadInstalledAgentPackage(agentId: String): JSONObject? {
        val file = File(filesDir, "napaxi/agent_app_packages/${safeFileComponent(agentId)}.json")
        return runCatching { JSONObject(file.readText()) }.getOrNull()
    }

    private fun triggerRecordFile(requestId: String): File =
        File(filesDir, "napaxi/agent_app_triggers/${safeFileComponent(requestId)}.json")

    private fun safeFileComponent(value: String): String =
        value.map { ch ->
            if (ch.isLetterOrDigit() || ch == '-' || ch == '_' || ch == '.') ch else '_'
        }.joinToString("")

    private fun startBackgroundServiceForQueuedTrigger(trigger: JSONObject) {
        runCatching {
            NapaxiAgentService.start(
                this,
                mapOf(
                    NapaxiAgentService.EXTRA_CHANNEL_NAME to "Agent",
                    NapaxiAgentService.EXTRA_CHANNEL_DESCRIPTION to "Agent background execution",
                    NapaxiAgentService.EXTRA_ONGOING_TITLE to "Agent received a trigger",
                    NapaxiAgentService.EXTRA_ONGOING_MESSAGE to
                        "Tap to continue ${trigger.optString("source", "provider")} request.",
                    NapaxiAgentService.EXTRA_WAKELOCK_TIMEOUT_MS to 30 * 60 * 1000,
                ),
            )
            NapaxiNotificationManager.createChannels(
                this,
                NapaxiNotificationManager.NotificationTextConfig.load(this),
            )
            NapaxiNotificationManager.showCompletionNotification(
                this,
                "Agent trigger received",
                "Tap to continue the provider request.",
            )
        }
    }

    private fun response(
        status: String,
        requestId: String,
        code: String? = null,
        message: String? = null,
    ): JSONObject {
        val result = JSONObject()
            .put("status", status)
            .put("request_id", requestId)
        if (code != null || message != null) {
            result.put(
                "error",
                JSONObject()
                    .put("code", code ?: "unknown")
                    .put("message", message ?: ""),
            )
        }
        return result
    }

    private fun triggerSignaturePayload(trigger: JSONObject): String {
        val payloadHash = sha256Base64NoPad(
            canonicalJson(trigger.opt("payload")).toByteArray(Charsets.UTF_8),
        )
        return listOf(
            "request_id=${trigger.optString("request_id", "")}",
            "provider_id=${trigger.optString("provider_id", "")}",
            "agent_id=${trigger.optString("agent_id", "")}",
            "message=${trigger.optString("message", "")}",
            "source=${trigger.optString("source", "")}",
            "event_type=${trigger.optString("event_type", "")}",
            "payload_sha256=$payloadHash",
            "created_at=${trigger.optString("created_at", "")}",
            "expires_at=${trigger.optString("expires_at", "")}",
            "nonce=${trigger.optString("nonce", "")}",
            "idempotency_key=${trigger.optString("idempotency_key", "")}",
            "host_instance_id=${trigger.optString("host_instance_id", "")}",
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
        Base64.getEncoder()
            .withoutPadding()
            .encodeToString(MessageDigest.getInstance("SHA-256").digest(bytes))

    private fun hmacSha256Base64NoPad(secret: ByteArray, payload: ByteArray): String {
        val mac = Mac.getInstance("HmacSHA256")
        mac.init(SecretKeySpec(secret, "HmacSHA256"))
        return Base64.getEncoder().withoutPadding().encodeToString(mac.doFinal(payload))
    }

    private fun signingCertSha256(packageName: String): String? {
        return try {
            val packageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
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
}
