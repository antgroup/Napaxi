import XCTest
@testable import Napaxi

final class ConfigStoreTests: XCTestCase {
    func testConfigProfileAndSelectionMapHelpersMirrorFlutterShape() {
        let profile = NapaxiConfigProfile(
            id: "primary",
            name: "Primary",
            provider: "openai",
            model: "gpt-test",
            baseUrl: nil,
            systemPrompt: "Use the profile prompt.",
            maxTokens: 12_345,
            maxToolIterations: 77,
            extraHeaders: nil,
            userTimezone: "Asia/Shanghai",
            allowedModels: [["name": "Fast", "id": "fast-model"]],
            imageModel: "image-test",
            imageAnalysisModel: "vision-test",
            videoModel: "video-test",
            audioModel: "audio-test",
            contextEngine: ContextEngineConfig(
                contextWindowTokens: 20_000,
                nativeContextWindowTokens: 18_000,
                providerContextWindowTokens: 16_000,
                responseReserveTokens: 1_024
            ),
            metadata: ["owner": .string("ios")]
        )
        let selection = NapaxiConfigSelection(
            selectedProfileId: "primary",
            selectedProfileIdByCapability: ["chat": "primary"],
            systemPrompt: "Global prompt",
            maxToolIterations: -1
        )

        let profileMap = profile.toMap()
        let selectionMap = selection.toMap()
        let decodedProfile = NapaxiConfigProfile.fromMap(profileMap)
        let decodedSelection = NapaxiConfigSelection.fromMap(selectionMap)

        XCTAssertEqual(profileMap["id"], .string("primary"))
        XCTAssertEqual(profileMap["base_url"], .null)
        XCTAssertEqual(profileMap["max_tokens"], .number(12_345))
        XCTAssertEqual(profileMap["system_prompt"], .string("Use the profile prompt."))
        XCTAssertEqual(profileMap["user_timezone"], .string("Asia/Shanghai"))
        XCTAssertEqual(profileMap["image_analysis_model"], .string("vision-test"))
        XCTAssertEqual(profileMap["context_engine"]?.objectValue?["context_window_tokens"], .number(20_000))
        XCTAssertEqual(profileMap["context_engine"]?.objectValue?["native_context_window_tokens"], .number(18_000))
        XCTAssertEqual(profileMap["metadata"], .object(["owner": .string("ios")]))
        XCTAssertEqual(decodedProfile.allowedModels, [["name": "Fast", "id": "fast-model"]])
        XCTAssertEqual(decodedProfile.userTimezone, "Asia/Shanghai")
        XCTAssertEqual(decodedProfile.contextEngine.contextWindowTokens, 20_000)
        XCTAssertEqual(decodedProfile.contextEngine.providerContextWindowTokens, 16_000)
        XCTAssertEqual(decodedProfile.metadata, ["owner": .string("ios")])
        XCTAssertEqual(selectionMap["selected_profile_id"], .string("primary"))
        XCTAssertEqual(selectionMap["selected_profile_id_by_capability"], .object(["chat": .string("primary")]))
        XCTAssertEqual(decodedSelection, selection)
        XCTAssertEqual(profileMap["extra_headers"], .null)
    }

    func testConfigProfileMapOmitsEmptyFlutterOptionalFields() {
        let profile = NapaxiConfigProfile(
            id: "primary",
            name: "Primary",
            provider: "openai",
            model: "gpt-test",
            systemPrompt: "  "
        )

        let map = profile.toMap()
        let decoded = NapaxiConfigProfile.fromMap([
            "id": .string("minimal"),
            "name": .string("Minimal"),
            "provider": .string("anthropic"),
            "model": .string("claude-test"),
            "max_tokens": .string("12345"),
            "max_tool_iterations": .string("7"),
        ])
        let selection = NapaxiConfigSelection.fromMap([
            "max_tool_iterations": .string("-1"),
        ])

        XCTAssertNil(map["system_prompt"])
        XCTAssertEqual(map["base_url"], .null)
        XCTAssertEqual(map["extra_headers"], .null)
        XCTAssertEqual(decoded.maxTokens, NapaxiConfigProfile.defaultMaxTokens)
        XCTAssertEqual(decoded.maxToolIterations, 50)
        XCTAssertEqual(selection.maxToolIterations, 50)
    }

    func testConfigProfileAndSelectionCodableUseFlutterMapShape() throws {
        let profile = NapaxiConfigProfile(
            id: "primary",
            name: "Primary",
            provider: "openai",
            model: "gpt-test",
            systemPrompt: "  ",
            metadata: [:]
        )
        let selection = NapaxiConfigSelection(
            selectedProfileId: nil,
            selectedProfileIdByCapability: ["chat": "primary"]
        )

        let profileJSON = try JSONDecoder().decode(
            NapaxiJSONValue.self,
            from: JSONEncoder().encode(profile)
        )
        let selectionJSON = try JSONDecoder().decode(
            NapaxiJSONValue.self,
            from: JSONEncoder().encode(selection)
        )

        guard case .object(let profileMap) = profileJSON,
              case .object(let selectionMap) = selectionJSON else {
            return XCTFail("Expected encoded objects")
        }

        XCTAssertEqual(profileMap["base_url"], .null)
        XCTAssertEqual(profileMap["extra_headers"], .null)
        XCTAssertNil(profileMap["system_prompt"])
        XCTAssertNil(profileMap["metadata"])
        XCTAssertEqual(profileMap["context_engine"]?.objectValue?["pre_compaction_memory_flush"], .bool(false))
        XCTAssertEqual(selectionMap["selected_profile_id"], .null)
        XCTAssertEqual(selectionMap["selected_profile_id_by_capability"], .object(["chat": .string("primary")]))
    }

    func testSavesProfilesWithoutWritingAPIKeysToPlainStorage() async throws {
        let plainStore = NapaxiMemoryConfigStore()
        let secretStore = NapaxiMemoryConfigStore()
        let store = NapaxiConfigStore(keyValueStore: plainStore, secretStore: secretStore)

        try await store.saveProfile(
            NapaxiConfigProfile(
                id: "primary",
                name: "Primary",
                provider: "openai",
                model: "gpt-test",
                baseUrl: "https://api.example",
                systemPrompt: "Use the profile prompt.",
                maxTokens: 12_345,
                maxToolIterations: -1,
                extraHeaders: "X-Test:1",
                allowedModels: [["name": "Fast", "id": "fast-model"]],
                imageModel: "image-test",
                imageAnalysisModel: "vision-test",
                videoModel: "video-test",
                audioModel: "audio-test",
                contextEngine: ContextEngineConfig(
                    contextWindowTokens: 20_000,
                    responseReserveTokens: 1_024
                )
            ),
            apiKey: "sk-secret"
        )

        let profiles = try await store.loadProfiles()
        let config = try await store.resolveConfig("primary")
        let plainValues = plainStore.values.values.joined(separator: "\n")

        XCTAssertEqual(profiles.first?.model, "gpt-test")
        XCTAssertEqual(profiles.first?.imageAnalysisModel, "vision-test")
        XCTAssertEqual(config?.apiKey, "sk-secret")
        XCTAssertEqual(config?.baseUrl, "https://api.example")
        XCTAssertEqual(config?.systemPrompt, "Use the profile prompt.")
        XCTAssertEqual(config?.maxTokens, 12_345)
        XCTAssertEqual(config?.maxToolIterations, -1)
        XCTAssertEqual(config?.extraHeaders, "X-Test:1")
        XCTAssertEqual(config?.allowedModels, [["name": "Fast", "id": "fast-model"]])
        XCTAssertEqual(config?.imageModel, "image-test")
        XCTAssertEqual(config?.imageAnalysisModel, "vision-test")
        XCTAssertEqual(config?.videoModel, "video-test")
        XCTAssertEqual(config?.audioModel, "audio-test")
        XCTAssertEqual(config?.contextEngine.contextWindowTokens, 20_000)
        XCTAssertEqual(config?.contextEngine.responseReserveTokens, 1_024)
        XCTAssertFalse(plainValues.contains("sk-secret"))
        XCTAssertEqual(Array(secretStore.values.values), ["sk-secret"])
    }

    func testConfigStorePersistsFlutterMapShape() async throws {
        let plainStore = NapaxiMemoryConfigStore()
        let store = NapaxiConfigStore(keyValueStore: plainStore, secretStore: NapaxiMemoryConfigStore())

        try await store.saveProfile(NapaxiConfigProfile(
            id: "primary",
            name: "Primary",
            provider: "openai",
            model: "gpt-test"
        ))
        try await store.saveSelection(NapaxiConfigSelection(
            selectedProfileIdByCapability: ["chat": "primary"]
        ))

        let profilesValue = try XCTUnwrap(plainStore.values[NapaxiConfigStore.profilesKey])
        let selectionValue = try XCTUnwrap(plainStore.values[NapaxiConfigStore.selectionKey])
        guard case .array(let profileItems) = try NapaxiRawJSON(jsonString: profilesValue).value,
              case .object(let profileMap) = profileItems.first else {
            return XCTFail("Expected persisted profile list")
        }
        guard case .object(let selectionMap) = try NapaxiRawJSON(jsonString: selectionValue).value else {
            return XCTFail("Expected persisted selection map")
        }

        XCTAssertEqual(profileMap["base_url"], .null)
        XCTAssertEqual(profileMap["extra_headers"], .null)
        XCTAssertEqual(selectionMap["selected_profile_id"], .null)
        XCTAssertEqual(selectionMap["selected_profile_id_by_capability"], .object(["chat": .string("primary")]))
    }

    func testLoadsFlutterSparseConfigStorePayloads() async throws {
        let plainStore = NapaxiMemoryConfigStore()
        let store = NapaxiConfigStore(keyValueStore: plainStore, secretStore: NapaxiMemoryConfigStore())

        try await plainStore.write(NapaxiConfigStore.profilesKey, value: """
        [
          {"id":"primary","provider":"openai","model":"gpt-test","max_tokens":"12345","context_engine":{"context_window_tokens":20000}},
          42,
          {"id":""}
        ]
        """)
        try await plainStore.write(NapaxiConfigStore.selectionKey, value: """
        {
          "selected_profile_id": "missing",
          "selected_profile_id_by_capability": {"chat":"primary","image":"missing"},
          "max_tool_iterations": "7"
        }
        """)

        let profiles = try await store.loadProfiles()
        let selection = try await store.loadSelection()

        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.id, "primary")
        XCTAssertEqual(profiles.first?.name, "")
        XCTAssertEqual(profiles.first?.maxTokens, NapaxiConfigProfile.defaultMaxTokens)
        XCTAssertEqual(profiles.first?.contextEngine.contextWindowTokens, 20_000)
        XCTAssertNil(selection.selectedProfileId)
        XCTAssertEqual(selection.selectedProfileIdByCapability, ["chat": "primary"])
        XCTAssertEqual(selection.systemPrompt, "")
        XCTAssertEqual(selection.maxToolIterations, 50)
    }

    func testConfigStoreInvalidJsonMatchesFlutterDecodeFailure() async throws {
        let plainStore = NapaxiMemoryConfigStore()
        let store = NapaxiConfigStore(keyValueStore: plainStore, secretStore: NapaxiMemoryConfigStore())

        try await plainStore.write(NapaxiConfigStore.profilesKey, value: "{")
        do {
            _ = try await store.loadProfiles()
            XCTFail("Expected invalid profile JSON to throw")
        } catch {
            XCTAssertNotNil(error)
        }

        try await plainStore.write(NapaxiConfigStore.profilesKey, value: "[]")
        try await plainStore.write(NapaxiConfigStore.selectionKey, value: "{")
        do {
            _ = try await store.loadSelection()
            XCTFail("Expected invalid selection JSON to throw")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    func testConfigStoreRejectsMalformedAllowedModelsLikeFlutter() async throws {
        let plainStore = NapaxiMemoryConfigStore()
        let store = NapaxiConfigStore(keyValueStore: plainStore, secretStore: NapaxiMemoryConfigStore())

        try await plainStore.write(NapaxiConfigStore.profilesKey, value: """
        [
          {
            "id": "primary",
            "provider": "openai",
            "model": "gpt-test",
            "allowed_models": [
              {"name": "Fast", "id": 42}
            ]
          }
        ]
        """)

        do {
            _ = try await store.loadProfiles()
            XCTFail("Expected malformed allowed_models to throw")
        } catch {
            XCTAssertEqual(error as? NapaxiError, .invalidJSON("allowed_models values must be strings"))
        }
    }

    func testConfigStoreRejectsMalformedCapabilitySelectionLikeFlutter() async throws {
        let plainStore = NapaxiMemoryConfigStore()
        let store = NapaxiConfigStore(keyValueStore: plainStore, secretStore: NapaxiMemoryConfigStore())

        try await plainStore.write(NapaxiConfigStore.profilesKey, value: """
        [
          {"id":"primary","provider":"openai","model":"gpt-test"}
        ]
        """)
        try await plainStore.write(NapaxiConfigStore.selectionKey, value: """
        {
          "selected_profile_id_by_capability": {"chat": 42}
        }
        """)

        do {
            _ = try await store.loadSelection()
            XCTFail("Expected malformed selected_profile_id_by_capability to throw")
        } catch {
            XCTAssertEqual(
                error as? NapaxiError,
                .invalidJSON("selected_profile_id_by_capability values must be strings")
            )
        }
    }

    func testDeletesProfileDataAndAPIKeyTogether() async throws {
        let plainStore = NapaxiMemoryConfigStore()
        let secretStore = NapaxiMemoryConfigStore()
        let store = NapaxiConfigStore(keyValueStore: plainStore, secretStore: secretStore)

        try await store.saveProfile(
            NapaxiConfigProfile(id: "primary", name: "Primary", provider: "openai", model: "gpt-test"),
            apiKey: "sk-secret"
        )
        try await store.saveSelection(NapaxiConfigSelection(
            selectedProfileId: "primary",
            selectedProfileIdByCapability: ["chat": "primary"],
            systemPrompt: "Global prompt",
            maxToolIterations: 77
        ))

        try await store.deleteProfile("primary")

        let selection = try await store.loadSelection()
        let profiles = try await store.loadProfiles()
        let resolvedConfig = try await store.resolveConfig("primary")
        XCTAssertEqual(profiles, [])
        XCTAssertNil(resolvedConfig)
        XCTAssertEqual(secretStore.values, [:])
        XCTAssertNil(selection.selectedProfileId)
        XCTAssertEqual(selection.selectedProfileIdByCapability, [:])
        XCTAssertEqual(selection.systemPrompt, "Global prompt")
        XCTAssertEqual(selection.maxToolIterations, 77)
    }

    func testNormalizesStaleProfileSelections() async throws {
        let store = NapaxiConfigStore.memory()

        try await store.saveProfile(NapaxiConfigProfile(
            id: "primary",
            name: "Primary",
            provider: "openai",
            model: "gpt-test"
        ))
        try await store.saveSelection(NapaxiConfigSelection(
            selectedProfileId: "missing",
            selectedProfileIdByCapability: [
                "chat": "primary",
                "imageGeneration": "missing",
            ],
            systemPrompt: "Global prompt",
            maxToolIterations: -1
        ))

        let selection = try await store.loadSelection()

        XCTAssertNil(selection.selectedProfileId)
        XCTAssertEqual(selection.selectedProfileIdByCapability, ["chat": "primary"])
        XCTAssertEqual(selection.systemPrompt, "Global prompt")
        XCTAssertEqual(selection.maxToolIterations, -1)
    }
}
