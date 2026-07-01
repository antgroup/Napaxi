package com.napaxi.android

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class AgentProviderHostProtocolTest {
    @Test
    fun providerProtocolAliasesExposeSdkModelsFromAndroidPackage() {
        val action = AgentAction(
            actionId = "pay",
            toolName = "app_action_pay",
            description = "Send payment",
            parametersJson = """{"type":"object"}""",
        )
        val packageDef = AgentPackage(
            providerId = "provider.app",
            agentId = "wallet",
            displayName = "Wallet",
            description = "Wallet provider",
            systemPrompt = "Handle wallet actions",
            actions = listOf(action),
        )
        val proposal = ActionProposal(
            requestId = "request-1",
            providerId = "provider.app",
            agentId = "wallet",
            actionId = "pay",
            toolName = "app_action_pay",
            createdAt = "2026-05-30T00:00:00Z",
            expiresAt = "2026-05-30T00:10:00Z",
            nonce = "nonce",
            idempotencyKey = "idem",
        )
        val result = ProviderActionResult(
            requestId = proposal.requestId,
            status = "succeeded",
            completedAt = "2026-05-30T00:01:00Z",
        )

        assertEquals("provider.app", AgentPackage.fromJson(packageDef.toJson()).providerId)
        assertEquals("app_action_pay", ActionProposal.fromJson(proposal.toJson()).toolName)
        assertEquals("succeeded", ProviderActionResult.fromJson(result.toJson()).status)
        assertEquals(true, ProviderProposalValidationResult.success().isValid)
    }

    @Test
    fun installResultValidationRequiresMatchingFreshSuccessfulEnvelope() {
        val request = installRequest()
        val result = AgentInstallResult(
            status = AgentInstallStatus.SUCCEEDED,
            requestId = request.requestId,
            nonce = request.nonce,
            packageJson = providerPackageJson(),
            completedAt = "2026-05-30T00:01:00Z",
        )

        AgentProviderHostApi.validateInstallResultEnvelope(
            result = result,
            request = request,
            now = Instant.parse("2026-05-30T00:02:00Z"),
        )

        val fromMap = AgentInstallResult.fromMap(
            mapOf(
                "status" to AgentInstallStatus.SUCCEEDED,
                "request_id" to request.requestId,
                "nonce" to request.nonce,
                "package" to mapOf(
                    "provider_id" to "provider.app",
                    "agent_id" to "calendar_agent",
                    "display_name" to "Calendar Agent",
                    "actions" to emptyList<Map<String, String>>(),
                ),
                "completed_at" to "2026-05-30T00:01:00Z",
            ),
        )
        val missingFields = AgentInstallResult.fromMap(emptyMap<String, Any?>())
        assertEquals(request.requestId, fromMap.requestId)
        assertEquals("provider.app", JSONObject(fromMap.packageJson!!).getString("provider_id"))
        assertEquals("", missingFields.status)
        assertEquals("", missingFields.requestId)

        assertThrows(IllegalStateException::class.java) {
            AgentProviderHostApi.validateInstallResultEnvelope(
                result = result.copy(nonce = "wrong"),
                request = request,
                now = Instant.parse("2026-05-30T00:02:00Z"),
            )
        }
        assertThrows(IllegalStateException::class.java) {
            AgentProviderHostApi.validateInstallResultEnvelope(
                result = result,
                request = request,
                now = Instant.parse("2026-05-30T00:20:00Z"),
            )
        }
    }

    @Test
    fun pendingProviderInstallPreservesCustomRequestCode() {
        val request = installRequest()
        val descriptor = AgentProviderDescriptor(
            packageName = "provider.app",
            activityName = "provider.app.ActionActivity",
            installActivityName = "provider.app.InstallActivity",
            displayName = "Provider",
        )
        val defaultPending = PendingAgentProviderInstall(descriptor, request)
        val customPending = PendingAgentProviderInstall(descriptor, request, requestCode = 7319)

        assertEquals(AgentProviderHostApi.REQUEST_INSTALL_AGENT, defaultPending.requestCode)
        assertEquals(7319, customPending.requestCode)
    }

    @Test
    fun agentProviderDescriptorRoundTripsFlutterStableJsonShape() {
        val descriptor = AgentProviderDescriptor(
            platform = "ios",
            packageName = "provider.app",
            activityName = "provider.app.ActionActivity",
            installActivityName = "provider.app.InstallActivity",
            displayName = "Provider",
            signingCertSha256 = "abc",
            installUrl = "napaxi-provider://install",
            actionUrl = "napaxi-provider://action",
            universalLinkDomain = "example.test",
            iosBundleId = "provider.ios",
            iosTeamId = "TEAM",
        )
        val stableJson = JSONObject(descriptor.toJson())
        val aliasedJson = descriptor.toJsonObject()
        val fromCamel = AgentProviderDescriptor.fromJson(stableJson.toString())
        val fromSnake = AgentProviderDescriptor.fromJsonObject(
            JSONObject()
                .put("platform", "android")
                .put("package_name", "provider.app")
                .put("activity_name", "provider.app.ActionActivity")
                .put("install_activity_name", "provider.app.InstallActivity")
                .put("display_name", "Provider")
                .put("signing_cert_sha256", "abc"),
        )
        val fromMap = AgentProviderDescriptor.fromMap(
            mapOf(
                "packageName" to "provider.map",
                "activityName" to "provider.map.ActionActivity",
                "label" to "Provider Map",
            ),
        )

        assertEquals("provider.app", stableJson.getString("packageName"))
        assertEquals("provider.app.InstallActivity", stableJson.getString("installActivityName"))
        assertEquals("provider.app.ActionActivity", stableJson.getString("activityName"))
        assertEquals("Provider", stableJson.getString("label"))
        assertEquals(false, stableJson.has("package_name"))
        assertEquals(false, stableJson.has("display_name"))
        assertEquals("provider.app", aliasedJson.getString("package_name"))
        assertEquals("Provider", aliasedJson.getString("display_name"))
        assertEquals("ios", fromCamel.platform)
        assertEquals("napaxi-provider://action", fromCamel.actionUrl)
        assertEquals("provider.app.InstallActivity", fromSnake.installActivityName)
        assertEquals("Provider", fromSnake.displayName)
        assertEquals("provider.map", fromMap.packageName)
        assertEquals("provider.map.ActionActivity", fromMap.installActivityName)
        assertEquals("Provider Map", fromMap.label)
    }

    @Test
    fun triggerValidationRequiresTrustedBindingSignatureAndReplayProtection() {
        val binding = AgentAppInstallBinding(
            platform = "android",
            appPackageName = "provider.app",
            activityName = "provider.app.ActionActivity",
            signingCertSha256 = "provider-cert",
            installedAt = "2026-05-30T00:00:00Z",
            installRequestId = "install-1",
            protocolVersion = 2,
            hostPackageName = "host.app",
            hostSigningCertSha256 = "host-cert",
            hostInstanceId = "host-instance-1",
            hostSharedSecret = "secret-1",
            backgroundTriggerSupported = true,
            hostBackgroundTriggerService = "host.AgentTriggerIngressService",
        )
        val packageDef = AgentAppPackage(
            JSONObject(providerPackageJson())
                .put("install_binding", binding.toJsonObject())
                .toString(),
        )
        val signed = AgentProviderHostApi.signTriggerRequest(
            triggerRequest(),
            binding,
        )

        AgentProviderHostApi.validateTriggerRequest(
            request = signed,
            packageDef = packageDef,
            now = Instant.parse("2026-05-30T00:02:00Z"),
        )

        assertEquals(AgentProviderHostApi.SIGNATURE_ALGORITHM_HMAC_SHA256_V1, signed.signatureAlgorithm)
        assertFalse(signed.signature.isNullOrBlank())
        assertTrue(AgentProviderHostApi.triggerSignaturePayload(signed).contains("payload_sha256="))
        val fromMap = AgentTriggerRequest.fromMap(
            mapOf(
                "protocol_version" to 2,
                "request_id" to "trigger-from-map",
                "provider_id" to "provider.app",
                "agent_id" to "calendar_agent",
                "message" to "Summarize my day",
                "payload" to mapOf("day" to "today"),
                "created_at" to "2026-05-30T00:00:00Z",
                "expires_at" to "2026-05-30T00:10:00Z",
                "nonce" to "nonce-trigger-map",
                "idempotency_key" to "idem-trigger-map",
            ),
        )
        val minimalJson = JSONObject(fromMap.toJsonString())
        assertEquals("trigger-from-map", fromMap.requestId)
        assertEquals("today", JSONObject(fromMap.payloadJson).getString("day"))
        assertFalse(minimalJson.has("host_instance_id"))
        assertFalse(minimalJson.has("signature_algorithm"))
        assertThrows(IllegalStateException::class.java) {
            AgentProviderHostApi.validateTriggerRequest(
                request = signed.copy(signature = "wrong"),
                packageDef = packageDef,
                now = Instant.parse("2026-05-30T00:02:00Z"),
            )
        }
        assertThrows(IllegalStateException::class.java) {
            AgentProviderHostApi.validateTriggerRequest(
                request = signed,
                packageDef = packageDef,
                isConsumed = true,
                now = Instant.parse("2026-05-30T00:02:00Z"),
            )
        }
        assertThrows(IllegalStateException::class.java) {
            AgentProviderHostApi.validateTriggerRequest(
                request = signed,
                packageDef = packageDef,
                now = Instant.parse("2026-05-30T00:20:00Z"),
            )
        }
    }

    @Test
    fun triggerIngressHelpersMatchProviderProtocolShape() {
        val triggerJson = triggerRequest().toJson()
        val response = JSONObject(
            AgentTriggerIngressService.responseJson(
                status = AgentTriggerSubmitResult.REJECTED,
                requestId = "trigger-1",
                code = "invalid_json",
                message = "Trigger JSON is invalid.",
            ),
        )

        assertEquals("trigger-1", AgentTriggerStore.requestId(triggerJson))
        assertEquals("", AgentTriggerStore.requestId("{not json"))
        assertEquals(AgentTriggerSubmitResult.REJECTED, response.getString("status"))
        assertEquals("trigger-1", response.getString("request_id"))
        assertEquals("invalid_json", response.getJSONObject("error").getString("code"))
        assertEquals(
            "Trigger JSON is invalid.",
            response.getJSONObject("error").getString("message"),
        )

        var delivered = false
        AgentTriggerIngressService.setDispatchCallback { json ->
            delivered = AgentTriggerStore.requestId(json) == "trigger-1"
            delivered
        }
        assertTrue(AgentTriggerIngressService.dispatchToHost(triggerJson))
        assertTrue(delivered)
        AgentTriggerIngressService.setDispatchCallback(null)
        assertFalse(AgentTriggerIngressService.dispatchToHost(triggerJson))
    }

    @Test
    fun triggerIngressRejectsUntrustedEnvelopeBeforeQueueing() {
        val binding = installBinding()
        val packageDef = AgentAppPackage(
            JSONObject(providerPackageJson())
                .put("install_binding", binding.toJsonObject())
                .toString(),
        )
        val signed = AgentProviderHostApi.signTriggerRequest(triggerRequest(), binding)

        assertEquals(
            null,
            AgentTriggerIngressService.validateIngressTriggerEnvelope(
                request = signed,
                packageDef = packageDef,
                now = Instant.parse("2026-05-30T00:02:00Z"),
            ),
        )
        assertEquals(
            "replayed",
            AgentTriggerIngressService.validateIngressTriggerEnvelope(
                request = signed,
                packageDef = packageDef,
                triggerAlreadyRecorded = true,
                now = Instant.parse("2026-05-30T00:02:00Z"),
            )?.first,
        )
        assertEquals(
            "signature_invalid",
            AgentTriggerIngressService.validateIngressTriggerEnvelope(
                request = signed.copy(signature = "wrong"),
                packageDef = packageDef,
                now = Instant.parse("2026-05-30T00:02:00Z"),
            )?.first,
        )
        assertEquals(
            "unsupported_platform",
            AgentTriggerIngressService.validateIngressTriggerEnvelope(
                request = signed,
                packageDef = AgentAppPackage(
                    JSONObject(providerPackageJson())
                        .put("install_binding", binding.copy(platform = "ios").toJsonObject())
                        .toString(),
                ),
                now = Instant.parse("2026-05-30T00:02:00Z"),
            )?.first,
        )
    }

    @Test
    fun triggerIngressRejectsCallerPackageOrSignatureMismatch() {
        val binding = installBinding()

        assertEquals(
            null,
            AgentTriggerIngressService.validateIngressCaller(
                callerPackages = setOf("provider.app"),
                currentSigningCertSha256 = "provider-cert",
                binding = binding,
            ),
        )
        assertEquals(
            "caller_mismatch",
            AgentTriggerIngressService.validateIngressCaller(
                callerPackages = setOf("other.provider"),
                currentSigningCertSha256 = "provider-cert",
                binding = binding,
            )?.first,
        )
        assertEquals(
            "caller_signature_mismatch",
            AgentTriggerIngressService.validateIngressCaller(
                callerPackages = setOf("provider.app"),
                currentSigningCertSha256 = "changed-cert",
                binding = binding,
            )?.first,
        )
    }

    @Test
    fun trustedProviderActionIntentUsesInstallBindingAndHidesHostSecret() {
        val binding = installBinding()
        val packageDef = AgentAppPackage(
            JSONObject(providerPackageJson())
                .put("install_binding", binding.toJsonObject())
                .toString(),
        )
        val proposal = actionProposal()

        val handoff = AgentProviderHostApi.validateTrustedActionHandoff(
            packageDef = packageDef,
            proposal = proposal,
            currentSigningCertSha256 = "provider-cert",
        )

        assertEquals("provider.app", handoff.first.appPackageName)
        assertEquals("provider.app.ActionActivity", handoff.first.activityName)
        assertEquals("summarize", handoff.second.actionId)
        val providerPackage = AgentProviderHostApi.sanitizePackageForProvider(packageDef)
        assertEquals("provider.app", providerPackage.getString("provider_id"))
        assertFalse(providerPackage.getJSONObject("install_binding").has("host_shared_secret"))

        assertThrows(IllegalArgumentException::class.java) {
            AgentProviderHostApi.validateTrustedActionHandoff(
                packageDef = packageDef,
                proposal = proposal,
                currentSigningCertSha256 = "changed-cert",
            )
        }
    }

    @Test
    fun androidProviderActionExecutorBuildsProtocolFailureResult() {
        val failed = JSONObject(
            AndroidAgentProviderActionExecutor.failedActionResult(
                requestId = "proposal-1",
                message = "Provider action was canceled",
            ).rawJson,
        )

        assertEquals("proposal-1", failed.getString("request_id"))
        assertEquals("failed", failed.getString("status"))
        assertEquals("provider_action_failed", failed.getJSONObject("error").getString("code"))
        assertEquals("Provider action was canceled", failed.getJSONObject("error").getString("message"))
        assertTrue(failed.has("completed_at"))
    }

    @Test
    fun pendingProviderInstallDescriptorUsesDiscoveredAndroidActivityWhenLaunchIntentIsIncomplete() {
        val pending = AgentProviderDescriptor(
            packageName = "provider.app",
            activityName = "",
            installActivityName = "",
            displayName = "Provider",
        )
        val discovered = AgentProviderDescriptor(
            packageName = "provider.app",
            activityName = "provider.app.ActionActivity",
            installActivityName = "provider.app.InstallActivity",
            displayName = "Discovered Provider",
            signingCertSha256 = "provider-cert",
        )

        val resolved = AgentProviderHostApi.resolveProviderInstallDescriptor(pending, listOf(discovered))

        assertEquals("provider.app.ActionActivity", resolved.activityName)
        assertEquals("provider.app.InstallActivity", resolved.installActivityName)
        assertEquals("Discovered Provider", resolved.displayName)
        assertEquals("provider-cert", resolved.signingCertSha256)
    }

    private fun installRequest(): AgentInstallRequest =
        AgentInstallRequest(
            protocolVersion = 2,
            requestId = "install-1",
            nonce = "nonce-install",
            hostPackageName = "host.app",
            createdAt = "2026-05-30T00:00:00Z",
            expiresAt = "2026-05-30T00:10:00Z",
            hostSigningCertSha256 = "host-cert",
            hostInstanceId = "host-instance-1",
            hostSharedSecret = "secret-1",
            backgroundTriggerSupported = true,
            hostBackgroundTriggerService = "host.AgentTriggerIngressService",
        )

    private fun triggerRequest(): AgentTriggerRequest =
        AgentTriggerRequest(
            protocolVersion = 2,
            requestId = "trigger-1",
            providerId = "provider.app",
            agentId = "calendar_agent",
            message = "Summarize my day",
            source = "calendar",
            eventType = "daily",
            payloadJson = """{"z":1,"a":["x"]}""",
            createdAt = "2026-05-30T00:00:00Z",
            expiresAt = "2026-05-30T00:10:00Z",
            nonce = "nonce-trigger",
            idempotencyKey = "idem-trigger",
        )

    private fun actionProposal(): AgentAppActionProposal =
        AgentAppActionProposal(
            """
            {
              "request_id":"proposal-1",
              "provider_id":"provider.app",
              "agent_id":"calendar_agent",
              "action_id":"summarize",
              "tool_name":"calendar.summarize",
              "arguments":{"day":"today"},
              "created_at":"2026-05-30T00:00:00Z",
              "expires_at":"2030-01-01T00:00:00Z",
              "nonce":"nonce-proposal",
              "idempotency_key":"idem-proposal"
            }
            """.trimIndent(),
        )

    private fun installBinding(): AgentAppInstallBinding =
        AgentAppInstallBinding(
            platform = "android",
            appPackageName = "provider.app",
            activityName = "provider.app.ActionActivity",
            signingCertSha256 = "provider-cert",
            installedAt = "2026-05-30T00:00:00Z",
            installRequestId = "install-1",
            protocolVersion = 2,
            hostPackageName = "host.app",
            hostSigningCertSha256 = "host-cert",
            hostInstanceId = "host-instance-1",
            hostSharedSecret = "secret-1",
            backgroundTriggerSupported = true,
            hostBackgroundTriggerService = "host.AgentTriggerIngressService",
        )

    private fun providerPackageJson(): String =
        """
        {
          "provider_id":"provider.app",
          "agent_id":"calendar_agent",
          "display_name":"Calendar Agent",
          "description":"Calendar helper",
          "system_prompt":"Use calendar actions",
          "actions":[{
            "action_id":"summarize",
            "tool_name":"calendar.summarize",
            "description":"Summarize calendar",
            "parameters":{"type":"object"},
            "result_schema":{"type":"object"},
            "risk":"low",
            "confirmation_policy":"provider_required",
            "execution_modes":["app_handoff"],
            "timeout_seconds":60
          }],
          "handoff":{"activityName":"provider.app.ActionActivity"},
          "result":{}
        }
        """.trimIndent()
}
