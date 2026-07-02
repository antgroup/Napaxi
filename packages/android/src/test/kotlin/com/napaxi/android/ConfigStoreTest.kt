package com.napaxi.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ConfigStoreTest {
    @Test
    fun profilePersistsMetadataSeparatelyFromApiKeyAndResolvesConfig() {
        val store = NapaxiConfigStore.memory()
        val profile = NapaxiConfigProfile(
            id = "main",
            name = "Main",
            provider = "openai_compatible",
            baseUrl = "https://example.test/v1",
            model = "chat-model",
            systemPrompt = "Be concise",
            maxTokens = 2048,
            maxToolIterations = 7,
            extraHeaders = "X-Test:1",
            userTimezone = "Asia/Shanghai",
            allowedModels = listOf(mapOf("id" to "chat-model", "label" to "Chat")),
            imageModel = "image-model",
            imageAnalysisModel = "vision-model",
            videoModel = "video-model",
            audioModel = "audio-model",
            contextEngine = ContextEngineConfig(
                enabled = true,
                engine = "compressor",
                triggerRatio = 0.72,
                targetRatio = 0.38,
                protectHeadMessages = 3,
                protectTailMessages = 11,
                contextWindowTokens = 32000,
                nativeContextWindowTokens = 1000000,
                providerContextWindowTokens = 128000,
                responseReserveTokens = 2048,
                compactionStrategy = "llm_summary",
                compactionModel = "summary-model",
                compactionTimeoutMs = 45000,
                preCompactionMemoryFlush = true,
            ),
        )

        store.saveProfile(profile, apiKey = "secret-key")
        val loaded = store.loadProfiles().single()
        val resolved = store.resolveConfig("main")
        val profileMap = loaded.toMap()
        val profileFromMap = NapaxiConfigProfile.fromMap(profileMap)

        assertEquals("main", loaded.id)
        assertEquals("Main", profileMap["name"])
        assertEquals("openai_compatible", profileFromMap.provider)
        assertEquals("chat-model", profileFromMap.allowedModels?.single()?.get("id"))
        assertEquals("openai_compatible", resolved?.provider)
        assertEquals("secret-key", resolved?.apiKey)
        assertEquals("https://example.test/v1", resolved?.baseUrl)
        assertEquals("chat-model", resolved?.model)
        assertEquals("Be concise", resolved?.systemPrompt)
        assertEquals(2048, resolved?.maxTokens)
        assertEquals(7, resolved?.maxToolIterations)
        assertEquals("X-Test:1", resolved?.extraHeaders)
        assertEquals("Asia/Shanghai", profileFromMap.userTimezone)
        assertEquals("Asia/Shanghai", resolved?.userTimezone)
        assertEquals(listOf(mapOf("id" to "chat-model", "label" to "Chat")), resolved?.allowedModels)
        assertEquals("image-model", resolved?.imageModel)
        assertEquals("vision-model", resolved?.imageAnalysisModel)
        assertEquals("video-model", resolved?.videoModel)
        assertEquals("audio-model", resolved?.audioModel)
        assertEquals(0.72, resolved?.contextEngine?.triggerRatio ?: 0.0, 0.001)
        assertEquals(0.38, profileFromMap.contextEngine.targetRatio, 0.001)
        assertEquals(32000, profileFromMap.contextEngine.contextWindowTokens)
        assertEquals(1000000, profileFromMap.contextEngine.nativeContextWindowTokens)
        assertEquals(128000, resolved?.contextEngine?.providerContextWindowTokens)
        assertEquals(2048, resolved?.contextEngine?.responseReserveTokens)
        assertEquals("summary-model", resolved?.contextEngine?.compactionModel)
        assertEquals(45000L, resolved?.contextEngine?.compactionTimeoutMs)
        assertEquals(true, resolved?.contextEngine?.preCompactionMemoryFlush)
    }

    @Test
    fun selectionIsNormalizedWhenProfilesChange() {
        val store = NapaxiConfigStore.memory()
        store.saveProfile(
            NapaxiConfigProfile(
                id = "main",
                name = "Main",
                provider = "anthropic",
                model = "claude",
            ),
        )
        store.saveProfile(
            NapaxiConfigProfile(
                id = "vision",
                name = "Vision",
                provider = "openai",
                model = "vision",
            ),
        )
        store.saveSelection(
            NapaxiConfigSelection(
                selectedProfileId = "main",
                selectedProfileIdByCapability = mapOf(
                    "napaxi.llm.chat" to "main",
                    "napaxi.llm.image_analysis" to "vision",
                    "napaxi.llm.missing" to "missing",
                ),
                systemPrompt = "Host prompt",
                maxToolIterations = 9,
            ),
        )

        assertEquals(
            mapOf(
                "napaxi.llm.chat" to "main",
                "napaxi.llm.image_analysis" to "vision",
            ),
            store.loadSelection().selectedProfileIdByCapability,
        )

        store.deleteProfile("main")
        val selection = store.loadSelection()
        val selectionFromMap = NapaxiConfigSelection.fromMap(selection.toMap())

        assertNull(selection.selectedProfileId)
        assertEquals(mapOf("napaxi.llm.image_analysis" to "vision"), selection.selectedProfileIdByCapability)
        assertEquals(selection.selectedProfileIdByCapability, selectionFromMap.selectedProfileIdByCapability)
        assertEquals("", store.readApiKey("main"))
    }

    @Test
    fun selectedConfigResolvesDefaultAndCapabilitySpecificProfiles() {
        val store = NapaxiConfigStore.memory()
        store.saveProfile(
            NapaxiConfigProfile(
                id = "chat",
                name = "Chat",
                provider = "openai",
                model = "gpt-test",
            ),
            apiKey = "chat-key",
        )
        store.saveProfile(
            NapaxiConfigProfile(
                id = "vision",
                name = "Vision",
                provider = "openai_compatible",
                baseUrl = "https://vision.test/v1",
                model = "vision-test",
            ),
            apiKey = "vision-key",
        )
        store.saveSelection(
            NapaxiConfigSelection(
                selectedProfileId = "chat",
                selectedProfileIdByCapability = mapOf("napaxi.llm.image_analysis" to "vision"),
            ),
        )

        val defaultConfig = store.resolveSelectedConfig()
        val visionConfig = store.resolveSelectedConfig("napaxi.llm.image_analysis")
        val missingOverrideConfig = store.resolveSelectedConfig("napaxi.llm.audio")

        assertEquals("gpt-test", defaultConfig?.model)
        assertEquals("chat-key", defaultConfig?.apiKey)
        assertEquals("vision-test", visionConfig?.model)
        assertEquals("vision-key", visionConfig?.apiKey)
        assertEquals("https://vision.test/v1", visionConfig?.baseUrl)
        assertEquals("gpt-test", missingOverrideConfig?.model)
    }

    @Test
    fun invalidPersistedJsonFallsBackToFlutterStyleDefaults() {
        val backing = NapaxiMemoryConfigStore()
        val store = NapaxiConfigStore(keyValueStore = backing, secretStore = backing)

        backing.write("napaxi.config.profiles.v1", "{not json")
        backing.write("napaxi.config.selection.v1", "{not json")

        val selection = store.loadSelection()

        assertEquals(emptyList<NapaxiConfigProfile>(), store.loadProfiles())
        assertNull(selection.selectedProfileId)
        assertEquals(emptyMap<String, String>(), selection.selectedProfileIdByCapability)
        assertEquals("", selection.systemPrompt)
        assertEquals(50, selection.maxToolIterations)
    }

    @Test
    fun emptyApiKeyDeletesStoredSecretLikeFlutterConfigStore() {
        val store = NapaxiConfigStore.memory()
        val profile = NapaxiConfigProfile(
            id = "main",
            name = "Main",
            provider = "openai",
            model = "gpt-test",
        )

        store.saveProfile(profile, apiKey = "secret-key")
        assertEquals("secret-key", store.readApiKey("main"))

        store.saveProfile(profile, apiKey = "")

        assertEquals("", store.readApiKey("main"))
        assertEquals("", store.resolveConfig("main")?.apiKey)
    }
}
