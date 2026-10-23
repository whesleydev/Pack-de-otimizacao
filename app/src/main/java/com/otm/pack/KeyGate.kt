package com.otm.pack

import android.content.Context
import android.os.Build
import android.provider.Settings
import org.json.JSONObject
import java.io.BufferedReader
import java.net.HttpURLConnection
import java.net.URL

/**
 * Validação da chave contra o banco (painel PHP), com apoio offline.
 *
 * O APK não guarda o token do banco: quem fala com o Turso é o painel. Aqui só
 * chamamos `api/validate.php`, que devolve se a chave vale agora (ativa,
 * expirada, revogada, limite de aparelhos…).
 *
 * Quando não há internet, cai no modo offline: confere a chave contra a lista
 * de hashes ativos guardada no aparelho (baixada de `api/hashes.php` e/ou
 * embarcada em `assets/panel/keys.json`). Assim o cliente que já entrou
 * continua usando o app mesmo sem rede.
 *
 * Ordem de decisão:
 *   1. online  → resposta do servidor manda (é a fonte da verdade);
 *   2. offline → lista local de hashes (aceita o que estava ativo no último sync);
 *   3. sem lista local → nega (falha fechado).
 */
object KeyGate {

    private const val ASSET = "panel/keys.json"
    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    private const val GROUPS = 3
    private const val GLEN = 4
    private const val PREFIX = "00"

    private const val PREF = "otm_gate"
    private const val PREF_OK = "unlocked"
    private const val PREF_HASHES = "offline_hashes"
    private const val PREF_SYNC_AT = "offline_sync_at"
    private const val PREF_URL = "api_url"
    private const val PREF_SYNC_TOKEN = "sync_token"

    /** Resultado da verificação: o que aconteceu e o que mostrar ao usuário. */
    data class Result(
        val ok: Boolean,
        val status: String,   // ok | expired | revoked | device_limit | use_limit | blocked | unknown | offline_ok | offline_no_list
        val message: String,
        val offline: Boolean = false,
    )

    // -------------------------------------------------------------------------
    //  forma da chave (igual ao painel: otm_key_normalize)
    // -------------------------------------------------------------------------

    fun normalize(raw: String): String {
        val clean = raw.uppercase().replace(Regex("[^A-Z0-9]"), "")
        val body = GROUPS * GLEN
        // O prefixo "00" também é caractere válido do alfabeto: só tira quando
        // sobra corpo suficiente, senão um corpo que comece com "00" perderia
        // os dois primeiros dígitos.
        val stripped = if (clean.startsWith(PREFIX) && clean.length > body) clean.substring(PREFIX.length) else clean
        val trimmed = stripped.take(body)
        val groups = ArrayList<String>()
        for (i in 0 until GROUPS) {
            val start = i * GLEN
            if (start >= trimmed.length) break
            groups.add(trimmed.substring(start, minOf(start + GLEN, trimmed.length)))
        }
        return PREFIX + if (groups.isEmpty()) "" else "-" + groups.joinToString("-")
    }

    fun wellFormed(raw: String): Boolean =
        Regex("^$PREFIX(-[$ALPHABET]{$GLEN}){$GROUPS}$").matches(normalize(raw))

    fun hash(raw: String): String =
        java.security.MessageDigest.getInstance("SHA-256")
            .digest(normalize(raw).toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    // -------------------------------------------------------------------------
    //  configuração (endereço do painel e segredo do sync)
    // -------------------------------------------------------------------------

    private fun prefs(c: Context) = c.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    fun setApiUrl(c: Context, url: String) =
        prefs(c).edit().putString(PREF_URL, url.trim().trimEnd('/')).apply()

    /**
     * Endereço do painel: o que o usuário configurou ou, se não houver, o que
     * veio embutido no build (BuildConfig.PANEL_URL). Vazio = só modo offline.
     */
    fun getApiUrl(c: Context): String {
        val saved = prefs(c).getString(PREF_URL, "") ?: ""
        return saved.ifBlank { BuildConfig.PANEL_URL.trim().trimEnd('/') }
    }

    fun setSyncToken(c: Context, token: String) =
        prefs(c).edit().putString(PREF_SYNC_TOKEN, token.trim()).apply()

    fun getSyncToken(c: Context): String {
        val saved = prefs(c).getString(PREF_SYNC_TOKEN, "") ?: ""
        return saved.ifBlank { BuildConfig.SYNC_TOKEN }
    }

    // -------------------------------------------------------------------------
    //  identificação do aparelho
    // -------------------------------------------------------------------------

    /** Id estável do aparelho (Android ID + modelo). Não é dado pessoal. */
    fun deviceId(c: Context): String {
        val aid = try {
            Settings.Secure.getString(c.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        } catch (_: Throwable) { "" }
        val base = "$aid|${Build.MANUFACTURER}|${Build.MODEL}"
        return java.security.MessageDigest.getInstance("SHA-256")
            .digest(base.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
            .substring(0, 24)
    }

    // -------------------------------------------------------------------------
    //  verificação
    // -------------------------------------------------------------------------

    /** Verifica a chave: online quando possível; sem rede, decide pela lista local. */
    fun check(c: Context, raw: String): Result {
        if (!wellFormed(raw)) {
            return Result(false, "unknown", "Formato inválido. Use 00-XXXX-XXXX-XXXX.")
        }

        val url = getApiUrl(c)
        if (url.isNotEmpty()) {
            checkRemote(c, raw, url)?.let { return it }
            // sem rede: cai no offline
        }
        return checkOffline(c, raw)
    }

    /** Pergunta ao painel. Devolve null quando não há rede/servidor. */
    private fun checkRemote(c: Context, raw: String, base: String): Result? {
        return try {
            val body = JSONObject().apply {
                put("key", normalize(raw))
                put("device_id", deviceId(c))
                put("model", "${Build.MANUFACTURER} ${Build.MODEL}".trim())
                put("android", Build.VERSION.RELEASE ?: "")
                put("app", BuildConfig.VERSION_NAME)
            }.toString()

            val conn = (URL("$base/api/validate.php").openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 6000
                readTimeout = 8000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=utf-8")
                setRequestProperty("Accept", "application/json")
            }
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use(BufferedReader::readText).orEmpty()
            conn.disconnect()

            if (text.isBlank()) return null
            val j = JSONObject(text)
            val ok = j.optBoolean("ok", false)
            val status = j.optString("result", if (ok) "ok" else "unknown")

            // A resposta do servidor decide — inclusive quando nega.
            if (ok) {
                unlock(c)
                rememberOffline(c, hash(raw))
            }
            Result(ok, status, friendly(status, j.optString("message", "")))
        } catch (_: Throwable) {
            null // sem rede, DNS, TLS…: decide offline
        }
    }

    /** Sem internet: confere contra a lista local de hashes ativos. */
    private fun checkOffline(c: Context, raw: String): Result {
        val hs = offlineHashes(c)
        if (hs.isEmpty()) {
            return Result(false, "offline_no_list",
                "Sem internet e sem lista de chaves salva. Conecte-se uma vez para validar.",
                offline = true)
        }
        return if (hs.contains(hash(raw))) {
            unlock(c)
            Result(true, "offline_ok", "Chave válida (modo offline).", offline = true)
        } else {
            Result(false, "unknown", "Chave não reconhecida. Confira com quem te passou.", offline = true)
        }
    }

    private fun friendly(status: String, serverMsg: String): String = when (status) {
        "ok"           -> serverMsg.ifBlank { "Chave válida." }
        "expired"      -> "Sua chave expirou. Fale com o suporte para renovar."
        "revoked"      -> "Esta chave foi revogada."
        "device_limit" -> "Esta chave já está no número máximo de aparelhos."
        "use_limit"    -> "Esta chave atingiu o limite de usos."
        "blocked"      -> "Este aparelho está bloqueado para esta chave."
        "unknown"      -> "Chave não reconhecida. Confira com quem te passou."
        "rate_limit"   -> "Muitas tentativas. Aguarde um instante e tente de novo."
        "server_error" -> "Servidor indisponível agora. Tente de novo em instantes."
        else           -> serverMsg.ifBlank { "Não consegui validar a chave agora." }
    }

    // -------------------------------------------------------------------------
    //  lista offline de hashes
    // -------------------------------------------------------------------------

    /** Hashes ativos conhecidos: os do sync (preferência) + os do APK. */
    fun offlineHashes(c: Context): Set<String> {
        val saved = prefs(c).getStringSet(PREF_HASHES, emptySet()) ?: emptySet()
        return if (saved.isNotEmpty()) saved.map { it.lowercase() }.toSet() else assetHashes(c)
    }

    private fun assetHashes(c: Context): Set<String> = try {
        val txt = c.assets.open(ASSET).use { it.readBytes().toString(Charsets.UTF_8) }
        Regex("\"([0-9a-fA-F]{64})\"").findAll(txt).map { it.groupValues[1].lowercase() }.toSet()
    } catch (_: Throwable) { emptySet() }

    private fun rememberOffline(c: Context, hash: String) {
        val cur = prefs(c).getStringSet(PREF_HASHES, emptySet()) ?: emptySet()
        if (cur.contains(hash)) return
        prefs(c).edit().putStringSet(PREF_HASHES, cur + hash).apply()
    }

    /**
     * Baixa a lista de chaves ativas do painel e guarda no aparelho. É o que
     * mantém o modo offline correto: o que foi revogado sai da lista.
     * @return nº de hashes recebidos, ou -1 em caso de falha.
     */
    fun syncOffline(c: Context): Int {
        val url = getApiUrl(c)
        val token = getSyncToken(c)
        if (url.isEmpty() || token.isEmpty()) return -1
        return try {
            val conn = (URL("$url/api/hashes.php?token=$token").openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = 6000
                readTimeout = 8000
                setRequestProperty("Accept", "application/json")
            }
            val code = conn.responseCode
            val text = (if (code in 200..299) conn.inputStream else conn.errorStream)
                ?.bufferedReader()?.use(BufferedReader::readText).orEmpty()
            conn.disconnect()
            if (code !in 200..299 || text.isBlank()) return -1

            val j = JSONObject(text)
            if (!j.optBoolean("ok", false)) return -1
            val arr = j.optJSONArray("hashes") ?: return -1
            val set = HashSet<String>(arr.length())
            for (i in 0 until arr.length()) set.add(arr.optString(i).lowercase())

            prefs(c).edit()
                .putStringSet(PREF_HASHES, set)
                .putLong(PREF_SYNC_AT, System.currentTimeMillis())
                .apply()
            set.size
        } catch (_: Throwable) { -1 }
    }

    fun lastSyncAt(c: Context): Long = prefs(c).getLong(PREF_SYNC_AT, 0L)

    // -------------------------------------------------------------------------
    //  estado local de entrada
    // -------------------------------------------------------------------------

    fun isUnlocked(c: Context): Boolean = prefs(c).getBoolean(PREF_OK, false)

    fun unlock(c: Context) { prefs(c).edit().putBoolean(PREF_OK, true).apply() }

    fun lock(c: Context) { prefs(c).edit().putBoolean(PREF_OK, false).apply() }

    /** Compatibilidade: verificação booleana simples (online com fallback). */
    fun verify(c: Context, raw: String): Boolean = check(c, raw).ok
}
