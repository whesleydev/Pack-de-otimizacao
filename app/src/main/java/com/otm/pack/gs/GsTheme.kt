package com.otm.pack.gs

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import java.util.concurrent.ConcurrentHashMap

/**
 * Tokens visuais do Game Space (cores e fontes).
 *
 * É o único lugar que precisa mudar para retematizar a tela inteira: os
 * componentes leem daqui, então trocar [accent] (e os derivados) repinta
 * tudo. As fontes são as mesmas do layout original (Chakra Petch para
 * rótulos/títulos e Oxanium para números), carregadas dos assets.
 */
object GsTheme {

    /** Cor de destaque. Muda aqui e o Game Space inteiro acompanha. */
    var accent: Int = Color.parseColor("#7fd8ff")

    /** Tinta sobre o acento (texto/ícone em cima da cor cheia). */
    var onAccent: Int = Color.parseColor("#04121f")

    /** Acento com alfa (0..255) — para bordas, brilhos e fundos tintados. */
    fun accentA(alpha: Int): Int = withAlpha(accent, alpha)

    fun withAlpha(color: Int, alpha: Int): Int =
        Color.argb(alpha.coerceIn(0, 255), Color.red(color), Color.green(color), Color.blue(color))

    // ---- fundo ---------------------------------------------------------------
    val bgRoot: Int = Color.parseColor("#020304")
    val bg0: Int = Color.parseColor("#050a10")
    val bg1: Int = Color.parseColor("#030507")
    val bg2: Int = Color.parseColor("#04080d")
    val railBg: Int = Color.parseColor("#80050a10")
    val dockBg: Int = Color.parseColor("#8c050a10")
    val toastBg: Int = Color.parseColor("#e61c1e22")
    val dropBg: Int = Color.parseColor("#fa0a1420")

    // ---- texto ---------------------------------------------------------------
    val text: Int = Color.parseColor("#f2f8fc")
    val textHi: Int = Color.parseColor("#e6f6ff")
    val textSoft: Int = Color.parseColor("#c9d6e0")
    val textMute: Int = Color.parseColor("#8fa7ba")
    val textDim: Int = Color.parseColor("#7f8c99")
    val textOff: Int = Color.parseColor("#8a97a3")

    // ---- vidro (branco com alfa) ---------------------------------------------
    /** Branco translúcido na porcentagem do token original (3,4,6,7,8,10,...). */
    fun white(pct: Int): Int = when (pct) {
        3 -> 0x08ffffff
        4 -> 0x0affffff
        6 -> 0x0fffffff
        7 -> 0x12ffffff
        8 -> 0x14ffffff
        10 -> 0x1affffff
        12 -> 0x1fffffff
        14 -> 0x24ffffff
        18 -> 0x2effffff
        20 -> 0x33ffffff
        25 -> 0x40ffffff
        else -> (2.55f * pct).toInt().coerceIn(0, 255) shl 24
    }

    // ---- semânticos ----------------------------------------------------------
    val green: Int = Color.parseColor("#4ade80")
    val warm: Int = Color.parseColor("#ffc266")
    val hot: Int = Color.parseColor("#ff5c6c")
    val gpu: Int = Color.parseColor("#b388ff")
    val ram: Int = Color.parseColor("#1de9b6")
    val glow: Int = Color.parseColor("#997fd8ff")

    // ---- fontes --------------------------------------------------------------
    private val cache = ConcurrentHashMap<String, Typeface>()

    private fun load(context: Context, file: String): Typeface =
        cache.getOrPut(file) {
            runCatching { Typeface.createFromAsset(context.assets, "gs/fonts/$file") }
                .getOrDefault(Typeface.DEFAULT)
        }

    fun title(context: Context): Typeface = load(context, "chakra_petch_bold.ttf")
    fun label(context: Context): Typeface = load(context, "chakra_petch_regular.ttf")
    fun labelSemi(context: Context): Typeface = load(context, "chakra_petch_semibold.ttf")
    fun num(context: Context): Typeface = load(context, "oxanium_bold.ttf")
    fun numSemi(context: Context): Typeface = load(context, "oxanium_semibold.ttf")
    fun numMed(context: Context): Typeface = load(context, "oxanium_medium.ttf")

    fun dp(context: Context, v: Float): Float = v * context.resources.displayMetrics.density
}
