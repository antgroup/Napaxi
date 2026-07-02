package demo.smarthome.provider

import android.app.Activity
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.TextView

/**
 * Runs [work] off the main thread and delivers the result back on the UI thread.
 * Replaces the repeated `Thread { … runOnUiThread { … } }` boilerplate the demo
 * used for every blocking SDK / provider call.
 */
fun <T> Activity.runOffMain(work: () -> T, onResult: (Result<T>) -> Unit) {
    Thread {
        val result = runCatching(work)
        runOnUiThread { onResult(result) }
    }.start()
}

object Palette {
    val background = Color.rgb(0xF5, 0xF5, 0xF5)
    val card = Color.WHITE
    val cardStroke = Color.rgb(0xEC, 0xEC, 0xEC)
    val title = Color.rgb(0x16, 0x18, 0x1D)
    val subtitle = Color.rgb(0x5F, 0x67, 0x70)
    val sectionTitle = Color.rgb(0x12, 0x14, 0x18)
    val divider = Color.rgb(0xE5, 0xE5, 0xE5)

    val iconLamp = Color.rgb(0xFF, 0xC1, 0x07)
    val iconLampBg = Color.rgb(0xFF, 0xE9, 0xC4)
    val iconBulb = Color.rgb(0xF5, 0xC0, 0x29)
    val iconBulbBg = Color.rgb(0xFF, 0xF1, 0xC9)
    val iconBlinds = Color.rgb(0x7C, 0x52, 0xD1)
    val iconBlindsBg = Color.rgb(0xE6, 0xDC, 0xFA)
    val iconAudio = Color.rgb(0x1E, 0x9C, 0xE2)
    val iconAudioBg = Color.rgb(0xCF, 0xE9, 0xFA)
    val iconAppliance = Color.rgb(0x6B, 0x70, 0x7A)
    val iconApplianceBg = Color.rgb(0xE3, 0xE3, 0xE5)
    val iconEv = Color.rgb(0x6B, 0x70, 0x7A)
    val iconEvBg = Color.rgb(0xE3, 0xE3, 0xE5)
    val iconBolt = Color.rgb(0x1A, 0xB7, 0x59)
    val iconBoltBg = Color.rgb(0xCD, 0xEE, 0xD9)
    val iconWave = Color.rgb(0xF1, 0x6A, 0x2C)
    val iconWaveBg = Color.rgb(0xFD, 0xDA, 0xC4)
    val iconHomePower = Color.rgb(0xF5, 0x8C, 0x1A)
    val iconHomePowerBg = Color.rgb(0xFD, 0xDC, 0xBE)
    val sliderTrack = Color.rgb(0xFF, 0xE9, 0xC4)
    val sliderFill = Color.rgb(0xFF, 0xC1, 0x07)
    val pillBg = Color.WHITE
    val pillStroke = Color.rgb(0xE5, 0xE5, 0xE5)
    val tempRed = Color.rgb(0xE0, 0x40, 0x40)
    val humidityBlue = Color.rgb(0x29, 0x8E, 0xE0)
}

fun label(text: String, size: Float = 14f, color: Int = Palette.title): TextView =
    TextView(AppContext.require()).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        includeFontPadding = false
    }

fun pill(text: String): TextView =
    label(text, 14f, Palette.title).apply {
        gravity = Gravity.CENTER
        setPadding(24, 14, 24, 14)
        background = rounded(Palette.pillBg, Palette.pillStroke, 18f)
    }

fun View.cardBackground() {
    background = rounded(Palette.card, Palette.cardStroke, 18f)
}

fun rounded(fill: Int, stroke: Int, radius: Float): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radius
        setColor(fill)
        if (stroke != Color.TRANSPARENT) setStroke(2, stroke)
    }

fun circle(fill: Int): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(fill)
    }
