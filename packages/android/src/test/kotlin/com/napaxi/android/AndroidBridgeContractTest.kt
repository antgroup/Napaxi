package com.napaxi.android

import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.Paths

class AndroidBridgeContractTest {
    @Test
    fun androidManifestPreservesFlutterBackgroundProviderAndFileBridgeCapabilities() {
        val root = repoRoot()
        val flutterManifest = readText(root.resolve("packages/flutter/android/AndroidManifest.xml"))
        val androidManifest = readText(root.resolve("packages/android/src/main/AndroidManifest.xml"))
        val fileProviderSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiFileProvider.kt"))

        val flutterPermissions = manifestPermissions(flutterManifest)
        val androidPermissions = manifestPermissions(androidManifest)
        val requiredManifestSnippets = listOf(
            "com.napaxi.android.NapaxiAgentService",
            "android:foregroundServiceType=\"specialUse\"",
            "android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE",
            "com.napaxi.android.AgentTriggerIngressService",
            "android:exported=\"true\"",
            "com.napaxi.android.NapaxiActionReceiver",
            "com.napaxi.android.NapaxiFileProvider",
            "\${applicationId}.napaxi.fileprovider",
            "android:grantUriPermissions=\"true\"",
            "agent.provider.action.INSTALL_AGENT",
            "agent.provider.action.HANDLE_PROPOSAL",
        )
        val requiredProviderSnippets = listOf(
            "\"files\" -> context.filesDir",
            "\"cache\" -> context.cacheDir",
            "\"external-files\" -> context.getExternalFilesDir(null)",
            "\"external-cache\" -> context.externalCacheDir",
            "context.getExternalFilesDir(null)?.canonicalFile",
            "\"external-files\"",
            "prepareShareableFile(context, file)",
            "File(context.cacheDir, \"napaxi-shared\")",
            "canonical.copyTo(target, overwrite = true)",
        )

        val missingPermissions = flutterPermissions - androidPermissions
        val missingManifestSnippets = requiredManifestSnippets.filterNot(androidManifest::contains)
        val missingProviderSnippets = requiredProviderSnippets.filterNot(fileProviderSource::contains)

        assertTrue(
            "Android native manifest is missing Flutter adapter permissions: $missingPermissions",
            missingPermissions.isEmpty(),
        )
        assertTrue(
            "Android native manifest is missing Flutter-equivalent background/provider/file components: $missingManifestSnippets",
            missingManifestSnippets.isEmpty(),
        )
        assertTrue(
            "Android native file provider is missing Flutter-equivalent share roots: $missingProviderSnippets",
            missingProviderSnippets.isEmpty(),
        )
    }

    @Test
    fun androidEnginePlatformContextMatchesFlutterRuntimeShape() {
        val root = repoRoot()
        val flutterEngine = readText(root.resolve("packages/flutter/lib/engine.dart"))
        val androidEngine = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))
        val androidPlatformContext = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/PlatformContext.kt"))
        val androidBuild = readText(root.resolve("packages/android/build.gradle.kts"))
        val androidRuntimeContext = androidEngine + "\n" + androidPlatformContext

        val requiredFlutterContextSnippets = listOf(
            "platformContextMap['capability_profile']",
            "platformContextMap['skill_readiness']",
            "platformContextMap['capability_selection']",
            "'use_process_fallback': false",
        )
        val requiredAndroidContextSnippets = listOf(
            "NapaxiPlatformContextResolver.resolve(context).platformContextJson",
            ".put(\"platform\", \"android\")",
            ".put(\"files_dir\", filesDir)",
            ".put(\"native_library_dir\", appContext.applicationInfo.nativeLibraryDir)",
            ".put(\"user_timezone\", userTimezone)",
            ".put(\"capability_profile\", profile.toJsonObject())",
            "\"skill_readiness\"",
            ".put(\"capabilities\", JSONArray(profile.supportedCapabilities))",
            ".put(\"use_process_fallback\", false)",
            ".put(\"capability_selection\", selection.toJsonObject())",
            "NapaxiNative.registerAssetManager(appContext.assets)",
        )
        val requiredAndroidCapabilitySnippets = listOf(
            "\"napaxi.platform_tool.*\".takeIf { enablePlatformTools }",
            "\"napaxi.platform_tool.take_photo\".takeIf { enablePlatformTools && !hasPlatformMediaToolHandler }",
            "\"napaxi.platform_tool.record_audio\".takeIf { enablePlatformTools && !hasPlatformMediaToolHandler }",
        )
        val requiredBuildSnippets = listOf(
            "assets.srcDirs(\"../flutter/android/assets\")",
            "jniLibs.srcDirs(\"../flutter/android/jniLibs\")",
            "libnapaxi_api_bridge.so",
            "api(\"agent.provider:android_agent_provider:",
        )

        val missingFlutterSnippets = requiredFlutterContextSnippets.filterNot(flutterEngine::contains)
        val missingAndroidSnippets = requiredAndroidContextSnippets.filterNot(androidRuntimeContext::contains)
        val missingCapabilitySnippets = requiredAndroidCapabilitySnippets.filterNot(androidEngine::contains)
        val missingBuildSnippets = requiredBuildSnippets.filterNot(androidBuild::contains)
        val selectionBody = classFunctionBody(androidEngine, "buildHostCapabilitySelection")

        assertTrue("Expected Flutter engine platform context shape to be discovered: $missingFlutterSnippets", missingFlutterSnippets.isEmpty())
        assertTrue(
            "Android engine platform context is missing Flutter runtime context fields: $missingAndroidSnippets",
            missingAndroidSnippets.isEmpty(),
        )
        assertTrue(
            "Android engine capability profile/selection is missing Flutter-equivalent runtime capability handling: $missingCapabilitySnippets",
            missingCapabilitySnippets.isEmpty(),
        )
        assertTrue(
            "Android capability selection should not explicitly enable the platform tool wildcard; it belongs in the profile like Flutter.",
            !selectionBody.contains("napaxi.platform_tool.*"),
        )
        assertTrue(
            "Android native SDK build is missing Flutter runtime asset/JNI/provider inputs: $missingBuildSnippets",
            missingBuildSnippets.isEmpty(),
        )
    }

    @Test
    fun kotlinBridgeMethodsHaveAndroidJniDispatchEntries() {
        val root = repoRoot()
        val androidSourceDir = root.resolve("packages/android/src/main/kotlin/com/napaxi/android")
        val androidJniSource = readText(root.resolve("packages/api_bridge/android_jni.rs"))

        val kotlinMethods = sortedSetOf<String>()
        Files.walk(androidSourceDir).use { paths ->
            val iterator = paths.iterator()
            while (iterator.hasNext()) {
                val path = iterator.next()
                if (path.toString().endsWith(".kt")) {
                    val source = readText(path)
                    bridgeMethodRegex.findAll(source).forEach { match ->
                        kotlinMethods += match.groupValues[1]
                    }
                    directCallBridgeMethodRegex.findAll(source).forEach { match ->
                        kotlinMethods += match.groupValues[1]
                    }
                }
            }
        }

        val missing = kotlinMethods.filterNot { method ->
            androidJniSource.contains("\"$method\"")
        }

        assertTrue(
            "Missing Android JNI dispatch entries for Kotlin bridge methods: $missing",
            missing.isEmpty(),
        )
        assertTrue("Expected Kotlin bridge methods to be discovered", kotlinMethods.isNotEmpty())
    }

    @Test
    fun androidChatEventsCoverFlutterStableEventTypes() {
        val root = repoRoot()
        val flutterChatEvents = readText(root.resolve("packages/flutter/lib/models/chat_event.dart"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))
        val flutterTypes = flutterEventTypeRegex.findAll(flutterChatEvents)
            .map { it.groupValues[1] }
            .toSet()
        val requiredAndroidSnippets = listOf(
            "fun fromJsonString(json: String): ChatEvent",
            "fun fromJsonObject(obj: JSONObject): ChatEvent",
            "fun fromMap(map: Map<String, *>): ChatEvent",
            "fun fromMap(map: Map<String, *>): EvolutionQueuedRun",
            "fun fromMap(map: Map<String, *>): ActivatedSkillInfo",
        )

        assertTrue(
            "Android ChatEvent is missing Flutter event types: ${flutterTypes - ChatEvent.flutterParityEventTypes()}",
            ChatEvent.flutterParityEventTypes().containsAll(flutterTypes),
        )
        assertTrue("Expected Flutter chat event types to be discovered", flutterTypes.isNotEmpty())
        assertTrue(
            "Android ChatEvent is missing Flutter-style parse helpers: ${requiredAndroidSnippets.filterNot(androidModels::contains)}",
            requiredAndroidSnippets.all(androidModels::contains),
        )
    }

    @Test
    fun androidSessionRunModelsCoverFlutterStableWireNames() {
        val root = repoRoot()
        val flutterSessionRuns = readText(root.resolve("packages/flutter/lib/models/session_run.dart"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))

        val flutterStatuses = enumWireNames(flutterSessionRuns, "SessionRunRecordStatus")
        val flutterEvidenceKinds = enumWireNames(flutterSessionRuns, "RunEvidenceKind")
        val flutterVerifications = enumWireNames(flutterSessionRuns, "RunVerification")

        assertTrue(
            "Android SessionRunRecordStatus is missing Flutter statuses: ${flutterStatuses - SessionRunRecordStatus.flutterParityWireNames()}",
            SessionRunRecordStatus.flutterParityWireNames().containsAll(flutterStatuses),
        )
        assertTrue(
            "Android RunEvidenceKind is missing Flutter evidence kinds: ${flutterEvidenceKinds - RunEvidenceKind.flutterParityWireNames()}",
            RunEvidenceKind.flutterParityWireNames().containsAll(flutterEvidenceKinds),
        )
        assertTrue(
            "Android RunVerification is missing Flutter verification values: ${flutterVerifications - RunVerification.flutterParityWireNames()}",
            RunVerification.flutterParityWireNames().containsAll(flutterVerifications),
        )
        assertTrue("Expected Flutter session run statuses to be discovered", flutterStatuses.isNotEmpty())
        assertTrue("Expected Flutter session run evidence kinds to be discovered", flutterEvidenceKinds.isNotEmpty())
        assertTrue("Expected Flutter session run verifications to be discovered", flutterVerifications.isNotEmpty())
        assertTrue(
            "Android session run models are missing Flutter-style decode helper",
            androidModels.contains("fun decodeSessionRunRecords(rawJson: String): List<SessionRunRecord>"),
        )
    }

    @Test
    fun androidSessionHistoryModelsExposeFlutterStableJsonHelpers() {
        val root = repoRoot()
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))

        val requiredSnippets = listOf(
            "public class ChatAttachment(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): ChatAttachment",
            "public class ToolCallInfo(rawJson: String)",
            "public val resultTruncated: Boolean",
            "public val errorTruncated: Boolean",
            "public val argumentsTruncated: Boolean",
            "public fun fromMap(map: Map<String, *>): ToolCallInfo",
            "public class ChatMessage(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): ChatMessage",
            "public class HistoryPage(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): HistoryPage",
            "public class ContextTokenBreakdown(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): ContextTokenBreakdown",
            "public class ContextBudgetStatus(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): ContextBudgetStatus",
            "public class ContextStatus(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): ContextStatus",
        )
        val missing = requiredSnippets.filterNot(androidModels::contains)

        assertTrue(
            "Android session history/context models are missing Flutter-style JSON helpers: $missing",
            missing.isEmpty(),
        )
    }

    @Test
    fun androidCapabilityModelsExposeFlutterStableJsonHelpers() {
        val root = repoRoot()
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))

        val requiredSnippets = listOf(
            "public class NapaxiCapabilityDefinition(rawJson: String = \"{}\")",
            "public constructor(",
            "public fun toJsonObject(): JSONObject",
            "public fun toJsonString(): String = toJson()",
            "public fun fromJsonObject(obj: JSONObject): NapaxiCapabilityDefinition",
            "public fun fromMap(map: Map<String, *>): NapaxiCapabilityDefinition",
            "public class NapaxiCapabilityStatus(rawJson: String = \"{}\")",
            "public fun fromJsonObject(obj: JSONObject): NapaxiCapabilityStatus",
            "public fun fromMap(map: Map<String, *>): NapaxiCapabilityStatus",
            "fun decodeCapabilityDefinitions(rawJson: String): List<NapaxiCapabilityDefinition>",
            "fun decodeCapabilityStatuses(rawJson: String): List<NapaxiCapabilityStatus>",
            "public class NapaxiScenarioSettingsContribution(rawJson: String = \"{}\")",
            "public class NapaxiScenarioUiContribution(rawJson: String = \"{}\")",
            "public class NapaxiScenarioPack(rawJson: String = \"{}\")",
            "public class NapaxiScenarioStatus(rawJson: String = \"{}\")",
            "public class NapaxiScenarioActivationPlan(rawJson: String = \"{}\")",
            "public class NapaxiScenarioResolution(rawJson: String = \"{}\")",
            "public class NapaxiScenarioPackInstallResult(rawJson: String = \"{}\")",
            "public class NapaxiScenarioPackRemovalResult(rawJson: String = \"{}\")",
            "fun decodeScenarioPacks(rawJson: String): List<NapaxiScenarioPack>",
            "fun decodeScenarioStatuses(rawJson: String): List<NapaxiScenarioStatus>",
            "fun decodeScenarioResolution(rawJson: String): NapaxiScenarioResolution?",
            "fun decodeScenarioPackInstallResult(rawJson: String): NapaxiScenarioPackInstallResult?",
            "fun decodeScenarioPackRemovalResult(rawJson: String): NapaxiScenarioPackRemovalResult?",
            "platform?.let { put(\"platform\", it) }",
        )
        val missing = requiredSnippets.filterNot(androidModels::contains)

        assertTrue(
            "Android capability models are missing Flutter-style JSON helpers: $missing",
            missing.isEmpty(),
        )
    }

    @Test
    fun androidFileBridgeExposesFlutterTypedConvenienceSurface() {
        val root = repoRoot()
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))

        val requiredApiSnippets = listOf(
            "suspend fun resolveFile(",
            "suspend fun deleteFile(",
            "suspend fun deleteFileScoped(",
            "suspend fun detectFileReferences(",
            "suspend fun detectFileReferencesScoped(",
            "suspend fun listFiles(",
            "suspend fun listFilesScoped(",
            "suspend fun workspaceSizeScoped(",
        )
        val requiredModelSnippets = listOf(
            "data class ResolvedFile",
            "fun fromMap(map: Map<String, *>): ResolvedFile",
            "data class WorkspaceFileInfo",
            "fun fromMap(map: Map<String, *>): WorkspaceFileInfo",
            "val sandboxPath: String",
            "val realPath: String",
            "val mimeType: String",
            "val sizeBytes:",
            "public class WorkspaceFile(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): WorkspaceFile",
            "public class WorkspaceEntry(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): WorkspaceEntry",
            "public class MemorySearchResult(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): MemorySearchResult",
            "public class MemoryRecallSnippet(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): MemoryRecallSnippet",
            "public class MemoryRecallSession(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): MemoryRecallSession",
            "public class RecallIndexStats(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): RecallIndexStats",
            "public class JournalDay(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): JournalDay",
            "public class JournalTurnRecord(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): JournalTurnRecord",
        )

        val missingApis = requiredApiSnippets.filterNot(androidApis::contains)
        val missingModels = requiredModelSnippets.filterNot(androidModels::contains)

        assertTrue("Android FileBridgeApi is missing Flutter-style typed methods: $missingApis", missingApis.isEmpty())
        assertTrue("Android file bridge models are missing Flutter-style fields: $missingModels", missingModels.isEmpty())
    }

    @Test
    fun androidProviderApisExposeFlutterStylePendingInstallAndAcceptedTriggerSurface() {
        val root = repoRoot()
        val androidProviders = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/AgentProviders.kt"))
        val providerAliases = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/ProviderProtocolAliases.kt"))
        val providerModels = readText(root.resolve("packages/agent_provider/android/src/main/kotlin/agent/provider/sdk/Models.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidTooling = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Tooling.kt"))
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))
        val androidReadme = readText(root.resolve("packages/android/README.md"))

        val requiredProviderSnippets = listOf(
            "data class AgentProviderDescriptor",
            "fun toJsonObject(includeAliases: Boolean = true): JSONObject",
            "fun toJsonString(): String = toJson()",
            "fun fromJsonObject(obj: JSONObject): AgentProviderDescriptor",
            "fun fromMap(map: Map<String, *>): AgentProviderDescriptor",
            "data class PendingAgentProviderInstall",
            "val requestCode: Int = AgentProviderHostApi.REQUEST_INSTALL_AGENT",
            "class AgentProviderInstallApi",
            "class AgentProviderTriggerApi",
            "fun beginInstallFromLaunchIntent(",
            "fun installFromLaunchIntent(",
            "suspend fun handleActivityResult(",
            "suspend fun handleInstallActivityResult(",
            "expectedRequestCode: Int =",
            "fun consumePendingTrigger(",
            "suspend fun validateTrigger(request: AgentTriggerRequest)",
            "fun resolveProviderInstallDescriptor(",
        )
        val requiredProviderAliasSnippets = listOf(
            "typealias AgentInstallRequest",
            "typealias AgentInstallResult",
            "typealias AgentInstallStatus",
            "typealias AgentTriggerRequest",
            "typealias AgentTriggerSubmitResult",
            "typealias AgentPackage",
            "typealias AgentAction",
            "typealias ActionProposal",
            "typealias ProviderActionResult",
            "typealias ProviderActionError",
            "typealias ProviderProposalValidationResult",
        )
        val requiredProviderSdkModelSnippets = listOf(
            "data class AgentPackage",
            "fun fromJsonObject(obj: JSONObject): AgentPackage",
            "fun fromMap(map: Map<String, *>): AgentPackage",
            "data class AgentAction",
            "fun fromJsonObject(obj: JSONObject): AgentAction",
            "fun fromMap(map: Map<String, *>): AgentAction",
            "data class ActionProposal",
            "fun fromJsonObject(obj: JSONObject): ActionProposal",
            "fun fromMap(map: Map<String, *>): ActionProposal",
            "data class ActionResult",
            "fun fromJsonObject(obj: JSONObject): ActionResult",
            "fun fromMap(map: Map<String, *>): ActionResult",
            "data class ActionError",
            "fun fromJsonObject(obj: JSONObject): ActionError",
            "fun fromMap(map: Map<String, *>): ActionError",
            "data class AgentInstallResult",
            "fun fromJsonObject(obj: JSONObject): AgentInstallResult",
            "fun fromMap(map: Map<String, *>): AgentInstallResult",
            "data class AgentTriggerRequest",
            "fun toJsonString(): String = toJson()",
            "fun toJsonObject(): JSONObject",
            "fun fromJsonObject(obj: JSONObject): AgentTriggerRequest",
            "fun fromMap(map: Map<String, *>): AgentTriggerRequest",
            "data class AgentTriggerSubmitResult",
            "fun fromJsonObject(obj: JSONObject): AgentTriggerSubmitResult",
            "fun fromMap(map: Map<String, *>): AgentTriggerSubmitResult",
        )
        val requiredTriggerModelSnippets = listOf(
            "class AcceptedAgentTrigger",
            "val request: AgentTriggerRequest?",
            "val requestJson: String",
            "val requestId: String",
            "val displayName: String",
        )
        val requiredAgentAppModelSnippets = listOf(
            "data class AgentAppInstallBinding",
            "fun fromJsonObject(obj: JSONObject): AgentAppInstallBinding",
            "fun fromMap(map: Map<String, *>): AgentAppInstallBinding",
            "class AgentAppActionManifest",
            "typealias AgentAppPackageAction",
            "class AgentAppActionResult",
            "val providerTraceId: String?",
            "class AgentAppActionRecord",
            "val proposal: AgentAppActionProposal",
            "val displayName: String",
            "val systemPrompt: String",
            "fun decodeAgentAppPackages(rawJson: String): List<AgentAppPackage>",
            "fun decodeAgentAppActionRecords(rawJson: String): List<AgentAppActionRecord>",
        )
        val requiredAgentAppApiSnippets = listOf(
            "registerPackage(packageDef: AgentAppPackage)",
            "suspend fun submitActionResult(resultJson: String): AgentAppActionRecord",
            "suspend fun submitActionResult(result: AgentAppActionResult): AgentAppActionRecord",
            "suspend fun submitResult(resultJson: String): AgentAppActionRecord",
            "suspend fun submitResult(result: AgentAppActionResult): AgentAppActionRecord",
            "acceptTrigger(request: AgentTriggerRequest)",
        )
        val requiredToolingSnippets = listOf(
            "typealias McAgentAppActionExecutor",
            "data class AgentAppActionRequest",
            "val `package`: org.json.JSONObject",
            "fun toJsonObject(): JSONObject",
            "fun toJsonString(): String = toJson()",
            "fun fromJsonObject(obj: JSONObject): AgentAppActionRequest",
            "fun fromMap(map: Map<String, *>): AgentAppActionRequest",
        )
        val requiredEngineSnippets = listOf(
            "val agentProviderInstall: AgentProviderInstallApi",
            "val agentProviderTrigger: AgentProviderTriggerApi",
            "suspend fun onAgentProviderInstallActivityResult(",
        )
        val requiredReadmeSnippets = listOf(
            "PendingAgentProviderInstall",
            "engine.onAgentProviderInstallActivityResult(",
            "installFromLaunchIntent(activity)",
        )

        val missingProviderSnippets = requiredProviderSnippets.filterNot(androidProviders::contains)
        val missingProviderAliasSnippets = requiredProviderAliasSnippets.filterNot(providerAliases::contains)
        val missingProviderSdkModelSnippets = requiredProviderSdkModelSnippets.filterNot(providerModels::contains)
        val missingTriggerModelSnippets = requiredTriggerModelSnippets.filterNot(androidModels::contains)
        val missingAgentAppModelSnippets = requiredAgentAppModelSnippets.filterNot(androidModels::contains)
        val missingAgentAppApiSnippets = requiredAgentAppApiSnippets.filterNot(androidApis::contains)
        val missingToolingSnippets = requiredToolingSnippets.filterNot(androidTooling::contains)
        val missingEngineSnippets = requiredEngineSnippets.filterNot(engineSource::contains)
        val missingReadmeSnippets = requiredReadmeSnippets.filterNot(androidReadme::contains)

        assertTrue(
            "Android provider install API is missing Flutter-style pending install helpers: $missingProviderSnippets",
            missingProviderSnippets.isEmpty(),
        )
        assertTrue(
            "Android SDK is missing com.napaxi.android provider protocol type exports: $missingProviderAliasSnippets",
            missingProviderAliasSnippets.isEmpty(),
        )
        assertTrue(
            "Android provider SDK models are missing Flutter-style parsing/JSON helpers: $missingProviderSdkModelSnippets",
            missingProviderSdkModelSnippets.isEmpty(),
        )
        assertTrue(
            "Android accepted trigger model is missing Flutter-style fields: $missingTriggerModelSnippets",
            missingTriggerModelSnippets.isEmpty(),
        )
        assertTrue(
            "Android Agent App models are missing Flutter-style typed fields: $missingAgentAppModelSnippets",
            missingAgentAppModelSnippets.isEmpty(),
        )
        assertTrue(
            "Android AgentAppApi is missing Flutter-style typed overloads: $missingAgentAppApiSnippets",
            missingAgentAppApiSnippets.isEmpty(),
        )
        assertTrue(
            "Android tooling aliases are missing Flutter stable names: $missingToolingSnippets",
            missingToolingSnippets.isEmpty(),
        )
        assertTrue(
            "Android NapaxiEngine is missing Flutter-style Agent Provider facade properties: $missingEngineSnippets",
            missingEngineSnippets.isEmpty(),
        )
        assertTrue(
            "Android README is missing Native provider install result handoff docs: $missingReadmeSnippets",
            missingReadmeSnippets.isEmpty(),
        )
    }

    @Test
    fun androidCoreApisExposeFlutterStyleTypedModelOverloads() {
        val root = repoRoot()
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))
        val androidBackground = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Background.kt"))

        val requiredApiSnippets = listOf(
            "createDefinition(definition: AgentDefinition)",
            "updateDefinition(definition: AgentDefinition)",
            "createAutomationJob(job: AutomationJob)",
            "updateAutomationJob(jobId: String, patch: JSONObject)",
            "updateAutomationJob(jobId: String, patch: Map<String, Any?>)",
        )
        val requiredModelSnippets = listOf(
            "fun create(",
            "fun fromFields(",
            "fun fromJson(rawJson: String): AgentDefinition",
            "fun fromMap(map: Map<String, *>): AgentDefinition",
            "fun fromMap(map: Map<String, *>): ScenePromptConfig",
            "fun fromMap(map: Map<String, *>): ContextEngineConfig",
            "fun fromMap(map: Map<String, *>): LlmCapabilityConfig",
            "fun fromMap(map: Map<String, *>): LlmConfig",
            "data class SessionInfo",
            "fun fromJson(rawJson: String): SessionInfo",
            "fun fromMap(map: Map<String, *>): SessionInfo",
            "class AutomationJob",
            "fun fromMap(map: Map<String, *>): AutomationTrigger",
            "fun fromMap(map: Map<String, *>): AutomationPayload",
            "fun fromMap(map: Map<String, *>): AutomationPolicy",
            "fun fromMap(map: Map<String, *>): AutomationJobState",
            "fun fromMap(map: Map<String, *>): AutomationJob",
            "fun fromMap(map: Map<String, *>): AutomationRun",
            "fun fromMap(map: Map<String, *>): AutomationWake",
            "fun decodeJsonObjectOrNull(rawJson: String): JSONObject?",
            "fun decodeAutomationJobs(rawJson: String): List<AutomationJob>",
            "fun decodeAutomationRuns(rawJson: String): List<AutomationRun>",
            "fun toJson(): String",
            "fun toJsonString(): String",
            "val compactionStrategy: String",
            "val lastCompactionDurationMs: Int?",
            "val nativeContextWindowTokens: Int?",
            "val providerContextWindowTokens: Int?",
            "val preCompactionMemoryFlush: Boolean",
            "val updatedAt: Long?",
            "val disabledCapabilities: List<String>",
            "val config: JSONObject",
            "val bytes: ByteArray",
        )
        val requiredBackgroundSnippets = listOf(
            "val wakeLockTimeout: java.time.Duration",
            "fun toJsonString(): String = toJson()",
            "fun fromJsonObject(obj: JSONObject): BackgroundNotificationConfig",
            "fun fromMap(map: Map<String, *>): BackgroundNotificationConfig",
            "fun fromJsonObject(obj: JSONObject): BackgroundConfig",
            "fun fromMap(map: Map<String, *>): BackgroundConfig",
            "fun fromJsonObject(obj: JSONObject): BackgroundActionEvent",
            "fun fromMap(map: Map<String, *>): BackgroundActionEvent",
        )
        val missingApis = requiredApiSnippets.filterNot(androidApis::contains)
        val missingModels = requiredModelSnippets.filterNot(androidModels::contains)
        val missingBackground = requiredBackgroundSnippets.filterNot(androidBackground::contains)

        assertTrue("Android APIs are missing Flutter-style typed model overloads: $missingApis", missingApis.isEmpty())
        assertTrue("Android typed models are missing JSON encode helpers: $missingModels", missingModels.isEmpty())
        assertTrue("Android background models are missing Flutter-style fields: $missingBackground", missingBackground.isEmpty())
    }

    @Test
    fun androidMcpApiExposesFlutterStyleTypedParameters() {
        val root = repoRoot()
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))

        val requiredSnippets = listOf(
            "headers: Map<String, String>",
            "JSONObject(headers).toString()",
            "clientId: String? = null",
            "clientSecret: String? = null",
            "authorizationUrl: String? = null",
            "tokenUrl: String? = null",
            "scopes: List<String> = emptyList()",
            "usePkce: Boolean? = null",
            "extraParams: Map<String, String> = emptyMap()",
            "resource: String? = null",
            "put(\"scopes\", JSONArray(scopes))",
            "put(\"extra_params\", JSONObject(extraParams))",
        )
        val requiredModelSnippets = listOf(
            "public class McpServerInfo(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): McpServerInfo",
            "public class McpToolInfo(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): McpToolInfo",
            "public class McpServerActionResult(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): McpServerActionResult",
            "public class McpOAuthStartResult(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): McpOAuthStartResult",
        )
        val missingSnippets = requiredSnippets.filterNot(androidApis::contains)
        val missingModelSnippets = requiredModelSnippets.filterNot(androidModels::contains)

        assertTrue(
            "Android McpApi is missing Flutter-style typed addServer/startOAuth parameters: $missingSnippets",
            missingSnippets.isEmpty(),
        )
        assertTrue(
            "Android MCP models are missing Flutter-style JSON helpers: $missingModelSnippets",
            missingModelSnippets.isEmpty(),
        )
    }

    @Test
    fun androidBrowserToolHostExposesFlutterStyleProviderAndApprovalSurface() {
        val root = repoRoot()
        val androidTooling = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Tooling.kt"))
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))
        val androidJni = readText(root.resolve("packages/api_bridge/android_jni.rs"))

        val requiredToolingSnippets = listOf(
            "object BrowserToolProvider",
            "class AndroidBrowserToolHost",
            "enum class BrowserMutationPolicy",
            "fun isBrowserTool(name: String)",
            "fun getToolDefinitions()",
            "Approve high-risk browser click",
            "val message: String? = null",
            "public fun toJsonString(): String = toJson()",
            "public fun fromJson(rawJson: String): McToolApprovalRequest",
            "public fun fromMap(map: Map<String, *>): McToolApprovalRequest",
            "public fun fromJson(rawJson: String): McToolApprovalResponse",
            "public fun fromMap(map: Map<String, *>): McToolApprovalResponse",
        )
        val requiredModelSnippets = listOf(
            "public data class CustomToolDef",
            "fun toJsonString(): String = toJson()",
            "public fun fromJson(rawJson: String): CustomToolDef",
            "public fun fromMap(map: Map<String, *>): CustomToolDef",
        )
        val requiredApiSnippets = listOf(
            "startRequestListener()",
            "engine.startToolRequestListener()",
            "browserToolDescriptors()",
            "isBrowserTool(name: String)",
        )
        val requiredEngineSnippets = listOf(
            "fun startToolRequestListener()",
            "registerToolDispatcher(",
            "toolDispatcherRegistered = true",
        )
        val requiredJniMethods = listOf(
            "\"tools.browser_tool_descriptors\"",
            "\"tools.is_browser_tool\"",
        )

        val missingTooling = requiredToolingSnippets.filterNot(androidTooling::contains)
        val missingModels = requiredModelSnippets.filterNot(androidModels::contains)
        val missingApis = requiredApiSnippets.filterNot(androidApis::contains)
        val missingEngine = requiredEngineSnippets.filterNot(engineSource::contains)
        val missingJni = requiredJniMethods.filterNot(androidJni::contains)

        assertTrue("Android browser tooling is missing Flutter-style host pieces: $missingTooling", missingTooling.isEmpty())
        assertTrue("Android custom tool models are missing Flutter-style JSON helpers: $missingModels", missingModels.isEmpty())
        assertTrue("Android ToolApi is missing browser tool helpers: $missingApis", missingApis.isEmpty())
        assertTrue("Android NapaxiEngine is missing Flutter-style tool request listener surface: $missingEngine", missingEngine.isEmpty())
        assertTrue("Android JNI dispatch allowlist is missing browser tool methods: $missingJni", missingJni.isEmpty())
    }

    @Test
    fun androidPlatformToolsPreserveFlutterStableResultShapes() {
        val root = repoRoot()
        val platformTools = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/PlatformTools.kt"))

        val requiredSnippets = listOf(
            "\"open_url\" -> openUrl(params)",
            ".put(\"success\", true)",
            ".put(\"url\", url)",
            ".put(\"has_content\", text.isNotEmpty())",
            ".put(\"copied_length\", text.length)",
            "\"send_notification\" -> sendNotification(params)",
            ".put(\"notification_id\", id)",
            "params.optString(\"apk_path\"",
            ".put(\"error\", \"apk_path is required.\")",
        )
        val missingSnippets = requiredSnippets.filterNot(platformTools::contains)

        assertTrue(
            "Android platform tools are missing Flutter-style stable result fields: $missingSnippets",
            missingSnippets.isEmpty(),
        )
    }

    @Test
    fun androidPlatformToolsCoverFlutterCapabilityHostDispatchNames() {
        val root = repoRoot()
        val flutterHost = readText(root.resolve("packages/flutter/lib/platform_tools/capability_host.dart"))
        val androidPlatformTools = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/PlatformTools.kt"))
        val androidReadme = readText(root.resolve("packages/android/README.md"))
        val flutterToolNames = Regex("""case\s+'([^']+)'\s*:""")
            .findAll(flutterHost)
            .map { it.groupValues[1] }
            .toSet()
        val androidToolNames = AndroidPlatformToolExecutor.platformToolNames
        val androidSwitchNames = Regex(""""([^"]+)"\s*->""")
            .findAll(androidPlatformTools)
            .map { it.groupValues[1] }
            .toSet()

        assertTrue("Expected Flutter platform tool names to be discovered", flutterToolNames.isNotEmpty())
        assertTrue(
            "Android platform tool name registry is missing Flutter platform tools: ${flutterToolNames - androidToolNames}",
            androidToolNames.containsAll(flutterToolNames),
        )
        assertTrue(
            "Android platform tool dispatcher is missing Flutter platform tools: ${flutterToolNames - androidSwitchNames}",
            androidSwitchNames.containsAll(flutterToolNames),
        )
        assertTrue(
            "Android README must document the Native media handler required for Flutter-style camera/audio tools",
            listOf(
                "AndroidPlatformMediaToolHandler",
                "take_photo",
                "media_library",
                "record_audio",
                "request.context.attachmentResultJson",
            ).all(androidReadme::contains),
        )
    }

    @Test
    fun androidEngineExposesFlutterStyleWorkspaceConvenienceSurface() {
        val root = repoRoot()
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))

        val requiredSnippets = listOf(
            "suspend fun readWorkspaceFile(",
            "suspend fun writeWorkspaceFile(",
            "suspend fun appendWorkspaceFile(",
            "suspend fun deleteWorkspaceFile(",
            "suspend fun listWorkspaceFiles(",
            "suspend fun searchMemory(",
            "suspend fun recallSessions(",
            "query: String,\n        limit: Int = 3,",
            "currentThreadId: String = \"\",",
            "suspend fun recallSessionsForThread(",
            "suspend fun rebuildRecallIndex(",
            "suspend fun recallIndexStats(",
            "suspend fun listJournalDays(",
            "suspend fun readJournalDay(",
            "suspend fun getSystemPrompt(",
            "suspend fun reseedWorkspace(",
        )
        val missingSnippets = requiredSnippets.filterNot(engineSource::contains)

        assertTrue(
            "Android NapaxiEngine is missing Flutter-style workspace convenience methods: $missingSnippets",
            missingSnippets.isEmpty(),
        )
    }

    @Test
    fun androidEngineExposesFlutterStyleAgentAndGroupConvenienceSurface() {
        val root = repoRoot()
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))

        val requiredAgentSnippets = listOf(
            "agentSend(",
            "agent: AgentHandle",
            "suspend fun deleteAgent(",
            "suspend fun createAgentDefinition(",
            "suspend fun listAgentDefinitions(",
            "suspend fun getAgentDefinition(",
            "suspend fun updateAgentDefinition(",
            "suspend fun deleteAgentDefinition(",
            "suspend fun importAgentMd(",
            "suspend fun listAvailableTools(",
            "suspend fun createAgentFromDefinition(",
        )
        val requiredGroupSnippets = listOf(
            "suspend fun createGroup(",
            "suspend fun deleteGroup(",
            "suspend fun listGroups(",
            "suspend fun getGroup(",
            "suspend fun renameGroup(",
            "suspend fun updateGroupMembers(",
            "suspend fun setGroupCustomPrompt(",
            "suspend fun getGroupMessages(",
            "suspend fun clearGroupHistory(",
            "suspend fun exportGroupState(",
            "suspend fun importGroupState(",
        )
        val requiredAgentApiSnippets = listOf(
            "send(",
            "agent: AgentHandle",
        )
        val requiredGroupModelSnippets = listOf(
            "public class ToolInfo(rawJson: String)",
            "fun fromMap(map: Map<String, *>): ToolInfo",
            "public class GroupInfo(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): GroupInfo",
            "public class GroupMessage(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): GroupMessage",
        )
        val missingAgentSnippets = requiredAgentSnippets.filterNot(engineSource::contains)
        val missingGroupSnippets = requiredGroupSnippets.filterNot(engineSource::contains)
        val missingAgentApiSnippets = requiredAgentApiSnippets.filterNot(androidApis::contains)
        val missingGroupModelSnippets = requiredGroupModelSnippets.filterNot(androidModels::contains)

        assertTrue(
            "Android NapaxiEngine is missing Flutter-style agent convenience methods: $missingAgentSnippets",
            missingAgentSnippets.isEmpty(),
        )
        assertTrue(
            "Android AgentApi is missing Flutter-style AgentHandle send overloads: $missingAgentApiSnippets",
            missingAgentApiSnippets.isEmpty(),
        )
        assertTrue(
            "Android NapaxiEngine is missing Flutter-style group convenience methods: $missingGroupSnippets",
            missingGroupSnippets.isEmpty(),
        )
        assertTrue(
            "Android group models are missing Flutter-style JSON helpers: $missingGroupModelSnippets",
            missingGroupModelSnippets.isEmpty(),
        )
    }

    @Test
    fun androidEngineExposesFlutterStyleA2AConvenienceSurface() {
        val root = repoRoot()
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))

        val requiredApiSnippets = listOf(
            "public class A2AApi",
            "fun generateLocalPairingSecret(",
            "fun normalizePairingSecret(",
            "fun formatPairingSecret(",
            "fun pairingCodeFromIdentity(",
            "fun pairingKey(",
            "fun deriveLocalSharedSecret(",
            "suspend fun agentCard(",
            "suspend fun createPeerInvite(",
            "suspend fun acceptPeerInvite(",
            "suspend fun listPeers(",
            "suspend fun deletePeer(",
            "suspend fun openPeerSession(",
            "suspend fun listPeerSessions(",
            "suspend fun createTaskMessage(",
            "suspend fun createTaskProgressMessage(",
            "suspend fun createTaskResultMessage(",
            "suspend fun recordPeerMessage(",
            "suspend fun recordDeliveryStatus(",
            "suspend fun listPeerMessages(",
            "suspend fun listDeliveryRecords(",
            "suspend fun localTransportStatus(",
            "suspend fun checkLocalTransportPermission(",
            "suspend fun requestLocalTransportPermission(",
            "suspend fun startLocalTransport(",
            "suspend fun stopLocalTransport(",
            "suspend fun discoverLocalPeers(",
            "suspend fun sendPeerMessage(",
            "suspend fun acceptDeepLink(",
            "suspend fun runTask(",
            "suspend fun listTasks(",
            "suspend fun getTask(",
            "suspend fun buildResultLink(",
            "suspend fun recordResultEnvelope(",
        )
        val requiredModelSnippets = listOf(
            "public class A2AAgentCard(rawJson: String = \"{}\")",
            "public class A2APeer(rawJson: String = \"{}\")",
            "public class A2ADeepLinkEnvelope(rawJson: String = \"{}\")",
            "public class A2ATaskRequest(rawJson: String = \"{}\")",
            "public class A2ATaskResult(rawJson: String = \"{}\")",
            "public class A2APeerSession(rawJson: String = \"{}\")",
            "public class A2APeerMessage(rawJson: String = \"{}\")",
            "public class A2ADeliveryRecord(rawJson: String = \"{}\")",
            "public class A2ALocalTransportStatus(rawJson: String = \"{}\")",
            "public class A2ALocalPeerAdvertisement(rawJson: String = \"{}\")",
            "public class A2ALocalTransportEvent(rawJson: String = \"{}\")",
        )
        val requiredEngineSnippets = listOf(
            "public val a2a: A2AApi = A2AApi(this)",
        )

        val missingApiSnippets = requiredApiSnippets.filterNot(androidApis::contains)
        val missingModelSnippets = requiredModelSnippets.filterNot(androidModels::contains)
        val missingEngineSnippets = requiredEngineSnippets.filterNot(engineSource::contains)

        assertTrue(
            "Android A2AApi is missing Flutter-style convenience methods: $missingApiSnippets",
            missingApiSnippets.isEmpty(),
        )
        assertTrue(
            "Android A2A models are missing Flutter-style JSON helpers: $missingModelSnippets",
            missingModelSnippets.isEmpty(),
        )
        assertTrue(
            "Android NapaxiEngine is missing Flutter-style A2A entrypoint: $missingEngineSnippets",
            missingEngineSnippets.isEmpty(),
        )
    }

    @Test
    fun flutterAndroidLocalA2ATransportRequiresNearbyWifiPermissionBeforeStartOrDiscover() {
        val root = repoRoot()
        val flutterManifest = readText(root.resolve("packages/flutter/android/AndroidManifest.xml"))
        val transportSource = readText(root.resolve("packages/flutter/android/src/main/kotlin/com/napaxi/flutter/A2ALocalTransport.kt"))
        val pluginSource = readText(root.resolve("packages/flutter/android/src/main/kotlin/com/napaxi/flutter/NapaxiFlutterPlugin.kt"))
        val startBody = classFunctionBody(transportSource, "start")
        val discoverBody = classFunctionBody(transportSource, "discover")
        val blockingPermissionBody = classFunctionBody(transportSource, "blockingPermissionReason")
        val requestPermissionBody = classFunctionBody(pluginSource, "requestA2ALocalPermission")

        val requiredManifestSnippets = listOf(
            "android.permission.CHANGE_WIFI_MULTICAST_STATE",
            "android.permission.NEARBY_WIFI_DEVICES",
            "android:usesPermissionFlags=\"neverForLocation\"",
        )
        val requiredTransportSnippets = listOf(
            "blockingPermissionReason()?.let { return permissionUnavailable(it) }",
            "blockingPermissionReason()?.let {",
            "\"started\" to false",
            "\"reason\" to it",
            "android_nearby_wifi_devices_permission_missing",
            "formatEndpointHost(host)",
            "clean.startsWith(\"[\")",
            "clean.lastIndexOf(':')",
        )
        val requiredPluginSnippets = listOf(
            "Manifest.permission.NEARBY_WIFI_DEVICES",
            "REQUEST_A2A_LOCAL_PERMISSION",
            "pendingA2ALocalPermissionResult = result",
        )

        assertTrue(
            "Flutter Android manifest is missing local A2A Wi-Fi/NSD permissions: ${requiredManifestSnippets.filterNot(flutterManifest::contains)}",
            requiredManifestSnippets.all(flutterManifest::contains),
        )
        assertTrue(
            "A2A start should fail clearly before NSD registration when runtime permission is missing.",
            startBody.contains("blockingPermissionReason()?.let { return permissionUnavailable(it) }"),
        )
        assertTrue(
            "A2A discover should return started=false with a reason when runtime permission is missing.",
            discoverBody.contains("blockingPermissionReason()?.let {") &&
                discoverBody.contains("\"started\" to false") &&
                discoverBody.contains("\"reason\" to it"),
        )
        assertTrue(
            "A2A transport is missing nearby Wi-Fi permission diagnostics: ${requiredTransportSnippets.filterNot(transportSource::contains)}",
            requiredTransportSnippets.all(transportSource::contains),
        )
        assertTrue(
            "A2A permission request bridge is missing nearby Wi-Fi permission flow: ${requiredPluginSnippets.filterNot(requestPermissionBody::contains)}",
            requiredPluginSnippets.all(requestPermissionBody::contains),
        )
        assertTrue(
            "A2A blocking permission gate should be Android 13+ specific.",
            blockingPermissionBody.contains("Build.VERSION.SDK_INT >= 33"),
        )
    }

    @Test
    fun flutterIosLocalA2ATransportExposesPermissionBridge() {
        val root = repoRoot()
        val pluginSource = readText(root.resolve("packages/flutter/ios/Classes/NapaxiFlutterPlugin.swift"))
        val transportSource = readText(root.resolve("packages/flutter/ios/Classes/A2ALocalTransport.swift"))
        val infoPlist = readText(root.resolve("examples/flutter/ios/Runner/Info.plist"))
        val requiredPluginSnippets = listOf(
            "\"checkA2ALocalPermission\"",
            "\"requestA2ALocalPermission\"",
            "hasRequiredLocalNetworkDeclarations()",
        )
        val requiredTransportSnippets = listOf(
            "func hasRequiredLocalNetworkDeclarations() -> Bool",
            "localNetworkWarnings().isEmpty",
            "formatEndpointHost(host)",
            "clean.hasPrefix(\"[\")",
            "clean.lastIndex(of: \":\")",
        )
        val requiredPlistSnippets = listOf(
            "NSLocalNetworkUsageDescription",
            "NSBonjourServices",
            "_napaxi-a2a._tcp",
        )

        assertTrue(
            "Flutter iOS plugin is missing local A2A permission method handlers: ${requiredPluginSnippets.filterNot(pluginSource::contains)}",
            requiredPluginSnippets.all(pluginSource::contains),
        )
        assertTrue(
            "Flutter iOS local A2A transport is missing local network declaration diagnostics: ${requiredTransportSnippets.filterNot(transportSource::contains)}",
            requiredTransportSnippets.all(transportSource::contains),
        )
        assertTrue(
            "Flutter demo iOS Info.plist is missing local A2A Bonjour/local network declarations: ${requiredPlistSnippets.filterNot(infoPlist::contains)}",
            requiredPlistSnippets.all(infoPlist::contains),
        )
    }

    @Test
    fun demoLocalA2ASlashFlowConnectsPairingCoreSessionAndTransportSend() {
        val root = repoRoot()
        val chatScreen = readText(root.resolve("examples/flutter/lib/screens/chat_screen.dart"))
        val mainSource = readText(root.resolve("examples/flutter/lib/main.dart"))
        val pairBody = dartFunctionBody(chatScreen, "_pairA2ASlashPeer")
        val sendBody = dartFunctionBody(chatScreen, "_sendA2ASlashTask")
        val pairRequestBody = dartSection(
            chatScreen,
            "Future<void> _sendA2APairingRequest",
            "Future<void> _sendA2ASlashTask",
        )
        val runBody = dartSection(
            chatScreen,
            "Future<void> _runA2ASlashTask",
            "Future<void> _answerA2ASlashTask",
        )
        val answerBody = dartSection(
            chatScreen,
            "Future<void> _answerA2ASlashTask",
            "Future<void> _fulfillA2ASlashTask",
        )
        val fulfillBody = dartSection(
            chatScreen,
            "Future<void> _fulfillA2ASlashTask",
            "Future<void> _replyA2ASlashTask",
        )
        val replyBody = dartSection(
            chatScreen,
            "Future<void> _replyA2ASlashTask",
            "Future<sdk.A2ALocalTransportStatus?> _ensureA2ALocalTransportStarted",
        )
        val doctorBody = dartSection(
            chatScreen,
            "Future<String> _slashA2ADoctorMessage",
            "String _slashA2APeerListMessage",
        )
        val e2eBody = dartSection(
            chatScreen,
            "Future<String> _slashA2AE2EGuideMessage",
            "Future<String> _slashA2APreflightMessage",
        )
        val preflightBody = dartSection(
            chatScreen,
            "Future<String> _slashA2APreflightMessage",
            "Future<String> _slashA2AInboxMessage",
        )
        val inboxBody = dartSection(
            chatScreen,
            "Future<String> _slashA2AInboxMessage",
            "Future<String> _slashA2ATasksMessage",
        )
        val peersBody = dartSection(
            chatScreen,
            "Future<String> _slashA2APeersMessage",
            "Future<List<sdk.A2ALocalPeerAdvertisement>> _discoverA2APeersForSlash",
        )
        val tasksBody = dartSection(
            chatScreen,
            "Future<String> _slashA2ATasksMessage",
            "Future<String> _slashA2AStatusMessage",
        )
        val traceBody = dartSection(
            chatScreen,
            "Future<String> _slashA2ATraceMessage",
            "_A2AInboundTask? _a2aInboundTaskFromRecord",
        )
        val inboundBody = dartFunctionBody(chatScreen, "_handleA2APageEvent")
        val receiptBody = dartFunctionBody(chatScreen, "_sendA2ATaskReceipt")
        val sendHelperBody = dartSection(
            chatScreen,
            "Future<_A2ASendEvidence> _sendA2AMessageToPeerOrThrow",
            "Future<sdk.A2ALocalTransportStatus?> _ensureA2ALocalTransportStarted",
        )
        val deliveryStatusBody = dartSection(
            chatScreen,
            "Future<String> _a2aDeliveryStatusForMessage",
            "Future<sdk.A2ALocalTransportStatus?> _ensureA2ALocalTransportStarted",
        )
        val pairedPeerBody = dartSection(
            chatScreen,
            "Future<sdk.A2ALocalPeerAdvertisement?> _resolveA2APairedPeer",
            "sdk.A2ALocalPeerAdvertisement? _a2aAdvertisementFromSavedPeer",
        )
        val completePairBody = dartSection(
            chatScreen,
            "Future<void> _completeA2ASlashPair",
            "Future<void> _sendA2APairingRequest",
        )
        val requiredPairSnippets = listOf(
            "_localA2AHelper.normalizePairingSecret",
            "_completeA2ASlashPair(",
            "successTarget: target",
        )
        val requiredCompletePairSnippets = listOf(
            "_confirmA2ASlashPair",
            "client.openLocalA2ASession",
            "_localA2AHelper.deriveLocalSharedSecret",
            "_a2aSaveRemotePairingSecret",
            "配对是双向的",
            "`/a2a pair-accept \${status.peerId} <你的配对密钥>`",
        )
        val requiredSendSnippets = listOf(
            "_resolveA2APairedPeer(target)",
            "_ensureA2ALocalTransportStarted(client)",
            "_a2aSharedSecretForPeer(peer, status: status)",
            "client.openLocalA2ASession",
            "sharedSecret: sharedSecret",
            "client.createLocalA2ATaskMessage",
            "_a2aTaskIdFromMessage(task)",
            "_sendA2AMessageToPeerOrThrow",
            "purpose: '发送任务'",
            "sessionId：`\${task.sessionId}`",
            "messageId：`\${evidence.messageId}`",
            "delivery：`\${evidence.deliveryStatus}`",
            "_a2aSendFailureMessage(",
            "`/a2a trace \$taskId`",
        )
        val requiredResendSnippets = listOf(
            "Future<void> _resendA2ASlashTask",
            "client.getLocalA2ATask(taskId)",
            "task.source != 'local_transport_outbound'",
            "_a2aOriginalTaskRequestMessage(client, task)",
            "client.listLocalA2APeerMessages",
            "message.kind != 'task_request'",
            "_a2aTaskIdFromMessage(message) == task.taskId",
            "_resolveA2APairedPeer(message.toPeerId)",
            "_ensureA2ALocalTransportStarted(client)",
            "_a2aSharedSecretForPeer(peer, status: status)",
            "_sendA2AMessageToPeerOrThrow",
            "purpose: '重发任务'",
            "messageId：`\${evidence.messageId}`",
            "delivery：`\${evidence.deliveryStatus}`",
            "_a2aSendFailureMessage(",
            "`/a2a trace \$taskId`",
        )
        val requiredPairRequestSnippets = listOf(
            "Future<void> _sendA2APairingRequest",
            "_resolveA2ASlashPeer(target) ?? await _resolveA2APairedPeer(target)",
            "_ensureA2ALocalTransportStarted(client)",
            "_createA2APairingRequestMessage(status, peer)",
            "kind: 'pairing_request'",
            "'endpoint': status.endpoint",
            "'transport': status.transport",
            "pairingCodeFromIdentity",
            "不包含配对密钥",
            "不会让对端自动信任本机",
            "purpose: '发送配对请求'",
            "messageId：`\${evidence.messageId}`",
            "delivery：`\${evidence.deliveryStatus}`",
        )
        val requiredPairAcceptSnippets = listOf(
            "Future<void> _acceptA2APairingRequest",
            "_resolveA2ASlashPeer(target)",
            "_completeA2ASlashPair(",
            "acceptedRequest: true",
            "`/a2a pair-accept <peerId> <对方配对密钥>`",
            "已配回",
        )
        val requiredInboundSnippets = listOf(
            "_resolveA2APairedPeer(message.fromPeerId)",
            "已拦截未配对 A2A 消息",
            "两台设备都需要互相配对",
            "message.kind == 'pairing_request'",
            "_a2aPeerFromPairingRequest(message)",
            "_a2aSlashPeers[requestPeer.peerId] = requestPeer",
            "_appendA2APairingRequestNotice(message)",
            "client.recordLocalA2AMessage(message)",
            "_a2aInboundTasks[taskId]",
            "delivery.status == 'delivered'",
            "_sendA2ATaskReceipt(client, peer, message.sessionId, taskId)",
        )
        val requiredReceiptSnippets = listOf(
            "client.createLocalA2AProgressMessage",
            "status: 'accepted'",
            "_sendA2AMessageToPeerOrThrow",
            "purpose: '回传任务接收回执'",
        )
        val requiredRunSnippets = listOf(
            "_resolveA2AInboundTask(taskId)",
            "client.runLocalA2ATask(taskId)",
            "record.status",
            "record.runId",
            "record.sessionKey",
            "record.summary",
            "`/a2a answer \$taskId`",
        )
        val requiredAnswerSnippets = listOf(
            "_resolveA2AInboundTask(taskId)",
            "_activeRun",
            "_latestA2AAgentAnswerForTask(taskId)",
            "_replyA2ASlashTask",
            "'result \$taskId \$answer'",
        )
        val requiredFulfillSnippets = listOf(
            "_resolveA2AInboundTask(taskId)",
            "_resolveA2APairedPeer(task.fromPeerId)",
            "_ensureA2ALocalTransportStarted(client)",
            "_a2aSharedSecretForPeer(peer, status: status)",
            "client.openLocalA2ASession(peer, sharedSecret: sharedSecret)",
            "client.createLocalA2AProgressMessage",
            "status: 'running'",
            "final progressEvidence = await _sendA2AMessageToPeerOrThrow",
            "client.runLocalA2ATask(taskId)",
            "_a2aResultTextForRecord(record)",
            "_a2aResultStatusForRecord(record)",
            "client.createLocalA2AResultMessage",
            "status: resultStatus",
            "final resultEvidence = await _sendA2AMessageToPeerOrThrow",
            "purpose: '回传任务结果'",
            "进度 messageId：`\${progressEvidence.messageId}`",
            "结果 messageId：`\${resultEvidence.messageId}`",
            "`/a2a trace \$taskId`",
            "status: 'failed'",
            "purpose: '回传任务失败结果'",
        )
        val requiredReplySnippets = listOf(
            "_resolveA2AInboundTask(taskId)",
            "_resolveA2APairedPeer(task.fromPeerId)",
            "_ensureA2ALocalTransportStarted(client)",
            "_a2aSharedSecretForPeer(peer, status: status)",
            "client.createLocalA2AResultMessage",
            "client.createLocalA2AProgressMessage",
            "client.openLocalA2ASession(peer, sharedSecret: sharedSecret)",
            "late final _A2ASendEvidence evidence",
            "evidence = await _sendA2AMessageToPeerOrThrow",
            "purpose: result ? '回传任务结果' : '回传任务进度'",
            "messageId：`\${evidence.messageId}`",
            "delivery：`\${evidence.deliveryStatus}`",
            "_a2aSendFailureMessage(",
            "`/a2a trace \$taskId`",
        )
        val requiredSendFailureSnippets = listOf(
            "String _a2aSendFailureMessage",
            "required Object error",
            "final resolvedTaskId = taskId ?? _a2aTaskIdFromMessage(message)",
            "sessionId：`\${message.sessionId}`",
            "messageId：`\${message.messageId}`",
            "Endpoint：\${peer.endpoint}",
            "`/a2a trace \$resolvedTaskId`",
            "`/a2a trace \${message.sessionId}`",
        )
        val requiredDoctorSnippets = listOf(
            "client.localA2AStatus()",
            "client.checkLocalA2APermission()",
            "_runA2ALoopbackCheck(client, status)",
            "client.createLocalA2ADiagnosticMessage",
            "client.sendLocalA2AMessage(",
            "endpoint: endpoint",
            "tcp://127.0.0.1:\${status.listenerPort}/a2a",
            "本机收发自检",
            "status.listenerPort",
            "status.endpoint",
            "status.discoveredPeerCount",
            "status.sentMessageCount",
            "status.receivedMessageCount",
            "`/a2a start`",
            "`/a2a scan`",
            "`/a2a pair <编号|peerId> <对方配对密钥>`",
        )
        val requiredE2ESnippets = listOf(
            "Future<String> _slashA2AE2EGuideMessage",
            "client.localA2AStatus()",
            "client.checkLocalA2APermission()",
            "client.listLocalA2APeers()",
            "client.listLocalA2ATasks()",
            "_ensureA2ALocalPairingSecret()",
            "_ensureA2ALocalPublicKey()",
            "本地 A2A 双机 E2E 清单",
            "`/a2a start`",
            "`/a2a preflight`",
            "`/a2a doctor`",
            "`/a2a scan`",
            "`/a2a pair <B编号|peerId> <B配对密钥>`",
            "`/a2a pair-request <B编号|peerId>`",
            "`/a2a pair-accept <A peerId> <A配对密钥>`",
            "`/a2a send ${'$'}pairedTarget <任务内容>`",
            "`/a2a inbox`",
            "`/a2a progress <taskId> <进度>`",
            "`/a2a fulfill <taskId>`",
            "`/a2a tasks`",
            "`/a2a trace <taskId|sessionId>`",
            "`/a2a resend <taskId>`",
            "`/a2a result <taskId> <结果>`",
        )
        val requiredPreflightSnippets = listOf(
            "client.localA2AStatus()",
            "client.checkLocalA2APermission()",
            "_runA2ALoopbackCheck(client, status)",
            "loopback.failed",
            "client.listLocalA2APeers()",
            "client.listLocalA2ATasks()",
            "pairedPeers",
            "pairedAdvertisements",
            "_a2aSlashPeers[peer.peerId] = peer",
            "pendingInbound",
            "activeOutbound",
            "本机收发自检",
            "任务账本",
            "可信设备",
            "本地 A2A 是双向信任",
            "B 还需要配回 A",
            "对端尚未配回本机",
            "`/a2a doctor`",
            "peerId：`\${entry.\$2.peerId}`",
            "endpoint：`\${entry.\$2.endpoint}`",
            "`/a2a start`",
            "`/a2a scan`",
            "`/a2a pair <编号|peerId> <对方配对密钥>`",
            "`/a2a fulfill ${'$'}{pendingInbound.first.taskId}`",
            "`/a2a tasks`",
            "`/a2a send ${'$'}{pairedAdvertisements.first.peerId} <任务>`",
            "`/a2a send <peerId> <任务>`",
        )
        val requiredPeersSnippets = listOf(
            "Future<String> _slashA2APeersMessage",
            "client.listLocalA2APeers()",
            "_a2aSlashPeers.values",
            "_a2aAdvertisementFromSavedPeer(peer)",
            "savedById[peer.peerId]",
            "trustLevel == 'user_confirmed'",
            "本地 A2A 设备",
            "peerId：`${'$'}{peer.peerId}`",
            "endpoint：`${'$'}{peer.endpoint}`",
            "transport：`${'$'}{peer.transport}`",
            "`/a2a send ${'$'}{peer.peerId} <任务>`",
            "`/a2a pair ${'$'}{entry.${'$'}1 + 1} <对方配对密钥>`",
            "trusted 只代表本机信任对端",
        )
        val requiredInboxSnippets = listOf(
            "client.listLocalA2ATasks()",
            "_a2aInboundTaskFromRecord(record)",
            "_a2aInboundTasks.isEmpty",
            "_a2aInboundTasks.values.toList()",
            "持久任务：\${durableTasks.length}",
            "taskId：`\${entry.\$2.taskId}`",
            "_compactMiddle(entry.\$2.fromPeerId)",
            "内容：\${entry.\$2.title}",
            "`/a2a fulfill <taskId>`",
            "`/a2a run <taskId>` 后 `/a2a answer <taskId>`",
        )
        val requiredTasksSnippets = listOf(
            "client.listLocalA2ATasks()",
            "client.localA2AStatus()).peerId",
            "_a2aTaskDirection(record, localPeerId)",
            "_a2aTaskStatusLine",
            "record.source == 'local_transport_outbound'",
            "record.sender.peerId == localPeerId",
            "状态：`\${record.status}`",
            "摘要：\${record.summary!.trim()}",
            "错误：\${record.error!.trim()}",
            "`/a2a fulfill <taskId>`",
        )
        val requiredTraceSnippets = listOf(
            "client.getLocalA2ATask(trimmed)",
            "client.listLocalA2APeerMessages",
            "client.listLocalA2ADeliveryRecords",
            "message.messageId",
            "delivery.status",
            "delivery.error",
            "deliveryError",
            "`/a2a fulfill \${task.taskId}`",
            "`/a2a tasks`",
            "Peer messages",
            "Delivery",
        )
        val requiredSendHelperSnippets = listOf(
            "final sent = await client.sendLocalA2AMessage",
            "endpoint: peer.endpoint",
            "if (!sent)",
            "throw StateError",
            "purpose",
            "_a2aDeliveryStatusForMessage(client, message)",
        )
        val requiredPairedPeerSnippets = listOf(
            "_resolveA2ASlashPeer(target)",
            "_isA2APeerPaired(scanned)",
            "client.listLocalA2APeers()",
            "_a2aAdvertisementFromSavedPeer(saved)",
            "_a2aSlashPeers[peer.peerId] = peer",
            "_isA2APeerPaired(peer)",
        )
        val requiredSharedSecretSnippets = listOf(
            "_a2aSavedSharedSecret(peer)",
            "_a2aRemotePairingSecret(peer)",
            "_localA2AHelper.deriveLocalSharedSecret",
            "saved.sharedSecret.trim()",
        )

        assertTrue(
            "Demo /a2a pair flow is missing pairing/core-session steps: ${requiredPairSnippets.filterNot(pairBody::contains)}",
            requiredPairSnippets.all(pairBody::contains),
        )
        assertTrue(
            "Demo A2A shared pairing completion must keep confirmation, secret derivation, core session write, and mutual-pair guidance: ${requiredCompletePairSnippets.filterNot(completePairBody::contains)}",
            requiredCompletePairSnippets.all(completePairBody::contains),
        )
        assertTrue(
            "Demo /a2a send flow is missing paired signed-session transport steps: ${requiredSendSnippets.filterNot(sendBody::contains)}",
            requiredSendSnippets.all(sendBody::contains),
        )
        assertTrue(
            "Demo /a2a resend should reuse the original outbound task_request message and record fresh delivery evidence: ${requiredResendSnippets.filterNot(chatScreen::contains)}",
            requiredResendSnippets.all(chatScreen::contains),
        )
        assertTrue(
            "Demo A2A send failures should include message/session/task evidence and a trace command: ${requiredSendFailureSnippets.filterNot(chatScreen::contains)}",
            requiredSendFailureSnippets.all(chatScreen::contains),
        )
        assertTrue(
            "Demo /a2a pair-request should send a safe local pairing prompt without auto-trusting the sender: ${requiredPairRequestSnippets.filterNot(pairRequestBody::contains)}",
            requiredPairRequestSnippets.all(pairRequestBody::contains),
        )
        assertTrue(
            "Demo /a2a pair-accept should reuse the existing pairing confirmation and trusted session path: ${requiredPairAcceptSnippets.filterNot(chatScreen::contains)}",
            requiredPairAcceptSnippets.all(chatScreen::contains),
        )
        assertTrue(
            "Demo inbound A2A flow must reject unpaired messages before recording them: ${requiredInboundSnippets.filterNot(inboundBody::contains)}",
            requiredInboundSnippets.all(inboundBody::contains),
        )
        assertTrue(
            "Demo inbound A2A pairing request notice must be explicit that it does not establish trust.",
            chatScreen.contains("不会自动建立信任") &&
                chatScreen.contains("不包含配对密钥") &&
                chatScreen.contains("`/a2a pair-accept \${message.fromPeerId} <对方配对密钥>`"),
        )
        assertTrue(
            "Demo inbound A2A flow should send a signed accepted receipt after the task is durably recorded: ${requiredReceiptSnippets.filterNot(receiptBody::contains)}",
            requiredReceiptSnippets.all(receiptBody::contains),
        )
        assertTrue(
            "Demo A2A local sends must treat transport false as failure instead of reporting success: ${requiredSendHelperSnippets.filterNot(sendHelperBody::contains)}",
            requiredSendHelperSnippets.all(sendHelperBody::contains),
        )
        assertTrue(
            "Demo A2A send evidence should read the core delivery ledger after local transport send.",
            chatScreen.contains("client.listLocalA2ADeliveryRecords") &&
                chatScreen.contains("delivery.messageId != message.messageId") &&
                chatScreen.contains("delivery.status"),
        )
        assertTrue(
            "Demo A2A send evidence should choose the strongest delivery status for a message instead of reporting stale created records.",
            deliveryStatusBody.contains("sdk.A2ADeliveryRecord? best") &&
                deliveryStatusBody.contains("_a2aDeliveryStatusRank(delivery.status)") &&
                deliveryStatusBody.contains("_a2aDeliveryStatusRank(best.status)") &&
                deliveryStatusBody.contains("if (best != null) return best.status") &&
                deliveryStatusBody.contains("int _a2aDeliveryStatusRank") &&
                deliveryStatusBody.contains("'failed' => 90") &&
                deliveryStatusBody.contains("'sent' => 40") &&
                deliveryStatusBody.contains("'created' => 10"),
        )
        assertTrue(
            "Demo inbound A2A notices should expose core delivery evidence for received task/progress/result messages.",
            chatScreen.contains("List<String> _a2aInboundDeliveryEvidenceLines") &&
                chatScreen.contains("messageId：`\${message.messageId}`") &&
                chatScreen.contains("delivery：`\${delivery.status}`") &&
                chatScreen.contains("deliveryError"),
        )
        assertTrue(
            "Demo /a2a run should execute through the core A2A task runtime and expose durable run evidence: ${requiredRunSnippets.filterNot(runBody::contains)}",
            requiredRunSnippets.all(runBody::contains),
        )
        assertTrue(
            "Demo /a2a answer flow must turn the latest Agent reply into a result response: ${requiredAnswerSnippets.filterNot(answerBody::contains)}",
            requiredAnswerSnippets.all(answerBody::contains),
        )
        assertTrue(
            "Demo /a2a fulfill should execute the task and return progress/result over trusted local transport: ${requiredFulfillSnippets.filterNot(fulfillBody::contains)}",
            requiredFulfillSnippets.all(fulfillBody::contains),
        )
        assertTrue(
            "Demo /a2a progress/result flow is missing paired transport response steps: ${requiredReplySnippets.filterNot(replyBody::contains)}",
            requiredReplySnippets.all(replyBody::contains),
        )
        assertTrue(
            "Demo /a2a should resolve trusted peers from durable core storage when the scan cache is empty: ${requiredPairedPeerSnippets.filterNot(pairedPeerBody::contains)}",
            requiredPairedPeerSnippets.all(pairedPeerBody::contains),
        )
        assertTrue(
            "Demo /a2a should prefer durable core shared secrets and only derive from pairing secrets as a fallback: ${requiredSharedSecretSnippets.filterNot(chatScreen::contains)}",
            requiredSharedSecretSnippets.all(chatScreen::contains),
        )
        assertTrue(
            "Demo /a2a doctor should expose a non-UI preflight for permissions, listener, discovery, and next steps: ${requiredDoctorSnippets.filterNot(doctorBody::contains)}",
            requiredDoctorSnippets.all(doctorBody::contains),
        )
        assertTrue(
            "Demo /a2a e2e should expose a slash-only two-device verification checklist covering discovery, pairing, task, progress, result, and recovery evidence: ${requiredE2ESnippets.filterNot(e2eBody::contains)}",
            requiredE2ESnippets.all(e2eBody::contains),
        )
        assertTrue(
            "Demo /a2a preflight should summarize local status, trusted peers, durable task ledger, and one next command: ${requiredPreflightSnippets.filterNot(preflightBody::contains)}",
            requiredPreflightSnippets.all(preflightBody::contains),
        )
        assertTrue(
            "Demo /a2a inbox should expose received task ids and next-step commands: ${requiredInboxSnippets.filterNot(inboxBody::contains)}",
            requiredInboxSnippets.all(inboxBody::contains),
        )
        assertTrue(
            "Demo /a2a peers should expose discovered and durable trusted peers with trust, endpoint, and next commands: ${requiredPeersSnippets.filterNot(peersBody::contains)}",
            requiredPeersSnippets.all(peersBody::contains),
        )
        assertTrue(
            "Demo /a2a tasks should expose durable inbound/outbound task state and recovery hints: ${requiredTasksSnippets.filterNot(tasksBody::contains)}",
            requiredTasksSnippets.all(tasksBody::contains),
        )
        assertTrue(
            "Demo /a2a trace should expose task, peer message, and delivery evidence without opening a UI panel: ${requiredTraceSnippets.filterNot(traceBody::contains)}",
            requiredTraceSnippets.all(traceBody::contains),
        )
        assertTrue(
            "Demo /a2a task lookup should recover received tasks from the core durable ledger after app restart.",
            chatScreen.contains("client.listLocalA2ATasks()") &&
                chatScreen.contains("_a2aInboundTaskFromRecord(record)") &&
                chatScreen.contains("_a2aInboundTasks[task.taskId] = task"),
        )
        assertTrue(
            "Inbound A2A flow should check pairing before recording local peer messages.",
            inboundBody.indexOf("_resolveA2APairedPeer(message.fromPeerId)") < inboundBody.indexOf("client.recordLocalA2AMessage(message)"),
        )
        assertTrue(
            "A2A diagnostic loopback messages should not enter the normal inbound task flow.",
            inboundBody.contains("message.kind.startsWith('diagnostic_')"),
        )
        assertTrue(
            "A2A pairing requests should show a safe pairing prompt before the trusted-message recording gate.",
            inboundBody.indexOf("message.kind == 'pairing_request'") < inboundBody.indexOf("_resolveA2APairedPeer(message.fromPeerId)") &&
                inboundBody.indexOf("_appendA2APairingRequestNotice(message)") < inboundBody.indexOf("client.recordLocalA2AMessage(message)"),
        )
        assertTrue(
            "Inbound A2A flow should only send receipts after core recording succeeds.",
            inboundBody.indexOf("client.recordLocalA2AMessage(message)") < inboundBody.indexOf("_sendA2ATaskReceipt"),
        )
        assertTrue(
            "A2A responses should verify pairing before creating progress/result messages.",
            replyBody.indexOf("_resolveA2APairedPeer(task.fromPeerId)") < replyBody.indexOf("client.createLocalA2AResultMessage"),
        )
        assertFalse(
            "A2A doctor must stay slash-first and avoid opening the debug panel.",
            doctorBody.contains("_openA2ALocalPanel"),
        )
        assertFalse(
            "A2A inbox must stay slash-first and avoid opening the debug panel.",
            inboxBody.contains("_openA2ALocalPanel"),
        )
        assertFalse(
            "Demo local A2A should stay slash-only and not expose the removed debug panel.",
            chatScreen.contains("_openA2ALocalPanel") ||
                chatScreen.contains("正在打开本地 A2A 调试面板") ||
                mainSource.contains("chat_a2a_widgets.dart"),
        )
    }

    @Test
    fun androidEngineExposesFlutterStyleSessionAndEvolutionConvenienceSurface() {
        val root = repoRoot()
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))

        val requiredSessionSnippets = listOf(
            "suspend fun deleteSession(",
            "suspend fun clearSession(",
            "suspend fun answerHumanRequest(",
            "suspend fun injectMessage(",
            "suspend fun retractInjectedMessage(",
            "fun saveAttachmentMetadata(",
            "fun getHistoryJson(",
            "suspend fun getHistory(",
            "suspend fun getHistoryPage(",
            "suspend fun compactContext(",
            "suspend fun contextStatus(",
        )
        val requiredEvolutionSnippets = listOf(
            "suspend fun listPendingEvolution(",
            "suspend fun applyPendingEvolution(",
            "suspend fun rejectPendingEvolution(",
            "suspend fun listEvolutionRuns(",
            "suspend fun listEvolutionDiagnostics(",
        )
        val requiredSessionApiSnippets = listOf(
            "engine.deleteSession(sessionKey, agentId)",
            "engine.clearSession(sessionKey, agentId)",
            "engine.answerHumanRequest(requestId, response)",
            "engine.getHistoryJson(threadId, agentId)",
            "engine.injectMessage(sessionKey, message, attachments, agentId)",
            "engine.retractInjectedMessage(sessionKey, message)",
        )
        val requiredEvolutionModelSnippets = listOf(
            "public class EvolutionRun(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): EvolutionRun",
            "public class EvolutionDiagnostic(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): EvolutionDiagnostic",
            "public class SkillConsolidationReviewResult(rawJson: String)",
            "public fun fromMap(map: Map<String, *>): SkillConsolidationReviewResult",
        )

        val missingSessionSnippets = requiredSessionSnippets.filterNot(engineSource::contains)
        val missingEvolutionSnippets = requiredEvolutionSnippets.filterNot(engineSource::contains)
        val missingSessionApiSnippets = requiredSessionApiSnippets.filterNot(androidApis::contains)
        val missingEvolutionModelSnippets = requiredEvolutionModelSnippets.filterNot(androidModels::contains)

        assertTrue(
            "Android NapaxiEngine is missing Flutter-style session convenience methods: $missingSessionSnippets",
            missingSessionSnippets.isEmpty(),
        )
        assertTrue(
            "Android NapaxiEngine is missing Flutter-style evolution convenience methods: $missingEvolutionSnippets",
            missingEvolutionSnippets.isEmpty(),
        )
        assertTrue(
            "Android evolution models are missing Flutter-style JSON helpers: $missingEvolutionModelSnippets",
            missingEvolutionModelSnippets.isEmpty(),
        )
        assertTrue(
            "Android SessionApi should route through top-level NapaxiEngine session methods: $missingSessionApiSnippets",
            missingSessionApiSnippets.isEmpty(),
        )
    }

    @Test
    fun androidEngineExposesFlutterStyleSkillConvenienceSurface() {
        val root = repoRoot()
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))

        val requiredEngineSnippets = listOf(
            "suspend fun listSkills(",
            "suspend fun getSkill(",
            "suspend fun listSkillStatus(",
            "suspend fun listSkillSources(",
            "suspend fun recordSkillSourceChanged(",
            "suspend fun getSkillStatus(",
            "suspend fun checkSkills(",
            "suspend fun listSkillCommands(",
            "suspend fun resolveSkillCommand(",
            "suspend fun runSkillCommand(",
            "suspend fun setSkillEnabled(",
            "suspend fun updateSkillConfig(",
            "suspend fun listSkillRemediationActions(",
            "suspend fun listSkillSnapshots(",
            "suspend fun getSkillSnapshot(",
            "suspend fun listSkillSecretRequirements(",
            "suspend fun recordSkillSecretAvailability(",
            "suspend fun requestSkillRemediation(",
            "suspend fun updateSkillRemediationRun(",
            "suspend fun listSkillRemediationRuns(",
            "suspend fun recordSkillRequirementResolution(",
            "suspend fun installSkill(",
            "suspend fun removeSkill(",
            "suspend fun reloadSkills(",
            "suspend fun listSkillUsage(",
            "suspend fun pinSkill(",
            "suspend fun archiveSkill(",
            "suspend fun restoreSkill(",
            "suspend fun runSkillCurator(",
            "suspend fun runSkillConsolidationReview(",
            "suspend fun readSkillSupportFile(",
            "suspend fun searchCatalog(",
            "suspend fun listCatalogPackages(",
            "suspend fun getCatalogSkill(",
            "suspend fun installFromCatalog(",
        )
        val requiredModelSnippets = listOf(
            "public class SkillLifecycleSummary(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillLifecycleSummary",
            "public class SkillInfo(rawJson: String)",
            "fun fromMap(map: Map<String, *>): SkillInfo",
            "public class SkillStatusReport(rawJson: String)",
            "fun fromMap(map: Map<String, *>): SkillStatusReport",
            "public class SkillStatusEntry(rawJson: String)",
            "fun fromMap(map: Map<String, *>): SkillStatusEntry",
            "public class SkillProvenance(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillProvenance",
            "public class SkillRequirementSummary(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillRequirementSummary",
            "public class SkillOpenClawMetadata(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillOpenClawMetadata",
            "public class SkillSourceReport(rawJson: String)",
            "fun fromMap(map: Map<String, *>): SkillSourceReport",
            "public class SkillSourceEntry(rawJson: String)",
            "fun fromMap(map: Map<String, *>): SkillSourceEntry",
            "public class SkillRefreshResult(rawJson: String)",
            "fun fromMap(map: Map<String, *>): SkillRefreshResult",
            "public data class SkillRemediationAction(",
            "fun fromMap(map: Map<String, *>): SkillRemediationAction",
            "public class SkillCommandReport(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillCommandReport",
            "public class SkillCommand(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillCommand",
            "public class SkillCommandDispatch(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillCommandDispatch",
            "fun fromMapOrNull(map: Map<String, *>?): SkillCommandDispatch?",
            "public class SkillCommandResolution(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillCommandResolution",
            "public class SkillCommandRun(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillCommandRun",
            "public class SkillSnapshotList(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillSnapshotList",
            "public open class SkillSnapshotIndexEntry(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillSnapshotIndexEntry",
            "public class SkillSnapshot(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillSnapshot",
            "public class SkillSnapshotCatalogEntry(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillSnapshotCatalogEntry",
            "public class SkillSecretRequirementReport(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillSecretRequirementReport",
            "public class SkillSecretRequirement(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillSecretRequirement",
            "public class SkillRemediationRun(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillRemediationRun",
            "public class SkillRemediationRunList(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillRemediationRunList",
            "public class SkillUsageRecord(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillUsageRecord",
            "public class CuratorRunSummary(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): CuratorRunSummary",
            "public class SkillSupportFileReadResult(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillSupportFileReadResult",
            "public class CatalogSearchResult(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): CatalogSearchResult",
            "public class CatalogPackagePage(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): CatalogPackagePage",
            "public class CatalogSkillInfo(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): CatalogSkillInfo",
            "public class SkillInstallResult(rawJson: String = \"{}\")",
            "fun fromMap(map: Map<String, *>): SkillInstallResult",
            "fun toJsonString(): String = toJson()",
        )
        val missingEngineSnippets = requiredEngineSnippets.filterNot(engineSource::contains)
        val missingModelSnippets = requiredModelSnippets.filterNot(androidModels::contains)

        assertTrue(
            "Android NapaxiEngine is missing Flutter-style skill convenience methods: $missingEngineSnippets",
            missingEngineSnippets.isEmpty(),
        )
        assertTrue(
            "Android skill command models are missing Flutter-style JSON helpers: $missingModelSnippets",
            missingModelSnippets.isEmpty(),
        )
    }

    @Test
    fun androidEngineExposesFlutterStyleAutomationFileBridgeAndApkConvenienceSurface() {
        val root = repoRoot()
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))
        val androidModels = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Models.kt"))
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))

        val requiredAutomationSnippets = listOf(
            "suspend fun createAutomationJob(",
            "suspend fun updateAutomationJob(",
            "suspend fun deleteAutomationJob(",
            "suspend fun listAutomationJobs(",
            "suspend fun getAutomationJob(",
            "suspend fun runAutomationJob(",
            "suspend fun listAutomationRuns(",
            "suspend fun getNextAutomationWake(",
            "suspend fun recordAutomationWake(",
        )
        val requiredFileBridgeSnippets = listOf(
            "suspend fun initFileBridge(",
            "suspend fun saveMessageAttachments(",
            "suspend fun loadThreadAttachments(",
            "suspend fun deleteThreadAttachments(",
            "suspend fun sandboxToReal(",
            "suspend fun sandboxToRealScoped(",
            "suspend fun realToSandbox(",
            "suspend fun realToSandboxScoped(",
            "suspend fun resolveFile(",
            "suspend fun resolveFileScoped(",
            "suspend fun deleteFile(",
            "suspend fun deleteFileScoped(",
            "suspend fun detectFileReferences(",
            "suspend fun detectFileReferencesScoped(",
            "suspend fun listFiles(",
            "suspend fun listFilesScoped(",
            "suspend fun listWorkspaceFilesystem(",
            "suspend fun workspaceSize(",
            "suspend fun workspaceSizeScoped(",
            "suspend fun workspaceDir(",
            "suspend fun workspaceDirScoped(",
            "suspend fun rootfsDir(",
            "suspend fun skillsDir(",
            "suspend fun openLocalFile(",
            "suspend fun openLocalFileResult(",
        )
        val requiredEngineApkSnippets = listOf(
            "suspend fun installApk(",
            "suspend fun installApkResult(",
        )
        val requiredStandaloneApkSnippets = listOf(
            "object NapaxiApkInstaller",
            "fun installApk(context: Context, apkPath: String): NapaxiApkInstallResult",
            "fun installApkJson(context: Context, apkPath: String): String",
        )
        val requiredApkModelSnippets = listOf(
            "data class NapaxiApkInstallResult",
            "fun fromJsonObject(obj: JSONObject, rawJson: String = obj.toString()): NapaxiApkInstallResult",
            "fun fromMap(map: Map<String, *>): NapaxiApkInstallResult",
            "fun toJsonString(): String = toJson()",
        )
        val requiredStandaloneFileBridgeSnippets = listOf(
            "object NapaxiFileBridge",
            "fun instance(engine: NapaxiEngine): FileBridgeApi",
            "suspend fun init(",
            "fun openLocalFileJson(",
            "fun openLocalFileResult(",
        )

        val missingAutomationSnippets = requiredAutomationSnippets.filterNot(engineSource::contains)
        val missingFileBridgeSnippets = requiredFileBridgeSnippets.filterNot(engineSource::contains)
        val missingEngineApkSnippets = requiredEngineApkSnippets.filterNot(engineSource::contains)
        val missingStandaloneApkSnippets = requiredStandaloneApkSnippets.filterNot(androidApis::contains)
        val missingApkModelSnippets = requiredApkModelSnippets.filterNot(androidModels::contains)
        val missingStandaloneFileBridgeSnippets = requiredStandaloneFileBridgeSnippets.filterNot(androidApis::contains)

        assertTrue(
            "Android NapaxiEngine is missing Flutter-style automation convenience methods: $missingAutomationSnippets",
            missingAutomationSnippets.isEmpty(),
        )
        assertTrue(
            "Android NapaxiEngine is missing Flutter-style file bridge convenience methods: $missingFileBridgeSnippets",
            missingFileBridgeSnippets.isEmpty(),
        )
        assertTrue(
            "Android NapaxiEngine is missing Flutter-style APK installer convenience methods: $missingEngineApkSnippets",
            missingEngineApkSnippets.isEmpty(),
        )
        assertTrue(
            "Android SDK is missing Flutter-style standalone NapaxiApkInstaller helpers: $missingStandaloneApkSnippets",
            missingStandaloneApkSnippets.isEmpty(),
        )
        assertTrue(
            "Android APK install result model is missing Flutter-style JSON helpers: $missingApkModelSnippets",
            missingApkModelSnippets.isEmpty(),
        )
        assertTrue(
            "Android SDK is missing Flutter-style standalone NapaxiFileBridge helpers: $missingStandaloneFileBridgeSnippets",
            missingStandaloneFileBridgeSnippets.isEmpty(),
        )
    }

    @Test
    fun androidFacadesCoverFlutterStablePublicMethods() {
        val root = repoRoot()
        val pairs = listOf(
            FacadePair("NapaxiEngine", "packages/flutter/lib/engine.dart", "packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"),
            FacadePair("AgentApi", "packages/flutter/lib/api/agent_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("SessionApi", "packages/flutter/lib/api/session_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("ChatApi", "packages/flutter/lib/api/chat_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("GroupApi", "packages/flutter/lib/api/group_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("SkillApi", "packages/flutter/lib/api/skill_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("AutomationApi", "packages/flutter/lib/api/automation_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("CapabilityApi", "packages/flutter/lib/api/capability_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("AgentAppApi", "packages/flutter/lib/api/agent_app_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("ToolApi", "packages/flutter/lib/api/tool_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("WorkspaceApi", "packages/flutter/lib/api/workspace_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("BackgroundApi", "packages/flutter/lib/api/background_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Background.kt"),
            FacadePair("SessionRunApi", "packages/flutter/lib/api/session_run_api.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
            FacadePair("McpApi", "packages/flutter/lib/mcp.dart", "packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"),
        )

        val missing = pairs.flatMap { pair ->
            val flutterSource = readText(root.resolve(pair.flutterPath))
            val androidSource = readText(root.resolve(pair.androidPath))
            val flutterMethods = dartPublicMethods(classBody(flutterSource, pair.className))
            val androidMethods = kotlinPublicMethods(classBody(androidSource, pair.className))

            flutterMethods
                .filterNot(androidMethods::contains)
                .map { "${pair.className}.$it" }
        }

        assertTrue(
            "Android stable facades are missing Flutter public methods: $missing",
            missing.isEmpty(),
        )
    }

    @Test
    fun androidChatTurnSemanticsMatchFlutterDefaultsAndAgentConfig() {
        val root = repoRoot()
        val androidEngine = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))
        val androidApis = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Apis.kt"))

        val requiredEngineSnippets = listOf(
            "requestConfig: LlmConfig = config",
            "val configJson = requestConfig.toJson()",
            "check(!hasActiveSessionRun(session, agentId)) { \"Session is already running: ${'$'}{session.threadId}\" }",
            "\"agent.send\"",
            ".put(\"config_json\", (config ?: this@NapaxiEngine.config).toJson())",
            "sandboxPaths: List<String>? = null",
            "attachments.toJsonArrayString(sandboxPaths)",
        )
        val missingEngineSnippets = requiredEngineSnippets.filterNot(androidEngine::contains)
        val androidDefaultMaxIterations = Regex("""maxIterations: Int = 0""")
            .findAll(androidEngine + androidApis)
            .count()

        assertTrue(
            "Android chat/agent send path must pass per-call agent config, reject duplicate active session turns, and preserve Flutter-style maxIterations=0 defaults. Missing snippets: $missingEngineSnippets",
            missingEngineSnippets.isEmpty() && androidDefaultMaxIterations >= 9,
        )
    }

    @Test
    fun androidPublicTypesCoverFlutterStableExportsExceptPlatformSpecificUi() {
        val root = repoRoot()
        val flutterTypes = flutterStableExportedFiles(root)
            .flatMap { dartPublicTypes(readText(it)) }
            .toSet()
        val androidTypes = androidPublicTypes(root)
        val flutterOnlyUiTypes = setOf(
            "BrowserBackendCapabilities",
            "BrowserScreenshotMode",
            "BrowserViewportMode",
            "NapaxiBrowserBackend",
            "NapaxiBrowserScreenshot",
            "NapaxiBrowserSnapshot",
            "NapaxiBrowserSurface",
            "IosAgentProviderActionExecutor",
        )
        val missing = flutterTypes
            .filterNot(androidTypes::contains)
            .filterNot(flutterOnlyUiTypes::contains)
            .sorted()

        assertTrue(
            "Android public SDK types are missing Flutter stable exported types: $missing",
            missing.isEmpty(),
        )
        assertTrue(
            "Flutter-only browser UI types must map to Android-native browser host abstractions",
            androidTypes.containsAll(
                setOf(
                    "NapaxiBrowserController",
                    "AndroidBrowserToolHost",
                    "BrowserMutationPolicy",
                    "BrowserToolProvider",
                ),
            ),
        )
        assertTrue(
            "Flutter-only iOS provider executor must map to Android provider action executor",
            androidTypes.contains("AndroidAgentProviderActionExecutor") &&
                androidTypes.contains("AgentAppActionExecutor"),
        )
    }

    @Test
    fun androidPublicTypesCoverFlutterAdvancedAndConvenienceExports() {
        val root = repoRoot()
        val flutterTypes = listOf(
            "packages/flutter/lib/advanced.dart",
            "packages/flutter/lib/convenience.dart",
        )
            .flatMap { entry -> flutterExportedFiles(root, entry) }
            .flatMap { dartPublicTypes(readText(it)) }
            .toSet()
        val androidTypes = androidPublicTypes(root)
        val missing = flutterTypes
            .filterNot(androidTypes::contains)
            .sorted()

        assertTrue(
            "Android public SDK types are missing Flutter advanced/convenience exported types: $missing",
            missing.isEmpty(),
        )
    }

    @Test
    fun engineDefaultDispatcherLifecycleTracksBuiltInExecutors() {
        val root = repoRoot()
        val engineSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/NapaxiEngine.kt"))
        val backgroundSource = readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Background.kt"))

        assertTrue(
            "NapaxiEngine should expose Flutter-style background service convenience methods",
            engineSource.contains("fun startBackgroundService()") &&
                engineSource.contains("fun stopBackgroundService()") &&
                backgroundSource.contains("engine.startBackgroundService()") &&
                backgroundSource.contains("engine.stopBackgroundService()"),
        )
        assertTrue(
            "NapaxiEngine.create must include default Android provider action executor in dispatcher registration",
            engineSource.contains("effectiveAgentAppActionExecutor") &&
                engineSource.contains("context as? Activity") &&
                engineSource.contains("let(::AndroidAgentProviderActionExecutor)"),
        )
        assertTrue(
            "Agent App action dispatcher fallback should return a complete AgentAppActionResult-shaped failure",
            engineSource.contains("AndroidAgentProviderActionExecutor.failedActionResult") &&
                engineSource.contains("No agent app action executor registered") &&
                !engineSource.contains("""JSONObject().put("status", "failed").put("error", "No agent app action executor registered")"""),
        )
        assertTrue(
            "Android provider action executor should not swallow Activity results when no action callback is pending",
            readText(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/AgentProviders.kt"))
                .contains("val callback = pendingCallback ?: return false"),
        )
        assertTrue(
            "NapaxiEngine.dispose must clear the global tool callback whenever any dispatcher was registered",
            Regex("""if\s*\(\s*toolDispatcherRegistered\s*\)\s*\{\s*NapaxiNative\.registerToolRequestCallback\(null\)""")
                .containsMatchIn(engineSource),
        )
        assertTrue(
            "Runtime default capability status must preserve whether a platform media handler was provided at create time",
            Regex("""private val hasPlatformMediaToolHandler: Boolean""").containsMatchIn(engineSource) &&
                Regex("""hasPlatformMediaToolHandler = hasPlatformMediaToolHandler""").findAll(engineSource).count() >= 2,
        )
    }

    private fun readText(path: Path): String = String(Files.readAllBytes(path), Charsets.UTF_8)

    private fun repoRoot(): Path {
        val cwd = Paths.get("").toAbsolutePath()
        return generateSequence(cwd) { it.parent }
            .firstOrNull { Files.exists(it.resolve("packages/api_bridge/android_jni.rs")) }
            ?: error("Could not locate Napaxi repository root from $cwd")
    }

    private data class FacadePair(
        val className: String,
        val flutterPath: String,
        val androidPath: String,
    )

    private companion object {
        private val bridgeMethodRegex = Regex("""\bbridge(?:Bool|Long)?\(\s*"([^"]+)"""")
        private val directCallBridgeMethodRegex = Regex("""\bNapaxiNative\.callBridge\(\s*"([^"]+)"""")
        private val flutterEventTypeRegex = Regex("""'([^']+)'\s*=>""")
        private val dartPublicMethodRegex = Regex(
            """(?m)^\s*(?!factory\b)(?!const\b)(?!static\b)(?!final\b)(?!return\b)(?!throw\b)(?!switch\b)(?!yield\b)(?!case\b)(?:[A-Za-z_][\w<>,?]*\s+)+([A-Za-z_]\w*)\s*\(""",
        )
        private val kotlinPublicMethodRegex = Regex("""\b(?:public\s+)?(?:suspend\s+)?fun\s+([A-Za-z_]\w*)\s*\(""")
        private val dartExportRegex = Regex("""(?m)^export\s+['"]([^'"]+)['"]""")
        private val dartPublicTypeRegex = Regex("""(?m)^\s*(?:abstract\s+)?class\s+([A-Za-z_]\w*)|^\s*enum\s+([A-Za-z_]\w*)|^\s*typedef\s+([A-Za-z_]\w*)""")
        private val kotlinPublicTypeRegex = Regex("""\b(?:public\s+)?(?:(?:data|sealed|open)\s+)*(?:class|interface|object)\s+([A-Za-z_]\w*)|\b(?:public\s+)?enum\s+class\s+([A-Za-z_]\w*)|\b(?:public\s+)?typealias\s+([A-Za-z_]\w*)""")
        private val manifestPermissionRegex = Regex("<uses-permission\\s+android:name=\"([^\"]+)\"")

        private fun manifestPermissions(source: String): Set<String> =
            manifestPermissionRegex.findAll(source)
                .map { it.groupValues[1] }
                .toSet()

        private fun enumWireNames(source: String, enumName: String): Set<String> {
            val body = Regex("""enum\s+$enumName\s*\{([\s\S]*?)\n\}""")
                .find(source)
                ?.groupValues
                ?.get(1)
                ?: return emptySet()
            return Regex("""\('([^']+)'\)""")
                .findAll(body)
                .map { it.groupValues[1] }
                .toSet()
        }

        private fun classBody(source: String, className: String): String {
            val match = Regex("""(?:abstract\s+)?class\s+$className\b""").find(source) ?: return ""
            val start = source.indexOf('{', match.range.last)
            if (start < 0) return ""
            var depth = 0
            for (index in start until source.length) {
                when (source[index]) {
                    '{' -> depth += 1
                    '}' -> {
                        depth -= 1
                        if (depth == 0) return source.substring(start + 1, index)
                    }
                }
            }
            return ""
        }

        private fun classFunctionBody(source: String, functionName: String): String {
            val match = Regex("""\bfun\s+$functionName\b""").find(source) ?: return ""
            val start = source.indexOf('(', match.range.last)
            if (start < 0) return ""
            val nextFunction = Regex("""\n\s*(?:private\s+)?fun\s+\w+""")
                .find(source, start + 1)
                ?.range
                ?.first
                ?: source.length
            return source.substring(start, nextFunction)
        }

        private fun dartFunctionBody(source: String, functionName: String): String {
            val match = Regex("""Future<void>\s+$functionName\b""").find(source) ?: return ""
            val nameStart = match.range.first
            val argumentStart = source.indexOf('(', nameStart)
            if (argumentStart < 0) return ""
            val start = source.indexOf('{', argumentStart)
            if (start < 0) return ""
            var depth = 0
            for (index in start until source.length) {
                when (source[index]) {
                    '{' -> depth += 1
                    '}' -> {
                        depth -= 1
                        if (depth == 0) return source.substring(start + 1, index)
                    }
                }
            }
            return ""
        }

        private fun dartSection(source: String, startMarker: String, endMarker: String): String {
            val start = source.indexOf(startMarker)
            if (start < 0) return ""
            val end = source.indexOf(endMarker, start + startMarker.length)
            if (end < 0) return source.substring(start)
            return source.substring(start, end)
        }

        private fun dartPublicMethods(body: String): Set<String> =
            dartPublicMethodRegex.findAll(body)
                .map { it.groupValues[1] }
                .filterNot { it.startsWith("_") }
                .toSet()

        private fun kotlinPublicMethods(body: String): Set<String> =
            kotlinPublicMethodRegex.findAll(body)
                .map { it.groupValues[1] }
                .toSet()

        private fun dartPublicTypes(source: String): Set<String> =
            dartPublicTypeRegex.findAll(source)
                .map { match ->
                    match.groupValues
                        .drop(1)
                        .first(String::isNotEmpty)
                }
                .filterNot { it.startsWith("_") }
                .toSet()

        private fun androidPublicTypes(root: Path): Set<String> {
            val androidSourceDir = root.resolve("packages/android/src/main/kotlin/com/napaxi/android")
            val names = mutableSetOf<String>()
            Files.walk(androidSourceDir).use { paths ->
                paths
                    .filter { it.toString().endsWith(".kt") }
                    .forEach { path ->
                        val source = String(Files.readAllBytes(path), Charsets.UTF_8)
                        kotlinPublicTypeRegex.findAll(source).forEach { match ->
                            names += match.groupValues
                                .drop(1)
                                .first(String::isNotEmpty)
                        }
                    }
            }
            return names
        }

        private fun flutterStableExportedFiles(root: Path): Set<Path> =
            flutterExportedFiles(root, "packages/flutter/lib/napaxi_flutter.dart")

        private fun flutterExportedFiles(root: Path, entryPath: String): Set<Path> {
            val entry = root.resolve(entryPath)
            val seen = linkedSetOf<Path>()

            fun visit(file: Path) {
                val normalized = file.normalize()
                if (!seen.add(normalized)) return
                val source = String(Files.readAllBytes(normalized), Charsets.UTF_8)
                dartExportRegex.findAll(source).forEach { match ->
                    val target = normalized.parent.resolve(match.groupValues[1])
                    if (!target.normalize().toString().contains("/generated/")) {
                        visit(target)
                    }
                }
            }

            visit(entry)
            return seen
        }
    }
}
