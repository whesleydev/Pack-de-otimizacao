package com.otm.pack

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Toast
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Painel flutuante (overlay) para usar **durante o jogo**.
 *
 * O app roda dentro do Free Fire/CODM/etc. por cima da tela, sem precisar
 * fechar o jogo para conferir a sensi, trocar o perfil de toque ou escolher o
 * motor de renderização. É um `Service` em primeiro plano com uma janela
 * `TYPE_APPLICATION_OVERLAY`, que pode ser arrastada e minimizada.
 *
 * O painel se chama só **"00"** e é organizado em **categorias (abas)** — Sensi,
 * Toque, Motor e Atalhos. Antes tudo saía numa lista corrida e, no meio da
 * partida, achar um botão era lento; agora cada aba mostra só o que interessa.
 *
 * **Minimizado ele vira só o ícone do app**: o painel inteiro some e sobra o
 * ícone do "00 Otimização", que continua arrastável. Um toque no ícone devolve
 * o painel completo — é o mesmo gesto de minimizar/maximizar de um app.
 *
 * O acesso ao shell vem de [OtmRunner], que a Activity preenche ao conectar o
 * Shizuku/ADB — o Service não tem como pedir permissão sozinho.
 */
class OverlayService : Service() {

    private lateinit var windowManager: WindowManager
    private var root: View? = null
    private var panel: View? = null
    private var bubble: View? = null
    private var sensiText: TextView? = null
    private var statusText: TextView? = null
    private var content: LinearLayout? = null
    private val tabChips = mutableListOf<TextView>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildNotification())
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        addOverlay()
        refreshSensi()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        scope.cancel()
        root?.let { runCatching { windowManager.removeView(it) } }
        root = null
        panel = null
        bubble = null
        super.onDestroy()
    }

    // ---- janela --------------------------------------------------------------

    private fun addOverlay() {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(dp(16).toFloat(), "#F00D0C0A", "#3A3733")
            setPadding(dp(12), dp(10), dp(12), dp(10))
            minimumWidth = dp(240)
        }
        box.addView(titleBar())
        box.addView(tabBar())

        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(content, matchWrap())

        statusText = TextView(this).apply {
            setTextColor(Color.parseColor("#B9B2A6"))
            textSize = 11f
            setPadding(0, dp(8), 0, 0)
        }
        box.addView(statusText)

        selectTab(0)
        panel = box
        bubble = bubbleView()
        root = box

        val params = baseParams()
        box.setOnTouchListener(dragger(params, box))
        runCatching { windowManager.addView(box, params) }
    }

    /** Abas: cada categoria mostra só o seu bloco, sem lista corrida. */
    private fun tabBar(): View {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        tabChips.clear()
        for ((i, name) in TABS.withIndex()) {
            val chip = tabChip(name, i)
            tabChips.add(chip)
            row.addView(chip)
        }
        return row
    }

    private fun tabChip(label: String, index: Int): TextView =
        TextView(this).apply {
            text = label
            textSize = 11f
            gravity = Gravity.CENTER
            setPadding(dp(6), dp(6), dp(6), dp(6))
            setOnClickListener { selectTab(index) }
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
            ).apply { marginEnd = dp(4) }
        }

    private fun selectTab(index: Int) {
        val box = content ?: return
        box.removeAllViews()
        box.addView(tabView(index), matchWrap())
        for ((i, chip) in tabChips.withIndex()) {
            val on = i == index
            chip.setTextColor(Color.parseColor(if (on) "#12151A" else "#D8D2C7"))
            chip.background = if (on) rounded(dp(8).toFloat(), "#E4571C")
            else rounded(dp(8).toFloat(), "#00000000", "#3A3733")
            chip.setTypeface(chip.typeface, if (on) Typeface.BOLD else Typeface.NORMAL)
        }
    }

    private fun tabView(index: Int): View = when (index) {
        0 -> sensiTab()
        1 -> touchTab()
        2 -> engineTab()
        else -> shortcutsTab()
    }

    /** Aba Sensi: o número que o usuário quer ver de relance. */
    private fun sensiTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(sectionHeader("Sensi do seu aparelho"))
        sensiText = TextView(this).apply {
            setTextColor(Color.parseColor("#F3EFE7"))
            textSize = 13f
            text = "lendo a sensi…"
        }
        box.addView(sensiText, matchWrap())
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(smallButton("Atualizar") { refreshSensi() })
        row.addView(smallButton("Headshot") { runScript("sensi.sh", listOf("headshot"), "Sensi: headshot") })
        box.addView(row, matchWrap())
        return box
    }

    /** Aba Toque: perfis de sensibilidade do jogo. */
    private fun touchTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(sectionHeader("Perfil de toque"))
        var row: LinearLayout? = null
        for ((i, p) in TOUCH_PROFILES.withIndex()) {
            if (i % 2 == 0) {
                row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                box.addView(row, matchWrap())
            }
            row!!.addView(smallButton(p.second) { runScript("ff-touch.sh", listOf(p.first), "Toque: ${p.second}") })
        }
        return box
    }

    /** Aba Motor: escolhe o motor de renderização (o mesmo do painel principal). */
    private fun engineTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(sectionHeader("Motor de renderização"))
        var row: LinearLayout? = null
        for ((i, e) in RENDERERS.withIndex()) {
            if (i % 2 == 0) {
                row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                box.addView(row, matchWrap())
            }
            row!!.addView(smallButton(e.second) {
                runScript("adb-tweaks.sh", listOf("renderer", e.first), "Motor: ${e.second}")
            })
        }
        return box
    }

    /** Aba Atalhos: latência, limpeza de RAM e atualizar. */
    private fun shortcutsTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(sectionHeader("Atalhos"))
        val row1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row1.addView(smallButton("Latência") { runScript("adb-tweaks.sh", listOf("latency"), "Latência") })
        row1.addView(smallButton("Limpar RAM") { runScript("clean.sh", listOf("now", "fundo"), "Limpeza") })
        box.addView(row1, matchWrap())
        val row2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row2.addView(smallButton("Game Clean") { runScript("game-clean.sh", listOf("on"), "Game Clean") })
        row2.addView(smallButton("Atualizar") { refreshSensi() })
        box.addView(row2, matchWrap())
        return box
    }

    /** Cabeçalho de seção: separa os blocos do painel. */
    private fun sectionHeader(text: String): View =
        TextView(this).apply {
            this.text = text
            setTextColor(Color.parseColor("#E4571C"))
            textSize = 12f
            setTypeface(typeface, Typeface.BOLD)
            setPadding(0, dp(10), 0, dp(6))
        }

    /** Barra do topo: arrasta pelo título, minimiza e fecha. */
    private fun titleBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        bar.addView(TextView(this).apply {
            text = "00"
            setTextColor(Color.parseColor("#E4571C"))
            textSize = 15f
            setTypeface(typeface, Typeface.BOLD)
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        bar.addView(iconButton("—") { toggleMinimize() })
        bar.addView(iconButton("X") { stopSelf() })
        return bar
    }

    /** O app minimizado: só o ícone, sem texto — um toque devolve o painel. */
    private fun bubbleView(): View =
        ImageView(this).apply {
            setImageResource(R.mipmap.ic_launcher)
            setPadding(dp(4), dp(4), dp(4), dp(4))
            background = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#E60D0C0A"))
                setStroke(dp(1), Color.parseColor("#3A3733"))
            }
            setOnClickListener { setMinimized(false) }
        }

    private var minimized = false

    /**
     * Minimiza/maximiza trocando a janela: minimizado sobra só o ícone do app
     * (a janela fica pequena, sem atrapalhar o jogo); um toque no ícone devolve
     * o painel completo, no mesmo lugar da tela.
     */
    private fun toggleMinimize() = setMinimized(!minimized)

    private fun setMinimized(value: Boolean) {
        if (value == minimized) return
        val atual = root ?: return
        val novo = (if (value) bubble else panel) ?: return
        val params = baseParams()
        // mantém onde o usuário deixou: a janela nova nasce na mesma posição
        (atual.layoutParams as? WindowManager.LayoutParams)?.let {
            params.x = it.x; params.y = it.y
        }
        minimized = value
        runCatching {
            windowManager.removeView(atual)
            novo.setOnTouchListener(dragger(params, novo))
            windowManager.addView(novo, params)
            root = novo
        }
    }

    private fun iconButton(label: String, action: () -> Unit): View =
        TextView(this).apply {
            text = label
            textSize = 12f
            setTextColor(Color.parseColor("#F3EFE7"))
            setPadding(dp(10), dp(2), dp(10), dp(2))
            setOnClickListener { action() }
        }

    private fun smallButton(label: String, action: () -> Unit): View =
        TextView(this).apply {
            text = label
            textSize = 11f
            gravity = Gravity.CENTER
            setTextColor(Color.parseColor("#12151A"))
            background = rounded(dp(8).toFloat(), "#E4571C")
            setPadding(dp(8), dp(6), dp(8), dp(6))
            setOnClickListener { action() }
        }.also {
            it.layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
            ).apply { marginEnd = dp(4) }
        }

    /** Fundo arredondado com borda opcional (usado no painel e nos chips de aba). */
    private fun rounded(radius: Float, fill: String, stroke: String? = null): GradientDrawable =
        GradientDrawable().apply {
            cornerRadius = radius
            setColor(Color.parseColor(fill))
            if (stroke != null) setStroke(dp(1), Color.parseColor(stroke))
        }

    private fun baseParams() = WindowManager.LayoutParams(
        WindowManager.LayoutParams.WRAP_CONTENT,
        WindowManager.LayoutParams.WRAP_CONTENT,
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_PHONE,
        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
        PixelFormat.TRANSLUCENT,
    ).apply {
        gravity = Gravity.TOP or Gravity.START
        x = dp(12); y = dp(80)
    }

    /** Arrasta a janela; um toque curto (sem mover) não consome o clique. */
    private fun dragger(params: WindowManager.LayoutParams, view: View): View.OnTouchListener {
        var startX = 0; var startY = 0; var downX = 0f; var downY = 0f
        return View.OnTouchListener { _, ev ->
            when (ev.action) {
                MotionEvent.ACTION_DOWN -> {
                    startX = params.x; startY = params.y
                    downX = ev.rawX; downY = ev.rawY
                    false
                }
                MotionEvent.ACTION_MOVE -> {
                    if (kotlin.math.abs(ev.rawX - downX) > dp(6) || kotlin.math.abs(ev.rawY - downY) > dp(6)) {
                        params.x = startX + (ev.rawX - downX).toInt()
                        params.y = startY + (ev.rawY - downY).toInt()
                        runCatching { windowManager.updateViewLayout(view, params) }
                        true
                    } else false
                }
                else -> false
            }
        }
    }

    // ---- ações ---------------------------------------------------------------

    private fun refreshSensi() {
        scope.launch {
            val out = OtmExec.run(this@OverlayService, OtmRunner.current, "sensi.sh", listOf("calc"))
            val text = joinOutput(out.stdout, out.stderr)
            val vals = parseSensi(text)
            post {
                sensiText?.text = if (vals == null) {
                    "sem acesso — conecte o Shizuku/ADB no painel"
                } else {
                    "Geral ${vals[0]}  ·  Ponto ${vals[1]}\n" +
                        "2x ${vals[2]}  ·  4x ${vals[3]}  ·  AWM ${vals[4]}\n" +
                        "Botão de atirar ${vals[5]}%"
                }
            }
        }
    }

    private fun runScript(script: String, args: List<String>, label: String) {
        post { statusText?.text = "$label: aplicando…" }
        scope.launch {
            val res = OtmExec.run(this@OverlayService, OtmRunner.current, script, args)
            val v = OtmExec.parseResult(joinOutput(res.stdout, res.stderr))
            val changed = v["changed"]?.toIntOrNull() ?: 0
            val failed = v["failed"]?.toIntOrNull() ?: 0
            val msg = when {
                !res.ok -> "$label: falhou (veja o painel)"
                changed > 0 -> "$label: aplicado ($changed)"
                failed > 0 -> "$label: nada mudou ($failed falha(s))"
                else -> "$label: sem mudança"
            }
            post {
                statusText?.text = msg
                Toast.makeText(this@OverlayService, msg, Toast.LENGTH_SHORT).show()
            }
        }
    }

    /** Extrai "Geral, Ponto, 2x, 4x, AWM, botão%" das linhas do `sensi.sh calc`. */
    private fun parseSensi(out: String): List<Int>? {
        fun grab(label: String): Int? {
            val line = out.lineSequence().firstOrNull { it.trimStart().startsWith(label) } ?: return null
            return Regex("(\\d+)").find(line.substringAfter(label))?.groupValues?.get(1)?.toIntOrNull()
        }
        val gen = grab("Geral") ?: return null
        val rd = grab("Ponto vermelho") ?: return null
        val x2 = grab("Mira 2x") ?: return null
        val x4 = grab("Mira 4x") ?: return null
        val awm = grab("AWM") ?: return null
        val btn = grab("Botão de atirar") ?: 0
        return listOf(gen, rd, x2, x4, awm, btn)
    }

    private fun post(block: () -> Unit) = android.os.Handler(mainLooper).post(block)

    // ---- utilidades ----------------------------------------------------------

    private fun buildNotification(): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val mgr = getSystemService(NotificationManager::class.java)
            if (mgr.getNotificationChannel(CHANNEL_ID) == null) {
                mgr.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Painel flutuante", NotificationManager.IMPORTANCE_LOW)
                        .apply { description = "Mantém o painel de sensi sobre o jogo." }
                )
            }
        }
        val b = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            Notification.Builder(this, CHANNEL_ID)
        else
            @Suppress("DEPRECATION") Notification.Builder(this)
        return b.setContentTitle("00 Otimização")
            .setContentText("Painel flutuante ativo — toque em Fechar no painel para sair.")
            .setSmallIcon(android.R.drawable.stat_notify_sync)
            .setOngoing(true)
            .build()
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    )

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    companion object {
        const val CHANNEL_ID = "otm_overlay"
        const val NOTIF_ID = 2
        const val ACTION_STOP = "com.otm.pack.overlay.STOP"

        /** Categorias do painel, na ordem das abas. */
        private val TABS = listOf("Sensi", "Toque", "Motor", "Atalhos")

        /** Perfis de toque do `ff-touch.sh`, na ordem em que aparecem no painel. */
        private val TOUCH_PROFILES = listOf(
            "balanced" to "Equilibrado",
            "headshot" to "Headshot",
            "spray" to "Spray",
            "sniper" to "Sniper",
            "speed" to "Speed",
        )

        /** Motores de renderização aceitos por `adb-tweaks.sh renderer`. */
        private val RENDERERS = listOf(
            "auto" to "Automático",
            "skiagl" to "SkiaGL",
            "skiavk" to "Skia Vulkan",
            "skiagl-threaded" to "SkiaGL MT",
            "skiavk-threaded" to "SkiaVK MT",
        )

        /** O usuário liberou "aparecer por cima de outros apps"? */
        fun canDraw(context: Context): Boolean =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) Settings.canDrawOverlays(context) else true

        fun start(context: Context) {
            context.startForegroundService(Intent(context, OverlayService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, OverlayService::class.java))
        }
    }
}
