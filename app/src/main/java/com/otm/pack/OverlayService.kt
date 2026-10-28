package com.otm.pack

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.Button
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
 * fechar o jogo para conferir a sensi ou trocar o perfil de toque. É um
 * `Service` em primeiro plano com uma janela `TYPE_APPLICATION_OVERLAY`, que
 * pode ser arrastada e minimizada.
 *
 * O que o painel mostra e faz:
 *  - a sensi calculada para ESTE aparelho (Geral, Ponto, 2x, 4x, AWM e o
 *    tamanho do botão de atirar), lida do `sensi.sh`;
 *  - os perfis de toque (Equilibrado, Headshot, Spray, Sniper, Speed);
 *  - atalhos de latência e limpeza de RAM, os mesmos do painel principal.
 *
 * O acesso ao shell vem de [OtmRunner], que a Activity preenche ao conectar o
 * Shizuku/ADB — o Service não tem como pedir permissão sozinho.
 */
class OverlayService : Service() {

    private lateinit var windowManager: WindowManager
    private var root: View? = null
    private var sensiText: TextView? = null
    private var statusText: TextView? = null
    private val content = ArrayList<View>()
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
        super.onDestroy()
    }

    // ---- janela --------------------------------------------------------------

    private fun addOverlay() {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.parseColor("#E60D0C0A"))
            setPadding(dp(14), dp(10), dp(14), dp(10))
        }
        box.addView(titleBar())

        sensiText = TextView(this).apply {
            setTextColor(Color.parseColor("#F3EFE7"))
            textSize = 13f
            text = "lendo a sensi…"
        }
        box.addView(sensiText, matchWrap())
        content.add(sensiText!!)

        val hint = TextView(this).apply {
            text = "Perfil de toque"
            setTextColor(Color.parseColor("#E4571C"))
            textSize = 12f
            setPadding(0, dp(8), 0, dp(4))
        }
        box.addView(hint)
        content.add(hint)

        val profiles = listOf(
            "balanced" to "Equilibrado",
            "headshot" to "Headshot",
            "spray" to "Spray",
            "sniper" to "Sniper",
            "speed" to "Speed",
        )
        for ((key, label) in profiles) {
            val b = profileButton(key, label)
            box.addView(b)
            content.add(b)
        }

        val extras = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        extras.addView(smallButton("Latência") { runScript("adb-tweaks.sh", listOf("latency"), "Latência") })
        extras.addView(smallButton("Limpar RAM") { runScript("adb-tweaks.sh", listOf("clean", "suave"), "Limpeza") })
        extras.addView(smallButton("Atualizar") { refreshSensi() })
        box.addView(extras, matchWrap())
        content.add(extras)

        statusText = TextView(this).apply {
            setTextColor(Color.parseColor("#B9B2A6"))
            textSize = 11f
            setPadding(0, dp(6), 0, 0)
        }
        box.addView(statusText)
        content.add(statusText!!)

        val params = WindowManager.LayoutParams(
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
        box.setOnTouchListener(dragger(params))
        root = box
        runCatching { windowManager.addView(box, params) }
    }

    /** Barra do topo: arrasta pelo título, minimiza e fecha. */
    private fun titleBar(): View {
        val bar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        bar.addView(TextView(this).apply {
            text = "Sensi & mira"
            setTextColor(Color.parseColor("#E4571C"))
            textSize = 13f
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        bar.addView(Button(this).apply {
            text = "—"
            textSize = 12f
            setPadding(dp(8), 0, dp(8), 0)
            setOnClickListener { toggleMinimize() }
        })
        bar.addView(Button(this).apply {
            text = "X"
            textSize = 12f
            setPadding(dp(8), 0, dp(8), 0)
            setOnClickListener { stopSelf() }
        })
        return bar
    }

    private var minimized = false

    private fun toggleMinimize() {
        minimized = !minimized
        for (v in content) v.visibility = if (minimized) View.GONE else View.VISIBLE
    }

    private fun profileButton(key: String, label: String): View =
        Button(this).apply {
            text = label
            textSize = 12f
            setOnClickListener { runScript("ff-touch.sh", listOf(key), "Toque: $label") }
        }.also { it.layoutParams = matchWrap() }

    private fun smallButton(label: String, action: () -> Unit): View =
        Button(this).apply {
            text = label
            textSize = 11f
            setPadding(dp(6), 0, dp(6), 0)
            setOnClickListener { action() }
        }

    /** Arrasta a janela; um toque curto (sem mover) não consome o clique. */
    private fun dragger(params: WindowManager.LayoutParams): View.OnTouchListener {
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
                        root?.let { runCatching { windowManager.updateViewLayout(it, params) } }
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
