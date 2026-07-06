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
                row("....XX......XX...."),
                row("..XXXXXX..XXXXXX.."),
                row(".XXXXXXXXXXXXXXXX."),
                row("..XXXXXXXXXXXXXX.."),
                row("....XXXXXXXXXX...."),
            ),
        ),
        Preset(
            id = "smile",
            label = "笑脸",
            description = "A simple smiling face for friendly acknowledgements.",
            defaultColor = Color.rgb(0xFF, 0xC1, 0x07),
            rowsTopFirst = listOf(
                row("...XX........XX..."),
                row("...XX........XX..."),
                row("................"),
                row("..XX..XXXXXXXX..XX"),
                row("...XXXXXXXXXXXX..."),
            ),
        ),
        Preset(
            id = "arrow_left",
            label = "左箭头",
            description = "Directional left arrow.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            rowsTopFirst = listOf(
                row("......XX.........."),
                row("...XXXXXX........."),
                row("XXXXXXXXXXXXXXXXXX"),
                row("...XXXXXX........."),
                row("......XX.........."),
            ),
        ),
        Preset(
            id = "arrow_right",
            label = "右箭头",
            description = "Directional right arrow.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            rowsTopFirst = listOf(
                row("............XX...."),
                row("...........XXXXXX."),
                row("..XXXXXXXXXXXXXXXXXX"),
                row("...........XXXXXX."),
                row("............XX...."),
            ),
        ),
        Preset(
            id = "arrow_up",
            label = "上箭头",
            description = "Directional up arrow for navigation and lift-up moments.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            rowsTopFirst = listOf(
                row(".........XX......."),
                row(".......XXXXXX....."),
                row(".....XXXXXXXXXX..."),
                row(".........XX......."),
                row(".........XX......."),
            ),
        ),
        Preset(
            id = "arrow_down",
            label = "下箭头",
            description = "Directional down arrow for drop, park, or settle actions.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            rowsTopFirst = listOf(
                row(".........XX......."),
                row(".........XX......."),
                row(".....XXXXXXXXXX..."),
                row(".......XXXXXX....."),
                row(".........XX......."),
            ),
        ),
        Preset(
            id = "check",
            label = "勾",
            description = "A bold check mark.",
            defaultColor = Color.rgb(0x3D, 0xD6, 0x66),
            rowsTopFirst = listOf(
                row("..............XX.."),
                row("............XXXX.."),
                row("..XX......XXXX...."),
                row("...XXXX..XXXX....."),
                row(".....XXXXXX......."),
            ),
        ),
        Preset(
            id = "cross",
            label = "叉",
            description = "A bold cross mark.",
            defaultColor = Color.rgb(0xFF, 0x5A, 0x5F),
            rowsTopFirst = listOf(
                row("..XX..........XX.."),
                row("....XX......XX...."),
                row("......XXXXXX......"),
                row("....XX......XX...."),
                row("..XX..........XX.."),
            ),
        ),
        Preset(
            id = "warning",
            label = "警示",
            description = "Warning marker with an exclamation silhouette.",
            defaultColor = Color.rgb(0xFF, 0xB2, 0x00),
            rowsTopFirst = listOf(
                row(".........XX........"),
                row("........XXXX......."),
                row(".......XX..XX......"),
                row("........XXXX......."),
                row(".........XX........"),
            ),
        ),
        Preset(
            id = "star",
            label = "星光",
            description = "A wide starburst that reads well from a distance.",
            defaultColor = Color.rgb(0xFF, 0xE0, 0x66),
            rowsTopFirst = listOf(
                row("........XX........"),
                row("..XX....XX....XX.."),
                row("....XXXXXXXXXX...."),
                row("..XX..XXXXXX..XX.."),
                row("......XX..XX......"),
            ),
        ),
        Preset(
            id = "bolt",
            label = "闪电",
            description = "A sharp lightning bolt for speed, power, and energy moments.",
            defaultColor = Color.rgb(0xFF, 0xD4, 0x1F),
            rowsTopFirst = listOf(
                row("......XXXXXX......"),
                row("....XXXXXX........"),
                row("......XXXXXXXX...."),
                row("........XXXXXX...."),
                row("......XXXX........"),
            ),
        ),
        Preset(
            id = "diamond",
            label = "钻石",
            description = "A clean gem silhouette for premium moments and spotlight demos.",
            defaultColor = Color.rgb(0x88, 0xF0, 0xFF),
            defaultAccentColor = Color.rgb(0xFF, 0xFF, 0xFF),
            rowsTopFirst = listOf(
                row(".........AA......."),
                row("......AAXXAAX....."),
                row("....AAXXXXXXAAX..."),
                row("......AAXXAAX....."),
                row(".........AA......."),
            ),
        ),
        Preset(
            id = "trophy",
            label = "奖杯",
            description = "A trophy cup for achievements, stage wins, and leaderboard reveals.",
            defaultColor = Color.rgb(0xFF, 0xC1, 0x07),
            rowsTopFirst = listOf(
                row("....XXXXXXXXXXXX.."),
                row("..XX..XXXXXXXX..XX"),
                row("....XXXXXXXXXXXX.."),
                row(".......XXXXXX....."),
                row("......XXXXXXXX...."),
            ),
        ),
        Preset(
            id = "music",
            label = "音符",
            description = "A music note for audio demos and party cues.",
            defaultColor = Color.rgb(0xB0, 0x4C, 0xFF),
            rowsTopFirst = listOf(
                row(".......XX....XXXX."),
                row(".......XX..XX..XX."),
                row(".......XX..XX..XX."),
                row(".......XXXX....XX."),
                row(".......XX......XX."),
            ),
        ),
        Preset(
            id = "eye",
            label = "眼睛",
            description = "A wide eye icon for sensing, awareness, and attention cues.",
            defaultColor = Color.rgb(0x00, 0xD8, 0xFF),
            defaultAccentColor = Color.rgb(0xFF, 0xFF, 0xFF),
            rowsTopFirst = listOf(
                row("....XXXXXXXXXXXX.."),
                row("..XXXX..AA..XXXX.."),
                row(".XXX....AA....XXX."),
                row("..XXXX..AA..XXXX.."),
                row("....XXXXXXXXXXXX.."),
            ),
        ),
        Preset(
            id = "signal",
            label = "信号",
            description = "A Wi-Fi style signal icon for connectivity or bridge demos.",
            defaultColor = Color.rgb(0x4C, 0xD9, 0x64),
            rowsTopFirst = listOf(
                row("........XX........"),
                row("......XX..XX......"),
                row("....XX......XX...."),
                row("..XX..........XX.."),
                row("........XX........"),
            ),
        ),
        Preset(
            id = "ai",
            label = "AI",
            description = "A bold AI wordmark that fits the 20x5 wall at trade-show distance.",
            defaultColor = Color.rgb(0x88, 0xF0, 0xFF),
            rowsTopFirst = listOf(
                row("XX....XX...XXXX...."),
                row("XX....XX..XX..XX..."),
                row("XXXXXXXX..XXXXXX..."),
                row("XX....XX..XX..XX..."),
                row("XX....XX..XX..XX..."),
            ),
        ),
        Preset(
            id = "party",
            label = "派对",
            description = "A confetti-style burst for party scenes and expo attraction moments.",
            defaultColor = Color.rgb(0xFF, 0x4D, 0xA6),
            defaultAccentColor = Color.rgb(0x00, 0xD8, 0xFF),
            rowsTopFirst = listOf(
                row("X...A...X...A...X."),
                row(".A...X...A...X...A"),
                row("...X...A...X...A.."),
                row(".A...X...A...X...A"),
                row("X...A...X...A...X."),
            ),
        ),
        Preset(
            id = "gold_wings",
            label = "金翼徽记",
            description = "A gold wing-like crest inspired by the official top-left hero card.",
            rowsTopFirst = listOf(
                row(".O....YYY..YYY...O."),
                row("..YYYYYYYYYYYYYY...."),
                row("...YYYYRRRRRRYYYY..."),
                row("....YYYYYYYYYYYY...."),
                row(".....YYYYYYYYYY....."),
            ),
        ),
        Preset(
            id = "crown",
            label = "皇冠",
            description = "A colorful crown sticker for premium demo moments and hero reveals.",
            rowsTopFirst = listOf(
                row("..Y.....YY.....Y..."),
                row(".YYY...YYYY...YYY.."),
                row("YYYYY.YYYYYY.YYYYY."),
                row(".YYYYYYRRRRYYYYYY.."),
                row("...YYYYYYYYYYYY...."),
            ),
        ),
        Preset(
            id = "ufo",
            label = "飞碟",
            description = "A playful UFO sticker for sci-fi and future-tech demos.",
            rowsTopFirst = listOf(
                row("......CCYYCC......"),
                row("....CCCCCCCCCC...."),
                row("..WWWWWWWWWWWWWW.."),
                row("......P....P......"),
                row("....P..P..P..P...."),
            ),
        ),
        Preset(
            id = "trees",
            label = "小树林",
            description = "A friendly tree pair for nature, outdoor, and calm ambient scenes.",
            rowsTopFirst = listOf(
                row(".....GG......GG...."),
                row("....GGGG....GGGG..."),
                row("...GGGGGG..GGGGGG.."),
                row("..GGGGGGGGGGGGGGG.."),
                row("....N.........N...."),
            ),
        ),
        Preset(
            id = "gems",
            label = "宝石",
            description = "Three jewel icons with bright accent colors for eye-catching showcases.",
            rowsTopFirst = listOf(
                row("..O....C....P....Y."),
                row(".OO..CCC..PPP..YY.."),
                row("OOOOCCCCCPPPPYYYY.."),
                row(".OO..CCC..PPP..YY.."),
                row("..O....C....P....Y."),
            ),
        ),
        Preset(
            id = "petal_trio",
            label = "三朵霓虹花",
            description = "Three colorful flower-like badges inspired by the official multi-color sticker row.",
            rowsTopFirst = listOf(
                row("..O.O...C.C...P.P..."),
                row(".OOYOO.CCYCC.PPYPP.."),
                row("..O.O...C.C...P.P..."),
                row(".YY.....YY.....YY..."),
                row("...................."),
            ),
        ),
        Preset(
            id = "dog",
            label = "小狗",
            description = "A simple side-profile dog sticker that reads well on the 20x5 wall.",
            defaultColor = Color.rgb(0xB8, 0x7A, 0x3F),
            rowsTopFirst = listOf(
                row("T..............T..."),
                row("TTT.TTTTTTTTTT.TTT."),
                row("TTTTTTTTTTTTTTTTTT.."),
                row("..TTTTTTTTTTTTTTTT.."),
                row("....TT........TT..."),
            ),
        ),
        Preset(
            id = "car",
            label = "小车",
            description = "A colorful car icon for mobility, drone, and robotics demos.",
            defaultAccentColor = Color.rgb(0xB0, 0xB7, 0xC3),
            rowsTopFirst = listOf(
                row("....RRRRRRRRRR...."),
                row("..RRRWWWWWWWWRRR.."),
                row(".RRRRRRRRRRRRRRRR."),
                row("..HH........HH...."),
                row("..HH........HH...."),
            ),
        ),
        Preset(
            id = "comet",
            label = "彗星",
            description = "A fast comet streak for launch, boost, and reveal moments.",
            rowsTopFirst = listOf(
                row("CC.................."),
                row("..CC................"),
                row("....CC.............."),
                row("......CC..WWTTTTTT.."),
                row("........WWTTTTTTTT.."),
            ),
        ),
        Preset(
            id = "skyline",
            label = "天际线",
            description = "A bright pixel skyline with ground line for stage background ambience.",
            rowsTopFirst = listOf(
                row("RRRRRR..RRRR..RRRRR."),
                row("RRRRRRR.RRRR.RRRRRR."),
                row("RRR..RRRRRRRRR..RRR."),
                row("RRRRRRR..RR..RRRRRR."),
                row("RRRRRRRRRRRRRRRRRRR."),
            ),
        ),
        Preset(
            id = "whale",
            label = "鲸鱼",
            description = "A blue whale sticker inspired by the official playful ocean-style presets.",
            rowsTopFirst = listOf(
                row("....CCCCCCCC........"),
                row("..CCCCCCCCCCCC......"),
                row(".CCCCCCCCCCCCCCC...C"),
                row("..WWWWCCCCCCCCCCCCC."),
                row("....WWWWWWWWWWCCC..."),
            ),
        ),
        Preset(
            id = "bat",
            label = "蝙蝠",
            description = "A sharp night-bat silhouette with a bright center accent.",
            rowsTopFirst = listOf(
                row("BBBBBBBBYYBBBBBBBBBB"),
                row("..BBBBBYYYYBBBBBB..."),
                row("....BBBYYYYYYBBB...."),
                row("......BBYYYYBB......"),
                row(".....BB..YY..BB....."),
            ),
        ),
        Preset(
            id = "sunrise",
            label = "日出",
            description = "Twin sunrise hills with warm tones, inspired by the official scenic presets.",
            rowsTopFirst = listOf(
                row("...RYYY......RYYY..."),
                row("..RYYYYY....RYYYYY.."),
                row("..YYYYYY....YYYYYY.."),
                row(".YYYYYYYY..YYYYYYYY."),
                row("BBBBBBBBBBBBBBBBBBBB"),
            ),
        ),
        Preset(
            id = "i_love_you",
            label = "I LOVE",
            description = "A bold text+heart sign for crowd-pleasing expo moments.",
            rowsTopFirst = listOf(
                row("W...RR....WW..W.WWWW"),
                row("W..RRRR...WW..W.W..."),
                row("W.RRRRRR..WWW.W.WWW."),
                row("W..RRRR...W.WWW.W..."),
                row("W...RR....W..WW.WWWW"),
            ),
        ),
        Preset(
            id = "white_red_bat",
            label = "白红蝙蝠",
            description = "A white bat spread with a red center, closely inspired by the official card.",
            rowsTopFirst = listOf(
                row("WWWWWW......WWWWWW.."),
                row(".WWWWW.RRRR.WWWWW..."),
                row("..WWW.WRRRRW.WWW...."),
                row("....WWW.RRRR.WWW...."),
                row("......WW.RR.WW......"),
            ),
        ),
        Preset(
            id = "saturn",
            label = "土星",
            description = "A ringed planet sticker that reads clearly as a space-tech cue.",
            rowsTopFirst = listOf(
                row("....BB........BB.."),
                row("..BBWWWWWWWWWW..BB"),
                row("BBBBWWWWWWWWWWBBBB"),
                row("..BBWWWWWWWWWW..BB"),
                row("....BB........BB.."),
            ),
        ),
        Preset(
            id = "triple_chevron",
            label = "三重箭头",
            description = "Three bold chevrons for motion, progression, and directional demos.",
            defaultColor = Color.rgb(0x39, 0xFF, 0x6A),
            rowsTopFirst = listOf(
                row("..XX...XX...XX......"),
                row(".XXXX.XXXX.XXXX....."),
                row("XX..XXX..XXX..XX...."),
                row(".XXXX.XXXX.XXXX....."),
                row("..XX...XX...XX......"),
            ),
        ),
        Preset(
            id = "pacman",
            label = "吃豆豆",
            description = "A yellow pixel character and dots patterned after the official playful arcade card.",
            rowsTopFirst = listOf(
                row(".YYYYYY............."),
                row("YYYYYYYY..PP....BB.."),
                row("YYYYYY....PPPP..BBBB"),
                row("YYYYYYYY..PP....BB.."),
                row(".YYYYYY............."),
            ),
        ),
        Preset(
            id = "cake",
            label = "蛋糕",
            description = "A bright celebration cake with candle and layered icing.",
            rowsTopFirst = listOf(
                row(".........R.........."),
                row("........WRW........."),
                row("....WWWWWWWWWW......"),
                row("...PPYYYYYYYYPP....."),
                row("..PPPPPPPPPPPPPP...."),
            ),
        ),
        Preset(
            id = "race_car",
            label = "赛车",
            description = "A sportier race-car silhouette for speed and robotics showcases.",
            rowsTopFirst = listOf(
                row(".....RRRRRRRR......."),
                row("...RRRWWWWWWRRR....."),
                row(".RRRRRRRRRRRRRRRR..."),
                row("..HH..........HH...."),
                row("..HH..........HH...."),
            ),
        ),
        Preset(
            id = "green_hills",
            label = "绿坡",
            description = "Rounded green hills with white windmills inspired by the official landscape cards.",
            rowsTopFirst = listOf(
                row("....GG......GG......"),
                row("..GGGGG....GGGGG...."),
                row(".GGGWGGGGGGGGWGGG..."),
                row("GGGGGGGGGGGGGGGGGGG."),
                row("BBBBBBBBBBBBBBBBBBBB"),
            ),
        ),
        Preset(
            id = "magnet",
            label = "磁铁",
            description = "A horseshoe magnet sticker for attraction, pull, and smart-trigger metaphors.",
            rowsTopFirst = listOf(
                row("CC..............YY.."),
                row("CC..WWWWWWWWWW..YY.."),
                row("CC..WW......WW..YY.."),
                row("CC..WW......WW..YY.."),
                row("CC..WWWWWWWWWW..YY.."),
            ),
        ),
        Preset(
            id = "pointer",
            label = "指示箭",
            description = "A dotted pointer arrow close to the official UI's sign-like indicators.",
            defaultColor = Color.rgb(0xFF, 0x58, 0xD8),
            defaultAccentColor = Color.rgb(0xFF, 0xD4, 0x1F),
            rowsTopFirst = listOf(
                row("PP.................."),
                row("PPPPPPPP............"),
                row("PPPPPPPPPPPP....YYYY"),
                row("PPPPPPPP............"),
                row("PP.................."),
            ),
        ),
        Preset(
            id = "blue_arrow_long",
            label = "蓝箭头",
            description = "A long blue directional arrow based on the official bottom-row pointer card.",
            rowsTopFirst = listOf(
                row("CC.................."),
                row("CCCC..............CC"),
                row("CCCCCCCCCCCCCCCCCCCC"),
                row("CCCC..............CC"),
                row("CC.................."),
            ),
        ),
        Preset(
            id = "white_train",
            label = "白列车",
            description = "A long white train card with a green window, modeled after the official transport-style preset.",
            rowsTopFirst = listOf(
                row("WW.WW..............W"),
                row("WWWGWWWWWWWWWWWWWWWW"),
                row("WWWWWWWWWWWWWWWWWWWW"),
                row(".WWWWWWWWWWWWWW..WW."),
                row("..WW..........WW...."),
            ),
        ),
        Preset(
            id = "yellow_signal",
            label = "黄信号",
            description = "A yellow sign-like bar card inspired by the official bright indicator preset.",
            rowsTopFirst = listOf(
                row("YY......YY.........."),
                row("YY......YY.........."),
                row("YYYYYYYYYY..YYYYYYYY"),
                row("YY......YY.........."),
                row("YY......YY.........."),
            ),
        ),
        Preset(
            id = "triple_hearts",
            label = "三色爱心",
            description = "Three bright hearts inspired by the official candy-colored sticker row.",
            rowsTopFirst = listOf(
                row("..RY....GC....PY...."),
                row(".RYYR..GCCG..PYYP..."),
                row("RYYYYRGCCCCGPYYYYP.."),
                row(".RYYR..GCCG..PYYP..."),
                row("..RY....GC....PY...."),
            ),
        ),
        Preset(
            id = "ice_cream_trio",
            label = "三球甜筒",
            description = "Three ice-cream cones inspired by the official dessert-style preset.",
            rowsTopFirst = listOf(
                row(".WW....R.....CC....."),
                row("WWWW..RRR...CCCC...."),
                row(".NN....NN....NN....."),
                row(".....WWWW...PPPP...."),
                row(".....NNNN...NNNN...."),
            ),
        ),
        Preset(
            id = "cupcake_trio",
            label = "纸杯蛋糕",
            description = "Three colorful cupcakes inspired by the official dessert-style shelf row.",
            rowsTopFirst = listOf(
                row(".WW....R.....CC....."),
                row("NNNN..YYYY..PPPP...."),
                row(".NN....YYYY...PP...."),
                row(".....WWWW...MMMM...."),
                row(".....NNNN...MMMM...."),
            ),
        ),
        Preset(
            id = "pink_city",
            label = "粉色城市",
            description = "A soft pink skyline card inspired by the official pastel city block row.",
            rowsTopFirst = listOf(
                row("MMMM..MMMM...MMMMM.."),
                row("MMMMM.MMMMM.MMMMMM.."),
                row("MMMMMMMMMMMMMMMMMMM."),
                row("MMW..MMMMM.MMM..WMM."),
                row("MMMMMMMMMMMMMMMMMMM."),
            ),
        ),
        Preset(
            id = "rose_marquee",
            label = "玫粉招牌",
            description = "A long rosy marquee inspired by the official pink billboard-style card.",
            rowsTopFirst = listOf(
                row("MMMMMMMMMMMMMMMMMMMM"),
                row("MMMM..MMMM..MMMMMMM."),
                row("MMM..MMWWMM..MM.MMM."),
                row("MMMM..MMMM..MMMMMMM."),
                row("MMMMMMMMMMMMMMMMMMMM"),
            ),
        ),
        Preset(
            id = "magenta_arrow",
            label = "紫点箭头",
            description = "A magenta dotted arrow card based on the official pointer-style sticker.",
            rowsTopFirst = listOf(
                row("PP.................."),
                row("PPPP....PPPP........"),
                row("PPPPPPPPPPPPPP..YY.."),
                row("PPPP....PPPP........"),
                row("PP.................."),
            ),
        ),
        Preset(
            id = "pink_pointer_dots",
            label = "粉点指针",
            description = "A pink pointer with yellow end dots, closer to the official dotted arrow card.",
            rowsTopFirst = listOf(
                row("MM.................."),
                row("MMMMM..............."),
                row("MMMMMMMMMMM.....YYY."),
                row("MMMMM..............."),
                row("MM.................."),
            ),
        ),
        Preset(
            id = "candy_c",
            label = "糖果C",
            description = "A yellow C with pink and blue accents inspired by the official candy-letter card.",
            rowsTopFirst = listOf(
                row(".YYYYY.............."),
                row("YY....YY..MMM..BB..."),
                row("YY........MMMM.BBBB."),
                row("YY....YY..MMM..BB..."),
                row(".YYYYY.............."),
            ),
        ),
        Preset(
            id = "white_badge",
            label = "白徽记",
            description = "A crisp white badge with green center accents inspired by the official white symbol card.",
            rowsTopFirst = listOf(
                row("..WWWW......WWWW...."),
                row(".WWWWWW.GG.WWWWWW..."),
                row("WWWWWWWGGGGWWWWWWW.."),
                row(".WWWWWW.GG.WWWWWW..."),
                row("..WWWW......WWWW...."),
            ),
        ),
        Preset(
            id = "white_wordmark",
            label = "白字招牌",
            description = "A white sign-like wordmark inspired by the official simple white text cards.",
            rowsTopFirst = listOf(
                row("WW..............WW.."),
                row("WW..WWWW..WW..WWWW.."),
                row("WW..WWWW..WW..WW...."),
                row("WW..WWWW..WW..WWWW.."),
                row("WW..............WW.."),
            ),
        ),
        Preset(
            id = "amber_totem",
            label = "琥珀图腾",
            description = "A warm amber totem-like badge inspired by the official decorative emblem cards.",
            rowsTopFirst = listOf(
                row("....OO....OO........"),
                row("..OOOOO..OOOOO......"),
                row(".OOOOOOOOOOOOOO....."),
                row("..OOOOO..OOOOO......"),
                row("....OO....OO........"),
            ),
        ),
        Preset(
            id = "yellow_brackets",
            label = "黄括号",
            description = "A bright yellow bracket-like symbol inspired by the official minimal signal cards.",
            rowsTopFirst = listOf(
                row("..YY........YY......"),
                row(".YYYY......YYYY....."),
                row("YYYYYY....YYYYYY...."),
                row(".YYYY......YYYY....."),
                row("..YY........YY......"),
            ),
        ),
        Preset(
            id = "orange_beacon",
            label = "橙色信标",
            description = "A bright orange beacon-style symbol inspired by the official alert-like cards.",
            rowsTopFirst = listOf(
                row("....OO....OO........"),
                row("..OOOO..OOOO........"),
                row(".OOOOOOOOOOOO......."),
                row("..OOOO..OOOO........"),
                row("....OO....OO........"),
            ),
        ),
        Preset(
            id = "sunburst_badge",
            label = "日芒徽记",
            description = "A yellow-orange sunburst badge inspired by the official bright emblem cards.",
            rowsTopFirst = listOf(
                row("....OY....YO........"),
                row("..OOYYY..YYYOO......"),
                row(".OOYYYYYYYYYYOO....."),
                row("..OOYYY..YYYOO......"),
                row("....OY....YO........"),
            ),
        ),
        Preset(
            id = "blue_cloud",
            label = "蓝云",
            description = "A blue-white cloud card inspired by the official floating cloud sticker.",
            rowsTopFirst = listOf(
                row("....CCCCC..........."),
                row("..CCCCCCCC.....CC..."),
                row("CCCCCCWWCCCCCCCCCCC."),
                row("..WWWWWWWWWWCCCCCC.."),
                row("....WWWWWW....CCC..."),
            ),
        ),
        Preset(
            id = "red_bus",
            label = "红巴士",
            description = "A blocky red vehicle card inspired by the official transport-style icon set.",
            rowsTopFirst = listOf(
                row("...RRRRRRRRRRR......."),
                row("..RRRWWWWWWWWRRR....."),
                row(".RRRRRRRRRRRRRRRR...."),
                row("..HH..........HH...."),
                row("..HH..........HH...."),
            ),
        ),
        Preset(
            id = "yellow_waves",
            label = "黄波纹",
            description = "A yellow three-wave sticker modeled after the official expo-style pulse card.",
            rowsTopFirst = listOf(
                row("...OYYY....OYYY....."),
                row("..YYYYYY..YYYYYY...."),
                row(".YYYYYYYYYYYYYYYY..."),
                row("...YYYY....YYYY....."),
                row("BBBBBBBBBBBBBBBBBBBB"),
            ),
        ),
        Preset(
            id = "green_chevrons",
            label = "绿箭列",
            description = "Triple green chevrons closer to the official marching-arrow sticker.",
            rowsTopFirst = listOf(
                row("..LL....LL....LL...."),
                row(".LLLL..LLLL..LLLL..."),
                row("LL..LLLL..LLLL..LL.."),
                row(".LLLL..LLLL..LLLL..."),
                row("..LL....LL....LL...."),
            ),
        ),
        Preset(
            id = "orange_hills",
            label = "橙山丘",
            description = "Twin orange-yellow hills on a blue baseline, directly inspired by the official scenic card.",
            rowsTopFirst = listOf(
                row("...RYY......RYY....."),
                row("..RYYYY....RYYYY...."),
                row(".RYYYYYY..RYYYYYY..."),
                row("..YYYYYY....YYYYYY.."),
                row("BBBBBBBBBBBBBBBBBBBB"),
            ),
        ),
        Preset(
            id = "blue_beetle",
            label = "蓝甲虫",
            description = "Blue side clusters with a white center, inspired by the official beetle-like card.",
            rowsTopFirst = listOf(
                row("....BB......BB......"),
                row("..BBBB..WWWW..BBBB.."),
                row(".BBBBBBWWWWWWBBBBBB."),
                row("..BBBB..WWWW..BBBB.."),
                row("BBB............BBB.."),
            ),
        ),
        Preset(
            id = "dual_badges",
            label = "双色徽章",
            description = "Two mirrored white-red badges inspired by the official paired emblem cards.",
            rowsTopFirst = listOf(
                row("..WWW..RR..RR..WWW.."),
                row(".WWWWW.RRRR.RWWWWW.."),
                row("..WWW..RRRR..WWW...."),
                row(".WWWWW.RRRR.RWWWWW.."),
                row("..WWW..RR..RR..WWW.."),
            ),
        ),
        Preset(
            id = "white_capsule",
            label = "白色胶囊",
            description = "A rounded white capsule with green highlight inspired by the official white transport-sign cards.",
            rowsTopFirst = listOf(
                row("...WWWWWWWWWWWW....."),
                row(".WWWWWWGGGGWWWWWW..."),
                row("WWWWWWWWWWWWWWWWWW.."),
                row(".WWWWWWGGGGWWWWWW..."),
                row("...WWWWWWWWWWWW....."),
            ),
        ),
        Preset(
            id = "mint_chain",
            label = "薄荷链环",
            description = "A mint-green linked strip inspired by the official decorative neon chain cards.",
            rowsTopFirst = listOf(
                row("...LL..LL..LL..LL..."),
                row(".LLLLLLLLLLLLLLLL..."),
                row("LL..LL..LL..LL..LL.."),
                row(".LLLLLLLLLLLLLLLL..."),
                row("...LL..LL..LL..LL..."),
            ),
        ),
        Preset(
            id = "white_chain",
            label = "白色链带",
            description = "A white linked strip inspired by the official crisp monochrome decorative cards.",
            rowsTopFirst = listOf(
                row("...WW..WW..WW..WW..."),
                row(".WWWWWWWWWWWWWWWW..."),
                row("WW..WW..WW..WW..WW.."),
                row(".WWWWWWWWWWWWWWWW..."),
                row("...WW..WW..WW..WW..."),
            ),
        ),
        Preset(
            id = "pink_lattice",
            label = "粉色格牌",
            description = "A pink lattice-like sign inspired by the official patterned marquee cards.",
            rowsTopFirst = listOf(
                row("MMMMMMMMMMMMMMMMMMMM"),
                row("MM..MM..MM..MM..MM.."),
                row("MMMMMMMMMMMMMMMMMMMM"),
                row("MM..MM..MM..MM..MM.."),
                row("MMMMMMMMMMMMMMMMMMMM"),
            ),
        ),
        Preset(
            id = "strawberry_trio",
            label = "三颗莓果",
            description = "Three fruit stickers with leaf accents inspired by the official colorful fruit row.",
            rowsTopFirst = listOf(
                row("..LG....LG....LG...."),
                row(".MMMM..LLLL..YYYY..."),
                row("MMMMMM.LLLLL.YYYYY.."),
                row(".MMMM..LLLL..YYYY..."),
                row("..MM....LL....YY...."),
            ),
        ),
        Preset(
            id = "cyan_trail",
            label = "流星拖尾",
            description = "A cyan swoop with a warm trailing bar inspired by the official comet-like card.",
            rowsTopFirst = listOf(
                row("CC.................."),
                row("..CC................"),
                row("....CC.............."),
                row("......CC..WWOOOOOOO."),
                row("........WWOOOOOOOOO."),
            ),
        ),
        Preset(
            id = "green_crawler",
            label = "绿爬行者",
            description = "A long green creature/train silhouette inspired by the official bottom-left green card.",
            rowsTopFirst = listOf(
                row(".....GGGG.......GG.."),
                row("..G.GGGGGG.G.G.GGG.."),
                row("GGGRRGGGGGGGGGGGGGG."),
                row(".GGRRGGG.G.G..G..G.."),
                row("BBBBBBBBBBBBBBBBBBBB"),
            ),
        ),
        Preset(
            id = "yellow_marks",
            label = "黄记号",
            description = "A minimal yellow signal card inspired by the official punctuation-like sticker.",
            rowsTopFirst = listOf(
                row("........YY..YY......"),
                row("........YY..YY......"),
                row("YYYYYY..YY..YYYYYYY."),
                row("........YY.........."),
                row("....YY......YY......"),
            ),
        ),
        Preset(
            id = "green_ribbon",
            label = "绿光带",
            description = "A long green ribbon with a red stripe and blue baseline inspired by the official bottom landscape card.",
            rowsTopFirst = listOf(
                row("......GGGGGGGG......"),
                row("..GGGGGGGGGGGGGGG..."),
                row("GGRRGGGGGGGGGGGGGGG."),
                row(".GGRRGGG..GG..GG.G.."),
                row("BBBBBBBBBBBBBBBBBBBB"),
            ),
        ),
        Preset(
            id = "white_runner",
            label = "白色穿梭机",
            description = "A long white shuttle silhouette inspired by the official transport-style white card.",
            rowsTopFirst = listOf(
                row("WW..WW............WW"),
                row("WWGGWWWWWWWWWWWWWW.."),
                row("WWWWWWWWWWWWWWWWWWW."),
                row(".WWWWWWWWWWWWW..WW.."),
                row("...WW........WW....."),
            ),
        ),
        Preset(
            id = "blue_orange_dash",
            label = "蓝橙穿梭",
            description = "A blue lead-in with a long orange dash inspired by the official shuttle-like bar card.",
            rowsTopFirst = listOf(
                row("CC.................."),
                row("..CC................"),
                row("....CC.............."),
                row("......CC..WOOOOOOOO."),
                row("........WWOOOOOOOO.."),
            ),
        ),
        Preset(
            id = "violet_ribbon",
            label = "紫粉光带",
            description = "A violet ribbon with pink highlights inspired by the official long neon strip cards.",
            rowsTopFirst = listOf(
                row(".....PPPPPPPP......."),
                row("..PPPPPPPPPPPPPPP..."),
                row("PPMMMPPPPPPPPPPPPPP."),
                row(".PPMMMPPP..PP..PP.P."),
                row("....MMMMMMMMMMMM...."),
            ),
        ),
        Preset(
            id = "blue_ladder",
            label = "蓝色梯牌",
            description = "A blue ladder-like signal strip inspired by the official geometric neon cards.",
            rowsTopFirst = listOf(
                row("BB..BB..BB..BB..BB.."),
                row("BBBBBBBBBBBBBBBBBBBB"),
                row("BB..BB..BB..BB..BB.."),
                row("BBBBBBBBBBBBBBBBBBBB"),
                row("BB..BB..BB..BB..BB.."),
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

    private val screenshotPresetOrder: List<String> = listOf(
        "gold_wings",
        "bat",
        "whale",
        "white_red_bat",
        "orange_hills",
        "i_love_you",
        "blue_beetle",
        "trees",
        "green_chevrons",
        "pacman",
        "gems",
        "petal_trio",
        "pink_pointer_dots",
        "candy_c",
        "white_badge",
        "white_wordmark",
        "amber_totem",
        "yellow_brackets",
        "orange_beacon",
        "sunburst_badge",
        "strawberry_trio",
        "dog",
        "pink_city",
        "rose_marquee",
        "white_train",
        "ice_cream_trio",
        "cupcake_trio",
        "yellow_marks",
        "blue_orange_dash",
        "white_runner",
        "red_bus",
        "green_hills",
        "dual_badges",
        "white_capsule",
        "mint_chain",
        "white_chain",
        "pink_lattice",
        "green_ribbon",
        "violet_ribbon",
        "blue_ladder",
        "blue_arrow_long",
        "green_crawler",
        "cyan_trail",
    )

    private val featuredPresetOrder: List<String> = screenshotPresetOrder + listOf(
        "crown",
        "sunrise",
        "triple_hearts",
        "yellow_signal",
        "yellow_waves",
        "cake",
        "comet",
        "blue_cloud",
        "magenta_arrow",
        "ufo",
        "race_car",
        "skyline",
        "magnet",
        "pointer",
        "party",
        "saturn",
        "wave",
        "rainbow",
    )

    private val utilityPresetOrder: List<String> = listOf(
        "diamond",
        "signal",
        "eye",
        "music",
        "trophy",
        "star",
        "bolt",
        "heart",
        "smile",
        "check",
        "cross",
        "warning",
        "arrow_left",
        "arrow_right",
        "arrow_up",
        "arrow_down",
        "ai",
        "car",
        "all_on",
        "clear",
    )

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

    fun featuredGalleryPresets(): List<Preset> {
        return featuredPresetOrder.mapNotNull(presetById::get)
    }

    fun screenshotGalleryPresets(): List<Preset> {
        return screenshotPresetOrder.mapNotNull(presetById::get)
    }

    fun officialStyleGalleryPresets(): List<Preset> {
        val screenshotIds = screenshotPresetOrder.toSet()
        return featuredPresetOrder
            .filterNot(screenshotIds::contains)
            .mapNotNull(presetById::get)
    }

    fun utilityGalleryPresets(): List<Preset> {
        val ordered = utilityPresetOrder.mapNotNull(presetById::get)
        val seen = ordered.mapTo(mutableSetOf()) { it.id }
        return ordered + presets.filterNot { seen.contains(it.id) || featuredPresetOrder.contains(it.id) }
    }

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

    fun renderRows(
        rowsTopFirst: List<String>,
        colorHex: String?,
        backgroundHex: String?,
        accentHex: String?,
        defaultColor: Int = Color.rgb(0xFF, 0xC1, 0x07),
        defaultAccentColor: Int = Color.rgb(0x00, 0xD8, 0xFF),
    ): List<Int> {
        val primary = colorHex?.takeIf { it.isNotBlank() }?.let(::parseColor) ?: defaultColor
        val background = backgroundHex?.takeIf { it.isNotBlank() }?.let(::parseColor) ?: Color.BLACK
        val accent = accentHex?.takeIf { it.isNotBlank() }?.let(::parseColor) ?: defaultAccentColor
        check(rowsTopFirst.size == MATRIX_ROWS) { "Matrix rows must have $MATRIX_ROWS rows" }
        rowsTopFirst.forEach { row ->
            check(row.length == MATRIX_COLUMNS) {
                "Matrix rows must be $MATRIX_COLUMNS columns wide"
            }
        }
        val pixels = mutableListOf<Int>()
        for (rowIndex in rowsTopFirst.indices.reversed()) {
            val row = rowsTopFirst[rowIndex]
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

    fun renderPreset(
        presetId: String,
        colorHex: String?,
        backgroundHex: String?,
        accentHex: String?,
    ): List<Int> {
        val preset = presetById[presetId.trim()]
            ?: error("Unsupported matrix preset: $presetId")
        return renderRows(
            rowsTopFirst = preset.rowsTopFirst,
            colorHex = colorHex,
            backgroundHex = backgroundHex,
            accentHex = accentHex,
            defaultColor = preset.defaultColor,
            defaultAccentColor = preset.defaultAccentColor,
        )
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
        'L' -> Color.rgb(0xA8, 0xE6, 0x4D)
        'O' -> Color.rgb(0xFF, 0x9F, 0x1C)
        'M' -> Color.rgb(0xFF, 0xA7, 0xC4)
        'C' -> Color.rgb(0x00, 0xD8, 0xFF)
        'B' -> Color.rgb(0x3A, 0x86, 0xFF)
        'P' -> Color.rgb(0xA6, 0x4D, 0xFF)
        'W' -> Color.WHITE
        'K' -> Color.BLACK
        'N' -> Color.rgb(0xB8, 0x7A, 0x3F)
        'T' -> Color.rgb(0x8C, 0x63, 0x22)
        'H' -> Color.rgb(0xB0, 0xB7, 0xC3)
        else -> error("Unsupported matrix token: $token")
    }

    private fun parseColor(value: String): Int {
        val hex = value.trim().removePrefix("#")
        check(hex.length == 6) { "Color must be #RRGGBB: $value" }
        return hex.toInt(16) and 0xFFFFFF
    }

    private fun filledRows(token: Char): List<String> =
        List(MATRIX_ROWS) { token.toString().repeat(MATRIX_COLUMNS) }

    private fun row(pattern: String, fill: Char = '.'): String =
        pattern.padEnd(MATRIX_COLUMNS, fill).take(MATRIX_COLUMNS)
}
