package demo.smartdesk.provider

import agent.provider.sdk.AgentAction
import agent.provider.sdk.AgentPackage
import agent.provider.sdk.ConfirmationPolicy
import agent.provider.sdk.ExecutionMode

object SmartDeskPackage {
    const val PROVIDER_ID = "demo.smart_desk_provider"
    const val AGENT_ID = "demo.smart_desk.agent"

    const val ACTION_FOCUS = "desk.scene.focus"
    const val ACTION_RELAX = "desk.scene.relax"
    const val ACTION_OFF = "desk.scene.off"
    const val ACTION_SET_COLOR = "desk.light.set_color"
    const val ACTION_SET_BRIGHTNESS = "desk.light.set_brightness"
    const val ACTION_PLUG_ON = "desk.plug.turn_on"
    const val ACTION_PLUG_OFF = "desk.plug.turn_off"
    const val ACTION_STATUS = "desk.status.get"

    val packageDef: AgentPackage
        get() = AgentPackage(
            providerId = PROVIDER_ID,
            agentId = AGENT_ID,
            displayName = "Smart Desk Agent",
            description = "A cinematic virtual desk with lights, plug, scenes, and sensor triggers.",
            systemPrompt = """
                You control a virtual smart desk through provider-owned actions.
                Prefer scene actions for broad user requests. Ask for confirmation through the provider app for any state-changing action.
            """.trimIndent(),
            actions = listOf(
                sceneAction(ACTION_FOCUS, "app_action_desk_scene_focus", "Focus scene", "专注场景", "Switch the desk into a crisp focus scene.", "切换到适合专注工作的桌面场景。"),
                sceneAction(ACTION_RELAX, "app_action_desk_scene_relax", "Relax scene", "放松场景", "Switch the desk into a warm relax scene.", "切换到温暖放松的桌面场景。"),
                sceneAction(ACTION_OFF, "app_action_desk_scene_off", "Turn desk off", "关闭桌面设备", "Turn the virtual desk devices off.", "关闭虚拟桌面的灯光和插座。"),
                AgentAction(
                    actionId = ACTION_SET_COLOR,
                    toolName = "app_action_desk_light_set_color",
                    description = "Set the virtual desk light color.",
                    parametersJson = """{"type":"object","properties":{"color":{"type":"string","description":"Hex RGB color like #4AA3FF."}},"required":["color"]}""",
                    resultSchemaJson = resultSchema,
                    risk = "medium",
                    confirmationPolicy = ConfirmationPolicy.PROVIDER_REQUIRED,
                    executionModes = executionModes,
                    timeoutSeconds = 300,
                    displayName = "Set light color",
                    localizedDisplayNames = names("Set light color", "设置灯光颜色"),
                    localizedDescriptions = descriptions("Set the virtual desk light color.", "设置虚拟桌面灯光的颜色。"),
                ),
                AgentAction(
                    actionId = ACTION_SET_BRIGHTNESS,
                    toolName = "app_action_desk_light_set_brightness",
                    description = "Set the virtual desk brightness from 0 to 100.",
                    parametersJson = """{"type":"object","properties":{"brightness":{"type":"integer","minimum":0,"maximum":100}},"required":["brightness"]}""",
                    resultSchemaJson = resultSchema,
                    risk = "medium",
                    confirmationPolicy = ConfirmationPolicy.PROVIDER_REQUIRED,
                    executionModes = executionModes,
                    timeoutSeconds = 300,
                    displayName = "Set brightness",
                    localizedDisplayNames = names("Set brightness", "设置亮度"),
                    localizedDescriptions = descriptions("Set the virtual desk brightness from 0 to 100.", "将虚拟桌面的灯光亮度设置为 0 到 100。"),
                ),
                sceneAction(ACTION_PLUG_ON, "app_action_desk_plug_turn_on", "Turn plug on", "打开插座", "Turn the virtual desk plug on.", "打开虚拟桌面的插座。"),
                sceneAction(ACTION_PLUG_OFF, "app_action_desk_plug_turn_off", "Turn plug off", "关闭插座", "Turn the virtual desk plug off.", "关闭虚拟桌面的插座。"),
                AgentAction(
                    actionId = ACTION_STATUS,
                    toolName = "app_action_desk_status_get",
                    description = "Read the current virtual smart desk state.",
                    parametersJson = """{"type":"object","properties":{}}""",
                    resultSchemaJson = resultSchema,
                    risk = "low",
                    confirmationPolicy = ConfirmationPolicy.NONE,
                    executionModes = executionModes,
                    timeoutSeconds = 120,
                    displayName = "Read desk status",
                    localizedDisplayNames = names("Read desk status", "读取桌面状态"),
                    localizedDescriptions = descriptions("Read the current virtual smart desk state.", "查看虚拟桌面的当前状态。"),
                ),
            ),
            handoffJson = """{"mode":"android_activity_result","display":"cinematic_confirmation"}""",
            resultJson = """{"mode":"activity_result","schema":"smart_desk_state"}""",
        )

    private val executionModes = listOf(
        ExecutionMode.APP_HANDOFF,
        ExecutionMode.ANDROID_ACTIVITY_RESULT,
    )

    private const val resultSchema =
        """{"type":"object","properties":{"scene":{"type":"string"},"light_on":{"type":"boolean"},"brightness":{"type":"integer"},"color":{"type":"string"},"plug_on":{"type":"boolean"},"timestamp":{"type":"string"}}}"""

    private fun sceneAction(
        actionId: String,
        toolName: String,
        displayName: String,
        chineseDisplayName: String,
        description: String,
        chineseDescription: String,
    ): AgentAction =
        AgentAction(
            actionId = actionId,
            toolName = toolName,
            description = description,
            parametersJson = """{"type":"object","properties":{}}""",
            resultSchemaJson = resultSchema,
            risk = "medium",
            confirmationPolicy = ConfirmationPolicy.PROVIDER_REQUIRED,
            executionModes = executionModes,
            timeoutSeconds = 300,
            displayName = displayName,
            localizedDisplayNames = names(displayName, chineseDisplayName),
            localizedDescriptions = descriptions(description, chineseDescription),
        )

    private fun names(english: String, chinese: String) =
        mapOf("en" to english, "zh-CN" to chinese)

    private fun descriptions(english: String, chinese: String) =
        mapOf("en" to english, "zh-CN" to chinese)
}
