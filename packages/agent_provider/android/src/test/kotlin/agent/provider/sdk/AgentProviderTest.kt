package agent.provider.sdk

import android.content.Intent
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.mockito.ArgumentCaptor
import org.mockito.Mockito.`when`
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify

class AgentProviderTest {
    @Test
    fun packageJsonRoundTrip() {
        val packageDef = samplePackage()

        val parsed = AgentProvider.packageFromJson(AgentProvider.packageToJson(packageDef))

        assertEquals("provider.test", parsed.providerId)
        assertEquals("provider.agent", parsed.agentId)
        assertEquals(1, parsed.actions.size)
        assertEquals("provider.order.create", parsed.actions.first().actionId)
        assertEquals(packageDef.toJson(), packageDef.toJsonString())
    }

    @Test
    fun packageFromMapMatchesFlutterStableDefaults() {
        val packageDef = AgentPackage.fromMap(
            mapOf(
                "provider_id" to "provider.map",
                "agent_id" to "provider.agent",
                "display_name" to "Provider Agent",
                "actions" to listOf(
                    mapOf(
                        "action_id" to "provider.order.create",
                        "tool_name" to "app_action_provider_order_create",
                        "description" to "Create an order proposal.",
                    ),
                ),
                "handoff" to mapOf("mode" to "activity"),
            ),
        )
        val missingFields = AgentPackage.fromMap(emptyMap<String, Any?>())

        assertEquals("provider.map", packageDef.providerId)
        assertEquals("activity", JSONObject(packageDef.handoffJson).getString("mode"))
        assertEquals(1, packageDef.actions.size)
        assertEquals("", missingFields.providerId)
        assertEquals("", missingFields.agentId)
        assertEquals(emptyList<AgentAction>(), missingFields.actions)
    }

    @Test
    fun actionJsonRoundTrip() {
        val action = sampleAction()

        val parsed = AgentAction.fromJson(action.toJson())

        assertEquals(action.actionId, parsed.actionId)
        assertEquals(action.toolName, parsed.toolName)
        assertEquals(ActionRisk.HIGH, parsed.risk)
        assertEquals(listOf(ExecutionMode.APP_HANDOFF), parsed.executionModes)
        assertEquals(action.toJson(), action.toJsonString())
    }

    @Test
    fun actionFromMapMatchesFlutterStableDefaults() {
        val action = AgentAction.fromMap(
            mapOf(
                "action_id" to "provider.order.create",
                "tool_name" to "app_action_provider_order_create",
                "description" to "Create an order proposal.",
                "parameters" to mapOf("type" to "object"),
                "result_schema" to mapOf("type" to "object"),
            ),
        )
        val missingFields = AgentAction.fromMap(emptyMap<String, Any?>())

        assertEquals("provider.order.create", action.actionId)
        assertEquals("object", JSONObject(action.parametersJson).getString("type"))
        assertEquals(ActionRisk.HIGH, action.risk)
        assertEquals(ConfirmationPolicy.PROVIDER_REQUIRED, action.confirmationPolicy)
        assertEquals(emptyList<String>(), action.executionModes)
        assertEquals(600, action.timeoutSeconds)
        assertEquals("", missingFields.actionId)
        assertEquals("", missingFields.toolName)
    }

    @Test
    fun parseProposalIntent() {
        val proposal = sampleProposal()
        val intent = proposalIntent(proposal)

        val parsed = AgentProvider.parseProposal(intent)

        assertNotNull(parsed)
        assertEquals("request-1", parsed?.requestId)
    }

    @Test
    fun actionProposalJsonRoundTripKeepsSignatureFields() {
        val proposal = sampleProposal(
            hostInstanceId = "host-instance-1",
            signatureAlgorithm = "hmac-sha256-v1",
            signature = "signature-1",
        )

        val parsed = ActionProposal.fromJson(proposal.toJson())

        assertEquals("host-instance-1", parsed.hostInstanceId)
        assertEquals("hmac-sha256-v1", parsed.signatureAlgorithm)
        assertEquals("signature-1", parsed.signature)
        assertEquals(proposal.toJson(), proposal.toJsonString())
    }

    @Test
    fun actionProposalFromMapAndJsonObjectMatchFlutterStableShape() {
        val proposal = ActionProposal.fromMap(
            mapOf(
                "request_id" to "request-2",
                "provider_id" to "provider.test",
                "agent_id" to "provider.agent",
                "action_id" to "provider.order.create",
                "tool_name" to "app_action_provider_order_create",
                "arguments" to mapOf("amount" to 100),
                "created_at" to "2025-12-15T00:00:00Z",
                "expires_at" to "2030-01-01T00:00:00Z",
                "nonce" to "nonce-2",
                "idempotency_key" to "idem-2",
            ),
        )
        val minimalJson = sampleProposal().toJsonObject()
        val missingFields = ActionProposal.fromMap(emptyMap<String, Any?>())

        assertEquals("request-2", proposal.requestId)
        assertEquals(100, JSONObject(proposal.argumentsJson).getInt("amount"))
        assertEquals(ActionRisk.HIGH, proposal.risk)
        assertEquals(ConfirmationPolicy.PROVIDER_REQUIRED, proposal.confirmationPolicy)
        assertFalse(minimalJson.has("host_instance_id"))
        assertFalse(minimalJson.has("signature_algorithm"))
        assertFalse(minimalJson.has("signature"))
        assertEquals("", missingFields.requestId)
        assertEquals("", missingFields.createdAt)
    }

    @Test
    fun parseProposalRejectsUnrelatedIntent() {
        val intent = mock(Intent::class.java)
        `when`(intent.action).thenReturn("other.action")

        assertNull(AgentProvider.parseProposal(intent))
    }

    @Test
    fun resultIntentContainsResultJson() {
        val result = sampleResult()
        val intent = mock(Intent::class.java)
        val resultCaptor = ArgumentCaptor.forClass(String::class.java)
        `when`(intent.setAction(AgentProviderContract.ACTION_RESULT)).thenReturn(intent)
        `when`(
            intent.putExtra(
                org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_RESULT_JSON),
                org.mockito.ArgumentMatchers.anyString(),
            ),
        ).thenReturn(intent)

        AgentProvider.buildResultIntent(result, intent)

        verify(intent).setAction(AgentProviderContract.ACTION_RESULT)
        verify(intent).putExtra(
            org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_RESULT_JSON),
            resultCaptor.capture(),
        )
        assertEquals("request-1", JSONObject(resultCaptor.value).getString("request_id"))
    }

    @Test
    fun actionResultAndErrorFromMapMatchStableDefaults() {
        val result = ActionResult.fromMap(
            mapOf(
                "request_id" to "request-2",
                "status" to ActionResultStatus.FAILED,
                "result" to mapOf("ok" to false),
                "error" to mapOf("code" to "denied", "message" to "Denied"),
                "provider_trace_id" to "trace-2",
                "completed_at" to "2025-12-15T00:02:00Z",
                "signature" to "signature-2",
            ),
        )
        val error = ActionError.fromMap(
            mapOf(
                "code" to "invalid",
                "message" to "Invalid input.",
                "details" to mapOf("field" to "amount"),
            ),
        )
        val missingResultFields = ActionResult.fromMap(emptyMap<String, Any?>())
        val missingErrorFields = ActionError.fromMap(emptyMap<String, Any?>())

        assertEquals("request-2", result.requestId)
        assertEquals(ActionResultStatus.FAILED, result.status)
        assertEquals(false, JSONObject(result.resultJson).getBoolean("ok"))
        assertEquals("denied", result.error?.code)
        assertEquals("trace-2", result.providerTraceId)
        assertEquals("signature-2", result.signature)
        assertEquals(result.toJson(), result.toJsonString())
        assertEquals("invalid", error.code)
        assertEquals("amount", JSONObject(error.detailsJson).getString("field"))
        assertEquals(error.toJson(), error.toJsonString())
        assertEquals("", missingResultFields.requestId)
        assertEquals("", missingResultFields.status)
        assertEquals("", missingResultFields.completedAt)
        assertEquals("", missingErrorFields.code)
        assertEquals("", missingErrorFields.message)
    }

    @Test
    fun installRequestJsonRoundTrip() {
        val request = sampleInstallRequest(
            protocolVersion = 2,
            hostSigningCertSha256 = "host123",
            hostInstanceId = "host-instance-1",
            hostSharedSecret = "secret-1",
            hostBundleId = "host.bundle",
            hostTeamId = "TEAM",
            hostCallbackScheme = "napaxi",
            callbackUrl = "napaxi://provider/install",
            backgroundTriggerSupported = true,
            hostBackgroundTriggerService = "host.app.AgentTriggerIngressService",
        )

        val parsed = AgentInstallRequest.fromJson(request.toJson())

        assertEquals(2, parsed.protocolVersion)
        assertEquals("install-1", parsed.requestId)
        assertEquals("nonce-install", parsed.nonce)
        assertEquals("host.app", parsed.hostPackageName)
        assertEquals("host123", parsed.hostSigningCertSha256)
        assertEquals("host-instance-1", parsed.hostInstanceId)
        assertEquals("secret-1", parsed.hostSharedSecret)
        assertEquals("host.bundle", parsed.hostBundleId)
        assertEquals("TEAM", parsed.hostTeamId)
        assertEquals("napaxi", parsed.hostCallbackScheme)
        assertEquals("napaxi://provider/install", parsed.callbackUrl)
        assertTrue(parsed.backgroundTriggerSupported)
        assertEquals("host.app.AgentTriggerIngressService", parsed.hostBackgroundTriggerService)
        assertEquals(request.toJson(), request.toJsonString())
    }

    @Test
    fun installRequestFromMapAndJsonObjectMatchFlutterStableShape() {
        val fromMap = AgentInstallRequest.fromMap(
            mapOf(
                "protocol_version" to 2,
                "request_id" to "install-2",
                "nonce" to "nonce-2",
                "host_package_name" to "host.app",
                "created_at" to "2025-12-15T00:00:00Z",
                "expires_at" to "2030-01-01T00:00:00Z",
                "host_signing_cert_sha256" to "host123",
                "host_instance_id" to "host-instance-2",
                "host_shared_secret" to "secret-2",
                "host_bundle_id" to "host.bundle",
                "host_team_id" to "TEAM",
                "host_callback_scheme" to "napaxi",
                "callback_url" to "napaxi://provider/install",
            ),
        )
        val minimalJson = sampleInstallRequest().toJsonObject()

        assertEquals("install-2", fromMap.requestId)
        assertEquals("host.bundle", fromMap.hostBundleId)
        assertEquals("TEAM", fromMap.hostTeamId)
        assertEquals("napaxi", fromMap.hostCallbackScheme)
        assertEquals("napaxi://provider/install", fromMap.callbackUrl)
        assertFalse(minimalJson.has("host_bundle_id"))
        assertFalse(minimalJson.has("host_team_id"))
        assertFalse(minimalJson.has("host_callback_scheme"))
        assertFalse(minimalJson.has("callback_url"))
        assertFalse(minimalJson.has("background_trigger_supported"))
        assertFalse(minimalJson.has("host_background_trigger_service"))
    }

    @Test
    fun installResultJsonRoundTrip() {
        val result = AgentInstallResult(
            status = AgentInstallStatus.SUCCEEDED,
            requestId = "install-1",
            nonce = "nonce-install",
            packageJson = samplePackage().toJson(),
            completedAt = "2025-12-15T00:01:00Z",
        )

        val parsed = AgentInstallResult.fromJson(result.toJson())

        assertEquals(AgentInstallStatus.SUCCEEDED, parsed.status)
        assertEquals("install-1", parsed.requestId)
        assertEquals("nonce-install", parsed.nonce)
        assertNotNull(parsed.packageJson)
        assertEquals(result.toJson(), result.toJsonString())
    }

    @Test
    fun installResultFromMapMatchesFlutterStableDefaults() {
        val result = AgentInstallResult.fromMap(
            mapOf(
                "status" to AgentInstallStatus.SUCCEEDED,
                "request_id" to "install-2",
                "nonce" to "nonce-2",
                "package" to mapOf(
                    "provider_id" to "provider.test",
                    "agent_id" to "provider.agent",
                    "display_name" to "Provider Agent",
                    "actions" to emptyList<Map<String, String>>(),
                ),
                "completed_at" to "2025-12-15T00:01:00Z",
            ),
        )
        val missingFields = AgentInstallResult.fromMap(emptyMap<String, Any?>())

        assertEquals(AgentInstallStatus.SUCCEEDED, result.status)
        assertEquals("install-2", result.requestId)
        assertEquals("provider.test", JSONObject(result.packageJson!!).getString("provider_id"))
        assertEquals("", missingFields.status)
        assertEquals("", missingFields.requestId)
        assertEquals("", missingFields.nonce)
        assertEquals("", missingFields.completedAt)
    }

    @Test
    fun triggerRequestJsonRoundTrip() {
        val trigger = sampleTriggerRequest(signature = "signature-1")

        val parsed = AgentTriggerRequest.fromJson(trigger.toJson())

        assertEquals("trigger-1", parsed.requestId)
        assertEquals("provider.test", parsed.providerId)
        assertEquals("provider.agent", parsed.agentId)
        assertEquals("virtual_sensor", parsed.source)
        assertEquals("hmac-sha256-v1", parsed.signatureAlgorithm)
        assertEquals("signature-1", parsed.signature)
        assertEquals(trigger.toJson(), trigger.toJsonString())
    }

    @Test
    fun triggerRequestFromMapAndJsonObjectMatchFlutterStableShape() {
        val fromMap = AgentTriggerRequest.fromMap(
            mapOf(
                "protocol_version" to 2,
                "request_id" to "trigger-2",
                "provider_id" to "provider.test",
                "agent_id" to "provider.agent",
                "message" to "Wake up",
                "source" to "sensor",
                "event_type" to "motion",
                "payload" to mapOf("room" to "office"),
                "created_at" to "2025-12-15T00:00:00Z",
                "expires_at" to "2030-01-01T00:00:00Z",
                "nonce" to "nonce-2",
                "idempotency_key" to "idem-2",
                "host_instance_id" to "host-instance-2",
                "signature_algorithm" to "hmac-sha256-v1",
                "signature" to "signature-2",
            ),
        )
        val minimalJson = sampleTriggerRequest().toJsonObject()

        assertEquals("trigger-2", fromMap.requestId)
        assertEquals("office", JSONObject(fromMap.payloadJson).getString("room"))
        assertEquals("host-instance-2", fromMap.hostInstanceId)
        assertEquals("hmac-sha256-v1", fromMap.signatureAlgorithm)
        assertEquals("signature-2", fromMap.signature)
        assertFalse(minimalJson.has("host_instance_id"))
        assertFalse(minimalJson.has("signature_algorithm"))
        assertFalse(minimalJson.has("signature"))
    }

    @Test
    fun buildHostTriggerIntentContainsSignedRequest() {
        val binding = TrustedHostBinding(
            hostPackageName = "host.app",
            hostSigningCertSha256 = "host123",
            hostInstanceId = "host-instance-1",
            hostSharedSecret = "secret-1",
            installedAt = "2026-05-27T00:00:00Z",
            backgroundTriggerSupported = true,
            hostBackgroundTriggerService = "host.app.AgentTriggerIngressService",
        )
        val signed = AgentProviderSecurity.signTriggerRequest(
            sampleTriggerRequest(),
            binding,
        )
        val intent = mock(Intent::class.java)
        val triggerCaptor = ArgumentCaptor.forClass(String::class.java)
        `when`(intent.setAction(AgentProviderContract.ACTION_HOST_TRIGGER_AGENT)).thenReturn(intent)
        `when`(intent.setPackage("host.app")).thenReturn(intent)
        `when`(
            intent.putExtra(
                org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_TRIGGER_REQUEST_JSON),
                org.mockito.ArgumentMatchers.anyString(),
            ),
        ).thenReturn(intent)

        AgentProvider.buildHostTriggerIntent(signed, binding.hostPackageName, intent)

        verify(intent).setAction(AgentProviderContract.ACTION_HOST_TRIGGER_AGENT)
        verify(intent).setPackage("host.app")
        verify(intent).putExtra(
            org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_TRIGGER_REQUEST_JSON),
            triggerCaptor.capture(),
        )
        val parsed = AgentTriggerRequest.fromJson(
            triggerCaptor.value,
        )
        assertEquals("host-instance-1", parsed.hostInstanceId)
        assertEquals("hmac-sha256-v1", parsed.signatureAlgorithm)
        assertFalse(parsed.signature.isNullOrBlank())
    }

    @Test
    fun triggerSubmitResultJsonRoundTrip() {
        val result = AgentTriggerSubmitResult(
            status = AgentTriggerSubmitResult.QUEUED,
            requestId = "trigger-1",
            error = ActionError("queued", "Queued for runtime resume."),
        )

        val parsed = AgentTriggerSubmitResult.fromJson(result.toJson())

        assertEquals(AgentTriggerSubmitResult.QUEUED, parsed.status)
        assertEquals("trigger-1", parsed.requestId)
        assertEquals("queued", parsed.error?.code)
        assertEquals(result.toJson(), result.toJsonString())
    }

    @Test
    fun triggerSubmitResultFromMapMatchesStableDefaults() {
        val result = AgentTriggerSubmitResult.fromMap(
            mapOf(
                "status" to AgentTriggerSubmitResult.REJECTED,
                "request_id" to "trigger-2",
                "error" to mapOf("code" to "invalid", "message" to "Invalid trigger."),
            ),
        )
        val missingFields = AgentTriggerSubmitResult.fromMap(emptyMap<String, Any?>())

        assertEquals(AgentTriggerSubmitResult.REJECTED, result.status)
        assertEquals("trigger-2", result.requestId)
        assertEquals("invalid", result.error?.code)
        assertEquals("", missingFields.status)
        assertEquals("", missingFields.requestId)
    }

    @Test
    fun submitBackgroundTriggerWithoutServiceBindingIsUnsupported() {
        val binding = TrustedHostBinding(
            hostPackageName = "host.app",
            hostSigningCertSha256 = "host123",
            hostInstanceId = "host-instance-1",
            hostSharedSecret = "secret-1",
            installedAt = "2026-05-27T00:00:00Z",
        )

        val result = AgentProvider.submitBackgroundTrigger(
            mock(android.content.Context::class.java),
            sampleTriggerRequest(),
            binding,
        )

        assertEquals(AgentTriggerSubmitResult.UNSUPPORTED, result.status)
        assertEquals("trigger-1", result.requestId)
    }

    @Test
    fun parseInstallRequestIntent() {
        val request = sampleInstallRequest()
        val intent = installRequestIntent(request)

        val parsed = AgentProvider.parseInstallRequest(intent)

        assertNotNull(parsed)
        assertEquals("install-1", parsed?.requestId)
    }

    @Test
    fun buildInstallResultIntentEchoesRequestAndNonce() {
        val request = sampleInstallRequest()
        val intent = mock(Intent::class.java)
        val resultCaptor = ArgumentCaptor.forClass(String::class.java)
        `when`(
            intent.putExtra(
                org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_INSTALL_RESULT_JSON),
                org.mockito.ArgumentMatchers.anyString(),
            ),
        ).thenReturn(intent)
        `when`(
            intent.putExtra(
                org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_PACKAGE_JSON),
                org.mockito.ArgumentMatchers.anyString(),
            ),
        ).thenReturn(intent)

        AgentProvider.buildInstallResultIntent(samplePackage(), request, intent)

        verify(intent).putExtra(
            org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_INSTALL_RESULT_JSON),
            resultCaptor.capture(),
        )
        val result = JSONObject(resultCaptor.value)
        assertEquals("install-1", result.getString("request_id"))
        assertEquals("nonce-install", result.getString("nonce"))
        assertEquals(AgentInstallStatus.SUCCEEDED, result.getString("status"))
        assertEquals("provider.test", result.getJSONObject("package").getString("provider_id"))
    }

    @Test
    fun buildInstallFailureIntentEchoesRequestAndNonce() {
        val request = sampleInstallRequest()
        val intent = mock(Intent::class.java)
        val resultCaptor = ArgumentCaptor.forClass(String::class.java)
        `when`(
            intent.putExtra(
                org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_INSTALL_RESULT_JSON),
                org.mockito.ArgumentMatchers.anyString(),
            ),
        ).thenReturn(intent)

        AgentProvider.buildInstallFailureIntent(request, "denied", "Denied", intent)

        verify(intent).putExtra(
            org.mockito.ArgumentMatchers.eq(AgentProviderContract.EXTRA_INSTALL_RESULT_JSON),
            resultCaptor.capture(),
        )
        val result = JSONObject(resultCaptor.value)
        assertEquals("install-1", result.getString("request_id"))
        assertEquals("nonce-install", result.getString("nonce"))
        assertEquals(AgentInstallStatus.FAILED, result.getString("status"))
        assertEquals("denied", result.getJSONObject("error").getString("code"))
    }

    @Test
    fun validateProposalAcceptsMatchingUnexpiredProposal() {
        val result = AgentProvider.validateProposal(
            sampleProposal(),
            samplePackage(),
            nowMillis = 1_765_750_000_000,
        )

        assertTrue(result.isValid)
    }

    @Test
    fun validateProposalRejectsExpiredProposal() {
        val result = AgentProvider.validateProposal(
            sampleProposal(expiresAt = "2024-01-01T00:00:00Z"),
            samplePackage(),
            nowMillis = 1_765_750_000_000,
        )

        assertFalse(result.isValid)
        assertEquals("expired", result.code)
    }

    @Test
    fun validateProposalRejectsProviderMismatch() {
        val result = AgentProvider.validateProposal(
            sampleProposal(providerId = "provider.other"),
            samplePackage(),
            nowMillis = 1_765_750_000_000,
        )

        assertFalse(result.isValid)
        assertEquals("provider_mismatch", result.code)
    }

    @Test
    fun validateProposalRejectsAgentMismatch() {
        val result = AgentProvider.validateProposal(
            sampleProposal(agentId = "other.agent"),
            samplePackage(),
            nowMillis = 1_765_750_000_000,
        )

        assertFalse(result.isValid)
        assertEquals("agent_mismatch", result.code)
    }

    @Test
    fun validateProposalRejectsActionMismatch() {
        val result = AgentProvider.validateProposal(
            sampleProposal(actionId = "provider.order.cancel"),
            samplePackage(),
            nowMillis = 1_765_750_000_000,
        )

        assertFalse(result.isValid)
        assertEquals("action_not_found", result.code)
    }

    @Test
    fun validateProposalRejectsMissingNonce() {
        val result = AgentProvider.validateProposal(
            sampleProposal(nonce = ""),
            samplePackage(),
            nowMillis = 1_765_750_000_000,
        )

        assertFalse(result.isValid)
        assertEquals("missing_nonce", result.code)
    }

    @Test
    fun validateProposalRejectsMissingIdempotencyKey() {
        val result = AgentProvider.validateProposal(
            sampleProposal(idempotencyKey = ""),
            samplePackage(),
            nowMillis = 1_765_750_000_000,
        )

        assertFalse(result.isValid)
        assertEquals("missing_idempotency_key", result.code)
    }

    private fun samplePackage(): AgentPackage =
        AgentPackage(
            providerId = "provider.test",
            agentId = "provider.agent",
            displayName = "Provider Agent",
            description = "Agent backed by a provider app.",
            systemPrompt = "Handle provider actions.",
            actions = listOf(sampleAction()),
        )

    private fun sampleAction(): AgentAction =
        AgentAction(
            actionId = "provider.order.create",
            toolName = "app_action_provider_order_create",
            description = "Create an order proposal.",
            parametersJson = """{"type":"object","properties":{}}""",
            resultSchemaJson = """{"type":"object"}""",
        )

    private fun sampleProposal(
        providerId: String = "provider.test",
        agentId: String = "provider.agent",
        actionId: String = "provider.order.create",
        nonce: String = "nonce-1",
        idempotencyKey: String = "idem-1",
        expiresAt: String = "2030-01-01T00:00:00Z",
        hostInstanceId: String = "",
        signatureAlgorithm: String = "",
        signature: String? = null,
    ): ActionProposal =
        ActionProposal(
            requestId = "request-1",
            providerId = providerId,
            agentId = agentId,
            actionId = actionId,
            toolName = "app_action_provider_order_create",
            argumentsJson = """{"amount":100}""",
            userIntentSummary = "Create an order.",
            createdAt = "2025-12-15T00:00:00Z",
            expiresAt = expiresAt,
            nonce = nonce,
            idempotencyKey = idempotencyKey,
            hostInstanceId = hostInstanceId,
            signatureAlgorithm = signatureAlgorithm,
            signature = signature,
        )

    private fun proposalIntent(proposal: ActionProposal): Intent {
        val intent = mock(Intent::class.java)
        `when`(intent.action).thenReturn(AgentProviderContract.ACTION_HANDLE_PROPOSAL)
        `when`(intent.hasExtra(AgentProviderContract.EXTRA_PROPOSAL_JSON)).thenReturn(true)
        `when`(intent.getStringExtra(AgentProviderContract.EXTRA_PROPOSAL_JSON))
            .thenReturn(proposal.toJson())
        return intent
    }

    private fun sampleInstallRequest(
        protocolVersion: Int = 1,
        hostSigningCertSha256: String = "",
        hostInstanceId: String = "",
        hostSharedSecret: String = "",
        hostBundleId: String = "",
        hostTeamId: String = "",
        hostCallbackScheme: String = "",
        callbackUrl: String = "",
        backgroundTriggerSupported: Boolean = false,
        hostBackgroundTriggerService: String = "",
    ): AgentInstallRequest =
        AgentInstallRequest(
            protocolVersion = protocolVersion,
            requestId = "install-1",
            nonce = "nonce-install",
            hostPackageName = "host.app",
            createdAt = "2025-12-15T00:00:00Z",
            expiresAt = "2030-01-01T00:00:00Z",
            hostSigningCertSha256 = hostSigningCertSha256,
            hostInstanceId = hostInstanceId,
            hostSharedSecret = hostSharedSecret,
            hostBundleId = hostBundleId,
            hostTeamId = hostTeamId,
            hostCallbackScheme = hostCallbackScheme,
            callbackUrl = callbackUrl,
            backgroundTriggerSupported = backgroundTriggerSupported,
            hostBackgroundTriggerService = hostBackgroundTriggerService,
        )

    private fun installRequestIntent(request: AgentInstallRequest): Intent {
        val intent = mock(Intent::class.java)
        `when`(intent.action).thenReturn(AgentProviderContract.ACTION_INSTALL_AGENT)
        `when`(intent.hasExtra(AgentProviderContract.EXTRA_INSTALL_REQUEST_JSON)).thenReturn(true)
        `when`(intent.getStringExtra(AgentProviderContract.EXTRA_INSTALL_REQUEST_JSON))
            .thenReturn(request.toJson())
        return intent
    }

    private fun sampleTriggerRequest(signature: String? = null): AgentTriggerRequest =
        AgentTriggerRequest(
            requestId = "trigger-1",
            providerId = "provider.test",
            agentId = "provider.agent",
            message = "Desk button pressed.",
            source = "virtual_sensor",
            eventType = "button_pressed",
            payloadJson = """{"button":"desk"}""",
            createdAt = "2026-05-27T00:00:00Z",
            expiresAt = "2030-01-01T00:00:00Z",
            nonce = "nonce-trigger",
            idempotencyKey = "trigger-1",
            hostInstanceId = if (signature == null) "" else "host-instance-1",
            signatureAlgorithm = if (signature == null) "" else "hmac-sha256-v1",
            signature = signature,
        )

    private fun sampleResult(): ActionResult =
        ActionResult(
            requestId = "request-1",
            status = ActionResultStatus.SUCCEEDED,
            resultJson = """{"order_id":"order-1"}""",
            completedAt = "2025-12-15T00:01:00Z",
            providerTraceId = "trace-1",
        )
}
