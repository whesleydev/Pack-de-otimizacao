package com.otm.pack

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Process
import android.provider.Settings
import org.json.JSONArray
import org.json.JSONObject

/**
 * Acesso ao uso (PACKAGE_USAGE_STATS) e leitura real do uso do aparelho.
 *
 * O Android só entrega os dados de uso a apps que o usuário autorizou em
 * "Acesso a dados de uso". Com essa permissão o painel mostra qual app está em
 * primeiro plano, quanto cada app usou nas últimas 24h e quanto tempo a tela
 * ficou acesa — lido do próprio sistema, sem depender de shell (Shizuku/ADB).
 *
 * O app é o "dono" do próprio uid, então depois de autorizado o AppOps não
 * bloqueia a leitura. Campo que o aparelho não expõe volta vazio e o painel
 * mostra "—", nunca um número inventado.
 */
object Usage {

    /** true se o usuário já liberou o acesso ao uso para este app. */
    fun granted(context: Context): Boolean {
        val appOps = context.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager ?: return false
        val mode = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), context.packageName
                )
            }
        } catch (_: Throwable) {
            AppOpsManager.MODE_ERRORED
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    /** Abre a tela do sistema para o usuário liberar o acesso ao uso. */
    fun openSettings(context: Context) {
        try {
            context.startActivity(
                Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        } catch (_: Throwable) {
        }
    }

    private fun label(context: Context, pkg: String): String = try {
        val pm = context.packageManager
        pm.getApplicationLabel(pm.getApplicationInfo(pkg, 0)).toString()
    } catch (_: Throwable) {
        pkg
    }

    private fun hhmm(ms: Long): String {
        val totalMin = ms / 60000
        val h = totalMin / 60
        val m = totalMin % 60
        return if (h > 0) "${h}h ${m}min" else "${m}min"
    }

    /**
     * Lê o uso real e devolve os campos extras no MESMO formato de
     * `panel-stats.sh`, para o painel reusar o renderizador. Sem autorização
     * devolve um objeto vazio (o painel mostra "—" e o botão de liberar).
     */
    fun snapshot(context: Context): JSONObject {
        val o = JSONObject()
        if (!granted(context)) return o
        val usm = context.getSystemService(Context.USAGE_STATS_SERVICE) as? UsageStatsManager ?: return o
        val now = System.currentTimeMillis()
        val dayAgo = now - 24L * 60 * 60 * 1000

        // --- app em primeiro plano agora -------------------------------------
        try {
            @Suppress("DEPRECATION")
            val ev = usm.queryEvents(now - 2L * 60 * 1000, now)
            var lastPkg = ""
            val e = android.app.usage.UsageEvents.Event()
            while (ev.hasNextEvent()) {
                ev.getNextEvent(e)
                if (e.eventType == android.app.usage.UsageEvents.Event.MOVE_TO_FOREGROUND) {
                    lastPkg = e.packageName ?: ""
                }
            }
            if (lastPkg.isNotEmpty()) {
                o.put("fg_pkg", lastPkg)
                o.put("fg_label", label(context, lastPkg))
            }
        } catch (_: Throwable) {
        }

        // --- apps que mais usaram nas últimas 24h ----------------------------
        try {
            val stats = usm.queryUsageStats(UsageStatsManager.INTERVAL_DAILY, dayAgo, now) ?: emptyList()
            val top = stats
                .filter { it.totalTimeInForeground > 0 }
                .sortedByDescending { it.totalTimeInForeground }
                .take(5)
            val arr = JSONArray()
            for (s in top) {
                arr.put(
                    JSONObject()
                        .put("pkg", s.packageName)
                        .put("label", label(context, s.packageName))
                        .put("time_ms", s.totalTimeInForeground)
                        .put("time", hhmm(s.totalTimeInForeground))
                )
            }
            if (arr.length() > 0) o.put("top_apps", arr)
        } catch (_: Throwable) {
        }

        // --- tempo total de uso (tela acesa) nas últimas 24h -----------------
        try {
            val total = usm.queryAndAggregateUsageStats(dayAgo, now).values
                .sumOf { it.totalTimeInForeground }
            if (total > 0) {
                o.put("screen_time_ms", total)
                o.put("screen_time", hhmm(total))
            }
        } catch (_: Throwable) {
        }

        return o
    }
}
