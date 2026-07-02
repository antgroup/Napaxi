package com.napaxi.android

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ModelsTest {
    @Test
    fun llmConfigRoundTripsCoreJsonShape() {
        val config = LlmConfig(
            provider = "openai_compatible",
            apiKey = "test-key",
            baseUrl = "https://example.test/v1",
            model = "test-model",
            systemPrompt = "Home agent",
            responseLanguage = "zh",
            maxTokens = 1024,
            maxToolIterations = 8,
            extraHeaders = "X-Test:1",
            userTimezone = "Asia/Shanghai",
            allowedModels = listOf(mapOf("id" to "fast", "label" to "Fast")),
            imageModel = "image-gen",
            imageAnalysisModel = "vision-model",
            imageBase64UrlFormat = "data_url",
            videoModel = "video-model",
            audioModel = "audio-model",
            capabilityConfigs = mapOf(
                "imageAnalysis" to LlmCapabilityConfig(
                    provider = "openai",
                    apiKey = "vision-key",
                    model = "vision-model",
                    baseUrl = "https://vision.test/v1",
                    maxTokens = 512,
                    extraHeaders = "X-Vision:1",
                    imageBase64UrlFormat = "raw",
                ),
            ),
            scenePromptConfig = ScenePromptConfig(
                enabled = true,
                hostPolicies = mapOf("location" to "ask"),
            ),
            contextEngine = ContextEngineConfig(
                enabled = true,
                engine = "compressor",
                triggerRatio = 0.75,
                targetRatio = 0.40,
                protectHeadMessages = 3,
                protectTailMessages = 10,
                contextWindowTokens = 16000,
                nativeContextWindowTokens = 1000000,
                providerContextWindowTokens = 128000,
                responseReserveTokens = 2000,
                compactionStrategy = "llm_summary",
                compactionModel = "fast-summary",
                compactionTimeoutMs = 45000,
                preCompactionMemoryFlush = true,
            ),
        )

        val parsed = LlmConfig.fromJson(config.toJson())
        val parsedFromObject = LlmConfig.fromJsonObject(config.toJsonObject())
        val parsedFromMap = LlmConfig.fromMap(
            mapOf(
                "provider" to "openai_compatible",
                "api_key" to "test-key",
                "base_url" to "https://example.test/v1",
                "model" to "test-model",
                "user_timezone" to "Asia/Shanghai",
                "context_engine" to mapOf(
                    "compaction_model" to "fast-summary",
                    "pre_compaction_memory_flush" to true,
                ),
            ),
        )

        assertEquals("openai_compatible", parsed.provider)
        assertEquals("test-key", parsed.apiKey)
        assertEquals("https://example.test/v1", parsed.baseUrl)
        assertEquals("test-model", parsed.model)
        assertEquals("Home agent", parsed.systemPrompt)
        assertEquals("zh", parsed.responseLanguage)
        assertEquals(1024, parsed.maxTokens)
        assertEquals(8, parsed.maxToolIterations)
        assertEquals("X-Test:1", parsed.extraHeaders)
        assertEquals("Asia/Shanghai", parsed.userTimezone)
        assertEquals(listOf(mapOf("id" to "fast", "label" to "Fast")), parsed.allowedModels)
        assertEquals("image-gen", parsed.imageModel)
        assertEquals("vision-model", parsed.imageAnalysisModel)
        assertEquals("data_url", parsed.imageBase64UrlFormat)
        assertEquals("video-model", parsed.videoModel)
        assertEquals("audio-model", parsed.audioModel)
        assertEquals("vision-model", parsed.capabilityConfigs?.get("imageAnalysis")?.model)
        assertEquals("vision-key", parsed.capabilityConfigs?.get("imageAnalysis")?.apiKey)
        assertEquals("raw", parsed.capabilityConfigs?.get("imageAnalysis")?.imageBase64UrlFormat)
        assertEquals(true, parsed.scenePromptConfig?.enabled)
        assertEquals(mapOf("location" to "ask"), parsed.scenePromptConfig?.hostPolicies)
        assertEquals(0.75, parsed.contextEngine.triggerRatio, 0.001)
        assertEquals(16000, parsed.contextEngine.contextWindowTokens)
        assertEquals(1000000, parsed.contextEngine.nativeContextWindowTokens)
        assertEquals(128000, parsed.contextEngine.providerContextWindowTokens)
        assertEquals(2000, parsed.contextEngine.responseReserveTokens)
        assertEquals("llm_summary", parsed.contextEngine.compactionStrategy)
        assertEquals("fast-summary", parsed.contextEngine.compactionModel)
        assertEquals(45000L, parsed.contextEngine.compactionTimeoutMs)
        assertEquals(true, parsed.contextEngine.preCompactionMemoryFlush)
        assertEquals(config.toJson(), config.toJsonString())
        assertEquals("test-model", parsedFromObject.model)
        assertEquals("test-model", parsedFromMap.model)
        assertEquals("en", parsedFromMap.responseLanguage)
        assertEquals("Asia/Shanghai", parsedFromMap.userTimezone)
        assertEquals("vision-model", LlmCapabilityConfig.fromJson(parsed.capabilityConfigs!!.getValue("imageAnalysis").toJson()).model)
        assertEquals("vision-model", LlmCapabilityConfig.fromMap(mapOf("provider" to "openai", "api_key" to "vision-key", "model" to "vision-model")).model)
        assertEquals(true, ScenePromptConfig.fromMap(mapOf("enabled" to true, "host_policies" to mapOf("location" to "ask"))).enabled)
        assertEquals("fast-summary", ContextEngineConfig.fromJson(config.contextEngine.toJson()).compactionModel)
        assertEquals(true, ContextEngineConfig.fromMap(mapOf("compaction_model" to "fast-summary", "pre_compaction_memory_flush" to true)).preCompactionMemoryFlush)
    }

    @Test
    fun llmConfigShellSecurityDefaultsToOnRequestAndRoundTripsTrustedAllow() {
        // Default posture is on_request and is emitted on the wire.
        val defaultJson = LlmConfig(provider = "openai", apiKey = "k", model = "m").toJsonObject()
        assertEquals(
            "on_request",
            defaultJson.getJSONObject("shell_security").getString("approval_mode"),
        )
        assertEquals(
            ShellApprovalMode.ON_REQUEST,
            LlmConfig.fromJson(LlmConfig(provider = "openai", apiKey = "k", model = "m").toJson()).shellSecurity.approvalMode,
        )

        // trusted_allow round-trips via snake_case wire.
        val trusted = LlmConfig(
            provider = "openai",
            apiKey = "k",
            model = "m",
            shellSecurity = ShellSecurityConfig(approvalMode = ShellApprovalMode.TRUSTED_ALLOW),
        )
        val parsed = LlmConfig.fromJson(trusted.toJson())
        assertEquals(ShellApprovalMode.TRUSTED_ALLOW, parsed.shellSecurity.approvalMode)

        // Unknown wire values fall back to on_request.
        assertEquals(
            ShellApprovalMode.ON_REQUEST,
            ShellSecurityConfig.fromMap(mapOf("approval_mode" to "bogus")).approvalMode,
        )
    }

    @Test
    fun llmConfigLocalizesDefaultSystemPromptWhenResponseLanguageIsChinese() {
        val zhJson = LlmConfig(
            provider = "openai",
            apiKey = "k",
            model = "m",
            responseLanguage = "zh",
        ).toJsonObject()
        assertEquals("你是一个有帮助的 AI 助手。", zhJson.getString("system_prompt"))

        val customJson = LlmConfig(
            provider = "openai",
            apiKey = "k",
            model = "m",
            systemPrompt = "Use host policy.",
            responseLanguage = "zh",
        ).toJsonObject()
        assertEquals("Use host policy.", customJson.getString("system_prompt"))

        val parsed = LlmConfig.fromJsonObject(
            JSONObject()
                .put("provider", "openai")
                .put("api_key", "k")
                .put("model", "m")
                .put("response_language", "zh"),
        )
        assertEquals("你是一个有帮助的 AI 助手。", parsed.systemPrompt)
    }

    @Test
    fun customToolDefUsesFlutterCompatibleJsonShape() {
        val tool = CustomToolDef(
            name = "home_light_set",
            description = "Control virtual lights",
            parameters = JSONObject("""{"type":"object","properties":{"room":{"type":"string"}}}"""),
            effect = "mutates_user_data",
        )

        val json = tool.toJsonObject()
        val fromMap = CustomToolDef.fromMap(
            mapOf(
                "name" to "home_lock",
                "description" to "Lock the front door",
                "parameters" to mapOf("type" to "object"),
                "effect" to "external",
            ),
        )
        val fromJson = CustomToolDef.fromJson(tool.toJson())
        val missingFields = CustomToolDef.fromMap(emptyMap<String, Any?>())

        assertEquals("home_light_set", json.getString("name"))
        assertEquals("Control virtual lights", json.getString("description"))
        assertEquals("object", json.getJSONObject("parameters").getString("type"))
        assertEquals("mutates_user_data", json.getString("effect"))
        assertEquals(tool.toJson(), tool.toJsonString())
        assertEquals("home_light_set", fromJson.name)
        assertEquals("home_lock", fromMap.name)
        assertEquals("object", fromMap.parameters.getString("type"))
        assertEquals("external", fromMap.effect)
        assertEquals("", missingFields.name)
        assertEquals("", missingFields.description)
        assertEquals("object", missingFields.parameters.getString("type"))
        assertEquals("unknown", missingFields.effect)
    }

    @Test
    fun chatEventDecodesCoreStreamEvents() {
        val response = ChatEvent.fromJson("""{"type":"response_delta","delta":"hello"}""")
        val toolCall = ChatEvent.fromJson(
            """{"type":"tool_call","tool_name":"home_light_set","arguments_json":"{}"}""",
        )
        val error = ChatEvent.fromJson("""{"type":"error","message":"bad handle"}""")
        val responseFromJsonString = ChatEvent.fromJsonString("""{"type":"response","content":"done"}""")
        val responseFromObject = ChatEvent.fromJsonObject(JSONObject("""{"type":"response_delta","content":"object"}"""))
        val responseFromMap = ChatEvent.fromMap(
            mapOf(
                "type" to "response_delta",
                "content" to "map",
            ),
        )
        val unknownFromBlank = ChatEvent.fromJson("")
        val streamReset = ChatEvent.fromJson(
            """{"type":"stream_reset","reason":"connection reset by peer"}""",
        )

        assertTrue(response is ChatEvent.ResponseDeltaEvent)
        assertEquals("hello", (response as ChatEvent.ResponseDeltaEvent).content)
        assertTrue(toolCall is ChatEvent.ToolCallEvent)
        assertEquals("home_light_set", (toolCall as ChatEvent.ToolCallEvent).toolName)
        assertTrue(error is ChatEvent.ErrorEvent)
        assertEquals("bad handle", (error as ChatEvent.ErrorEvent).message)
        assertTrue(responseFromJsonString is ChatEvent.ResponseEvent)
        assertEquals("done", (responseFromJsonString as ChatEvent.ResponseEvent).content)
        assertTrue(responseFromObject is ChatEvent.ResponseDeltaEvent)
        assertEquals("object", (responseFromObject as ChatEvent.ResponseDeltaEvent).content)
        assertTrue(responseFromMap is ChatEvent.ResponseDeltaEvent)
        assertEquals("map", (responseFromMap as ChatEvent.ResponseDeltaEvent).content)
        assertTrue(unknownFromBlank is ChatEvent.RawEvent)
        assertEquals("unknown", (unknownFromBlank as ChatEvent.RawEvent).type)
        assertTrue(streamReset is ChatEvent.StreamResetEvent)
        assertEquals(
            "connection reset by peer",
            (streamReset as ChatEvent.StreamResetEvent).reason,
        )
    }

    @Test
    fun a2aModelsExposeFlutterStableFields() {
        val envelope = A2ADeepLinkEnvelope.fromMap(
            mapOf(
                "protocolVersion" to 1,
                "envelopeId" to "env-1",
                "kind" to "task_request",
                "sender" to mapOf("agentId" to "sender.agent", "peerId" to "peer-1"),
                "recipient" to mapOf("agentId" to "receiver.agent"),
                "task" to mapOf(
                    "taskId" to "task-1",
                    "message" to "hello",
                    "sessionMode" to "isolated",
                ),
                "callback" to mapOf("deepLinkUrl" to "agent-sender://a2a/result"),
                "createdAt" to "2026-06-03T00:00:00Z",
                "expiresAt" to "2026-06-03T01:00:00Z",
                "nonce" to "nonce",
                "idempotencyKey" to "idem",
            ),
        )
        val task = A2ATaskRecord.fromMap(
            mapOf(
                "task_id" to "task-1",
                "envelope_id" to "env-1",
                "idempotency_key" to "idem",
                "agent_id" to "receiver.agent",
                "sender" to mapOf("agent_id" to "sender.agent"),
                "request" to mapOf("task_id" to "task-1", "message" to "hello"),
                "status" to "pending_user_confirmation",
                "trust" to "untrusted",
                "source" to "deep_link",
                "created_at" to "2026-06-03T00:00:00Z",
                "updated_at" to "2026-06-03T00:00:00Z",
                "session_id" to "peer-session-1",
                "peer_message_id" to "peer-message-1",
                "result_artifacts" to listOf(
                    mapOf("artifact_id" to "photo-1", "mime_type" to "image/jpeg"),
                ),
            ),
        )
        assertEquals("photo-1", task.resultArtifacts.single().artifactId)
        val invite = A2APeerInvite.fromMap(
            mapOf(
                "peerId" to "peer-1",
                "sharedSecret" to "secret",
                "envelope" to envelope.jsonObject(),
                "deepLinkUrl" to "agent-host://a2a/peer?envelope=...",
            ),
        )
        val localStatus = A2ALocalTransportStatus.fromMap(
            mapOf(
                "supported" to true,
                "running" to true,
                "transport" to "lan_tcp_jsonl",
                "serviceType" to "_napaxi-a2a._tcp.",
                "peerId" to "phone-a",
                "listenerPort" to 38471,
                "registeredName" to "Napaxi-phone-a",
                "discoveredPeerCount" to 2,
                "activeDiscoveryCount" to 1,
                "sentMessageCount" to 3,
                "receivedMessageCount" to 4,
                "multicastLockHeld" to true,
                "lastError" to "",
            ),
        )

        assertEquals("env-1", envelope.envelopeId)
        assertEquals("peer-1", envelope.sender.peerId)
        assertEquals("receiver.agent", envelope.recipient?.agentId)
        assertEquals("task-1", envelope.task?.taskId)
        assertEquals("agent-sender://a2a/result", envelope.callback?.deepLinkUrl)
        assertEquals("idem", task.idempotencyKey)
        assertEquals("pending_user_confirmation", task.status)
        assertEquals("peer-session-1", task.sessionId)
        assertEquals("peer-message-1", task.peerMessageId)
        assertEquals("peer-1", invite.peerId)
        assertEquals("env-1", invite.envelope.envelopeId)
        assertEquals(38471, localStatus.listenerPort)
        assertEquals("Napaxi-phone-a", localStatus.registeredName)
        assertEquals(2, localStatus.discoveredPeerCount)
        assertEquals(1, localStatus.activeDiscoveryCount)
        assertEquals(3, localStatus.sentMessageCount)
        assertEquals(4, localStatus.receivedMessageCount)
        assertEquals(true, localStatus.multicastLockHeld)
    }

    @Test
    fun a2aPairingHelpersDeriveSymmetricNonPublicSecret() {
        val peerA = A2ALocalPeerAdvertisement.fromMap(
            mapOf(
                "peerId" to "phone-a",
                "agentId" to "agent.a",
                "displayName" to "Phone A",
                "publicKey" to "public-a",
                "transport" to "lan_tcp_jsonl",
                "endpoint" to "tcp://192.168.1.7:38471/a2a",
                "host" to "192.168.1.7",
                "port" to 38471,
            ),
        )
        val peerB = A2ALocalPeerAdvertisement.fromMap(
            mapOf(
                "peerId" to "phone-b",
                "agentId" to "agent.b",
                "displayName" to "Phone B",
                "publicKey" to "public-b",
                "transport" to "lan_tcp_jsonl",
                "endpoint" to "tcp://192.168.1.8:38471/a2a",
                "host" to "192.168.1.8",
                "port" to 38471,
            ),
        )

        assertEquals("phone-a|public-a", A2APairing.pairingKey(peerA.peerId, peerA.publicKey))
        assertEquals(9, A2APairing.pairingCodeFromIdentity("phone-a", "public-a").length)
        assertEquals("A1B2C3D4EF00", A2APairing.normalizePairingSecret(" a1b2-c3d4 ef00 "))
        assertEquals("A1B2 C3D4 EF00", A2APairing.formatPairingSecret("a1b2c3d4ef00"))

        val secretA = "AAAA BBBB CCCC DDDD"
        val secretB = "1111-2222-3333-4444"
        val aToB = A2APairing.deriveLocalSharedSecret(
            localPeerId = peerA.peerId,
            localPublicKey = peerA.publicKey,
            localPairingSecret = secretA,
            remotePeerId = peerB.peerId,
            remotePublicKey = peerB.publicKey,
            remotePairingSecret = secretB,
        )
        val bToA = A2APairing.deriveLocalSharedSecret(
            localPeerId = peerB.peerId,
            localPublicKey = peerB.publicKey,
            localPairingSecret = secretB,
            remotePeerId = peerA.peerId,
            remotePublicKey = peerA.publicKey,
            remotePairingSecret = secretA,
        )
        val withoutRemoteSecret = A2APairing.deriveLocalSharedSecret(
            localPeerId = peerA.peerId,
            localPublicKey = peerA.publicKey,
            localPairingSecret = secretA,
            remotePeerId = peerB.peerId,
            remotePublicKey = peerB.publicKey,
            remotePairingSecret = "",
        )

        assertEquals(
            "tofu-hmac-v2:2F4C67A6913CE598670024D0F63C64C26DE3D8B6CDED86ED376EB0A9F02979DF",
            aToB,
        )
        assertEquals(aToB, bToA)
        assertTrue(aToB.startsWith("tofu-hmac-v2:"))
        assertEquals("tofu-hmac-v2:".length + 64, aToB.length)
        assertTrue(aToB != withoutRemoteSecret)
        assertFalse(aToB.contains("public-a"))
        assertFalse(aToB.contains("public-b"))
        assertFalse(aToB.contains("AAAA"))
        assertFalse(aToB.contains("1111"))
    }

    @Test
    fun chatEventDecodesFlutterStableTypedEvents() {
        val askingHuman = ChatEvent.fromJson(
            """
            {
              "type":"asking_human",
              "question":"Proceed?",
              "request_id":"hitl-1",
              "options":["yes","no"],
              "context":"approval"
            }
            """.trimIndent(),
        )
        val skillActivated = ChatEvent.fromJson(
            """
            {
              "type":"skill_activated",
              "agent_id":"assistant",
              "skills":[{"name":"wallet","version":"1.0","reason":"matched"}]
            }
            """.trimIndent(),
        )
        val actionProposal = ChatEvent.fromJson(
            """
            {
              "type":"action_proposal_created",
              "request_id":"proposal-1",
              "provider_id":"demo.provider",
              "agent_id":"wallet",
              "action_id":"pay",
              "tool_name":"app_action_pay",
              "risk":"high",
              "expires_at":"2030-01-01T00:00:00Z"
            }
            """.trimIndent(),
        )
        val evolutionQueued = ChatEvent.fromMap(
            mapOf(
                "type" to "evolution_queued",
                "review_types" to listOf("skills"),
                "runs" to listOf(
                    mapOf(
                        "id" to "run-1",
                        "reviewType" to "skills",
                    ),
                ),
            ),
        )
        val activatedInfo = ChatEvent.ActivatedSkillInfo.fromMap(
            mapOf(
                "name" to "wallet",
                "version" to "1.0",
                "reason" to "matched",
            ),
        )

        assertTrue(askingHuman is ChatEvent.AskingHumanEvent)
        assertEquals("Proceed?", (askingHuman as ChatEvent.AskingHumanEvent).question)
        assertEquals(listOf("yes", "no"), askingHuman.options)
        assertEquals("approval", askingHuman.context)

        assertTrue(skillActivated is ChatEvent.SkillActivatedEvent)
        assertEquals("assistant", (skillActivated as ChatEvent.SkillActivatedEvent).agentId)
        assertEquals("wallet", skillActivated.skills.single().name)
        assertEquals("matched", skillActivated.skills.single().reason)

        assertTrue(actionProposal is ChatEvent.ActionProposalCreatedEvent)
        assertEquals("proposal-1", (actionProposal as ChatEvent.ActionProposalCreatedEvent).requestId)
        assertEquals("app_action_pay", actionProposal.toolName)

        assertTrue(evolutionQueued is ChatEvent.EvolutionQueuedEvent)
        assertEquals(listOf("skills"), (evolutionQueued as ChatEvent.EvolutionQueuedEvent).reviewTypes)
        assertEquals(listOf("run-1"), evolutionQueued.runIds)
        assertEquals("skills", evolutionQueued.runs.single().reviewType)
        assertEquals("wallet", activatedInfo.name)
        assertEquals("matched", activatedInfo.reason)
    }

    @Test
    fun sessionInfoDecodesFlutterStableShape() {
        val info = SessionInfo.fromJson(
            """
            {
              "key":{"channel_type":"app","account_id":"user","thread_id":"thread"},
              "title":"Thread",
              "preview":"Hello",
              "message_count":3,
              "created_at":"2030-01-01T00:00:00Z",
              "updated_at":"2030-01-01T00:01:00Z"
            }
            """.trimIndent(),
        )

        assertEquals("app", info.key.channelType)
        assertEquals("user", info.key.accountId)
        assertEquals("thread", info.key.threadId)
        assertEquals("Thread", info.title)
        assertEquals("Hello", info.preview)
        assertEquals(3, info.messageCount)
        assertEquals("2030-01-01T00:01:00Z", info.updatedAt)
        assertEquals("thread", SessionInfo.fromJsonObject(info.toJsonObject()).key.threadId)
        assertEquals("thread-map", SessionInfo.fromMap(mapOf("key" to mapOf("thread_id" to "thread-map"))).key.threadId)
        assertEquals(info.toJson(), info.toJsonString())
    }

    @Test
    fun sessionRunInfoTracksActiveAndTerminalState() {
        val key = SessionKey(channelType = "app", accountId = "user", threadId = "thread")
        val run = SessionRunInfo.create(key, agentId = "assistant", now = 1000L)

        assertEquals("assistant:app:user:thread", run.id)
        assertEquals(SessionRunStatus.Running, run.status)
        assertEquals(false, run.isTerminal)
        assertEquals(false, run.needsInput)

        val waiting = run.copyWith(
            status = SessionRunStatus.WaitingForInput,
            activity = "Waiting for input",
            humanRequestId = "request-1",
            updatedAt = 2000L,
        )

        assertEquals(SessionRunStatus.WaitingForInput, waiting.status)
        assertEquals(true, waiting.needsInput)
        assertEquals("request-1", waiting.humanRequestId)
        assertEquals(2000L, waiting.updatedAt)

        val completed = waiting.copyWith(
            status = SessionRunStatus.Completed,
            activity = "Completed",
            clearHumanRequest = true,
            updatedAt = 3000L,
        )

        assertEquals(SessionRunStatus.Completed, completed.status)
        assertEquals(true, completed.isTerminal)
        assertEquals(null, completed.humanRequestId)
        assertEquals(3000L, completed.updatedAt)
    }

    @Test
    fun sessionHistoryModelsExposeFlutterStableFields() {
        val message = ChatMessage(
            """
            {
              "id":"msg-1",
              "role":"tool_calls",
              "content":"{\"narrative\":\"Checking\",\"calls\":[{\"name\":\"search\",\"call_id\":\"call-1\",\"arguments\":{\"query\":\"napaxi\"},\"result_preview\":\"ok\"}]}",
              "created_at":"2030-01-01T00:00:00Z",
              "attachments":[
                {"kind":"image","mime_type":"image/png","filename":"out.png","path":"/workspace/out.png"},
                {"kind":"document","mime_type":"text/plain","name":"note.txt","path":"/tmp/note.txt"}
              ]
            }
            """.trimIndent(),
        )
        val human = ChatMessage(
            """
            {
              "role":"asking_human",
              "content":"{\"request_id\":\"hitl-1\",\"question\":\"Proceed?\",\"options\":[\"yes\",\"no\"],\"context\":\"approval\"}"
            }
            """.trimIndent(),
        )
        val page = HistoryPage(
            """
            {
              "messages":[{"role":"assistant","content":"hello"}],
              "has_more":true,
              "next_before":"cursor-1"
            }
            """.trimIndent(),
        )

        assertEquals("msg-1", message.id)
        assertEquals("tool_calls", message.role)
        assertEquals("Checking", message.thinkingContent)
        assertEquals("search", message.toolCalls?.single()?.name)
        assertEquals("call-1", message.toolCalls?.single()?.callId)
        assertEquals("napaxi", message.toolCalls?.single()?.arguments?.getString("query"))
        assertEquals("ok", message.toolCalls?.single()?.result)
        assertEquals(true, message.toolCalls?.single()?.resultTruncated)
        assertEquals("/workspace/out.png", message.attachments.first().sandboxPath)
        assertEquals(null, message.attachments.first().localPath)
        assertEquals("image", message.attachments.first().toJsonObject().getString("kind"))
        assertEquals("image/png", message.attachments.first().toJsonObject().getString("mime_type"))
        assertEquals("/workspace/out.png", message.attachments.first().toJsonObject().getString("sandbox_path"))
        assertEquals("/tmp/note.txt", message.attachments.last().localPath)
        assertEquals(null, message.attachments.last().sandboxPath)
        assertEquals("/tmp/note.txt", message.attachments.last().toJsonObject().getString("path"))

        val createdAttachment = ChatAttachment.create(
            kind = "document",
            mimeType = "text/plain",
            filename = "note.txt",
            localPath = "/tmp/note.txt",
        )
        assertEquals("note.txt", createdAttachment.filename)
        assertEquals("/tmp/note.txt", createdAttachment.localPath)
        assertEquals("text/plain", JSONObject(createdAttachment.toJson()).getString("mime_type"))
        assertEquals("note.txt", ChatAttachment.fromJson(createdAttachment.toJson()).filename)
        assertEquals("note.txt", ChatAttachment.fromJsonObject(createdAttachment.toJsonObject()).filename)
        assertEquals(
            "/tmp/note.txt",
            ChatAttachment.fromMap(
                mapOf(
                    "kind" to "document",
                    "mime_type" to "text/plain",
                    "name" to "note.txt",
                    "path" to "/tmp/note.txt",
                ),
            ).localPath,
        )

        assertEquals("hitl-1", human.humanRequestId)
        assertEquals("Proceed?", human.humanQuestion)
        assertEquals(listOf("yes", "no"), human.humanOptions)
        assertEquals("approval", human.humanContext)

        assertEquals(true, page.hasMore)
        assertEquals("cursor-1", page.nextBefore)
        assertEquals("assistant", page.messages.single().role)
        assertEquals("tool_calls", ChatMessage.fromJson(message.toJson()).role)
        assertEquals("assistant", ChatMessage.fromMap(mapOf("role" to "assistant", "content" to "hello")).role)
        assertEquals("search", ToolCallInfo.fromJson(message.toolCalls!!.single().toJson()).name)
        assertEquals(
            true,
            ToolCallInfo.fromMap(
                mapOf(
                    "name" to "search",
                    "tool_call_id" to "call-2",
                    "parameters" to """{"query":"napaxi"}""",
                    "error_preview" to "failed",
                    "parameters_truncated" to true,
                ),
            ).argumentsTruncated,
        )
        assertEquals("failed", ToolCallInfo.fromMap(mapOf("error_preview" to "failed")).error)
        assertEquals("assistant", HistoryPage.fromJson(page.toJson()).messages.single().role)
        assertEquals(
            "assistant",
            HistoryPage.fromMap(
                mapOf(
                    "messages" to listOf(mapOf("role" to "assistant", "content" to "hello")),
                    "has_more" to true,
                ),
            ).messages.single().role,
        )
    }

    @Test
    fun mcAttachmentSupportsFlutterStyleSandboxPathOverride() {
        val attachment = McAttachment(
            kind = "image",
            mimeType = "image/png",
            filename = "out.png",
            sandboxPath = "/workspace/original.png",
            localPath = "/local/out.png",
            dataBase64 = "cG5n",
        )
        val withoutOverride = attachment.toJsonObject()
        val withOverride = attachment.toJsonObject("/workspace/override.png")

        assertEquals("/workspace/original.png", withoutOverride.getString("sandbox_path"))
        assertEquals("/workspace/override.png", withOverride.getString("sandbox_path"))
        assertEquals("/local/out.png", withOverride.getString("path"))
        assertEquals("cG5n", withOverride.getString("data_base64"))
    }

    @Test
    fun workspacePathsExposeFlutterStableConstants() {
        assertEquals("SOUL.md", WorkspacePaths.soul)
        assertEquals("IDENTITY.md", WorkspacePaths.identity)
        assertEquals("AGENTS.md", WorkspacePaths.agents)
        assertEquals("USER.md", WorkspacePaths.user)
        assertEquals("MEMORY.md", WorkspacePaths.memory)
        assertEquals("PROJECT.md", WorkspacePaths.project)
        assertEquals("HEARTBEAT.md", WorkspacePaths.heartbeat)
        assertEquals("TOOLS.md", WorkspacePaths.tools)
        assertEquals("BOOTSTRAP.md", WorkspacePaths.bootstrap)
        assertEquals("context/profile.json", WorkspacePaths.profile)
        assertEquals("daily/", WorkspacePaths.dailyDir)
    }

    @Test
    fun contextStatusExposesFlutterStableBudgetFields() {
        val status = ContextStatus(
            """
            {
              "thread_id":"thread",
              "engine":"compressor",
              "summary_present":true,
              "compaction_count":2,
              "tokens_before":1000,
              "tokens_after":500,
              "estimated_tokens":750,
              "context_window_tokens":1000,
              "trigger_tokens":700,
              "target_tokens":450,
              "response_reserve_tokens":100,
              "usage_percent":75.0,
              "trigger_ratio":0.7,
              "target_ratio":0.45,
              "last_compacted_at":"2030-01-01T00:00:00Z",
              "display_used_tokens":760,
              "display_source":"provider",
              "last_prompt_tokens":800,
              "preflight_estimated_tokens":770,
              "cache_read_tokens":10,
              "cache_write_tokens":20,
              "context_window_source":"model",
              "native_context_window_tokens":1000000,
              "native_context_window_source":"model_rule",
              "effective_context_window_tokens":1000,
              "effective_context_window_source":"config",
              "response_reserve_source":"config",
              "provider_metadata_fetched_at":"2030-01-01T00:00:00Z",
              "provider_metadata_stale":false,
              "context_guard_status":"ok",
              "context_guard_reason":"",
              "context_route":"prune_tools",
              "overflow_tokens":20,
              "breakdown":{"system_prompt_tokens":1,"summary_tokens":2,"history_tokens":3,"tool_descriptor_tokens":4,"tool_result_tokens":5,"tool_call_tokens":6,"attachment_tokens":7,"image_tokens":8,"response_reserve_tokens":9,"total_tokens":45},
              "context_budget_status":{"source":"provider","provider":"openai","model":"gpt","route":"compact","should_compact":true,"estimated_prompt_tokens":900,"context_token_budget":1000,"native_context_window_tokens":1000000,"native_context_window_source":"model_rule","effective_context_window_tokens":1000,"effective_context_window_source":"config","response_reserve_source":"config","provider_metadata_fetched_at":"2030-01-01T00:00:00Z","provider_metadata_stale":false,"prompt_budget_before_reserve":900,"reserve_tokens":100,"effective_reserve_tokens":120,"remaining_prompt_budget_tokens":0,"overflow_tokens":20,"tool_result_reducible_chars":100,"tool_result_reducible_tokens":40,"context_guard_status":"ok","context_guard_reason":"","message_count":5,"unwindowed_message_count":1,"updated_at":"2030-01-01T00:00:00Z"},
              "updated_at":"2030-01-01T00:00:01Z",
              "fresh":true,
              "current_window_tokens":760,
              "transcript_estimated_tokens":900,
              "last_context_delta_tokens":12,
              "last_context_delta_reason":"tool_result_pruned",
              "tool_result_pruned_tokens":50,
              "tool_result_pruned_chars":500,
              "context_display_label":"current_window",
              "compaction_strategy":"llm_summary",
              "last_compaction_duration_ms":321,
              "adaptive_chunk_count":3,
              "oversized_message_count":1,
              "protected_tail_tokens":18000,
              "overflow_retry_attempted_at":"2030-01-01T00:00:02Z",
              "overflow_retry_succeeded":true,
              "overflow_retry_reason":"overflow_retry_succeeded",
              "pre_compaction_memory_flush_enabled":true,
              "pre_compaction_memory_flush_status":"disabled_for_v6a"
            }
            """.trimIndent(),
        )

        assertEquals("thread", status.threadId)
        assertEquals(true, status.summaryPresent)
        assertEquals(2, status.compactionCount)
        assertEquals(760, status.displayUsedTokens)
        assertEquals(800, status.lastPromptTokens)
        assertEquals(770, status.preflightEstimatedTokens)
        assertEquals(10, status.cacheReadTokens)
        assertEquals(20, status.cacheWriteTokens)
        assertEquals("model", status.contextWindowSource)
        assertEquals(1000000, status.nativeContextWindowTokens)
        assertEquals("model_rule", status.nativeContextWindowSource)
        assertEquals(1000, status.effectiveContextWindowTokens)
        assertEquals("config", status.effectiveContextWindowSource)
        assertEquals("config", status.responseReserveSource)
        assertEquals("2030-01-01T00:00:00Z", status.providerMetadataFetchedAt)
        assertEquals("ok", status.contextGuardStatus)
        assertEquals("prune_tools", status.contextRoute)
        assertEquals(20, status.overflowTokens)
        assertEquals(true, status.isNearTrigger)
        assertEquals(0.76, status.usageFraction, 0.001)
        assertEquals(true, status.isProviderBacked)
        assertEquals(false, status.hasError)
        assertEquals(45, status.breakdown?.totalTokens)
        assertEquals(4, status.breakdown?.toolDescriptorTokens)
        assertEquals(8, status.breakdown?.imageTokens)
        assertEquals(true, status.contextBudgetStatus?.shouldCompact)
        assertEquals("compact", status.contextBudgetStatus?.route)
        assertEquals(1000000, status.contextBudgetStatus?.nativeContextWindowTokens)
        assertEquals("model_rule", status.contextBudgetStatus?.nativeContextWindowSource)
        assertEquals(1000, status.contextBudgetStatus?.effectiveContextWindowTokens)
        assertEquals("config", status.contextBudgetStatus?.effectiveContextWindowSource)
        assertEquals("config", status.contextBudgetStatus?.responseReserveSource)
        assertEquals("2030-01-01T00:00:00Z", status.contextBudgetStatus?.providerMetadataFetchedAt)
        assertEquals(20, status.contextBudgetStatus?.overflowTokens)
        assertEquals(40, status.contextBudgetStatus?.toolResultReducibleTokens)
        assertEquals("ok", status.contextBudgetStatus?.contextGuardStatus)
        assertEquals(5, status.contextBudgetStatus?.messageCount)
        assertEquals(1, status.contextBudgetStatus?.unwindowedMessageCount)
        assertEquals(760, status.currentWindowTokens)
        assertEquals(900, status.transcriptEstimatedTokens)
        assertEquals(12, status.lastContextDeltaTokens)
        assertEquals("tool_result_pruned", status.lastContextDeltaReason)
        assertEquals(50, status.toolResultPrunedTokens)
        assertEquals(500, status.toolResultPrunedChars)
        assertEquals("current_window", status.contextDisplayLabel)
        assertEquals("llm_summary", status.compactionStrategy)
        assertEquals(321, status.lastCompactionDurationMs)
        assertEquals(3, status.adaptiveChunkCount)
        assertEquals(1, status.oversizedMessageCount)
        assertEquals(18000, status.protectedTailTokens)
        assertEquals(true, status.overflowRetrySucceeded)
        assertEquals(true, status.preCompactionMemoryFlushEnabled)
        assertEquals("disabled_for_v6a", status.preCompactionMemoryFlushStatus)
        assertEquals("thread", ContextStatus.fromJson(status.toJson()).threadId)
        assertEquals("thread", ContextStatus.fromJsonObject(status.toJsonObject()).threadId)
        assertEquals(
            45,
            ContextTokenBreakdown.fromMap(
                mapOf(
                    "system_prompt_tokens" to 1,
                    "summary_tokens" to 2,
                    "history_tokens" to 3,
                    "tool_descriptor_tokens" to 4,
                    "tool_result_tokens" to 5,
                    "tool_call_tokens" to 6,
                    "attachment_tokens" to 7,
                    "image_tokens" to 8,
                    "response_reserve_tokens" to 9,
                    "total_tokens" to 45,
                ),
            ).totalTokens,
        )
        assertEquals(
            "compact",
            ContextBudgetStatus.fromMap(
                mapOf(
                    "source" to "provider",
                    "provider" to "openai",
                    "model" to "gpt",
                    "route" to "compact",
                    "should_compact" to true,
                    "estimated_prompt_tokens" to 900,
                    "context_token_budget" to 1000,
                    "prompt_budget_before_reserve" to 900,
                    "reserve_tokens" to 100,
                    "effective_reserve_tokens" to 120,
                    "remaining_prompt_budget_tokens" to 0,
                    "overflow_tokens" to 20,
                    "tool_result_reducible_chars" to 100,
                    "message_count" to 5,
                    "unwindowed_message_count" to 1,
                    "updated_at" to "2030-01-01T00:00:00Z",
                ),
            ).route,
        )
    }

    @Test
    fun sessionRunRecordDecodesFlutterStableLedgerShape() {
        val record = SessionRunRecord.fromJson(
            """
            {
              "runId":"run-1",
              "status":"unverified",
              "agentId":"assistant",
              "sessionKey":"app:user:thread",
              "threadId":"thread",
              "startedAt":1000,
              "completedAt":2500,
              "durationMs":1500,
              "evidenceKind":"side_effect_observed",
              "verification":"unverified",
              "toolCallCount":2,
              "evidence":[
                {
                  "kind":"tool_observed",
                  "source":"tool",
                  "effect":"mutates_user_data",
                  "isError":false,
                  "digest":"abc"
                }
              ],
              "summary":"Done",
              "error":null,
              "parentRunId":"parent-1",
              "childRunIds":["child-1"]
            }
            """.trimIndent(),
        )

        assertEquals("run-1", record.runId)
        assertEquals(SessionRunRecordStatus.Unverified, record.status)
        assertEquals("assistant", record.agentId)
        assertEquals("app:user:thread", record.sessionKey)
        assertEquals("thread", record.threadId)
        assertEquals(1000L, record.startedAt)
        assertEquals(2500L, record.completedAt)
        assertEquals(1500L, record.durationMs)
        assertEquals(RunEvidenceKind.SideEffectObserved, record.evidenceKind)
        assertEquals(RunVerification.Unverified, record.verification)
        assertEquals(2, record.toolCallCount)
        assertEquals(RunEvidenceKind.ToolObserved, record.evidence.single().kind)
        assertEquals("mutates_user_data", record.evidence.single().effect)
        assertEquals("abc", record.evidence.single().digest)
        assertEquals("Done", record.summary)
        assertEquals("parent-1", record.parentRunId)
        assertEquals(listOf("child-1"), record.childRunIds)
        assertEquals("run-1", decodeSessionRunRecords("[${record.rawJson}]").single().runId)
        assertEquals("run-1", decodeSessionRunRecords("""{"runs":[${record.rawJson}]}""").single().runId)
    }

    @Test
    fun agentDefinitionDecodesFlutterStableShape() {
        val definition = AgentDefinition(
            """
            {
              "id":"assistant",
              "name":"Assistant",
              "description":"Helpful",
              "system_prompt":"Be useful",
              "provider":"openai",
              "model":"gpt-test",
              "model_profile_id":"fast",
              "engine_id":"external_host",
              "engine_profile_id":"dev-loop",
              "engine_config":{"binary":"custom-agent"},
              "tool_filter":{"type":"Allowlist","tools":["search","write"]},
              "icon":"spark"
            }
            """.trimIndent(),
        )

        assertEquals("assistant", definition.id)
        assertEquals("Assistant", definition.name)
        assertEquals("Helpful", definition.description)
        assertEquals("Be useful", definition.systemPrompt)
        assertEquals("openai", definition.provider)
        assertEquals("gpt-test", definition.model)
        assertEquals("fast", definition.modelProfileId)
        assertEquals("external_host", definition.engineId)
        assertEquals("dev-loop", definition.engineProfileId)
        assertEquals("custom-agent", definition.engineConfig.getString("binary"))
        assertEquals(ToolFilter.Allowlist, definition.toolFilter)
        assertEquals(listOf("search", "write"), definition.toolList)
        assertEquals("spark", definition.icon)
        assertEquals("assistant", definition.toJsonObject().getString("id"))
        assertEquals("assistant", JSONObject(definition.toJson()).getString("id"))
        assertEquals(definition.toJson(), definition.toJsonString())
        assertEquals("assistant", AgentDefinition.fromJson(definition.toJson()).id)
        assertEquals("assistant", AgentDefinition.fromJsonObject(definition.toJsonObject()).id)
        assertEquals(
            "assistant",
            AgentDefinition.fromMap(
                mapOf(
                    "id" to "assistant",
                    "name" to "Assistant",
                    "tool_filter" to mapOf("type" to "Allowlist", "tools" to listOf("search")),
                ),
            ).id,
        )

        val created = AgentDefinition.create(
            id = "writer",
            name = "Writer",
            description = "Writes things",
            systemPrompt = "Write clearly",
            provider = "openai",
            model = "gpt-test",
            modelProfileId = "quality",
            engineId = "external_host",
            engineProfileId = "dev-loop",
            engineConfig = JSONObject("""{"binary":"custom-agent"}"""),
            toolFilter = ToolFilter.Denylist,
            toolList = listOf("delete_file"),
            icon = "pen",
        )

        assertEquals("writer", created.id)
        assertEquals("Writer", created.name)
        assertEquals("Writes things", created.description)
        assertEquals("Write clearly", created.systemPrompt)
        assertEquals("openai", created.provider)
        assertEquals("gpt-test", created.model)
        assertEquals("quality", created.modelProfileId)
        assertEquals("external_host", created.engineId)
        assertEquals("dev-loop", created.engineProfileId)
        assertEquals("custom-agent", created.engineConfig.getString("binary"))
        assertEquals(ToolFilter.Denylist, created.toolFilter)
        assertEquals(listOf("delete_file"), created.toolList)
        assertEquals("pen", created.icon)
        assertEquals("external_host", created.toJsonObject().getString("engine_id"))
        assertEquals("Denylist", created.toJsonObject().getJSONObject("tool_filter").getString("type"))
    }

    @Test
    fun agentEngineRunEventModelsExposeFlutterStableFields() {
        val request = AgentEngineRunEventRequest.create(
            runId = "run-1",
            sessionKeyJson = """{"thread_id":"t1"}""",
            event = JSONObject("""{"type":"completed","tool_call_count":1}"""),
        )

        assertEquals("run-1", request.runId)
        assertEquals("""{"thread_id":"t1"}""", request.sessionKeyJson)
        assertEquals("completed", request.event.getString("type"))
        assertEquals("run-1", AgentEngineRunEventRequest.fromJson(request.toJson()).runId)

        val result = AgentEngineRunEventResult.fromJson(
            """
            {
              "event":{"type":"run_completed","run_id":"run-1"},
              "final_content":"",
              "is_error":false,
              "completed":true
            }
            """.trimIndent(),
        )

        assertEquals("run_completed", result.event.getString("type"))
        assertEquals("", result.finalContent)
        assertFalse(result.isError)
        assertTrue(result.completed)
    }

    @Test
    fun toolInfoDecodesFlutterStableShape() {
        val tool = ToolInfo.fromJson("""{"name":"read_file","description":"Read a workspace file"}""")
        val mapped = ToolInfo.fromMap(
            mapOf(
                "name" to "write_file",
                "description" to "Write a workspace file",
            ),
        )

        assertEquals("read_file", tool.name)
        assertEquals("Read a workspace file", tool.description)
        assertEquals("read_file", ToolInfo.fromJsonObject(tool.toJsonObject()).name)
        assertEquals(tool.toJson(), tool.toJsonString())
        assertEquals("write_file", mapped.name)
        assertEquals("Write a workspace file", mapped.description)
    }

    @Test
    fun workspaceAndMemoryModelsExposeFlutterStableFields() {
        val workspaceFile = WorkspaceFile(
            """{"path":"notes/today.md","content":"hello","updatedAt":"2030-01-01T00:00:00Z"}""",
        )
        val workspaceEntry = WorkspaceEntry(
            """{"path":"notes/today.md","isDirectory":false,"preview":"hello"}""",
        )
        val searchResult = MemorySearchResult(
            """
            {
              "source":"journal",
              "path":"daily/2030-01-01.md",
              "content":"remember this",
              "score":0.75,
              "is_hybrid_match":true,
              "updated_at":"2030-01-01T00:00:00Z",
              "thread_id":"thread",
              "turn_id":"turn",
              "created_at":"2030-01-01T00:00:00Z"
            }
            """.trimIndent(),
        )
        val recall = MemoryRecallSession(
            """
            {
              "thread_id":"thread",
              "title":"Plan",
              "summary":"Summary",
              "snippets":[{"source":"memory","path":"MEMORY.md","content":"note","score":0.9,"turn_id":"turn"}],
              "score":0.8,
              "source":"recall",
              "started_at":"2030-01-01T00:00:00Z",
              "last_active_at":"2030-01-02T00:00:00Z",
              "cached":true,
              "fallback":false,
              "source_doc_ids":["doc-1"],
              "system_note":"indexed"
            }
            """.trimIndent(),
        )
        val stats = RecallIndexStats(
            """
            {
              "status":"ready",
              "db_path":"/tmp/recall.db",
              "schema_version":2,
              "indexed_docs":10,
              "memory_docs":3,
              "journal_docs":4,
              "legacy_daily_docs":1,
              "cached_summaries":2,
              "last_rebuild_at":"2030-01-01T00:00:00Z"
            }
            """.trimIndent(),
        )
        val day = JournalDay(
            """{"date":"2030-01-01","path":"daily/2030-01-01.md","turn_count":2,"legacy":true}""",
        )
        val turn = JournalTurnRecord(
            """
            {
              "turn_id":"turn",
              "created_at":"2030-01-01T00:00:00Z",
              "agent_id":"assistant",
              "thread_id":"thread",
              "user":"hi",
              "assistant":"hello",
              "kind":"turn"
            }
            """.trimIndent(),
        )
        val workspaceFileFromMap = WorkspaceFile.fromMap(
            mapOf(
                "path" to "notes/mapped.md",
                "content" to "mapped",
                "updated_at" to "2030-01-02T00:00:00Z",
            ),
        )
        val workspaceEntryFromMap = WorkspaceEntry.fromMap(
            mapOf(
                "path" to "notes",
                "is_directory" to true,
                "updated_at" to "2030-01-02T00:00:00Z",
            ),
        )
        val searchFromMap = MemorySearchResult.fromMap(
            mapOf(
                "source" to "memory",
                "path" to "MEMORY.md",
                "content" to "mapped memory",
                "score" to 0.6,
                "isHybridMatch" to true,
                "threadId" to "thread-map",
            ),
        )
        val snippetFromMap = MemoryRecallSnippet.fromMap(
            mapOf(
                "source" to "memory",
                "path" to "MEMORY.md",
                "content" to "snippet",
                "score" to 0.7,
                "turn_id" to "turn-map",
            ),
        )
        val recallFromMap = MemoryRecallSession.fromMap(
            mapOf(
                "threadId" to "thread-map",
                "title" to "Mapped",
                "summary" to "Mapped summary",
                "snippets" to listOf(
                    mapOf(
                        "source" to "memory",
                        "path" to "MEMORY.md",
                        "content" to "mapped snippet",
                    ),
                ),
                "sourceDocIds" to listOf("doc-map"),
            ),
        )
        val statsFromMap = RecallIndexStats.fromMap(
            mapOf(
                "status" to "indexing",
                "dbPath" to "/tmp/map.db",
                "schemaVersion" to 3,
                "indexedDocs" to 11,
            ),
        )
        val dayFromMap = JournalDay.fromMap(
            mapOf(
                "date" to "2030-01-02",
                "path" to "daily/2030-01-02.md",
                "turnCount" to 3,
            ),
        )
        val turnFromMap = JournalTurnRecord.fromMap(
            mapOf(
                "turnId" to "turn-map",
                "agentId" to "assistant",
                "threadId" to "thread-map",
                "user" to "hello",
                "assistant" to "hi",
            ),
        )

        assertEquals("notes/today.md", workspaceFile.path)
        assertEquals("hello", workspaceFile.content)
        assertEquals(workspaceFile.toJson(), workspaceFile.toJsonString())
        assertEquals("notes/today.md", WorkspaceFile.fromJson(workspaceFile.toJson()).path)
        assertEquals("notes/mapped.md", workspaceFileFromMap.path)
        assertEquals("mapped", workspaceFileFromMap.content)
        assertEquals("today.md", workspaceEntry.name)
        assertEquals(false, workspaceEntry.isDirectory)
        assertEquals(workspaceEntry.toJson(), workspaceEntry.toJsonString())
        assertEquals(true, workspaceEntryFromMap.isDirectory)
        assertEquals("notes", workspaceEntryFromMap.name)
        assertEquals("journal", searchResult.source)
        assertEquals(true, searchResult.isHybridMatch)
        assertEquals("thread", searchResult.threadId)
        assertEquals(searchResult.toJson(), searchResult.toJsonString())
        assertEquals("memory", searchFromMap.source)
        assertEquals("thread-map", searchFromMap.threadId)
        assertEquals("snippet", snippetFromMap.content)
        assertEquals("turn-map", snippetFromMap.turnId)
        assertEquals(snippetFromMap.toJson(), snippetFromMap.toJsonString())
        assertEquals("thread", recall.threadId)
        assertEquals("note", recall.snippets.single().content)
        assertEquals(listOf("doc-1"), recall.sourceDocIds)
        assertEquals(recall.toJson(), recall.toJsonString())
        assertEquals("thread-map", recallFromMap.threadId)
        assertEquals("mapped snippet", recallFromMap.snippets.single().content)
        assertEquals(listOf("doc-map"), recallFromMap.sourceDocIds)
        assertEquals("ready", stats.status)
        assertEquals(10, stats.indexedDocs)
        assertEquals(stats.toJson(), stats.toJsonString())
        assertEquals("indexing", statsFromMap.status)
        assertEquals(11, statsFromMap.indexedDocs)
        assertEquals("2030-01-01", day.date)
        assertEquals(true, day.legacy)
        assertEquals(day.toJson(), day.toJsonString())
        assertEquals("2030-01-02", dayFromMap.date)
        assertEquals(3, dayFromMap.turnCount)
        assertEquals("turn", turn.turnId)
        assertEquals("assistant", turn.agentId)
        assertEquals(turn.toJson(), turn.toJsonString())
        assertEquals("turn-map", turnFromMap.turnId)
        assertEquals("thread-map", turnFromMap.threadId)
    }

    @Test
    fun evolutionAndGroupModelsExposeFlutterStableFields() {
        val run = EvolutionRun(
            """
            {
              "id":"run-1",
              "agent_id":"assistant",
              "thread_id":"thread",
              "review_type":"skill_consolidation",
              "status":"completed",
              "queued_at":"2030-01-01T00:00:00Z",
              "started_at":"2030-01-01T00:00:01Z",
              "completed_at":"2030-01-01T00:00:02Z",
              "suggestions_count":3,
              "auto_applied_count":1,
              "pending_count":2
            }
            """.trimIndent(),
        )
        val diagnostic = EvolutionDiagnostic(
            """
            {
              "id":"diag-1",
              "created_at":"2030-01-01T00:00:00Z",
              "agent_id":"assistant",
              "thread_id":"thread",
              "review_type":"memory",
              "trigger_reason":"manual",
              "input_summary":{"turns":2},
              "tool_calls":["read","write"],
              "suggestions_count":1,
              "pending_count":1,
              "auto_applied_count":0,
              "apply_result":"queued"
            }
            """.trimIndent(),
        )
        val review = SkillConsolidationReviewResult(
            """
            {
              "reviewed":true,
              "dry_run":false,
              "suggestions_count":2,
              "pending_count":1,
              "pending_id":"pending-1",
              "actions":[{"kind":"merge"}],
              "warnings":["check manually"]
            }
            """.trimIndent(),
        )
        val group = GroupInfo(
            """
            {
              "id":"group-1",
              "name":"Crew",
              "members":["assistant","researcher"],
              "coordinator":"napaxi",
              "created_at":"2030-01-01T00:00:00Z",
              "message_count":5,
              "last_message_preview":"done",
              "last_message_time":"2030-01-01T00:05:00Z",
              "custom_prompt":"Coordinate"
            }
            """.trimIndent(),
        )
        val message = GroupMessage(
            """
            {
              "id":"msg-1",
              "group_id":"group-1",
              "sender":"assistant",
              "content":"Calling researcher",
              "type":"tool_call",
              "timestamp":"2030-01-01T00:00:00Z",
              "tool_call_id":"call-1",
              "tool_name":"delegate",
              "target_agent":"researcher"
            }
            """.trimIndent(),
        )

        assertEquals("run-1", run.id)
        assertEquals(EvolutionRunStatus.Completed, run.status)
        assertEquals(true, run.isFinished)
        assertEquals(3, run.suggestionsCount)
        assertEquals("diag-1", diagnostic.id)
        assertEquals(2, diagnostic.inputSummary.getInt("turns"))
        assertEquals(listOf("read", "write"), diagnostic.toolCalls)
        assertEquals(true, review.reviewed)
        assertEquals(false, review.dryRun)
        assertEquals("pending-1", review.pendingId)
        assertEquals("merge", review.actions.single().getString("kind"))
        assertEquals("group-1", group.id)
        assertEquals(listOf("assistant", "researcher"), group.members)
        assertEquals("done", group.lastMessagePreview)
        assertEquals(GroupMessageType.ToolCall, message.messageType)
        assertEquals(true, message.isDelegation)
        assertEquals(false, message.isUser)
        assertEquals("run-1", EvolutionRun.fromJson(run.toJson()).id)
        assertEquals("assistant", EvolutionRun.fromMap(mapOf("id" to "run-2", "agent_id" to "assistant")).agentId)
        assertEquals("diag-1", EvolutionDiagnostic.fromJsonObject(diagnostic.toJsonObject()).id)
        assertEquals(
            2,
            EvolutionDiagnostic.fromMap(
                mapOf(
                    "id" to "diag-2",
                    "created_at" to "2030-01-01T00:00:00Z",
                    "input_summary" to mapOf("turns" to 2),
                    "tool_calls" to listOf("read", "write"),
                ),
            ).inputSummary.getInt("turns"),
        )
        assertEquals("pending-1", SkillConsolidationReviewResult.fromJson(review.toJson()).pendingId)
        assertEquals("merge", SkillConsolidationReviewResult.fromMap(mapOf("actions" to listOf(mapOf("kind" to "merge")))).actions.single().getString("kind"))
        assertEquals("group-1", GroupInfo.fromJson(group.toJson()).id)
        assertEquals("group-2", GroupInfo.fromMap(mapOf("id" to "group-2", "members" to listOf("assistant"))).id)
        assertEquals("msg-1", GroupMessage.fromJsonObject(message.toJsonObject()).id)
        assertEquals(GroupMessageType.ToolResult, GroupMessage.fromMap(mapOf("type" to "tool_result")).messageType)
    }

    @Test
    fun skillStatusAndCommandModelsExposeFlutterStableFields() {
        val report = SkillStatusReport(
            """
            {
              "entries":[
                {
                  "name":"wallet",
                  "description":"Wallet ops",
                  "source_kind":"bundled",
                  "source":"core",
                  "trust":"Trusted",
                  "enabled":true,
                  "eligible":false,
                  "status":"missing_requirements",
                  "requirements":{"bins":["node"],"any_bins":["python3"],"env":["API_KEY"],"capabilities":["napaxi.tool.shell"]},
                  "missing":{"env":["API_KEY"]},
                  "install_options":[{"kind":"env"}],
                  "warnings":["missing key"],
                  "error":"blocked",
                  "lifecycle":{"state":"active","pinned":true,"use_count":4},
                  "metadata":{"user_invocable":false,"command_tool":"wallet_pay","skill_key":"wallet"},
                  "provenance":{"source_kind":"bundled","managed_by":"sdk","legacy":true},
                  "remediation_actions":[{"id":"set-key","kind":"secret","label":"Set key","requirement":"API_KEY","host_handled":true,"danger_level":"low"}]
                }
              ],
              "ready":1,
              "disabled":2,
              "blocked":3,
              "missing_requirements":4,
              "parse_error":5,
              "security_blocked":6,
              "too_large":7,
              "top_blockers":[{"name":"wallet","status":"blocked"}]
            }
            """.trimIndent(),
        )
        val commands = SkillCommandReport(
            """
            {
              "commands":[
                {
                  "name":"pay",
                  "skill_name":"wallet",
                  "description":"Pay",
                  "dispatch":{"kind":"tool","tool_name":"wallet_pay"},
                  "arg_mode":"json",
                  "eligible":true,
                  "disabled_reason":null
                }
              ],
              "total":1,
              "snapshot_id":"snapshot-1"
            }
            """.trimIndent(),
        )
        val resolution = SkillCommandResolution(
            """{"matched":true,"command":{"name":"pay","skill_name":"wallet"},"args":"{\"amount\":1}"}""",
        )
        val commandRun = SkillCommandRun(
            """
            {
              "success":true,
              "status":"completed",
              "command_name":"pay",
              "skill_name":"wallet",
              "args":"{}",
              "session_key":"app:user:thread",
              "message":"done",
              "dispatch":{"kind":"tool","tool_name":"wallet_pay"}
            }
            """.trimIndent(),
        )
        val commandFromMap = SkillCommand.fromMap(
            mapOf(
                "name" to "map-pay",
                "skillName" to "wallet",
                "description" to "Mapped pay",
                "dispatch" to mapOf("kind" to "tool", "toolName" to "wallet_pay"),
                "argMode" to "json",
                "eligible" to true,
            ),
        )
        val commandsFromMap = SkillCommandReport.fromMap(
            mapOf(
                "commands" to listOf(
                    mapOf(
                        "name" to "map-pay",
                        "skill_name" to "wallet",
                    ),
                ),
                "snapshotId" to "snapshot-map",
            ),
        )
        val dispatchFromMap = SkillCommandDispatch.fromMap(
            mapOf("kind" to "tool", "tool_name" to "wallet_pay"),
        )
        val resolutionFromMap = SkillCommandResolution.fromMap(
            mapOf(
                "matched" to true,
                "command" to mapOf("name" to "map-pay", "skill_name" to "wallet"),
                "args" to "{}",
            ),
        )
        val commandRunFromMap = SkillCommandRun.fromMap(
            mapOf(
                "success" to true,
                "status" to "completed",
                "commandName" to "map-pay",
                "skillName" to "wallet",
                "sessionKey" to "app:user:thread",
                "dispatch" to mapOf("kind" to "tool", "toolName" to "wallet_pay"),
            ),
        )

        val entry = report.entries.single()
        assertEquals("wallet", entry.name)
        assertEquals("bundled", entry.sourceKind)
        assertEquals(false, entry.eligible)
        assertEquals(true, entry.isBlocked)
        assertEquals(listOf("node"), entry.requirements.bins)
        assertEquals(listOf("python3"), entry.requirements.anyBins)
        assertEquals(listOf("API_KEY"), entry.missing.env)
        assertEquals("env", entry.installOptions.single().getString("kind"))
        assertEquals(true, entry.lifecycle.pinned)
        assertEquals(4, entry.lifecycle.useCount)
        assertEquals(false, entry.metadata.userInvocable)
        assertEquals("wallet_pay", entry.metadata.commandTool)
        assertEquals("sdk", entry.provenance.managedBy)
        assertEquals(true, entry.provenance.legacy)
        assertEquals("Set key", entry.remediationActions.single().label)
        assertEquals("Set key", entry.remediationActions.single().title)
        assertEquals("API_KEY", entry.remediationActions.single().requirement)
        assertEquals(4, report.missingRequirements)
        assertEquals(6, report.securityBlocked)
        assertEquals("wallet", report.topBlockers.single().name)
        assertEquals("wallet", SkillStatusReport.fromJson(report.toJson()).entries.single().name)
        assertEquals("wallet", SkillStatusReport.fromMap(mapOf("entries" to listOf(mapOf("name" to "wallet")))).entries.single().name)
        assertEquals("wallet", SkillStatusEntry.fromJson(entry.toJson()).name)
        assertEquals("wallet", SkillStatusEntry.fromMap(mapOf("name" to "wallet", "status" to "ready")).name)
        assertEquals(4, SkillLifecycleSummary.fromJson(entry.lifecycle.toJson()).useCount)
        assertEquals(5, SkillLifecycleSummary.fromMap(mapOf("useCount" to 5)).useCount)
        assertEquals("sdk", SkillProvenance.fromJson(entry.provenance.toJson()).managedBy)
        assertEquals("sdk", SkillProvenance.fromMap(mapOf("managedBy" to "sdk")).managedBy)
        assertEquals(listOf("node"), SkillRequirementSummary.fromJson(entry.requirements.toJson()).bins)
        assertEquals(listOf("python3"), SkillRequirementSummary.fromMap(mapOf("anyBins" to listOf("python3"))).anyBins)
        assertEquals("wallet_pay", SkillOpenClawMetadata.fromJson(entry.metadata.toJson()).commandTool)
        assertEquals("wallet", SkillOpenClawMetadata.fromMap(mapOf("skill_key" to "wallet")).skillKey)
        assertEquals("Set key", SkillRemediationAction.fromJson(entry.remediationActions.single().toJson()).label)
        assertEquals("Set key", SkillRemediationAction.fromMap(mapOf("id" to "set-key", "label" to "Set key")).label)

        assertEquals("pay", commands.commands.single().name)
        assertEquals("wallet", commands.commands.single().skillName)
        assertEquals("wallet_pay", commands.commands.single().dispatch?.toolName)
        assertEquals("json", commands.commands.single().argMode)
        assertEquals("snapshot-1", commands.snapshotId)
        assertEquals(commands.toJson(), commands.toJsonString())
        assertEquals("pay", SkillCommandReport.fromJson(commands.toJson()).commands.single().name)
        assertEquals("snapshot-map", commandsFromMap.snapshotId)
        assertEquals("map-pay", commandsFromMap.commands.single().name)
        assertEquals("map-pay", commandFromMap.name)
        assertEquals("wallet_pay", commandFromMap.dispatch?.toolName)
        assertEquals(commandFromMap.toJson(), commandFromMap.toJsonString())
        assertEquals("wallet_pay", dispatchFromMap.toolName)
        assertEquals(dispatchFromMap.toJson(), dispatchFromMap.toJsonString())
        assertEquals(true, resolution.matched)
        assertEquals("wallet", resolution.command?.skillName)
        assertEquals(resolution.toJson(), resolution.toJsonString())
        assertEquals("wallet", resolutionFromMap.command?.skillName)
        assertEquals(true, commandRun.success)
        assertEquals("pay", commandRun.commandName)
        assertEquals("wallet_pay", commandRun.dispatch?.toolName)
        assertEquals(commandRun.toJson(), commandRun.toJsonString())
        assertEquals("map-pay", commandRunFromMap.commandName)
        assertEquals("wallet_pay", commandRunFromMap.dispatch?.toolName)
    }

    @Test
    fun skillSourceSnapshotRemediationAndCatalogModelsExposeFlutterStableFields() {
        val info = SkillInfo(
            """
            {
              "name":"wallet",
              "version":"1.0",
              "description":"Wallet ops",
              "always":true,
              "allowed_agents":["assistant"],
              "trust":"Trusted",
              "source":"core",
              "keywords":["pay"],
              "tags":["finance"],
              "prompt_content":"Use carefully",
              "content_hash":"hash",
              "lifecycle":{"state":"active","view_count":2},
              "support_files":["README.md"]
            }
            """.trimIndent(),
        )
        val sources = SkillSourceReport(
            """
            {
              "agent_id":"assistant",
              "sources":[{"id":"bundled","kind":"dir","root":"/skills","priority":1,"trust":"Trusted","exists":true,"version":2,"updated_at":"2030-01-01"}]
            }
            """.trimIndent(),
        )
        val refresh = SkillRefreshResult(
            """{"success":true,"agent_id":"assistant","source_id":"bundled","version":3,"recorded_at":"2030-01-02"}""",
        )
        val snapshotList = SkillSnapshotList(
            """{"snapshots":[{"snapshot_id":"snap-1","agent_id":"assistant","purpose":"manual","created_at":"2030-01-01"}],"total":1}""",
        )
        val snapshot = SkillSnapshot(
            """
            {
              "snapshot_id":"snap-1",
              "agent_id":"assistant",
              "purpose":"manual",
              "created_at":"2030-01-01",
              "source_versions":{"bundled":2},
              "catalog_entries":[{"name":"wallet","version":"1.0","description":"Wallet ops","trust":"Trusted","activation_hint":"pay","content_hash":"hash"}],
              "command_entries":[{"name":"pay","skill_name":"wallet"}],
              "status_counts":{"ready":1},
              "catalog_plan":{"next":"refresh"}
            }
            """.trimIndent(),
        )
        val secrets = SkillSecretRequirementReport(
            """{"requirements":[{"skill_name":"wallet","skill_key":"wallet","key":"API_KEY","source":"env","available":true}]}""",
        )
        val runList = SkillRemediationRunList(
            """
            {
              "runs":[{"run_id":"run-1","agent_id":"assistant","skill_name":"wallet","action_id":"set-key","status":"done","requested_at":"2030-01-01","updated_at":"2030-01-02","result":{"ok":true}}],
              "total":1
            }
            """.trimIndent(),
        )
        val usage = SkillUsageRecord(
            """{"skill_name":"wallet","created_at":"2030-01-01","state":"active","pinned":true,"use_count":9}""",
        )
        val curator = CuratorRunSummary(
            """{"dry_run":false,"checked":10,"marked_stale":2,"archived":1,"restored_active":3,"actions":["archive"]}""",
        )
        val supportFile = SkillSupportFileReadResult(
            """{"success":true,"skill_name":"wallet","file_path":"README.md","content":"hello"}""",
        )
        val catalog = CatalogPackagePage(
            """
            {
              "items":[{"slug":"wallet","displayName":"Wallet","summary":"Pay things","latestVersion":{"version":"1.2"},"stats":{"stars":5,"downloads":10},"owner":{"handle":"team","displayName":"Team"},"capabilityTags":["finance"],"updatedAt":1893456000000}],
              "next_cursor":"next"
            }
            """.trimIndent(),
        )
        val search = CatalogSearchResult("""{"results":[{"slug":"wallet","name":"wallet","score":0.5}]}""")
        val snapshotListFromMap = SkillSnapshotList.fromMap(
            mapOf(
                "snapshots" to listOf(
                    mapOf(
                        "snapshotId" to "snap-map",
                        "agentId" to "assistant",
                        "purpose" to "manual",
                    ),
                ),
            ),
        )
        val snapshotFromMap = SkillSnapshot.fromMap(
            mapOf(
                "snapshotId" to "snap-map",
                "agentId" to "assistant",
                "sourceVersions" to mapOf("bundled" to 4),
                "catalogEntries" to listOf(
                    mapOf(
                        "name" to "wallet",
                        "activationHint" to "pay",
                    ),
                ),
                "commandEntries" to listOf(
                    mapOf(
                        "name" to "pay",
                        "skillName" to "wallet",
                    ),
                ),
                "statusCounts" to mapOf("ready" to 2),
                "catalogPlan" to mapOf("next" to "install"),
            ),
        )
        val secretsFromMap = SkillSecretRequirementReport.fromMap(
            mapOf(
                "requirements" to listOf(
                    mapOf(
                        "skillName" to "wallet",
                        "skillKey" to "wallet",
                        "key" to "API_KEY",
                        "available" to true,
                    ),
                ),
            ),
        )
        val runListFromMap = SkillRemediationRunList.fromMap(
            mapOf(
                "runs" to listOf(
                    mapOf(
                        "runId" to "run-map",
                        "agentId" to "assistant",
                        "skillName" to "wallet",
                        "actionId" to "set-key",
                        "result" to mapOf("ok" to true),
                    ),
                ),
            ),
        )
        val usageFromMap = SkillUsageRecord.fromMap(
            mapOf(
                "skillName" to "wallet",
                "state" to "active",
                "use_count" to 7,
            ),
        )
        val curatorFromMap = CuratorRunSummary.fromMap(
            mapOf(
                "dry_run" to false,
                "checked" to 2,
                "actions" to listOf("archive"),
            ),
        )
        val supportFileFromMap = SkillSupportFileReadResult.fromMap(
            mapOf(
                "success" to true,
                "skillName" to "wallet",
                "filePath" to "README.md",
                "content" to "hello",
            ),
        )
        val catalogFromMap = CatalogPackagePage.fromMap(
            mapOf(
                "items" to listOf(
                    mapOf(
                        "slug" to "wallet",
                        "displayName" to "Wallet",
                        "latestVersion" to mapOf("version" to "1.3"),
                    ),
                ),
                "nextCursor" to "cursor-map",
            ),
        )
        val searchFromMap = CatalogSearchResult.fromMap(
            mapOf(
                "results" to listOf(
                    mapOf(
                        "slug" to "wallet",
                        "score" to 0.75,
                    ),
                ),
            ),
        )
        val installResultFromMap = SkillInstallResult.fromMap(
            mapOf(
                "name" to "wallet",
                "success" to true,
            ),
        )
        val install = SkillInstallInput(
            skillMd = "# Wallet",
            extraFiles = listOf(SkillInstallExtraFile.fromBytes(path = "README.md", bytes = "hello".toByteArray())),
        )
        val installJson = JSONObject(install.toInstallPayloadJson())

        assertEquals("wallet", info.name)
        assertEquals(true, info.always)
        assertEquals(listOf("assistant"), info.allowedAgents)
        assertEquals("Use carefully", info.promptContent)
        assertEquals(2, info.lifecycle.viewCount)
        assertEquals(listOf("README.md"), info.supportFiles)
        assertEquals("wallet", SkillInfo.fromJson(info.toJson()).name)
        assertEquals("wallet", SkillInfo.fromMap(mapOf("name" to "wallet", "support_files" to listOf("README.md"))).name)
        assertEquals("assistant", sources.agentId)
        assertEquals("bundled", sources.sources.single().id)
        assertEquals(true, sources.sources.single().exists)
        assertEquals("assistant", SkillSourceReport.fromJson(sources.toJson()).agentId)
        assertEquals("bundled", SkillSourceReport.fromMap(mapOf("agentId" to "assistant", "sources" to listOf(mapOf("id" to "bundled")))).sources.single().id)
        assertEquals("bundled", SkillSourceEntry.fromJson(sources.sources.single().toJson()).id)
        assertEquals("bundled", SkillSourceEntry.fromMap(mapOf("id" to "bundled", "exists" to true)).id)
        assertEquals(true, refresh.success)
        assertEquals("bundled", refresh.sourceId)
        assertEquals("bundled", SkillRefreshResult.fromJson(refresh.toJson()).sourceId)
        assertEquals("bundled", SkillRefreshResult.fromMap(mapOf("success" to true, "sourceId" to "bundled")).sourceId)
        assertEquals("snap-1", snapshotList.snapshots.single().snapshotId)
        assertEquals(snapshotList.toJson(), snapshotList.toJsonString())
        assertEquals("snap-map", snapshotListFromMap.snapshots.single().snapshotId)
        assertEquals(2, snapshot.sourceVersions["bundled"])
        assertEquals("pay", snapshot.catalogEntries.single().activationHint)
        assertEquals("wallet", snapshot.commandEntries.single().skillName)
        assertEquals(1, snapshot.statusCounts.getInt("ready"))
        assertEquals("refresh", snapshot.catalogPlan.getString("next"))
        assertEquals(snapshot.toJson(), snapshot.toJsonString())
        assertEquals(4, snapshotFromMap.sourceVersions["bundled"])
        assertEquals("pay", snapshotFromMap.catalogEntries.single().activationHint)
        assertEquals("wallet", snapshotFromMap.commandEntries.single().skillName)
        assertEquals(2, snapshotFromMap.statusCounts.getInt("ready"))
        assertEquals("install", snapshotFromMap.catalogPlan.getString("next"))
        assertEquals("API_KEY", secrets.requirements.single().key)
        assertEquals(true, secrets.requirements.single().available)
        assertEquals(secrets.toJson(), secrets.toJsonString())
        assertEquals("API_KEY", secretsFromMap.requirements.single().key)
        assertEquals("run-1", runList.runs.single().runId)
        assertEquals(true, runList.runs.single().result?.getBoolean("ok"))
        assertEquals(runList.toJson(), runList.toJsonString())
        assertEquals("run-map", runListFromMap.runs.single().runId)
        assertEquals(9, usage.useCount)
        assertEquals(7, usageFromMap.useCount)
        assertEquals(usage.toJson(), usage.toJsonString())
        assertEquals(false, curator.dryRun)
        assertEquals(listOf("archive"), curator.actions)
        assertEquals(2, curatorFromMap.checked)
        assertEquals(curator.toJson(), curator.toJsonString())
        assertEquals("README.md", supportFile.filePath)
        assertEquals("wallet", supportFileFromMap.skillName)
        assertEquals(supportFile.toJson(), supportFile.toJsonString())
        assertEquals("Wallet", catalog.items.single().name)
        assertEquals("1.2", catalog.items.single().version)
        assertEquals(5, catalog.items.single().stars)
        assertEquals("team", catalog.items.single().owner)
        assertEquals(listOf("finance"), catalog.items.single().tags)
        assertEquals(1893456000000L, catalog.items.single().updatedAt)
        assertEquals("next", catalog.nextCursor)
        assertEquals("1.3", catalogFromMap.items.single().version)
        assertEquals("cursor-map", catalogFromMap.nextCursor)
        assertEquals(catalog.toJson(), catalog.toJsonString())
        assertEquals("wallet", search.results.single().slug)
        assertEquals(0.75, searchFromMap.results.single().score, 0.001)
        assertEquals(search.toJson(), search.toJsonString())
        assertEquals("wallet", installResultFromMap.name)
        assertEquals(true, installResultFromMap.success)
        assertEquals(installResultFromMap.toJson(), installResultFromMap.toJsonString())
        assertEquals("# Wallet", installJson.getString("skill_md"))
        assertEquals("hello", install.extraFiles.single().bytes.toString(Charsets.UTF_8))
        assertEquals("aGVsbG8=", installJson.getJSONArray("extra_files").getJSONObject(0).getString("content_base64"))
    }

    @Test
    fun fileBridgeModelsDecodeFlutterStableShapes() {
        val resolved = ResolvedFile.fromJson(
            """
            {
              "sandbox_path":"/workspace/out.png",
              "real_path":"/data/user/0/app/files/workspace/out.png",
              "filename":"out.png",
              "mime_type":"image/png",
              "is_image":true,
              "is_directory":false,
              "exists":true,
              "size_bytes":4096
            }
            """.trimIndent(),
        )
        val entry = WorkspaceFileInfo.fromJson(
            """
            {
              "name":"out.png",
              "sandbox_path":"/workspace/out.png",
              "real_path":"/data/user/0/app/files/workspace/out.png",
              "mime_type":"image/png",
              "is_directory":false,
              "size_bytes":4096,
              "modified":1700000000000
            }
            """.trimIndent(),
        )

        assertEquals("/workspace/out.png", resolved.sandboxPath)
        assertEquals("/data/user/0/app/files/workspace/out.png", resolved.realPath)
        assertEquals("out.png", resolved.filename)
        assertEquals("image/png", resolved.mimeType)
        assertEquals(true, resolved.isImage)
        assertEquals(false, resolved.isDirectory)
        assertEquals(true, resolved.exists)
        assertEquals(4096L, resolved.sizeBytes)
        assertEquals("/workspace/out.png", ResolvedFile.fromMap(resolved.toJsonObject().toStringMap()).sandboxPath)
        assertEquals(resolved.toJson(), resolved.toJsonString())

        assertEquals("out.png", entry.name)
        assertEquals("/workspace/out.png", entry.sandboxPath)
        assertEquals("/data/user/0/app/files/workspace/out.png", entry.realPath)
        assertEquals("image/png", entry.mimeType)
        assertEquals(false, entry.isDirectory)
        assertEquals(4096L, entry.sizeBytes)
        assertEquals(1700000000000L, entry.modified)
        assertEquals("out.png", WorkspaceFileInfo.fromMap(entry.toJsonObject().toStringMap()).name)
        assertEquals(entry.toJson(), entry.toJsonString())
    }

    @Test
    fun fileBridgeModelsDecodeCamelCaseAndDefaults() {
        val resolved = ResolvedFile.fromJson(
            """
            {
              "sandboxPath":"/workspace/report.pdf",
              "realPath":"/data/user/0/app/files/workspace/report.pdf",
              "filename":"report.pdf",
              "mimeType":"application/pdf",
              "isImage":false,
              "isDirectory":false,
              "exists":true,
              "sizeBytes":2048
            }
            """.trimIndent(),
        )
        val defaultResolved = ResolvedFile.fromJson("{}")
        val entry = WorkspaceFileInfo.fromJson(
            """
            {
              "name":"notes",
              "sandboxPath":"/workspace/notes",
              "realPath":"/data/user/0/app/files/workspace/notes",
              "mimeType":"inode/directory",
              "isDirectory":true,
              "sizeBytes":0,
              "modified":1700000000001
            }
            """.trimIndent(),
        )
        val defaultEntry = WorkspaceFileInfo.fromJson("{}")

        assertEquals("/workspace/report.pdf", resolved.sandboxPath)
        assertEquals("/data/user/0/app/files/workspace/report.pdf", resolved.realPath)
        assertEquals("application/pdf", resolved.mimeType)
        assertEquals(false, resolved.isImage)
        assertEquals(false, resolved.isDirectory)
        assertEquals(true, resolved.exists)
        assertEquals(2048L, resolved.sizeBytes)

        assertEquals("", defaultResolved.sandboxPath)
        assertEquals("", defaultResolved.realPath)
        assertEquals("", defaultResolved.filename)
        assertEquals("application/octet-stream", defaultResolved.mimeType)
        assertEquals(false, defaultResolved.isImage)
        assertEquals(false, defaultResolved.isDirectory)
        assertEquals(false, defaultResolved.exists)
        assertEquals(null, defaultResolved.sizeBytes)

        assertEquals("notes", entry.name)
        assertEquals("/workspace/notes", entry.sandboxPath)
        assertEquals("/data/user/0/app/files/workspace/notes", entry.realPath)
        assertEquals("inode/directory", entry.mimeType)
        assertEquals(true, entry.isDirectory)
        assertEquals(0L, entry.sizeBytes)
        assertEquals(1700000000001L, entry.modified)

        assertEquals("", defaultEntry.name)
        assertEquals("", defaultEntry.sandboxPath)
        assertEquals("", defaultEntry.realPath)
        assertEquals("application/octet-stream", defaultEntry.mimeType)
        assertEquals(false, defaultEntry.isDirectory)
        assertEquals(0L, defaultEntry.sizeBytes)
        assertEquals(0L, defaultEntry.modified)
    }

    @Test
    fun apkInstallResultDecodesFlutterStableShapeAndFallbacks() {
        val opened = NapaxiApkInstallResult.fromJson(
            """
            {
              "success":true,
              "installerOpened":true,
              "permissionRequired":true,
              "apkPath":"/tmp/app.apk",
              "code":"REQUEST_INSTALL_PACKAGES"
            }
            """.trimIndent(),
        )
        val legacyPath = NapaxiApkInstallResult.fromJson("""{"success":true,"path":"/tmp/legacy.apk"}""")
        val snakeCase = NapaxiApkInstallResult.fromJson(
            """
            {
              "success":false,
              "installer_opened":false,
              "permission_required":true,
              "apk_path":"/tmp/snake.apk",
              "error":"permission required",
              "code":"REQUEST_INSTALL_PACKAGES"
            }
            """.trimIndent(),
        )
        val defaultResult = NapaxiApkInstallResult.fromJson("")
        val failed = NapaxiApkInstallResult(
            success = false,
            error = "APK installation is only supported on Android.",
            code = "unsupported",
        ).toJsonObject()

        assertEquals(true, opened.success)
        assertEquals(true, opened.installerOpened)
        assertEquals(true, opened.permissionRequired)
        assertEquals("/tmp/app.apk", opened.apkPath)
        assertEquals("REQUEST_INSTALL_PACKAGES", opened.code)
        assertEquals("/tmp/legacy.apk", legacyPath.apkPath)
        assertEquals(false, snakeCase.installerOpened)
        assertEquals(true, snakeCase.permissionRequired)
        assertEquals("/tmp/snake.apk", snakeCase.apkPath)
        assertEquals("permission required", snakeCase.error)
        assertEquals("REQUEST_INSTALL_PACKAGES", snakeCase.code)

        assertEquals(false, defaultResult.success)
        assertEquals(false, defaultResult.installerOpened)
        assertEquals(false, defaultResult.permissionRequired)
        assertEquals(null, defaultResult.apkPath)
        assertEquals(null, defaultResult.error)
        assertEquals(null, defaultResult.code)

        assertEquals(false, failed.getBoolean("success"))
        assertEquals(false, failed.getBoolean("installerOpened"))
        assertEquals(false, failed.getBoolean("permissionRequired"))
        assertEquals("APK installation is only supported on Android.", failed.getString("error"))
        assertEquals("unsupported", failed.getString("code"))
        assertEquals("/tmp/app.apk", NapaxiApkInstallResult.fromJsonObject(opened.toJsonObject()).apkPath)
        assertEquals(
            "/tmp/map.apk",
            NapaxiApkInstallResult.fromMap(
                mapOf(
                    "success" to true,
                    "installerOpened" to true,
                    "permissionRequired" to false,
                    "apkPath" to "/tmp/map.apk",
                ),
            ).apkPath,
        )
        assertEquals(opened.toJson(), opened.toJsonString())
    }

    @Test
    fun acceptedAgentTriggerExposesFlutterStyleFields() {
        val accepted = AcceptedAgentTrigger(
            """
            {
              "trigger":{
                "request_id":"trigger-1",
                "provider_id":"provider.app",
                "agent_id":"calendar_agent",
                "message":"Summarize my day",
                "source":"calendar",
                "event_type":"daily",
                "payload":{"day":"today"},
                "created_at":"2030-01-01T00:00:00Z",
                "expires_at":"2030-01-01T00:10:00Z",
                "nonce":"nonce-1",
                "idempotency_key":"idem-1",
                "host_instance_id":"host-1",
                "signature_algorithm":"hmac-sha256-v1",
                "signature":"sig"
              },
              "status":"accepted",
              "display_name":"Calendar Agent"
            }
            """.trimIndent(),
        )

        assertEquals("trigger-1", accepted.requestId)
        assertEquals("provider.app", accepted.providerId)
        assertEquals("calendar_agent", accepted.agentId)
        assertEquals("Summarize my day", accepted.message)
        assertEquals("calendar", accepted.source)
        assertEquals("daily", accepted.eventType)
        assertEquals("accepted", accepted.status)
        assertEquals("Calendar Agent", accepted.displayName)
        assertEquals("trigger-1", accepted.request?.requestId)
        assertEquals("calendar_agent", accepted.request?.agentId)
        assertEquals("""{"day":"today"}""", accepted.request?.payloadJson)
        assertEquals("hmac-sha256-v1", accepted.request?.signatureAlgorithm)
        assertTrue(accepted.requestJson.contains("trigger-1"))
    }

    @Test
    fun agentAppModelsExposeFlutterStableFields() {
        val manifest = AgentAppActionManifest(
            actionId = "create_event",
            toolName = "app_action_create_event",
            description = "Create event",
            parameters = JSONObject("""{"type":"object"}"""),
            executionModes = listOf("activity"),
            timeoutSeconds = 300,
        )
        val manifestFromMap: AgentAppPackageAction = AgentAppActionManifest.fromMap(
            mapOf(
                "action_id" to "create_event",
                "tool_name" to "app_action_create_event",
                "description" to "Create event",
                "parameters" to mapOf("type" to "object"),
                "execution_modes" to listOf("activity"),
                "timeout_seconds" to 300,
            ),
        )
        val packageDef = AgentAppPackage(
            """
            {
              "provider_id":"provider.app",
              "agent_id":"calendar_agent",
              "display_name":"Calendar Agent",
              "description":"Calendar actions",
              "system_prompt":"Use calendar context",
              "actions":[
                {
                  "action_id":"create_event",
                  "tool_name":"app_action_create_event",
                  "description":"Create event",
                  "parameters":{"type":"object"},
                  "result_schema":{"type":"object"},
                  "risk":"high",
                  "confirmation_policy":"provider_required",
                  "execution_modes":["activity"],
                  "timeout_seconds":300
                }
              ],
              "handoff":{"mode":"activity"},
              "result":{"installed":true},
              "install_binding":{
                "platform":"android",
                "app_package_name":"provider.app",
                "activity_name":"ProviderActivity",
                "signing_cert_sha256":"abc",
                "installed_at":"2030-01-01T00:00:00Z",
                "install_request_id":"install-1",
                "protocol_version":2,
                "host_package_name":"host.app",
                "host_signing_cert_sha256":"host-cert",
                "host_instance_id":"host-1",
                "host_shared_secret":"secret",
                "ios_bundle_id":"ios.bundle",
                "ios_team_id":"TEAM",
                "install_url":"napaxi-provider://install",
                "action_url":"napaxi-provider://action",
                "universal_link_domain":"example.test",
                "host_bundle_id":"host.bundle",
                "host_team_id":"HOST",
                "host_callback_scheme":"napaxi",
                "background_trigger_supported":true,
                "host_background_trigger_service":"TriggerService"
              },
              "created_at":"2030-01-01T00:00:00Z",
              "updated_at":"2030-01-02T00:00:00Z"
            }
            """.trimIndent(),
        )
        val proposal = AgentAppActionProposal(
            """
            {
              "request_id":"request-1",
              "provider_id":"provider.app",
              "agent_id":"calendar_agent",
              "action_id":"create_event",
              "tool_name":"app_action_create_event",
              "arguments":{"title":"Demo"},
              "user_intent_summary":"Create a demo event",
              "created_at":"2030-01-01T00:00:00Z",
              "expires_at":"2030-01-01T00:10:00Z",
              "nonce":"nonce",
              "idempotency_key":"idem",
              "callback":{"scheme":"napaxi"},
              "risk":"high",
              "confirmation_policy":"provider_required",
              "host_instance_id":"host-1",
              "signature_algorithm":"hmac-sha256-v1",
              "signature":"sig"
            }
            """.trimIndent(),
        )
        val result = AgentAppActionResult(
            """
            {
              "request_id":"request-1",
              "status":"succeeded",
              "result":{"event_id":"event-1"},
              "provider_trace_id":"trace-1",
              "completed_at":"2030-01-01T00:01:00Z",
              "signature":"result-sig"
            }
            """.trimIndent(),
        )
        val record = AgentAppActionRecord(
            """
            {
              "proposal":${proposal.rawJson},
              "status":"succeeded",
              "result":${result.rawJson},
              "created_at":"2030-01-01T00:00:00Z",
              "updated_at":"2030-01-01T00:01:00Z"
            }
            """.trimIndent(),
        )

        assertEquals("provider.app", packageDef.providerId)
        assertEquals("Calendar Agent", packageDef.displayName)
        assertEquals("Use calendar context", packageDef.systemPrompt)
        assertEquals(true, packageDef.result.getBoolean("installed"))
        assertEquals("activity", packageDef.handoff.getString("mode"))
        assertEquals("create_event", packageDef.actions.single().actionId)
        assertEquals("object", packageDef.actions.single().parameters.getString("type"))
        assertEquals(listOf("activity"), packageDef.actions.single().executionModes)
        assertEquals(300, packageDef.actions.single().timeoutSeconds)
        assertEquals("host.app", packageDef.installBinding?.hostPackageName)
        assertEquals("ios.bundle", packageDef.installBinding?.iosBundleId)
        assertEquals("napaxi", packageDef.installBinding?.hostCallbackScheme)
        assertEquals(true, packageDef.installBinding?.backgroundTriggerSupported)
        assertEquals("2030-01-02T00:00:00Z", packageDef.updatedAt)
        assertEquals(packageDef.rawJson, packageDef.toJsonString())
        assertEquals("create_event", manifest.actionId)
        assertEquals("provider_required", manifest.confirmationPolicy)
        assertEquals("object", manifest.parameters.getString("type"))
        assertEquals("activity", manifestFromMap.executionModes.single())
        assertEquals("provider_required", manifestFromMap.confirmationPolicy)
        assertEquals(300, manifestFromMap.timeoutSeconds)
        assertTrue(manifest.toJsonString().contains(""""action_id":"create_event""""))

        assertEquals("request-1", proposal.requestId)
        assertEquals("Create a demo event", proposal.userIntentSummary)
        assertEquals("Demo", proposal.arguments.getString("title"))
        assertEquals("napaxi", proposal.callback.getString("scheme"))
        assertEquals("hmac-sha256-v1", proposal.signatureAlgorithm)
        assertEquals("sig", proposal.signature)

        assertEquals("request-1", result.requestId)
        assertEquals("succeeded", result.status)
        assertEquals("event-1", result.result.getString("event_id"))
        assertEquals("trace-1", result.providerTraceId)
        assertEquals("result-sig", result.signature)
        assertEquals(result.rawJson, result.toJsonString())

        assertEquals("request-1", record.proposal.requestId)
        assertEquals("succeeded", record.status)
        assertEquals("event-1", record.result?.result?.getString("event_id"))
        assertEquals("2030-01-01T00:01:00Z", record.updatedAt)

        val constructedProposal = AgentAppActionProposal(
            requestId = "request-2",
            providerId = "provider.app",
            agentId = "calendar_agent",
            actionId = "create_event",
            toolName = "app_action_create_event",
            arguments = JSONObject("""{"title":"Typed"}"""),
            userIntentSummary = "Create a typed event",
            createdAt = "2030-01-01T00:00:00Z",
            expiresAt = "2030-01-01T00:10:00Z",
            nonce = "nonce-2",
            idempotencyKey = "idem-2",
            callback = JSONObject("""{"scheme":"napaxi"}"""),
            signatureAlgorithm = "hmac-sha256-v1",
            signature = "sig-2",
        )
        val constructedResult = AgentAppActionResult(
            requestId = constructedProposal.requestId,
            status = "succeeded",
            result = JSONObject("""{"event_id":"event-2"}"""),
            providerTraceId = "trace-2",
            completedAt = "2030-01-01T00:02:00Z",
        )
        val constructedPackage = AgentAppPackage(
            providerId = "provider.app",
            agentId = "calendar_agent",
            displayName = "Calendar Agent",
            description = "Calendar actions",
            systemPrompt = "Use calendar context",
            actions = listOf(manifest),
            handoff = JSONObject("""{"mode":"activity"}"""),
            result = JSONObject("""{"installed":true}"""),
            installBinding = packageDef.installBinding,
            createdAt = "2030-01-01T00:00:00Z",
            updatedAt = "2030-01-02T00:00:00Z",
        )
        val constructedRecord = AgentAppActionRecord(
            proposal = constructedProposal,
            status = constructedResult.status,
            result = constructedResult,
            createdAt = "2030-01-01T00:00:00Z",
            updatedAt = "2030-01-01T00:02:00Z",
        )

        assertEquals("Typed", constructedProposal.arguments.getString("title"))
        assertEquals("sig-2", constructedProposal.signature)
        assertEquals("event-2", constructedResult.result.getString("event_id"))
        assertEquals("Calendar Agent", constructedPackage.displayName)
        assertEquals("create_event", constructedPackage.actions.single().actionId)
        assertEquals("host.app", constructedPackage.installBinding?.hostPackageName)
        assertEquals("event-2", constructedRecord.result?.result?.getString("event_id"))
        val bindingFromJson = AgentAppInstallBinding.fromJsonObject(packageDef.installBinding!!.toJsonObject())
        val bindingFromMap = AgentAppInstallBinding.fromMap(
            mapOf(
                "platform" to "android",
                "app_package_name" to "provider.app",
                "activity_name" to "ProviderActivity",
                "signing_cert_sha256" to "abc",
                "installed_at" to "2030-01-01T00:00:00Z",
                "install_request_id" to "install-2",
                "host_package_name" to "host.app",
                "background_trigger_supported" to true,
                "host_background_trigger_service" to "TriggerService",
            ),
        )
        assertEquals("ProviderActivity", bindingFromJson.activityName)
        assertEquals("host.app", bindingFromJson.hostPackageName)
        assertEquals("install-2", bindingFromMap.installRequestId)
        assertEquals(1, bindingFromMap.protocolVersion)
        assertEquals(true, bindingFromMap.backgroundTriggerSupported)
        assertEquals("TriggerService", bindingFromMap.hostBackgroundTriggerService)
        assertTrue(bindingFromJson.toJsonString().contains(""""install_request_id":"install-1""""))
        val minimalBindingJson = AgentAppInstallBinding(
            platform = "android",
            appPackageName = "provider.app",
            activityName = "ProviderActivity",
            signingCertSha256 = "abc",
            installedAt = "2030-01-01T00:00:00Z",
            installRequestId = "install-min",
            protocolVersion = 1,
        ).toJsonObject()
        assertEquals(false, minimalBindingJson.has("host_package_name"))
        assertEquals(false, minimalBindingJson.has("host_shared_secret"))
        assertEquals(false, minimalBindingJson.has("background_trigger_supported"))
        assertEquals(false, minimalBindingJson.has("host_background_trigger_service"))
        assertEquals("request-2", AgentAppActionProposal.fromJsonObject(constructedProposal.toJsonObject()).requestId)
        assertEquals(
            "provider.app",
            AgentAppPackage.fromMap(
                mapOf(
                    "provider_id" to "provider.app",
                    "agent_id" to "calendar_agent",
                    "display_name" to "Calendar Agent",
                ),
            ).providerId,
        )
        assertEquals(
            "succeeded",
            AgentAppActionResult.fromMap(
                mapOf(
                    "request_id" to "request-2",
                    "status" to "succeeded",
                    "result" to mapOf("event_id" to "event-2"),
                ),
            ).status,
        )
        assertEquals(
            "calendar_agent",
            decodeAgentAppPackages("[${constructedPackage.rawJson}]").single().agentId,
        )
        assertEquals(
            "calendar_agent",
            decodeAgentAppPackages("""{"packages":[${constructedPackage.rawJson}]}""").single().agentId,
        )
        assertEquals(
            "request-2",
            decodeAgentAppActionRecords("[${constructedRecord.rawJson}]").single().proposal.requestId,
        )
        assertEquals(
            "request-2",
            decodeAgentAppActionRecords("""{"proposals":[${constructedRecord.rawJson}]}""").single().proposal.requestId,
        )
    }

    @Test
    fun capabilityModelsExposeFlutterStableFields() {
        val definition = NapaxiCapabilityDefinition(
            """
            {
              "id":"napaxi.tool.browser",
              "kind":"tool",
              "version":"1",
              "platforms":["android","ios"],
              "config_schema":{"type":"object"},
              "risk":"medium",
              "requirements":["host_browser"],
              "default_enabled":false,
              "activation":"host"
            }
            """.trimIndent(),
        )
        val status = NapaxiCapabilityStatus(
            """
            {
              "definition":${definition.rawJson},
              "registered":true,
              "available":false,
              "enabled":false,
              "unavailable_reason":"missing host browser"
            }
            """.trimIndent(),
        )
        val profile = NapaxiCapabilityProfile(
            platform = "android",
            supportedCapabilities = listOf("napaxi.tool.browser"),
            disabledCapabilities = listOf("napaxi.tool.shell"),
        )
        val selection = NapaxiCapabilitySelection(
            enabledCapabilities = listOf("napaxi.tool.browser"),
            disabledCapabilities = listOf("napaxi.tool.shell"),
            config = JSONObject("""{"napaxi.tool.browser":{"enabled":true}}"""),
        )
        val constructedDefinition = NapaxiCapabilityDefinition(
            id = "napaxi.llm.openai",
            kind = "llm_provider",
            version = "1",
            platforms = listOf("android"),
            configSchema = JSONObject("""{"type":"object"}"""),
            risk = "medium",
            requirements = listOf("api_key"),
            defaultEnabled = true,
            activation = "config",
        )
        val definitionFromMap = NapaxiCapabilityDefinition.fromMap(
            mapOf(
                "id" to "napaxi.tool.shell",
                "kind" to "tool",
                "version" to "1",
                "platforms" to listOf("android"),
                "config_schema" to mapOf("type" to "object"),
                "risk" to "high",
                "requirements" to listOf("host_shell"),
                "default_enabled" to false,
                "activation" to "host",
            ),
        )
        val statusFromMap = NapaxiCapabilityStatus.fromMap(
            mapOf(
                "definition" to mapOf(
                    "id" to "napaxi.tool.browser",
                    "kind" to "tool",
                    "version" to "1",
                    "platforms" to listOf("android"),
                ),
                "registered" to true,
                "available" to true,
                "enabled" to true,
            ),
        )
        val constructedStatus = NapaxiCapabilityStatus(
            definition = constructedDefinition,
            registered = true,
            available = true,
            enabled = false,
            unavailableReason = null,
        )
        val platformAgnosticProfile = NapaxiCapabilityProfile(platform = null)

        assertEquals("napaxi.tool.browser", definition.id)
        assertEquals("tool", definition.kind)
        assertEquals("1", definition.version)
        assertEquals(listOf("android", "ios"), definition.platforms)
        assertEquals("object", definition.configSchema.getString("type"))
        assertEquals("medium", definition.risk)
        assertEquals(listOf("host_browser"), definition.requirements)
        assertEquals(false, definition.defaultEnabled)
        assertEquals("host", definition.activation)

        assertEquals("napaxi.tool.browser", status.definition.id)
        assertEquals(true, status.registered)
        assertEquals(false, status.available)
        assertEquals(false, status.enabled)
        assertEquals("missing host browser", status.unavailableReason)
        assertEquals("napaxi.llm.openai", constructedDefinition.id)
        assertEquals("config", constructedDefinition.activation)
        assertEquals(constructedDefinition.toJson(), constructedDefinition.toJsonString())
        assertEquals("napaxi.tool.shell", definitionFromMap.id)
        assertEquals("object", definitionFromMap.configSchema.getString("type"))
        assertEquals(listOf("host_shell"), definitionFromMap.requirements)
        assertEquals("napaxi.tool.browser", statusFromMap.definition.id)
        assertEquals(true, statusFromMap.enabled)
        assertEquals(constructedStatus.toJson(), constructedStatus.toJsonString())
        assertEquals(false, constructedStatus.toJsonObject().has("unavailable_reason"))
        assertEquals("napaxi.llm.openai", NapaxiCapabilityStatus.fromJson(constructedStatus.toJson()).definition.id)
        assertEquals(listOf("napaxi.tool.browser"), profile.supportedCapabilities)
        assertEquals(listOf("napaxi.tool.shell"), profile.disabledCapabilities)
        assertEquals("napaxi.tool.shell", profile.toJsonObject().getJSONArray("disabled_capabilities").getString(0))
        assertEquals(profile.toJson(), profile.toJsonString())
        assertEquals(false, platformAgnosticProfile.toJsonObject().has("platform"))
        assertEquals(listOf("napaxi.tool.browser"), selection.enabledCapabilities)
        assertEquals(listOf("napaxi.tool.shell"), selection.disabledCapabilities)
        assertEquals(true, selection.config.getJSONObject("napaxi.tool.browser").getBoolean("enabled"))
        assertEquals(selection.toJson(), selection.toJsonString())
        assertEquals(
            "napaxi.tool.browser",
            decodeCapabilityDefinitions("[${definition.rawJson}]").single().id,
        )
        assertEquals(
            "napaxi.tool.browser",
            decodeCapabilityDefinitions("""{"definitions":[${definition.rawJson}]}""").single().id,
        )
        assertEquals(
            "napaxi.tool.browser",
            decodeCapabilityStatuses("[${status.rawJson}]").single().definition.id,
        )
        assertEquals(
            "napaxi.tool.browser",
            decodeCapabilityStatuses("""{"statuses":[${status.rawJson}]}""").single().definition.id,
        )

        val scenario = NapaxiScenarioPack(
            id = "napaxi.scenario.mobile_development",
            version = "1",
            label = "Developer Workbench",
            description = "Developer scene",
            risk = "critical",
            activation = "host_policy",
            executionPlanes = listOf("core", "host_bridge", "remote_workspace"),
            requiredCapabilities = listOf("napaxi.service.remote_workspace"),
            recommendedCapabilities = listOf("napaxi.mcp.runtime"),
            optionalCapabilities = listOf("napaxi.service.automation"),
            uiSurfaces = listOf("chat", "diff_view"),
            settingsContributions = listOf(
                NapaxiScenarioSettingsContribution(
                    id = "settings.git",
                    capabilityId = "napaxi.tool.git",
                    placement = "scenario_settings",
                    title = "Git",
                    schema = JSONObject(
                        mapOf(
                            "type" to "object",
                            "properties" to mapOf(
                                "token" to mapOf("type" to "secret"),
                            ),
                        ),
                    ),
                    actions = listOf("save", "clear_credentials"),
                ),
            ),
            uiContributions = listOf(
                NapaxiScenarioUiContribution(
                    id = "ui.repo_workbench",
                    capabilityId = "napaxi.tool.git",
                    placement = "left_menu",
                    title = "Repositories",
                    icon = "folder_git",
                    renderer = "repo_workbench",
                    dataSources = JSONObject(mapOf("repositories" to "git.repositories")),
                    actions = listOf("open_repository", "search_files"),
                ),
            ),
            memoryScopes = listOf("project"),
            tags = listOf("developer"),
        )
        val scenarioStatus = NapaxiScenarioStatus(
            definition = scenario,
            registered = true,
            available = false,
            enabled = false,
            missingRequiredCapabilities = listOf("napaxi.tool.git"),
            disabledRequiredCapabilities = listOf("napaxi.policy.approval"),
            unavailableReasons = listOf("requires host support"),
        )
        val activationPlan = NapaxiScenarioActivationPlan(
            supportedCapabilities = listOf("napaxi.service.remote_workspace"),
            enabledCapabilities = listOf("napaxi.tool.shell_remote"),
            hostRequiredCapabilities = listOf("napaxi.policy.approval"),
            remoteRequiredCapabilities = listOf("napaxi.tool.shell_remote"),
            policyRequiredCapabilities = listOf("napaxi.policy.approval"),
            warnings = listOf("critical risk"),
        )
        val resolution = NapaxiScenarioResolution(
            status = scenarioStatus,
            activationPlan = activationPlan,
        )

        assertEquals("host_policy", scenario.activation)
        assertEquals(listOf("remote_workspace"), scenario.executionPlanes.filter { it == "remote_workspace" })
        assertEquals("napaxi.scenario.mobile_development", NapaxiScenarioPack.fromJson(scenario.toJson()).id)
        assertEquals("settings.git", scenario.settingsContributions.single().id)
        assertEquals("secret", scenario.settingsContributions.single().schema.getJSONObject("properties").getJSONObject("token").getString("type"))
        assertEquals("clear_credentials", scenario.settingsContributions.single().actions.last())
        assertEquals("ui.repo_workbench", scenario.uiContributions.single().id)
        assertEquals("repo_workbench", scenario.uiContributions.single().renderer)
        assertEquals("git.repositories", scenario.uiContributions.single().dataSources.getString("repositories"))
        assertEquals("search_files", scenario.uiContributions.single().actions.last())
        assertEquals("napaxi.tool.git", scenarioStatus.missingRequiredCapabilities.single())
        assertEquals("napaxi.policy.approval", scenarioStatus.disabledRequiredCapabilities.single())
        assertEquals("requires host support", scenarioStatus.unavailableReasons.single())
        assertEquals("napaxi.tool.shell_remote", activationPlan.enabledCapabilities.single())
        assertEquals("napaxi.tool.shell_remote", activationPlan.remoteRequiredCapabilities.single())
        assertEquals("napaxi.policy.approval", activationPlan.policyRequiredCapabilities.single())
        assertEquals("napaxi.scenario.mobile_development", resolution.status.definition.id)
        assertEquals("napaxi.tool.shell_remote", resolution.activationPlan.enabledCapabilities.single())
        assertEquals(
            "napaxi.scenario.mobile_development",
            decodeScenarioPacks("[${scenario.rawJson}]").single().id,
        )
        assertEquals(
            "napaxi.scenario.mobile_development",
            decodeScenarioPacks("""{"scenarios":[${scenario.rawJson}]}""").single().id,
        )
        assertEquals(
            "napaxi.tool.git",
            decodeScenarioStatuses("[${scenarioStatus.rawJson}]").single().missingRequiredCapabilities.single(),
        )
        assertEquals(
            "napaxi.tool.shell_remote",
            decodeScenarioResolution(resolution.toJson())!!.activationPlan.remoteRequiredCapabilities.single(),
        )
        assertEquals(null, decodeScenarioResolution("""{"error":{"code":"unknown_scenario"}}"""))

        val installResult = NapaxiScenarioPackInstallResult(
            definition = scenario,
            installed = true,
            replaced = false,
            warnings = listOf("core execution plane was added"),
        )
        val removalResult = NapaxiScenarioPackRemovalResult(
            scenarioId = "napaxi.scenario.mobile_development",
            removed = true,
        )
        assertEquals("napaxi.scenario.mobile_development", installResult.definition.id)
        assertEquals(true, installResult.installed)
        assertEquals(false, installResult.replaced)
        assertEquals("core execution plane was added", installResult.warnings.single())
        assertEquals(
            "napaxi.scenario.mobile_development",
            decodeScenarioPackInstallResult(installResult.toJson())!!.definition.id,
        )
        assertEquals("napaxi.scenario.mobile_development", removalResult.scenarioId)
        assertEquals(true, removalResult.removed)
        assertEquals(
            "napaxi.scenario.mobile_development",
            decodeScenarioPackRemovalResult(removalResult.toJson())!!.scenarioId,
        )
        assertEquals(null, decodeScenarioPackInstallResult("""{"error":{"code":"invalid"}}"""))
        assertEquals(null, decodeScenarioPackRemovalResult("""{"error":{"code":"invalid"}}"""))
    }

    @Test
    fun channelModelsExposeFlutterStableFields() {
        val registration = NapaxiChannelRegistration.im(
            name = "work-telegram",
            type = "telegram",
            accountId = "work",
            endpointKind = NapaxiChannelEndpointKind.DIRECT,
            modalities = listOf(
                NapaxiChannelModality.TEXT,
                NapaxiChannelModality.IMAGE,
                NapaxiChannelModality.FILE,
            ),
            contentFormats = listOf(
                NapaxiChannelContentFormat.PLAIN_TEXT,
                NapaxiChannelContentFormat.MARKDOWN,
            ),
            transport = "bot_api",
            config = JSONObject("""{"allow_from":["tg:123"]}"""),
        )
        val record = NapaxiChannelRecord(
            """
            {
              "name":"work-telegram",
              "type":"telegram",
              "surface_kind":"im",
              "endpoint_kind":"direct",
              "modalities":["text","image"],
              "content_formats":["plain_text","markdown"],
              "transport":"bot_api",
              "capability_id":"napaxi.channel.im",
              "config":{"token":"redacted"},
              "registered_at":"2026-06-11T00:00:00Z",
              "updated_at":"2026-06-11T00:00:01Z"
            }
            """.trimIndent(),
        )

        val registrationJson = registration.toJsonObject()
        assertEquals("work-telegram", registrationJson.getString("name"))
        assertEquals("telegram", registrationJson.getString("type"))
        assertEquals("work", registrationJson.getString("account_id"))
        assertEquals(NapaxiChannelSurfaceKind.IM, registrationJson.getString("surface_kind"))
        assertEquals(NapaxiChannelEndpointKind.DIRECT, registrationJson.getString("endpoint_kind"))
        assertEquals(NapaxiChannelModality.TEXT, registrationJson.getJSONArray("modalities").getString(0))
        assertEquals(NapaxiChannelModality.IMAGE, registrationJson.getJSONArray("modalities").getString(1))
        assertEquals(NapaxiChannelModality.FILE, registrationJson.getJSONArray("modalities").getString(2))
        assertEquals(NapaxiChannelContentFormat.PLAIN_TEXT, registrationJson.getJSONArray("content_formats").getString(0))
        assertEquals(NapaxiChannelContentFormat.MARKDOWN, registrationJson.getJSONArray("content_formats").getString(1))
        assertEquals("bot_api", registrationJson.getString("transport"))
        assertEquals("tg:123", registrationJson.getJSONObject("config").getJSONArray("allow_from").getString(0))
        assertEquals(registration.toJson(), registration.toJsonString())

        assertEquals("work-telegram", record.name)
        assertEquals("telegram", record.type)
        assertEquals(NapaxiChannelSurfaceKind.IM, record.surfaceKind)
        assertEquals(NapaxiChannelEndpointKind.DIRECT, record.endpointKind)
        assertEquals(listOf(NapaxiChannelModality.TEXT, NapaxiChannelModality.IMAGE), record.modalities)
        assertEquals(
            listOf(NapaxiChannelContentFormat.PLAIN_TEXT, NapaxiChannelContentFormat.MARKDOWN),
            record.contentFormats,
        )
        assertEquals("bot_api", record.transport)
        assertEquals(NapaxiChannelCapability.IM, record.capabilityId)
        assertEquals("napaxi.channel.device", NapaxiChannelCapability.DEVICE)
        assertEquals("redacted", record.config.getString("token"))
        assertEquals("2026-06-11T00:00:00Z", record.registeredAt)
        assertEquals("2026-06-11T00:00:01Z", record.updatedAt)
        assertEquals(record.toJson(), record.toJsonString())

        val inbound = NapaxiChannelInboundMessage(
            channelName = "feishu",
            accountId = "main",
            platformMessageId = "om_1",
            threadId = "om_root",
            peer = NapaxiChannelPeer(
                kind = NapaxiChannelEndpointKind.GROUP,
                id = "oc_group",
                displayName = "Ops",
            ),
            sender = NapaxiChannelActor(id = "ou_user", displayName = "Alice"),
            text = "ship status?",
            media = listOf(
                NapaxiChannelMedia(
                    kind = NapaxiChannelModality.IMAGE,
                    uri = "file:///tmp/a.png",
                    mimeType = "image/png",
                ),
            ),
        )
        val inboundJson = inbound.toJsonObject()
        assertEquals("feishu", inboundJson.getString("channel_name"))
        assertEquals(NapaxiChannelEndpointKind.GROUP, inboundJson.getJSONObject("peer").getString("kind"))
        assertEquals("ou_user", inboundJson.getJSONObject("sender").getString("id"))
        assertEquals("image/png", inboundJson.getJSONArray("media").getJSONObject(0).getString("mime_type"))

        val outbound = NapaxiChannelOutboundMessage.fromJson(
            """
            {
              "id":"out_1",
              "channel_name":"qqbot",
              "account_id":"bot-a",
              "peer":{"kind":"direct","id":"openid-a"},
              "reply_to_message_id":"msg_1",
              "text":"hello",
              "format":"markdown",
              "lease_id":"lease_1",
              "status":"leased",
              "created_at":"2026-06-11T00:00:00Z",
              "updated_at":"2026-06-11T00:00:01Z"
            }
            """.trimIndent(),
        )
        assertEquals("qqbot", outbound.channelName)
        assertEquals("openid-a", outbound.peer.id)
        assertEquals(NapaxiChannelContentFormat.MARKDOWN, outbound.format)
        assertEquals("lease_1", outbound.leaseId)

        val receipt = NapaxiChannelAcceptedReceipt.fromJson("""{"accepted":true,"id":"in_1","duplicate":true}""")
        assertEquals(true, receipt.accepted)
        assertEquals("in_1", receipt.id)
        assertEquals(true, receipt.duplicate)

        val route = NapaxiChannelAgentRoute.channelDefault(
            channelName = "qqbot",
            channelAccountId = "bot-a",
            sessionAccountId = "default",
            agentId = "agent.qq",
        )
        val routeJson = route.toJsonObject()
        assertEquals("qqbot", routeJson.getString("channel_name"))
        assertEquals("bot-a", routeJson.getString("channel_account_id"))
        assertEquals("default", routeJson.getString("session_account_id"))
        assertEquals("agent.qq", routeJson.getString("agent_id"))
        assertEquals("stable_by_peer_or_thread", routeJson.getString("session_policy"))

        val status = NapaxiChannelAgentStatus.fromJson(
            """
            {
              "routes":[{"channel_name":"qqbot","agent_id":"agent.qq"}],
              "pending_human":[{"request_id":"req-1"}]
            }
            """.trimIndent(),
        )
        assertEquals("qqbot", status.routes.single().channelName)
        assertEquals("agent.qq", status.routes.single().agentId)
        assertEquals("req-1", status.pendingHuman.single().getString("request_id"))
    }

    @Test
    fun mcpModelsExposeFlutterStableFields() {
        val server = McpServerInfo(
            """
            {
              "name":"filesystem",
              "url":"stdio://filesystem",
              "connected":false,
              "tools":["read_file","write_file"],
              "error":"",
              "authRequired":true,
              "oauthConnected":false,
              "oauthPending":true
            }
            """.trimIndent(),
        )
        val connectedServer = McpServerInfo(
            """{"name":"github","url":"https://example.test/mcp","connected":true}""",
        )
        val failedServer = McpServerInfo(
            """{"name":"bad","url":"https://bad.test","connected":false,"error":"boom"}""",
        )
        val tool = McpToolInfo("""{"name":"read_file","server_name":"filesystem"}""")
        val action = McpServerActionResult(
            """{"name":"filesystem","tools_loaded":["read_file"],"message":"ok"}""",
        )
        val oauth = McpOAuthStartResult(
            """
            {
              "name":"github",
              "authorization_url":"https://auth.test",
              "state":"state-1",
              "redirect_uri":"napaxi://oauth/mcp"
            }
            """.trimIndent(),
        )

        assertEquals("filesystem", server.name)
        assertEquals("stdio://filesystem", server.url)
        assertEquals(false, server.connected)
        assertEquals(listOf("read_file", "write_file"), server.tools)
        assertEquals(true, server.authRequired)
        assertEquals(false, server.oauthConnected)
        assertEquals(true, server.oauthPending)
        assertEquals(McpConnectionState.Connecting, server.connectionState)
        assertEquals(McpConnectionState.Connected, connectedServer.connectionState)
        assertEquals(McpConnectionState.Error, failedServer.connectionState)

        assertEquals("read_file", tool.name)
        assertEquals("filesystem", tool.serverName)
        assertEquals("filesystem", action.name)
        assertEquals(listOf("read_file"), action.toolsLoaded)
        assertEquals("ok", action.message)
        assertEquals(true, action.isSuccess)
        assertEquals("github", oauth.name)
        assertEquals("https://auth.test", oauth.authorizationUrl)
        assertEquals("state-1", oauth.state)
        assertEquals("napaxi://oauth/mcp", oauth.redirectUri)
        assertEquals(true, oauth.isSuccess)
        assertEquals("filesystem", McpServerInfo.fromJson(server.toJson()).name)
        assertEquals("bad", McpServerInfo.fromJsonObject(failedServer.toJsonObject()).name)
        assertEquals("github", McpServerInfo.fromMap(mapOf("name" to "github", "connected" to true)).name)
        assertEquals("read_file", McpToolInfo.fromJson(tool.toJson()).name)
        assertEquals("filesystem", McpToolInfo.fromMap(mapOf("name" to "read_file", "serverName" to "filesystem")).serverName)
        assertEquals("filesystem", McpServerActionResult.fromJson(action.toJson()).name)
        assertEquals("filesystem", McpServerActionResult.fromMap(mapOf("name" to "filesystem", "tools_loaded" to listOf("read_file"))).name)
        assertEquals("github", McpOAuthStartResult.fromJson(oauth.toJson()).name)
        assertEquals("state-2", McpOAuthStartResult.fromMap(mapOf("state" to "state-2")).state)
    }

    @Test
    fun automationModelsExposeFlutterStableFields() {
        val job = AutomationJob(
            """
            {
              "id":"job-1",
              "name":"Morning brief",
              "enabled":true,
              "account_id":"acct",
              "agent_id":"assistant",
              "trigger":{
                "kind":"interval",
                "every_ms":60000,
                "anchor_ms":1000
              },
              "payload":{
                "kind":"agentTurn",
                "message":"Brief me",
                "session_mode":"isolated",
                "model_profile_id":"fast",
                "max_iterations":5
              },
              "policy":{
                "requires_user_visible_notification":true,
                "allow_high_risk_tools":false,
                "max_run_duration_ms":120000,
                "max_retries":3,
                "retry_backoff_ms":[1000,2000],
                "delete_after_success":true
              },
              "state":{
                "next_run_at_ms":2000,
                "last_run_at_ms":1000,
                "last_run_status":"succeeded",
                "last_error":null,
                "consecutive_errors":0,
                "running_run_id":"run-active",
                "running_at_ms":1500,
                "last_wake_source":"alarm",
                "last_wake_at_ms":900
              },
              "created_at":10,
              "updated_at":20
            }
            """.trimIndent(),
        )
        val run = AutomationRun(
            """
            {
              "run_id":"run-1",
              "job_id":"job-1",
              "status":"succeeded",
              "trigger_source":"manual",
              "started_at":100,
              "completed_at":250,
              "duration_ms":150,
              "session_key":"{}",
              "summary":"Done",
              "error":null,
              "tool_call_count":2,
              "delivery_status":"delivered"
            }
            """.trimIndent(),
        )
        val wake = AutomationWake(
            """
            {
              "jobId":"job-1",
              "atMs":3000,
              "trigger":{"kind":"manual"}
            }
            """.trimIndent(),
        )

        assertEquals("job-1", job.id)
        assertEquals("Morning brief", job.name)
        assertEquals(true, job.enabled)
        assertEquals("acct", job.accountId)
        assertEquals("assistant", job.agentId)
        assertEquals("interval", job.trigger.kind)
        assertEquals(60000L, job.trigger.everyMs)
        assertEquals(1000L, job.trigger.anchorMs)
        assertEquals("agentTurn", job.payload.kind)
        assertEquals("Brief me", job.payload.message)
        assertEquals("isolated", job.payload.sessionMode)
        assertEquals("fast", job.payload.modelProfileId)
        assertEquals(5, job.payload.maxIterations)
        assertEquals(true, job.policy.requiresUserVisibleNotification)
        assertEquals(false, job.policy.allowHighRiskTools)
        assertEquals(120000L, job.policy.maxRunDurationMs)
        assertEquals(3, job.policy.maxRetries)
        assertEquals(listOf(1000L, 2000L), job.policy.retryBackoffMs)
        assertEquals(true, job.policy.deleteAfterSuccess)
        assertEquals(2000L, job.state.nextRunAtMs)
        assertEquals("succeeded", job.state.lastRunStatus)
        assertEquals("run-active", job.state.runningRunId)
        assertEquals("alarm", job.state.lastWakeSource)
        assertEquals(10L, job.createdAt)
        assertEquals(20L, job.updatedAt)

        assertEquals("run-1", run.runId)
        assertEquals("job-1", run.jobId)
        assertEquals("succeeded", run.status)
        assertEquals("manual", run.triggerSource)
        assertEquals(100L, run.startedAt)
        assertEquals(250L, run.completedAt)
        assertEquals(150L, run.durationMs)
        assertEquals("{}", run.sessionKeyJson)
        assertEquals("Done", run.summary)
        assertEquals(2, run.toolCallCount)
        assertEquals("delivered", run.deliveryStatus)

        assertEquals("job-1", wake.jobId)
        assertEquals(3000L, wake.atMs)
        assertEquals("manual", wake.trigger.kind)

        assertEquals("ok", decodeJsonObjectOrNull("""{"status":"ok"}""")?.getString("status"))
        assertEquals(null, decodeJsonObjectOrNull("""{"error":"missing"}"""))
        assertEquals(null, decodeJsonObjectOrNull("[]"))
        assertEquals("job-1", decodeAutomationJobs("[${job.rawJson}]").single().id)
        assertEquals("job-1", decodeAutomationJobs("""{"jobs":[${job.rawJson}]}""").single().id)
        assertEquals("run-1", decodeAutomationRuns("[${run.rawJson}]").single().runId)
        assertEquals("run-1", decodeAutomationRuns("""{"runs":[${run.rawJson}]}""").single().runId)
        assertEquals("interval", AutomationTrigger.fromJson(job.trigger.toJson()).kind)
        assertEquals("hostEvent", AutomationTrigger.fromMap(mapOf("kind" to "hostEvent", "eventType" to "boot")).kind)
        assertEquals("agentTurn", AutomationPayload.fromJson(job.payload.toJson()).kind)
        assertEquals("Resume", AutomationPayload.fromMap(mapOf("kind" to "agentTurn", "message" to "Resume")).message)
        assertEquals(3, AutomationPolicy.fromJson(job.policy.toJson()).maxRetries)
        assertEquals(4, AutomationPolicy.fromMap(mapOf("maxRetries" to 4, "retryBackoffMs" to listOf(1000, 2000))).maxRetries)
        assertEquals("succeeded", AutomationJobState.fromJson(job.state.toJson()).lastRunStatus)
        assertEquals("run-map", AutomationJobState.fromMap(mapOf("runningRunId" to "run-map")).runningRunId)
        assertEquals("job-1", AutomationJob.fromJson(job.toJson()).id)
        assertEquals("Brief me", AutomationJob.fromJsonObject(job.toJsonObject()).payload.message)
        assertEquals("job-map", AutomationJob.fromMap(mapOf("id" to "job-map", "name" to "Mapped")).id)
        assertEquals("run-1", AutomationRun.fromJson(run.toJson()).runId)
        assertEquals("job-map", AutomationRun.fromMap(mapOf("jobId" to "job-map", "runId" to "run-map")).jobId)
        assertEquals("job-1", AutomationWake.fromJson(wake.toJson()).jobId)
        assertEquals("manual", AutomationWake.fromMap(mapOf("jobId" to "job-map", "trigger" to mapOf("kind" to "manual"))).trigger.kind)
    }

    @Test
    fun automationBuildersCreateFlutterStableJsonShape() {
        val trigger = AutomationTrigger.hostEvent(eventType = "boot", source = "system")
        val payload = AutomationPayload.agentTurn(
            message = "Resume",
            sessionMode = "existing",
            modelProfileId = "fast",
            maxIterations = 4,
        )
        val job = AutomationJob.create(
            name = "Resume on boot",
            trigger = trigger,
            payload = payload,
            accountId = "acct",
            agentId = "assistant",
        )

        assertEquals("hostEvent", trigger.kind)
        assertEquals("boot", trigger.eventType)
        assertEquals("system", trigger.source)
        assertEquals("agentTurn", payload.kind)
        assertEquals("Resume", payload.message)
        assertEquals("existing", payload.sessionMode)
        assertEquals("fast", payload.modelProfileId)
        assertEquals(4, payload.maxIterations)
        assertEquals("Resume on boot", job.name)
        assertEquals("acct", job.accountId)
        assertEquals("assistant", job.agentId)
        assertEquals("hostEvent", job.trigger.kind)
        assertEquals("agentTurn", job.payload.kind)
        assertEquals("Resume on boot", JSONObject(job.toJson()).getString("name"))
        assertEquals(job.toJson(), job.toJsonString())
    }
}
