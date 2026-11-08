package com.otm.pack

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Histórico de execuções (`state/log.jsonl`) — o que o painel mostra em "Logs".
 *
 * Fica num objeto, e não dentro do [PackBridge], porque **duas origens** escrevem
 * aqui: o painel WebView (ações do PackBridge) e o painel flutuante
 * ([OverlayService]). Antes só o WebView gravava, então o que o usuário mexia no
 * flutuante sumia dos Logs. O formato é o MESMO do lado PHP (`otm_log`), para os
 * dois painéis lerem igual.
 */
object OtmLog {

    /** Quantas execuções o log guarda antes de podar as mais antigas. */
    const val MAX = 800

    /**
     * Onde vive o histórico. Antes era `packDir()/state`, dentro da pasta que o
     * app apaga a cada atualização — instalar uma versão nova zerava o histórico.
     */
    fun stateDir(context: Context): File {
        val dir = PackAssets.stateDir(context)
        // Resgata o histórico da versão anterior (morava dentro do `pack`).
        try {
            val antigo = File(PackAssets.ensureExtracted(context), "state")
            if (antigo.isDirectory) {
                for (nome in listOf("log.jsonl", "term.jsonl")) {
                    val de = File(antigo, nome)
                    val para = File(dir, nome)
                    if (de.isFile && !para.exists()) de.copyTo(para, overwrite = false)
                }
            }
        } catch (_: Throwable) {}
        return dir
    }

    /**
     * Registra uma execução. Além de ok/erro, guarda o que o script tentou
     * (applies/changed/failed), as linhas que explicam a falha e a saída crua.
     */
    fun append(
        context: Context,
        id: String, label: String, cmd: String,
        ok: Boolean, code: Int, out: String = "",
        applies: Int = 0, changed: Int = 0, failed: Int = 0, durMs: Long = 0,
    ) {
        try {
            val f = File(stateDir(context), "log.jsonl")
            f.parentFile?.mkdirs()
            val rec = JSONObject()
                .put("ts", ts())
                .put("id", id).put("label", label).put("cmd", cmd)
                .put("ok", ok).put("code", code)
                .put("applies", applies).put("changed", changed).put("failed", failed)
                .put("dur_ms", durMs)
                .put("reasons", JSONArray(failReasons(out)))
                .put("out", out.take(6000))
                .toString()
            f.appendText(rec + "\n")
            trimLog(f)
        } catch (_: Throwable) {}
    }

    private fun ts(): String =
        java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", java.util.Locale.US)
            .format(java.util.Date())

    /**
     * O log guarda a saída crua de cada ação, então cresce rápido. Mantém as
     * últimas [MAX] linhas: o histórico continua completo para o usuário e o
     * arquivo não vira um peso morto no aparelho.
     */
    private fun trimLog(f: File) {
        try {
            if (f.length() < 1_500_000) return
            val keep = f.readLines().filter { it.isNotBlank() }.takeLast(MAX)
            f.writeText(keep.joinToString("\n") + "\n")
        } catch (_: Throwable) {}
    }

    /**
     * Linhas que explicam POR QUE falhou. Os scripts marcam a falha com "✕"/"X"
     * e dizem o valor lido de volta (ex.: "X tcp_congestion_control nao mudou
     * (lido: cubic)"). Sem isso o log só dizia "erro".
     */
    private fun failReasons(out: String): List<String> {
        if (out.isBlank()) return emptyList()
        val clean = out.replace(Regex("\u001B\\[[0-9;]*m"), "")
        val hit = Regex(
            "^[✕X]|(n[ãa]o (mudou|pegou|consegui|aceitou|encontrei|dispon[íi]vel|existe|permitido)" +
                "|falhou|falha\\(s\\)|sem acesso|denied|denial|not found)",
            RegexOption.IGNORE_CASE,
        )
        return clean.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && hit.containsMatchIn(it) }
            .map { it.replace(Regex("^[✕X]\\s*"), "") }
            .distinct()
            .take(12)
            .toList()
    }
}
