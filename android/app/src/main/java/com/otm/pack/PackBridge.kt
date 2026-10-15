package com.otm.pack

import android.content.Context
import android.webkit.JavascriptInterface
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Uma ação do painel: espelha o registro de web/lib.php (otm_actions). */
private class Action(
    val id: String,
    val group: String,
    val label: String,
    val confirm: Boolean,
    val argv: List<String>,
    val params: List<Param>,
)

private class Param(
    val name: String,
    val type: String,
    val default: String?,
    val optional: Boolean,
    val min: Double?,
    val max: Double?,
    val options: List<String>,
)

/**
 * Ponte entre o painel web (WebView) e o Android.
 *
 * O painel foi feito em PHP; no app ele vira um HTML estático que, em vez de
 * chamar `api.php`, chama `OTM.call()` por JavaScript. Cada ação é montada igual
 * ao `otm_run` do painel: valida parâmetros, troca os marcadores `{nome}` e roda
 * `sh <script> <args>` com HOME na pasta do app (para os scripts gravarem o
 * estado em `~/.packotm`).
 *
 * A chamada é assíncrona: o trabalho roda fora da thread de UI (ações podem
 * demorar minutos) e o resultado volta por [deliver], que avalia um callback no
 * próprio WebView. Sem isso, uma ação longa travaria a interface.
 */
class PackBridge(
    private val context: Context,
    private val runnerProvider: () -> ShellRunner?,
    private val onConnect: () -> Unit,
    private val onSoundToggle: () -> Boolean,
    private val onActionSound: (String) -> Unit,
    private val deliver: (cbId: String, json: String) -> Unit,
) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val actions: Map<String, Action> = loadCatalog()

    /** Ponto único chamado pelo JS: `OTM.call(kind, payloadJson, cbId)`. */
    @JavascriptInterface
    fun call(kind: String, payload: String, cbId: String) {
        scope.launch {
            val json = try {
                when (kind) {
                    "run" -> runImpl(payload)
                    "status" -> textResult(scriptCommand("pack.sh", listOf("status")))
                    "dns" -> textResult(scriptCommand("dns.sh", listOf("status")))
                    "mode" -> modeImpl()
                    "apps" -> appsImpl()
                    "modules" -> modulesImpl()
                    "log" -> logImpl()
                    "actions" -> actionsImpl()
                    "info" -> infoImpl()
                    "connect" -> { withContext(Dispatchers.Main) { onConnect() }; okJson() }
                    "sound" -> JSONObject().put("ok", true)
                        .put("muted", withContext(Dispatchers.Main) { onSoundToggle() }).toString()
                    else -> err("ação desconhecida: $kind")
                }
            } catch (t: Throwable) {
                err("erro: ${t.message}")
            }
            deliver(cbId, json)
        }
    }

    // ---- implementações ------------------------------------------------------

    private fun runImpl(bodyJson: String): String {
        val body = try { JSONObject(bodyJson) } catch (e: Exception) { JSONObject() }
        val id = body.optString("id")
        val paramsObj = body.optJSONObject("params") ?: JSONObject()
        val confirm = body.optBoolean("confirm", false)

        val a = actions[id] ?: return err("ação desconhecida: $id")
        if (a.confirm && !confirm) {
            return JSONObject().put("ok", false).put("need_confirm", true)
                .put("out", "esta ação pede confirmação").toString()
        }

        val resolved = HashMap<String, String>()
        for (p in a.params) {
            val v = paramsObj.optString(p.name, p.default ?: "").trim()
            if (v.isEmpty()) {
                if (p.optional) { resolved["{${p.name}}"] = ""; continue }
                return err("faltou o parâmetro '${p.name}'")
            }
            validate(p, v)?.let { return err(it) }
            resolved["{${p.name}}"] = if (p.type == "float") v.toDouble().toString() else v
        }

        val argv = ArrayList<String>()
        for (piece in a.argv) {
            val rv = resolved[piece]
            if (rv != null) { if (rv.isNotEmpty()) argv.add(rv) } else argv.add(piece)
        }

        onActionSound(soundFor(a.group))
        val res = shell(scriptCommand(argv[0], argv.drop(1)))
        val out = joinOutput(res.stdout, res.stderr)
        val v = parseResult(out)
        val applies = v["applies"]?.toIntOrNull() ?: 0
        val changed = v["changed"]?.toIntOrNull() ?: 0
        val failed = v["failed"]?.toIntOrNull() ?: 0
        val applied = applies > 0
        val real = !applied || changed > 0

        var ok = res.ok
        var text = out
        if (applied && changed == 0) {
            ok = false
            text += "\n\n⚠ Nenhuma alteração real no sistema" +
                (if (failed > 0) " ($failed tentativa(s) não pegaram)" else "") +
                ".\nConfira o acesso em Configs: sem Shizuku/ADB/root os ajustes não aplicam."
        }

        return JSONObject()
            .put("ok", ok).put("code", res.code).put("out", text)
            .put("id", id).put("label", a.label)
            .put("applies", applies).put("changed", changed).put("failed", failed)
            .put("applied", applied).put("real", real)
            .toString()
    }

    private fun modeImpl(): String {
        val out = output(scriptCommand("config.sh", listOf("show")))
        val m = Regex("detectado agora\\s*:\\s*(\\S+)").find(out)?.groupValues?.get(1) ?: ""
        val priv = Regex("privilégio\\s*:\\s*([^\\n]+)").find(out)?.groupValues?.get(1)?.trim() ?: ""
        return JSONObject().put("ok", true).put("mode", m).put("priv", priv).put("text", out).toString()
    }

    private fun appsImpl(): String {
        val out = output(scriptCommand("adb-tweaks.sh", listOf("raw", "pm list packages -3")))
        val list = ArrayList<String>()
        for (line in out.split("\n")) {
            val l = line.trim().removePrefix("package:")
            if (PKG.matches(l)) list.add(l)
        }
        list.sort()
        return JSONObject().put("ok", true).put("apps", JSONArray(list)).toString()
    }

    private fun modulesImpl(): String {
        val out = output(scriptCommand("modules.sh", listOf("list")))
        val arr = JSONArray()
        for (line in out.split("\n")) {
            val l = line.trim()
            if (l.isEmpty() || l.contains("◆") || l.contains("─") ||
                l.contains("executar:") || l.contains("atalho:")) continue
            val parts = l.split(Regex("\\s+"))
            if (parts.size == 2) arr.put(JSONObject().put("name", parts[0]).put("group", parts[1]))
        }
        return JSONObject().put("ok", true).put("modules", arr).toString()
    }

    private fun logImpl(): String {
        val f = File(packDir(), "state/log.jsonl")
        val arr = JSONArray()
        if (f.isFile) {
            val lines = f.readLines().filter { it.isNotBlank() }.takeLast(40).reversed()
            for (l in lines) try { arr.put(JSONObject(l)) } catch (_: Exception) {}
        }
        return JSONObject().put("ok", true).put("log", arr).toString()
    }

    private fun actionsImpl(): String {
        val out = JSONArray()
        for (a in actions.values) {
            val params = JSONArray()
            for (p in a.params) {
                val o = JSONObject().put("name", p.name).put("type", p.type)
                p.default?.let { o.put("default", it) }
                if (p.optional) o.put("optional", true)
                p.min?.let { o.put("min", it) }
                p.max?.let { o.put("max", it) }
                params.put(o)
            }
            out.put(
                JSONObject().put("id", a.id).put("label", a.label)
                    .put("risk", "safe").put("confirm", a.confirm).put("params", params)
            )
        }
        return JSONObject().put("ok", true).put("actions", out).toString()
    }

    private fun infoImpl(): String = JSONObject()
        .put("ok", true).put("root", packDir().absolutePath)
        .put("php", "android").put("have_adb", false).put("have_timeout", false)
        .toString()

    // ---- execução ------------------------------------------------------------

    private fun shell(cmd: String): ExecResult {
        val r = runnerProvider() ?: return ExecResult(1, "", "sem acesso (conecte o Shizuku ou o ADB)")
        return try { runBlocking { r.exec(cmd) } }
        catch (t: Throwable) { ExecResult(1, "", "erro: ${t.message}") }
    }

    private fun output(cmd: String): String {
        val res = shell(cmd)
        return joinOutput(res.stdout, res.stderr)
    }

    private fun textResult(cmd: String): String =
        JSONObject().put("ok", true).put("text", output(cmd)).toString()

    /** Monta `sh <pasta>/scripts/<script> <args>` com HOME na pasta do app. */
    private fun scriptCommand(script: String, args: List<String>): String {
        val dir = packDir().absolutePath
        val sb = StringBuilder()
        sb.append("export HOME='").append(dir).append("'; ")
        sb.append("cd '").append(dir).append("'; ")
        sb.append("sh '").append(dir).append("/scripts/").append(script).append('\'')
        for (a in args) sb.append(" '").append(a.replace("'", "'\\''")).append('\'')
        return sb.toString()
    }

    private fun packDir(): File = PackAssets.ensureExtracted(context)

    private fun parseResult(out: String): Map<String, String> {
        val m = Regex("#OTM-RESULT\\b(.*)$", RegexOption.MULTILINE).find(out) ?: return emptyMap()
        val kv = HashMap<String, String>()
        for (tok in m.groupValues[1].trim().split(Regex("\\s+"))) {
            val i = tok.indexOf('=')
            if (i > 0) kv[tok.substring(0, i)] = tok.substring(i + 1)
        }
        return kv
    }

    private fun validate(p: Param, v: String): String? {
        when (p.type) {
            "pkg" -> if (!PKG.matches(v)) return "pacote inválido: $v"
            "host" -> if (!HOST.matches(v)) return "host inválido: $v"
            "int" -> {
                if (!INT.matches(v)) return "${p.name} não é número"
                val n = v.toInt()
                if (p.min != null && n < p.min) return "${p.name} abaixo do mínimo"
                if (p.max != null && n > p.max) return "${p.name} acima do máximo"
            }
            "float" -> {
                val f = v.toDoubleOrNull() ?: return "${p.name} não é número"
                if (p.min != null && f < p.min) return "${p.name} abaixo do mínimo"
                if (p.max != null && f > p.max) return "${p.name} acima do máximo"
            }
            "name" -> if (!NAME.matches(v)) return "${p.name} inválido"
            "enum" -> if (v !in p.options) return "${p.name} inválido (use: ${p.options.joinToString("|")})"
            else -> if (!TEXT.matches(v)) return "${p.name} inválido"
        }
        return null
    }

    private fun soundFor(group: String): String = when (group) {
        "RAM / Limpeza", "Congelar apps" -> "liberando-memoria-ram.mp3"
        "DNS", "Wi-Fi e rede" -> "configurando-dns.mp3"
        "Renderizador", "Por app / jogo", "Profundas (root)", "Extremos (root)" -> "ativando.mp3"
        "Touch / Free Fire", "Debloat" -> "configurando.mp3"
        else -> "otimizando-o-sistema.mp3"
    }

    private fun okJson(): String = JSONObject().put("ok", true).toString()

    private fun err(msg: String): String = JSONObject().put("ok", false).put("out", msg).toString()

    // ---- catálogo ------------------------------------------------------------

    private fun loadCatalog(): Map<String, Action> {
        val map = LinkedHashMap<String, Action>()
        try {
            val raw = context.assets.open("panel/actions.json").use { it.readBytes().toString(Charsets.UTF_8) }
            val arr = JSONArray(raw)
            for (i in 0 until arr.length()) {
                val o = arr.getJSONObject(i)
                val argv = o.getJSONArray("argv").let { a -> (0 until a.length()).map { a.getString(it) } }
                val params = ArrayList<Param>()
                val pa = o.optJSONArray("params")
                if (pa != null) for (j in 0 until pa.length()) {
                    val p = pa.getJSONObject(j)
                    params.add(
                        Param(
                            name = p.getString("name"),
                            type = p.optString("type", "text"),
                            default = if (p.has("default")) p.getString("default") else null,
                            optional = p.optBoolean("optional", false),
                            min = if (p.has("min")) p.getDouble("min") else null,
                            max = if (p.has("max")) p.getDouble("max") else null,
                            options = p.optJSONArray("options")?.let { a -> (0 until a.length()).map { a.getString(it) } } ?: emptyList(),
                        )
                    )
                }
                map[o.getString("id")] = Action(
                    id = o.getString("id"),
                    group = o.optString("group", ""),
                    label = o.optString("label", o.getString("id")),
                    confirm = o.optBoolean("confirm", false),
                    argv = argv,
                    params = params,
                )
            }
        } catch (t: Throwable) {
            // sem catálogo o painel ainda mostra os cards; só não executa
        }
        return map
    }

    private companion object {
        val PKG = Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z0-9_]+)+$")
        val HOST = Regex("^[A-Za-z0-9]([A-Za-z0-9.-]{0,61}[A-Za-z0-9])?$")
        val INT = Regex("^-?\\d+$")
        val NAME = Regex("^[A-Za-z0-9._-]{1,40}$")
        val TEXT = Regex("^[A-Za-z0-9 ._:-]{0,40}$")
    }
}
