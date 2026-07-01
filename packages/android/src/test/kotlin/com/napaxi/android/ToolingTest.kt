package com.napaxi.android

import android.content.ContextWrapper
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class ToolingTest {
    @Test
    fun bridgeResultUnwrapsCApiEnvelopeToFlutterStyleRawValues() {
        assertEquals(
            """[{"id":"napaxi.tool.browser"}]""",
            unwrapBridgeResult("""{"ok":true,"value":[{"id":"napaxi.tool.browser"}]}"""),
        )
        assertEquals(
            "napaxi.llm.openai",
            unwrapBridgeResult("""{"ok":true,"value":"napaxi.llm.openai"}"""),
        )
        assertEquals("true", unwrapBridgeResult("""{"ok":true,"value":true}"""))
        assertEquals("null", unwrapBridgeResult("""{"ok":true,"value":null}"""))
        assertEquals(
            """{"ok":false,"error":{"message":"bad"}}""",
            unwrapBridgeResult("""{"ok":false,"error":{"message":"bad"}}"""),
        )
    }

    @Test
    fun browserToolHostBlocksRiskyClickWhenApprovalIsDenied() {
        var controllerCalled = false
        val controller = NapaxiBrowserController { _, _, callback ->
            controllerCalled = true
            callback.success("""{"success":true}""")
        }
        val host = AndroidBrowserToolHost(
            controller = controller,
            approvalHandler = McToolApprovalHandler { request, callback ->
                assertEquals("browser_click", request.toolName)
                assertTrue(request.description.contains("high-risk"))
                callback.success(McToolApprovalResponse(approved = false).toJson())
            },
        )

        var result = JSONObject()
        host.execute(
            "browser_click",
            """{"text":"Confirm purchase"}""",
            object : McToolCallback {
                override fun success(resultJson: String) {
                    result = JSONObject(resultJson)
                }

                override fun error(message: String) {
                    error(message)
                }
            },
        )

        assertEquals(false, controllerCalled)
        assertEquals(false, result.getBoolean("success"))
        assertEquals("browser_click", result.getString("action"))
        assertEquals("Browser action requires user approval", result.getString("blocked_or_approval_reason"))
    }

    @Test
    fun browserToolHostDelegatesRiskyClickAfterApproval() {
        var delegatedToolName = ""
        var delegatedParams = ""
        val controller = NapaxiBrowserController { toolName, paramsJson, callback ->
            delegatedToolName = toolName
            delegatedParams = paramsJson
            callback.success(
                JSONObject()
                    .put("success", true)
                    .put("action", toolName)
                    .put("clicked", true)
                    .toString(),
            )
        }
        val host = AndroidBrowserToolHost(
            controller = controller,
            approvalHandler = McToolApprovalHandler { request, callback ->
                assertEquals("browser_click", request.toolName)
                assertEquals("""{"text":"Confirm purchase"}""", request.parametersJson)
                assertEquals(false, request.allowAlways)
                assertTrue(request.description.contains("high-risk"))
                callback.success(McToolApprovalResponse(approved = true).toJson())
            },
        )

        var result = JSONObject()
        host.execute(
            "browser_click",
            """{"text":"Confirm purchase"}""",
            object : McToolCallback {
                override fun success(resultJson: String) {
                    result = JSONObject(resultJson)
                }

                override fun error(message: String) {
                    error(message)
                }
            },
        )

        assertEquals("browser_click", delegatedToolName)
        assertEquals("""{"text":"Confirm purchase"}""", delegatedParams)
        assertEquals(true, result.getBoolean("success"))
        assertEquals(true, result.getBoolean("clicked"))
    }

    @Test
    fun browserToolHostDelegatesReadOnlySnapshotWithoutApproval() {
        var controllerCalled = false
        val controller = NapaxiBrowserController { toolName, _, callback ->
            controllerCalled = true
            callback.success(JSONObject().put("action", toolName).put("success", true).toString())
        }
        val host = AndroidBrowserToolHost(controller = controller)

        var result = JSONObject()
        host.execute(
            "browser_snapshot",
            "{}",
            object : McToolCallback {
                override fun success(resultJson: String) {
                    result = JSONObject(resultJson)
                }

                override fun error(message: String) {
                    error(message)
                }
            },
        )

        assertEquals(true, controllerCalled)
        assertEquals(true, result.getBoolean("success"))
        assertEquals("browser_snapshot", result.getString("action"))
    }

    @Test
    fun browserToolProviderHasStableFallbackDefinitions() {
        val definitions = BrowserToolProvider.getToolDefinitions()
        val names = definitions.map { it.name }.toSet()

        assertTrue(BrowserToolProvider.isBrowserTool("browser_open"))
        assertTrue(names.contains("browser_open"))
        assertTrue(names.contains("browser_snapshot"))
        assertTrue(names.contains("browser_click"))
    }

    @Test
    fun androidPlatformToolRegistryNormalizesCoreCapabilityNames() {
        assertEquals("open_url", AndroidPlatformToolExecutor.normalizeToolName("napaxi.platform_tool.open_url"))
        assertEquals("open_url", AndroidPlatformToolExecutor.normalizeToolName("open_url"))
        assertTrue(AndroidPlatformToolExecutor.platformToolNames.contains("open_url"))
        assertTrue(AndroidPlatformToolExecutor.platformToolNames.contains("install_apk"))
        assertTrue(AndroidPlatformToolExecutor.platformToolNames.contains("media_library"))
        assertTrue(AndroidPlatformToolExecutor.platformToolNames.contains("record_audio"))
    }

    @Test
    fun agentAppActionRequestExposesFlutterStylePackageField() {
        val request = AgentAppActionRequest(
            """
            {
              "proposal":{
                "request_id":"request-1",
                "provider_id":"provider.app",
                "agent_id":"calendar_agent",
                "action_id":"create_event",
                "tool_name":"app_action_create_event",
                "arguments":{"title":"Demo"}
              },
              "action":{
                "action_id":"create_event",
                "tool_name":"app_action_create_event",
                "description":"Create event"
              },
              "package":{
                "provider_id":"provider.app",
                "agent_id":"calendar_agent",
                "display_name":"Calendar Agent"
              }
            }
            """.trimIndent(),
        )

        assertEquals("request-1", request.proposal.requestId)
        assertEquals("create_event", request.action.actionId)
        assertEquals("provider.app", request.`package`.getString("provider_id"))
        assertEquals(request.packageJson.toString(), request.`package`.toString())

        val typedRequest = AgentAppActionRequest(
            proposal = AgentAppActionProposal(
                requestId = "request-2",
                providerId = "provider.app",
                agentId = "calendar_agent",
                actionId = "create_event",
                toolName = "app_action_create_event",
                arguments = JSONObject("""{"title":"Typed"}"""),
            ),
            action = AgentAppActionManifest(
                actionId = "create_event",
                toolName = "app_action_create_event",
                description = "Create event",
            ),
            `package` = JSONObject(
                """
                {
                  "provider_id":"provider.app",
                  "agent_id":"calendar_agent",
                  "display_name":"Calendar Agent"
                }
                """.trimIndent(),
            ),
        )

        assertEquals("request-2", typedRequest.requestId)
        assertEquals("Typed", typedRequest.proposal.arguments.getString("title"))
        assertEquals("Calendar Agent", typedRequest.`package`.getString("display_name"))
        assertEquals("request-2", AgentAppActionRequest.fromJson(typedRequest.toJsonString()).requestId)
        assertEquals("create_event", AgentAppActionRequest.fromJsonObject(typedRequest.toJsonObject()).action.actionId)

        val fromMap = AgentAppActionRequest.fromMap(
            mapOf(
                "proposal" to mapOf(
                    "request_id" to "request-3",
                    "provider_id" to "provider.app",
                    "agent_id" to "calendar_agent",
                    "action_id" to "create_event",
                    "tool_name" to "app_action_create_event",
                    "arguments" to mapOf("title" to "Mapped"),
                ),
                "action" to mapOf(
                    "action_id" to "create_event",
                    "tool_name" to "app_action_create_event",
                    "description" to "Create event",
                ),
                "package" to mapOf(
                    "provider_id" to "provider.app",
                    "agent_id" to "calendar_agent",
                    "display_name" to "Calendar Agent",
                ),
            ),
        )

        assertEquals("request-3", fromMap.requestId)
        assertEquals("Mapped", fromMap.proposal.arguments.getString("title"))
        assertEquals("Calendar Agent", fromMap.`package`.getString("display_name"))
        assertEquals(fromMap.toJson(), fromMap.toJsonString())
    }

    @Test
    fun toolApprovalRequestParametersFallbackToEmptyObjectLikeFlutter() {
        val valid = McToolApprovalRequest(
            requestId = 1L,
            toolName = "browser_click",
            parametersJson = """{"text":"Pay"}""",
        )
        val invalid = McToolApprovalRequest(
            requestId = 2L,
            toolName = "browser_click",
            parametersJson = "{not json",
        )
        val nonObject = McToolApprovalRequest(
            requestId = 3L,
            toolName = "browser_click",
            parametersJson = """["not","object"]""",
        )

        assertEquals("Pay", valid.parameters.getString("text"))
        assertEquals(0, invalid.parameters.length())
        assertEquals(0, nonObject.parameters.length())
        val fromJson = McToolApprovalRequest.fromJson(
            """
            {
              "request_id":4,
              "tool_name":"browser_click",
              "description":"Approve click",
              "parameters":{"text":"Submit"},
              "context":{"surface":"browser"},
              "allow_always":true
            }
            """.trimIndent(),
        )
        val fromMap = McToolApprovalRequest.fromMap(
            mapOf(
                "requestId" to 5L,
                "toolName" to "browser_click",
                "parametersJson" to """{"text":"Cancel"}""",
                "allowAlways" to true,
            ),
        )

        assertEquals(4L, fromJson.requestId)
        assertEquals("browser_click", fromJson.toolName)
        assertEquals("Submit", fromJson.parameters.getString("text"))
        assertEquals("browser", JSONObject(fromJson.contextJson).getString("surface"))
        assertEquals(true, fromJson.allowAlways)
        assertEquals(5L, fromMap.requestId)
        assertEquals("Cancel", fromMap.parameters.getString("text"))
        assertEquals(true, fromMap.allowAlways)
    }

    @Test
    fun toolApprovalResponseMatchesFlutterStableJsonShape() {
        val denied = McToolApprovalResponse(approved = false)
        val approved = McToolApprovalResponse(
            approved = true,
            always = true,
            message = "Approved for this session.",
        )

        val deniedJson = denied.toJsonObject()
        val approvedJson = JSONObject(approved.toJsonString())

        assertEquals(false, deniedJson.getBoolean("approved"))
        assertEquals(false, deniedJson.getBoolean("always"))
        assertEquals(false, deniedJson.has("message"))
        assertEquals(true, approvedJson.getBoolean("approved"))
        assertEquals(true, approvedJson.getBoolean("always"))
        assertEquals("Approved for this session.", approvedJson.getString("message"))
        assertEquals(approved.toJson(), approved.toJsonString())
        assertEquals(true, McToolApprovalResponse.fromJson(approved.toJson()).approved)
        assertEquals(false, McToolApprovalResponse.fromJsonObject(deniedJson).approved)
        assertEquals(
            "Approved from map.",
            McToolApprovalResponse.fromMap(
                mapOf(
                    "approved" to true,
                    "always" to true,
                    "message" to "Approved from map.",
                ),
            ).message,
        )
    }

    @Test
    fun androidPlatformToolsReturnFlutterStyleValidationFailures() {
        val executor = AndroidPlatformToolExecutor(ContextWrapper(null))
        val invalidUrl = JSONObject(executor.execute("open_url", "{}"))
        val missingPhone = JSONObject(executor.execute("make_call", "{}"))
        val missingSmsPhone = JSONObject(executor.execute("send_sms", "{}"))
        val missingApkPath = JSONObject(executor.execute("install_apk", "{}"))
        val thrownFailure = JSONObject(executor.execute("get_clipboard", "{}"))
        var callbackFailure = JSONObject()
        executor.execute(
            "open_url",
            "{not json",
            "{}",
            object : McToolCallback {
                override fun success(resultJson: String) {
                    callbackFailure = JSONObject(resultJson)
                }

                override fun error(message: String) {
                    error(message)
                }
            },
        )

        assertEquals(false, invalidUrl.getBoolean("success"))
        assertEquals("Invalid URL: ", invalidUrl.getString("error"))
        assertEquals(false, missingPhone.getBoolean("success"))
        assertEquals("phone_number is required", missingPhone.getString("error"))
        assertEquals(false, missingSmsPhone.getBoolean("success"))
        assertEquals("phone_number is required", missingSmsPhone.getString("error"))
        assertEquals(false, missingApkPath.getBoolean("success"))
        assertEquals(false, missingApkPath.getBoolean("installerOpened"))
        assertEquals(false, missingApkPath.getBoolean("permissionRequired"))
        assertEquals("missing_apk_path", missingApkPath.getString("code"))
        assertEquals(false, thrownFailure.getBoolean("success"))
        assertTrue(thrownFailure.getString("error").isNotBlank())
        assertEquals(false, callbackFailure.getBoolean("success"))
        assertTrue(callbackFailure.getString("error").isNotBlank())
    }

    @Test
    fun androidPlatformToolContextMirrorsFlutterSandboxMappingAndAttachmentShape() {
        val tempDir = Files.createTempDirectory("napaxi-platform-context").toFile()
        val workspaceBase = tempDir.resolve("workspace-base").absolutePath
        val context = AndroidPlatformToolContext(
            filesDir = tempDir.absolutePath,
            workspaceFilesDir = workspaceBase,
        )
        val attachmentDir = context.ensureAttachmentDir("camera")
        val result = JSONObject(
            context.attachmentResultJson(
                sandboxPath = "/workspace/attachments/camera/photo.jpg",
                kind = "image",
                filename = "photo.jpg",
                mimeType = "image/jpeg",
                sizeBytes = 1234L,
                extra = JSONObject().put("source", "camera"),
            ),
        )

        assertEquals("$workspaceBase/linux-env/workspace", context.workspaceDir)
        assertEquals("${tempDir.absolutePath}/linux-env/rootfs", context.rootfsDir)
        assertEquals("${tempDir.absolutePath}/prompt_skills", context.skillsDir)
        assertEquals("$workspaceBase/linux-env/workspace/out.png", context.resolveSandboxOrLocalPath("/workspace/out.png"))
        assertEquals("${tempDir.absolutePath}/prompt_skills/wallet/SKILL.md", context.resolveSandboxOrLocalPath("/skills/wallet/SKILL.md"))
        assertEquals("${tempDir.absolutePath}/linux-env/rootfs/tmp/out.txt", context.resolveSandboxOrLocalPath("/tmp/out.txt"))
        assertEquals("/sdcard/Download/out.txt", context.resolveSandboxOrLocalPath("/sdcard/Download/out.txt"))
        assertEquals("/workspace/attachments/audio/rec.wav", context.attachmentSandboxPath("audio", "rec.wav"))
        assertEquals("$workspaceBase/linux-env/workspace/attachments/camera", attachmentDir?.absolutePath)
        assertEquals(true, attachmentDir?.isDirectory)

        assertEquals("/workspace/attachments/camera/photo.jpg", result.getString("sandbox_path"))
        assertEquals("/workspace/attachments/camera/photo.jpg", result.getString("file_path"))
        assertEquals("image", result.getString("kind"))
        assertEquals("photo.jpg", result.getString("filename"))
        assertEquals("image/jpeg", result.getString("mime_type"))
        assertEquals("image/jpeg", result.getString("mimeType"))
        assertEquals(1234L, result.getLong("size_bytes"))
        assertEquals(1234L, result.getLong("sizeBytes"))
        assertEquals("camera", result.getString("source"))
    }

    @Test
    fun androidPlatformMediaRequestClampsFlutterDurationParameters() {
        val context = AndroidPlatformToolContext(filesDir = "/app/files", workspaceFilesDir = null)

        assertEquals(
            1,
            AndroidPlatformMediaToolRequest(
                toolName = "record_audio",
                params = JSONObject("""{"duration_seconds":0}"""),
                paramsJson = """{"duration_seconds":0}""",
                context = context,
            ).durationSeconds,
        )
        assertEquals(
            60,
            AndroidPlatformMediaToolRequest(
                toolName = "record_audio",
                params = JSONObject("""{"durationSecs":120}"""),
                paramsJson = """{"durationSecs":120}""",
                context = context,
            ).durationSeconds,
        )
        assertEquals(
            10,
            AndroidPlatformMediaToolRequest(
                toolName = "record_audio",
                params = JSONObject("{}"),
                paramsJson = "{}",
                context = context,
            ).durationSeconds,
        )
    }

    @Test
    fun androidAlarmParserAcceptsFlutterRepeatDayAliases() {
        val alarm = AndroidPlatformToolExecutor.parseAlarm(
            JSONObject("""{"time":"07:30","message":"Wake up","repeat_days":"weekdays,周末"}"""),
        )

        assertEquals(7, alarm.hour)
        assertEquals(30, alarm.minute)
        assertEquals("Wake up", alarm.message)
        assertEquals(setOf(1, 2, 3, 4, 5, 6, 7), alarm.repeatDays.toSet())
    }
}
