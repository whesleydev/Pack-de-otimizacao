package com.otm.pack

import android.content.Context
import java.security.MessageDigest

/**
 * Acesso por chave no app: primeiro a chave, depois o método de conexão.
 *
 * As chaves são as mesmas do painel web (`sh main.sh web key new`). O app não
 * fala com o PHP, então recebe uma cópia **só com os hashes** em
 * `assets/panel/keys.json` (gerada por `sh main.sh web key sync`). Guardamos
 * apenas o SHA-256 — a chave em texto nunca vai para o APK.
 *
 * A validação é local: normaliza o que o usuário digitou, tira o SHA-256 e
 * compara com a lista. A forma normalizada é idêntica à do `web/keys.php`, então
 * digitar com espaços, sem hífen ou em minúsculas funciona do mesmo jeito.
 */
object KeyGate {

    private const val ASSET = "panel/keys.json"
    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    private const val GROUPS = 3
    private const val GLEN = 4
    private const val PREFIX = "OTM"

    private const val PREF = "otm_gate"
    private const val PREF_OK = "unlocked"

    /** Forma canônica `OTM-XXXX-XXXX-XXXX` (espelha `otm_key_normalize`). */
    fun normalize(raw: String): String {
        val clean = raw.uppercase().replace(Regex("[^A-Z0-9]"), "")
        val body = if (clean.startsWith(PREFIX)) clean.substring(PREFIX.length) else clean
        val groups = ArrayList<String>()
        for (i in 0 until GROUPS) {
            val start = i * GLEN
            if (start >= body.length) break
            groups.add(body.substring(start, minOf(start + GLEN, body.length)))
        }
        return PREFIX + if (groups.isEmpty()) "" else "-" + groups.joinToString("-")
    }

    /** Aceita só chaves bem formadas (mesmo alfabeto sem ambíguos do painel). */
    fun wellFormed(raw: String): Boolean {
        val n = normalize(raw)
        val re = Regex("^$PREFIX(-[$ALPHABET]{$GLEN}){$GROUPS}$")
        return re.matches(n)
    }

    fun hash(raw: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(normalize(raw).toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /**
     * Hashes aceitos, lidos do `assets/panel/keys.json` — um array de SHA-256
     * gerado por `sh main.sh web key sync`.
     */
    private fun hashes(context: Context): Set<String> {
        return try {
            val txt = context.assets.open(ASSET).use { it.readBytes().toString(Charsets.UTF_8) }
            Regex("\"([0-9a-fA-F]{64})\"")
                .findAll(txt).map { it.groupValues[1].lowercase() }.toSet()
        } catch (_: Throwable) {
            emptySet()
        }
    }

    /**
     * Confere a chave digitada contra a lista de hashes do APK. Falha fechado:
     * sem lista (ou vazia) nada é aceito — o app nunca libera por não ter a lista.
     */
    fun verify(context: Context, raw: String): Boolean {
        if (!wellFormed(raw)) return false
        val hs = hashes(context)
        if (hs.isEmpty()) return false
        return hs.contains(hash(raw))
    }

    fun isUnlocked(context: Context): Boolean =
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE).getBoolean(PREF_OK, false)

    fun unlock(context: Context) {
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .edit().putBoolean(PREF_OK, true).apply()
    }

    fun lock(context: Context) {
        context.getSharedPreferences(PREF, Context.MODE_PRIVATE)
            .edit().putBoolean(PREF_OK, false).apply()
    }
}
