package com.otm.pack.gs

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View

/**
 * Gráfico de linha ao vivo (FPS/CPU/GPU/RAM). Guarda uma janela de amostras e
 * desenha uma curva suavizada com preenchimento em gradiente.
 *
 * Porte do `PerfGraphView` de referência, reescrito: sem `BlurMaskFilter`
 * (caro por quadro) e com o número de amostras fixo por janela de tempo.
 */
class GsGraphView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : View(context, attrs) {

    private val samples = ArrayDeque<Float>()
    private val maxSamples = 90

    /** Cor da linha (o preenchimento sai dela, mais transparente). */
    var lineColor: Int = GsTheme.accent
        set(v) { field = v; rebuildShader(); invalidate() }

    /** Valor máximo do eixo Y. 0 = autoescala pela maior amostra. */
    var maxValue: Float = 0f
        set(v) { field = v; invalidate() }

    private val line = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val path = Path()
    private val fillPath = Path()
    private val rect = RectF()

    init {
        line.strokeWidth = GsTheme.dp(context, 2f)
        rebuildShader()
    }

    private fun rebuildShader() {
        fillPaint.shader = null
        fillPaint.color = GsTheme.withAlpha(lineColor, 0x33)
    }

    /** Adiciona uma amostra e pede redesenho. */
    fun push(value: Float) {
        samples.addLast(value)
        while (samples.size > maxSamples) samples.removeFirst()
        invalidate()
    }

    fun clear() {
        samples.clear()
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f || samples.size < 2) return

        val top = maxValue.takeIf { it > 0f } ?: (samples.maxOrNull() ?: 1f).coerceAtLeast(1f)
        val bottom = 0f
        val stepX = w / (maxSamples - 1)

        // a amostra mais recente encosta na borda direita
        val offset = (maxSamples - samples.size) * stepX

        fun yFor(v: Float): Float = h - ((v - bottom) / (top - bottom)).coerceIn(0f, 1f) * h

        path.reset()
        fillPath.reset()
        var first = true
        samples.forEachIndexed { i, v ->
            val x = offset + i * stepX
            val y = yFor(v)
            if (first) {
                path.moveTo(x, y)
                fillPath.moveTo(x, h)
                fillPath.lineTo(x, y)
                first = false
            } else {
                path.lineTo(x, y)
                fillPath.lineTo(x, y)
            }
        }
        fillPath.lineTo(offset + (samples.size - 1) * stepX, h)
        fillPath.close()

        fillPaint.color = GsTheme.withAlpha(lineColor, 0x33)
        canvas.drawPath(fillPath, fillPaint)

        line.color = lineColor
        canvas.drawPath(path, line)

        // marcador na ponta (última amostra)
        val lastY = yFor(samples.last())
        val lastX = offset + (samples.size - 1) * stepX
        val dot = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = lineColor }
        canvas.drawCircle(lastX, lastY, GsTheme.dp(context, 3f), dot)
    }
}

/**
 * Faixa de temperatura da sessão: barra verde→amarelo→vermelho com o trecho
 * percorrido e um marcador na temperatura atual.
 *
 * Porte do `TempRangeView`. A escala é 30..50 °C (abaixo de 30 é verde, acima
 * de 50 é vermelho), igual à referência.
 */
class GsTempRangeView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : View(context, attrs) {

    private val band = Paint(Paint.ANTI_ALIAS_FLAG)
    private val track = Paint(Paint.ANTI_ALIAS_FLAG)
    private val marker = Paint(Paint.ANTI_ALIAS_FLAG)
    private val markerGlow = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val path = Path()

    private var minT: Float = Float.NaN
    private var maxT: Float = Float.NaN
    private var curT: Float = Float.NaN

    private var anim: ValueAnimator? = null

    init {
        track.style = Paint.Style.STROKE
        track.strokeWidth = GsTheme.dp(context, 1f)
        track.color = GsTheme.white(14)
    }

    private fun frac(t: Float): Float = ((t - 30f) / 20f).coerceIn(0f, 1f)

    fun setRange(min: Float, max: Float, current: Float) {
        minT = min; maxT = max
        if (curT.isNaN()) curT = current
        val from = if (curT.isNaN()) current else curT
        anim?.cancel()
        anim = ValueAnimator.ofFloat(from, current).apply {
            duration = 450
            addUpdateListener { curT = it.animatedValue as Float; invalidate() }
            start()
        }
        invalidate()
    }

    override fun onDetachedFromWindow() {
        anim?.cancel()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f) return
        val d = GsTheme.dp(context, 1f)

        rect.set(0f, h * 0.35f, w, h * 0.65f)
        val r = h * 0.15f
        path.reset()
        path.addRoundRect(rect, r, r, Path.Direction.CW)
        val save = canvas.save()
        canvas.clipPath(path)
        band.color = GsTheme.green; band.alpha = 56
        canvas.drawRect(0f, rect.top, w * 0.5f, rect.bottom, band)
        band.color = GsTheme.warm; band.alpha = 56
        canvas.drawRect(w * 0.5f, rect.top, w * 0.75f, rect.bottom, band)
        band.color = GsTheme.hot; band.alpha = 56
        canvas.drawRect(w * 0.75f, rect.top, w, rect.bottom, band)
        canvas.restoreToCount(save)

        if (minT.isNaN() || maxT.isNaN()) return

        val x0 = w * frac(minT)
        val x1 = w * frac(maxT)
        val bw = (x1 - x0).coerceAtLeast(d * 2f)
        rect.set(x0, h * 0.28f, x0 + bw, h * 0.72f)
        val br = minOf(h * 0.22f, bw / 2f)
        val grad = LinearGradient(
            rect.left, 0f, rect.right, 0f,
            GsTheme.withAlpha(GsTheme.accent, 0x2e),
            GsTheme.withAlpha(GsTheme.accent, 0x52),
            Shader.TileMode.CLAMP,
        )
        val seg = Paint(Paint.ANTI_ALIAS_FLAG).apply { shader = grad }
        canvas.drawRoundRect(rect, br, br, seg)

        if (!curT.isNaN()) {
            val cx = w * frac(curT)
            rect.set(cx - d * 2f, 0f, cx + d * 2f, h * 0.95f)
            markerGlow.color = GsTheme.withAlpha(GsTheme.accent, 0x66)
            markerGlow.setShadowLayer(GsTheme.dp(context, 4f), 0f, 0f, markerGlow.color)
            marker.color = GsTheme.accent
            canvas.drawRoundRect(rect, d * 2f, d * 2f, markerGlow)
            canvas.drawRoundRect(rect, d * 2f, d * 2f, marker)
        }
    }
}

/**
 * Slider horizontal do Game Space (saturação de cor). Trilha fina, preenchida
 * até o valor, com o "polegar" arrastável.
 */
class GsSlider @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : View(context, attrs) {

    var min = 0.8f
    var max = 2.0f
    var value = 1.0f
        set(v) {
            field = v.coerceIn(min, max)
            invalidate()
        }

    var onChanged: ((Float) -> Unit)? = null

    private val track = Paint(Paint.ANTI_ALIAS_FLAG)
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val knob = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()

    init {
        track.color = GsTheme.white(10)
        fill.color = GsTheme.accent
        knob.color = GsTheme.textHi
    }

    private fun frac(): Float = ((value - min) / (max - min)).coerceIn(0f, 1f)

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f) return
        val cy = h / 2f
        val th = GsTheme.dp(context, 3f)

        rect.set(0f, cy - th / 2f, w, cy + th / 2f)
        canvas.drawRoundRect(rect, th / 2f, th / 2f, track)

        val x = w * frac()
        rect.set(0f, cy - th / 2f, x, cy + th / 2f)
        canvas.drawRoundRect(rect, th / 2f, th / 2f, fill)

        canvas.drawCircle(x, cy, GsTheme.dp(context, 7f), knob)
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_MOVE -> {
                val f = (event.x / width.toFloat()).coerceIn(0f, 1f)
                value = min + f * (max - min)
                onChanged?.invoke(value)
                performClick()
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                onChanged?.invoke(value)
                return true
            }
        }
        return super.onTouchEvent(event)
    }

    override fun performClick(): Boolean = super.performClick()
}
