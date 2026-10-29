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
import android.view.View.MeasureSpec
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
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
 * O painel se chama só **"00"** e é organizado em **categorias (abas)** — Monitor,
 * Toque, Motor, Processos e Atalhos. Antes tudo saía numa lista corrida e, no
 * meio da partida, achar um botão era lento; agora cada aba mostra só o que
 * interessa.
 *
 * **Tamanho**: a janela tem **largura fixa** ([panelWidth], ~46% da tela) para
 * não mudar de tamanho ao trocar de aba, e a altura acompanha o conteúdo até um
 * teto ([panelMaxHeight], ~50% da tela) — aba curta fica baixa, aba longa rola.
 * Minimizada ela vira um quadrado fixo de [BUBBLE_DP] com o ícone do app.
 *
 * **Visual**: os botões são pílulas de vidro (fundo translúcido + brilho na cor
 * de destaque) e a janela pede *blur* por trás (Android 12+ com "cross-window
 * blur" ligado); onde o sistema não permite, o fundo translúcido mantém o mesmo
 * aspecto. A cor de destaque e a fonte são as escolhidas no painel ([OtmUi]),
 * então o flutuante acompanha o tema do app.
 *
 * **Minimizado ele vira só o ícone do app**: o painel inteiro some e sobra o
 * ícone do "Trix", que continua arrastável. Um toque no ícone devolve
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
    private var statusText: TextView? = null
    private var content: LinearLayout? = null
    /** Onde a lista de "Rodando agora" é montada (aba Processos). */
    private var procListBox: LinearLayout? = null

    /** Lista de TODOS os apps instalados (exceções do "não encerrar"). */
    private var procAllBox: LinearLayout? = null
    /** Onde a grade do monitor é montada (aba Monitor). */
    private var monitorBox: LinearLayout? = null
    private val tabChips = mutableListOf<TextView>()
    /** Fontes já carregadas do asset: não reler o .ttf a cada texto criado. */
    private val fontCache = HashMap<String, Typeface>()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIF_ID, buildNotification())
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        OtmUi.load(this)
        // o painel avisa quando o usuário troca a cor/fonte: o flutuante se redesenha
        OtmUi.onChanged = { post { rebuild() } }
        addOverlay()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        return START_STICKY
    }

    override fun onDestroy() {
        OtmUi.onChanged = null
        scope.cancel()
        root?.let { runCatching { windowManager.removeView(it) } }
        root = null
        panel = null
        bubble = null
        super.onDestroy()
    }

    /** Reconstrói a janela com a aparência atual (cor/fonte novas do painel). */
    private fun rebuild() {
        val atual = root ?: return
        // a posição é copiada ANTES de remover: a janela nova nasce onde a antiga estava
        val pos = (atual.layoutParams as? WindowManager.LayoutParams)
        val onde = if (pos != null) pos.x to pos.y else null
        val eraMinimizado = minimized
        runCatching { windowManager.removeView(atual) }
        root = null; panel = null; bubble = null
        minimized = false
        addOverlay(onde)
        if (eraMinimizado) setMinimized(true)
    }

    // ---- janela --------------------------------------------------------------

    private fun addOverlay(onde: Pair<Int, Int>? = null) {
        val box = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = rounded(dp(18).toFloat(), "#E61A1815", "#3A3733")
            setPadding(dp(12), dp(10), dp(12), dp(10))
            elevation = dp(12).toFloat()
        }
        box.addView(titleBar())
        box.addView(tabBar())

        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        // A janela tem LARGURA FIXA (ver [panelWidth]): com WRAP_CONTENT cada
        // aba media um tamanho diferente e o painel "pulava" de largura ao
        // trocar de aba. A ALTURA acompanha o conteúdo até um teto — aba curta
        // fica baixa e aba longa rola, em vez de reservar um bloco vazio alto.
        val rolagem = object : ScrollView(this) {
            override fun onMeasure(w: Int, h: Int) {
                val teto = panelMaxHeight()
                super.onMeasure(w, MeasureSpec.makeMeasureSpec(teto, MeasureSpec.AT_MOST))
            }
        }.apply {
            addView(content, LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                LinearLayout.LayoutParams.WRAP_CONTENT,
            ))
        }
        box.addView(rolagem, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT,
        ))

        statusText = TextView(this).apply {
            setTextColor(col(C_MUTED))
            textSize = 11f
            typeface = bodyTypeface()
            setPadding(0, dp(6), 0, 0)
        }
        box.addView(statusText)

        selectTab(0)
        panel = box
        bubble = bubbleView()
        root = box

        val p = baseParams(panelWidth())
        if (onde != null) { p.x = onde.first; p.y = onde.second }
        applyBlur(p)
        box.setOnTouchListener(dragger(p, box))
        runCatching { windowManager.addView(box, p) }
    }

    /**
     * Pede o *blur* do fundo atrás da janela (Android 12+). Precisa que o
     * aparelho suporte "cross-window blur"; quando não suporta, o fundo
     * translúcido do painel já dá o efeito de vidro.
     */
    private fun applyBlur(p: WindowManager.LayoutParams) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        runCatching {
            p.flags = p.flags or WindowManager.LayoutParams.FLAG_BLUR_BEHIND
            p.blurBehindRadius = dp(18)
        }
    }

    /**
     * Abas: cada categoria mostra só o seu bloco, sem lista corrida.
     *
     * Em DUAS linhas (3 + 2). Cinco rótulos numa linha só, dentro de um painel
     * estreito, ficariam ilegíveis ou cortados; em duas linhas cada chip tem
     * largura de sobra e a barra fica sempre do mesmo tamanho.
     */
    private fun tabBar(): View {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        tabChips.clear()
        var linha: LinearLayout? = null
        for ((i, name) in TABS.withIndex()) {
            if (i % TAB_COLS == 0) {
                linha = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                col.addView(linha, matchWrap())
            }
            val chip = tabChip(name, i)
            tabChips.add(chip)
            linha!!.addView(chip)
        }
        // a última linha tem menos chips: completa com espaçadores para os chips
        // ficarem alinhados com os de cima (senão o último "esticava" sozinho)
        val faltam = (TAB_COLS - (TABS.size % TAB_COLS)) % TAB_COLS
        repeat(faltam) {
            linha!!.addView(View(this), LinearLayout.LayoutParams(
                0, 1, 1f,
            ).apply { marginEnd = dp(4) })
        }
        return col
    }

    private fun tabChip(label: String, index: Int): TextView =
        TextView(this).apply {
            text = label
            textSize = 10.5f
            gravity = Gravity.CENTER
            typeface = bodyTypeface()
            setPadding(dp(6), dp(7), dp(6), dp(7))
            setOnClickListener { selectTab(index) }
            layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
            ).apply { marginEnd = dp(4); bottomMargin = dp(4) }
        }

    private fun selectTab(index: Int) {
        val box = content ?: return
        box.removeAllViews()
        // a lista de processos é recriada a cada visita à aba: não segurar view removida
        procListBox = null
        procAllBox = null
        // idem para o monitor: parar o auto-refresh da aba que saiu de cena
        monitorBox = null
        box.addView(tabView(index), matchWrap())
        for ((i, chip) in tabChips.withIndex()) {
            val on = i == index
            chip.setTextColor(col(if (on) accentInk() else C_TEXT))
            chip.background = if (on) pill(dp(11).toFloat(), accent())
            else pill(dp(11).toFloat(), C_GLASS, C_LINE)
            chip.setTypeface(bodyTypeface(), if (on) Typeface.BOLD else Typeface.NORMAL)
        }
    }

    /**
     * Conteúdo de cada aba. A ORDEM tem de casar com [TABS]: a barra de abas
     * passa o índice do rótulo, então um `when` fora de sincronia mostraria o
     * conteúdo de uma aba no rótulo de outra (o FPS saía em "Processos").
     */
    private fun tabView(index: Int): View = when (index) {
        0 -> monitorTab()
        1 -> gameTab()
        2 -> touchTab()
        3 -> engineTab()
        4 -> procTab()
        else -> shortcutsTab()
    }

    /**
     * Aba Monitor: o consumo REAL do aparelho durante a partida, com o **FPS
     * real do jogo** em destaque.
     *
     * Os números vêm do `panel-stats.sh` (o mesmo da home) e o FPS do
     * `SurfaceFlinger` — são os frames que o jogo realmente apresentou, não a
     * taxa de tela. Campo que o aparelho não expõe fica "—"; nada de estimativa.
     */
    private fun monitorTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(sectionHeader("Ao vivo"))
        val grade = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(grade, matchWrap())
        monitorBox = grade
        loadMonitor()
        return box
    }

    /** Lê o consumo real e monta a grade do monitor (atualiza a cada 4 s). */
    private fun loadMonitor() {
        val box = monitorBox ?: return
        scope.launch {
            val res = OtmExec.run(this@OverlayService, OtmRunner.current, "panel-stats.sh", emptyList())
            val s = parseStats(joinOutput(res.stdout, res.stderr))
            post {
                box.removeAllViews()
                for (linha in monitorRows(s)) box.addView(linha)
                box.addView(TextView(this@OverlayService).apply {
                    text = "atualizar"
                    textSize = 11f
                    setTextColor(col(accent()))
                    typeface = bodyTypeface()
                    setPadding(0, dp(8), 0, 0)
                    setOnClickListener { loadMonitor() }
                })
                // enquanto a aba Monitor estiver aberta, se atualiza sozinha
                postDelayed(4000) { if (monitorBox === box) loadMonitor() }
            }
        }
    }

    /** Uma métrica por linha: rótulo à esquerda, valor à direita. */
    private fun monitorRow(rotulo: String, valor: String, destaque: Boolean = false): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        row.addView(TextView(this).apply {
            text = rotulo
            textSize = 11.5f
            setTextColor(col(C_MUTED))
            typeface = bodyTypeface()
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(TextView(this).apply {
            text = valor
            textSize = if (destaque) 15f else 12.5f
            setTextColor(col(if (destaque) accent() else C_TEXT))
            typeface = bodyTypeface()
            setPadding(dp(6), dp(2), 0, dp(2))
        })
        return row
    }

    /** Monta as linhas do monitor com o que o aparelho realmente informou. */
    private fun monitorRows(s: Map<String, String>): List<View> {
        val linhas = ArrayList<View>()
        val fps = s["fps"]?.takeIf { it.isNotEmpty() }
        val hz = s["refresh_peak"]?.takeIf { it.isNotEmpty() } ?: s["refresh_hz"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow("FPS do jogo", fps ?: "—", destaque = true))
        linhas.add(monitorRow("Teto da tela", if (hz != null) "$hz Hz" else "—"))
        fun pct(k: String) = s[k]?.takeIf { it.isNotEmpty() }?.let { "$it%" } ?: "—"
        fun mb(k: String) = s[k]?.takeIf { it.isNotEmpty() }?.let { "$it MB" } ?: "—"
        linhas.add(monitorRow("RAM em uso", pct("ram_uso_pct")))
        linhas.add(monitorRow("RAM livre", mb("ram_livre_mb")))
        linhas.add(monitorRow("CPU", pct("cpu_uso_pct")))
        val mhz = s["cpu_cur_mhz"]?.takeIf { it.isNotEmpty() }
        val maxMhz = s["cpu_max_mhz"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow("Frequência", if (mhz != null) "$mhz${if (maxMhz != null) "/$maxMhz" else ""} MHz" else "—"))
        val cores = s["ncores"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow("Núcleos", if (cores != null) cores else "—"))
        val gov = s["cpu_gov"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow("Governador", if (gov != null) gov else "—"))
        val temp = s["bat_temp_c"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow("Temperatura", if (temp != null) "$temp °C" else "—"))
        val bat = s["bat_level"]?.takeIf { it.isNotEmpty() }
        val st = s["bat_status"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow("Bateria", if (bat != null) "$bat%${if (st != null) " · $st" else ""}" else "—"))
        val saude = s["vital_health"]?.takeIf { it.isNotEmpty() }
        val ciclos = s["vital_cycles"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow(
            "Saúde da bateria",
            if (saude != null) "$saude%${if (ciclos != null) " · $ciclos ciclos" else ""}" else "—",
        ))
        val storLivre = s["stor_livre_mb"]?.takeIf { it.isNotEmpty() }
        val storTotal = s["stor_total_mb"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow(
            "Armazenamento",
            if (storLivre != null) "$storLivre${if (storTotal != null) "/$storTotal" else ""} MB" else "—",
        ))
        if (fps == null) {
            linhas.add(procNote("sem FPS: abra o jogo (o painel precisa dele na tela)"))
        }
        return linhas
    }

    /**
     * Lê o JSON de uma linha do `panel-stats.sh` (o mesmo formato da home).
     * O JSON é plano e de strings, então um parser simples basta — e não
     * arrasta uma dependência só para ler 20 campos.
     */
    private fun parseStats(out: String): Map<String, String> {
        val map = HashMap<String, String>()
        for (linha in out.split("\n")) {
            val t = linha.trim()
            if (!t.startsWith("{")) continue
            for (m in Regex("\"([a-z_0-9]+)\"\\s*:\\s*\"([^\"]*)\"").findAll(t)) {
                map[m.groupValues[1]] = m.groupValues[2]
            }
            break
        }
        return map
    }

    /**
     * Aba Toque: sensibilidade e resposta do dedo — o que se mexe no meio da
     * partida quando a mira não está encaixando.
     *
     * Cada botão chama o MESMO script do painel principal (`ff-touch.sh` para os
     * perfis de toque, `sensi.sh` para o cálculo da sensi, `adb-tweaks.sh` para a
     * resposta do dedo) — nada é reimplementado aqui.
     */
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
        box.addView(procNote("perfis do pack: troca a resposta do toque no jogo"))
        val tRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        tRow.addView(smallButton("Ver perfil") { runScript("ff-touch.sh", listOf("list"), "Perfis de toque") })
        tRow.addView(smallButton("Restaurar") { runScript("ff-touch.sh", listOf("restore"), "Toque restaurado") })
        box.addView(tRow, matchWrap())

        box.addView(sectionHeader("Sensi (mira)"))
        box.addView(procNote("só calcula os valores do seu aparelho — não altera nada"))
        var sRow: LinearLayout? = null
        for ((i, s) in SENSI_PROFILES.withIndex()) {
            if (i % 2 == 0) {
                sRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                box.addView(sRow, matchWrap())
            }
            sRow!!.addView(smallButton(s.second) {
                runScript("sensi.sh", listOf("calc", s.first), "Sensi: ${s.second}")
            })
        }
        val sRow2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        sRow2.addView(smallButton("Ler a minha") { runScript("sensi.sh", listOf("analyze"), "Sensi lida") })
        sRow2.addView(smallButton("Ordem do FF") { runScript("sensi.sh", listOf("ff"), "Sensi (ordem FF)") })
        box.addView(sRow2, matchWrap())

        box.addView(sectionHeader("Resposta do dedo"))
        var dRow: LinearLayout? = null
        for ((i, d) in TOUCH_LEVELS.withIndex()) {
            if (i % 2 == 0) {
                dRow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                box.addView(dRow, matchWrap())
            }
            dRow!!.addView(smallButton(d.second) {
                runScript("adb-tweaks.sh", listOf("touch_latency", d.first, "350", "0", "4"), "Toque: ${d.second}")
            })
        }
        val dRow2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        dRow2.addView(smallButton("Multitouch 300") {
            runScript("adb-tweaks.sh", listOf("touch_multi", "300"), "Multitouch 300ms")
        })
        dRow2.addView(smallButton("Multitouch 150") {
            runScript("adb-tweaks.sh", listOf("touch_multi", "150"), "Multitouch 150ms")
        })
        box.addView(dRow2, matchWrap())
        return box
    }

    /**
     * Aba Jogo: o que só faz sentido com a partida aberta — resolução, modo do
     * app, anti-relog e o estado atual do tuning.
     */
    private fun gameTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        box.addView(sectionHeader("Desempenho do jogo"))
        box.addView(procNote("o flutuante não sabe qual é o jogo: o script resolve (auto)"))
        val perf = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        perf.addView(smallButton("Performance") {
            runScript("game-per-app.sh", listOf("mode", "auto", "performance"), "Jogo: performance")
        })
        perf.addView(smallButton("Padrão") {
            runScript("game-per-app.sh", listOf("mode", "auto", "standard"), "Jogo: padrão")
        })
        box.addView(perf, matchWrap())

        box.addView(sectionHeader("Anti-relog (não fechar)"))
        box.addView(procNote("aplica ao jogo escolhido no pack (sem escolha, o Free Fire)"))
        val relog = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        relog.addView(smallButton("Ligar") {
            runScript("adb-tweaks.sh", listOf("game"), "Anti-relog ligado")
        })
        relog.addView(smallButton("Abrir o jogo") {
            runScript("adb-tweaks.sh", listOf("game_open"), "Abrindo o jogo")
        })
        box.addView(relog, matchWrap())

        box.addView(sectionHeader("Resolução (mais FPS)"))
        box.addView(procNote("reduz a resolução de renderização — reinicie o jogo"))
        var jrow: LinearLayout? = null
        for ((i, g) in GAME_SCALES.withIndex()) {
            if (i % 2 == 0) {
                jrow = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                box.addView(jrow, matchWrap())
            }
            // "auto" deixa o script resolver o jogo (escolhido no pack, ou o app
            // em primeiro plano) — o flutuante não tem como saber qual é o jogo.
            jrow!!.addView(smallButton(g.second) {
                runScript("game-per-app.sh", listOf("apply", "auto", g.first), "Resolução: ${g.second}")
            })
        }
        val jreset = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        jreset.addView(smallButton("Reset resolução") {
            runScript("game-per-app.sh", listOf("reset", "auto"), "Resolução restaurada")
        })
        jreset.addView(smallButton("Ver tuning") {
            runScript("game-per-app.sh", listOf("show", "auto"), "Tuning do jogo")
        })
        box.addView(jreset, matchWrap())

        box.addView(sectionHeader("Extras do jogo"))
        val extra = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        extra.addView(smallButton("Otimizar agora") {
            runScript("smart-opt.sh", listOf("auto"), "Otimização inteligente")
        })
        extra.addView(smallButton("Otimizar +") {
            runScript("adb-tweaks.sh", listOf("game_tune"), "Tuning do jogo")
        })
        box.addView(extra, matchWrap())

        val extra2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        extra2.addView(smallButton("Compilar jogo") {
            runScript("turbo.sh", listOf("art-all", "speed-profile"), "Compilando apps")
        })
        extra2.addView(smallButton("Abrir mais rápido") {
            runScript("turbo.sh", listOf("dexopt-bg"), "bg-dexopt")
        })
        box.addView(extra2, matchWrap())
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

        // Resolução de tela: é o ajuste que MAIS rende FPS, então tem de estar
        // no meio da partida, não só no painel principal. Os degraus vão do mais
        // leve (mais FPS) ao mais nítido; "Fábrica" desfaz.
        box.addView(sectionHeader("Resolução (mais FPS)"))
        var rowRes: LinearLayout? = null
        for ((i, r) in RESOLUTIONS.withIndex()) {
            if (i % 2 == 0) {
                rowRes = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                box.addView(rowRes, matchWrap())
            }
            rowRes!!.addView(smallButton(r.second) {
                runScript("resolution.sh", listOf("apply", r.first), "Resolução: ${r.second}")
            })
        }
        val rowFab = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        rowFab.addView(smallButton("Automático") {
            runScript("resolution.sh", listOf("auto"), "Resolução automática")
        })
        rowFab.addView(smallButton("Fábrica") {
            runScript("resolution.sh", listOf("reset"), "Resolução de fábrica")
        })
        box.addView(rowFab, matchWrap())
        return box
    }

    /**
     * Aba Processos: o gerenciador de segundo plano para usar no meio da partida.
     *
     * - escolhe quantos apps o sistema mantém em cache (limite de 2º plano);
     * - lista os apps rodando agora, com a RAM de cada um;
     * - "Encerrar todos" fecha o 2º plano poupando o jogo, o 1º plano e as
     *   exceções;
     * - "Exceção" marca um app que nunca deve ser encerrado (ex.: a live do
     *   TikTok, que fecha se você encerrar tudo).
     *
     * O app em 1º plano é identificado na hora; a lista e as exceções vêm do
     * `proc-mgr.sh` (fonte única, a mesma do painel principal).
     */
    private fun procTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        box.addView(sectionHeader("Processos em 2º plano"))
        var row: LinearLayout? = null
        for ((i, l) in PROC_LIMITS.withIndex()) {
            if (i % 2 == 0) {
                row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                box.addView(row, matchWrap())
            }
            row!!.addView(smallButton(l.second) {
                runScript("adb-tweaks.sh", listOf("proc_limit", l.first), "Limite: ${l.second}")
            })
        }

        box.addView(sectionHeader("Ações"))
        val row1 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row1.addView(smallButton("Encerrar todos") {
            runScript("proc-mgr.sh", listOf("kill"), "Encerrar todos")
        })
        row1.addView(smallButton("RAM agora") {
            runScript("ram-boost.sh", listOf("boost", "normal"), "Liberar RAM")
        })
        box.addView(row1, matchWrap())

        box.addView(sectionHeader("Exceção: não encerrar"))
        val row2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row2.addView(smallButton("App em 1º plano") {
            runScript("proc-mgr.sh", listOf("keep-fg"), "Exceção (1º plano)")
        })
        row2.addView(smallButton("Ver exceções") {
            runScript("proc-mgr.sh", listOf("keep-list"), "Exceções")
        })
        box.addView(row2, matchWrap())

        box.addView(sectionHeader("Rodando agora"))
        val lista = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(lista, matchWrap())
        procListBox = lista
        loadProcList()

        // Proteger um app que NÃO está rodando agora (ex.: o do banco): a lista
        // "rodando agora" só tem quem está vivo neste instante.
        box.addView(sectionHeader("Todos os apps"))
        box.addView(procNote("toque em um app para ele NUNCA ser encerrado"))
        val todos = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(todos, matchWrap())
        procAllBox = todos
        loadAllApps()
        return box
    }

    /** Todos os apps instalados, com o chip de exceção (liga/desliga). */
    private fun loadAllApps() {
        val box = procAllBox ?: return
        scope.launch {
            val res = OtmExec.run(this@OverlayService, OtmRunner.current, "proc-mgr.sh", listOf("apps"))
            val linhas = parseProcList(joinOutput(res.stdout, res.stderr))
            post {
                if (procAllBox !== box) return@post
                box.removeAllViews()
                if (linhas.isEmpty()) box.addView(procNote("nenhum app de usuário instalado"))
                else for (p in linhas) box.addView(procRow(p))
            }
        }
    }

    /** Mostra os apps rodando agora, com a RAM de cada um e o que está poupado. */
    private fun loadProcList() {
        val box = procListBox ?: return
        box.removeAllViews()
        box.addView(procNote("carregando…"))
        scope.launch {
            val res = OtmExec.run(this@OverlayService, OtmRunner.current, "proc-mgr.sh", listOf("list"))
            val linhas = parseProcList(joinOutput(res.stdout, res.stderr))
            post {
                box.removeAllViews()
                if (linhas.isEmpty()) {
                    box.addView(procNote("nenhum app rodando (fora o pack)"))
                } else {
                    for (p in linhas) box.addView(procRow(p))
                }
                val rodando = TextView(this@OverlayService).apply {
                    text = "atualizar lista"
                    textSize = 11f
                    setTextColor(col(accent()))
                    typeface = bodyTypeface()
                    setPadding(0, dp(8), 0, 0)
                    setOnClickListener { loadProcList() }
                }
                box.addView(rodando)
            }
        }
    }

    /** Uma linha por app rodando: nome (ou pacote), RAM e o estado da exceção. */
    private fun procRow(p: ProcInfo): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val nome = TextView(this).apply {
            text = appLabel(p.pkg)
            textSize = 11.5f
            setTextColor(col(C_TEXT))
            typeface = bodyTypeface()
            maxLines = 1
        }
        row.addView(nome, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        row.addView(TextView(this).apply {
            text = if (p.ramMb > 0) "${p.ramMb}MB" else "—"
            textSize = 11f
            setTextColor(col(C_MUTED))
            typeface = bodyTypeface()
            setPadding(dp(6), 0, dp(6), 0)
        })
        // toque na linha: cria/remove a exceção deste app (o "X não encerra")
        val chip = TextView(this).apply {
            text = if (p.protegido) "não encerra" else "exceção"
            textSize = 10.5f
            gravity = Gravity.CENTER
            typeface = bodyTypeface()
            setTextColor(col(if (p.protegido) accentInk() else accent()))
            background = if (p.protegido) pill(dp(10).toFloat(), accent())
            else pill(dp(10).toFloat(), C_GLASS, accentA(0x66))
            setPadding(dp(8), dp(4), dp(8), dp(4))
            setOnClickListener {
                runScript(
                    "proc-mgr.sh",
                    listOf(if (p.protegido) "unkeep" else "keep", p.pkg),
                    if (p.protegido) "Exceção removida" else "Exceção criada",
                )
                postDelayed({ loadProcList() }, 900)
            }
        }
        row.addView(chip)
        return row
    }

    private fun procNote(txt: String): TextView =
        TextView(this).apply {
            text = txt
            textSize = 11f
            setTextColor(col(C_MUTED))
            typeface = bodyTypeface()
        }

    /** Nome legível do app; se o sistema não der, cai no próprio pacote. */
    private fun appLabel(pkg: String): String = try {
        val pm = packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Throwable) {
        pkg
    }

    /**
     * Aba Atalhos: o resto do ajuste de meio-de-partida, em blocos curtos.
     *
     * Cada botão chama o MESMO script que o painel principal usa — nada é
     * reimplementado aqui (o flutuante não pode divergir do painel). O que é
     * específico de jogo mora na aba **Jogo**; aqui ficam rede, tela, limpeza,
     * avisos, barras e snapshot.
     */
    private fun shortcutsTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        box.addView(sectionHeader("Rede e latência"))
        val rede = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        rede.addView(smallButton("Latência") { runScript("adb-tweaks.sh", listOf("latency"), "Latência") })
        rede.addView(smallButton("Latência off") { runScript("adb-tweaks.sh", listOf("latency_reset"), "Latência restaurada") })
        box.addView(rede, matchWrap())

        val rede2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        rede2.addView(smallButton("DNS gamer") { runScript("dns.sh", listOf("gaming"), "DNS gaming") })
        rede2.addView(smallButton("DNS auto") { runScript("dns.sh", listOf("auto"), "DNS automático") })
        box.addView(rede2, matchWrap())

        val rede3 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        rede3.addView(smallButton("Rede/TCP") { runScript("adb-tweaks.sh", listOf("net"), "Rede/TCP") })
        rede3.addView(smallButton("Rede off") { runScript("adb-tweaks.sh", listOf("net_reset"), "Rede restaurada") })
        box.addView(rede3, matchWrap())

        val rede4 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        rede4.addView(smallButton("Medir ping") { runScript("dns.sh", listOf("bench"), "Ping do DNS") })
        rede4.addView(smallButton("Wi-Fi") { runScript("adb-tweaks.sh", listOf("wifi"), "Ajustes de Wi-Fi") })
        box.addView(rede4, matchWrap())

        box.addView(sectionHeader("Tela e fluidez"))
        var row: LinearLayout? = null
        for ((i, r) in REFRESH_RATES.withIndex()) {
            if (i % 2 == 0) {
                row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
                box.addView(row, matchWrap())
            }
            row!!.addView(smallButton(r.second) {
                // "auto" destrava (volta ao dinâmico); os Hz fixos travam
                // min=peak e evitam a tela oscilar no meio da partida.
                val args = if (r.first == "auto") listOf("refresh", "auto")
                else listOf("refresh_fixed", r.first)
                runScript("turbo.sh", args, "Tela: ${r.second}")
            })
        }
        val fixo = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fixo.addView(smallButton("Perf. fixo") { runScript("turbo.sh", listOf("perfmode", "on"), "Desempenho fixo") })
        fixo.addView(smallButton("Perf. off") { runScript("turbo.sh", listOf("perfmode", "off"), "Desempenho normal") })
        box.addView(fixo, matchWrap())

        val fluidez = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        fluidez.addView(smallButton("Fluidez") { runScript("adb-tweaks.sh", listOf("fluidez"), "Fluidez") })
        fluidez.addView(smallButton("GPU") { runScript("adb-tweaks.sh", listOf("gpu"), "Ajustes de GPU") })
        box.addView(fluidez, matchWrap())

        box.addView(sectionHeader("Durante a partida"))
        val partida = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        partida.addView(smallButton("Foco de jogo") { runScript("adb-tweaks.sh", listOf("game_focus"), "Foco de jogo") })
        partida.addView(smallButton("Foco off") { runScript("adb-tweaks.sh", listOf("game_focus_off"), "Foco desligado") })
        box.addView(partida, matchWrap())

        val limpeza = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        limpeza.addView(smallButton("Limpar RAM") { runScript("clean.sh", listOf("now", "fundo"), "Limpeza") })
        limpeza.addView(smallButton("RAM máximo") { runScript("ram-boost.sh", listOf("boost", "max"), "RAM máxima") })
        box.addView(limpeza, matchWrap())

        val congelar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        congelar.addView(smallButton("Hibernar") { runScript("turbo.sh", listOf("hibernate", "now"), "Hibernar apps") })
        congelar.addView(smallButton("Poda caches") { runScript("turbo.sh", listOf("trim"), "Caches podados") })
        box.addView(congelar, matchWrap())

        val congelar2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        congelar2.addView(smallButton("Congelar") { runScript("adb-tweaks.sh", listOf("freezer"), "Congelar apps") })
        congelar2.addView(smallButton("Descongelar") { runScript("adb-tweaks.sh", listOf("freezer_off"), "Congelador desligado") })
        box.addView(congelar2, matchWrap())

        val gameClean = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        gameClean.addView(smallButton("Game Clean") { runScript("game-clean.sh", listOf("on"), "Game Clean") })
        gameClean.addView(smallButton("Game Clean off") { runScript("game-clean.sh", listOf("off"), "Game Clean desligado") })
        box.addView(gameClean, matchWrap())

        val matar = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        matar.addView(smallButton("Matar 2º plano") { runScript("turbo.sh", listOf("killbg"), "2º plano encerrado") })
        matar.addView(smallButton("Phantom on") { runScript("turbo.sh", listOf("phantom", "on"), "Phantom Killer") })
        box.addView(matar, matchWrap())

        box.addView(sectionHeader("Sem interrupção"))
        val avisos = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        avisos.addView(smallButton("Não perturbe") { runScript("adb-tweaks.sh", listOf("dnd"), "DND ligado") })
        avisos.addView(smallButton("DND off") { runScript("adb-tweaks.sh", listOf("dnd_off"), "DND desligado") })
        box.addView(avisos, matchWrap())

        val avisos2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        avisos2.addView(smallButton("Menos avisos") { runScript("adb-tweaks.sh", listOf("notif"), "Heads-up desligado") })
        avisos2.addView(smallButton("Telemetria off") { runScript("turbo.sh", listOf("telemetry", "off"), "Telemetria desligada") })
        box.addView(avisos2, matchWrap())

        box.addView(sectionHeader("Aparência e tela"))
        val visual = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        visual.addView(smallButton("Efeitos off") { runScript("adb-tweaks.sh", listOf("effects", "off"), "Efeitos leves") })
        visual.addView(smallButton("Efeitos on") { runScript("adb-tweaks.sh", listOf("effects", "on"), "Efeitos ligados") })
        box.addView(visual, matchWrap())

        val barras = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        barras.addView(smallButton("Esconder topo") { runScript("adb-tweaks.sh", listOf("sysbars", "so_status"), "Barra de cima") })
        barras.addView(smallButton("Mostrar tudo") { runScript("adb-tweaks.sh", listOf("sysbars", "on"), "Barras visíveis") })
        box.addView(barras, matchWrap())

        val barras2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        barras2.addView(smallButton("Tela cheia") { runScript("adb-tweaks.sh", listOf("sysbars", "off"), "Imersivo") })
        barras2.addView(smallButton("Animações 0") { runScript("adb-tweaks.sh", listOf("perf_max"), "Performance extrema") })
        box.addView(barras2, matchWrap())

        box.addView(sectionHeader("Bateria e sistema"))
        val bat = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        bat.addView(smallButton("Sem economia") { runScript("adb-tweaks.sh", listOf("battery_off"), "Economia desligada") })
        bat.addView(smallButton("Economia") { runScript("adb-tweaks.sh", listOf("battery"), "Economia ligada") })
        box.addView(bat, matchWrap())

        val doze = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        doze.addView(smallButton("Sono off") { runScript("adb-tweaks.sh", listOf("doze", "off"), "Doze desligado") })
        doze.addView(smallButton("Sono on") { runScript("adb-tweaks.sh", listOf("doze", "on"), "Doze ligado") })
        box.addView(doze, matchWrap())

        val perfis = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        perfis.addView(smallButton("Perf. 0.5x") { runScript("adb-tweaks.sh", listOf("perf"), "Animações 0.5x") })
        perfis.addView(smallButton("RAM gaming") { runScript("adb-tweaks.sh", listOf("mem", "gaming"), "RAM gaming") })
        box.addView(perfis, matchWrap())

        val perfis2 = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        perfis2.addView(smallButton("RAM padrão") { runScript("adb-tweaks.sh", listOf("mem", "padrao"), "RAM padrão") })
        perfis2.addView(smallButton("Ver bateria") { runScript("vitality.sh", listOf("diag"), "Saúde da bateria") })
        box.addView(perfis2, matchWrap())

        box.addView(sectionHeader("Snapshot"))
        val snap = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        snap.addView(smallButton("Salvar") { runScript("snapshot.sh", listOf("save", "no-jogo"), "Snapshot salvo") })
        snap.addView(smallButton("Restaurar") { runScript("snapshot.sh", listOf("restore", "latest"), "Snapshot restaurado") })
        box.addView(snap, matchWrap())

        return box
    }

    /** Cabeçalho de seção: separa os blocos do painel. */
    private fun sectionHeader(text: String): View =
        TextView(this).apply {
            this.text = text
            setTextColor(col(accent()))
            textSize = 11.5f
            setTypeface(bodyTypeface(), Typeface.BOLD)
            setPadding(0, dp(8), 0, dp(4))
        }

    /** Barra do topo: arrasta pelo título, minimiza e fecha. */
    private fun titleBar(): View {
        val bar = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        bar.addView(TextView(this).apply {
            text = "00"
            setTextColor(col(accent()))
            textSize = 14f
            setTypeface(bodyTypeface(), Typeface.BOLD)
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        bar.addView(iconButton("—") { toggleMinimize() })
        bar.addView(iconButton("X") { stopSelf() })
        return bar
    }

    /**
     * O app minimizado: só o ícone do app, sem texto — um toque devolve o painel.
     *
     * Usa `ic_launcher_round` (PNG já redondo) e NÃO `ic_launcher`: este último
     * é um *adaptive icon*, que desenha o logo dentro de ~66% do quadro (safe
     * zone). Num ImageView isso dá um logo pequeno perdido num círculo grande —
     * era o que deixava a bolha "esquisita". O PNG redondo preenche o círculo
     * exatamente, então a bolha fica limpa em qualquer densidade.
     */
    private fun bubbleView(): View {
        return FrameLayout(this).apply {
            addView(
                ImageView(this@OverlayService).apply {
                    setImageResource(R.mipmap.ic_launcher_round)
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    setOnClickListener { setMinimized(false) }
                },
                FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                ),
            )
            elevation = dp(12).toFloat()
            setOnClickListener { setMinimized(false) }
        }
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
        // minimizado: quadrado fixo do ícone; aberto: largura fixa do painel.
        val p = baseParams(if (value) dp(BUBBLE_DP) else panelWidth())
        // mantém onde o usuário deixou: a janela nova nasce na mesma posição
        (atual.layoutParams as? WindowManager.LayoutParams)?.let {
            p.x = it.x; p.y = it.y
        }
        applyBlur(p)
        minimized = value
        runCatching {
            windowManager.removeView(atual)
            novo.setOnTouchListener(dragger(p, novo))
            windowManager.addView(novo, p)
            root = novo
        }
    }

    private fun iconButton(label: String, action: () -> Unit): View =
        TextView(this).apply {
            text = label
            textSize = 13f
            setTextColor(col(C_TEXT))
            typeface = bodyTypeface()
            setPadding(dp(11), dp(3), dp(11), dp(3))
            setOnClickListener { action() }
        }

    /**
     * Botão do painel: pílula de vidro (translúcida + borda) com a cor de
     * destaque na borda e no texto. É o "visual melhor" pedido — antes era um
     * retângulo laranja chapado, igual para tudo.
     */
    private fun smallButton(label: String, action: () -> Unit): View =
        TextView(this).apply {
            text = label
            textSize = 11f
            gravity = Gravity.CENTER
            typeface = bodyTypeface()
            setTextColor(col(accent()))
            background = pill(dp(10).toFloat(), C_GLASS, accentA(0x66))
            setPadding(dp(7), dp(7), dp(7), dp(7))
            setOnClickListener { action() }
        }.also {
            it.layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
            ).apply { marginEnd = dp(4); bottomMargin = dp(4) }
        }

    /** Pílula de vidro arredondada com borda opcional. */
    private fun pill(radius: Float, fill: String, stroke: String? = null): GradientDrawable =
        GradientDrawable().apply {
            cornerRadius = radius
            setColor(Color.parseColor(fill))
            if (stroke != null) setStroke(dp(1), Color.parseColor(stroke))
        }

    /** Fundo arredondado com borda opcional (usado no painel e nos chips de aba). */
    private fun rounded(radius: Float, fill: String, stroke: String? = null): GradientDrawable =
        pill(radius, fill, stroke)

    // ---- tema do app (cor de destaque e fonte vêm do painel) -----------------

    /** Cor de destaque escolhida no painel. */
    private fun accent(): String = OtmUi.accent

    /** Tinta do texto sobre a cor de destaque (clara ou escura, conforme o brilho). */
    private fun accentInk(): String = OtmUi.accentInk

    /** Mesma cor de destaque com outra transparência (ex.: borda do botão). */
    private fun accentA(alpha: Int): String =
        String.format("#%02X%s", alpha, accent().removePrefix("#").uppercase())

    /**
     * Fonte escolhida no painel, aplicada ao painel flutuante.
     *
     * Carrega o mesmo `.ttf` empacotado que o painel usa (o overlay não tem
     * WebView, então precisa do arquivo na mão). Fonte sem arquivo — ou que
     * falhe ao carregar — cai numa equivalente do sistema, para o painel nunca
     * ficar sem texto.
     */
    private fun bodyTypeface(): Typeface {
        val key = OtmUi.font
        fontCache[key]?.let { return it }
        val tf = FONT_FILES[key]?.let { file ->
            runCatching { Typeface.createFromAsset(assets, "panel/assets/fonts/$file") }.getOrNull()
        } ?: when (key) {
            "mono", "minecraft", "monocraft", "pixel" -> Typeface.MONOSPACE
            "serifa" -> Typeface.SERIF
            "manuscrita" -> Typeface.create("cursive", Typeface.NORMAL)
            else -> Typeface.create("sans-serif", Typeface.NORMAL)
        }
        fontCache[key] = tf
        return tf
    }

    /** Converte "#RRGGBB" em cor; se vier algo estranho, cai na prata padrão. */
    private fun col(hex: String): Int =
        runCatching { Color.parseColor(hex) }.getOrDefault(Color.parseColor("#C7CCD6"))

    /**
     * Parâmetros da janela. [largura] é fixa (em px) para o painel não mudar de
     * tamanho ao trocar de aba; a altura continua WRAP_CONTENT, limitada pelo
     * teto do ScrollView.
     */
    private fun baseParams(largura: Int = panelWidth()) = WindowManager.LayoutParams(
        largura,
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

    /**
     * Largura do painel: uma fração da tela, com piso e teto em dp. Fixa (e não
     * WRAP_CONTENT) para o painel ter SEMPRE o mesmo tamanho em qualquer aba —
     * antes cada aba media um tamanho e a janela mudava de largura ao trocar.
     * O teto em dp evita que num tablet o painel vire uma faixa enorme.
     */
    private fun panelWidth(): Int {
        val tela = resources.displayMetrics.widthPixels
        return (tela * PANEL_W_FRAC).toInt().coerceIn(dp(240), dp(420))
    }

    /** Teto de altura do conteúdo: o resto da tela fica livre para o jogo. */
    private fun panelMaxHeight(): Int =
        (resources.displayMetrics.heightPixels * PANEL_H_FRAC).toInt().coerceAtLeast(dp(160))

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

    private fun post(block: () -> Unit) = android.os.Handler(mainLooper).post(block)

    private fun postDelayed(ms: Long, block: () -> Unit) =
        android.os.Handler(mainLooper).postDelayed(block, ms)

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
        return b.setContentTitle("Trix")
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

        /** "Vidro": fundo translúcido e borda clara (o blur do sistema soma). */
        private const val C_GLASS = "#1FFFFFFF"
        private const val C_LINE = "#33FFFFFF"
        private const val C_TEXT = "#F3EFE7"
        private const val C_MUTED = "#B9B2A6"

        /**
         * Largura do painel: fração da tela, com piso/teto em dp ([panelWidth]).
         * 0.70 num aparelho de 360 dp dá ~252 dp — largura de painel de verdade.
         * Antes era 0.46 (~170 dp) e o conteúdo ficava apertado, "fino".
         */
        private const val PANEL_W_FRAC = 0.70f
        /** Teto de altura do conteúdo (o resto da tela fica para o jogo). */
        private const val PANEL_H_FRAC = 0.62f
        /** Lado do ícone minimizado (quadrado, sempre igual em qualquer aparelho). */
        private const val BUBBLE_DP = 56

        /**
         * Fontes empacotadas (mesmos `.ttf` do painel), por chave do `FONTS` do
         * HTML. O que não estiver aqui cai na fonte do sistema.
         */
        private val FONT_FILES = mapOf(
            "minecraft" to "monocraft.ttf",
            "monocraft" to "monocraft.ttf",
            "pixel" to "pressstart2p.ttf",
            "cartaz" to "anton.ttf",
            "condensada" to "bebasneue.ttf",
            "futurista" to "orbitron.ttf",
            "quadrada" to "russoone.ttf",
            "serifa" to "playfairdisplay.ttf",
            "manuscrita" to "caveat.ttf",
            "mono" to "jetbrainsmono.ttf",
        )

        /**
         * Categorias do painel, na ordem das abas (casa com [tabView]).
         * O FPS fica na PRIMEIRA: é o que se abre no meio da partida.
         */
        private val TABS = listOf("Monitor", "Jogo", "Toque", "Motor", "Processos", "Atalhos")
        /** Abas por linha: 6 rótulos numa linha só não cabem no painel. */
        private const val TAB_COLS = 3

        /** Perfis de sensi do `sensi.sh calc <perfil>` (só cálculo, não altera). */
        private val SENSI_PROFILES = listOf(
            "padrao" to "Padrão",
            "headshot" to "Headshot",
            "spray" to "Spray",
            "sniper" to "Sniper",
            "speed" to "Speed",
        )

        /**
         * Resposta do dedo (`adb-tweaks.sh touch_latency <tr> 350 0 4`). O valor é
         * a responsividade 1..1000: menor = o toque responde mais cedo. Os
         * mesmos degraus que o `ff-touch.sh` usa nos perfis, para não inventar
         * número que o pack não usa.
         */
        private val TOUCH_LEVELS = listOf(
            "95" to "Preciso (95)",
            "100" to "Padrão (100)",
            "110" to "Rápido (110)",
            "120" to "Ultra (120)",
        )

        /** Taxas de tela fixas aceitas por `turbo.sh refresh_fixed <hz>`. */
        private val REFRESH_RATES = listOf(
            "60" to "60 Hz",
            "90" to "90 Hz",
            "120" to "120 Hz",
            "auto" to "Automática",
        )

        /**
         * Downscale do jogo (reduz a resolução de renderização = mais FPS).
         * Os valores são os mesmos perfis do `game-per-app.sh`: 0.9 quase
         * imperceptível, 0.5 serrilhado mas o mais leve.
         */
        private val GAME_SCALES = listOf(
            "fps" to "FPS (0.9)",
            "balanced" to "Equilíbrio",
            "max" to "Máx (0.5)",
        )

        /** Limite de processos em 2º plano aceito por `adb-tweaks.sh proc_limit`. */
        private val PROC_LIMITS = listOf(
            "4" to "4 · jogo",
            "8" to "8 · meio",
            "32" to "32 · multitarefa",
            "padrao" to "Padrão",
        )

        /**
         * Degraus de resolução aceitos por `resolution.sh apply <WxH>`, do mais
         * leve (mais FPS) ao mais nítido. São os mesmos perfis que o módulo
         * oferece, para o flutuante e o painel principal nunca divergirem.
         */
        private val RESOLUTIONS = listOf(
            "540x960" to "540p",
            "720x1280" to "720p",
            "720x1600" to "720p+",
            "1080x2340" to "1080p",
            "1440x2560" to "1440p",
        )

        /** Um app rodando, lido das linhas `#OTM-PROC` do `proc-mgr.sh list`. */
        private data class ProcInfo(val pkg: String, val ramMb: Int, val protegido: Boolean)

        /**
         * Lê as linhas `#OTM-PROC pkg=… ram=… protected=…` que o `proc-mgr.sh`
         * emite. Ignora qualquer outra linha (avisos, cores, o `#OTM-RESULT`).
         */
        private fun parseProcList(out: String): List<ProcInfo> {
            val list = ArrayList<ProcInfo>()
            for (line in out.split("\n")) {
                val t = line.trim()
                val pre = when {
                    t.startsWith("#OTM-PROC") -> "#OTM-PROC"
                    t.startsWith("#OTM-APP") -> "#OTM-APP"
                    else -> continue
                }
                var pkg = ""; var ram = 0; var prot = false
                for (tok in t.removePrefix(pre).trim().split(Regex("\\s+"))) {
                    val i = tok.indexOf('=')
                    if (i <= 0) continue
                    when (tok.substring(0, i)) {
                        "pkg" -> pkg = tok.substring(i + 1)
                        "ram" -> ram = tok.substring(i + 1).toIntOrNull() ?: 0
                        "protected" -> prot = tok.substring(i + 1) == "1"
                    }
                }
                if (pkg.isNotEmpty()) list.add(ProcInfo(pkg, ram, prot))
            }
            // "Rodando agora" ordena por RAM; a lista de instalados é alfabética.
            return if (list.any { it.ramMb > 0 }) list.sortedByDescending { it.ramMb }
            else list.sortedBy { it.pkg }
        }

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

        /** Retorno de `onStartCommand`: mantém o serviço vivo entre partidas. */

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
