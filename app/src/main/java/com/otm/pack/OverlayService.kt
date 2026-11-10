package com.otm.pack

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.text.InputType
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.View.MeasureSpec
import android.view.WindowManager
import android.view.inputmethod.InputMethodManager
import android.widget.EditText
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
import org.json.JSONObject
import rikka.shizuku.Shizuku

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
 * Shizuku/ADB. Se o Android matar o processo do painel no meio da partida (é o
 * que as próprias ações de limpeza fazem), o estático [OtmRunner] volta nulo e
 * NENHUMA ação do flutuante funcionava — dava erro em tudo. Como o
 * `ShizukuProvider` está no manifesto, o Service se recupera sozinho: reconecta
 * o Shizuku (a permissão já foi concedida) sem precisar abrir o app.
 */
class OverlayService : Service() {

    private lateinit var windowManager: WindowManager
    private val shizuku = ShizukuRunner()
    /** Transporte recuperado pelo próprio Service (ver [shellRunner]). */
    private var runner: ShellRunner? = null
    private var shizukuListener: Shizuku.OnBinderReceivedListener? = null
    private var root: View? = null
    private var panel: View? = null
    private var bubble: View? = null
    private var statusText: TextView? = null
    private var content: LinearLayout? = null
    /** Onde a lista de "Rodando agora" é montada (aba Processos). */
    private var procListBox: LinearLayout? = null
    /** Campo e rótulo da "Menor largura" (aba Atalhos) — relidos a cada troca. */
    private var dpiCampo: EditText? = null
    private var dpiAgora: TextView? = null

    /** Lista de TODOS os apps instalados (exceções do "não encerrar"). */
    private var procAllBox: LinearLayout? = null
    /** Onde a grade do monitor é montada (aba Monitor). */
    private var monitorBox: LinearLayout? = null
    /** Onde a lista de Logs é montada (aba Logs). */
    private var logBox: LinearLayout? = null
    /** Filtro de texto dos Logs (aba Logs) — relido a cada redesenho. */
    private var logFilter: EditText? = null
    /** Só os erros? (aba Logs) */
    private var logOnlyErrors = false
    /** "limpar" pede um segundo toque antes de apagar (sem diálogo no overlay). */
    private var logClearArmed = false
    /** Histórico já lido do disco: o filtro roda em memória, sem reler o arquivo. */
    private var logCache: List<JSONObject> = emptyList()
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
        // densidade atual (para detectar troca de DPI em onConfigurationChanged)
        densidadeAtual = resources.configuration.densityDpi
        // o painel avisa quando o usuário troca a cor/fonte: o flutuante se redesenha
        OtmUi.onChanged = { post { rebuild() } }
        registerShizukuRecovery()
        addOverlay()
    }

    /**
     * Recupera o transporte de shell sem depender da Activity.
     *
     * Se o processo foi reiniciado, [OtmRunner.current] está nulo. Aqui o
     * Service pergunta ao Shizuku (o binder chega pelo `ShizukuProvider`) e, se a
     * permissão já foi concedida, reconecta — a partir daí o overlay volta a
     * funcionar sozinho. Sem Shizuku, as ações seguem avisando "sem acesso".
     *
     * O listener é registrado SEMPRE (não só quando falta transporte): se o
     * binder do Shizuku cair depois, o estático vira nulo e sem isto o flutuante
     * ficaria preso em erro até alguém abrir o app de novo.
     */
    private fun registerShizukuRecovery() {
        try {
            val l = Shizuku.OnBinderReceivedListener { runCatching { autoConnectShizuku() } }
            shizukuListener = l
            Shizuku.addBinderReceivedListenerSticky(l)
        } catch (_: Throwable) {
            // Shizuku não instalado: o aviso de "sem acesso" das ações basta.
        }
        autoConnectShizuku()
    }

    private fun autoConnectShizuku() {
        if (runner != null || OtmRunner.current != null) return
        try {
            if (shizuku.isAvailable() && shizuku.hasPermission()) {
                runner = shizuku
                OtmRunner.current = shizuku
            }
        } catch (_: Throwable) {
        }
    }

    /** Transporte atual: o do processo (se ainda vivo) ou o recuperado aqui. */
    private fun shellRunner(): ShellRunner? = OtmRunner.current ?: runner

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        autoConnectShizuku()
        return START_STICKY
    }

    override fun onDestroy() {
        OtmUi.onChanged = null
        shizukuListener?.let { runCatching { Shizuku.removeBinderReceivedListener(it) } }
        shizukuListener = null
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
     * Em LINHAS de [TAB_COLS]: com 7 rótulos, 3 por linha (3 + 3 + 1) cada chip
     * tem largura de sobra dentro do painel estreito. Numa linha só os rótulos
     * ficariam ilegíveis ou cortados.
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
        // se o usuário estava digitando a largura, o teclado e o foco da janela
        // têm de voltar ao normal ao trocar de aba
        soltarFoco()
        box.removeAllViews()
        // a lista de processos é recriada a cada visita à aba: não segurar view removida
        procListBox = null
        procAllBox = null
        // idem para o monitor: parar o auto-refresh da aba que saiu de cena
        monitorBox = null
        logBox = null
        logFilter = null
        box.addView(tabView(index), matchWrap())
        for ((i, chip) in tabChips.withIndex()) {
            val on = i == index
            chip.setTextColor(col(if (on) accentInk() else C_TEXT))
            chip.background = if (on) pill(dp(11).toFloat(), accent())
            else pill(dp(11).toFloat(), C_GLASS, C_LINE)
            chip.setTypeface(bodyTypeface(), if (on) Typeface.BOLD else Typeface.NORMAL)
        }
        // se as métricas da tela mudaram enquanto o painel estava minimizado/
        // fechado, o reajuste pode não ter chegado: refazer na troca de aba é
        // de graça.
        refitToScreen()
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
        5 -> logTab()
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

    /**
     * Telemetria pelo núcleo nativo (C) — MESMOS campos do `panel-stats.sh`, só
     * os que dá para ler sem processo. Devolve vazio quando a lib não carregou
     * (aparelho/ABI sem suporte), e aí nada muda no comportamento antigo.
     */
    private fun nativeStats(): Map<String, String> {
        val m = LinkedHashMap<String, String>()
        if (!OtmNative.available) return m
        OtmNative.ramAvailableMb()?.let { livre ->
            m["ram_livre_mb"] = livre.toString()
            OtmNative.ramTotalKb().takeIf { it > 0 }?.let { totKb ->
                val totMb = totKb / 1024
                if (totMb > 0) {
                    val uso = ((totMb - livre) * 100 / totMb).coerceIn(0, 100)
                    m["ram_uso_pct"] = uso.toString()
                }
            }
        }
        OtmNative.cpuFreqMhz()?.let { m["cpu_cur_mhz"] = it.toString() }
        OtmNative.cpuPct()?.let { m["cpu_uso_pct"] = it.toString() }
        OtmNative.cpuCores().takeIf { it > 0 }?.let { m["ncores"] = it.toString() }
        OtmNative.thermalC()?.let {
            m["temp_c"] = String.format(java.util.Locale.US, "%.1f", it)
        }
        // --- telemetria estendida (o que o shell só trazia com fork+binder) ---
        // Térmico por TIPO: separa bateria quente de SoC quente. Cada tipo é uma
        // zona diferente e o painel mostra só o que o aparelho realmente expõe.
        for ((tipo, chave) in THERM_KEYS) {
            OtmNative.thermalZoneC(tipo)?.let {
                m[chave] = String.format(java.util.Locale.US, "%.1f", it)
            }
        }
        // GPU: carga real quando o driver expõe (Adreno/Mali). Sem isso, some.
        OtmNative.gpuPct()?.let { m["gpu_pct"] = it.toString() }
        // Bateria: corrente (sinal indica carga/descarga), tensão e carga.
        OtmNative.batteryCurrentMa()?.let {
            m["bat_ma"] = String.format(java.util.Locale.US, "%.0f", it)
        }
        OtmNative.batteryVoltageV()?.let {
            m["bat_v"] = String.format(java.util.Locale.US, "%.2f", it)
        }
        OtmNative.batteryCapacityPct().takeIf { it in 0..100 }?.let { m["bat_pct"] = it.toString() }
        // Pressão de memória (PSI): melhor sinal de aperto do que "RAM livre".
        OtmNative.memPressurePct()?.let {
            m["mem_press"] = String.format(java.util.Locale.US, "%.1f", it)
        }
        OtmNative.swapUsedMb()?.let { m["swap_mb"] = it.toString() }
        // Rede: total desde o boot. O painel calcula a taxa entre leituras.
        OtmNative.netRxBytes().takeIf { it >= 0 }?.let { m["net_rx"] = it.toString() }
        OtmNative.netTxBytes().takeIf { it >= 0 }?.let { m["net_tx"] = it.toString() }
        OtmNative.cpuGovernor()?.let { m["cpu_gov"] = it }
        return m
    }

    /** Lê o consumo real e monta a grade do monitor (atualiza a cada 4 s). */
    private fun loadMonitor() {
        val box = monitorBox ?: return
        if (shellRunner() == null) {
            // Sem shell ainda dá para mostrar a bateria: o próprio Android
            // entrega nível/temperatura/estado. Melhor do que uma tela vazia.
            box.removeAllViews()
            val m = LinkedHashMap<String, String>()
            m.putAll(nativeStats())   // RAM/CPU/frequência/núcleos pelo núcleo C
            val bat = OtmBattery.snapshot(this)
            val keys = bat.keys()
            while (keys.hasNext()) { val k = keys.next(); if (!m.containsKey(k)) m[k] = bat.optString(k) }
            for (linha in monitorRows(m, semShell = true)) box.addView(linha)
            box.addView(procNote("conecte o Shizuku para ver FPS e o resto"))
            return
        }
        scope.launch {
            val res = OtmExec.run(this@OverlayService, shellRunner(), "panel-stats.sh", emptyList())
            val s = HashMap(parseStats(joinOutput(res.stdout, res.stderr)))
            // O núcleo nativo completa o que o shell não trouxe (e nunca
            // sobrescreve o shell, que lê mais). Sem Shizuku, é o que sustenta
            // RAM, CPU, frequência e temperatura.
            val nat = nativeStats()
            for ((k, v) in nat) if (!s.containsKey(k) || s[k].isNullOrEmpty()) s[k] = v
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

    /**
     * Dá foco ao campo e abre o teclado.
     *
     * A janela do overlay nasce com `FLAG_NOT_FOCUSABLE`, então um EditText
     * nela NUNCA recebe foco de teclado — o toque não abria nada e o usuário
     * não conseguia digitar a largura. Aqui removemos a flag só enquanto o
     * campo está em uso e pedimos o teclado explicitamente; ao perder o foco,
     * a flag volta (senão o painel passaria a roubar o toque do jogo).
     */
    private fun focusCampo(campo: EditText) {
        val p = root?.layoutParams as? WindowManager.LayoutParams ?: return
        if (p.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE != 0) {
            p.flags = p.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE.inv()
            runCatching { windowManager.updateViewLayout(root, p) }
        }
        campo.requestFocus()
        campo.post {
            val im = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            im?.showSoftInput(campo, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    /** Volta a janela a não-focável (o toque no jogo deixa de ir para o painel). */
    private fun soltarFoco() {
        val im = getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
        // qualquer campo de texto da aba atual (largura ou filtro de logs)
        for (campo in listOfNotNull(dpiCampo, logFilter)) {
            if (campo.hasFocus()) {
                im?.hideSoftInputFromWindow(campo.windowToken, 0)
                campo.clearFocus()
            }
        }
        val p = root?.layoutParams as? WindowManager.LayoutParams ?: return
        if (p.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE == 0) {
            p.flags = p.flags or WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
            runCatching { windowManager.updateViewLayout(root, p) }
        }
    }

    /** Lê a "Menor largura" em uso no aparelho e preenche o campo e o rótulo. */
    private fun loadDpi() {
        if (shellRunner() == null) {
            dpiAgora?.text = "conecte o Shizuku para ver a largura atual"
            return
        }
        scope.launch {
            val res = OtmExec.run(this@OverlayService, shellRunner(), "game-per-app.sh", listOf("dpi-atual"))
            val atual = joinOutput(res.stdout, res.stderr).trim().lines()
                .lastOrNull { it.trim().isNotEmpty() }?.trim()?.takeIf { it.all(Char::isDigit) }
            post {
                if (atual != null) {
                    dpiAgora?.text = "Em uso agora: $atual dp"
                    // só preenche o campo se o usuário não estiver digitando
                    if (dpiCampo?.hasFocus() != true) dpiCampo?.setText(atual)
                } else {
                    dpiAgora?.text = "não consegui ler a largura atual"
                }
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

    /**
     * "120.0" → "120 Hz"; "59.94" → "59.94 Hz". O `dumpsys` devolve a taxa com
     * casa decimal (120.0) e mostrar "120.0 Hz" soava como número cru de debug.
     */
    private fun hzTxt(hz: String): String {
        val t = hz.trim()
        val inteiro = t.endsWith(".0") || Regex("^\\d+$").matches(t)
        return if (inteiro) "${t.removeSuffix(".0")} Hz" else "$t Hz"
    }

    /** Monta as linhas do monitor com o que o aparelho realmente informou. */
    private fun monitorRows(s: Map<String, String>, semShell: Boolean = false): List<View> {
        val linhas = ArrayList<View>()
        val fps = s["fps"]?.takeIf { it.isNotEmpty() }
        // "Teto da tela" é o MAIOR modo que o PAINEL suporta (refresh_max, do
        // dumpsys display) — não o valor travado nas settings. Antes o monitor
        // mostrava o peak gravado (ex.: 120 num aparelho de 90 Hz) e parecia
        // que o aparelho tinha um teto que não existe.
        val teto = s["refresh_max"]?.takeIf { it.isNotEmpty() }
        val travado = s["refresh_peak"]?.takeIf { it.isNotEmpty() }
        val atual = s["refresh_hz"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow("FPS do jogo", fps ?: "—", destaque = true))
        // "Taxa agora" é o Hz EM USO (modo ativo da tela), não o teto do painel.
        // Marcamos "(travada)" quando o pack fixou min == peak (é o que faz o
        // refresh_peak vir preenchido) — antes a condição exigia `atual == null`
        // e, como o refresh_hz quase sempre existe, o rótulo nunca aparecia.
        val agora = atual ?: travado
        linhas.add(monitorRow(
            "Taxa agora",
            if (agora != null) hzTxt(agora) + (if (travado != null) " (travada)" else "") else "—",
            destaque = true,
        ))
        linhas.add(monitorRow("Teto da tela", if (teto != null) hzTxt(teto) else "—"))
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
        // temperatura do sistema (núcleo nativo, SoC) tem prioridade; sem ela, a
        // da bateria (Android) — as duas são reais, nunca estimativa
        val temp = s["temp_c"]?.takeIf { it.isNotEmpty() }
            ?: s["bat_temp_c"]?.takeIf { it.isNotEmpty() }
        linhas.add(monitorRow("Temperatura", if (temp != null) "$temp °C" else "—"))
        // partes quentes separadas: SoC x GPU x pele (o que o térmico do jogo vê).
        // Só entra a linha do tipo que o aparelho realmente expõe.
        for ((chave, rotulo) in listOf(
            "temp_soc_c" to "Temp. do SoC",
            "temp_gpu_c" to "Temp. da GPU",
            "temp_skin_c" to "Temp. da carcaça",
        )) {
            s[chave]?.takeIf { it.isNotEmpty() }?.let {
                linhas.add(monitorRow(rotulo, "$it °C"))
            }
        }
        // GPU: carga real do driver (Adreno/Mali), quando exposta
        s["gpu_pct"]?.takeIf { it.isNotEmpty() }?.let { linhas.add(monitorRow("GPU", "$it%")) }
        // pressão de memória (PSI): o melhor sinal de aperto — melhor que "RAM livre"
        s["mem_press"]?.takeIf { it.isNotEmpty() }?.let {
            linhas.add(monitorRow("Pressão de RAM", "$it%"))
        }
        s["swap_mb"]?.takeIf { it.isNotEmpty() }?.let {
            linhas.add(monitorRow("zram/swap em uso", "$it MB"))
        }
        // bateria: corrente (sinal indica carga/descarga) e tensão
        val ma = s["bat_ma"]?.takeIf { it.isNotEmpty() }
        if (ma != null) {
            val f = ma.toDoubleOrNull()
            val txt = when {
                f == null -> "$ma mA"
                f < -1 -> "${ma} mA (descarga)"
                f > 1 -> "$ma mA (carregando)"
                else -> "$ma mA"
            }
            linhas.add(monitorRow("Corrente", txt))
        }
        s["bat_v"]?.takeIf { it.isNotEmpty() }?.let { linhas.add(monitorRow("Tensão", "$it V")) }
        val bat = s["bat_level"]?.takeIf { it.isNotEmpty() } ?: s["bat_pct"]?.takeIf { it.isNotEmpty() }
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
            linhas.add(procNote(
                if (semShell) "FPS: conecte o Shizuku para medir (o jogo tem de estar na tela)"
                else "sem FPS: abra o jogo (o painel precisa dele na tela)"
            ))
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
        box.addView(procNote("SkiaGL multithread e Skia Vulkan multithread só valem após reiniciar"))
        box.addView(sectionHeader("Driver gráfico"))
        box.addView(driverRow("ANGLE em todos os apps", "angle_all"))
        box.addView(driverRow("Driver de jogo (todos)", "gamedriver"))
        val upd = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        upd.addView(smallButton("Driver pré-lançamento") {
            runScript("deep-tune.sh", listOf("gfxdriver", "updatable", "pre"), "Driver pré-lançamento")
        })
        upd.addView(smallButton("Driver estável") {
            runScript("deep-tune.sh", listOf("gfxdriver", "updatable", "producao"), "Driver do sistema")
        })
        box.addView(upd, matchWrap())
        return box
    }

    /** Par liga/desliga de driver: `deep-tune.sh gfxdriver <sub> on|off`. */
    private fun driverRow(label: String, sub: String): View {
        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(smallButton("$label: ligar") {
            runScript("deep-tune.sh", listOf("gfxdriver", sub, "on"), "$label ligado")
        })
        row.addView(smallButton("desligar") {
            runScript("deep-tune.sh", listOf("gfxdriver", sub, "off"), "$label desligado")
        })
        return row
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
        if (shellRunner() == null) {
            box.addView(procNote("sem acesso — abra o app e conecte o Shizuku"))
            return
        }
        scope.launch {
            val res = OtmExec.run(this@OverlayService, shellRunner(), "proc-mgr.sh", listOf("apps"))
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
            val res = OtmExec.run(this@OverlayService, shellRunner(), "proc-mgr.sh", listOf("list"))
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

    // ---- aba Logs ------------------------------------------------------------

    /**
     * Aba Logs: o histórico de execuções (o MESMO `state/log.jsonl` do painel),
     * com filtro e detalhe por toque.
     *
     * O flutuante não tem WebView, então a lista é montada em views nativas.
     * Traz o que o painel mostra em "Logs" (ok/erro, duração, razões e saída),
     * resumido: aqui é para conferir no meio da partida o que pegou e o que não
     * pegou, sem sair do jogo. A lista é lida UMA vez e filtrada em memória —
     * não relê o arquivo a cada tecla.
     */
    private fun logTab(): View {
        val box = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        val acoes = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val soErros = logChip("Só erros", logOnlyErrors)
        soErros.setOnClickListener {
            logOnlyErrors = !logOnlyErrors
            pintarLogChip(soErros, logOnlyErrors)
            renderLogs()
        }
        acoes.addView(soErros)
        acoes.addView(logChip("Atualizar", false).apply { setOnClickListener { refreshLogs() } })
        acoes.addView(logChip("Limpar", false).apply { setOnClickListener { pedirLimparLogs() } })
        box.addView(acoes, matchWrap())

        val campo = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_TEXT
            textSize = 11.5f
            hint = "filtrar (nome, comando, erro…)"
            setTextColor(col(C_TEXT))
            setHintTextColor(col(C_MUTED))
            setTypeface(bodyTypeface())
            background = pill(dp(10).toFloat(), C_GLASS, accentA(0x66))
            setPadding(dp(9), dp(6), dp(9), dp(6))
            isFocusableInTouchMode = true
            setOnTouchListener { _, ev -> if (ev.action == MotionEvent.ACTION_DOWN) focusCampo(this); false }
        }
        logFilter = campo
        // filtra enquanto digita: a lista já está em memória
        campo.addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun onTextChanged(s: CharSequence?, a: Int, b: Int, c: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) = renderLogs()
        })
        box.addView(campo, matchWrap())

        val lista = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        box.addView(lista, matchWrap())
        logBox = lista
        refreshLogs()
        return box
    }

    /** Chip de ação da aba Logs; o visual "aceso" marca o estado ligado. */
    private fun logChip(label: String, on: Boolean): TextView =
        TextView(this).apply {
            text = label
        }.also {
            pintarLogChip(it, on)
            it.layoutParams = LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f,
            ).apply { marginEnd = dp(4) }
        }

    private fun pintarLogChip(chip: TextView, on: Boolean) {
        chip.textSize = 11f
        chip.gravity = Gravity.CENTER
        chip.typeface = bodyTypeface()
        chip.setTextColor(col(if (on) accentInk() else accent()))
        chip.background = if (on) pill(dp(10).toFloat(), accent())
        else pill(dp(10).toFloat(), C_GLASS, accentA(0x66))
        chip.setPadding(dp(8), dp(6), dp(8), dp(6))
    }

    /** Lê o histórico do disco (fora da thread da UI) e redesenha. */
    private fun refreshLogs() {
        val box = logBox ?: return
        box.removeAllViews()
        box.addView(procNote("lendo…"))
        scope.launch {
            val lidos = OtmLog.read(this@OverlayService)
            post {
                if (logBox !== box) return@post
                logCache = lidos
                renderLogs()
            }
        }
    }

    /** Desenha a lista já lida (filtro em memória, sem tocar no disco). */
    private fun renderLogs() {
        val box = logBox ?: return
        val q = logFilter?.text?.toString()?.trim()?.lowercase() ?: ""
        val linhas = logCache.filter { casaLog(it, q) }
        box.removeAllViews()
        if (linhas.isEmpty()) {
            box.addView(procNote(
                if (logCache.isEmpty()) "nada registrado ainda" else "nada bate com o filtro",
            ))
            return
        }
        val erros = logCache.count { !it.optBoolean("ok", true) }
        box.addView(procNote("${linhas.size} de ${logCache.size} · $erros erro(s)"))
        for (l in linhas) box.addView(logRow(l))
    }

    private fun casaLog(o: JSONObject, q: String): Boolean {
        if (logOnlyErrors && o.optBoolean("ok", true)) return false
        if (q.isEmpty()) return true
        val hay = buildString {
            append(o.optString("label")); append(' ')
            append(o.optString("id")); append(' ')
            append(o.optString("cmd")); append(' ')
            append(o.optString("out"))
            val r = o.optJSONArray("reasons")
            if (r != null) for (i in 0 until r.length()) { append(' '); append(r.optString(i)) }
        }.lowercase()
        return hay.contains(q)
    }

    /**
     * Uma execução: status, hora, o que foi e o resumo do resultado. No toque,
     * abre o detalhe (comando, razões da falha e saída) — montado só ao abrir,
     * para não criar dezenas de blocos de texto grandes à toa.
     */
    private fun logRow(o: JSONObject): View {
        val ok = o.optBoolean("ok", true)
        val coluna = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        val topo = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        topo.addView(TextView(this).apply {
            text = if (ok) "[ok]" else "[erro]"
            textSize = 11f
            typeface = bodyTypeface()
            setTextColor(col(if (ok) C_OK else C_ERR))
        })
        topo.addView(TextView(this).apply {
            text = horaLog(o.optString("ts"))
            textSize = 11f
            typeface = bodyTypeface()
            setTextColor(col(C_MUTED))
            setPadding(dp(6), 0, dp(6), 0)
        })
        topo.addView(TextView(this).apply {
            text = o.optString("label").ifEmpty { o.optString("id") }
            textSize = 11.5f
            typeface = bodyTypeface()
            setTextColor(col(C_TEXT))
            maxLines = 2
        }, LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f))
        val chev = TextView(this).apply {
            text = "▾"
            textSize = 11f
            setTextColor(col(C_MUTED))
            typeface = bodyTypeface()
        }
        topo.addView(chev)
        coluna.addView(topo, matchWrap())

        val resumo = logSummary(o)
        if (resumo.isNotEmpty()) coluna.addView(TextView(this).apply {
            text = resumo
            textSize = 11f
            typeface = bodyTypeface()
            setTextColor(col(C_MUTED))
        })

        val det = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            visibility = View.GONE
        }
        coluna.addView(det, matchWrap())

        // toque na CABEÇA (status/hora/rótulo) abre o detalhe; tocar no detalhe
        // aberto não fecha sem querer (dá para rolar/selecionar a saída)
        var montado = false
        val toggle = View.OnClickListener {
            val abrir = det.visibility != View.VISIBLE
            if (abrir && !montado) { montarLogDetalhe(det, o); montado = true }
            det.visibility = if (abrir) View.VISIBLE else View.GONE
            chev.text = if (abrir) "▴" else "▾"
        }
        topo.setOnClickListener(toggle)
        return coluna
    }

    /** Preenche o detalhe da linha (chamado só quando ela é aberta). */
    private fun montarLogDetalhe(box: LinearLayout, o: JSONObject) {
        box.setPadding(dp(8), dp(6), dp(8), dp(6))
        box.background = pill(dp(8).toFloat(), C_GLASS, C_LINE)
        val cmd = o.optString("cmd")
        if (cmd.isNotEmpty()) box.addView(logDetTexto("$ $cmd", C_MUTED))
        val r = o.optJSONArray("reasons")
        if (r != null) for (i in 0 until r.length()) box.addView(logDetTexto("! " + r.optString(i), C_ERR))
        val out = o.optString("out").trim()
        if (out.isNotEmpty()) {
            val mostra = if (out.length > 2000) out.take(2000) + "\n…(resto no painel)" else out
            box.addView(logDetTexto(mostra, C_TEXT))
        }
        if (box.childCount == 0) box.addView(logDetTexto("(sem detalhe)", C_MUTED))
    }

    private fun logDetTexto(txt: String, cor: String): TextView =
        TextView(this).apply {
            text = txt
            textSize = 10.5f
            typeface = Typeface.MONOSPACE
            setTextColor(col(cor))
            setPadding(0, dp(1), 0, dp(1))
        }

    /** Resumo curto do resultado (o que aplicou, o que não pegou, a duração). */
    private fun logSummary(o: JSONObject): String {
        val p = mutableListOf<String>()
        val applies = o.optInt("applies", 0)
        val changed = o.optInt("changed", 0)
        val failed = o.optInt("failed", 0)
        if (applies > 0) p.add("$changed/$applies aplicada(s)")
        else if (changed > 0) p.add("$changed aplicada(s)")
        if (failed > 0) p.add("$failed não pegou")
        val dur = o.optLong("dur_ms", 0)
        if (dur > 0) p.add(if (dur >= 1000) "${dur / 1000}s" else "${dur}ms")
        val code = o.optInt("code", 0)
        if (!o.optBoolean("ok", true) && code != 0) p.add("código $code")
        return p.joinToString(" · ")
    }

    /** "2026-11-03T22:19:04-03:00" → "22:19:04" (a data quase sempre é hoje). */
    private fun horaLog(ts: String): String =
        Regex("T(\\d{2}:\\d{2}:\\d{2})").find(ts)?.groupValues?.getOrNull(1) ?: "--:--"

    /**
     * Limpar pede DOIS toques. O flutuante não abre diálogo (a janela é
     * não-focável), então o segundo toque é a confirmação; sem ele, o pedido
     * "desarma" sozinho depois de alguns segundos.
     */
    private fun pedirLimparLogs() {
        if (!logClearArmed) {
            logClearArmed = true
            statusText?.text = "Limpar: toque de novo para confirmar"
            postDelayed(4000) { logClearArmed = false }
            return
        }
        logClearArmed = false
        OtmLog.clear(this)
        logCache = emptyList()
        renderLogs()
        statusText?.text = "Logs apagados"
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

        box.addView(sectionHeader("Menor largura (DPI da tela)"))
        val dpiAviso = TextView(this).apply {
            text = "O mesmo \"Menor largura\" das Opções do desenvolvedor. Menor = interface menor; maior = interface maior. Vale para o telefone inteiro."
            textSize = 10f
            setTextColor(col(C_MUTED))
            setTypeface(bodyTypeface())
            setPadding(0, 0, 0, dp(4))
        }
        box.addView(dpiAviso, matchWrap())

        // largura EM USO agora (lida do aparelho, não do que foi pedido)
        val dpiInfo = TextView(this).apply {
            text = "lendo…"
            textSize = 11.5f
            setTextColor(col(accent()))
            typeface = bodyTypeface()
            setPadding(0, 0, 0, dp(6))
        }
        dpiAgora = dpiInfo
        box.addView(dpiInfo, matchWrap())

        val dpiLinha = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        dpiLinha.addView(smallButton("Padrão do aparelho") {
            runScript("game-per-app.sh", listOf("dpi", "padrao"), "Menor largura padrão")
            postDelayed(1500) { loadDpi() }
        })
        box.addView(dpiLinha, matchWrap())

        // valor exato em dp (o overlay não tem slider, então o campo é o caminho
        // para quem quer 360, 420 etc.)
        val dpiExato = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val dpiCampo = EditText(this).apply {
            inputType = InputType.TYPE_CLASS_NUMBER
            textSize = 12f
            hint = "largura (dp)"
            setTextColor(col(C_TEXT))
            setHintTextColor(col(C_MUTED))
            setTypeface(bodyTypeface())
            background = pill(dp(10).toFloat(), C_GLASS, accentA(0x66))
            setPadding(dp(9), dp(6), dp(9), dp(6))
            setSelectAllOnFocus(true)
            isFocusableInTouchMode = true
            setOnTouchListener { _, ev -> if (ev.action == MotionEvent.ACTION_DOWN) focusCampo(this); false }
            layoutParams = LinearLayout.LayoutParams(0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f)
                .apply { marginEnd = dp(4) }
        }
        this.dpiCampo = dpiCampo
        dpiExato.addView(dpiCampo)
        dpiExato.addView(smallButton("Aplicar") {
            val v = dpiCampo.text.toString().trim().toIntOrNull()
            if (v == null) {
                statusText?.text = "Menor largura: digite um número"
            } else {
                runScript("game-per-app.sh", listOf("dpi", v.toString()), "Menor largura $v dp")
                postDelayed(1500) { loadDpi() }
            }
        })
        box.addView(dpiExato, matchWrap())
        loadDpi()

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
     *
     * O clique (voltar ao painel) fica no container, que é quem também recebe o
     * arrasto. Se o `ImageView` de dentro tivesse listener de clique, ele viraria
     * "clickable" e engoliria o toque: o `OnTouchListener` do container (o
     * `dragger`) nunca rodaria e a bolha ficaria presa no lugar.
     */
    private fun bubbleView(): View {
        return FrameLayout(this).apply {
            addView(
                ImageView(this@OverlayService).apply {
                    setImageResource(R.mipmap.ic_launcher_round)
                    scaleType = ImageView.ScaleType.FIT_CENTER
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

    /** densidade (dpi) da última configuração vista; detecta troca de DPI. */
    private var densidadeAtual = 0

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
        // o teto também não pode passar da tela: um valor fixo em dp (320) ficava
        // MAIOR que a tela num aparelho estreito e o painel saía cortado na borda.
        val teto = minOf(dp(320), tela - dp(16))
        // dp(200) pode passar do teto quando a densidade está muito alta (DPI
        // "pequeno"): aí `coerceIn(min, max)` estoura com min > max e a janela
        // fica com largura inválida — o painel some. O piso tem de caber no teto.
        val piso = minOf(dp(200), teto)
        return (tela * PANEL_W_FRAC).toInt().coerceIn(piso, teto)
    }

    /** Teto de altura do conteúdo: o resto da tela fica livre para o jogo. */
    private fun panelMaxHeight(): Int =
        (resources.displayMetrics.heightPixels * PANEL_H_FRAC).toInt().coerceAtLeast(dp(160))

    /**
     * A janela do overlay é posicionada em pixels absolutos; se as métricas da
     * tela mudarem (rotação, mudança de densidade pelo usuário), o painel
     * calculado para a tela antiga passaria a ocupar mais do que a tela nova —
     * ficava enorme, cortado. Recalcula o tamanho, preservando o modo minimizado.
     */
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        val novaDens = newConfig.densityDpi
        val velhaDens = densidadeAtual
        densidadeAtual = novaDens
        if (velhaDens != 0 && novaDens != velhaDens) {
            // a densidade mudou (DPI do pack ou opções do desenvolvedor): remonta
            // o conteúdo em dp para ele não ficar no tamanho antigo
            onDensityChanged()
        } else {
            refitToScreen()
        }
    }

    private fun refitToScreen() {
        val atual = root ?: return
        val p = atual.layoutParams as? WindowManager.LayoutParams ?: return
        val largura = if (minimized) dp(BUBBLE_DP) else panelWidth()
        if (p.width == largura) return
        p.width = largura
        val tela = resources.displayMetrics
        p.x = p.x.coerceIn(0, (tela.widthPixels - largura).coerceAtLeast(0))
        p.y = p.y.coerceIn(0, (tela.heightPixels - dp(48)).coerceAtLeast(0))
        runCatching { windowManager.updateViewLayout(atual, p) }
    }

    /**
     * A densidade (DPI) pode mudar com o painel aberto — inclusive pela própria
     * aba de DPI. O conteúdo é construído em dp, então precisa ser REMONTADO
     * com a nova densidade, senão os textos e paddings ficam no tamanho antigo.
     * Preserva a posição e o modo minimizado (o rebuild já faz isso).
     */
    private fun onDensityChanged() {
        if (root == null) return
        post {
            rebuild()
            loadMonitor()
        }
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

    private fun runScript(script: String, args: List<String>, label: String) {
        post { statusText?.text = "$label: aplicando…" }
        scope.launch {
            val t0 = System.currentTimeMillis()
            val res = OtmExec.run(this@OverlayService, shellRunner(), script, args)
            val durMs = System.currentTimeMillis() - t0
            val out = joinOutput(res.stdout, res.stderr)
            val v = OtmExec.parseResult(out)
            val changed = v["changed"]?.toIntOrNull() ?: 0
            val failed = v["failed"]?.toIntOrNull() ?: 0
            val applies = v["applies"]?.toIntOrNull() ?: 0
            val ok = v["ok"]?.toIntOrNull()
            val msg = when {
                // sem permissão de shell é o caso mais comum de "erro em tudo":
                // dizer o que fazer é melhor que mandar procurar o painel.
                !res.ok && out.contains("sem permissão de shell") ->
                    "$label: sem acesso (conecte o Shizuku)"
                !res.ok -> "$label: falhou (veja o painel)"
                changed > 0 -> "$label: aplicado ($changed)"
                // ações de leitura (sensi, ver tuning) marcam ok=1 sem mudar nada:
                // antes elas caíam em "sem mudança", que parecia erro.
                ok == 1 -> "$label: pronto"
                failed > 0 -> "$label: nada mudou ($failed falha(s))"
                else -> "$label: sem mudança"
            }
            // Registra no MESMO histórico do painel (Logs): o que se mexe no
            // flutuante antes não aparecia em lugar nenhum. [ok] segue a mesma
            // regra do PackBridge: falhou, ou tentou aplicar e nada mudou.
            OtmLog.append(
                this@OverlayService, script, label, cmdLine(script, args),
                ok = res.ok && !(applies > 0 && changed == 0),
                code = res.code, out = out,
                applies = applies, changed = changed, failed = failed, durMs = durMs,
            )
            post {
                statusText?.text = msg
                Toast.makeText(this@OverlayService, msg, Toast.LENGTH_SHORT).show()
            }
        }
    }

    /** Linha de comando como aparece no log (mesma ideia do `cmd` do painel). */
    private fun cmdLine(script: String, args: List<String>): String =
        (listOf(script) + args).joinToString(" ")

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
        /** Mesmas cores de estado do painel (--teal/--danger). */
        private const val C_OK = "#31C0A5"
        private const val C_ERR = "#FF6B5E"

        // tipo na zona térmica -> chave no monitor (mesmos nomes do panel-stats,
        // para o nativo e o shell preencherem o MESMO campo). Só aparece o que existir.
        private val THERM_KEYS = listOf(
            "battery" to "bat_temp_c",
            "gpu" to "temp_gpu_c",
            "skin" to "temp_skin_c",
            "soc" to "temp_soc_c",
        )

        /**
         * Largura do painel: fração da tela, com piso/teto em dp ([panelWidth]).
         * 0.70 num aparelho de 360 dp dava ~252 dp e o painel tomava a tela no
         * jogo; 0.58 dá ~209 dp — legível, mas ainda deixando o jogo à vista.
         */
        private const val PANEL_W_FRAC = 0.58f
        /**
         * Teto de altura do conteúdo (o resto da tela fica para o jogo). 0.62
         * deixava o painel com mais da metade da tela por cima do jogo.
         */
        private const val PANEL_H_FRAC = 0.50f
        /** Lado do ícone minimizado (quadrado, sempre igual em qualquer aparelho). */
        private const val BUBBLE_DP = 48

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
        private val TABS = listOf("Monitor", "Jogo", "Toque", "Motor", "Processos", "Logs", "Atalhos")
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
