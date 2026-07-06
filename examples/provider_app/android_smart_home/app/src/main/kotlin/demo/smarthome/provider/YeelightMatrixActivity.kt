package demo.smarthome.provider

import android.app.Activity
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView

class YeelightMatrixActivity : Activity() {
    private lateinit var matrixView: PixelMatrixView
    private lateinit var statusText: TextView
    private var selectedColor: Int = Color.rgb(0xFF, 0xC1, 0x07)
    private var pixels: MutableList<Int> = MutableList(MATRIX_PIXEL_COUNT) { Color.BLACK }
    private val swatchViews = mutableListOf<ColorSwatchView>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        AppContext.context = applicationContext
        setContentView(buildUi())
    }

    private fun buildUi(): View {
        val root = FrameLayout(this).apply {
            setBackgroundColor(Palette.background)
        }
        val scroll = ScrollView(this)
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(16), dp(18), dp(16), dp(28))
        }
        scroll.addView(content)
        root.addView(scroll)

        content.addView(header())
        statusText = label("Yeelight · ${YeelightLanClient.summary(this)}", 13f, Palette.subtitle).apply {
            setPadding(0, dp(8), 0, 0)
        }
        content.addView(statusText)

        matrixView = PixelMatrixView(this).apply {
            colors = pixels
            activeColor = selectedColor
            onPixelTap = { index ->
                pixels[index] = selectedColor
                colors = pixels
            }
        }
        val matrixScroller = HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(matrixView, ViewGroup.LayoutParams(dp(680), dp(200)))
        }
        content.addView(matrixScroller, LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            dp(208),
        ).apply { topMargin = dp(18) })

        content.addView(sectionTitle("颜色"), LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(18) })
        content.addView(colorPalette())

        content.addView(sectionTitle("预设"), LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(18) })
        content.addView(presetRow())

        content.addView(actionRow(), LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            ViewGroup.LayoutParams.WRAP_CONTENT,
        ).apply { topMargin = dp(20) })
        return root
    }

    private fun header(): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            addView(label("Yeelight 点阵", 22f, Palette.title).apply {
                typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f)
            })
            addView(pill("关闭").apply {
                setOnClickListener { finish() }
            })
        }

    private fun sectionTitle(text: String): TextView =
        label(text, 15f, Palette.sectionTitle).apply {
            typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
        }

    private fun colorPalette(): HorizontalScrollView {
        swatchViews.clear()
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(8), dp(2), 0)
        }
        paletteColors().forEach { color ->
            row.addView(ColorSwatchView(this).apply {
                swatchColor = color
                isSelectedColor = color == selectedColor
                setOnClickListener {
                    selectedColor = color
                    matrixView.activeColor = selectedColor
                    updateSwatchSelection()
                }
                layoutParams = LinearLayout.LayoutParams(dp(42), dp(42)).apply {
                    rightMargin = dp(10)
                }
                swatchViews += this
            })
        }
        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        }
    }

    private fun presetRow(): HorizontalScrollView {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, dp(8), dp(2), 0)
        }
        MatrixPresetLibrary.presets.forEach { preset ->
            row.addView(actionPill(preset.label) {
                pixels = MatrixPresetLibrary.renderPreset(
                    presetId = preset.id,
                    colorHex = toHexColor(selectedColor),
                    backgroundHex = "#000000",
                    accentHex = toHexColor(Color.rgb(0x00, 0xD8, 0xFF)),
                ).toMutableList()
                matrixView.colors = pixels
                statusText.text = "已载入预设：${preset.label}"
            })
        }
        return HorizontalScrollView(this).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        }
    }

    private fun actionRow(): LinearLayout =
        LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            addView(pill("发送").apply {
                setOnClickListener { sendMatrix() }
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                    rightMargin = dp(6)
                }
            })
            addView(pill("关屏").apply {
                setOnClickListener {
                    pixels = MutableList(MATRIX_PIXEL_COUNT) { Color.BLACK }
                    matrixView.colors = pixels
                    sendMatrix()
                }
                layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
                    leftMargin = dp(6)
                }
            })
        }

    private fun actionPill(text: String, block: () -> Unit): TextView =
        pill(text).apply {
            setOnClickListener { block() }
            layoutParams = LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
            ).apply { rightMargin = dp(8) }
        }

    private fun sendMatrix() {
        statusText.text = "正在发送 20 x 5 图案..."
        Thread {
            runCatching { YeelightLanClient.drawMatrix100(this, pixels.map { it and 0xFFFFFF }) }
                .fold(
                    onSuccess = { result ->
                        VirtualHomeStore.recordAgentNote(
                            this,
                            "Yeelight Cube",
                            "点阵页面已发送 20 x 5 图案。",
                        )
                        runOnUiThread {
                            statusText.text = "已发送：${result.optString("layout", "20x5")}"
                            matrixView.colors = pixels
                        }
                    },
                    onFailure = { error ->
                        runOnUiThread {
                            statusText.text = "发送失败：${error.message ?: "未知错误"}"
                        }
                    },
                )
        }.start()
    }

    private fun updateSwatchSelection() {
        swatchViews.forEach { swatch ->
            swatch.isSelectedColor = swatch.swatchColor == selectedColor
        }
    }

    private fun paletteColors(): List<Int> =
        listOf(
            Color.rgb(0xFF, 0xC1, 0x07),
            Color.rgb(0xFF, 0x00, 0x00),
            Color.rgb(0x00, 0xFF, 0x00),
            Color.rgb(0x00, 0x00, 0xFF),
            Color.rgb(0x00, 0xD8, 0xFF),
            Color.rgb(0xB0, 0x4C, 0xFF),
            Color.rgb(0xFF, 0x4D, 0xA6),
            Color.WHITE,
            Color.BLACK,
        )

    private fun dp(value: Int): Int =
        TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            value.toFloat(),
            resources.displayMetrics,
        ).toInt()

    private fun toHexColor(color: Int): String =
        String.format("#%06X", 0xFFFFFF and color)
}

private class PixelMatrixView(context: android.content.Context) : View(context) {
    var colors: List<Int> = List(MATRIX_PIXEL_COUNT) { Color.BLACK }
        set(value) {
            field = value.take(MATRIX_PIXEL_COUNT).let { clipped ->
                clipped + List(MATRIX_PIXEL_COUNT - clipped.size) { Color.BLACK }
            }
            invalidate()
        }
    var activeColor: Int = Color.WHITE
        set(value) {
            field = value
            invalidate()
        }
    var onPixelTap: ((Int) -> Unit)? = null

    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0xE5, 0xE5, 0xE5)
        style = Paint.Style.STROKE
        strokeWidth = 2f
    }
    private val activePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(0x16, 0x18, 0x1D)
        style = Paint.Style.STROKE
        strokeWidth = 4f
    }
    private val rect = RectF()

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val gap = 6f
        val cellByWidth = ((width - paddingLeft - paddingRight) - gap * (MATRIX_COLUMNS - 1)) / MATRIX_COLUMNS
        val cellByHeight = ((height - paddingTop - paddingBottom) - gap * (MATRIX_ROWS - 1)) / MATRIX_ROWS
        val cell = minOf(cellByWidth, cellByHeight)
        val totalWidth = cell * MATRIX_COLUMNS + gap * (MATRIX_COLUMNS - 1)
        val totalHeight = cell * MATRIX_ROWS + gap * (MATRIX_ROWS - 1)
        val startX = paddingLeft + ((width - paddingLeft - paddingRight - totalWidth) / 2f).coerceAtLeast(0f)
        val startY = paddingTop + ((height - paddingTop - paddingBottom - totalHeight) / 2f).coerceAtLeast(0f)
        for (index in 0 until MATRIX_PIXEL_COUNT) {
            val (row, col) = physicalPosition(index)
            val left = startX + col * (cell + gap)
            val top = startY + row * (cell + gap)
            rect.set(left, top, left + cell, top + cell)
            fillPaint.color = colors.getOrElse(index) { Color.BLACK }
            fillPaint.style = Paint.Style.FILL
            canvas.drawRoundRect(rect, 14f, 14f, fillPaint)
            canvas.drawRoundRect(rect, 14f, 14f, strokePaint)
        }
        rect.set(0f, 0f, 0f, 0f)
        fillPaint.color = activeColor
        fillPaint.style = Paint.Style.FILL
        canvas.drawCircle(width - 24f, 24f, 12f, fillPaint)
        canvas.drawCircle(width - 24f, 24f, 13f, activePaint)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.action != MotionEvent.ACTION_DOWN) return true
        val index = pixelAt(event.x, event.y)
        if (index >= 0) {
            onPixelTap?.invoke(index)
        }
        return true
    }

    private fun pixelAt(x: Float, y: Float): Int {
        val gap = 6f
        val cellByWidth = ((width - paddingLeft - paddingRight) - gap * (MATRIX_COLUMNS - 1)) / MATRIX_COLUMNS
        val cellByHeight = ((height - paddingTop - paddingBottom) - gap * (MATRIX_ROWS - 1)) / MATRIX_ROWS
        val cell = minOf(cellByWidth, cellByHeight)
        val totalWidth = cell * MATRIX_COLUMNS + gap * (MATRIX_COLUMNS - 1)
        val totalHeight = cell * MATRIX_ROWS + gap * (MATRIX_ROWS - 1)
        val startX = paddingLeft + ((width - paddingLeft - paddingRight - totalWidth) / 2f).coerceAtLeast(0f)
        val startY = paddingTop + ((height - paddingTop - paddingBottom - totalHeight) / 2f).coerceAtLeast(0f)
        for (index in 0 until MATRIX_PIXEL_COUNT) {
            val (row, col) = physicalPosition(index)
            val left = startX + col * (cell + gap)
            val top = startY + row * (cell + gap)
            if (x >= left && x <= left + cell && y >= top && y <= top + cell) return index
        }
        return -1
    }

    private fun physicalPosition(index: Int): Pair<Int, Int> =
        MATRIX_ROWS - 1 - (index / MATRIX_COLUMNS) to (index % MATRIX_COLUMNS)
}

private const val MATRIX_COLUMNS = 20
private const val MATRIX_ROWS = 5
private const val MATRIX_PIXEL_COUNT = MATRIX_COLUMNS * MATRIX_ROWS

private class ColorSwatchView(context: android.content.Context) : View(context) {
    var swatchColor: Int = Color.WHITE
        set(value) {
            field = value
            invalidate()
        }
    var isSelectedColor: Boolean = false
        set(value) {
            field = value
            invalidate()
        }
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        rect.set(3f, 3f, width - 3f, height - 3f)
        paint.style = Paint.Style.FILL
        paint.color = swatchColor
        canvas.drawRoundRect(rect, 12f, 12f, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = if (isSelectedColor) 5f else 2f
        paint.color = if (isSelectedColor) Palette.title else Palette.pillStroke
        canvas.drawRoundRect(rect, 12f, 12f, paint)
    }
}
