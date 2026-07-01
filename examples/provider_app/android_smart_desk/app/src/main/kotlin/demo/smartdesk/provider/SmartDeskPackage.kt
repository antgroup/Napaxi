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
                sceneAction(ACTION_FOCUS, "app_action_desk_scene_focus", "Switch the desk into a crisp focus scene."),
                sceneAction(ACTION_RELAX, "app_action_desk_scene_relax", "Switch the desk into a warm relax scene."),
                sceneAction(ACTION_OFF, "app_action_desk_scene_off", "Turn the virtual desk devices off."),
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
                ),
                sceneAction(ACTION_PLUG_ON, "app_action_desk_plug_turn_on", "Turn the virtual desk plug on."),
                sceneAction(ACTION_PLUG_OFF, "app_action_desk_plug_turn_off", "Turn the virtual desk plug off."),
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

    private fun sceneAction(actionId: String, toolName: String, description: String): AgentAction =
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
        )
}
