package agent.provider.sdk

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.Uri
import android.os.IBinder
import java.time.Instant
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

object AgentProvider {
    @JvmStatic
    fun packageToJson(packageDef: AgentPackage): String = packageDef.toJson()

    @JvmStatic
    fun packageFromJson(json: String): AgentPackage = AgentPackage.fromJson(json)

    @JvmStatic
    fun isInstallRequestIntent(intent: Intent?): Boolean =
        intent?.action == AgentProviderContract.ACTION_INSTALL_AGENT &&
            intent.hasExtra(AgentProviderContract.EXTRA_INSTALL_REQUEST_JSON)

    @JvmStatic
    fun parseInstallRequest(intent: Intent?): AgentInstallRequest? {
        if (!isInstallRequestIntent(intent)) {
            return null
        }

        val json = intent?.getStringExtra(AgentProviderContract.EXTRA_INSTALL_REQUEST_JSON)
            ?: return null
        return runCatching { AgentInstallRequest.fromJson(json) }.getOrNull()
    }

    @JvmStatic
    fun buildInstallResultIntent(
        packageDef: AgentPackage,
        request: AgentInstallRequest,
    ): Intent =
        buildInstallResultIntent(packageDef, request, Intent())

    internal fun buildInstallResultIntent(
        packageDef: AgentPackage,
        request: AgentInstallRequest,
        intent: Intent,
    ): Intent {
        val result = AgentInstallResult(
            status = AgentInstallStatus.SUCCEEDED,
            requestId = request.requestId,
            nonce = request.nonce,
            packageJson = packageDef.toJson(),
            completedAt = Instant.now().toString(),
        )
        return intent.putExtra(AgentProviderContract.EXTRA_INSTALL_RESULT_JSON, result.toJson())
            .putExtra(AgentProviderContract.EXTRA_PACKAGE_JSON, packageDef.toJson())
    }

    @JvmStatic
    fun buildInstallFailureIntent(
        request: AgentInstallRequest,
        code: String,
        message: String,
    ): Intent =
        buildInstallFailureIntent(request, code, message, Intent())

    internal fun buildInstallFailureIntent(
        request: AgentInstallRequest,
        code: String,
        message: String,
        intent: Intent,
    ): Intent {
        val result = AgentInstallResult(
            status = AgentInstallStatus.FAILED,
            requestId = request.requestId,
            nonce = request.nonce,
            error = ActionError(code, message),
            completedAt = Instant.now().toString(),
        )
        return intent.putExtra(AgentProviderContract.EXTRA_INSTALL_RESULT_JSON, result.toJson())
    }

    @JvmStatic
    fun buildHostTriggerIntent(
        request: AgentTriggerRequest,
        hostPackageName: String,
    ): Intent =
        buildHostTriggerIntent(request, hostPackageName, Intent(AgentProviderContract.ACTION_HOST_TRIGGER_AGENT))

    internal fun buildHostTriggerIntent(
        request: AgentTriggerRequest,
        hostPackageName: String,
        intent: Intent,
    ): Intent =
        intent.setAction(AgentProviderContract.ACTION_HOST_TRIGGER_AGENT).apply {
            if (hostPackageName.isNotBlank()) {
                setPackage(hostPackageName)
            }
            putExtra(AgentProviderContract.EXTRA_TRIGGER_REQUEST_JSON, request.toJson())
        }

    @JvmStatic
    fun signTriggerRequest(
        request: AgentTriggerRequest,
        binding: TrustedHostBinding,
    ): AgentTriggerRequest =
        AgentProviderSecurity.signTriggerRequest(request, binding)

    @JvmStatic
    @JvmOverloads
    fun submitBackgroundTrigger(
        context: Context,
        request: AgentTriggerRequest,
        binding: TrustedHostBinding,
        timeoutMillis: Long = 3000,
    ): AgentTriggerSubmitResult {
        if (!binding.backgroundTriggerSupported || binding.hostBackgroundTriggerService.isBlank()) {
            return AgentTriggerSubmitResult(
                status = AgentTriggerSubmitResult.UNSUPPORTED,
                requestId = request.requestId,
                error = ActionError("unsupported", "Host does not advertise background trigger support."),
            )
        }
        val signed = AgentProviderSecurity.signTriggerRequest(request, binding)
        val intent = Intent().apply {
            component = ComponentName(binding.hostPackageName, binding.hostBackgroundTriggerService)
        }
        val latch = CountDownLatch(1)
        var response: AgentTriggerSubmitResult? = null
        var serviceError: String? = null
        val connection = object : ServiceConnection {
            override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
                try {
                    val ingress = IAgentTriggerIngress.Stub.asInterface(service)
                    response = AgentTriggerSubmitResult.fromJson(ingress.submitTrigger(signed.toJson()))
                } catch (error: Exception) {
                    serviceError = error.message ?: "Background trigger submission failed."
                } finally {
                    latch.countDown()
                }
            }

            override fun onServiceDisconnected(name: ComponentName?) {
                serviceError = "Host background trigger service disconnected."
                latch.countDown()
            }
        }
        val bound = runCatching {
            context.applicationContext.bindService(intent, connection, Context.BIND_AUTO_CREATE)
        }.getOrDefault(false)
        if (!bound) {
            return AgentTriggerSubmitResult(
                status = AgentTriggerSubmitResult.HOST_UNAVAILABLE,
                requestId = request.requestId,
                error = ActionError("bind_failed", "Unable to bind Host background trigger service."),
            )
        }
        try {
            if (!latch.await(timeoutMillis, TimeUnit.MILLISECONDS)) {
                return AgentTriggerSubmitResult(
                    status = AgentTriggerSubmitResult.HOST_UNAVAILABLE,
                    requestId = request.requestId,
                    error = ActionError("timeout", "Host background trigger service timed out."),
                )
            }
        } finally {
            runCatching { context.applicationContext.unbindService(connection) }
        }
        return response ?: AgentTriggerSubmitResult(
            status = AgentTriggerSubmitResult.HOST_UNAVAILABLE,
            requestId = request.requestId,
            error = ActionError("submit_failed", serviceError ?: "Host background trigger service unavailable."),
        )
    }

    @JvmStatic
    fun isProposalIntent(intent: Intent?): Boolean =
        intent?.action == AgentProviderContract.ACTION_HANDLE_PROPOSAL &&
            intent.hasExtra(AgentProviderContract.EXTRA_PROPOSAL_JSON)

    @JvmStatic
    fun parseProposal(intent: Intent?): ActionProposal? {
        if (!isProposalIntent(intent)) {
            return null
        }

        val json = intent?.getStringExtra(AgentProviderContract.EXTRA_PROPOSAL_JSON)
            ?: return null
        return runCatching { ActionProposal.fromJson(json) }.getOrNull()
    }

    @JvmStatic
    fun validateProposal(
        proposal: ActionProposal,
        packageDef: AgentPackage,
        nowMillis: Long,
    ): ProposalValidationResult {
        if (proposal.providerId != packageDef.providerId) {
            return ProposalValidationResult.failure(
                "provider_mismatch",
                "Proposal provider does not match this agent package.",
            )
        }

        if (proposal.agentId != packageDef.agentId) {
            return ProposalValidationResult.failure(
                "agent_mismatch",
                "Proposal agent does not match this agent package.",
            )
        }

        val action = packageDef.actions.firstOrNull { it.actionId == proposal.actionId }
            ?: return ProposalValidationResult.failure(
                "action_not_found",
                "Proposal action is not declared by this agent package.",
            )

        if (proposal.toolName.isNotBlank() && proposal.toolName != action.toolName) {
            return ProposalValidationResult.failure(
                "tool_mismatch",
                "Proposal tool name does not match the declared action.",
            )
        }

        if (proposal.nonce.isBlank()) {
            return ProposalValidationResult.failure(
                "missing_nonce",
                "Proposal nonce is required.",
            )
        }

        if (proposal.idempotencyKey.isBlank()) {
            return ProposalValidationResult.failure(
                "missing_idempotency_key",
                "Proposal idempotency key is required.",
            )
        }

        val expiresAtMillis = runCatching { Instant.parse(proposal.expiresAt).toEpochMilli() }
            .getOrNull()
            ?: return ProposalValidationResult.failure(
                "invalid_expiry",
                "Proposal expires_at must be an ISO-8601 instant.",
            )

        if (expiresAtMillis <= nowMillis) {
            return ProposalValidationResult.failure(
                "expired",
                "Proposal has expired.",
            )
        }

        return ProposalValidationResult.success()
    }

    @JvmStatic
    fun buildResultIntent(result: ActionResult): Intent =
        buildResultIntent(result, Intent())

    internal fun buildResultIntent(result: ActionResult, intent: Intent): Intent =
        intent.setAction(AgentProviderContract.ACTION_RESULT).putExtra(
            AgentProviderContract.EXTRA_RESULT_JSON,
            result.toJson(),
        )

    @JvmStatic
    fun buildCallbackUri(result: ActionResult, callbackUri: Uri?): Uri? =
        callbackUri?.buildUpon()
            ?.appendQueryParameter("result", result.toJson())
            ?.build()
}
