package demo.smartdesk.provider

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.widget.TextView

fun label(text: String, size: Float = 14f, color: Int = Color.rgb(212, 226, 245)): TextView =
    TextView(AppContext.require()).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        includeFontPadding = false
    }

fun pill(text: String): TextView =
    label(text, 14f, Color.rgb(31, 42, 58)).apply {
        gravity = Gravity.CENTER
        setPadding(24, 14, 24, 14)
        background = rounded(Color.rgb(245, 247, 250), Color.rgb(214, 221, 231), 16f)
    }

fun View.panelBackground() {
    background = rounded(Color.WHITE, Color.rgb(222, 228, 236), 24f)
}

fun rounded(fill: Int, stroke: Int, radius: Float): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radius
        setColor(fill)
        setStroke(2, stroke)
    }
