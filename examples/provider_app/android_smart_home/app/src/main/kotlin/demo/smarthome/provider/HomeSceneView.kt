package demo.smarthome.provider

import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.util.AttributeSet
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.SeekBar
import android.widget.TextView

class HomeSceneView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    private val rootColumn: LinearLayout
    private val outdoorRow: LinearLayout
    private val sectionsColumn: LinearLayout

    var onDeviceTap: ((roomId: String, deviceId: String) -> Unit)? = null
    var onLightBrightnessChange: ((roomId: String, deviceId: String, brightness: Int) -> Unit)? = null
    var onMenuTap: (() -> Unit)? = null

    var state: VirtualHomeState = VirtualHomeState()
        set(value) {
            field = value
            render()
        }

    init {
        setBackgroundColor(Palette.background)

        val scroll = ScrollView(context).apply {
            layoutParams = LayoutParams(
                LayoutParams.MATCH_PARENT,
                LayoutParams.MATCH_PARENT,
            )
            isFillViewport = true
            overScrollMode = OVER_SCROLL_NEVER
        }
        rootColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(8), dp(16), dp(112))
        }
        scroll.addView(rootColumn)
        addView(scroll)

        rootColumn.addView(buildAppBar())
        outdoorRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(4), dp(8), dp(4), dp(16))
        }
        rootColumn.addView(outdoorRow)

        sectionsColumn = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
        }
        rootColumn.addView(sectionsColumn)

        render()
    }

    private fun render() {
        outdoorRow.removeAllViews()
        outdoorRow.addView(outdoorPill("🌡", "%.1f".format(state.outdoor.tempC), Palette.tempRed))
        outdoorRow.addView(outdoorPill("💧", "%.1f".format(state.outdoor.humidity), Palette.humidityBlue))
        outdoorRow.addView(outdoorPill("🚗", if (state.outdoor.awayMode) "离家" else "在家", Palette.subtitle))

        sectionsColumn.removeAllViews()
        state.rooms.forEach { sectionsColumn.addView(buildRoomSection(it)) }
        sectionsColumn.addView(buildEnergySection())
    }

    private fun buildAppBar(): View {
        val bar = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), dp(12), dp(4), dp(12))
        }
        bar.addView(iconText("≡", 26f, Palette.title).apply {
            setPadding(dp(4), 0, dp(8), 0)
        })
        val dot = View(context).apply {
            background = circle(Color.rgb(0xF7, 0xA8, 0x09))
            layoutParams = LinearLayout.LayoutParams(dp(8), dp(8)).apply {
                rightMargin = dp(8)
            }
        }
        bar.addView(dot)
        bar.addView(label("家居助手", 22f, Palette.title).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        })
        bar.addView(iconText("⋮", 24f, Palette.subtitle).apply {
            setPadding(dp(12), dp(8), dp(12), dp(8))
            isClickable = true
            isFocusable = true
            setOnClickListener { onMenuTap?.invoke() }
        })
        return bar
    }

    private fun outdoorPill(emoji: String, value: String, accent: Int): View {
        val pill = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            background = rounded(Palette.card, Palette.cardStroke, dp(20).toFloat())
            setPadding(dp(12), dp(8), dp(14), dp(8))
            val lp = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            lp.rightMargin = dp(8)
            layoutParams = lp
        }
        pill.addView(label(emoji, 14f, accent).apply {
            setPadding(0, 0, dp(6), 0)
        })
        pill.addView(label(value, 14f, Palette.title).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        })
        return pill
    }

    private fun buildRoomSection(room: HomeRoom): View {
        val section = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(10), 0, dp(8))
        }

        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), dp(4), dp(4), dp(12))
        }
        header.addView(iconText(roomEmoji(room.id), 18f, Palette.sectionTitle).apply {
            setPadding(0, 0, dp(8), 0)
        })
        header.addView(label(room.displayName, 18f, Palette.sectionTitle).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        })
        header.addView(label("🌡", 13f, Palette.tempRed).apply {
            setPadding(0, 0, dp(4), 0)
        })
        header.addView(label("%.1f".format(room.tempC), 13f, Palette.title).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
            setPadding(0, 0, dp(10), 0)
        })
        header.addView(label("💧", 13f, Palette.humidityBlue).apply {
            setPadding(0, 0, dp(4), 0)
        })
        header.addView(label("${room.humidity}", 13f, Palette.title).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        })
        section.addView(header)

        section.addView(buildGrid(room.devices.map { device -> deviceCard(room, device) }))
        return section
    }

    private fun buildEnergySection(): View {
        val section = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, dp(14), 0, dp(8))
        }
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(4), dp(4), dp(4), dp(12))
        }
        header.addView(iconText("⚡", 18f, Palette.sectionTitle).apply {
            setPadding(0, 0, dp(8), 0)
        })
        header.addView(label("能源", 18f, Palette.sectionTitle).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        })
        section.addView(header)

        val cards = listOf(
            simpleCard(
                "🚗", Palette.iconEvBg, Palette.iconEv, "电动车",
                if (state.energy.evPlugged) "已插入" else "已拔出",
            ),
            simpleCard(
                "⚡", Palette.iconBoltBg, Palette.iconBolt, "上次充电",
                "${state.energy.lastChargeKwh} kWh",
            ),
            simpleCard(
                "⚡", Palette.iconHomePowerBg, Palette.iconHomePower, "家庭功率",
                "${state.energy.homePowerWatts} W",
            ),
            simpleCard(
                "〰", Palette.iconWaveBg, Palette.iconWave, "电压",
                "${state.energy.voltageV} V",
            ),
        )
        section.addView(buildGrid(cards))
        return section
    }

    private fun deviceCard(room: HomeRoom, device: HomeDevice): View {
        val (emoji, iconColor, iconBg) = iconForDevice(device)
        val interactive = device.kind != DeviceKind.SENSOR
        val card = simpleCard(
            emoji = emoji,
            iconBg = iconBg,
            iconColor = iconColor,
            title = device.name,
            subtitle = device.summary(),
        )
        if (interactive) {
            card.isClickable = true
            card.isFocusable = true
            card.setOnClickListener { onDeviceTap?.invoke(room.id, device.id) }
        }
        if (device.kind == DeviceKind.LIGHT && device.on) {
            card.addView(buildBrightnessSlider(room.id, device))
        }
        return card
    }

    private fun buildBrightnessSlider(roomId: String, device: HomeDevice): View {
        val seek = SeekBar(context).apply {
            max = 100
            progress = device.brightness.coerceIn(0, 100)
            val lp = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            )
            lp.topMargin = dp(6)
            layoutParams = lp
            progressTintList = android.content.res.ColorStateList.valueOf(Palette.sliderFill)
            progressBackgroundTintList = android.content.res.ColorStateList.valueOf(Palette.sliderTrack)
            thumbTintList = android.content.res.ColorStateList.valueOf(Palette.sliderFill)
            splitTrack = false
            setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
                override fun onProgressChanged(bar: SeekBar?, p: Int, fromUser: Boolean) {}
                override fun onStartTrackingTouch(bar: SeekBar?) {}
                override fun onStopTrackingTouch(bar: SeekBar?) {
                    onLightBrightnessChange?.invoke(roomId, device.id, bar?.progress ?: 0)
                }
            })
        }
        return seek
    }

    private fun simpleCard(
        emoji: String,
        iconBg: Int,
        iconColor: Int,
        title: String,
        subtitle: String,
    ): LinearLayout {
        val card = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(Palette.card, Palette.cardStroke, dp(14).toFloat())
            setPadding(dp(12), dp(12), dp(12), dp(12))
        }
        val row = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val iconContainer = FrameLayout(context).apply {
            background = circle(iconBg)
            layoutParams = LinearLayout.LayoutParams(dp(40), dp(40)).apply {
                rightMargin = dp(12)
            }
        }
        val iconLabel = label(emoji, 16f, iconColor).apply {
            gravity = Gravity.CENTER
            layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
        }
        iconContainer.addView(iconLabel)
        row.addView(iconContainer)

        val textCol = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
        }
        textCol.addView(label(title, 14f, Palette.title).apply {
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        })
        textCol.addView(label(subtitle, 12f, Palette.subtitle).apply {
            setPadding(0, dp(2), 0, 0)
        })
        row.addView(textCol)
        card.addView(row)

        return card
    }

    private fun buildGrid(cards: List<View>): View {
        val column = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
        cards.chunked(2).forEach { pair ->
            val row = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                setPadding(0, 0, 0, dp(10))
            }
            pair.forEachIndexed { index, view ->
                val lp = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                    if (index == 0) rightMargin = dp(10)
                }
                row.addView(view, lp)
            }
            if (pair.size == 1) {
                row.addView(View(context), LinearLayout.LayoutParams(0, 0, 1f))
            }
            column.addView(row)
        }
        return column
    }

    private fun iconForDevice(device: HomeDevice): Triple<String, Int, Int> = when {
        device.kind == DeviceKind.LIGHT && device.id.contains("floor") ->
            Triple("🛋", Palette.iconLamp, Palette.iconLampBg)
        device.kind == DeviceKind.LIGHT && device.id.contains("spot") ->
            Triple("◔", Palette.iconLamp, Palette.iconLampBg)
        device.kind == DeviceKind.LIGHT ->
            Triple("💡", Palette.iconBulb, Palette.iconBulbBg)
        device.kind == DeviceKind.COVER ->
            Triple("⛩", Palette.iconBlinds, Palette.iconBlindsBg)
        device.kind == DeviceKind.MEDIA ->
            Triple("🎵", Palette.iconAudio, Palette.iconAudioBg)
        device.kind == DeviceKind.CLIMATE ->
            Triple("❄", Palette.iconAudio, Palette.iconAudioBg)
        device.kind == DeviceKind.APPLIANCE ->
            Triple("◔", Palette.iconAppliance, Palette.iconApplianceBg)
        else -> Triple("📦", Palette.iconAppliance, Palette.iconApplianceBg)
    }

    private fun roomEmoji(roomId: String): String = when (roomId) {
        "living_room" -> "🛋"
        "kitchen" -> "🧊"
        else -> "🏠"
    }

    private fun iconText(text: String, size: Float, color: Int): TextView =
        label(text, size, color).apply {
            paintFlags = paintFlags or Paint.ANTI_ALIAS_FLAG
        }

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()
}
