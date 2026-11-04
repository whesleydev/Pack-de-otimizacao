package com.otm.pack

import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Cliente mínimo do Turso (libSQL) sobre a HTTP API v2 (`/v2/pipeline`).
 *
 * Espelha `panel/src/Turso.php`: manda vários comandos numa só ida à rede e
 * devolve as linhas como mapas coluna→valor. É o único ponto que fala com o
 * banco — o resto do app usa [TursoClient.query]/[TursoClient.run].
 */
class TursoClient(endpoint: String, private val token: String) {

    /** Endereço do pipeline. Aceita `libsql://` e converte para `https://`. */
    private val url: String = normalize(endpoint)

    private fun normalize(raw: String): String {
        var s = raw.trim().trimEnd('/')
        s = when {
            s.startsWith("libsql://") -> "https://" + s.removePrefix("libsql://")
            s.startsWith("http://") || s.startsWith("https://") -> s
            s.isEmpty() -> ""
            else -> "https://$s"
        }
        if (s.isNotEmpty() && !s.endsWith("/v2/pipeline")) s += "/v2/pipeline"
        return s
    }

    fun isConfigured(): Boolean = url.isNotEmpty() && token.isNotEmpty()

    /** Uma linha ou null. */
    fun one(sql: String, args: List<Any?> = emptyList()): JSONObject? = all(sql, args).firstOrNull()

    /** Primeiro campo da primeira linha. */
    fun scalar(sql: String, args: List<Any?> = emptyList()): String? {
        val row = one(sql, args) ?: return null
        val key = row.keys().asSequence().firstOrNull() ?: return null
        return if (row.isNull(key)) null else row.get(key).toString()
    }

    /** Escrita/DDL: devolve quantas linhas mudaram. */
    fun run(sql: String, args: List<Any?> = emptyList()): Int =
        pipeline(listOf(stmt(sql, args))).firstOrNull()
            ?.optJSONObject("result")?.optInt("affected_row_count", 0) ?: 0

    /** INSERT que devolve o id gerado. */
    fun insert(sql: String, args: List<Any?> = emptyList()): Long =
        pipeline(listOf(stmt(sql, args))).firstOrNull()
            ?.optJSONObject("result")?.optString("last_insert_rowid", "")
            ?.takeIf { it.isNotEmpty() && it != "null" }?.toLongOrNull() ?: 0L

    /** Vários comandos numa ida só (transação implícita). */
    fun batch(statements: List<Pair<String, List<Any?>>>): List<JSONObject> =
        pipeline(statements.map { stmt(it.first, it.second) })

    fun all(sql: String, args: List<Any?> = emptyList()): List<JSONObject> =
        rows(pipeline(listOf(stmt(sql, args))).firstOrNull() ?: JSONObject())

    fun ping(): String = scalar("select sqlite_version()") ?: ""

    // -------------------------------------------------------------------------

    private fun stmt(sql: String, args: List<Any?>): JSONObject {
        val typed = JSONArray()
        for (a in args) typed.put(typedArg(a))
        return JSONObject()
            .put("type", "execute")
            .put("stmt", JSONObject().put("sql", sql).put("args", typed))
    }

    /** Converte um valor Kotlin no argumento tipado que o Turso espera. */
    private fun typedArg(v: Any?): JSONObject = when (v) {
        null -> JSONObject().put("type", "null")
        is Boolean -> JSONObject().put("type", "integer").put("value", if (v) "1" else "0")
        is Int -> JSONObject().put("type", "integer").put("value", v.toString())
        is Long -> JSONObject().put("type", "integer").put("value", v.toString())
        is Double -> JSONObject().put("type", "float").put("value", v.toString())
        else -> JSONObject().put("type", "text").put("value", v.toString())
    }

    /** POST do pipeline; devolve a lista de `response` do tipo execute. */
    private fun pipeline(requests: List<JSONObject>): List<JSONObject> {
        if (!isConfigured()) throw IllegalStateException("banco não configurado")
        val reqs = JSONArray()
        for (r in requests) reqs.put(r)
        reqs.put(JSONObject().put("type", "close"))
        val body = JSONObject().put("requests", reqs).toString()

        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            connectTimeout = 8000
            readTimeout = 15000
            doOutput = true
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Content-Type", "application/json")
        }
        val raw: String
        try {
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            raw = stream?.bufferedReader()?.use(BufferedReader::readText).orEmpty()
        } finally {
            conn.disconnect()
        }

        val json = try { JSONObject(raw) } catch (e: Exception) {
            throw IllegalStateException("resposta inválida do banco")
        }
        json.optString("error").takeIf { it.isNotEmpty() }?.let {
            throw IllegalStateException("banco: $it")
        }

        val out = ArrayList<JSONObject>()
        val results = json.optJSONArray("results") ?: JSONArray()
        for (i in 0 until results.length()) {
            val r = results.getJSONObject(i)
            if (r.optString("type") == "error") {
                throw IllegalStateException(
                    "banco: " + (r.optJSONObject("error")?.optString("message") ?: "erro")
                )
            }
            val resp = r.optJSONObject("response") ?: continue
            if (resp.optString("type") == "execute") out.add(resp)
        }
        return out
    }

    /** Transforma a resposta de um execute em linhas coluna→valor. */
    private fun rows(resp: JSONObject): List<JSONObject> {
        val result = resp.optJSONObject("result") ?: return emptyList()
        val cols = result.optJSONArray("cols") ?: return emptyList()
        val names = ArrayList<String>()
        for (i in 0 until cols.length()) names.add(cols.getJSONObject(i).optString("name"))

        val out = ArrayList<JSONObject>()
        val rowArr = result.optJSONArray("rows") ?: JSONArray()
        for (r in 0 until rowArr.length()) {
            val cells = rowArr.getJSONArray(r)
            val row = JSONObject()
            for (c in names.indices) {
                val cell = if (c < cells.length()) cells.optJSONObject(c) else null
                row.put(names[c], untyped(cell))
            }
            out.add(row)
        }
        return out
    }

    /** Valor "solto" de uma célula tipada; null quando o campo é NULL. */
    private fun untyped(cell: JSONObject?): Any? {
        if (cell == null) return JSONObject.NULL
        return when (cell.optString("type")) {
            "null" -> JSONObject.NULL
            "integer" -> cell.optString("value").toLongOrNull() ?: JSONObject.NULL
            "float" -> cell.optString("value").toDoubleOrNull() ?: JSONObject.NULL
            else -> cell.optString("value")
        }
    }
}
