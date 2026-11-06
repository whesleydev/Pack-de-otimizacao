package com.otm.pack

import android.content.Context
import java.security.MessageDigest

/**
 * Login local do app.
 *
 * Não há servidor nem banco de licenças: a credencial é conferida no próprio
 * aparelho, contra um hash embutido. É uma portinha para separar quem é dono de
 * quem pegou o app por fora — não é segurança forte, e não precisa ser: o valor
 * do Trix está no servidor oficial, não numa chave.
 *
 * A sessão e o "aceitei os termos" ficam só neste aparelho.
 */
object AppLogin {

    private const val PREF = "otm_login"
    private const val PREF_LOGGED = "logged"
    private const val PREF_TERMS = "terms_ok"

    private const val USER = "00deUdia"
    /** SHA-256 de "user:senha". A senha não fica em texto no código. */
    private const val HASH = "b6cddaaf9333c33071ae824248927b5349955fbb87167a5c1ddef5afa23d1a4d"

    private fun prefs(c: Context) = c.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    private fun sha256(s: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(s.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /** Confere usuário e senha. Compara o hash inteiro, sem vazar qual parte errou. */
    fun check(user: String, pass: String): Boolean =
        MessageDigest.isEqual(
            sha256(user.trim() + ":" + pass).toByteArray(Charsets.UTF_8),
            HASH.toByteArray(Charsets.UTF_8),
        )

    fun login(c: Context) {
        prefs(c).edit().putBoolean(PREF_LOGGED, true).apply()
    }

    fun logout(c: Context) {
        prefs(c).edit().remove(PREF_LOGGED).apply()
    }

    fun isLogged(c: Context): Boolean = prefs(c).getBoolean(PREF_LOGGED, false)

    /** Nome mostrado no painel (o dono). */
    fun userName(c: Context): String = if (isLogged(c)) USER else ""

    fun termsAccepted(c: Context): Boolean = prefs(c).getBoolean(PREF_TERMS, false)

    fun acceptTerms(c: Context) {
        prefs(c).edit().putBoolean(PREF_TERMS, true).apply()
    }
}
