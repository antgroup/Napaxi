package demo.smarthome.provider

import org.json.JSONArray
import org.json.JSONObject

/**
 * Single source of truth for the lights this demo can control.
 *
 * Both napaxi integration paths read from here:
 * - the local embedded SDK ([SmartHomeAgentRuntime]) builds its custom-tool
 *   schemas and system prompt from this catalog, and
 * - the provider protocol package ([SmartHomePackage]) builds its action
 *   parameter schemas and system prompt from the same catalog.
 *
 * Adding or removing a light only requires editing [lights]; the tool schemas,
 * the validation, and both system prompts stay in sync automatically.
 */
object LightCatalog {
    data class Light(val room: String, val device: String, val label: String)

    val lights: List<Light> = listOf(
        Light("living_room", "floor_lamp", "客厅落地灯"),
        Light("living_room", "spotlights", "客厅射灯"),
        Light("living_room", "bar_lamp", "吧台灯"),
        Light("kitchen", "spotlights", "厨房射灯"),
    )

    /** Total pixels on the bound Yeelight Cube (20 columns x 5 rows). */
    const val MATRIX_PIXEL_COUNT: Int = 100

    fun roomEnum(): List<String> = lights.map { it.room }.distinct()

    fun deviceEnum(): List<String> = lights.map { it.device }.distinct()

    fun isSupported(room: String, device: String): Boolean =
        lights.any { it.room == room && it.device == device }

    fun labelsJoined(separator: String = "、"): String =
        lights.joinToString(separator) { it.label }

    /** Multi-line `- room/device: label` list, used inside system prompts. */
    fun promptLines(): String =
        lights.joinToString(separator = "\n") { "- ${it.room}/${it.device}: ${it.label}" }

    /** Comma-joined `room/floor_lamp` style pairs, used inside descriptions. */
    fun pairsJoined(separator: String = ", "): String =
        lights.joinToString(separator) { "${it.room}/${it.device}" }

    /** Parameter schema for controlling a single light. */
    fun lightParamsSchemaJson(): String =
        JSONObject()
            .put("type", "object")
            .put(
                "properties",
                JSONObject()
                    .put("room", stringEnumSchema(roomEnum()))
                    .put("device", stringEnumSchema(deviceEnum()))
                    .put("on", JSONObject().put("type", "boolean"))
                    .put("brightness", brightnessSchema()),
            )
            .put("required", JSONArray(listOf("room", "device")))
            .toString()

    /** Parameter schema for controlling every supported light at once. */
    fun allLightsParamsSchemaJson(): String =
        JSONObject()
            .put("type", "object")
            .put(
                "properties",
                JSONObject()
                    .put("on", JSONObject().put("type", "boolean"))
                    .put("brightness", brightnessSchema()),
            )
            .toString()

    /** Parameter schema for drawing one 20x5 RGB frame on the Yeelight Cube. */
    fun matrixParamsSchemaJson(): String =
        JSONObject()
            .put("type", "object")
            .put(
                "properties",
                JSONObject().put(
                    "pixels",
                    JSONObject()
                        .put("type", "array")
                        .put(
                            "description",
                            "Exactly $MATRIX_PIXEL_COUNT RGB colors for a 20-column by 5-row " +
                                "Yeelight Cube matrix. Use #RRGGBB strings; #000000 turns a pixel off. " +
                                "Pixel order starts at the bottom-left, proceeds left-to-right across " +
                                "each row, then moves upward row by row.",
                        )
                        .put(
                            "items",
                            JSONObject()
                                .put("type", "string")
                                .put("pattern", "^#[0-9A-Fa-f]{6}$"),
                        )
                        .put("minItems", MATRIX_PIXEL_COUNT)
                        .put("maxItems", MATRIX_PIXEL_COUNT),
                ),
            )
            .put("required", JSONArray(listOf("pixels")))
            .toString()

    private fun stringEnumSchema(values: List<String>): JSONObject =
        JSONObject()
            .put("type", "string")
            .put("enum", JSONArray(values))

    private fun brightnessSchema(): JSONObject =
        JSONObject()
            .put("type", "integer")
            .put("minimum", 0)
            .put("maximum", 100)
}
