package demo.wallet.provider

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.TextView

fun Context.label(
    text: String,
    size: Float = 14f,
    color: Int = Color.rgb(42, 52, 68),
    bold: Boolean = false,
): TextView =
    TextView(this).apply {
        this.text = text
        textSize = size
        setTextColor(color)
        includeFontPadding = false
        if (bold) typeface = Typeface.DEFAULT_BOLD
    }

fun Context.buttonLabel(text: String): TextView =
    label(text, 14f, Color.rgb(31, 42, 58), bold = true).apply {
        gravity = Gravity.CENTER
        setPadding(22, 14, 22, 14)
        background = rounded(Color.WHITE, Color.rgb(216, 224, 235), 16f)
    }

fun View.cardBackground() {
    background = rounded(Color.WHITE, Color.rgb(226, 232, 240), 24f)
    elevation = 2f
}

fun LinearLayout.addGap(height: Int) {
    addView(View(context), LinearLayout.LayoutParams(1, height))
}

fun rounded(fill: Int, stroke: Int, radius: Float): GradientDrawable =
    GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = radius
        setColor(fill)
        setStroke(2, stroke)
    }

fun linearParams(
    width: Int = ViewGroup.LayoutParams.MATCH_PARENT,
    height: Int = ViewGroup.LayoutParams.WRAP_CONTENT,
): LinearLayout.LayoutParams = LinearLayout.LayoutParams(width, height)
