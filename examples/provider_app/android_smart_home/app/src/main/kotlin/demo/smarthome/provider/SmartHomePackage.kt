package demo.smarthome.provider

import agent.provider.sdk.AgentAction
import agent.provider.sdk.AgentPackage
import agent.provider.sdk.ConfirmationPolicy
import agent.provider.sdk.ExecutionMode

object SmartHomePackage {
    const val PROVIDER_ID = "demo.smart_home_provider"
    const val AGENT_ID = "demo.smart_home.agent"

    const val ACTION_LIGHT_SET = "home.light.set"
    const val ACTION_LIGHT_MATRIX_PRESET = "home.light.matrix.preset.show"
    const val ACTION_LIGHT_MATRIX_ANIMATION = "home.light.matrix.animation.show"
    const val ACTION_LIGHT_MATRIX_DRAW = "home.light.matrix.draw_20x5"
    const val ACTION_COVER_SET = "home.cover.set"
    const val ACTION_MEDIA_TOGGLE = "home.media.toggle"
    const val ACTION_APPLIANCE_TOGGLE = "home.appliance.toggle"
    const val ACTION_CLIMATE_SET = "home.climate.set"
    const val ACTION_SCENE_AWAY = "home.scene.away"
    const val ACTION_SCENE_HOME = "home.scene.home"
    const val ACTION_STATUS = "home.status.get"

    val packageDef: AgentPackage
        get() = AgentPackage(
            providerId = PROVIDER_ID,
            agentId = AGENT_ID,
            displayName = "Smart Home Light Agent",
            description = "Control smart home lights and a Yeelight Cube 20x5 pixel matrix through a trusted provider binding.",
            systemPrompt = """
                You control smart home lights through provider-owned actions.
                Use app_action_home_light_set for normal light power and brightness.
                Use app_action_home_light_matrix_preset_show for common Yeelight Cube icons, arrows, mood patterns, and quick visual feedback.
                Use app_action_home_light_matrix_animation_show for short high-impact Yeelight Cube animations that are easy to read at demo distance.
                Use app_action_home_light_matrix_draw_20x5 only when the user asks to draw, display, render, animate a still frame, or control the Yeelight Cube pixel matrix.
                Available lights are ${LightCatalog.pairsJoined()}.
                The Yeelight Cube is bound to living_room/floor_lamp and has a 20-column by 5-row RGB matrix, 100 pixels total.
                Available matrix presets are ${MatrixPresetLibrary.summaryJoined()}.
                Available matrix animations are ${MatrixAnimationLibrary.summaryJoined()}.
                Matrix pixel order is bottom row first: index 0 is bottom-left, indices 0-19 go left-to-right across the bottom row; indices 20-39 are the row above; continue upward until indices 80-99 are the top row.
                Matrix colors must be #RRGGBB strings. To leave a pixel dark, use #000000.
                Prefer the preset tool for common symbols because it is faster and more reliable than manually specifying 100 pixels.
                Prefer the animation tool for expo showcases, celebration cues, directions, scanning, radar, music, and active-status displays.
                Prefer simple readable patterns with high contrast, because the display is only 20 x 5.
                When a user asks for entryway or presence lighting, prefer living_room/floor_lamp.
                These trusted demo actions can execute without a provider confirmation tap after the smart home app is connected to Napaxi.
            """.trimIndent(),
            actions = listOf(
                AgentAction(
                    actionId = ACTION_LIGHT_SET,
                    toolName = "app_action_home_light_set",
                    description = "Turn a light on/off and optionally set brightness 0-100.",
                    parametersJson = LightCatalog.lightParamsSchemaJson(),
                    resultSchemaJson = resultSchema,
                    risk = "medium",
                    confirmationPolicy = ConfirmationPolicy.NONE,
                    executionModes = executionModes,
                    timeoutSeconds = 300,
                    displayName = "Control light",
                    localizedDisplayNames = names("Control light", "控制灯光"),
                    localizedDescriptions = descriptions("Turn a light on/off and optionally set brightness 0-100.", "打开或关闭灯光，并可设置 0 到 100 的亮度。"),
                ),
                AgentAction(
                    actionId = ACTION_LIGHT_MATRIX_PRESET,
                    toolName = "app_action_home_light_matrix_preset_show",
                    description = """
                        Show one named preset on the bound Yeelight Cube 20 x 5 RGB matrix.
                        Best for hearts, smiley faces, arrows, checks, crosses, warnings, rainbows, waves, all-on, and clear/off.
                        Use optional colors when the user asks for a specific colorway.
                    """.trimIndent(),
                    parametersJson = matrixPresetParametersJson,
                    resultSchemaJson = resultSchema,
                    risk = "medium",
                    confirmationPolicy = ConfirmationPolicy.NONE,
                    executionModes = executionModes,
                    timeoutSeconds = 300,
                    displayName = "Show matrix preset",
                    localizedDisplayNames = names("Show matrix preset", "显示矩阵预设"),
                    localizedDescriptions = descriptions("Show a named preset on the Yeelight Cube matrix.", "在 Yeelight Cube 矩阵上显示预设图案。"),
                ),
                AgentAction(
                    actionId = ACTION_LIGHT_MATRIX_ANIMATION,
                    toolName = "app_action_home_light_matrix_animation_show",
                    description = """
                        Play one short-loop Yeelight Cube 20 x 5 RGB animation.
                        Best for expo demos, scanning beams, equalizers, pulsing hearts, radar, sparkle, and directional motion.
                        Use optional color overrides when the user asks for a specific look.
                    """.trimIndent(),
                    parametersJson = matrixAnimationParametersJson,
                    resultSchemaJson = resultSchema,
                    risk = "medium",
                    confirmationPolicy = ConfirmationPolicy.NONE,
                    executionModes = executionModes,
                    timeoutSeconds = 300,
                    displayName = "Play matrix animation",
                    localizedDisplayNames = names("Play matrix animation", "播放矩阵动画"),
                    localizedDescriptions = descriptions("Play a short Yeelight Cube matrix animation.", "在 Yeelight Cube 矩阵上播放短动画。"),
                ),
                AgentAction(
                    actionId = ACTION_LIGHT_MATRIX_DRAW,
                    toolName = "app_action_home_light_matrix_draw_20x5",
                    description = """
                        Draw one still frame on the bound Yeelight Cube 20 x 5 RGB pixel matrix.
                        Provide exactly 100 #RRGGBB colors in bottom-row-first order.
                        Index mapping: 0 is bottom-left, 19 is bottom-right, 20 is the next row up leftmost, and 99 is top-right.
                        Use #000000 for off pixels. Keep drawings simple and high contrast.
                    """.trimIndent(),
                    parametersJson = matrixParametersJson,
                    resultSchemaJson = resultSchema,
                    risk = "medium",
                    confirmationPolicy = ConfirmationPolicy.NONE,
                    executionModes = executionModes,
                    timeoutSeconds = 300,
                    displayName = "Draw pixel frame",
                    localizedDisplayNames = names("Draw pixel frame", "绘制像素画面"),
                    localizedDescriptions = descriptions("Draw one still frame on the Yeelight Cube 20 x 5 RGB matrix.", "在 Yeelight Cube 20×5 RGB 矩阵上绘制一帧像素画面。"),
                ),
            ),
            handoffJson = """{"mode":"android_activity_result","display":"home_dashboard_confirmation"}""",
            resultJson = """{"mode":"activity_result","schema":"smart_home_state"}""",
        )

    private val executionModes = listOf(
        ExecutionMode.APP_HANDOFF,
        ExecutionMode.ANDROID_ACTIVITY_RESULT,
    )

    private const val resultSchema =
        """{"type":"object","properties":{"scene":{"type":"string"},"rooms":{"type":"object"},"energy":{"type":"object"},"outdoor":{"type":"object"},"timestamp":{"type":"string"}}}"""

    // Light parameter schemas are generated from the shared LightCatalog so the
    // provider protocol and the local SDK path can never drift apart.
    private val matrixPresetParametersJson: String
        get() = LightCatalog.matrixPresetParamsSchemaJson()

    private val matrixAnimationParametersJson: String
        get() = LightCatalog.matrixAnimationParamsSchemaJson()

    private val matrixParametersJson: String
        get() = LightCatalog.matrixParamsSchemaJson()

    private fun names(english: String, chinese: String) =
        mapOf("en" to english, "zh-CN" to chinese)

    private fun descriptions(english: String, chinese: String) =
        mapOf("en" to english, "zh-CN" to chinese)
}
