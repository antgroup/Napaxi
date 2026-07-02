package com.napaxi.android

import agent.provider.sdk.AgentProviderContract
import android.app.Activity
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Binder
import android.os.Build
import android.os.IBinder
import agent.provider.sdk.IAgentTriggerIngress
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.util.Base64
import java.util.UUID
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

public data class AgentProviderDescriptor(
    val packageName: String,
    val activityName: String,
    val displayName: String,
    val installActivityName: String = activityName,
    val platform: String = "android",
    val signingCertSha256: String = "",
    val installUrl: String = "",
    val actionUrl: String = "",
    val universalLinkDomain: String = "",
    val iosBundleId: String = "",
    val iosTeamId: String = "",
) {
    public val label: String get() = displayName

    fun toJsonObject(includeAliases: Boolean = true): JSONObject = JSONObject()
        .put("platform", platform)
        .put("packageName", packageName)
        .put("installActivityName", installActivityName)
        .put("activityName", activityName)
        .put("label", displayName)
        .put("signingCertSha256", signingCertSha256)
        .apply {
            if (includeAliases) {
                put("package_name", packageName)
                put("activity_name", activityName)
                put("display_name", displayName)
                put("install_activity_name", installActivityName)
                put("signing_cert_sha256", signingCertSha256)
            }
            if (installUrl.isNotBlank()) put("installUrl", installUrl)
            if (actionUrl.isNotBlank()) put("actionUrl", actionUrl)
            if (universalLinkDomain.isNotBlank()) put("universalLinkDomain", universalLinkDomain)
            if (iosBundleId.isNotBlank()) put("iosBundleId", iosBundleId)
            if (iosTeamId.isNotBlank()) put("iosTeamId", iosTeamId)
        }

    public fun toJson(): String = toJsonObject(includeAliases = false).toString()
    public fun toJsonString(): String = toJson()

    public companion object {
        @JvmStatic
        public fun fromJson(rawJson: String): AgentProviderDescriptor =
            fromJsonObject(JSONObject(rawJson.ifBlank { "{}" }))

        @JvmStatic
        public fun fromJsonObject(obj: JSONObject): AgentProviderDescriptor {
            val activityName = obj.optString(
                "activityName",
                obj.optString("activity_name", obj.optString("installActivityName", obj.optString("install_activity_name"))),
            )
            val installActivityName = obj.optString(
                "installActivityName",
                obj.optString("install_activity_name", activityName),
            )
            val displayName = obj.optString(
                "label",
                obj.optString("display_name", obj.optString("displayName")),
            )
            return AgentProviderDescriptor(
                platform = obj.optString("platform", "android"),
                packageName = obj.optString("packageName", obj.optString("package_name")),
                installActivityName = installActivityName,
                activityName = activityName,
                displayName = displayName,
                signingCertSha256 = obj.optString("signingCertSha256", obj.optString("signing_cert_sha256")),
                installUrl = obj.optString("installUrl", obj.optString("install_url")),
                actionUrl = obj.optString("actionUrl", obj.optString("action_url")),
                universalLinkDomain = obj.optString("universalLinkDomain", obj.optString("universal_link_domain")),
                iosBundleId = obj.optString("iosBundleId", obj.optString("ios_bundle_id")),
                iosTeamId = obj.optString("iosTeamId", obj.optString("ios_team_id")),
            )
        }

        @JvmStatic
        public fun fromMap(map: Map<String, *>): AgentProviderDescriptor =
            fromJsonObject(JSONObject(map))
    }
}

public data class PendingAgentProviderInstall(
    val descriptor: AgentProviderDescriptor,
    val request: AgentInstallRequest,
    val requestCode: Int = AgentProviderHostApi.REQUEST_INSTALL_AGENT,
)

public class AgentProviderInstallApi internal constructor(
    private val host: AgentProviderHostApi,
) {
    public fun discoverProviders(): List<AgentProviderDescriptor> =
        host.discoverProviders()

    public fun buildInstallRequest(
        expiresAt: Instant = Instant.now().plusSeconds(600),
    ): AgentInstallRequest =
        host.buildInstallRequest(expiresAt)

    public fun requestInstall(
        activity: Activity,
        provider: AgentProviderDescriptor,
        request: AgentInstallRequest = buildInstallRequest(),
        requestCode: Int = AgentProviderHostApi.REQUEST_INSTALL_AGENT,
    ): AgentInstallRequest =
        host.requestInstall(activity, provider, request, requestCode)

    public fun beginInstallFromLaunchIntent(
        activity: Activity,
        request: AgentInstallRequest = buildInstallRequest(),
        requestCode: Int = AgentProviderHostApi.REQUEST_INSTALL_AGENT,
    ): PendingAgentProviderInstall? =
        host.beginInstallFromLaunchIntent(activity, request, requestCode)

    public fun installFromLaunchIntent(
        activity: Activity,
        request: AgentInstallRequest = buildInstallRequest(),
        requestCode: Int = AgentProviderHostApi.REQUEST_INSTALL_AGENT,
    ): PendingAgentProviderInstall? =
        host.installFromLaunchIntent(activity, request, requestCode)

    public suspend fun registerInstallResult(result: AgentInstallResult): AgentAppPackage? =
        host.registerInstallResult(result)

    public suspend fun registerInstallResult(
        result: AgentInstallResult,
        request: AgentInstallRequest,
        descriptor: AgentProviderDescriptor,
        now: Instant = Instant.now(),
    ): AgentAppPackage =
        host.registerInstallResult(result, request, descriptor, now)

    public suspend fun handleActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
        pending: PendingAgentProviderInstall,
        now: Instant = Instant.now(),
    ): AgentAppPackage? =
        host.handleInstallActivityResult(requestCode, resultCode, data, pending, now)

    public suspend fun handleActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
        descriptor: AgentProviderDescriptor,
        request: AgentInstallRequest,
        expectedRequestCode: Int = AgentProviderHostApi.REQUEST_INSTALL_AGENT,
        now: Instant = Instant.now(),
    ): AgentAppPackage? =
        host.handleInstallActivityResult(requestCode, resultCode, data, descriptor, request, expectedRequestCode, now)

    public fun validateInstallResult(
        result: AgentInstallResult,
        request: AgentInstallRequest,
        now: Instant = Instant.now(),
    ) {
        host.validateInstallResult(result, request, now)
    }

    public fun parseInstallResult(data: Intent?): AgentInstallResult? =
        host.parseInstallResult(data)

    public fun getPendingProviderInstallRequest(intent: Intent?): AgentProviderDescriptor? =
        host.getPendingProviderInstallRequest(intent)

    public fun clearPendingProviderInstallRequest(activity: Activity) {
        host.clearPendingProviderInstallRequest(activity)
    }
}

public class AgentProviderTriggerApi internal constructor(
    private val host: AgentProviderHostApi,
) {
    public fun consumePendingTrigger(intent: Intent? = null): AgentTriggerRequest? =
        host.consumePendingTrigger(intent)

    public fun getPendingAgentTriggerRequest(intent: Intent?): AgentTriggerRequest? =
        host.getPendingAgentTriggerRequest(intent)

    public suspend fun acceptTrigger(request: AgentTriggerRequest): AcceptedAgentTrigger =
        host.acceptTrigger(request)

    public suspend fun validateTrigger(request: AgentTriggerRequest): AgentAppPackage =
        host.validateTrigger(request)

    public fun validateTrigger(
        request: AgentTriggerRequest,
        packageDef: AgentAppPackage,
        now: Instant = Instant.now(),
    ): AgentAppPackage =
        host.validateTrigger(request, packageDef, now)

    public fun clearPendingAgentTriggerRequest(activity: Activity) {
        host.clearPendingAgentTriggerRequest(activity)
    }

    public fun peekQueuedTrigger(): AgentTriggerRequest? =
        host.peekQueuedTrigger()

    public fun removeQueuedTrigger(request: AgentTriggerRequest? = null) {
        host.removeQueuedTrigger(request)
    }

    public fun markTriggerConsumed(request: AgentTriggerRequest) {
        host.markTriggerConsumed(request)
    }

    public fun markTriggerConsumed(requestId: String) {
        host.markTriggerConsumed(requestId)
    }

    public fun isTriggerConsumed(requestId: String): Boolean =
        host.isTriggerConsumed(requestId)
}

public class AgentProviderHostApi internal constructor(
    private val engine: NapaxiEngine,
    private val context: Context,
) {
    public fun discoverProviders(): List<AgentProviderDescriptor> {
        val intent = Intent(AgentProviderContract.ACTION_INSTALL_AGENT).addCategory(Intent.CATEGORY_DEFAULT)
        val infos = context.packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return infos
            .mapNotNull { info ->
                val packageName = info.activityInfo?.packageName ?: return@mapNotNull null
                val installActivityName = info.activityInfo?.name ?: return@mapNotNull null
                AgentProviderDescriptor(
                    packageName = packageName,
                    activityName = findActionActivity(packageName) ?: installActivityName,
                    displayName = info.loadLabel(context.packageManager)?.toString() ?: packageName,
                    installActivityName = installActivityName,
                    signingCertSha256 = runCatching { signingCertSha256(packageName) }.getOrDefault(""),
                )
            }
            .distinctBy { "${it.packageName}/${it.installActivityName}" }
    }

    public fun buildInstallRequest(
        expiresAt: Instant = Instant.now().plusSeconds(600),
    ): AgentInstallRequest {
        val packageName = context.packageName
        return AgentInstallRequest(
            protocolVersion = 2,
            requestId = UUID.randomUUID().toString(),
            nonce = UUID.randomUUID().toString(),
            hostPackageName = packageName,
            createdAt = Instant.now().toString(),
            expiresAt = expiresAt.toString(),
            hostSigningCertSha256 = signingCertSha256(packageName),
            hostInstanceId = UUID.randomUUID().toString(),
            hostSharedSecret = UUID.randomUUID().toString(),
            backgroundTriggerSupported = true,
            hostBackgroundTriggerService = AgentTriggerIngressService::class.java.name,
        )
    }

    public fun requestInstall(activity: Activity, descriptor: AgentProviderDescriptor, request: AgentInstallRequest = buildInstallRequest(), requestCode: Int = REQUEST_INSTALL_AGENT): AgentInstallRequest {
        val intent = Intent(AgentProviderContract.ACTION_INSTALL_AGENT)
            .setComponent(ComponentName(descriptor.packageName, descriptor.installActivityName))
            .putExtra(AgentProviderContract.EXTRA_INSTALL_REQUEST_JSON, request.toJson())
        activity.startActivityForResult(intent, requestCode)
        return request
    }

    public fun beginInstallFromLaunchIntent(
        activity: Activity,
        request: AgentInstallRequest = buildInstallRequest(),
        requestCode: Int = REQUEST_INSTALL_AGENT,
    ): PendingAgentProviderInstall? {
        val pending = getPendingProviderInstallRequest(activity.intent) ?: return null
        val descriptor = resolveProviderInstallDescriptor(pending, discoverProviders())
        requestInstall(activity, descriptor, request, requestCode)
        return PendingAgentProviderInstall(descriptor, request, requestCode)
    }

    public fun installFromLaunchIntent(
        activity: Activity,
        request: AgentInstallRequest = buildInstallRequest(),
        requestCode: Int = REQUEST_INSTALL_AGENT,
    ): PendingAgentProviderInstall? =
        beginInstallFromLaunchIntent(activity, request, requestCode)

    public suspend fun registerInstallResult(result: AgentInstallResult): AgentAppPackage? {
        val packageJson = result.packageJson ?: return null
        return engine.agentApp.registerPackage(packageJson)
    }

    public suspend fun registerInstallResult(
        result: AgentInstallResult,
        request: AgentInstallRequest,
        descriptor: AgentProviderDescriptor,
        now: Instant = Instant.now(),
    ): AgentAppPackage {
        validateInstallResult(result, request, now)
        val packageJson = result.packageJson ?: error("Provider did not return an Agent package")
        val binding = buildInstallBinding(descriptor, request, result)
        val packageWithBinding = JSONObject(packageJson)
            .put("install_binding", binding.toJsonObject())
            .toString()
        return engine.agentApp.registerPackage(packageWithBinding)
    }

    public suspend fun handleInstallActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
        pending: PendingAgentProviderInstall,
        now: Instant = Instant.now(),
    ): AgentAppPackage? =
        handleInstallActivityResult(requestCode, resultCode, data, pending.descriptor, pending.request, pending.requestCode, now)

    public suspend fun handleInstallActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
        descriptor: AgentProviderDescriptor,
        request: AgentInstallRequest,
        expectedRequestCode: Int = REQUEST_INSTALL_AGENT,
        now: Instant = Instant.now(),
    ): AgentAppPackage? {
        if (requestCode != expectedRequestCode) return null
        check(resultCode == Activity.RESULT_OK) { "Provider install was canceled" }
        val result = parseInstallResult(data) ?: error("Install result missing")
        return registerInstallResult(result, request, descriptor, now)
    }

    public fun validateInstallResult(
        result: AgentInstallResult,
        request: AgentInstallRequest,
        now: Instant = Instant.now(),
    ) {
        validateInstallResultEnvelope(result, request, now)
    }

    public fun buildInstallBinding(
        descriptor: AgentProviderDescriptor,
        request: AgentInstallRequest,
        result: AgentInstallResult,
    ): AgentAppInstallBinding =
        AgentAppInstallBinding(
            platform = "android",
            appPackageName = descriptor.packageName,
            activityName = descriptor.activityName,
            signingCertSha256 = signingCertSha256(descriptor.packageName),
            installedAt = result.completedAt,
            installRequestId = request.requestId,
            protocolVersion = request.protocolVersion,
            hostPackageName = request.hostPackageName,
            hostSigningCertSha256 = request.hostSigningCertSha256,
            hostInstanceId = request.hostInstanceId,
            hostSharedSecret = request.hostSharedSecret,
            backgroundTriggerSupported = request.backgroundTriggerSupported,
            hostBackgroundTriggerService = request.hostBackgroundTriggerService,
        )

    public fun parseInstallResult(data: Intent?): AgentInstallResult? =
        data?.getStringExtra(AgentProviderContract.EXTRA_INSTALL_RESULT_JSON)
            ?.let { runCatching { AgentInstallResult.fromJson(it) }.getOrNull() }

    public fun consumeTrigger(intent: Intent?): AgentTriggerRequest? =
        intent?.takeIf { it.action == AgentProviderContract.ACTION_HOST_TRIGGER_AGENT }
            ?.getStringExtra(AgentProviderContract.EXTRA_TRIGGER_REQUEST_JSON)
            ?.let { runCatching { AgentTriggerRequest.fromJson(it) }.getOrNull() }

    public fun getPendingProviderInstallRequest(intent: Intent?): AgentProviderDescriptor? =
        pendingProviderInstallDescriptor(intent)

    public fun clearPendingProviderInstallRequest(activity: Activity) {
        if (activity.intent?.action == AgentProviderContract.ACTION_HOST_INSTALL_PROVIDER_AGENT) {
            activity.intent = Intent(activity.intent).apply { action = null }
        }
    }

    public fun getPendingAgentTriggerRequest(intent: Intent?): AgentTriggerRequest? =
        consumeTrigger(intent)
            ?: AgentTriggerStore.peek(context)?.let { runCatching { AgentTriggerRequest.fromJson(it) }.getOrNull() }

    public fun consumePendingTrigger(intent: Intent? = null): AgentTriggerRequest? =
        getPendingAgentTriggerRequest(intent)

    public fun clearPendingAgentTriggerRequest(activity: Activity) {
        if (activity.intent?.action == AgentProviderContract.ACTION_HOST_TRIGGER_AGENT) {
            activity.intent = Intent(activity.intent).apply { action = null }
        }
        AgentTriggerStore.remove(context, null)
    }

    public fun peekQueuedTrigger(): AgentTriggerRequest? =
        AgentTriggerStore.peek(context)?.let { runCatching { AgentTriggerRequest.fromJson(it) }.getOrNull() }

    public fun removeQueuedTrigger(request: AgentTriggerRequest? = null) {
        AgentTriggerStore.remove(context, request?.toJson())
    }

    public suspend fun acceptTrigger(request: AgentTriggerRequest): AcceptedAgentTrigger {
        val packageDef = engine.agentApp.getPackage(request.agentId)
            ?: error("Triggered Agent is not installed")
        validateTrigger(request, packageDef)
        markTriggerConsumed(request)
        val accepted = JSONObject(engine.agentApp.acceptTrigger(request.toJson()).rawJson)
        val displayName = JSONObject(packageDef.toJson()).optString("display_name", packageDef.agentId)
            .takeIf { it.isNotBlank() }
            ?: packageDef.agentId
        return AcceptedAgentTrigger(accepted.put("display_name", displayName).toString())
    }

    public suspend fun validateTrigger(request: AgentTriggerRequest): AgentAppPackage {
        val packageDef = engine.agentApp.getPackage(request.agentId)
            ?: error("Triggered Agent is not installed")
        return validateTrigger(request, packageDef)
    }

    public fun validateTrigger(
        request: AgentTriggerRequest,
        packageDef: AgentAppPackage,
        now: Instant = Instant.now(),
    ): AgentAppPackage {
        validateTriggerRequest(
            request = request,
            packageDef = packageDef,
            isConsumed = isTriggerConsumed(request.requestId),
            now = now,
        )
        return packageDef
    }

    public fun markTriggerConsumed(request: AgentTriggerRequest) {
        markTriggerConsumed(request.requestId)
    }

    public fun markTriggerConsumed(requestId: String) {
        if (requestId.isBlank()) return
        val next = consumedTriggerIds().toMutableSet()
        next += requestId
        triggerPreferences().edit().putStringSet(CONSUMED_TRIGGERS_KEY, next).apply()
    }

    public fun isTriggerConsumed(requestId: String): Boolean =
        consumedTriggerIds().contains(requestId)

    public fun buildActionIntent(packageDef: AgentPackage, proposal: AgentAppActionProposal): Intent {
        val action = packageDef.actions.firstOrNull {
            it.actionId == proposal.actionId && it.toolName == proposal.toolName
        } ?: error("Package has no action matching proposal ${proposal.actionId}/${proposal.toolName}")
        require(packageDef.providerId == proposal.providerId) { "Proposal provider does not match package" }
        require(packageDef.agentId == proposal.agentId) { "Proposal agent does not match package" }
        require(proposal.nonce.isNotBlank()) { "Proposal nonce is required" }
        require(proposal.idempotencyKey.isNotBlank()) { "Proposal idempotency key is required" }
        require(runCatching { Instant.parse(proposal.expiresAt) }.getOrNull()?.isAfter(Instant.now()) == true) {
            "Proposal expired"
        }
        val handoff = JSONObject(packageDef.handoffJson)
        val activityName = handoff.optString("activityName", handoff.optString("activity_name"))
        require(activityName.isNotBlank()) { "Agent package handoff missing activityName" }
        return Intent(AgentProviderContract.ACTION_HANDLE_PROPOSAL)
            .setComponent(ComponentName(packageDef.providerId, activityName))
            .putExtra(AgentProviderContract.EXTRA_PROPOSAL_JSON, proposal.rawJson)
            .putExtra(AgentProviderContract.EXTRA_ACTION_JSON, action.toJson())
            .putExtra(AgentProviderContract.EXTRA_PACKAGE_JSON, packageDef.toJson())
    }

    public fun buildTrustedActionIntent(packageDef: AgentAppPackage, proposal: AgentAppActionProposal): Intent {
        val binding = packageDef.installBinding
            ?: error("Provider action package is not installed with an Android binding")
        return buildTrustedActionIntent(
            packageDef = packageDef,
            proposal = proposal,
            currentSigningCertSha256 = signingCertSha256(binding.appPackageName),
        )
    }

    public fun parseActionResult(data: Intent?): agent.provider.sdk.ActionResult? =
        data?.getStringExtra(AgentProviderContract.EXTRA_RESULT_JSON)
            ?.let { runCatching { agent.provider.sdk.ActionResult.fromJson(it) }.getOrNull() }

    public fun packageJsonForProvider(packageDef: AgentAppPackage): JSONObject =
        sanitizePackageForProvider(packageDef)

    private fun signingCertSha256(packageName: String): String {
        val signatures = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
            context.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
                .signingInfo?.apkContentsSigners
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNATURES).signatures
        }
        val cert = signatures?.firstOrNull()?.toByteArray() ?: return ""
        return MessageDigest.getInstance("SHA-256")
            .digest(cert)
            .joinToString("") { "%02x".format(it) }
    }

    private fun findActionActivity(packageName: String): String? {
        val intent = Intent(AgentProviderContract.ACTION_HANDLE_PROPOSAL)
            .addCategory(Intent.CATEGORY_DEFAULT)
            .setPackage(packageName)
        return context.packageManager
            .queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .firstOrNull()
            ?.activityInfo
            ?.name
    }

    private fun consumedTriggerIds(): Set<String> =
        triggerPreferences().getStringSet(CONSUMED_TRIGGERS_KEY, emptySet()).orEmpty()

    private fun triggerPreferences() =
        context.getSharedPreferences(TRIGGER_PREFS, Context.MODE_PRIVATE)

    public companion object {
        public const val REQUEST_INSTALL_AGENT: Int = 4303
        public const val REQUEST_HANDLE_PROPOSAL: Int = 4304
        public const val SIGNATURE_ALGORITHM_HMAC_SHA256_V1: String = "hmac-sha256-v1"
        private const val TRIGGER_PREFS = "napaxi_agent_provider_triggers"
        private const val CONSUMED_TRIGGERS_KEY = "consumed_trigger_request_ids"

        @JvmStatic
        public fun buildTrustedActionIntent(
            packageDef: AgentAppPackage,
            proposal: AgentAppActionProposal,
            currentSigningCertSha256: String?,
        ): Intent {
            val handoff = validateTrustedActionHandoff(packageDef, proposal, currentSigningCertSha256)
            val binding = handoff.first
            val action = handoff.second
            return Intent(AgentProviderContract.ACTION_HANDLE_PROPOSAL)
                .setComponent(ComponentName(binding.appPackageName, binding.activityName))
                .putExtra(AgentProviderContract.EXTRA_PROPOSAL_JSON, proposal.rawJson)
                .putExtra(AgentProviderContract.EXTRA_ACTION_JSON, action.toJson())
                .putExtra(AgentProviderContract.EXTRA_PACKAGE_JSON, sanitizePackageForProvider(packageDef).toString())
        }

        @JvmStatic
        public fun validateTrustedActionHandoff(
            packageDef: AgentAppPackage,
            proposal: AgentAppActionProposal,
            currentSigningCertSha256: String?,
        ): Pair<AgentAppInstallBinding, AgentAppPackageAction> {
            val binding = packageDef.installBinding
                ?: error("Provider action package is not installed with an Android binding")
            require(binding.platform == "android") { "Provider action binding is not Android" }
            require(
                binding.appPackageName.isNotBlank() &&
                    binding.activityName.isNotBlank() &&
                    binding.signingCertSha256.isNotBlank(),
            ) {
                "Provider action binding is incomplete"
            }
            require(currentSigningCertSha256.equals(binding.signingCertSha256, ignoreCase = true)) {
                "Provider app signature changed; reinstall this Agent"
            }
            val action = packageDef.actions.firstOrNull {
                it.actionId == proposal.actionId && it.toolName == proposal.toolName
            } ?: error("Package has no action matching proposal ${proposal.actionId}/${proposal.toolName}")
            require(packageDef.providerId == proposal.providerId) { "Proposal provider does not match package" }
            require(packageDef.agentId == proposal.agentId) { "Proposal agent does not match package" }
            require(proposal.nonce.isNotBlank()) { "Proposal nonce is required" }
            require(proposal.idempotencyKey.isNotBlank()) { "Proposal idempotency key is required" }
            require(runCatching { Instant.parse(proposal.expiresAt) }.getOrNull()?.isAfter(Instant.now()) == true) {
                "Proposal expired"
            }
            return binding to action
        }

        @JvmStatic
        public fun sanitizePackageForProvider(packageDef: AgentAppPackage): JSONObject {
            val copy = JSONObject(packageDef.toJson())
            copy.optJSONObject("install_binding")?.remove("host_shared_secret")
            return copy
        }

        @JvmStatic
        public fun pendingProviderInstallDescriptor(intent: Intent?): AgentProviderDescriptor? {
            if (intent?.action != AgentProviderContract.ACTION_HOST_INSTALL_PROVIDER_AGENT) return null
            val packageName = intent.getStringExtra("providerPackageName")
                ?: intent.getStringExtra("packageName")
                ?: intent.data?.getQueryParameter("package")
                ?: return null
            val activityName = intent.getStringExtra("activityName")
                ?: intent.data?.getQueryParameter("activity")
                ?: ""
            val installActivityName = intent.getStringExtra("installActivityName")
                ?: intent.data?.getQueryParameter("installActivity")
                ?: activityName
            return AgentProviderDescriptor(
                packageName = packageName,
                activityName = activityName,
                installActivityName = installActivityName,
                displayName = intent.getStringExtra("label") ?: packageName,
                signingCertSha256 = intent.getStringExtra("signingCertSha256") ?: "",
            )
        }

        @JvmStatic
        public fun resolveProviderInstallDescriptor(
            pending: AgentProviderDescriptor,
            discovered: List<AgentProviderDescriptor>,
        ): AgentProviderDescriptor =
            if (pending.platform != "ios" &&
                (pending.installActivityName.isBlank() || pending.activityName.isBlank())
            ) {
                discovered.firstOrNull { it.packageName == pending.packageName } ?: pending
            } else {
                pending
            }

        @JvmStatic
        public fun validateInstallResultEnvelope(
            result: AgentInstallResult,
            request: AgentInstallRequest,
            now: Instant = Instant.now(),
        ) {
            val expiresAt = runCatching { Instant.parse(request.expiresAt) }.getOrNull()
                ?: error("Install request expiry is invalid")
            check(now.isBefore(expiresAt)) { "Install request expired" }
            check(result.requestId == request.requestId && result.nonce == request.nonce) {
                "Install result does not match the request"
            }
            check(result.status == AgentInstallStatus.SUCCEEDED) {
                result.error?.message ?: "Provider install failed"
            }
        }

        @JvmStatic
        public fun validateTriggerRequest(
            request: AgentTriggerRequest,
            packageDef: AgentAppPackage,
            isConsumed: Boolean = false,
            now: Instant = Instant.now(),
        ) {
            check(request.protocolVersion >= 2) { "Agent trigger protocol v2 is required" }
            check(
                request.requestId.isNotBlank() &&
                    request.providerId.isNotBlank() &&
                    request.agentId.isNotBlank() &&
                    request.message.isNotBlank() &&
                    request.nonce.isNotBlank() &&
                    request.idempotencyKey.isNotBlank(),
            ) {
                "Agent trigger is missing required fields"
            }
            val expiresAt = runCatching { Instant.parse(request.expiresAt) }.getOrNull()
                ?: error("Agent trigger expiry is invalid")
            check(expiresAt.isAfter(now)) { "Agent trigger expired" }
            check(!isConsumed) { "Agent trigger has already been consumed" }
            check(request.hostInstanceId.isNotBlank()) { "Agent trigger is missing trusted host instance" }
            check(request.signatureAlgorithm == SIGNATURE_ALGORITHM_HMAC_SHA256_V1) {
                "Agent trigger signature algorithm is unsupported"
            }
            check(!request.signature.isNullOrBlank()) { "Agent trigger is missing signature" }
            check(packageDef.providerId == request.providerId) {
                "Agent trigger provider does not match installed Agent"
            }
            val binding = packageDef.installBinding
                ?: error("Agent trigger is not bound to a trusted host")
            check(binding.hostInstanceId == request.hostInstanceId && binding.hostSharedSecret.isNotBlank()) {
                "Agent trigger is not bound to a trusted host"
            }
            val expected = hmacSha256Base64NoPad(binding.hostSharedSecret, triggerSignaturePayload(request))
            check(expected == request.signature) { "Agent trigger signature is invalid" }
        }

        @JvmStatic
        public fun triggerSignaturePayload(request: AgentTriggerRequest): String {
            val payloadHash = sha256Base64NoPad(canonicalJson(JSONObject(request.payloadJson)))
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

        @JvmStatic
        public fun signTriggerRequest(request: AgentTriggerRequest, binding: AgentAppInstallBinding): AgentTriggerRequest {
            val unsigned = request.copy(
                hostInstanceId = binding.hostInstanceId,
                signatureAlgorithm = SIGNATURE_ALGORITHM_HMAC_SHA256_V1,
                signature = null,
            )
            return unsigned.copy(
                signature = hmacSha256Base64NoPad(
                    binding.hostSharedSecret,
                    triggerSignaturePayload(unsigned),
                ),
            )
        }

        private fun canonicalJson(value: Any?): String =
            when (value) {
                null, JSONObject.NULL -> "null"
                is Boolean, is Number -> value.toString()
                is String -> JSONObject.quote(value)
                is org.json.JSONArray -> {
                    List(value.length()) { index -> canonicalJson(value.get(index)) }
                        .joinToString(prefix = "[", postfix = "]", separator = ",")
                }
                is JSONObject -> {
                    value.keys().asSequence().toList().sorted()
                        .joinToString(prefix = "{", postfix = "}", separator = ",") { key ->
                            "${JSONObject.quote(key)}:${canonicalJson(value.get(key))}"
                        }
                }
                else -> JSONObject.quote(value.toString())
            }

        private fun sha256Base64NoPad(value: String): String =
            Base64.getEncoder().withoutPadding().encodeToString(
                MessageDigest.getInstance("SHA-256").digest(value.toByteArray(Charsets.UTF_8)),
            )

        private fun hmacSha256Base64NoPad(secret: String, payload: String): String {
            val mac = Mac.getInstance("HmacSHA256")
            mac.init(SecretKeySpec(secret.toByteArray(Charsets.UTF_8), "HmacSHA256"))
            return Base64.getEncoder().withoutPadding().encodeToString(
                mac.doFinal(payload.toByteArray(Charsets.UTF_8)),
            )
        }
    }
}

public class AndroidAgentProviderActionExecutor @JvmOverloads constructor(
    private val activity: Activity,
    private val requestCode: Int = AgentProviderHostApi.REQUEST_HANDLE_PROPOSAL,
) : AgentAppActionExecutor {
    private var pendingCallback: AgentAppActionCallback? = null
    private var pendingRequestId: String? = null

    override fun execute(request: AgentAppActionRequest, callback: AgentAppActionCallback) {
        if (pendingCallback != null) {
            callback.success(failedActionResult(request.requestId, "Agent provider action already in progress"))
            return
        }
        val packageDef = runCatching { AgentAppPackage(request.packageJson.toString()) }.getOrNull()
        if (packageDef == null) {
            callback.success(failedActionResult(request.requestId, "Invalid provider action package JSON"))
            return
        }
        val binding = packageDef.installBinding
        val currentDigest = binding?.appPackageName
            ?.takeIf(String::isNotBlank)
            ?.let { AgentTriggerIngressService.signingCertSha256(activity, it) }
        val intent = runCatching {
            AgentProviderHostApi.buildTrustedActionIntent(
                packageDef = packageDef,
                proposal = request.proposal,
                currentSigningCertSha256 = currentDigest,
            )
        }.getOrElse { error ->
            callback.success(failedActionResult(request.requestId, error.message ?: "Provider action handoff failed"))
            return
        }
        pendingCallback = callback
        pendingRequestId = request.requestId
        try {
            activity.startActivityForResult(intent, requestCode)
        } catch (error: Throwable) {
            pendingCallback = null
            pendingRequestId = null
            callback.success(failedActionResult(request.requestId, error.message ?: "Provider action handoff failed"))
        }
    }

    public fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != this.requestCode) return false
        val callback = pendingCallback ?: return false
        val requestId = pendingRequestId.orEmpty()
        pendingCallback = null
        pendingRequestId = null
        val resultJson = data?.getStringExtra(AgentProviderContract.EXTRA_RESULT_JSON)
        if (resultCode == Activity.RESULT_OK && !resultJson.isNullOrBlank()) {
            callback.success(AgentAppActionResult(resultJson))
        } else {
            callback.success(failedActionResult(requestId, "Provider action was canceled or returned no result"))
        }
        return true
    }

    public companion object {
        @JvmStatic
        public fun failedActionResult(requestId: String, message: String): AgentAppActionResult =
            AgentAppActionResult(
                JSONObject()
                    .put("request_id", requestId)
                    .put("status", "failed")
                    .put("result", JSONObject())
                    .put(
                        "error",
                        JSONObject()
                            .put("code", "provider_action_failed")
                            .put("message", message),
                    )
                    .put("completed_at", Instant.now().toString())
                    .toString(),
            )
    }
}

public class AgentTriggerIngressService : Service() {
    private val binder = object : IAgentTriggerIngress.Stub() {
        override fun submitTrigger(triggerJson: String?): String =
            handleSubmit(triggerJson.orEmpty(), Binder.getCallingUid())
    }

    private fun handleSubmit(triggerJson: String, callingUid: Int): String {
        val request = runCatching { AgentTriggerRequest.fromJson(triggerJson) }.getOrNull()
            ?: return responseJson(
                status = AgentTriggerSubmitResult.REJECTED,
                requestId = "",
                code = "invalid_json",
                message = "Trigger JSON is invalid.",
            )
        val validation = validateIngressTrigger(request, callingUid)
        if (validation != null) {
            return responseJson(
                status = AgentTriggerSubmitResult.REJECTED,
                requestId = request.requestId,
                code = validation.first,
                message = validation.second,
            )
        }
        if (!persistTriggerRecord(request, triggerJson)) {
            return responseJson(
                status = AgentTriggerSubmitResult.REJECTED,
                requestId = request.requestId,
                code = "persist_failed",
                message = "Unable to persist trigger.",
            )
        }
        AgentTriggerStore.enqueue(this@AgentTriggerIngressService, triggerJson)
        val delivered = dispatchToHost(triggerJson)
        if (!delivered) {
            startBackgroundServiceForQueuedTrigger(request)
        }
        return AgentTriggerSubmitResult(
            status = if (delivered) AgentTriggerSubmitResult.ACCEPTED else AgentTriggerSubmitResult.QUEUED,
            requestId = request.requestId,
            error = null,
        ).toJson()
    }

    override fun onBind(intent: Intent?): IBinder? {
        val component = intent?.component ?: return null
        if (component.packageName != packageName || component.className != SERVICE_CLASS_NAME) return null
        return binder
    }

    private fun validateIngressTrigger(request: AgentTriggerRequest, callingUid: Int): Pair<String, String>? {
        val packageDef = loadInstalledAgentPackage(request.agentId)
            ?: return "agent_not_installed" to "Triggered Agent package is not installed."
        val envelopeValidation = validateIngressTriggerEnvelope(
            request = request,
            packageDef = packageDef,
            triggerAlreadyRecorded = triggerRecordFile(request.requestId).exists(),
        )
        if (envelopeValidation != null) return envelopeValidation
        val binding = packageDef.installBinding
            ?: return "missing_binding" to "Installed Agent has no trusted binding."
        val callerPackages = packageManager.getPackagesForUid(callingUid)?.toSet().orEmpty()
        val currentDigest = signingCertSha256(this, binding.appPackageName)
        return validateIngressCaller(
            callerPackages = callerPackages,
            currentSigningCertSha256 = currentDigest,
            binding = binding,
        )
    }

    private fun persistTriggerRecord(request: AgentTriggerRequest, triggerJson: String): Boolean {
        val file = triggerRecordFile(request.requestId)
        val parent = file.parentFile ?: return false
        if (!parent.exists() && !parent.mkdirs()) return false
        val now = Instant.now().toString()
        val record = JSONObject()
            .put("trigger", JSONObject(triggerJson))
            .put("status", "queued")
            .put("created_at", now)
            .put("updated_at", now)
        return runCatching { file.writeText(record.toString(2)) }.isSuccess
    }

    private fun loadInstalledAgentPackage(agentId: String): AgentAppPackage? {
        val file = File(filesDir, "napaxi/agent_app_packages/${safeFileComponent(agentId)}.json")
        return runCatching { AgentAppPackage(file.readText()) }.getOrNull()
    }

    private fun triggerRecordFile(requestId: String): File =
        File(filesDir, "napaxi/agent_app_triggers/${safeFileComponent(requestId)}.json")

    private fun startBackgroundServiceForQueuedTrigger(request: AgentTriggerRequest) {
        runCatching {
            val intent = Intent(this, NapaxiAgentService::class.java)
                .setAction(NapaxiAgentService.ACTION_START)
                .putExtra(NapaxiAgentService.EXTRA_CHANNEL_NAME, "Agent")
                .putExtra(NapaxiAgentService.EXTRA_CHANNEL_DESCRIPTION, "Agent background execution")
                .putExtra(NapaxiAgentService.EXTRA_ONGOING_TITLE, "Agent received a trigger")
                .putExtra(
                    NapaxiAgentService.EXTRA_ONGOING_MESSAGE,
                    "Tap to continue ${request.source.ifBlank { "provider" }} request.",
                )
                .putExtra(NapaxiAgentService.EXTRA_WAKELOCK_TIMEOUT_MS, 30 * 60 * 1000)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
            NapaxiNotificationManager.showCompletionNotification(
                this,
                "Agent trigger received",
                "Tap to continue the provider request.",
            )
        }
    }

    public companion object {
        public const val SERVICE_CLASS_NAME: String = "com.napaxi.android.AgentTriggerIngressService"
        private var dispatchCallback: ((String) -> Boolean)? = null

        @JvmStatic
        public fun setDispatchCallback(callback: ((String) -> Boolean)?) {
            dispatchCallback = callback
        }

        @JvmStatic
        public fun dispatchToHost(triggerJson: String): Boolean =
            dispatchCallback?.invoke(triggerJson) == true

        @JvmStatic
        public fun responseJson(
            status: String,
            requestId: String,
            code: String? = null,
            message: String? = null,
        ): String {
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
            return result.toString()
        }

        @JvmStatic
        public fun validateIngressTriggerEnvelope(
            request: AgentTriggerRequest,
            packageDef: AgentAppPackage,
            triggerAlreadyRecorded: Boolean = false,
            now: Instant = Instant.now(),
        ): Pair<String, String>? {
            if (request.protocolVersion < 2) {
                return "invalid_protocol" to "Agent trigger protocol v2 is required."
            }
            if (
                request.requestId.isBlank() ||
                request.providerId.isBlank() ||
                request.agentId.isBlank() ||
                request.message.isBlank() ||
                request.nonce.isBlank() ||
                request.idempotencyKey.isBlank()
            ) {
                return "missing_fields" to "Agent trigger is missing required fields."
            }
            val expiresAt = runCatching { Instant.parse(request.expiresAt) }.getOrNull()
                ?: return "invalid_expiry" to "Trigger expiry is invalid."
            if (!expiresAt.isAfter(now)) {
                return "expired" to "Trigger has expired."
            }
            if (triggerAlreadyRecorded) {
                return "replayed" to "Trigger request has already been accepted."
            }
            if (packageDef.providerId != request.providerId) {
                return "provider_mismatch" to "Trigger provider does not match installed Agent."
            }
            val binding = packageDef.installBinding
                ?: return "missing_binding" to "Installed Agent has no trusted binding."
            if (binding.platform != "android") {
                return "unsupported_platform" to "Background trigger is Android-only."
            }
            if (
                binding.hostInstanceId.isBlank() ||
                binding.hostSharedSecret.isBlank() ||
                request.hostInstanceId != binding.hostInstanceId
            ) {
                return "host_binding_mismatch" to "Trigger is not bound to this Host."
            }
            if (
                request.signatureAlgorithm != AgentProviderHostApi.SIGNATURE_ALGORITHM_HMAC_SHA256_V1 ||
                request.signature.isNullOrBlank()
            ) {
                return "missing_signature" to "Trigger is missing trusted signature fields."
            }
            val trusted = runCatching {
                AgentProviderHostApi.validateTriggerRequest(
                    request = request,
                    packageDef = packageDef,
                    isConsumed = false,
                    now = now,
                )
            }.isSuccess
            if (!trusted) {
                return "signature_invalid" to "Trigger signature is invalid."
            }
            return null
        }

        @JvmStatic
        public fun validateIngressCaller(
            callerPackages: Set<String>,
            currentSigningCertSha256: String?,
            binding: AgentAppInstallBinding,
        ): Pair<String, String>? {
            if (binding.appPackageName.isBlank() || !callerPackages.contains(binding.appPackageName)) {
                return "caller_mismatch" to "Calling package does not match installed Provider."
            }
            if (
                currentSigningCertSha256 == null ||
                !currentSigningCertSha256.equals(binding.signingCertSha256, ignoreCase = true)
            ) {
                return "caller_signature_mismatch" to
                    "Calling package signature does not match installed Provider."
            }
            return null
        }

        @JvmStatic
        public fun signingCertSha256(context: Context, packageName: String): String? {
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

        private fun safeFileComponent(value: String): String =
            value.map { ch ->
                if (ch.isLetterOrDigit() || ch == '-' || ch == '_' || ch == '.') ch else '_'
            }.joinToString("")
    }
}

public object AgentTriggerStore {
    private const val PREFS_NAME = "agent_provider_background_triggers"
    private const val KEY_PENDING = "pending_trigger_json_queue"

    @Synchronized
    public fun enqueue(context: Context, triggerJson: String) {
        val requestId = requestId(triggerJson)
        val queue = readQueue(context).toMutableList()
        if (requestId.isNotBlank() && queue.any { requestId(it) == requestId }) return
        queue.add(triggerJson)
        context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING, JSONArray(queue).toString())
            .apply()
    }

    @Synchronized
    public fun peek(context: Context): String? = readQueue(context).firstOrNull()

    @Synchronized
    public fun remove(context: Context, triggerJson: String?) {
        val queue = readQueue(context)
        if (queue.isEmpty()) return
        val requestId = requestId(triggerJson.orEmpty())
        val next = if (requestId.isBlank()) {
            queue.drop(1)
        } else {
            queue.filterNot { requestId(it) == requestId }
        }
        context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_PENDING, JSONArray(next).toString())
            .apply()
    }

    public fun readQueue(context: Context): List<String> {
        val raw = context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_PENDING, "[]") ?: "[]"
        return runCatching {
            val array = JSONArray(raw)
            List(array.length()) { index -> array.optString(index) }
                .filter { it.isNotBlank() }
        }.getOrDefault(emptyList())
    }

    @JvmStatic
    public fun requestId(triggerJson: String): String =
        runCatching { JSONObject(triggerJson).optString("request_id", "") }.getOrDefault("")
}
