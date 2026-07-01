package demo.smartdesk.provider

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View
import android.view.animation.DecelerateInterpolator
import kotlin.math.max
import kotlin.math.min

class DeskSceneView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(33, 43, 58)
        textSize = 28f
    }
    private val rect = RectF()
    private var pulse = 0f

    var state: VirtualDeskState = VirtualDeskState()
        set(value) {
            field = value
            startPulse()
            invalidate()
        }

    private val pulseAnimator = ValueAnimator.ofFloat(0f, 1f).apply {
        duration = 520L
        interpolator = DecelerateInterpolator()
        addUpdateListener {
            pulse = it.animatedValue as Float
            invalidate()
        }
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        drawCard(canvas, w, h)
        drawDesk(canvas, w, h)
        drawLamp(canvas, w, h)
        drawPlug(canvas, w, h)
        drawStatus(canvas, w, h)
    }

    private fun drawCard(canvas: Canvas, w: Float, h: Float) {
        paint.color = Color.rgb(245, 247, 250)
        canvas.drawRect(0f, 0f, w, h, paint)

        val pad = min(w, h) * 0.08f
        rect.set(pad, pad, w - pad, h - pad)
        paint.color = Color.WHITE
        canvas.drawRoundRect(rect, 28f, 28f, paint)

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f
        paint.color = Color.rgb(224, 230, 238)
        canvas.drawRoundRect(rect, 28f, 28f, paint)
        paint.style = Paint.Style.FILL
    }

    private fun drawDesk(canvas: Canvas, w: Float, h: Float) {
        val left = w * 0.17f
        val right = w * 0.83f
        val top = h * 0.52f
        val bottom = h * 0.63f

        rect.set(left, top, right, bottom)
        paint.shader = LinearGradient(
            left,
            top,
            right,
            bottom,
            Color.rgb(58, 73, 96),
            Color.rgb(36, 48, 66),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRoundRect(rect, 18f, 18f, paint)
        paint.shader = null

        val stripAlpha = if (state.lightOn) (80 + state.brightness).coerceAtMost(180) else 28
        rect.set(left + 22f, top + 16f, right - 22f, top + 24f)
        paint.color = withAlpha(state.color, stripAlpha)
        canvas.drawRoundRect(rect, 8f, 8f, paint)

        paint.strokeWidth = 12f
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = Color.rgb(74, 88, 110)
        canvas.drawLine(left + 44f, bottom, left + 20f, h * 0.78f, paint)
        canvas.drawLine(right - 44f, bottom, right - 20f, h * 0.78f, paint)
        paint.strokeCap = Paint.Cap.BUTT
    }

    private fun drawLamp(canvas: Canvas, w: Float, h: Float) {
        val baseX = w * 0.32f
        val baseY = h * 0.51f
        paint.strokeWidth = 10f
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = Color.rgb(82, 96, 118)
        canvas.drawLine(baseX, baseY, baseX + w * 0.07f, h * 0.34f, paint)
        canvas.drawLine(baseX + w * 0.07f, h * 0.34f, baseX + w * 0.2f, h * 0.34f, paint)

        rect.set(baseX + w * 0.17f, h * 0.29f, baseX + w * 0.29f, h * 0.39f)
        paint.color = Color.rgb(69, 83, 105)
        canvas.drawRoundRect(rect, 14f, 14f, paint)

        if (state.lightOn) {
            paint.color = withAlpha(state.color, (64 + state.brightness).coerceAtMost(150))
            val radius = max(w * 0.09f, 48f) + pulse * 12f
            canvas.drawCircle(rect.centerX(), rect.bottom + 28f, radius, paint)
        }
        paint.strokeCap = Paint.Cap.BUTT
    }

    private fun drawPlug(canvas: Canvas, w: Float, h: Float) {
        rect.set(w * 0.62f, h * 0.43f, w * 0.78f, h * 0.51f)
        paint.color = Color.rgb(236, 240, 245)
        canvas.drawRoundRect(rect, 16f, 16f, paint)
        paint.color = if (state.plugOn) Color.rgb(35, 163, 110) else Color.rgb(145, 156, 171)
        canvas.drawCircle(rect.left + 26f, rect.centerY(), 9f, paint)

        textPaint.textSize = 18f
        textPaint.color = Color.rgb(89, 101, 118)
        canvas.drawText(if (state.plugOn) "ON" else "OFF", rect.left + 44f, rect.centerY() + 7f, textPaint)
    }

    private fun drawStatus(canvas: Canvas, w: Float, h: Float) {
        val left = w * 0.17f
        val top = h * 0.15f
        textPaint.color = Color.rgb(29, 39, 54)
        textPaint.textSize = 30f
        canvas.drawText("Smart Desk", left, top, textPaint)

        textPaint.color = Color.rgb(105, 118, 136)
        textPaint.textSize = 20f
        canvas.drawText("Scene ${state.scene}  ·  ${state.brightness}%  ·  ${state.colorHex}", left, top + 36f, textPaint)

        val barWidth = w * 0.48f
        val barTop = top + 58f
        paint.color = Color.rgb(231, 235, 241)
        canvas.drawRoundRect(RectF(left, barTop, left + barWidth, barTop + 10f), 6f, 6f, paint)
        paint.color = if (state.lightOn) state.color else Color.rgb(158, 168, 181)
        canvas.drawRoundRect(
            RectF(left, barTop, left + barWidth * state.brightness / 100f, barTop + 10f),
            6f,
            6f,
            paint,
        )
    }

    private fun startPulse() {
        pulseAnimator.cancel()
        pulseAnimator.start()
    }

    private fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha.coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))
}
