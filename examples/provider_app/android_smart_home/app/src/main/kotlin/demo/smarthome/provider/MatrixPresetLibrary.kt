package demo.smarthome.provider

import android.graphics.Color
import org.json.JSONArray
import org.json.JSONObject

/**
 * Deterministic 20x5 Yeelight Cube preset library owned by the smart-home app.
 *
 * Presets are authored in a human-readable top-row-first form and converted to
 * the bottom-row-first wire layout expected by the provider prompt and Yeelight
 * LAN transport.
 */
object MatrixPresetLibrary {
    data class Preset(
        val id: String,
        val label: String,
        val description: String,
        val defaultColor: Int = Color.rgb(0xFF, 0xC1, 0x07),
        val defaultAccentColor: Int = Color.rgb(0x00, 0xD8, 0xFF),
        val rowsTopFirst: List<String>,
    )

    private const val MATRIX_COLUMNS = 20
    private const val MATRIX_ROWS = 5

    val presets: List<Preset> = listOf(
        Preset(
            id = "all_on",
            label = "全亮",
            description = "Fill the whole 20x5 matrix with one solid color.",
            rowsTopFirst = filledRows('X'),
        ),
        Preset(
            id = "clear",
            label = "清空",
            description = "Turn every matrix pixel off.",
            rowsTopFirst = filledRows('.'),
        ),
        Preset(
            id = "heart",
            label = "爱心",
            description = "A centered heart icon for warm ambient feedback.",
            defaultColor = Color.rgb(0xFF, 0x4D, 0x6D),
            rowsTopFirst = listOf(
                "....XX......XX......",
                "..XXXXXX..XXXXXX....",
                ".XXXXXXXXXXXXXXXX...",
                "..XXXXXXXXXXXXXX....",
                "....XXXXXXXXXX......",
            ),
        ),
        Preset(
            id = "smile",
            label = "笑脸",
            description = "A simple smiling face for friendly acknowledgements.",
            defaultColor = Color.rgb(0xFF, 0xC1, 0x07),
            rowsTopFirst = listOf(
                "...XX........XX.....",
                "...XX........XX.....",
                "....................",
                "..XX..XXXXXXXX..XX..",
                "...XXXXXXXXXXXX.....",
            ),
        ),
        Preset(
            id = "arrow_left",
            label = "左箭头",
            description = "Directional left arrow.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            rowsTopFirst = listOf(
                "......XX............",
                "...XXXXXX...........",
                "XXXXXXXXXXXXXXXXXX..",
                "...XXXXXX...........",
                "......XX............",
            ),
        ),
        Preset(
            id = "arrow_right",
            label = "右箭头",
            description = "Directional right arrow.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            rowsTopFirst = listOf(
                "............XX......",
                "...........XXXXXX...",
                "..XXXXXXXXXXXXXXXXXX",
                "...........XXXXXX...",
                "............XX......",
            ),
        ),
        Preset(
            id = "check",
            label = "勾",
            description = "A bold check mark.",
            defaultColor = Color.rgb(0x3D, 0xD6, 0x66),
            rowsTopFirst = listOf(
                "..............XX....",
                "............XXXX....",
                "..XX......XXXX......",
                "...XXXX..XXXX.......",
                ".....XXXXXX.........",
            ),
        ),
        Preset(
            id = "cross",
            label = "叉",
            description = "A bold cross mark.",
            defaultColor = Color.rgb(0xFF, 0x5A, 0x5F),
            rowsTopFirst = listOf(
                "..XX..........XX....",
                "....XX......XX......",
                "......XXXXXX........",
                "....XX......XX......",
                "..XX..........XX....",
            ),
        ),
        Preset(
            id = "warning",
            label = "警示",
            description = "Warning marker with an exclamation silhouette.",
            defaultColor = Color.rgb(0xFF, 0xB2, 0x00),
            rowsTopFirst = listOf(
                ".........XX.........",
                "........XXXX........",
                ".......XX..XX.......",
                "........XXXX........",
                ".........XX.........",
            ),
        ),
        Preset(
            id = "wave",
            label = "波浪",
            description = "A soft animated-looking wave frame for ambience.",
            defaultColor = Color.rgb(0x00, 0xC6, 0xFF),
            defaultAccentColor = Color.rgb(0x1E, 0x66, 0xF5),
            rowsTopFirst = listOf(
                "AA....AA....AA....AA",
                "..AA....AA....AA....",
                "....AA....AA....AA..",
                "..AA....AA....AA....",
                "AA....AA....AA....AA",
            ),
        ),
        Preset(
            id = "rainbow",
            label = "彩虹",
            description = "Full-width rainbow bands across the 20x5 matrix.",
            rowsTopFirst = listOf(
                "RRRRRRRRRRRRRRRRRRRR",
                "YYYYYYYYYYYYYYYYYYYY",
                "GGGGGGGGGGGGGGGGGGGG",
                "CCCCCCCCCCCCCCCCCCCC",
                "BBBBBBBBBBBBBBBBBBBB",
            ),
        ),
    )

    private val presetById: Map<String, Preset> = presets.associateBy { it.id }

    init {
        presets.forEach { preset ->
            check(preset.rowsTopFirst.size == MATRIX_ROWS) {
                "Preset ${preset.id} must have exactly $MATRIX_ROWS rows"
            }
            preset.rowsTopFirst.forEach { row ->
                check(row.length == MATRIX_COLUMNS) {
                    "Preset ${preset.id} rows must be $MATRIX_COLUMNS columns wide"
                }
            }
        }
    }

    fun presetIds(): List<String> = presets.map { it.id }

    fun summaryJoined(separator: String = ", "): String =
        presets.joinToString(separator) { "${it.id}(${it.label})" }

    fun promptLines(): String =
        presets.joinToString(separator = "\n") {
            "- ${it.id}: ${it.label}，${it.description}"
        }

    fun paramsSchemaJson(): String =
        JSONObject()
            .put("type", "object")
            .put(
                "properties",
                JSONObject()
                    .put(
                        "preset",
                        JSONObject()
                            .put("type", "string")
                            .put("enum", JSONArray(presetIds()))
                            .put(
                                "description",
                                "One named 20x5 preset. Available values: ${summaryJoined()}",
                            ),
                    )
                    .put(
                        "color",
                        JSONObject()
                            .put("type", "string")
                            .put("pattern", "^#[0-9A-Fa-f]{6}$")
                            .put("description", "Optional primary preset color in #RRGGBB format."),
                    )
                    .put(
                        "background_color",
                        JSONObject()
                            .put("type", "string")
                            .put("pattern", "^#[0-9A-Fa-f]{6}$")
                            .put("description", "Optional background color in #RRGGBB format. Defaults to #000000."),
                    )
                    .put(
                        "accent_color",
                        JSONObject()
                            .put("type", "string")
                            .put("pattern", "^#[0-9A-Fa-f]{6}$")
                            .put("description", "Optional secondary accent color for presets that use two tones."),
                    ),
            )
            .put("required", JSONArray(listOf("preset")))
            .toString()

    fun renderPreset(
        presetId: String,
        colorHex: String?,
        backgroundHex: String?,
        accentHex: String?,
    ): List<Int> {
        val preset = presetById[presetId.trim()]
            ?: error("Unsupported matrix preset: $presetId")
        val primary = colorHex?.takeIf { it.isNotBlank() }?.let(::parseColor) ?: preset.defaultColor
        val background = backgroundHex?.takeIf { it.isNotBlank() }?.let(::parseColor) ?: Color.BLACK
        val accent = accentHex?.takeIf { it.isNotBlank() }?.let(::parseColor) ?: preset.defaultAccentColor
        val rows = preset.rowsTopFirst
        check(rows.size == MATRIX_ROWS) { "Preset ${preset.id} must have $MATRIX_ROWS rows" }
        rows.forEach {
            check(it.length == MATRIX_COLUMNS) {
                "Preset ${preset.id} rows must be $MATRIX_COLUMNS columns wide"
            }
        }
        val pixels = mutableListOf<Int>()
        for (rowIndex in rows.indices.reversed()) {
            val row = rows[rowIndex]
            for (columnIndex in row.indices) {
                pixels += colorForToken(
                    token = row[columnIndex],
                    primary = primary,
                    background = background,
                    accent = accent,
                )
            }
        }
        return pixels
    }

    private fun colorForToken(
        token: Char,
        primary: Int,
        background: Int,
        accent: Int,
    ): Int = when (token) {
        '.', ' ' -> background
        'X' -> primary
        'A' -> accent
        'R' -> Color.rgb(0xFF, 0x4D, 0x4F)
        'Y' -> Color.rgb(0xFF, 0xC5, 0x3D)
        'G' -> Color.rgb(0x4C, 0xD9, 0x64)
        'C' -> Color.rgb(0x00, 0xD8, 0xFF)
        'B' -> Color.rgb(0x3A, 0x86, 0xFF)
        'P' -> Color.rgb(0xA6, 0x4D, 0xFF)
        'W' -> Color.WHITE
        'K' -> Color.BLACK
        else -> error("Unsupported matrix token: $token")
    }

    private fun parseColor(value: String): Int {
        val hex = value.trim().removePrefix("#")
        check(hex.length == 6) { "Color must be #RRGGBB: $value" }
        return hex.toInt(16) and 0xFFFFFF
    }

    private fun filledRows(token: Char): List<String> =
        List(MATRIX_ROWS) { token.toString().repeat(MATRIX_COLUMNS) }
}
