import XCTest
@testable import Napaxi

final class ModelTests: XCTestCase {
    func testEngineAliasesMirrorFlutterAPISurface() {
        let agentApp: (NapaxiEngine) -> NapaxiAgentAppAPI = { engine in
            engine.agentApp
        }
        let ensureAgent: (NapaxiEngine) throws -> Bool = { engine in
            try engine.ensureAgent()
        }
        let startToolRequestListener: (NapaxiEngine) -> Void = { engine in
            engine.startToolRequestListener()
        }
        let dispose: (NapaxiEngine) -> Void = { engine in
            engine.dispose()
        }
        let toolStartRequestListener: (NapaxiToolAPI) -> Void = { api in
            api.startRequestListener()
        }

        XCTAssertNotNil(agentApp)
        XCTAssertNotNil(ensureAgent)
        XCTAssertNotNil(startToolRequestListener)
        XCTAssertNotNil(dispose)
        XCTAssertNotNil(toolStartRequestListener)
    }

    func testChannelTypedHelpersMirrorFlutterGeneratedBridge() {
        let registerChannel: (NapaxiChannelAPI, String) throws -> Bool = { api, configJSON in
            try api.registerChannel(configJSON: configJSON)
        }
        let registerTypedChannel: (NapaxiChannelAPI, NapaxiChannelRegistration) throws -> Bool = { api, registration in
            try api.register(registration)
        }
        let unregisterChannel: (NapaxiChannelAPI, String) throws -> Bool = { api, channelName in
            try api.unregisterChannel(channelName)
        }

        XCTAssertNotNil(registerChannel)
        XCTAssertNotNil(registerTypedChannel)
        XCTAssertNotNil(unregisterChannel)
    }

    func testChannelModelsExposeFlutterStableFields() throws {
        let registration = NapaxiChannelRegistration.im(
            name: "work-telegram",
            type: "telegram",
            accountId: "work",
            endpointKind: NapaxiChannelEndpointKind.direct,
            modalities: [
                NapaxiChannelModality.text,
                NapaxiChannelModality.image,
                NapaxiChannelModality.file,
            ],
            contentFormats: [
                NapaxiChannelContentFormat.plainText,
                NapaxiChannelContentFormat.markdown,
            ],
            transport: "bot_api",
            config: ["allow_from": .array([.string("tg:123")])]
        )
        let registrationJson = registration.toJson()
        XCTAssertEqual(registrationJson["name"], .string("work-telegram"))
        XCTAssertEqual(registrationJson["type"], .string("telegram"))
        XCTAssertEqual(registrationJson["account_id"], .string("work"))
        XCTAssertEqual(registrationJson["surface_kind"], .string(NapaxiChannelSurfaceKind.im))
        XCTAssertEqual(registrationJson["endpoint_kind"], .string(NapaxiChannelEndpointKind.direct))
        XCTAssertEqual(
            registrationJson["modalities"],
            .array([
                .string(NapaxiChannelModality.text),
                .string(NapaxiChannelModality.image),
                .string(NapaxiChannelModality.file),
            ])
        )
        XCTAssertEqual(
            registrationJson["content_formats"],
            .array([
                .string(NapaxiChannelContentFormat.plainText),
                .string(NapaxiChannelContentFormat.markdown),
            ])
        )
        XCTAssertEqual(registrationJson["transport"], .string("bot_api"))

        let record = NapaxiChannelRecord.fromJson([
            "name": .string("work-telegram"),
            "type": .string("telegram"),
            "surface_kind": .string("im"),
            "endpoint_kind": .string("direct"),
            "modalities": .array([.string("text"), .string("image")]),
            "content_formats": .array([.string("plain_text"), .string("markdown")]),
            "transport": .string("bot_api"),
            "capability_id": .string(NapaxiChannelCapability.im),
            "config": .object(["token": .string("redacted")]),
            "registered_at": .string("2026-06-11T00:00:00Z"),
            "updated_at": .string("2026-06-11T00:00:01Z"),
        ])
        XCTAssertEqual(record.name, "work-telegram")
        XCTAssertEqual(record.type, "telegram")
        XCTAssertEqual(record.surfaceKind, NapaxiChannelSurfaceKind.im)
        XCTAssertEqual(record.endpointKind, NapaxiChannelEndpointKind.direct)
        XCTAssertEqual(record.modalities, [NapaxiChannelModality.text, NapaxiChannelModality.image])
        XCTAssertEqual(record.contentFormats, [NapaxiChannelContentFormat.plainText, NapaxiChannelContentFormat.markdown])
        XCTAssertEqual(record.transport, "bot_api")
        XCTAssertEqual(record.capabilityId, NapaxiChannelCapability.im)
        XCTAssertEqual(NapaxiChannelCapability.device, "napaxi.channel.device")
        XCTAssertEqual(record.config["token"], .string("redacted"))
        XCTAssertEqual(record.registeredAt, "2026-06-11T00:00:00Z")
        XCTAssertEqual(record.updatedAt, "2026-06-11T00:00:01Z")

        let decoded = try decodeChannelRecords("""
        [{
          "name":"work-telegram",
          "type":"telegram",
          "surface_kind":"im",
          "endpoint_kind":"direct",
          "modalities":["text"],
          "transport":"bot_api",
          "capability_id":"napaxi.channel.im",
          "config":{},
          "registered_at":"2026-06-11T00:00:00Z",
          "updated_at":"2026-06-11T00:00:01Z"
        }]
        """)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.name, "work-telegram")

        let inbound = NapaxiChannelInboundMessage(
            channelName: "feishu",
            accountId: "main",
            peer: NapaxiChannelPeer(
                kind: NapaxiChannelEndpointKind.group,
                id: "oc_group",
                displayName: "Ops"
            ),
            sender: NapaxiChannelActor(id: "ou_user", displayName: "Alice"),
            platformMessageId: "om_1",
            threadId: "om_root",
            text: "ship status?",
            media: [
                NapaxiChannelMedia(
                    kind: NapaxiChannelModality.image,
                    uri: "file:///tmp/a.png",
                    mimeType: "image/png"
                ),
            ]
        )
        let inboundJson = inbound.toJson()
        XCTAssertEqual(inboundJson["channel_name"], .string("feishu"))
        XCTAssertEqual(
            inboundJson["peer"],
            .object(["kind": .string(NapaxiChannelEndpointKind.group), "id": .string("oc_group"), "display_name": .string("Ops")])
        )
        XCTAssertEqual(inboundJson["sender"], .object(["id": .string("ou_user"), "display_name": .string("Alice")]))
        XCTAssertEqual(inboundJson["media"], .array([.object(["kind": .string(NapaxiChannelModality.image), "uri": .string("file:///tmp/a.png"), "mime_type": .string("image/png")])]))

        let outbound = NapaxiChannelOutboundMessage.fromJson([
            "id": .string("out_1"),
            "channel_name": .string("qqbot"),
            "account_id": .string("bot-a"),
            "peer": .object(["kind": .string("direct"), "id": .string("openid-a")]),
            "reply_to_message_id": .string("msg_1"),
            "text": .string("hello"),
            "format": .string("markdown"),
            "lease_id": .string("lease_1"),
            "status": .string("leased"),
            "created_at": .string("2026-06-11T00:00:00Z"),
            "updated_at": .string("2026-06-11T00:00:01Z"),
        ])
        XCTAssertEqual(outbound.channelName, "qqbot")
        XCTAssertEqual(outbound.peer.id, "openid-a")
        XCTAssertEqual(outbound.format, NapaxiChannelContentFormat.markdown)
        XCTAssertEqual(outbound.leaseId, "lease_1")

        let receipt = try decodeChannelAcceptedReceipt(#"{"accepted":true,"id":"in_1","duplicate":true}"#)
        XCTAssertTrue(receipt.accepted)
        XCTAssertEqual(receipt.id, "in_1")
        XCTAssertTrue(receipt.duplicate)

        let route = NapaxiChannelAgentRoute.channelDefault(
            channelName: "qqbot",
            channelAccountId: "bot-a",
            sessionAccountId: "default",
            agentId: "agent.qq"
        )
        let routeJson = route.toJson()
        XCTAssertEqual(routeJson["channel_name"], .string("qqbot"))
        XCTAssertEqual(routeJson["channel_account_id"], .string("bot-a"))
        XCTAssertEqual(routeJson["session_account_id"], .string("default"))
        XCTAssertEqual(routeJson["agent_id"], .string("agent.qq"))
        XCTAssertEqual(routeJson["session_policy"], .string("stable_by_peer_or_thread"))

        let status = NapaxiChannelAgentStatus.fromJson([
            "routes": .array([.object(["channel_name": .string("qqbot"), "agent_id": .string("agent.qq")])]),
            "pending_human": .array([.object(["request_id": .string("req-1")])]),
        ])
        XCTAssertEqual(status.routes.first?.channelName, "qqbot")
        XCTAssertEqual(status.routes.first?.agentId, "agent.qq")
        XCTAssertEqual(status.pendingHuman.first?["request_id"], .string("req-1"))
    }

    func testChatDefaultsMirrorFlutterSendDefaults() {
        XCTAssertEqual(NapaxiChatDefaults.maxIterations, 0)
        XCTAssertEqual(NapaxiChatDefaults.maxIterationsInt32, 0)
    }

    func testChatMaxIterationsUsesSwiftIntLikeFlutterInt() {
        let engineSend: (NapaxiEngine, String, Int) async throws -> NapaxiJSONValue = { engine, message, maxIterations in
            try await engine.send(message, maxIterations: maxIterations)
        }
        let engineSendStream: (NapaxiEngine, String, Int) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> = { engine, message, maxIterations in
            try engine.sendStream(message, maxIterations: maxIterations)
        }
        let engineSessionSend: (NapaxiEngine, NapaxiSessionKey, String, Int) async throws -> NapaxiJSONValue = { engine, key, message, maxIterations in
            try await engine.sendToSession(sessionKey: key, message: message, maxIterations: maxIterations)
        }
        let engineSessionSendPositional: (NapaxiEngine, NapaxiSessionKey, String, Int) async throws -> NapaxiJSONValue = { engine, key, message, maxIterations in
            try await engine.sendToSession(key, message, maxIterations: maxIterations)
        }
        let engineSessionSendStreamPositional: (NapaxiEngine, NapaxiSessionKey, String, Int) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> = { engine, key, message, maxIterations in
            try engine.sendToSessionStream(key, message, maxIterations: maxIterations)
        }
        let chatSend: (NapaxiChatAPI, String, Int) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> = { api, message, maxIterations in
            try api.send(message, maxIterations: maxIterations)
        }
        let chatSessionSend: (NapaxiChatAPI, NapaxiSessionKey, String, Int) throws -> AsyncThrowingStream<NapaxiChatEvent, Error> = { api, key, message, maxIterations in
            try api.sendToSession(key, message, maxIterations: maxIterations)
        }

        XCTAssertNotNil(engineSend)
        XCTAssertNotNil(engineSendStream)
        XCTAssertNotNil(engineSessionSend)
        XCTAssertNotNil(engineSessionSendPositional)
        XCTAssertNotNil(engineSessionSendStreamPositional)
        XCTAssertNotNil(chatSend)
        XCTAssertNotNil(chatSessionSend)
        XCTAssertEqual(NapaxiChatDefaults.bridgeMaxIterations(Int.max), Int32.max)
        XCTAssertEqual(NapaxiChatDefaults.bridgeMaxIterations(Int.min), Int32.min)
    }

    func testTopLevelFlutterCompatibilityAliases() {
        XCTAssertEqual(defaultMaxTokens, NapaxiConfig.defaultMaxTokens)
        XCTAssertEqual(napaxiDesktopUserAgent, NapaxiDesktopUserAgent)

        let config = LlmConfig(provider: "openai", apiKey: "sk-test", model: "gpt-test")
        let capability = LlmCapabilityConfig(provider: "openai", apiKey: "sk-vision", model: "vision")
        let scenePrompt = ScenePromptConfig(enabled: true)
        let contextEngine = ContextEngineConfig()
        XCTAssertEqual(config.provider, "openai")
        XCTAssertEqual(capability.model, "vision")
        XCTAssertTrue(scenePrompt.enabled)
        XCTAssertEqual(contextEngine.engine, "compressor")

        let actionExecutor: AgentAppActionExecutor = AliasActionExecutor()
        let logger: (String, String) -> Void = log
        XCTAssertNotNil(actionExecutor)
        XCTAssertNotNil(logger)
    }

    func testConfigEncodesFlutterCompatibleKeys() throws {
        let config = NapaxiConfig(
            provider: "openai",
            apiKey: "sk-test",
            model: "gpt-test",
            baseUrl: "https://api.example",
            extra: ["temperature": .number(0.2)]
        )

        let raw = try config.jsonString()
        let value = try NapaxiRawJSON(jsonString: raw).value

        guard case .object(let object) = value else {
            return XCTFail("config should encode as object")
        }
        XCTAssertEqual(object["provider"], .string("openai"))
        XCTAssertEqual(object["api_key"], .string("sk-test"))
        XCTAssertEqual(object["model"], .string("gpt-test"))
        XCTAssertEqual(object["base_url"], .string("https://api.example"))
        XCTAssertEqual(object["temperature"], .number(0.2))
    }

    func testConfigOptionalStringEncodingMirrorsFlutterLlmConfig() throws {
        let config = NapaxiConfig(
            provider: "openai",
            apiKey: "sk-test",
            model: "gpt-test",
            baseUrl: nil,
            extraHeaders: "",
            imageModel: "",
            imageAnalysisModel: "",
            imageBase64UrlFormat: "",
            videoModel: "",
            audioModel: "",
            capabilityConfigs: [
                "imageAnalysis": NapaxiLlmCapabilityConfig(
                    provider: "openai",
                    apiKey: "sk-vision",
                    model: "vision",
                    extraHeaders: "",
                    imageBase64UrlFormat: ""
                ),
            ],
            contextEngine: NapaxiContextEngineConfig(compactionModel: "  ")
        )

        let value = try NapaxiRawJSON(jsonString: config.jsonString()).value
        guard case .object(let object) = value,
              case .object(let capabilityConfigs)? = object["capability_configs"],
              case .object(let imageAnalysis)? = capabilityConfigs["imageAnalysis"],
              case .object(let contextEngine)? = object["context_engine"] else {
            return XCTFail("config should encode as object")
        }

        XCTAssertEqual(object["base_url"], .null)
        XCTAssertEqual(object["extra_headers"], .string(""))
        XCTAssertEqual(object["image_model"], .string(""))
        XCTAssertEqual(object["image_analysis_model"], .string(""))
        XCTAssertEqual(object["image_base64_url_format"], .string(""))
        XCTAssertEqual(object["video_model"], .string(""))
        XCTAssertEqual(object["audio_model"], .string(""))
        XCTAssertEqual(imageAnalysis["base_url"], .null)
        XCTAssertEqual(imageAnalysis["extra_headers"], .string(""))
        XCTAssertEqual(imageAnalysis["image_base64_url_format"], .string(""))
        XCTAssertNil(contextEngine["compaction_model"])
    }

    func testConfigNestedStableModelsEncodeThroughFlutterMapShape() throws {
        let config = NapaxiConfig(
            provider: "openai",
            apiKey: "sk-test",
            model: "gpt-test",
            scenePromptConfig: NapaxiScenePromptConfig(raw: [
                "enabled": .bool(true),
                "host_policies": .object(["location": .string("ask")]),
            ]),
            contextEngine: NapaxiContextEngineConfig(raw: [
                "contextWindowTokens": .number(200_000),
                "nativeContextWindowTokens": .number(1_000_000),
                "compactionModel": .string("  "),
            ])
        )

        let value = try NapaxiRawJSON(jsonString: config.jsonString()).value
        guard case .object(let object) = value,
              case .object(let scenePrompt)? = object["scene_prompt_config"],
              case .object(let contextEngine)? = object["context_engine"] else {
            return XCTFail("config should encode nested objects")
        }

        XCTAssertEqual(scenePrompt["enabled"], .bool(true))
        XCTAssertEqual(scenePrompt["host_policies"], .object(["location": .string("ask")]))
        XCTAssertEqual(contextEngine["context_window_tokens"], .number(200_000))
        XCTAssertEqual(contextEngine["native_context_window_tokens"], .number(1_000_000))
        XCTAssertNil(contextEngine["contextWindowTokens"])
        XCTAssertNil(contextEngine["nativeContextWindowTokens"])
        XCTAssertNil(contextEngine["compaction_model"])
        XCTAssertNil(contextEngine["compactionModel"])
    }

    func testScenePromptHostPoliciesStringifyDynamicValuesLikeFlutter() {
        let scenePrompt = ScenePromptConfig.fromMap([
            "enabled": .bool(true),
            "host_policies": .object([
                "allow": .bool(true),
                "count": .number(2),
                "nested": .object(["mode": .string("ask")]),
                "scopes": .array([.string("camera"), .bool(false)]),
            ]),
        ])

        XCTAssertEqual(scenePrompt.hostPolicies?["allow"], "true")
        XCTAssertEqual(scenePrompt.hostPolicies?["count"], "2")
        XCTAssertEqual(scenePrompt.hostPolicies?["nested"], "{mode: ask}")
        XCTAssertEqual(scenePrompt.hostPolicies?["scopes"], "[camera, false]")
    }

    func testConfigEncodesFullFlutterLlmConfigShape() throws {
        let config = NapaxiConfig(
            provider: "openai_compatible",
            apiKey: "sk-test",
            model: "model-main",
            baseUrl: "https://api.example",
            systemPrompt: "Be concise.",
            responseLanguage: "zh",
            maxTokens: 12345,
            maxToolIterations: -1,
            extraHeaders: "X-Test:1",
            userTimezone: "Asia/Shanghai",
            allowedModels: [["name": "Fast", "id": "fast-model"]],
            imageModel: "image-model",
            imageAnalysisModel: "vision-model",
            imageBase64UrlFormat: "data_url",
            videoModel: "video-model",
            audioModel: "audio-model",
            capabilityConfigs: [
                "imageAnalysis": NapaxiLlmCapabilityConfig(
                    provider: "openai",
                    apiKey: "sk-vision",
                    model: "vision-model",
                    baseUrl: "https://vision.example",
                    maxTokens: 2048,
                    extraHeaders: "X-Vision:1",
                    imageBase64UrlFormat: "raw"
                ),
            ],
            scenePromptConfig: NapaxiScenePromptConfig(
                enabled: true,
                hostPolicies: ["location": "ask"]
            ),
            contextEngine: NapaxiContextEngineConfig(
                enabled: true,
                engine: "compressor",
                triggerRatio: 0.9,
                targetRatio: 0.5,
                protectHeadMessages: 3,
                protectTailMessages: 12,
                contextWindowTokens: 20_000,
                nativeContextWindowTokens: 18_000,
                providerContextWindowTokens: 16_000,
                responseReserveTokens: 1_024,
                compactionStrategy: "llm_summary",
                compactionModel: "summary-model",
                compactionTimeoutMs: 45_000,
                preCompactionMemoryFlush: true
            )
        )

        let decoded = try NapaxiRawJSON(jsonString: config.jsonString()).value
        guard case .object(let object) = decoded,
              case .array(let allowedModels)? = object["allowed_models"],
              case .object(let firstAllowed)? = allowedModels.first,
              case .object(let capabilityConfigs)? = object["capability_configs"],
              case .object(let imageAnalysis)? = capabilityConfigs["imageAnalysis"],
              case .object(let scenePrompt)? = object["scene_prompt_config"],
              case .object(let hostPolicies)? = scenePrompt["host_policies"],
              case .object(let contextEngine)? = object["context_engine"] else {
            return XCTFail("Expected Flutter-compatible LlmConfig object")
        }

        XCTAssertEqual(object["system_prompt"], .string("Be concise."))
        XCTAssertEqual(object["response_language"], .string("zh"))
        XCTAssertEqual(object["max_tokens"], .number(12345))
        XCTAssertEqual(object["max_tool_iterations"], .number(-1))
        XCTAssertEqual(object["extra_headers"], .string("X-Test:1"))
        XCTAssertEqual(object["user_timezone"], .string("Asia/Shanghai"))
        XCTAssertEqual(firstAllowed["id"], .string("fast-model"))
        XCTAssertEqual(object["image_model"], .string("image-model"))
        XCTAssertEqual(object["image_analysis_model"], .string("vision-model"))
        XCTAssertEqual(object["image_base64_url_format"], .string("data_url"))
        XCTAssertEqual(object["video_model"], .string("video-model"))
        XCTAssertEqual(object["audio_model"], .string("audio-model"))
        XCTAssertEqual(imageAnalysis["provider"], .string("openai"))
        XCTAssertEqual(imageAnalysis["api_key"], .string("sk-vision"))
        XCTAssertEqual(imageAnalysis["max_tokens"], .number(2048))
        XCTAssertEqual(scenePrompt["enabled"], .bool(true))
        XCTAssertEqual(hostPolicies["location"], .string("ask"))
        XCTAssertEqual(contextEngine["trigger_ratio"], .number(0.9))
        XCTAssertEqual(contextEngine["response_reserve_tokens"], .number(1024))
        XCTAssertEqual(contextEngine["compaction_strategy"], .string("llm_summary"))
        XCTAssertEqual(contextEngine["compaction_model"], .string("summary-model"))
        XCTAssertEqual(contextEngine["compaction_timeout_ms"], .number(45_000))
        XCTAssertEqual(contextEngine["pre_compaction_memory_flush"], .bool(true))
    }

    func testConfigDecodesFlutterLlmConfigDefaultsAndTypedChildren() throws {
        let config = try NapaxiConfig(jsonString: #"{"provider":"openai","api_key":"sk-test","model":"gpt","max_tokens":"12345","max_tool_iterations":"7","user_timezone":"Asia/Shanghai","capability_configs":{"imageAnalysis":{"provider":"openai","api_key":"sk-vision","model":"vision"}},"scene_prompt_config":{"enabled":true},"context_engine":{"enabled":false}}"#)

        XCTAssertEqual(config.provider, "openai")
        XCTAssertEqual(config.apiKey, "sk-test")
        XCTAssertEqual(config.model, "gpt")
        XCTAssertEqual(config.systemPrompt, "")
        XCTAssertEqual(config.responseLanguage, "en")
        XCTAssertEqual(config.maxTokens, NapaxiConfig.defaultMaxTokens)
        XCTAssertEqual(config.maxToolIterations, 50)
        XCTAssertEqual(config.userTimezone, "Asia/Shanghai")
        XCTAssertEqual(config.capabilityConfigs?["imageAnalysis"]?.apiKey, "sk-vision")
        XCTAssertEqual(config.capabilityConfigs?["imageAnalysis"]?.model, "vision")
        XCTAssertEqual(config.scenePromptConfig?.enabled, true)
        XCTAssertEqual(config.contextEngine.enabled, false)
        XCTAssertEqual(config.contextEngine.engine, "compressor")
        XCTAssertEqual(config.contextEngine.triggerRatio, 0.85)
        XCTAssertEqual(config.contextEngine.compactionStrategy, "llm_summary")
        XCTAssertNil(config.contextEngine.compactionModel)
        XCTAssertEqual(config.contextEngine.compactionTimeoutMs, 60_000)
        XCTAssertFalse(config.contextEngine.preCompactionMemoryFlush)
    }

    func testConfigLocalizesDefaultSystemPromptWhenResponseLanguageIsChinese() throws {
        let config = NapaxiConfig(
            provider: "openai",
            apiKey: "sk-test",
            model: "model-main",
            responseLanguage: "zh"
        )
        let decoded = try NapaxiRawJSON(jsonString: config.jsonString()).value
        guard case .object(let object) = decoded else {
            return XCTFail("Expected object")
        }
        XCTAssertEqual(object["system_prompt"], .string("你是一个有帮助的 AI 助手。"))

        let custom = NapaxiConfig(
            provider: "openai",
            apiKey: "sk-test",
            model: "model-main",
            systemPrompt: "Use host policy.",
            responseLanguage: "zh"
        )
        let customDecoded = try NapaxiRawJSON(jsonString: custom.jsonString()).value
        guard case .object(let customObject) = customDecoded else {
            return XCTFail("Expected object")
        }
        XCTAssertEqual(customObject["system_prompt"], .string("Use host policy."))

        let parsed = try NapaxiConfig(jsonString: #"{"provider":"openai","api_key":"sk-test","model":"gpt","response_language":"zh"}"#)
        XCTAssertEqual(parsed.systemPrompt, "你是一个有帮助的 AI 助手。")
    }

    func testConfigRejectsMalformedStructuredFieldsLikeFlutterFromJson() throws {
        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "allowed_models": [
            {"name": "Fast", "id": 42}
          ]
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("allowed_models values must be strings"))
        }

        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "capability_configs": {
            "imageAnalysis": 42
          }
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("capability_configs values must be JSON objects"))
        }

        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "capability_configs": {
            "imageAnalysis": {
              "provider": "openai",
              "api_key": "sk-vision",
              "model": "vision",
              "max_tokens": "2048"
            }
          }
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("capability_configs.max_tokens must be an integer"))
        }

        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "scene_prompt_config": {
            "enabled": "true"
          }
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("scene_prompt_config.enabled must be a bool"))
        }

        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "scene_prompt_config": {
            "host_policies": 42
          }
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("scene_prompt_config.host_policies must be a JSON object"))
        }

        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "context_engine": {
            "trigger_ratio": "0.9"
          }
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("context_engine.trigger_ratio must be a number"))
        }

        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "context_engine": {
            "protect_head_messages": "3"
          }
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("context_engine.protect_head_messages must be an integer"))
        }
    }

    func testConfigDefaultsShellSecurityToOnRequestAndEmitsItOnTheWire() throws {
        let config = NapaxiConfig(provider: "openai", apiKey: "sk-test", model: "gpt-test")
        XCTAssertEqual(config.shellSecurity.approvalMode, .onRequest)

        let value = try NapaxiRawJSON(jsonString: config.jsonString()).value
        guard case .object(let object) = value,
              case .object(let shellSecurity)? = object["shell_security"] else {
            return XCTFail("config should encode shell_security as an object")
        }
        XCTAssertEqual(shellSecurity["approval_mode"], .string("on_request"))
    }

    func testConfigShellSecurityRoundTripsTrustedAllowViaSnakeCaseWire() throws {
        let config = NapaxiConfig(
            provider: "openai",
            apiKey: "sk-test",
            model: "gpt-test",
            shellSecurity: NapaxiShellSecurityConfig(approvalMode: .trustedAllow)
        )

        let json = try config.jsonString()
        let value = try NapaxiRawJSON(jsonString: json).value
        guard case .object(let object) = value,
              case .object(let shellSecurity)? = object["shell_security"] else {
            return XCTFail("config should encode shell_security as an object")
        }
        XCTAssertEqual(shellSecurity["approval_mode"], .string("trusted_allow"))

        let parsed = try NapaxiConfig(jsonString: json)
        XCTAssertEqual(parsed.shellSecurity.approvalMode, .trustedAllow)
    }

    func testShellSecurityFallsBackToOnRequestForUnknownWireValues() {
        XCTAssertEqual(
            ShellSecurityConfig.fromMap(["approval_mode": .string("bogus")]).approvalMode,
            .onRequest
        )
        XCTAssertEqual(ShellApprovalMode.fromWire("bogus"), .onRequest)
        XCTAssertEqual(ShellApprovalMode.fromWire(nil), .onRequest)
    }

    func testConfigRejectsNonStringShellSecurityApprovalModeLikeFlutterFromJson() throws {
        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "shell_security": {
            "approval_mode": 42
          }
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("shell_security.approval_mode must be a string"))
            XCTAssertTrue((error as? NapaxiError)?.errorDescription?.contains("shell_security") == true)
        }

        XCTAssertThrowsError(try LlmConfig.fromJson("""
        {
          "provider": "openai",
          "api_key": "sk-test",
          "model": "gpt",
          "shell_security": {
            "approval_mode": {"mode": "trusted_allow"}
          }
        }
        """)) { error in
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("shell_security.approval_mode must be a string"))
        }
    }

    func testConfigMapHelpersMirrorFlutterFactories() throws {
        let scene = ScenePromptConfig.fromMap([
            "enabled": .bool(true),
            "host_policies": .object([
                "location": .string("ask"),
                "budget": .number(2),
            ]),
        ])
        XCTAssertTrue(scene.enabled)
        XCTAssertEqual(scene.hostPolicies?["location"], "ask")
        XCTAssertEqual(scene.hostPolicies?["budget"], "2")
        XCTAssertEqual(scene.toMap()["enabled"], .bool(true))
        XCTAssertEqual(scene.toMap()["host_policies"], .object([
            "location": .string("ask"),
            "budget": .string("2"),
        ]))

        let context = ContextEngineConfig.fromMap([
            "engine": .string("compressor"),
            "trigger_ratio": .number(0.9),
            "target_ratio": .number(0.5),
            "protect_head_messages": .string("3"),
            "protect_tail_messages": .number(12),
            "context_window_tokens": .string("20000"),
            "native_context_window_tokens": .string("18000"),
            "provider_context_window_tokens": .number(16000),
            "response_reserve_tokens": .number(1024),
            "compaction_strategy": .string("recursive_summary"),
            "compaction_model": .string("summary-model"),
            "compaction_timeout_ms": .string("45000"),
            "pre_compaction_memory_flush": .bool(true),
        ])
        XCTAssertTrue(context.enabled)
        XCTAssertEqual(context.engine, "compressor")
        XCTAssertEqual(context.triggerRatio, 0.9)
        XCTAssertEqual(context.targetRatio, 0.5)
        XCTAssertEqual(context.protectHeadMessages, 2)
        XCTAssertEqual(context.protectTailMessages, 12)
        XCTAssertNil(context.contextWindowTokens)
        XCTAssertNil(context.nativeContextWindowTokens)
        XCTAssertEqual(context.providerContextWindowTokens, 16_000)
        XCTAssertEqual(context.responseReserveTokens, 1_024)
        XCTAssertNil(context.toMap()["native_context_window_tokens"])
        XCTAssertEqual(context.toMap()["provider_context_window_tokens"], .number(16_000))
        XCTAssertEqual(context.compactionStrategy, "recursive_summary")
        XCTAssertEqual(context.compactionModel, "summary-model")
        XCTAssertEqual(context.compactionTimeoutMs, 60_000)
        XCTAssertTrue(context.preCompactionMemoryFlush)
        XCTAssertNil(context.toMap()["context_window_tokens"])
        XCTAssertEqual(context.toMap()["compaction_strategy"], .string("recursive_summary"))
        XCTAssertEqual(context.toMap()["compaction_model"], .string("summary-model"))
        XCTAssertEqual(context.toMap()["compaction_timeout_ms"], .number(60_000))
        XCTAssertEqual(context.toMap()["pre_compaction_memory_flush"], .bool(true))

        let capability = LlmCapabilityConfig.fromMap([
            "provider": .string("openai"),
            "api_key": .string("sk-vision"),
            "base_url": .string("https://vision.example"),
            "model": .string("vision"),
            "max_tokens": .string("2048"),
            "extra_headers": .string("X-Vision:1"),
            "image_base64_url_format": .string("raw"),
        ])
        XCTAssertEqual(capability.provider, "openai")
        XCTAssertEqual(capability.apiKey, "sk-vision")
        XCTAssertEqual(capability.baseUrl, "https://vision.example")
        XCTAssertEqual(capability.model, "vision")
        XCTAssertNil(capability.maxTokens)
        XCTAssertEqual(capability.extraHeaders, "X-Vision:1")
        XCTAssertEqual(capability.imageBase64UrlFormat, "raw")
        XCTAssertEqual(capability.toMap()["base_url"], .string("https://vision.example"))

        let nullBaseUrl = LlmCapabilityConfig(provider: "openai", apiKey: "sk", model: "gpt")
        XCTAssertEqual(nullBaseUrl.toMap()["base_url"], .null)

        let config = try LlmConfig.fromJson(#"{"provider":"openai","api_key":"sk-test","model":"gpt","context_engine":{"enabled":false}}"#)
        XCTAssertEqual(config.provider, "openai")
        XCTAssertEqual(config.apiKey, "sk-test")
        XCTAssertEqual(config.contextEngine.enabled, false)
        XCTAssertEqual(try NapaxiRawJSON(jsonString: config.toJson()).value.objectValue?["provider"], .string("openai"))
    }

    func testEnvelopeDecodingSurfacesNativeErrors() throws {
        let raw = #"{"ok":false,"error":{"code":"bad","message":"Nope"}}"#
        XCTAssertThrowsError(try NapaxiNativeBridge.decodeEnvelope(raw)) { error in
            XCTAssertEqual(error as? NapaxiError, .nativeError(code: "bad", message: "Nope"))
        }
    }

    func testStableRawModelPreservesExportJson() throws {
        let agent = NapaxiAgentHandle(raw: [
            "agent_id": .string("agent-1"),
            "message_count": .number(3),
            "unknown_future_field": .object(["nested": .bool(true)]),
        ])

        let data = try JSONEncoder().encode(agent)
        let decoded = try JSONDecoder().decode(NapaxiAgentHandle.self, from: data)

        XCTAssertEqual(decoded.string("agent_id"), "agent-1")
        XCTAssertEqual(decoded.number("message_count"), 3)
        XCTAssertEqual(decoded.raw["unknown_future_field"], .object(["nested": .bool(true)]))
    }

    func testStableStringModelRoundTrips() throws {
        let status = NapaxiRunEvidenceKind(rawValue: "strong")
        let data = try JSONEncoder().encode(status)
        let decoded = try JSONDecoder().decode(NapaxiRunEvidenceKind.self, from: data)

        XCTAssertEqual(decoded.rawValue, "strong")
    }

    func testChatEventTypedAccessorsMatchFlutterEvents() throws {
        let completed = try NapaxiChatEvent(
            jsonString: #"{"type":"run_completed","run_id":"run-1","status":"unverified","evidence_kind":"weak","verification":"strong","tool_call_count":2}"#
        )
        let defaultedCompleted = try NapaxiChatEvent(
            jsonString: #"{"type":"run_completed","tool_call_count":"2"}"#
        )
        let fractionalCompleted = try NapaxiChatEvent(
            jsonString: #"{"type":"run_completed","tool_call_count":2.5}"#
        )
        let toolResult = try NapaxiChatEvent(
            jsonString: #"{"type":"agent_tool_result","call_id":"call-1","name":"shell","output":"done","is_error":true,"agent_id":"agent-1"}"#
        )
        let action = try NapaxiChatEvent(
            jsonString: #"{"type":"action_result_received","request_id":"req-1","provider_id":"wallet","status":"succeeded","provider_trace_id":"trace-1"}"#
        )
        let streamReset = try NapaxiChatEvent(
            jsonString: #"{"type":"stream_reset","reason":"connection reset by peer"}"#
        )

        XCTAssertEqual(completed.type, "run_completed")
        XCTAssertEqual(completed.runId, "run-1")
        XCTAssertEqual(completed.evidenceKind, "weak")
        XCTAssertEqual(completed.toolCallCount, 2)
        XCTAssertEqual(defaultedCompleted.toolCallCount, 0)
        XCTAssertEqual(fractionalCompleted.toolCallCount, 0)
        XCTAssertTrue(completed.isUnverified)
        XCTAssertEqual(toolResult.callId, "call-1")
        XCTAssertEqual(toolResult.name, "shell")
        XCTAssertEqual(toolResult.output, "done")
        XCTAssertTrue(toolResult.isError)
        XCTAssertEqual(toolResult.agentId, "agent-1")
        XCTAssertEqual(action.requestId, "req-1")
        XCTAssertEqual(action.providerId, "wallet")
        XCTAssertEqual(action.status, "succeeded")
        XCTAssertEqual(action.providerTraceId, "trace-1")
        XCTAssertEqual(streamReset.type, "stream_reset")
        XCTAssertEqual(streamReset.reason, "connection reset by peer")
    }

    func testChatEventMapHelpersMirrorFlutterFactories() throws {
        let event = NapaxiChatEvent.fromMap([
            "type": .string("response_delta"),
            "content": .string("hello"),
        ])
        let decoded = try NapaxiChatEvent.fromJsonString(#"{"type":"tool_result","call_id":"call-1","name":"shell","output":"done","is_error":false}"#)
        let compacted = NapaxiChatEvent.fromMap([
            "type": .string("context_compacted"),
            "turns_removed": .number(2),
            "tokens_before": .string("100"),
            "tokens_after": .number(50.5),
        ])

        XCTAssertEqual(event.type, "response_delta")
        XCTAssertEqual(event.content, "hello")
        XCTAssertEqual(event.toMap()["content"], .string("hello"))
        XCTAssertEqual(decoded.type, "tool_result")
        XCTAssertEqual(decoded.callId, "call-1")
        XCTAssertFalse(decoded.isError)
        XCTAssertEqual(compacted.turnsRemoved, 2)
        XCTAssertEqual(compacted.tokensBefore, 0)
        XCTAssertEqual(compacted.tokensAfter, 0)
    }

    func testChatEventNestedEvolutionAndSkillAccessors() throws {
        let evolution = try NapaxiChatEvent(
            jsonString: #"{"type":"evolution_queued","review_types":["memory","skill"],"runs":[{"id":"run-1","review_type":"memory"},{"id":"run-2","reviewType":"skill"}]}"#
        )
        let activated = try NapaxiChatEvent(
            jsonString: #"{"type":"skill_activated","agent_id":"agent-1","skills":[{"name":"browser","version":"1.0.0","description":"Browse","trust":"trusted","reason":"matched"}]}"#
        )

        XCTAssertEqual(evolution.reviewTypes, ["memory", "skill"])
        XCTAssertEqual(evolution.runIds, ["run-1", "run-2"])
        XCTAssertEqual(evolution.evolutionQueuedRuns[0].reviewType, "memory")
        XCTAssertEqual(evolution.evolutionQueuedRuns[1].reviewType, "skill")
        XCTAssertEqual(activated.agentId, "agent-1")
        XCTAssertEqual(activated.activatedSkills.first?.name, "browser")
        XCTAssertEqual(activated.activatedSkills.first?.version, "1.0.0")
        XCTAssertEqual(activated.activatedSkills.first?.reason, "matched")
    }

    func testIshSupportDisablesShellWhenRootfsIsMissing() {
        XCTAssertEqual(
            NapaxiIshSupport.disabledCapabilities(rootfsAvailable: false),
            [NapaxiIshSupport.shellCapabilityId]
        )
        XCTAssertEqual(NapaxiIshSupport.disabledCapabilities(rootfsAvailable: true), [])
    }

    func testIshSupportFindsBundledRootfsResource() throws {
        let rootfs = try XCTUnwrap(NapaxiIshSupport.bundledRootfsArchiveURL())

        XCTAssertEqual(rootfs.lastPathComponent, "alpine-rootfs.tar.gz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootfs.path))
        XCTAssertTrue(NapaxiIshSupport.isBundledRootfsAvailable)
        XCTAssertTrue(NapaxiIshSupport.registerBundledRootfsArchive())
    }

    func testCapabilityProfileCanCarryDisabledShellCapability() {
        let profile = NapaxiCapabilityProfile(
            platform: "ios",
            supportedCapabilities: ["napaxi.platform_tool.*"],
            disabledCapabilities: NapaxiIshSupport.disabledCapabilities(rootfsAvailable: false)
        )

        let value = profile.jsonValue()
        guard case .object(let object) = value else {
            return XCTFail("profile should encode as object")
        }
        XCTAssertEqual(object["platform"], .string("ios"))
        XCTAssertEqual(object["disabled_capabilities"], .array([.string("napaxi.tool.shell")]))
    }

    func testMcpAPINormalizesDefaultAccount() {
        let defaultApi = NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: 0))
        XCTAssertEqual(defaultApi.defaultUserId, NapaxiEngine.defaultAccountId)

        let blankApi = NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: 0), defaultUserId: "  ")
        XCTAssertEqual(blankApi.defaultUserId, NapaxiEngine.defaultAccountId)

        let accountApi = NapaxiMcpAPI(rawAPI: NapaxiRawAPI(handle: 0), defaultUserId: " user-1 ")
        XCTAssertEqual(accountApi.defaultUserId, "user-1")
    }
}

private final class AliasActionExecutor: AgentAppActionExecutor {
    func execute(_ request: NapaxiAgentAppActionRequest) async throws -> NapaxiAgentAppActionResult {
        NapaxiAgentAppActionResult(
            requestId: request.proposal.requestId,
            status: "succeeded",
            completedAt: "1970-01-01T00:00:00Z"
        )
    }
}
