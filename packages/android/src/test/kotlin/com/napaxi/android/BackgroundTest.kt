package com.napaxi.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class BackgroundTest {
    @Test
    fun backgroundConfigExportsFlutterChannelShape() {
        val config = BackgroundConfig(
            enabled = true,
            notificationConfig = BackgroundNotificationConfig(
                channelName = "Agent Channel",
                ongoingTitle = "Running",
                completionMessage = "Done",
            ),
            wakeLockTimeoutMs = 1234,
        )
        val map = config.toMap()
        val json = config.toJsonObject()
        val flutterNamedConfig = NotificationConfig(channelName = "Flutter Name")
        val parsed = BackgroundConfig.fromJson(config.toJson())
        val fromMap = BackgroundConfig.fromMap(
            mapOf(
                "enabled" to false,
                "channelName" to "Mapped Channel",
                "ongoingTitle" to "Mapped Running",
                "completionMessage" to "Mapped Done",
                "wakeLockTimeoutMs" to 4321,
            ),
        )
        val notificationFromMap = BackgroundNotificationConfig.fromMap(
            mapOf(
                "channelName" to "Notify Channel",
                "hitlTitle" to "Needs approval",
                "openActionLabel" to "Open app",
            ),
        )

        assertEquals(true, map["enabled"])
        assertEquals("Agent Channel", map["channelName"])
        assertEquals("Running", map["ongoingTitle"])
        assertEquals("Done", map["completionMessage"])
        assertEquals(1234, map["wakeLockTimeoutMs"])
        assertEquals(1234L, config.wakeLockTimeout.toMillis())
        assertEquals("Agent Channel", json.getString("channelName"))
        assertEquals(1234, json.getInt("wakeLockTimeoutMs"))
        assertEquals("Flutter Name", flutterNamedConfig.channelName)
        assertEquals(config.toJson(), config.toJsonString())
        assertEquals("Agent Channel", parsed.notificationConfig.channelName)
        assertEquals(1234, parsed.wakeLockTimeoutMs)
        assertEquals(false, fromMap.enabled)
        assertEquals("Mapped Channel", fromMap.notificationConfig.channelName)
        assertEquals("Mapped Running", fromMap.notificationConfig.ongoingTitle)
        assertEquals("Mapped Done", fromMap.notificationConfig.completionMessage)
        assertEquals(4321, fromMap.wakeLockTimeoutMs)
        assertEquals("Notify Channel", notificationFromMap.channelName)
        assertEquals("Needs approval", notificationFromMap.hitlTitle)
        assertEquals("Open app", notificationFromMap.openActionLabel)
        assertEquals(notificationFromMap.toJson(), notificationFromMap.toJsonString())
    }

    @Test
    fun backgroundActionEventExposesTypedFlutterActionNames() {
        val approved = BackgroundActionEvent.fromAction(
            BackgroundAction.HitlApprove,
            requestId = "hitl-1",
            payload = "Allow",
        )
        val denied = BackgroundActionEvent.fromNotificationAction(
            NapaxiNotificationManager.ACTION_DENY,
            requestId = "hitl-2",
            payload = "Deny",
        )
        val fromMap = BackgroundActionEvent.fromMap(
            mapOf(
                "action" to "agentTrigger",
                "requestId" to "trigger-1",
                "payload" to "Wake",
            ),
        )
        val parsed = BackgroundActionEvent.fromJson(approved.toJson())

        assertEquals("hitlApprove", approved.action)
        assertEquals(BackgroundAction.HitlApprove, approved.actionType)
        assertEquals("hitl-1", approved.toMap()["requestId"])
        assertEquals("Allow", approved.toJsonObject().getString("payload"))
        assertEquals(approved.toJson(), approved.toJsonString())
        assertEquals("hitlApprove", parsed.action)
        assertEquals("hitl-1", parsed.requestId)

        assertEquals(BackgroundAction.HitlDeny, denied?.actionType)
        assertEquals("hitlDeny", denied?.action)
        assertEquals(BackgroundAction.AgentTrigger, fromMap.actionType)
        assertEquals("trigger-1", fromMap.requestId)
        assertEquals("Wake", fromMap.payload)
    }

    @Test
    fun backgroundActionEnumCoversFlutterStableActions() {
        val flutterActions = setOf("stop", "hitlApprove", "hitlDeny", "viewResult", "agentTrigger")

        assertTrue(BackgroundAction.flutterParityWireNames().containsAll(flutterActions))
    }

    @Test
    fun backgroundApiExposesFlutterStyleControllerAndPermissionHelpers() {
        val root = repoRoot()
        val backgroundSource = String(
            java.nio.file.Files.readAllBytes(root.resolve("packages/android/src/main/kotlin/com/napaxi/android/Background.kt")),
            Charsets.UTF_8,
        )

        val requiredSnippets = listOf(
            "public val controller: NapaxiBackgroundController?",
            "fun checkNotificationPermission(context: Context)",
            "fun requestNotificationPermission(",
            "fun canRunInBackground(context: Context)",
            "NapaxiBackgroundPermissions.checkNotificationPermission(context)",
            "NapaxiBackgroundPermissions.requestNotificationPermission(activity, requestCode)",
            "NapaxiBackgroundPermissions.canRunInBackground(context)",
            "fun fromMap(map: Map<String, *>): BackgroundConfig",
            "fun fromMap(map: Map<String, *>): BackgroundNotificationConfig",
            "fun fromMap(map: Map<String, *>): BackgroundActionEvent",
            "fun toJsonString(): String = toJson()",
        )
        val missingSnippets = requiredSnippets.filterNot(backgroundSource::contains)

        assertTrue(
            "Android BackgroundApi is missing Flutter-style controller or permission helpers: $missingSnippets",
            missingSnippets.isEmpty(),
        )
    }

    private fun repoRoot(): java.nio.file.Path {
        val cwd = java.nio.file.Paths.get("").toAbsolutePath()
        return generateSequence(cwd) { it.parent }
            .firstOrNull { java.nio.file.Files.exists(it.resolve("packages/android/src/main/kotlin/com/napaxi/android/Background.kt")) }
            ?: error("Could not locate Napaxi repository root from $cwd")
    }
}
