package com.otm.pack.gs

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Construtores dos blocos do Game Space (cabeçalho, segmentado, interruptor,
 * card, linha, botão). Ficam aqui para a tela (`GameSpaceActivity`) só descrever
 * o conteúdo, sem repetir layout.
 */
object Gs {

    fun dp(ctx: Context, v: Float): Int = GsTheme.dp(ctx, v).toInt()

    fun lp(w: Int, h: Int, weight: Float = 0f): LinearLayout.LayoutParams =
        LinearLayout.LayoutParams(w, h, weight)

    fun matchWrap(weight: Float = 0f) = lp(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT, weight)

    fun text(
        ctx: Context,
        s: CharSequence,
        size: Float,
        color: Int,
        typeface: Typeface,
        letterSpacing: Float = 0f,
        gravity: Int = Gravity.START,
    ): GsText = GsText(ctx).apply {
        text = s
        textSize = size
        setTextColor(color)
        this.typeface = typeface
        this.letterSpacing = letterSpacing
        this.gravity = gravity
    }

    fun title(ctx: Context, s: CharSequence, size: Float = 20f, color: Int = GsTheme.textHi) =
        text(ctx, s, size, color, GsTheme.title(ctx))

    fun label(ctx: Context, s: CharSequence, size: Float = 13f, color: Int = GsTheme.textHi, semi: Boolean = true) =
        text(ctx, s, size, color, if (semi) GsTheme.labelSemi(ctx) else GsTheme.label(ctx))

    fun num(ctx: Context, s: CharSequence, size: Float = 15f, color: Int = GsTheme.textHi) =
        text(ctx, s, size, color, GsTheme.num(ctx))

    fun numMed(ctx: Context, s: CharSequence, size: Float = 11f, color: Int = GsTheme.textMute) =
        text(ctx, s, size, color, GsTheme.numMed(ctx))

    /** Cabeçalho: "eyebrow" em cima, título grande embaixo, e um trailing opcional à direita. */
    fun header(ctx: Context, label: String, title: String, trailing: View? = null): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val col = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        col.addView(text(ctx, label, 9f, GsTheme.accent, GsTheme.label(ctx), 0.3f))
        col.addView(text(ctx, title, 20f, GsTheme.textHi, GsTheme.title(ctx)).apply {
            setPadding(0, dp(ctx, 1f), 0, 0)
        })
        row.addView(col)
        row.addView(View(ctx), lp(0, 1, 1f))
        if (trailing != null) {
            trailing.layoutParams = lp(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
                .apply { marginStart = dp(ctx, 12f) }
            row.addView(trailing)
        }
        return row
    }

    /** Pílula de vidro pequena com ícone + texto (usada nos headers). */
    fun pillChip(ctx: Context, text: String, iconRes: Int?, tint: Int): GsBox {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        if (iconRes != null) row.addView(icon(ctx, iconRes, 15, tint))
        row.addView(text(ctx, text, 13f, GsTheme.textHi, GsTheme.num(ctx)).apply {
            setPadding(dp(ctx, if (iconRes != null) 6f else 0f), 0, 0, 0)
        })
        return GsBox(ctx).apply {
            bg = GsTheme.white(4)
            borderColor = GsTheme.white(8)
            radiusPx = GsTheme.dp(ctx, 999f)
            setPadding(dp(ctx, 13f), dp(ctx, 7f), dp(ctx, 13f), dp(ctx, 7f))
            addView(row)
        }
    }

    fun icon(ctx: Context, res: Int, sizeDp: Int, tint: Int): ImageView =
        ImageView(ctx).apply {
            setImageResource(res)
            setColorFilter(tint)
            layoutParams = lp(dp(ctx, sizeDp.toFloat()), dp(ctx, sizeDp.toFloat()))
        }

    /** Linha divisória fina. */
    fun divider(ctx: Context): View =
        View(ctx).apply {
            setBackgroundColor(GsTheme.white(6))
            layoutParams = lp(LinearLayout.LayoutParams.MATCH_PARENT, dp(ctx, 1f))
        }

    /**
     * Card com título e ícone. Devolve o card e a coluna onde o conteúdo entra.
     * O card rola por dentro quando o conteúdo não cabe.
     */
    fun card(ctx: Context, titleRes: Int, iconRes: Int): Pair<GsBox, LinearLayout> {
        val head = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        head.addView(icon(ctx, iconRes, 18, GsTheme.accent))
        head.addView(text(ctx, ctx.getString(titleRes), 11f, GsTheme.accent, GsTheme.label(ctx), 0.24f).apply {
            setPadding(dp(ctx, 8f), 0, 0, 0)
        })

        val column = LinearLayout(ctx).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(ctx, 15f), dp(ctx, 11f), dp(ctx, 15f), dp(ctx, 11f))
        }
        column.addView(head)

        val card = GsBox(ctx).apply {
            bg = GsTheme.white(3)
            borderColor = GsTheme.white(7)
            radiusPx = GsTheme.dp(ctx, 18f)
            addView(column)
        }
        return card to column
    }

    /** Linha de ajuste: título/sub à esquerda, controle à direita. */
    fun row(ctx: Context, title: String, sub: String?, right: View): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, dp(ctx, 9f), 0, dp(ctx, 9f))
        }
        val col = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        col.addView(label(ctx, title, 13f))
        if (!sub.isNullOrBlank()) {
            col.addView(text(ctx, sub, 10.5f, GsTheme.textDim, GsTheme.label(ctx)).apply {
                setPadding(0, dp(ctx, 1f), 0, 0)
            })
        }
        row.addView(col, lp(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        right.layoutParams = lp(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT)
            .apply { marginStart = dp(ctx, 12f) }
        row.addView(right)
        return row
    }

    /** Segmentado (Performance/Econômico/Padrão): opções em pílulas, a ativa em acento. */
    fun segmented(
        ctx: Context,
        options: List<String>,
        selected: Int,
        onSelect: (Int) -> Unit,
    ): GsBox {
        val track = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val pills = ArrayList<TextView>()
        options.forEachIndexed { i, opt ->
            val tv = GsText(ctx).apply {
                text = opt
                textSize = 12f
                gravity = Gravity.CENTER
                typeface = GsTheme.labelSemi(ctx)
                setPadding(dp(ctx, 12f), dp(ctx, 6f), dp(ctx, 12f), dp(ctx, 6f))
                setOnClickListener { onSelect(i) }
            }
            pills.add(tv)
            track.addView(tv, lp(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f).apply {
                if (i > 0) marginStart = dp(ctx, 3f)
            })
        }
        fun paint(sel: Int) {
            pills.forEachIndexed { i, tv ->
                val on = i == sel
                tv.setTextColor(if (on) GsTheme.onAccent else GsTheme.textSoft)
                tv.background = rounded(ctx, 10f, if (on) GsTheme.accent else Color.TRANSPARENT)
            }
        }
        paint(selected)
        val box = GsBox(ctx).apply {
            bg = GsTheme.white(4)
            radiusPx = GsTheme.dp(ctx, 12f)
            setPadding(dp(ctx, 3f), dp(ctx, 3f), dp(ctx, 3f), dp(ctx, 3f))
            addView(track)
        }
        // repinta ao trocar
        track.tag = selected
        pills.forEachIndexed { i, tv -> tv.setOnClickListener { paint(i); onSelect(i) } }
        return box
    }

    /** Interruptor (trilha + botão). Devolve o track; chame `setOn` para pintar. */
    fun toggle(ctx: Context, checked: Boolean, onToggle: (Boolean) -> Unit): GsBox {
        val knob = GsBox(ctx).apply {
            bg = GsTheme.textMute
            radiusPx = GsTheme.dp(ctx, 999f)
            layoutParams = lp(dp(ctx, 18f), dp(ctx, 18f)).apply {
                marginStart = dp(ctx, 4f); topMargin = dp(ctx, 4f)
            }
        }
        val track = GsBox(ctx).apply {
            bg = GsTheme.white(6)
            borderColor = GsTheme.white(14)
            radiusPx = GsTheme.dp(ctx, 999f)
            layoutParams = lp(dp(ctx, 44f), dp(ctx, 26f))
            addView(knob)
        }
        var state = checked
        fun paint() {
            track.bg = if (state) GsTheme.accentA(0x40) else GsTheme.white(6)
            knob.bg = if (state) GsTheme.accent else GsTheme.textMute
        }
        paint()
        track.setOnClickListener {
            state = !state
            paint()
            onToggle(state)
        }
        return track
    }

    /** Botão principal (cheio, no acento). */
    fun accentButton(ctx: Context, text: String, iconRes: Int?, onClick: () -> Unit): GsBox {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        if (iconRes != null) row.addView(icon(ctx, iconRes, 20, GsTheme.onAccent))
        row.addView(GsText(ctx).apply {
            this.text = text
            textSize = 13f
            setTextColor(GsTheme.onAccent)
            typeface = GsTheme.labelSemi(ctx)
            setPadding(dp(ctx, if (iconRes != null) 8f else 0f), 0, 0, 0)
        })
        return GsBox(ctx).apply {
            bg = GsTheme.accent
            radiusPx = GsTheme.dp(ctx, 12f)
            glowColor = GsTheme.accentA(0x59)
            glowRadiusPx = GsTheme.dp(ctx, 14f)
            setPadding(dp(ctx, 14f), dp(ctx, 9f), dp(ctx, 14f), dp(ctx, 9f))
            addView(row)
            setOnClickListener { onClick() }
        }
    }

    /** Botão secundário (vidro, borda discreta). */
    fun ghostButton(ctx: Context, text: String, iconRes: Int?, onClick: () -> Unit): GsBox {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        if (iconRes != null) row.addView(icon(ctx, iconRes, 17, GsTheme.textSoft))
        row.addView(GsText(ctx).apply {
            this.text = text
            textSize = 12.5f
            setTextColor(GsTheme.textSoft)
            typeface = GsTheme.labelSemi(ctx)
            setPadding(dp(ctx, if (iconRes != null) 6f else 0f), 0, 0, 0)
        })
        return GsBox(ctx).apply {
            bg = GsTheme.white(4)
            borderColor = GsTheme.white(10)
            radiusPx = GsTheme.dp(ctx, 12f)
            setPadding(dp(ctx, 13f), dp(ctx, 9f), dp(ctx, 13f), dp(ctx, 9f))
            addView(row)
            setOnClickListener { onClick() }
        }
    }

    /** Rótulo + valor (usado nos chips e no dock). */
    fun stat(ctx: Context, labelTxt: String, valueTxt: String): Pair<View, TextView> {
        val col = LinearLayout(ctx).apply { orientation = LinearLayout.VERTICAL }
        col.addView(text(ctx, labelTxt, 8f, GsTheme.textDim, GsTheme.label(ctx), 0.22f))
        val value = text(ctx, valueTxt, 13f, GsTheme.textHi, GsTheme.num(ctx)).apply {
            setPadding(0, dp(ctx, 1f), 0, 0)
        }
        col.addView(value)
        return col to value
    }

    fun rounded(ctx: Context, radiusDp: Float, fill: Int, stroke: Int? = null): android.graphics.drawable.GradientDrawable =
        android.graphics.drawable.GradientDrawable().apply {
            cornerRadius = GsTheme.dp(ctx, radiusDp)
            setColor(fill)
            if (stroke != null) setStroke(dp(ctx, 1f), stroke)
        }

    /** Cartão de app (ícone + nome) para a lista de apps pesados. */
    fun appChip(ctx: Context, name: String, ramMb: Int, onClick: (() -> Unit)?): View {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(ctx, 9f), dp(ctx, 8f), dp(ctx, 9f), dp(ctx, 8f))
        }
        row.addView(text(ctx, name, 12f, GsTheme.textHi, GsTheme.labelSemi(ctx), gravity = Gravity.CENTER_VERTICAL),
            lp(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(text(ctx, "$ramMb MB", 11f, GsTheme.ram, GsTheme.num(ctx)))
        val box = GsBox(ctx).apply {
            bg = GsTheme.white(3)
            borderColor = GsTheme.white(8)
            radiusPx = GsTheme.dp(ctx, 10f)
            addView(row)
            if (onClick != null) setOnClickListener { onClick() }
        }
        box.layoutParams = matchWrap().apply { topMargin = dp(ctx, 6f) }
        return box
    }

    /** Espaçador flexível. */
    fun spacer(ctx: Context): View = View(ctx).apply { layoutParams = lp(0, 0, 1f) }

    /**
     * Linha de "chips" selecionáveis (usada nos presets de resolução). Rola na
     * horizontal quando não cabe, em vez de espremer os rótulos.
     */
    fun chipRow(
        ctx: Context,
        options: List<String>,
        selected: Int,
        onSelect: (Int) -> Unit,
    ): android.widget.HorizontalScrollView {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val chips = ArrayList<TextView>()
        options.forEachIndexed { i, opt ->
            val tv = GsText(ctx).apply {
                text = opt
                textSize = 12f
                gravity = Gravity.CENTER
                typeface = GsTheme.labelSemi(ctx)
                setPadding(dp(ctx, 13f), dp(ctx, 7f), dp(ctx, 13f), dp(ctx, 7f))
            }
            chips.add(tv)
            row.addView(tv, lp(LinearLayout.LayoutParams.WRAP_CONTENT, LinearLayout.LayoutParams.WRAP_CONTENT).apply {
                if (i > 0) marginStart = dp(ctx, 6f)
            })
        }
        fun paint(sel: Int) {
            chips.forEachIndexed { i, tv ->
                val on = i == sel
                tv.setTextColor(if (on) GsTheme.onAccent else GsTheme.textSoft)
                tv.background = if (on) {
                    rounded(ctx, 10f, GsTheme.accent)
                } else {
                    rounded(ctx, 10f, GsTheme.white(4), GsTheme.white(10))
                }
            }
        }
        paint(selected)
        chips.forEachIndexed { i, tv ->
            tv.setOnClickListener { paint(i); onSelect(i) }
        }
        return android.widget.HorizontalScrollView(ctx).apply {
            isHorizontalScrollBarEnabled = false
            addView(row)
        }
    }

    /** Valor com uma etiqueta pequena ao lado (ex.: "100%" + "Android 13+"). */
    fun valueWithBadge(ctx: Context, value: String, badge: String?): Pair<View, TextView> {
        val row = LinearLayout(ctx).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        if (badge != null) {
            val b = GsText(ctx).apply {
                text = badge
                textSize = 9.5f
                setTextColor(GsTheme.accent)
                typeface = GsTheme.labelSemi(ctx)
                setPadding(dp(ctx, 6f), dp(ctx, 1f), dp(ctx, 6f), dp(ctx, 1f))
                background = rounded(ctx, 5f, GsTheme.accentA(0x1f))
            }
            row.addView(b)
        }
        val tv = GsText(ctx).apply {
            text = value
            textSize = 11f
            setTextColor(GsTheme.accent)
            typeface = GsTheme.numMed(ctx)
            setPadding(dp(ctx, if (badge != null) 6f else 0f), 0, 0, 0)
        }
        row.addView(tv)
        return row to tv
    }

    /** Campo de texto compacto (ex.: "1280x720" personalizado). */
    fun field(ctx: Context, hint: String): android.widget.EditText =
        android.widget.EditText(ctx).apply {
            this.hint = hint
            textSize = 13f
            setTextColor(GsTheme.textHi)
            setHintTextColor(GsTheme.textDim)
            typeface = GsTheme.numMed(ctx)
            background = rounded(ctx, 10f, GsTheme.white(4), GsTheme.white(10))
            setPadding(dp(ctx, 11f), dp(ctx, 9f), dp(ctx, 11f), dp(ctx, 9f))
            inputType = android.text.InputType.TYPE_CLASS_TEXT
            maxLines = 1
        }

    fun vSpace(ctx: Context, v: Float): View =
        View(ctx).apply { layoutParams = lp(LinearLayout.LayoutParams.MATCH_PARENT, dp(ctx, v)) }

    /** Centraliza uma view num FrameLayout ocupando tudo. */
    fun centerIn(ctx: Context, v: View): FrameLayout =
        FrameLayout(ctx).apply { addView(v, FrameLayout.LayoutParams(-2, -2, Gravity.CENTER)) }
}
