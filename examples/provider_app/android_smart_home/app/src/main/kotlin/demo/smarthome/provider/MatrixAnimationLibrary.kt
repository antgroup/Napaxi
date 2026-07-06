package demo.smarthome.provider

import android.graphics.Color
import org.json.JSONArray
import org.json.JSONObject

/**
 * Deterministic short-loop animations for the Yeelight Cube 20x5 matrix.
 *
 * These are intentionally tuned for demo floors: high contrast, short cycles,
 * and shapes that remain legible from a distance.
 */
object MatrixAnimationLibrary {
    data class Animation(
        val id: String,
        val label: String,
        val description: String,
        val defaultColor: Int = Color.rgb(0xFF, 0xC1, 0x07),
        val defaultAccentColor: Int = Color.rgb(0x00, 0xD8, 0xFF),
        val frameDelayMs: Int = 180,
        val recommendedLoops: Int = 3,
        val framesTopFirst: List<List<String>>,
    )

    private const val MATRIX_COLUMNS = 20
    private const val MATRIX_ROWS = 5

    val animations: List<Animation> = listOf(
        Animation(
            id = "scanner",
            label = "扫描光束",
            description = "A sweeping vertical beam that reads clearly across a booth.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            defaultAccentColor = Color.rgb(0x88, 0xF0, 0xFF),
            frameDelayMs = 120,
            recommendedLoops = 4,
            framesTopFirst = listOf(
                beamFrame(0),
                beamFrame(3),
                beamFrame(6),
                beamFrame(9),
                beamFrame(12),
                beamFrame(15),
            ),
        ),
        Animation(
            id = "equalizer",
            label = "均衡器",
            description = "Animated bar graph for music, speech, and active-agent demos.",
            defaultColor = Color.rgb(0x4C, 0xD9, 0x64),
            defaultAccentColor = Color.rgb(0xFF, 0xC1, 0x07),
            frameDelayMs = 150,
            recommendedLoops = 4,
            framesTopFirst = listOf(
                listOf(
                    row("...................."),
                    row("....AA......AA......"),
                    row("..XXAA..XX..XXAA..XX"),
                    row("XXXXAA..XXXXXXAA..XX"),
                    row("XXXXXXXXXXXXXXXXXXXX"),
                ),
                listOf(
                    row("..AA..........AA...."),
                    row("..XX..AA..AA..XX...."),
                    row("..XX..XX..XX..XX..AA"),
                    row("XXXX..XX..XX..XXXXAA"),
                    row("XXXXXXXXXXXXXXXXXXXX"),
                ),
                listOf(
                    row("......AA....AA......"),
                    row("..AA..XX....XX..AA.."),
                    row("..XX..XX..AA..XX..XX"),
                    row("XXXX..XXXXXX..XX..XX"),
                    row("XXXXXXXXXXXXXXXXXXXX"),
                ),
                listOf(
                    row("....AA..........AA.."),
                    row("....XX..AA..AA..XX.."),
                    row("AA..XX..XX..XX..XX.."),
                    row("AAXXXX..XX..XX..XXXX"),
                    row("XXXXXXXXXXXXXXXXXXXX"),
                ),
            ),
        ),
        Animation(
            id = "pulse_heart",
            label = "心跳",
            description = "A pulsing heart loop for welcome, empathy, and human-agent moments.",
            defaultColor = Color.rgb(0xFF, 0x4D, 0x6D),
            defaultAccentColor = Color.rgb(0xFF, 0xA6, 0xB8),
            frameDelayMs = 180,
            recommendedLoops = 3,
            framesTopFirst = listOf(
                listOf(
                    row("......AA....AA......"),
                    row("....AAXXAA..AAXXAA.."),
                    row("...XXXXXXXXXXXXXX..."),
                    row("....XXXXXXXXXXXX...."),
                    row("......XXXXXXXX......"),
                ),
                listOf(
                    row("....AA......AA......"),
                    row("..AAXXXXAA..AAXXXX.."),
                    row(".XXXXXXXXXXXXXXXXXX."),
                    row("..XXXXXXXXXXXXXXXX.."),
                    row("....XXXXXXXXXXXX...."),
                ),
                listOf(
                    row("......AA....AA......"),
                    row("....AAXXAA..AAXXAA.."),
                    row("...XXXXXXXXXXXXXX..."),
                    row("....XXXXXXXXXXXX...."),
                    row("......XXXXXXXX......"),
                ),
                listOf(
                    row("........AA..AA......"),
                    row("......AAXXXXAA......"),
                    row("....XXXXXXXXXXXX...."),
                    row("......XXXXXXXX......"),
                    row("........XXXX........"),
                ),
            ),
        ),
        Animation(
            id = "arrow_chase",
            label = "追光箭头",
            description = "A moving right-arrow loop for guiding visitors to the next station.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            defaultAccentColor = Color.rgb(0xFF, 0xFF, 0xFF),
            frameDelayMs = 120,
            recommendedLoops = 4,
            framesTopFirst = listOf(
                arrowFrame(0),
                arrowFrame(4),
                arrowFrame(8),
                arrowFrame(12),
            ),
        ),
        Animation(
            id = "sparkle",
            label = "星闪",
            description = "A clean sparkle loop for premium showcase moments.",
            defaultColor = Color.rgb(0xFF, 0xE0, 0x66),
            defaultAccentColor = Color.rgb(0xFF, 0xFF, 0xFF),
            frameDelayMs = 150,
            recommendedLoops = 4,
            framesTopFirst = listOf(
                listOf(
                    row("A.......X.......A..."),
                    row("....X.......A......."),
                    row("........A.......X..."),
                    row("...X.......A........"),
                    row("A.......X.......A..."),
                ),
                listOf(
                    row("...A.......X.......A"),
                    row(".......A.......X...."),
                    row("...X.......A........"),
                    row("........X.......A..."),
                    row("...A.......X.......A"),
                ),
                listOf(
                    row("X.......A.......X..."),
                    row("....A.......X......."),
                    row("........X.......A..."),
                    row("...A.......X........"),
                    row("X.......A.......X..."),
                ),
                listOf(
                    row("...X.......A.......X"),
                    row(".......X.......A...."),
                    row("...A.......X........"),
                    row("........A.......X..."),
                    row("...X.......A.......X"),
                ),
            ),
        ),
        Animation(
            id = "rainbow_chase",
            label = "彩虹追逐",
            description = "A colorful horizontal chase that feels immediately like showcase mode.",
            frameDelayMs = 120,
            recommendedLoops = 4,
            framesTopFirst = listOf(
                listOf(
                    row("RRYYGGCCBBPPRRYYGGCC"),
                    row("RRYYGGCCBBPPRRYYGGCC"),
                    row("RRYYGGCCBBPPRRYYGGCC"),
                    row("RRYYGGCCBBPPRRYYGGCC"),
                    row("RRYYGGCCBBPPRRYYGGCC"),
                ),
                listOf(
                    row("YYGGCCBBPPRRYYGGCCRR"),
                    row("YYGGCCBBPPRRYYGGCCRR"),
                    row("YYGGCCBBPPRRYYGGCCRR"),
                    row("YYGGCCBBPPRRYYGGCCRR"),
                    row("YYGGCCBBPPRRYYGGCCRR"),
                ),
                listOf(
                    row("GGCCBBPPRRYYGGCCRRYY"),
                    row("GGCCBBPPRRYYGGCCRRYY"),
                    row("GGCCBBPPRRYYGGCCRRYY"),
                    row("GGCCBBPPRRYYGGCCRRYY"),
                    row("GGCCBBPPRRYYGGCCRRYY"),
                ),
                listOf(
                    row("CCBBPPRRYYGGCCRRYYGG"),
                    row("CCBBPPRRYYGGCCRRYYGG"),
                    row("CCBBPPRRYYGGCCRRYYGG"),
                    row("CCBBPPRRYYGGCCRRYYGG"),
                    row("CCBBPPRRYYGGCCRRYYGG"),
                ),
            ),
        ),
        Animation(
            id = "traffic_flow",
            label = "流动灯带",
            description = "A moving ribbon effect for active status and kinetic product demos.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            defaultAccentColor = Color.rgb(0x4C, 0xD9, 0x64),
            frameDelayMs = 110,
            recommendedLoops = 5,
            framesTopFirst = listOf(
                listOf(
                    row("XX.................."),
                    row("..XX................"),
                    row("....AAXX............"),
                    row("........AAXX........"),
                    row("............AAXX...."),
                ),
                listOf(
                    row("....XX.............."),
                    row("......XX............"),
                    row("........AAXX........"),
                    row("............AAXX...."),
                    row("................AAXX"),
                ),
                listOf(
                    row("........XX.........."),
                    row("..........XX........"),
                    row("............AAXX...."),
                    row("................AAXX"),
                    row("..............AAXX.."),
                ),
                listOf(
                    row("............XX......"),
                    row("..............XX...."),
                    row("................AAXX"),
                    row("..............AAXX.."),
                    row("..........AAXX......"),
                ),
            ),
        ),
        Animation(
            id = "ocean_wave",
            label = "海浪流动",
            description = "A layered blue-white wave loop inspired by the official ocean-style sticker rows.",
            defaultColor = Color.rgb(0x00, 0xC6, 0xFF),
            defaultAccentColor = Color.rgb(0xFF, 0xFF, 0xFF),
            frameDelayMs = 140,
            recommendedLoops = 4,
            framesTopFirst = listOf(
                listOf(
                    row("...................."),
                    row("..AAA......AAA......"),
                    row(".XXXXAA..XXXXAA....."),
                    row("XXXXXXXXXXXXXXAA...."),
                    row("..AAAAAAAAAAAAAA...."),
                ),
                listOf(
                    row("...................."),
                    row("....AAA......AAA...."),
                    row("..XXXXAA..XXXXAA...."),
                    row(".XXXXXXXXXXXXXXAA..."),
                    row("....AAAAAAAAAAAAAA.."),
                ),
                listOf(
                    row("...................."),
                    row("......AAA......AAA.."),
                    row("....XXXXAA..XXXXAA.."),
                    row("...AXXXXXXXXXXXXXX.."),
                    row("..AAAAAAAAAAAAAA...."),
                ),
                listOf(
                    row("...................."),
                    row(".AAA......AAA......."),
                    row(".AAXXXX..AAXXXX....."),
                    row("AAXXXXXXXXXXXXXX...."),
                    row("AAAAAAAAAAAAAA......"),
                ),
            ),
        ),
        Animation(
            id = "party_blink",
            label = "派对闪烁",
            description = "A multicolor burst loop that feels close to an official party preset turned dynamic.",
            frameDelayMs = 130,
            recommendedLoops = 5,
            framesTopFirst = listOf(
                listOf(
                    row("R...Y...G...C...B..."),
                    row(".Y...G...C...B...P.."),
                    row("..G...C...B...P...R."),
                    row(".C...B...P...R...Y.."),
                    row("B...P...R...Y...G..."),
                ),
                listOf(
                    row(".Y...G...C...B...P.."),
                    row("..G...C...B...P...R."),
                    row(".C...B...P...R...Y.."),
                    row("B...P...R...Y...G..."),
                    row(".R...Y...G...C...B.."),
                ),
                listOf(
                    row("..G...C...B...P...R."),
                    row(".C...B...P...R...Y.."),
                    row("B...P...R...Y...G..."),
                    row(".R...Y...G...C...B.."),
                    row("..Y...G...C...B...P."),
                ),
            ),
        ),
        Animation(
            id = "windmill",
            label = "风车转动",
            description = "A simple rotating windmill loop inspired by the green-hills official cards.",
            defaultColor = Color.rgb(0x4C, 0xD9, 0x64),
            defaultAccentColor = Color.rgb(0xFF, 0xFF, 0xFF),
            frameDelayMs = 160,
            recommendedLoops = 4,
            framesTopFirst = listOf(
                listOf(
                    row("........A..........."),
                    row("......AAXAA........."),
                    row("........A..........."),
                    row(".......AAA.........."),
                    row(".......ANA.........."),
                ),
                listOf(
                    row("..........A........."),
                    row("........AAXAA......."),
                    row("..........A........."),
                    row(".........AAA........"),
                    row(".........ANA........"),
                ),
                listOf(
                    row("........A..........."),
                    row("......AAXAA........."),
                    row("........A..........."),
                    row(".......AAA.........."),
                    row(".......ANA.........."),
                ),
                listOf(
                    row("......A............."),
                    row("....AAXAA..........."),
                    row("......A............."),
                    row(".....AAA............"),
                    row(".....ANA............"),
                ),
            ),
        ),
        Animation(
            id = "radar",
            label = "雷达扫描",
            description = "A compact radar sweep for sensing, monitoring, and automation demos.",
            defaultColor = Color.rgb(0x4C, 0xD9, 0x64),
            defaultAccentColor = Color.rgb(0x88, 0xF0, 0xFF),
            frameDelayMs = 160,
            recommendedLoops = 4,
            framesTopFirst = listOf(
                listOf(
                    row(".........A.........."),
                    row("........AX.........."),
                    row(".......AAXX........."),
                    row("........AX.........."),
                    row(".........A.........."),
                ),
                listOf(
                    row("...........A........"),
                    row("..........XA........"),
                    row(".........XXAA......."),
                    row("..........XA........"),
                    row("...........A........"),
                ),
                listOf(
                    row("..........A........."),
                    row("..........XA........"),
                    row(".........XXAA......."),
                    row("..........XA........"),
                    row("..........A........."),
                ),
                listOf(
                    row("........A..........."),
                    row("........AX.........."),
                    row(".......AAXX........."),
                    row("........AX.........."),
                    row("........A..........."),
                ),
            ),
        ),
    )

    private val animationById: Map<String, Animation> = animations.associateBy { it.id }

    init {
        animations.forEach { animation ->
            check(animation.framesTopFirst.isNotEmpty()) {
                "Animation ${animation.id} must have at least one frame"
            }
            animation.framesTopFirst.forEach { frame ->
                check(frame.size == MATRIX_ROWS) {
                    "Animation ${animation.id} frames must have exactly $MATRIX_ROWS rows"
                }
                frame.forEach { row ->
                    check(row.length == MATRIX_COLUMNS) {
                        "Animation ${animation.id} rows must be $MATRIX_COLUMNS columns wide"
                    }
                }
            }
        }
    }

    fun animationIds(): List<String> = animations.map { it.id }

    fun summaryJoined(separator: String = ", "): String =
        animations.joinToString(separator) { "${it.id}(${it.label})" }

    fun promptLines(): String =
        animations.joinToString(separator = "\n") {
            "- ${it.id}: ${it.label}，${it.description}"
        }

    fun paramsSchemaJson(): String =
        JSONObject()
            .put("type", "object")
            .put(
                "properties",
                JSONObject()
                    .put(
                        "animation",
                        JSONObject()
                            .put("type", "string")
                            .put("enum", JSONArray(animationIds()))
                            .put(
                                "description",
                                "One named Yeelight Cube short-loop animation. Available values: ${summaryJoined()}",
                            ),
                    )
                    .put(
                        "color",
                        JSONObject()
                            .put("type", "string")
                            .put("pattern", "^#[0-9A-Fa-f]{6}$")
                            .put("description", "Optional primary animation color in #RRGGBB format."),
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
                            .put("description", "Optional accent color for two-tone animations."),
                    )
                    .put(
                        "loops",
                        JSONObject()
                            .put("type", "integer")
                            .put("minimum", 1)
                            .put("maximum", 6)
                            .put("description", "Optional loop count. Keep loops short for expo demos."),
                    )
                    .put(
                        "frame_delay_ms",
                        JSONObject()
                            .put("type", "integer")
                            .put("minimum", 80)
                            .put("maximum", 1000)
                            .put("description", "Optional per-frame delay in milliseconds."),
                    ),
            )
            .put("required", JSONArray(listOf("animation")))
            .toString()

    fun renderAnimationFrames(
        animationId: String,
        colorHex: String?,
        backgroundHex: String?,
        accentHex: String?,
    ): List<List<Int>> {
        val animation = animationById[animationId.trim()]
            ?: error("Unsupported matrix animation: $animationId")
        return animation.framesTopFirst.map { frame ->
            MatrixPresetLibrary.renderRows(
                rowsTopFirst = frame,
                colorHex = colorHex,
                backgroundHex = backgroundHex,
                accentHex = accentHex,
                defaultColor = animation.defaultColor,
                defaultAccentColor = animation.defaultAccentColor,
            )
        }
    }

    fun defaultLoopCount(animationId: String): Int =
        animationById[animationId.trim()]?.recommendedLoops
            ?: error("Unsupported matrix animation: $animationId")

    fun defaultFrameDelayMs(animationId: String): Int =
        animationById[animationId.trim()]?.frameDelayMs
            ?: error("Unsupported matrix animation: $animationId")

    private fun beamFrame(start: Int): List<String> =
        List(MATRIX_ROWS) { row(".".repeat(start.coerceAtLeast(0)) + "AX") }

    private fun arrowFrame(offset: Int): List<String> {
        val blank = ".".repeat(offset.coerceAtLeast(0))
        return listOf(
            row("${blank}....XX"),
            row("${blank}..XXXXXX"),
            row("${blank}XXXXXXXXXX"),
            row("${blank}..XXXXXX"),
            row("${blank}....XX"),
        )
    }

    private fun row(pattern: String, fill: Char = '.'): String =
        pattern.padEnd(MATRIX_COLUMNS, fill).take(MATRIX_COLUMNS)
}
