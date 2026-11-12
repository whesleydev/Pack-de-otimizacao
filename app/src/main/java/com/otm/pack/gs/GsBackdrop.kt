package com.otm.pack.gs

import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.util.AttributeSet
import android.view.View

/**
 * Fundo do Game Space: gradiente vertical escuro com um brilho radial no canto
 * superior direito, na cor de destaque.
 *
 * Porte do `GsBackdropView` de referência, sem a imagem opcional de fundo —
 * o efeito que dá o "clima" é o gradiente + o brilho.
 */
class GsBackdropView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : View(context, attrs) {

    private val base = Paint(Paint.ANTI_ALIAS_FLAG)
    private val glow = Paint(Paint.ANTI_ALIAS_FLAG)

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        super.onSizeChanged(w, h, ow, oh)
        val fh = h.toFloat()

        base.shader = LinearGradient(
            0f, 0f, 0f, fh,
            intArrayOf(GsTheme.bg0, GsTheme.bg1, GsTheme.bg2),
            floatArrayOf(0f, 0.5f, 1f),
            Shader.TileMode.CLAMP,
        )

        val fw = w.toFloat()
        val radius = (fw * 0.6f).coerceAtLeast(1f)
        val accentSoft = GsTheme.accentA(0x17)
        val g = RadialGradient(
            fw, 0f, radius,
            intArrayOf(accentSoft, accentSoft and 0x00ffffff),
            floatArrayOf(0f, 0.65f),
            Shader.TileMode.CLAMP,
        )
        val m = Matrix()
        val hHalf = (fh * 0.5f).coerceAtLeast(1f)
        m.setScale(1f, hHalf / radius, fw, 0f)
        g.setLocalMatrix(m)
        glow.shader = g
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), base)
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), glow)
    }
}

/**
 * O "orb" da marca: círculo escuro com um halo na cor de destaque, usado no
 * topo do rail de abas.
 *
 * Versão enxuta do `OrbView` de referência (que pré-renderizava em bitmap com
 * cache). Aqui é desenho direto — poucos círculos por quadro.
 */
class GsOrbView @JvmOverloads constructor(
    context: Context, attrs: AttributeSet? = null,
) : View(context, attrs) {

    private val halo = Paint(Paint.ANTI_ALIAS_FLAG)
    private val core = Paint(Paint.ANTI_ALIAS_FLAG)
    private val ring = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.STROKE }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val r = minOf(cx, cy)

        halo.color = GsTheme.accentA(0x59)
        halo.setShadowLayer(GsTheme.dp(context, 10f), 0f, 0f, GsTheme.accentA(0x66))
        canvas.drawCircle(cx, cy, r, halo)
        halo.clearShadowLayer()

        core.color = GsTheme.withAlpha(GsTheme.bgRoot, 0xff)
        canvas.drawCircle(cx, cy, r * 0.92f, core)

        ring.color = GsTheme.accentA(0xe6)
        ring.strokeWidth = GsTheme.dp(context, 1.5f)
        canvas.drawCircle(cx, cy, r * 0.92f, ring)
    }
}
