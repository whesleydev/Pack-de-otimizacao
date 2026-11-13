package com.otm.pack.gs

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.util.AttributeSet
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Caixa de vidro do Game Space: retângulo arredondado com preenchimento,
 * borda opcional e um brilho suave por fora.
 *
 * Substitui o `ZyBox` do app de referência — a API é a mesma ideia (propriedades
 * `bg`/`radius`/`border`/`glow`), mas o desenho é nosso: um `View.onDraw` com
 * `Paint`, sem os bitmaps de sombra em cache que aquele usava.
 */
open class GsBox @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    var bg: Int = Color.TRANSPARENT
        set(v) { field = v; invalidate() }

    var radiusPx: Float = GsTheme.dp(context, 14f)
        set(v) { field = v; invalidate() }

    var borderColor: Int = Color.TRANSPARENT
        set(v) { field = v; invalidate() }

    var borderWidthPx: Float = GsTheme.dp(context, 1f)
        set(v) { field = v; invalidate() }

    /** Brilho externo: cor + raio. Alfa 0 desliga. */
    var glowColor: Int = Color.TRANSPARENT
        set(v) { field = v; invalidate() }

    var glowRadiusPx: Float = 0f
        set(v) { field = v; invalidate() }

    private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }
    private val glowPaint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val rect = RectF()
    private val clipPath = Path()

    init {
        setWillNotDraw(false)
        clipToPadding = false
        clipChildren = false
    }

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        super.onSizeChanged(w, h, ow, oh)
        clipPath.reset()
        clipPath.addRoundRect(RectF(0f, 0f, w.toFloat(), h.toFloat()), radiusPx, radiusPx, Path.Direction.CW)
    }

    override fun dispatchDraw(canvas: Canvas) {
        val save = canvas.save()
        canvas.clipPath(clipPath)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(save)
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return
        val r = minOf(radiusPx, minOf(w, h) / 2f)

        if (Color.alpha(glowColor) > 0 && glowRadiusPx > 0f) {
            glowPaint.setShadowLayer(glowRadiusPx, 0f, GsTheme.dp(context, 3f), glowColor)
            glowPaint.color = Color.TRANSPARENT
            rect.set(0f, 0f, w, h)
            canvas.drawRoundRect(rect, r, r, glowPaint)
            glowPaint.clearShadowLayer()
        }

        if (Color.alpha(bg) > 0) {
            fill.color = bg
            rect.set(0f, 0f, w, h)
            canvas.drawRoundRect(rect, r, r, fill)
        }

        if (Color.alpha(borderColor) > 0 && borderWidthPx > 0f) {
            val i = borderWidthPx / 2f
            stroke.color = borderColor
            stroke.strokeWidth = borderWidthPx
            rect.set(i, i, w - i, h - i)
            canvas.drawRoundRect(rect, r - i, r - i, stroke)
        }
    }
}

/** Atalho: cria um [GsBox] já configurado, sem XML. */
fun gsBox(
    context: Context,
    bg: Int = Color.TRANSPARENT,
    radiusDp: Float = 14f,
    border: Int = Color.TRANSPARENT,
    glow: Int = Color.TRANSPARENT,
    glowDp: Float = 0f,
): GsBox = GsBox(context).apply {
    this.bg = bg
    radiusPx = GsTheme.dp(context, radiusDp)
    borderColor = border
    glowColor = glow
    glowRadiusPx = GsTheme.dp(context, glowDp)
}

/**
 * Texto do Game Space. Enxuga o `ZyTextView` original (que corrigia o
 * `letterSpacing` do Android pintando deslocado): aqui só desligamos o padding
 * de fonte, que é o efeito que realmente importa no layout.
 */
class GsText @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : TextView(context, attrs) {
    init {
        includeFontPadding = false
    }
}
