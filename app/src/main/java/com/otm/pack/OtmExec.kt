package com.otm.pack

import android.content.Context
import kotlinx.coroutines.runBlocking

/**
 * Executa os scripts do pack pelo transporte privilegiado (Shizuku/ADB).
 *
 * O painel (WebView) e o painel flutuante (overlay) precisam rodar os mesmos
 * scripts com o mesmo `HOME` e a mesma pasta de execução. Antes isso morava só
 * no [PackBridge]; agora é compartilhado para o overlay não reimplementar (e
 * divergir) a montagem do comando.
 */
object OtmExec {

    /** Monta `sh <execDir>/scripts/<script> <args>` com `HOME` na pasta de execução. */
    fun scriptCommand(context: Context, runner: ShellRunner?, script: String, args: List<String>): String {
        val dir = PackAssets.ensureShellCopy(context, runner)
            ?: return "echo 'sem acesso (conecte o Shizuku ou o ADB)' >&2; exit 1"
        val sb = StringBuilder()
        sb.append("export HOME='").append(dir).append("'; ")
        sb.append("cd '").append(dir).append("'; ")
        sb.append("sh '").append(dir).append("/scripts/").append(script).append('\'')
        for (a in args) sb.append(" '").append(a.replace("'", "'\\''")).append('\'')
        return sb.toString()
    }

    /** Roda um script do pack e devolve a saída crua. */
    fun run(context: Context, runner: ShellRunner?, script: String, args: List<String>): ExecResult {
        val r = runner ?: return ExecResult(1, "", "sem acesso (conecte o Shizuku ou o ADB)")
        val cmd = scriptCommand(context, r, script, args)
        return try {
            runBlocking { r.exec(cmd) }
        } catch (t: Throwable) {
            ExecResult(1, "", "erro: ${t.message}")
        }
    }

    /** Lê a linha `#OTM-RESULT ... k=v` que os scripts emitem. */
    fun parseResult(out: String): Map<String, String> {
        val m = Regex("#OTM-RESULT\\b(.*)$", RegexOption.MULTILINE).find(out) ?: return emptyMap()
        val kv = HashMap<String, String>()
        for (tok in m.groupValues[1].trim().split(Regex("\\s+"))) {
            val i = tok.indexOf('=')
            if (i > 0) kv[tok.substring(0, i)] = tok.substring(i + 1)
        }
        return kv
    }
}

/**
 * Guarda o transporte conectado ([ShellRunner]) para quem não é a Activity: o
 * painel flutuante roda num Service e precisa do mesmo acesso do painel. Sem
 * isso o overlay não teria como mandar comando nenhum.
 */
object OtmRunner {
    @Volatile
    var current: ShellRunner? = null
}

/**
 * Aparência escolhida no painel, compartilhada com o painel flutuante.
 *
 * A cor de destaque e a fonte são escolhidas no WebView (localStorage), que o
 * Service não enxerga. O painel grava em `SharedPreferences` pela ponte
 * (`OTM.call("ui_prefs", …)`) e o overlay lê daqui, então os dois ficam com o
 * mesmo tema. [onChanged] avisa o overlay na hora, sem precisar reabrir.
 */
object OtmUi {
    const val PREFS = "otm-ui"

    /** Cor de destaque (hex #rrggbb) e a tinta do texto sobre ela. */
    @Volatile var accent: String = "#ff6a2b"
    @Volatile var accentInk: String = "#180d06"

    /** Chave da fonte escolhida no painel (ver `FONTS` no HTML). */
    @Volatile var font: String = "sistema"

    /** Chamado quando a aparência muda, para o overlay se redesenhar. */
    @Volatile var onChanged: (() -> Unit)? = null

    fun load(context: Context) {
        val sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        accent = sp.getString("accent", accent) ?: accent
        accentInk = sp.getString("ink", accentInk) ?: accentInk
        font = sp.getString("font", font) ?: font
    }

    fun save(context: Context, accentHex: String?, ink: String?, fontKey: String?) {
        val sp = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        sp.edit().apply {
            if (!accentHex.isNullOrBlank()) putString("accent", accentHex)
            if (!ink.isNullOrBlank()) putString("ink", ink)
            if (!fontKey.isNullOrBlank()) putString("font", fontKey)
            apply()
        }
        load(context)
        onChanged?.invoke()
    }
}
