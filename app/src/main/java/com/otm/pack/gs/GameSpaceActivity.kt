package com.otm.pack.gs

import android.content.Context
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.LinearLayout
import androidx.appcompat.app.AppCompatActivity
import com.otm.pack.OtmExec
import com.otm.pack.OtmNative
import com.otm.pack.OtmRunner
import com.otm.pack.R
import com.otm.pack.ShellRunner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.Locale

/**
 * Game Space do Trix — a tela cheia de otimização durante a partida.
 *
 * Visual inspirado num app de referência (rail lateral com abas, cabeçalho
 * "eyebrow" + título, cards de vidro e um dock de estatísticas ao vivo), mas
 * TODO o conteúdo roda nos scripts do próprio pack — nada da lógica de
 * terceiros. As 4 abas são: Jogo, Desempenho, Gráficos e Bateria.
 */
class GameSpaceActivity : AppCompatActivity() {

    private lateinit var rail: LinearLayout
    private lateinit var content: FrameLayout
    private lateinit var dock: View

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val handler = Handler(Looper.getMainLooper())

    private val pages = ArrayList<View>()
    private val tabIcons = ArrayList<android.widget.ImageView>()
    private val tabInds = ArrayList<View>()
    private val tabBoxes = ArrayList<GsBox>()

    // stats do dock
    private var statTemp: android.widget.TextView? = null
    private var statCpu: android.widget.TextView? = null
    private var statRam: android.widget.TextView? = null
    private var statFps: android.widget.TextView? = null
    private var statPing: android.widget.TextView? = null
    private var statBatt: android.widget.TextView? = null

    // gráfico ao vivo da aba Desempenho
    private var graph: GsGraphView? = null
    private var chipFps: android.widget.TextView? = null
    private var chipCpu: android.widget.TextView? = null
    private var chipGpu: android.widget.TextView? = null
    private var chipRam: android.widget.TextView? = null
    private var ramText: android.widget.TextView? = null
    private var ramSub: android.widget.TextView? = null
    private var heavyBox: LinearLayout? = null
    private var heavyEmpty: View? = null

    // bateria
    private var battPct: android.widget.TextView? = null
    private var battState: android.widget.TextView? = null
    private var tempRange: GsTempRangeView? = null
    private var tempValue: android.widget.TextView? = null
    private var tempState: android.widget.TextView? = null

    private var statusToast: GsBox? = null
    private var statusText: android.widget.TextView? = null

    private var polling = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val root = FrameLayout(this).apply { setBackgroundColor(GsTheme.bgRoot) }
        root.addView(GsBackdropView(this), FrameLayout.LayoutParams(-1, -1))

        val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        row.addView(buildRail())
        content = FrameLayout(this)
        row.addView(content, LinearLayout.LayoutParams(0, -1, 1f))
        root.addView(row, FrameLayout.LayoutParams(-1, -1))

        // páginas
        pages.add(pageJogo())
        pages.add(pageDesempenho())
        pages.add(pageGraficos())
        pages.add(pageBateria())
        pages.forEach {
            it.visibility = View.GONE
            content.addView(it, FrameLayout.LayoutParams(-1, -1))
        }

        // dock de estatísticas ao vivo (rodapé, sobre as páginas)
        dock = buildDock()
        content.addView(dock, FrameLayout.LayoutParams(-1, -2, Gravity.BOTTOM).apply {
            marginStart = Gs.dp(this@GameSpaceActivity, 22f)
            marginEnd = Gs.dp(this@GameSpaceActivity, 22f)
            bottomMargin = Gs.dp(this@GameSpaceActivity, 18f)
        })

        // aviso flutuante (toast interno)
        statusText = Gs.num(this, "", 13f, GsTheme.text)
        statusToast = GsBox(this).apply {
            bg = GsTheme.toastBg
            borderColor = GsTheme.accentA(0x40)
            radiusPx = GsTheme.dp(this@GameSpaceActivity, 999f)
            setPadding(Gs.dp(this@GameSpaceActivity, 17f), Gs.dp(this@GameSpaceActivity, 11f),
                Gs.dp(this@GameSpaceActivity, 17f), Gs.dp(this@GameSpaceActivity, 11f))
            addView(statusText)
            alpha = 0f
            visibility = View.GONE
        }
        root.addView(statusToast, FrameLayout.LayoutParams(-2, -2, Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL).apply {
            bottomMargin = Gs.dp(this@GameSpaceActivity, 92f)
        })

        setContentView(root)
        selectPage(0)
        startPolling()
    }

    override fun onDestroy() {
        polling = false
        handler.removeCallbacksAndMessages(null)
        scope.cancel()
        super.onDestroy()
    }

    // ---- rail (lateral) ------------------------------------------------------

    private fun buildRail(): View {
        rail = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setBackgroundColor(GsTheme.railBg)
            setPadding(0, Gs.dp(this@GameSpaceActivity, 20f), 0, Gs.dp(this@GameSpaceActivity, 20f))
        }
        val w = Gs.dp(this, 73f)

        val orbWrap = FrameLayout(this).apply {
            addView(GsOrbView(this@GameSpaceActivity), FrameLayout.LayoutParams(Gs.dp(this@GameSpaceActivity, 40f), Gs.dp(this@GameSpaceActivity, 40f)))
        }
        rail.addView(orbWrap, LinearLayout.LayoutParams(Gs.dp(this, 40f), Gs.dp(this, 40f)).apply { bottomMargin = Gs.dp(this@GameSpaceActivity, 10f) })

        val tabs = listOf(
            Triple(R.drawable.ic_sports_esports, R.string.gs_title_game, 0),
            Triple(R.drawable.ic_speed, R.string.gs_title_perf, 1),
            Triple(R.drawable.ic_display_settings, R.string.gs_title_gfx, 2),
            Triple(R.drawable.ic_battery_charging_full, R.string.gs_title_batt, 3),
        )
        for ((iconRes, _, index) in tabs) {
            val box = GsBox(this).apply {
                radiusPx = GsTheme.dp(this@GameSpaceActivity, 14f)
                layoutParams = LinearLayout.LayoutParams(Gs.dp(this@GameSpaceActivity, 44f), Gs.dp(this@GameSpaceActivity, 44f))
                    .apply { topMargin = Gs.dp(this@GameSpaceActivity, 10f) }
            }
            val iv = Gs.icon(this, iconRes, 21, GsTheme.textDim)
            box.addView(iv, FrameLayout.LayoutParams(Gs.dp(this, 21f), Gs.dp(this, 21f), Gravity.CENTER))
            val ind = GsBox(this).apply {
                bg = GsTheme.accent
                radiusPx = GsTheme.dp(this@GameSpaceActivity, 2f)
                visibility = View.GONE
            }
            box.addView(ind, FrameLayout.LayoutParams(Gs.dp(this, 3f), Gs.dp(this, 20f), Gravity.START or Gravity.CENTER_VERTICAL).apply {
                marginStart = -Gs.dp(this@GameSpaceActivity, 14f)
            })
            box.setOnClickListener { selectPage(index) }
            tabBoxes.add(box); tabIcons.add(iv); tabInds.add(ind)
            rail.addView(box)
        }

        rail.addView(View(this), LinearLayout.LayoutParams(1, 0, 1f))

        val exit = FrameLayout(this).apply {
            background = Gs.rounded(this@GameSpaceActivity, 999f, GsTheme.white(6))
            layoutParams = LinearLayout.LayoutParams(Gs.dp(this@GameSpaceActivity, 40f), Gs.dp(this@GameSpaceActivity, 40f))
                .apply { topMargin = Gs.dp(this@GameSpaceActivity, 10f) }
            addView(Gs.icon(this@GameSpaceActivity, R.drawable.ic_power_settings_new, 18, GsTheme.textHi),
                FrameLayout.LayoutParams(-2, -2, Gravity.CENTER))
            setOnClickListener { finish() }
        }
        rail.addView(exit)

        return rail.also {
            it.layoutParams = LinearLayout.LayoutParams(w, -1)
        }
    }

    /** Dock inferior: as estatísticas ao vivo da partida, em faixas separadas. */
    private fun buildDock(): View {
        val row = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val stats = listOf(
            R.string.gs_stat_temp to { v: android.widget.TextView -> statTemp = v },
            R.string.gs_stat_cpu to { v: android.widget.TextView -> statCpu = v },
            R.string.gs_stat_fps to { v: android.widget.TextView -> statFps = v },
            R.string.gs_stat_ram to { v: android.widget.TextView -> statRam = v },
            R.string.gs_stat_ping to { v: android.widget.TextView -> statPing = v },
            R.string.gs_stat_batt to { v: android.widget.TextView -> statBatt = v },
        )
        stats.forEachIndexed { i, (labelRes, bind) ->
            if (i > 0) {
                row.addView(View(this).apply { setBackgroundColor(GsTheme.white(7)) },
                    LinearLayout.LayoutParams(Gs.dp(this, 1f), Gs.dp(this, 26f)).apply { marginStart = Gs.dp(this@GameSpaceActivity, 10f) })
            }
            val (col, value) = Gs.stat(this, getString(labelRes), "—")
            bind(value)
            row.addView(col, LinearLayout.LayoutParams(-2, -2).apply {
                if (i > 0) marginStart = Gs.dp(this@GameSpaceActivity, 10f)
            })
        }
        row.addView(View(this), LinearLayout.LayoutParams(0, 1, 1f))
        row.addView(Gs.accentButton(this, "", R.drawable.ic_play_arrow) {
            run("adb-tweaks.sh", listOf("game_open"), "Abrindo o jogo")
        })
        return GsBox(this).apply {
            bg = GsTheme.dockBg
            borderColor = GsTheme.white(7)
            radiusPx = GsTheme.dp(this@GameSpaceActivity, 20f)
            setPadding(Gs.dp(this@GameSpaceActivity, 17f), Gs.dp(this@GameSpaceActivity, 9f),
                Gs.dp(this@GameSpaceActivity, 9f), Gs.dp(this@GameSpaceActivity, 9f))
            addView(row)
        }
    }

    private fun selectPage(index: Int) {

        pages.forEachIndexed { i, p -> p.visibility = if (i == index) View.VISIBLE else View.GONE }
        tabBoxes.forEachIndexed { i, box ->
            val on = i == index
            box.bg = if (on) GsTheme.accentA(0x29) else Color.TRANSPARENT
            tabIcons[i].setColorFilter(if (on) GsTheme.accent else GsTheme.textDim)
            tabInds[i].visibility = if (on) View.VISIBLE else View.GONE
        }
    }

    // ---- abas ----------------------------------------------------------------

    private fun pageShell(titleRes: Int, labelRes: Int, trailing: View?): LinearLayout {
        val col = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(Gs.dp(this@GameSpaceActivity, 22f), Gs.dp(this@GameSpaceActivity, 18f),
                Gs.dp(this@GameSpaceActivity, 22f), Gs.dp(this@GameSpaceActivity, 92f))
        }
        col.addView(Gs.header(this, getString(labelRes), getString(titleRes), trailing))
        return col
    }

    private fun clockText(): android.widget.TextView =
        Gs.num(this, nowHm(), 14f, GsTheme.textSoft).apply {
            setPadding(Gs.dp(this@GameSpaceActivity, 12f), 0, 0, 0)
        }

    private fun nowHm(): String {
        val c = java.util.Calendar.getInstance()
        return String.format(Locale.US, "%02d:%02d", c.get(java.util.Calendar.HOUR_OF_DAY), c.get(java.util.Calendar.MINUTE))
    }

    private fun pageJogo(): View {
        val col = pageShell(R.string.gs_title_game, R.string.gs_label_game, clockText())

        col.addView(Gs.vSpace(this, 12f))

        // Card: desempenho do jogo
        val (cardGame, cg) = Gs.card(this, R.string.gs_label_perf, R.drawable.ic_speed)
        cg.addView(Gs.divider(this))
        cg.addView(Gs.row(this, getString(R.string.gs_game_mode), null, segmentedMode()))
        cg.addView(Gs.divider(this))
        cg.addView(Gs.row(this, getString(R.string.gs_fps_limit), getString(R.string.gs_fps_sub), segmentedFps()))
        cg.addView(Gs.divider(this))
        cg.addView(Gs.row(this, getString(R.string.gs_downscale), getString(R.string.gs_downscale_sub), segmentedRes()))
        col.addView(cardGame, Gs.matchWrap())
        col.addView(Gs.vSpace(this, 12f))

        // Card: extras
        val (cardExtra, ce) = Gs.card(this, R.string.gs_label_game, R.drawable.ic_sports_esports)
        ce.addView(Gs.divider(this))
        ce.addView(Gs.row(this, getString(R.string.gs_anti_relog), getString(R.string.gs_anti_relog_sub),
            Gs.toggle(this, false) { on -> run("adb-tweaks.sh", listOf("game"), if (on) "Anti-relog ligado" else "Anti-relog") }))
        ce.addView(Gs.divider(this))
        val bts = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 10f), 0, 0)
        }
        bts.addView(Gs.accentButton(this, getString(R.string.gs_open_game), R.drawable.ic_play_arrow) {
            run("adb-tweaks.sh", listOf("game_open"), "Abrindo o jogo")
        }, Gs.lp(0, -2, 1f).apply { marginEnd = Gs.dp(this@GameSpaceActivity, 6f) })
        bts.addView(Gs.ghostButton(this, getString(R.string.gs_opt_now), R.drawable.ic_bolt) {
            run("smart-opt.sh", listOf("auto"), "Otimização inteligente")
        }, Gs.lp(0, -2, 1f))
        ce.addView(bts)
        val bts2 = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 6f), 0, 0)
        }
        bts2.addView(Gs.ghostButton(this, getString(R.string.gs_opt_plus), R.drawable.ic_electric_bolt) {
            run("adb-tweaks.sh", listOf("game_tune"), "Tuning do jogo")
        }, Gs.lp(0, -2, 1f).apply { marginEnd = Gs.dp(this@GameSpaceActivity, 6f) })
        bts2.addView(Gs.ghostButton(this, getString(R.string.gs_compile), R.drawable.ic_rocket_launch) {
            run("turbo.sh", listOf("art-all", "speed-profile"), "Compilando apps")
        }, Gs.lp(0, -2, 1f))
        ce.addView(bts2)
        col.addView(cardExtra, Gs.matchWrap())

        return scrollWrap(col)
    }

    private fun segmentedMode(): View = Gs.segmented(this, listOf(
        getString(R.string.gs_mode_perf), getString(R.string.gs_mode_saver), getString(R.string.gs_mode_std),
    ), 0) { i ->
        val m = listOf("performance", "battery", "standard")[i]
        run("game-per-app.sh", listOf("mode", "auto", m), "Modo do jogo: $m")
    }

    private fun segmentedFps(): View = Gs.segmented(this, listOf("60", "90", "120", "Auto"), 3) { i ->
        val v = listOf("60", "90", "120", "auto")[i]
        if (v == "auto") run("turbo.sh", listOf("refresh", "max"), "Taxa automática")
        else run("turbo.sh", listOf("refresh_fixed", v), "Taxa de tela ${v}Hz")
    }

    private fun segmentedRes(): View = Gs.segmented(this, listOf("FPS", "Equil.", "Máx"), 0) { i ->
        val p = listOf("fps", "balanced", "max")[i]
        run("game-per-app.sh", listOf("apply", "auto", p), "Resolução: $p")
    }

    private fun pageDesempenho(): View {
        val trailing = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }
        val tempPill = Gs.pillChip(this, "—", R.drawable.ic_device_thermostat, GsTheme.green)
        tempValue = (tempPill.getChildAt(0) as LinearLayout).getChildAt(1) as android.widget.TextView
        trailing.addView(tempPill)
        trailing.addView(clockText())

        val col = pageShell(R.string.gs_title_perf, R.string.gs_label_perf, trailing)
        col.addView(Gs.vSpace(this, 12f))

        // gráfico + chips
        val (cardGraph, cgr) = Gs.card(this, R.string.gs_label_perf, R.drawable.ic_speed)
        val chips = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL }
        val (cCpu, vCpu) = Gs.stat(this, "CPU", "—"); chipCpu = vCpu
        val (cGpu, vGpu) = Gs.stat(this, "GPU", "—"); chipGpu = vGpu
        val (cRam, vRam) = Gs.stat(this, "RAM", "—"); chipRam = vRam
        val (cFps, vFps) = Gs.stat(this, "FPS", "—"); chipFps = vFps
        listOf(cCpu, cGpu, cRam, cFps).forEachIndexed { i, v ->
            val box = GsBox(this).apply {
                bg = GsTheme.white(3); borderColor = GsTheme.white(8)
                radiusPx = GsTheme.dp(this@GameSpaceActivity, 10f)
                setPadding(Gs.dp(this@GameSpaceActivity, 9f), Gs.dp(this@GameSpaceActivity, 7f), Gs.dp(this@GameSpaceActivity, 9f), Gs.dp(this@GameSpaceActivity, 7f))
                addView(v)
            }
            chips.addView(box, Gs.lp(0, -2, 1f).apply { if (i > 0) marginStart = Gs.dp(this@GameSpaceActivity, 6f) })
        }
        cgr.addView(chips, Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 8f) })
        graph = GsGraphView(this).apply { lineColor = GsTheme.accent }
        cgr.addView(graph, Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 10f) })
        val legend = FrameLayout(this)
        legend.addView(Gs.label(this, getString(R.string.gs_graph_60s), 10f, GsTheme.textDim, semi = false),
            FrameLayout.LayoutParams(-2, -2, Gravity.START))
        legend.addView(Gs.label(this, getString(R.string.gs_graph_now), 10f, GsTheme.textDim, semi = false),
            FrameLayout.LayoutParams(-2, -2, Gravity.END))
        cgr.addView(legend, Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 4f) })
        col.addView(cardGraph, Gs.matchWrap())
        col.addView(Gs.vSpace(this, 12f))

        // limpar RAM + apps pesados
        val (cardRam, cr) = Gs.card(this, R.string.gs_clean_ram, R.drawable.ic_cleaning_services)
        val ramHead = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        }
        ramText = Gs.num(this, "—", 15f, GsTheme.textHi)
        ramHead.addView(Gs.label(this, getString(R.string.gs_clean_ram), 13f), Gs.lp(0, -2, 1f))
        ramHead.addView(ramText)
        cr.addView(ramHead, Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 8f) })
        val ramRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 6f), 0, 0)
        }
        ramRow.addView(Gs.accentButton(this, getString(R.string.gs_clean_ram), R.drawable.ic_cleaning_services) {
            run("ram-boost.sh", listOf("boost"), "Limpando RAM")
        })
        ramSub = Gs.numMed(this, "—", 11f, GsTheme.textMute)
        ramRow.addView(ramSub, Gs.lp(0, -2, 1f).apply { marginStart = Gs.dp(this@GameSpaceActivity, 10f) })
        cr.addView(ramRow)
        cr.addView(Gs.divider(this).apply { (layoutParams as LinearLayout.LayoutParams).topMargin = Gs.dp(this@GameSpaceActivity, 8f) })
        cr.addView(Gs.label(this, getString(R.string.gs_heavy_apps), 10f, GsTheme.textDim, semi = false),
            Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 8f) })
        heavyBox = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        cr.addView(heavyBox)
        heavyEmpty = Gs.label(this, getString(R.string.gs_no_heavy_apps), 12.5f, GsTheme.textMute, semi = false)
        cr.addView(heavyEmpty)
        col.addView(cardRam, Gs.matchWrap())
        col.addView(Gs.vSpace(this, 12f))

        // modo desempenho fixo + animação
        val (cardFix, cf) = Gs.card(this, R.string.gs_title_perf, R.drawable.ic_electric_bolt)
        cf.addView(Gs.divider(this))
        cf.addView(Gs.row(this, getString(R.string.gs_fixed_perf), getString(R.string.gs_fixed_perf_sub),
            Gs.toggle(this, false) { on -> run("turbo.sh", listOf("perfmode", if (on) "on" else "off"), "Desempenho fixo") }))
        cf.addView(Gs.divider(this))
        cf.addView(Gs.row(this, getString(R.string.gs_anim), null, segmentedAnim()))
        cf.addView(Gs.label(this, getString(R.string.gs_reset_note), 10.5f, GsTheme.textDim, semi = false),
            Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 10f) })
        col.addView(cardFix, Gs.matchWrap())

        return scrollWrap(col)
    }

    private fun segmentedAnim(): View = Gs.segmented(this, listOf(
        getString(R.string.gs_anim_fast), getString(R.string.gs_anim_normal), getString(R.string.gs_anim_off),
    ), 1) { i ->
        val scale = listOf("0.5", "1.0", "0")
        run("adb-tweaks.sh", listOf("raw", "settings put global window_animation_scale ${scale[i]}; settings put global transition_animation_scale ${scale[i]}; settings put global animator_duration_scale ${scale[i]}"), "Animação do sistema")
    }

    private fun pageGraficos(): View {
        val col = pageShell(R.string.gs_title_gfx, R.string.gs_label_gfx, clockText())
        col.addView(Gs.vSpace(this, 12f))

        val (cardGfx, cg) = Gs.card(this, R.string.gs_label_gfx, R.drawable.ic_display_settings)
        cg.addView(Gs.divider(this))

        // --- resolução do jogo (renderiza menos pixels, mesma interface) ---
        cg.addView(resolutionBlock())
        cg.addView(Gs.divider(this))

        cg.addView(Gs.row(this, getString(R.string.gs_refresh), getString(R.string.gs_refresh_sub), segmentedFps()))
        cg.addView(Gs.divider(this))
        cg.addView(Gs.row(this, getString(R.string.gs_gfx_driver), getString(R.string.gs_gfx_driver_sub), segmentedDriver()))
        cg.addView(Gs.divider(this))
        cg.addView(Gs.row(this, getString(R.string.gs_aa), getString(R.string.gs_aa_sub),
            Gs.toggle(this, false) { on ->
                run("adb-tweaks.sh", listOf("raw", "setprop debug.hwui.force_msaa ${if (on) 1 else 0}"), "Anti-aliasing")
            }))
        cg.addView(Gs.divider(this))

        // saturação
        val satCol = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 9f), 0, Gs.dp(this@GameSpaceActivity, 9f))
        }
        val satHead = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL }
        satHead.addView(Gs.label(this, getString(R.string.gs_color_sat), 13f), Gs.lp(0, -2, 1f))
        val satVal = Gs.numMed(this, "1.0x", 12f, GsTheme.accent)
        satHead.addView(satVal)
        satCol.addView(satHead)
        val slider = GsSlider(this).apply {
            min = 0.8f; max = 2.0f; value = 1.0f
            layoutParams = Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 8f); height = Gs.dp(this@GameSpaceActivity, 22f) }
            onChanged = { v ->
                satVal.text = String.format(Locale.US, "%.1fx", v)
            }
        }
        slider.setOnTouchListener(null)
        satCol.addView(slider)
        val applySat = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, Gs.dp(this@GameSpaceActivity, 8f), 0, 0) }
        applySat.addView(Gs.ghostButton(this, "Aplicar saturação", R.drawable.ic_tune) {
            val v = slider.value
            run("adb-tweaks.sh", listOf("raw", "settings put system screen_color_saturation ${(v * 100).toInt()}"), "Saturação ${v}x")
        })
        satCol.addView(applySat)
        cg.addView(satCol)
        cg.addView(Gs.divider(this))
        cg.addView(Gs.row(this, getString(R.string.gs_color_mode), null, segmentedColorMode()))
        col.addView(cardGfx, Gs.matchWrap())
        col.addView(Gs.vSpace(this, 12f))

        val (cardReset, crs) = Gs.card(this, R.string.gs_reset_default, R.drawable.ic_restart_alt)
        crs.addView(Gs.divider(this))
        val rr = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 10f), 0, 0)
        }
        rr.addView(Gs.ghostButton(this, "Reset resolução", R.drawable.ic_restart_alt) {
            run("game-per-app.sh", listOf("reset", "auto"), "Resolução restaurada")
        }, Gs.lp(0, -2, 1f).apply { marginEnd = Gs.dp(this@GameSpaceActivity, 6f) })
        rr.addView(Gs.ghostButton(this, "Ver tuning", R.drawable.ic_info) {
            run("game-per-app.sh", listOf("show", "auto"), "Tuning do jogo")
        }, Gs.lp(0, -2, 1f))
        crs.addView(rr)
        crs.addView(Gs.label(this, getString(R.string.gs_reset_note), 10.5f, GsTheme.textDim, semi = false),
            Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 10f) })
        col.addView(cardReset, Gs.matchWrap())
        return scrollWrap(col)
    }

    /**
     * Bloco de resolução: o que o usuário pediu — trocar a resolução do celular
     * com presets prontos (720p, 540p…), escala livre (50–100%) e um campo pra
     * digitar o tamanho exato. Tudo por baixo chama `game-per-app.sh res …`.
     */
    private fun resolutionBlock(): View {
        val col = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }

        // título + valor em uso + badge
        val head = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 9f), 0, Gs.dp(this@GameSpaceActivity, 4f))
        }
        val left = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        left.addView(Gs.label(this, getString(R.string.gs_res_title), 13f))
        left.addView(Gs.label(this, getString(R.string.gs_res_sub), 10.5f, GsTheme.textDim, semi = false))
        head.addView(left, Gs.lp(0, -2, 1f))
        val (badgeRow, resValue) = Gs.valueWithBadge(this, "100%", getString(R.string.gs_res_badge))
        head.addView(badgeRow)
        col.addView(head)

        // slider 50–100%
        val slider = GsSlider(this).apply {
            min = 50f; max = 100f; value = 100f
            layoutParams = Gs.matchWrap().apply {
                topMargin = Gs.dp(this@GameSpaceActivity, 6f)
                height = Gs.dp(this@GameSpaceActivity, 22f)
            }
        }
        col.addView(slider)
        val scale = FrameLayout(this).apply { setPadding(0, Gs.dp(this@GameSpaceActivity, 4f), 0, 0) }
        scale.addView(Gs.label(this, "50%", 10f, GsTheme.textDim, semi = false), FrameLayout.LayoutParams(-2, -2, Gravity.START))
        scale.addView(Gs.label(this, "100%", 10f, GsTheme.textDim, semi = false), FrameLayout.LayoutParams(-2, -2, Gravity.END))
        col.addView(scale)

        fun mostraPct(pct: Int) {
            resValue.text = "$pct%"
            slider.value = pct.toFloat()
        }
        slider.onChanged = { v -> resValue.text = "${v.toInt()}%" }

        // presets de renderização
        col.addView(Gs.label(this, getString(R.string.gs_res_phones), 10f, GsTheme.textDim, semi = false),
            Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 10f) })
        val presets = listOf("100%", "90%", "75%", "60%", "50%", "Nativo")
        val chips = Gs.chipRow(this, presets, -1) { i ->
            if (i == presets.lastIndex) {
                run("game-per-app.sh", listOf("res", "native"), "Resolução nativa")
                mostraPct(100)
            } else {
                val n = presets[i].removeSuffix("%")
                run("game-per-app.sh", listOf("res", "preset", n), "Resolução ${presets[i]}")
            }
        }
        col.addView(chips, Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 6f) })

        // aplicar a escala do slider
        val applyRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 10f), 0, 0)
        }
        applyRow.addView(Gs.ghostButton(this, getString(R.string.gs_res_apply), R.drawable.ic_check) {
            val pct = slider.value.toInt()
            run("game-per-app.sh", listOf("res", pct.toString()), "Resolução $pct%")
        })
        applyRow.addView(View(this), Gs.lp(0, 1, 1f))
        applyRow.addView(Gs.ghostButton(this, getString(R.string.gs_res_native), R.drawable.ic_restart_alt) {
            run("game-per-app.sh", listOf("res", "native"), "Resolução nativa")
            mostraPct(100)
        })
        col.addView(applyRow)

        // personalizado (fator exato)
        col.addView(Gs.label(this, getString(R.string.gs_res_custom), 10f, GsTheme.textDim, semi = false),
            Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 12f) })
        val customRow = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 6f), 0, 0)
        }
        val campo = Gs.field(this, getString(R.string.gs_res_field_hint))
        campo.inputType = android.text.InputType.TYPE_CLASS_NUMBER or android.text.InputType.TYPE_NUMBER_FLAG_DECIMAL
        customRow.addView(campo, Gs.lp(0, -2, 1f).apply { marginEnd = Gs.dp(this@GameSpaceActivity, 6f) })
        customRow.addView(Gs.accentButton(this, getString(R.string.gs_res_apply), null) {
            val t = campo.text.toString().trim().replace(',', '.')
            val f = t.toFloatOrNull()
            if (f == null || f < 0.5f || f > 1f) {
                toast("Use um fator de 0.5 a 1.0 (ex.: 0.65)")
            } else {
                run("game-per-app.sh", listOf("res", "px", t), "Resolução fator $t")
                campo.setText("")
            }
        })
        col.addView(customRow)

        col.addView(Gs.label(this, getString(R.string.gs_res_note), 10.5f, GsTheme.textDim, semi = false),
            Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 10f) })

        // lê o que está em uso agora
        scope.launch {
            val res = OtmExec.run(this@GameSpaceActivity, OtmRunner.current, "game-per-app.sh", listOf("res-atual"))
            val txt = res.stdout.trim().lines().firstOrNull { it.isNotBlank() }?.trim().orEmpty()
            if (txt.isNotEmpty()) {
                if (txt == "native") {
                    resValue.text = getString(R.string.gs_res_native)
                    slider.value = 100f
                } else {
                    resValue.text = txt
                    val pct = txt.removeSuffix("%").toIntOrNull()
                    if (pct != null) slider.value = pct.coerceIn(50, 100).toFloat()
                }
            }
        }

        return col
    }

    private fun segmentedDriver(): View = Gs.segmented(this, listOf("Auto", "SkiaGL", "Vulkan"), 0) { i ->
        val r = listOf("auto", "skiagl", "skiavk")[i]
        run("adb-tweaks.sh", listOf("renderer", r), "Driver: $r")
    }

    private fun segmentedColorMode(): View = Gs.segmented(this, listOf("Natural", "Vívido", "Alto contraste"), 0) { i ->
        val m = listOf("0", "1", "2")[i]
        run("adb-tweaks.sh", listOf("raw", "settings put secure accessibility_display_daltonizer_enabled 0; settings put system display_color_mode $m"), "Modo de cor")
    }

    private fun pageBateria(): View {
        val trailing = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
        }
        val statePill = Gs.pillChip(this, getString(R.string.gs_batt_discharging), R.drawable.ic_battery_charging_full, GsTheme.green)
        battState = (statePill.getChildAt(0) as LinearLayout).getChildAt(1) as android.widget.TextView
        trailing.addView(statePill)
        trailing.addView(clockText())

        val col = pageShell(R.string.gs_title_batt, R.string.gs_label_batt, trailing)
        col.addView(Gs.vSpace(this, 12f))

        // nível
        val (cardLvl, cl) = Gs.card(this, R.string.gs_label_batt, R.drawable.ic_battery_charging_full)
        val big = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 10f), 0, Gs.dp(this@GameSpaceActivity, 10f))
        }
        big.addView(Gs.icon(this, R.drawable.ic_battery_charging_full, 34, GsTheme.green))
        battPct = Gs.num(this, "—", 34f, GsTheme.textHi)
        big.addView(battPct, Gs.lp(-2, -2).apply { marginStart = Gs.dp(this@GameSpaceActivity, 12f) })
        cl.addView(big)
        cl.addView(Gs.divider(this))
        val cells = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; setPadding(0, Gs.dp(this@GameSpaceActivity, 10f), 0, 0) }
        val (cTemp, vTemp) = Gs.stat(this, getString(R.string.gs_batt_temp_session).uppercase(), "—")
        val (cVolt, vVolt) = Gs.stat(this, getString(R.string.gs_batt_voltage).uppercase(), "—")
        val (cCur, vCur) = Gs.stat(this, getString(R.string.gs_batt_current).uppercase(), "—")
        listOf(cTemp, cVolt, cCur).forEachIndexed { i, v ->
            cells.addView(v, Gs.lp(0, -2, 1f).apply { if (i > 0) marginStart = Gs.dp(this@GameSpaceActivity, 6f) })
        }
        cl.addView(cells)
        col.addView(cardLvl, Gs.matchWrap())
        col.addView(Gs.vSpace(this, 12f))

        // temperatura da sessão
        val (cardT, ct) = Gs.card(this, R.string.gs_batt_temp_session, R.drawable.ic_device_thermostat)
        val tHead = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER_VERTICAL
            setPadding(0, Gs.dp(this@GameSpaceActivity, 8f), 0, 0)
        }
        tempValue = Gs.num(this, "—", 15f, GsTheme.textHi)
        tHead.addView(tempValue)
        tempState = Gs.label(this, getString(R.string.gs_temp_normal), 12f, GsTheme.green)
        tHead.addView(tempState, Gs.lp(-2, -2).apply { marginStart = Gs.dp(this@GameSpaceActivity, 8f) })
        ct.addView(tHead)
        tempRange = GsTempRangeView(this)
        ct.addView(tempRange, Gs.matchWrap().apply { topMargin = Gs.dp(this@GameSpaceActivity, 8f); height = Gs.dp(this@GameSpaceActivity, 26f) })
        col.addView(cardT, Gs.matchWrap())
        col.addView(Gs.vSpace(this, 12f))

        // economia de bateria
        val (cardSaver, cs) = Gs.card(this, R.string.gs_batt_saver, R.drawable.ic_energy_savings_leaf)
        cs.addView(Gs.divider(this))
        cs.addView(Gs.row(this, getString(R.string.gs_batt_saver), "Reduz brilho, limita a taxa e pausa a sincronização", Gs.toggle(this, false) { on ->
            run("adb-tweaks.sh", listOf("raw", "settings put global low_power ${if (on) 1 else 0}"), "Economia de bateria")
        }))
        col.addView(cardSaver, Gs.matchWrap())
        return scrollWrap(col)
    }

    /** Envolve uma página num ScrollView. */
    private fun scrollWrap(inner: View): View =
        android.widget.ScrollView(this).apply {
            isFillViewport = true
            addView(inner, FrameLayout.LayoutParams(-1, -2))
        }

    // ---- ações ---------------------------------------------------------------

    private fun run(script: String, args: List<String>, label: String) {
        toast("$label…")
        scope.launch {
            val runner: ShellRunner? = OtmRunner.current
            val res = OtmExec.run(this@GameSpaceActivity, runner, script, args)
            val out = (res.stdout + "\n" + res.stderr).trim()
            val v = OtmExec.parseResult(out)
            val changed = v["changed"]?.toIntOrNull() ?: 0
            val msg = when {
                !res.ok && out.contains("sem permissão de shell") -> "$label: sem acesso (conecte o Shizuku)"
                !res.ok -> "$label: falhou"
                changed > 0 -> "$label: aplicado ($changed)"
                else -> "$label: pronto"
            }
            toast(msg)
        }
    }

    private fun toast(msg: String) {
        val t = statusToast ?: return
        statusText?.text = msg
        t.visibility = View.VISIBLE
        t.animate().alpha(1f).setDuration(150).start()
        handler.removeCallbacks(hideToast)
        handler.postDelayed(hideToast, 2600)
    }

    private val hideToast = Runnable {
        statusToast?.animate()?.alpha(0f)?.setDuration(250)?.withEndAction {
            statusToast?.visibility = View.GONE
        }?.start()
    }

    // ---- telemetria ----------------------------------------------------------

    private fun startPolling() {
        polling = true
        handler.post(poll)
    }

    private val poll = object : Runnable {
        override fun run() {
            if (!polling) return
            refreshStats()
            handler.postDelayed(this, 2000)
        }
    }

    private fun refreshStats() {
        scope.launch {
            val m = readStats()
            val tempC = m["temp_c"] ?: m["thermal_soc"]
            statTemp?.text = tempC?.let { "${it}°" } ?: "—"
            statCpu?.text = m["cpu_uso_pct"]?.let { "$it%" } ?: "—"
            statRam?.text = m["ram_uso_pct"]?.let { "$it%" } ?: "—"
            statFps?.text = m["fps"]?.takeIf { it.isNotEmpty() } ?: "—"
            statPing?.text = m["ping_ms"]?.takeIf { it.isNotEmpty() } ?: "—"
            statBatt?.text = m["bat_level"]?.let { "$it%" } ?: "—"

            chipCpu?.text = m["cpu_uso_pct"]?.let { "$it%" } ?: "—"
            chipGpu?.text = m["gpu_pct"]?.let { "$it%" } ?: "—"
            chipRam?.text = m["ram_uso_pct"]?.let { "$it%" } ?: "—"
            val fps = m["fps"]?.toFloatOrNull()
            chipFps?.text = fps?.toInt()?.toString() ?: "—"
            if (fps != null) graph?.push(fps)
            ramText?.text = m["ram_uso_pct"]?.let { "$it%" } ?: "—"
            ramSub?.text = m["ram_livre_mb"]?.let { "$it MB livres" } ?: "—"

            battPct?.text = m["bat_level"]?.let { "$it%" } ?: "—"
            val tc = tempC?.toFloatOrNull()
            tempValue?.text = tc?.let { String.format(Locale.US, "%.1f°C", it) } ?: "—"
            if (tc != null) {
                tempState?.text = when {
                    tc >= 45f -> getString(R.string.gs_temp_hot)
                    tc >= 38f -> getString(R.string.gs_temp_warm)
                    else -> getString(R.string.gs_temp_normal)
                }
                val color = when {
                    tc >= 45f -> GsTheme.hot
                    tc >= 38f -> GsTheme.warm
                    else -> GsTheme.green
                }
                tempState?.setTextColor(color)
                val min = (tc - 3f).coerceAtLeast(30f)
                val max = (tc + 3f).coerceAtMost(50f)
                tempRange?.setRange(min, max, tc)
            }
        }
    }

    /** Lê o núcleo nativo quando existe; cai no `panel-stats.sh` quando não. */
    private suspend fun readStats(): Map<String, String> {
        val m = HashMap<String, String>()
        if (OtmNative.available) {
            OtmNative.ramAvailableMb()?.let { livre ->
                m["ram_livre_mb"] = livre.toString()
                OtmNative.ramTotalKb().takeIf { it > 0 }?.let { totKb ->
                    val totMb = totKb / 1024
                    if (totMb > 0) m["ram_uso_pct"] = ((totMb - livre) * 100 / totMb).coerceIn(0, 100).toString()
                }
            }
            OtmNative.cpuPct()?.let { m["cpu_uso_pct"] = it.toString() }
            OtmNative.gpuPct()?.let { m["gpu_pct"] = it.toString() }
            OtmNative.thermalC()?.let { m["temp_c"] = String.format(Locale.US, "%.1f", it) }
            OtmNative.batteryCapacityPct().takeIf { it > 0 }?.let { m["bat_level"] = it.toString() }
            OtmNative.batteryVoltageV()?.let { m["bat_volt"] = String.format(Locale.US, "%.2f", it) }
            OtmNative.batteryCurrentMa()?.let { m["bat_cur"] = String.format(Locale.US, "%.0f", it) }
        }
        // complementa com o script (FPS real, ping, bateria detalhada)
        val res = OtmExec.run(this, OtmRunner.current, "panel-stats.sh", emptyList())
        if (res.ok) m.putAll(parseStats(res.stdout))
        return m
    }

    private fun parseStats(out: String): Map<String, String> {
        val map = HashMap<String, String>()
        for (linha in out.split("\n")) {
            val t = linha.trim()
            if (!t.startsWith("{")) continue
            runCatching {
                val o = JSONObject(t)
                for (k in o.keys()) map[k] = o.optString(k)
            }
            break
        }
        return map
    }

}
