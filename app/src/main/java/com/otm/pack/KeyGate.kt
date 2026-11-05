package com.otm.pack

import android.content.Context
import android.os.Build
import android.provider.Settings
import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Chaves de acesso (licenças) e a sessão local.
 *
 * O formato é `00-XXXX-XXXX-XXXX` (o mesmo do painel antigo): alfabeto sem
 * caracteres ambíguos, três grupos de quatro. Do que o usuário digita, só o
 * SHA-256 vai para o banco — a chave em claro nunca é gravada.
 *
 * A validação fala direto com o Turso ([TursoClient]). Quando não há rede, cai
 * no cache local: a última chave que entrou continua valendo por alguns dias,
 * para o app não travar sem internet. A decisão é sempre "falha fechado":
 * sem banco e sem cache, nega.
 */
object KeyGate {

    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    private const val GROUPS = 3
    private const val GLEN = 4

    /** Prefixo das chaves de dono/admin. */
    const val PREFIX_OWNER = "00"

    /** Prefixo das chaves de usuário comum. */
    const val PREFIX_USER = "TRIX"

    /** Prefixo que a chave de cada papel usa. */
    fun prefixFor(role: String): String = if (role == "user") PREFIX_USER else PREFIX_OWNER

    private const val PREF = "otm_gate"
    private const val PREF_SESSION = "session_key_hash"
    private const val PREF_ROLE = "session_role"
    private const val PREF_LABEL = "session_label"
    private const val PREF_EXPIRES = "session_expires"
    private const val PREF_OFFLINE_UNTIL = "offline_until"
    private const val PREF_MAX_SEEN = "max_seen_epoch"
    private const val PREF_PREFIX = "session_prefix"
    private const val PREF_TAIL = "session_tail"
    private const val PREF_NICK = "profile_nick"

    /** Tolerância de relógio (segundos) antes de acusar adulteração. */
    private const val CLOCK_TOLERANCE = 3600L

    /** Quantos dias a chave continua valendo sem falar com o banco. */
    private const val OFFLINE_DAYS = 7L

    const val ROLE_OWNER = "owner"

    /** Resultado da verificação: o que aconteceu e o que mostrar ao usuário. */
    data class Result(
        val ok: Boolean,
        val status: String,
        val message: String,
        val label: String = "",
        val role: String = "user",
        val expiresAt: String? = null,
        val offline: Boolean = false,
    )

    // -------------------------------------------------------------------------
    //  formato da chave
    // -------------------------------------------------------------------------

    /**
     * Descobre qual prefixo a chave digitada usa. "TRIX" é o prefixo de usuário;
     * qualquer outra coisa cai em "00" (dono/admin).
     */
    fun detectPrefix(raw: String): String {
        val clean = raw.uppercase().replace(Regex("[^A-Z0-9]"), "")
        return if (clean.startsWith(PREFIX_USER)) PREFIX_USER else PREFIX_OWNER
    }

    fun normalize(raw: String): String = normalize(raw, detectPrefix(raw))

    fun normalize(raw: String, prefix: String): String {
        val clean = raw.uppercase().replace(Regex("[^A-Z0-9]"), "")
        val body = GROUPS * GLEN
        // O prefixo também é feito de caracteres do alfabeto: só remove quando
        // sobra corpo suficiente, senão um corpo que comece igual perderia dígitos.
        val stripped = if (clean.startsWith(prefix) && clean.length > body) clean.substring(prefix.length) else clean
        val trimmed = stripped.take(body)
        val groups = ArrayList<String>()
        for (i in 0 until GROUPS) {
            val start = i * GLEN
            if (start >= trimmed.length) break
            groups.add(trimmed.substring(start, minOf(start + GLEN, trimmed.length)))
        }
        return prefix + if (groups.isEmpty()) "" else "-" + groups.joinToString("-")
    }

    private val OWNER_RE = Regex("^$PREFIX_OWNER(-[$ALPHABET]{$GLEN}){$GROUPS}$")
    private val USER_RE = Regex("^$PREFIX_USER(-[$ALPHABET]{$GLEN}){$GROUPS}$")

    fun wellFormed(raw: String): Boolean =
        OWNER_RE.matches(normalize(raw)) || USER_RE.matches(normalize(raw))

    fun hash(raw: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(normalize(raw).toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    /** Gera uma chave nova. `role` decide o prefixo: usuário usa "TRIX". */
    fun generate(role: String = "user"): String {
        val prefix = prefixFor(role)
        val rnd = SecureRandom()
        val sb = StringBuilder()
        repeat(GROUPS * GLEN) { sb.append(ALPHABET[rnd.nextInt(ALPHABET.length)]) }
        return normalize(sb.toString(), prefix)
    }

    /** Pedaço visível (00-XXXX / TRIX-XXXX) para identificar sem revelar a chave. */
    fun prefixOf(raw: String): String {
        val p = detectPrefix(raw)
        return p + "-" + normalize(raw).removePrefix(p).removePrefix("-").take(GLEN)
    }

    /** Últimos caracteres da chave: o bastante para reconhecê-la, não para usá-la. */
    fun tailOf(raw: String): String =
        normalize(raw).substringAfter("-").replace("-", "").takeLast(GLEN)

    /**
     * Rótulo com o **começo e o fim** da chave e o meio escondido
     * (`00-FWYE-····-99WV`). É o que aparece nas listas: dá para bater o olho e
     * reconhecer a chave sem expor o miolo, que é o que interessa a quem rouba.
     */
    fun maskOf(raw: String): String = maskOf(prefixOf(raw), tailOf(raw))

    fun maskOf(prefix: String, tail: String): String {
        val p = prefix.ifBlank { PREFIX_OWNER + "-····" }
        val t = tail.ifBlank { "····" }
        return "$p-····-$t"
    }

    // -------------------------------------------------------------------------
    //  cofre da chave (para o dono poder ver/copiar depois)
    // -------------------------------------------------------------------------

    /**
     * Guarda a chave em claro no banco, cifrada, para o dono poder revelar e
     * copiar depois. O `key_hash` sozinho não permite reconstruir a chave, e sem
     * isso uma chave vendida e perdida não teria como ser reenviada.
     *
     * O sigilo aqui é limitado de propósito: a chave de cifra é derivada do
     * token do banco, que vai no APK. Quem tem o APK e o token consegue abrir.
     * Serve para a chave não ficar em texto puro num dump do banco — não é
     * segredo forte. Por isso o painel só revela uma chave por vez, e não a
     * lista inteira de uma vez.
     */
    private const val SEAL_SALT = "otm-pack:cofre-de-chave:v1"

    private fun sealKey(): SecretKeySpec {
        val base = BuildConfig.TURSO_TOKEN + "|" + SEAL_SALT
        val digest = MessageDigest.getInstance("SHA-256").digest(base.toByteArray(Charsets.UTF_8))
        return SecretKeySpec(digest, "AES")
    }

    /** Cifra a chave (AES-GCM). Devolve base64(iv || ciphertext). */
    fun seal(raw: String): String {
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, sealKey(), GCMParameterSpec(128, iv))
        val out = c.doFinal(normalize(raw).toByteArray(Charsets.UTF_8))
        val buf = ByteArray(iv.size + out.size)
        System.arraycopy(iv, 0, buf, 0, iv.size)
        System.arraycopy(out, 0, buf, iv.size, out.size)
        return Base64.encodeToString(buf, Base64.NO_WRAP)
    }

    /** Abre o que [seal] cifrou. Devolve null se o blob for de outra instalação. */
    fun unseal(blob: String): String? = try {
        val buf = Base64.decode(blob, Base64.NO_WRAP)
        if (buf.size <= 12) null else {
            val c = Cipher.getInstance("AES/GCM/NoPadding")
            c.init(Cipher.DECRYPT_MODE, sealKey(), GCMParameterSpec(128, buf.copyOfRange(0, 12)))
            normalize(String(c.doFinal(buf.copyOfRange(12, buf.size)), Charsets.UTF_8))
        }
    } catch (_: Throwable) { null }

    // -------------------------------------------------------------------------
    //  aparelho
    // -------------------------------------------------------------------------

    /** Id estável do aparelho (Android ID + modelo), hasheado. Não é dado pessoal. */
    fun deviceId(c: Context): String {
        val aid = try {
            Settings.Secure.getString(c.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
        } catch (_: Throwable) { "" }
        val base = "$aid|${Build.MANUFACTURER}|${Build.MODEL}"
        return MessageDigest.getInstance("SHA-256")
            .digest(base.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
            .substring(0, 24)
    }

    // -------------------------------------------------------------------------
    //  cliente do banco
    // -------------------------------------------------------------------------

    private fun db(): TursoClient = TursoClient(BuildConfig.TURSO_URL, BuildConfig.TURSO_TOKEN)

    fun dbConfigured(): Boolean = db().isConfigured()

    // -------------------------------------------------------------------------
    //  sessão local
    // -------------------------------------------------------------------------

    private fun prefs(c: Context) = c.getSharedPreferences(PREF, Context.MODE_PRIVATE)

    fun sessionRole(c: Context): String = prefs(c).getString(PREF_ROLE, "") ?: ""
    fun sessionLabel(c: Context): String = prefs(c).getString(PREF_LABEL, "") ?: ""
    /** Prefixo da chave da sessão (00-XXXX / TRIX-XXXX) para mostrar no perfil. */
    fun sessionPrefix(c: Context): String = prefs(c).getString(PREF_PREFIX, "") ?: ""
    /** Fim da chave da sessão, para o rótulo "começo-····-fim". */
    fun sessionTail(c: Context): String = prefs(c).getString(PREF_TAIL, "") ?: ""
    /** Rótulo da chave da sessão com começo e fim (`00-FWYE-····-99WV`). */
    fun sessionMask(c: Context): String = maskOf(sessionPrefix(c), sessionTail(c))
    /** SHA-256 da chave da sessão (nunca a chave em claro). */
    fun sessionHash(c: Context): String = prefs(c).getString(PREF_SESSION, "") ?: ""
    /** Validade combinada na entrada (texto UTC), vazio quando é vitalícia. */
    fun sessionExpires(c: Context): String = prefs(c).getString(PREF_EXPIRES, "") ?: ""

    /** Apelido do perfil: só deste aparelho, não vai para o banco. */
    fun nick(c: Context): String = prefs(c).getString(PREF_NICK, "") ?: ""

    fun setNick(c: Context, value: String) {
        prefs(c).edit().putString(PREF_NICK, value.trim().take(40)).apply()
    }

    fun isLogged(c: Context): Boolean = (prefs(c).getString(PREF_SESSION, "") ?: "").isNotEmpty()
    fun isOwner(c: Context): Boolean = sessionRole(c) == ROLE_OWNER

    fun logout(c: Context) {
        prefs(c).edit()
            .remove(PREF_SESSION).remove(PREF_ROLE).remove(PREF_LABEL).remove(PREF_EXPIRES)
            .remove(PREF_PREFIX).remove(PREF_TAIL)
            .apply()
    }

    private fun saveSession(
        c: Context,
        keyHash: String,
        role: String,
        label: String,
        expiresAt: String?,
        prefix: String,
        tail: String,
    ) {
        val now = System.currentTimeMillis() / 1000L
        prefs(c).edit()
            .putString(PREF_SESSION, keyHash)
            .putString(PREF_ROLE, role)
            .putString(PREF_LABEL, label)
            .putString(PREF_PREFIX, prefix)
            .putString(PREF_TAIL, tail)
            .putString(PREF_EXPIRES, expiresAt ?: "")
            .putString(PREF_OFFLINE_UNTIL, (now + OFFLINE_DAYS * 86400).toString())
            .putLong(PREF_MAX_SEEN, now)
            .apply()
    }

    // -------------------------------------------------------------------------
    //  entrada
    // -------------------------------------------------------------------------

    /** Valida a chave: online quando dá; sem rede, decide pelo cache local. */
    fun check(c: Context, raw: String): Result {
        if (!wellFormed(raw)) {
            return Result(false, "unknown", "Formato inválido. Use 00-XXXX-XXXX-XXXX (admin) ou TRIX-XXXX-XXXX-XXXX (usuário).")
        }
        val key = normalize(raw)
        val h = hash(key)

        if (dbConfigured()) {
            val remote = try { checkRemote(c, key, h) } catch (_: Throwable) { null }
            if (remote != null) return remote
        }
        return checkOffline(c, h)
    }

    /** Pergunta ao banco. Devolve null quando não há rede (para cair no offline). */
    private fun checkRemote(c: Context, key: String, h: String): Result? {
        val db = db()
        val row = db.one("SELECT * FROM otm_keys WHERE key_hash = ?", listOf(h)) ?: run {
            logEvent(db, null, prefixOf(key), "unknown", c, "Chave não encontrada.")
            return Result(false, "unknown", "Chave não reconhecida. Confira com quem te passou.")
        }

        val keyId = row.optLong("id")
        val label = row.optString("label")
        val role = row.optString("role").ifBlank { "user" }
        val now = nowUtc()

        if (row.optString("revoked_at").isNotEmpty()) {
            logEvent(db, keyId, prefixOf(key), "revoked", c, "Chave revogada.")
            return Result(false, "revoked", "Esta chave foi revogada.", label)
        }
        val exp = row.optString("expires_at")
        if (exp.isNotEmpty() && exp <= now) {
            logEvent(db, keyId, prefixOf(key), "expired", c, "Chave expirada.")
            return Result(false, "expired", "Sua chave expirou. Fale com o suporte.", label)
        }
        val maxUses = row.optLong("max_uses")
        val uses = row.optLong("uses_count")
        if (maxUses > 0 && uses >= maxUses) {
            logEvent(db, keyId, prefixOf(key), "use_limit", c, "Limite de usos atingido.")
            return Result(false, "use_limit", "Esta chave atingiu o limite de usos.", label)
        }

        // limite de aparelhos (0 = ilimitado)
        val dev = deviceId(c)
        val maxDev = row.optLong("max_devices")
        if (maxDev > 0 && dev.isNotEmpty()) {
            val known = db.one(
                "SELECT id, blocked_at FROM otm_key_devices WHERE key_id = ? AND device_id = ?",
                listOf(keyId, dev)
            )
            if (known != null && known.optString("blocked_at").isNotEmpty()) {
                logEvent(db, keyId, prefixOf(key), "blocked", c, "Aparelho bloqueado.")
                return Result(false, "blocked", "Este aparelho está bloqueado para esta chave.", label)
            }
            if (known == null) {
                val n = db.scalar(
                    "SELECT COUNT(*) FROM otm_key_devices WHERE key_id = ? AND blocked_at IS NULL",
                    listOf(keyId)
                )?.toIntOrNull() ?: 0
                if (n >= maxDev) {
                    logEvent(db, keyId, prefixOf(key), "device_limit", c, "Limite de aparelhos.")
                    return Result(false, "device_limit", "Limite de aparelhos atingido ($maxDev).", label)
                }
            }
        }

        // passou: marca uso e atualiza o aparelho
        db.run(
            "UPDATE otm_keys SET uses_count = uses_count + 1, last_used_at = ?, " +
                "activated_at = COALESCE(activated_at, ?) WHERE id = ?",
            listOf(now, now, keyId)
        )
        if (dev.isNotEmpty()) {
            db.run(
                "INSERT INTO otm_key_devices (key_id, device_id, model, android_ver, app_version, first_seen_at, last_seen_at) " +
                    "VALUES (?,?,?,?,?,?,?) ON CONFLICT(key_id, device_id) DO UPDATE SET last_seen_at = excluded.last_seen_at",
                listOf(keyId, dev, "${Build.MANUFACTURER} ${Build.MODEL}".trim(),
                    Build.VERSION.RELEASE ?: "", BuildConfig.VERSION_NAME, now, now)
            )
        }
        logEvent(db, keyId, prefixOf(key), "ok", c, "")
        saveSession(c, h, role, label, exp.ifEmpty { null }, prefixOf(key), tailOf(key))
        // A chave em claro passa por aqui uma vez: aproveita para encher o cofre
        // de quem foi criado antes dele (essas só tinham o hash).
        if (row.optString("key_sealed").isEmpty()) {
            runCatching {
                db.run("UPDATE otm_keys SET key_sealed = ? WHERE id = ? AND (key_sealed IS NULL OR key_sealed = '')",
                    listOf(seal(key), keyId))
            }
        }
        // Idem para o fim da chave: chave criada antes do rótulo "começo-····-fim"
        // só tem o prefixo guardado, e a lista precisa dos dois pedaços.
        if (row.optString("key_tail").isEmpty()) {
            runCatching {
                db.run("UPDATE otm_keys SET key_tail = ? WHERE id = ? AND (key_tail IS NULL OR key_tail = '')",
                    listOf(tailOf(key), keyId))
            }
        }
        return Result(true, "ok", "Chave válida.", label, role, exp.ifEmpty { null })
    }

    /** Sem internet: aceita a chave da última sessão enquanto o prazo valer. */
    private fun checkOffline(c: Context, h: String): Result {
        val p = prefs(c)
        val saved = p.getString(PREF_SESSION, "") ?: ""
        if (saved.isEmpty() || saved != h) {
            return Result(false, "offline_no_list",
                "Sem internet para validar a chave. Conecte-se e tente de novo.", offline = true)
        }
        val now = System.currentTimeMillis() / 1000L
        val seen = p.getLong(PREF_MAX_SEEN, 0L)
        if (seen > 0 && now < seen - CLOCK_TOLERANCE) {
            return Result(false, "clock", "A data do aparelho está errada. Ajuste o relógio.", offline = true)
        }
        val until = (p.getString(PREF_OFFLINE_UNTIL, "") ?: "").toLongOrNull() ?: 0L
        if (until in 1 until now) {
            return Result(false, "offline_expired",
                "Sua chave precisa de internet: faz mais de $OFFLINE_DAYS dias da última validação.",
                offline = true)
        }
        p.edit().putLong(PREF_MAX_SEEN, now).apply()
        val role = p.getString(PREF_ROLE, "user") ?: "user"
        val label = p.getString(PREF_LABEL, "") ?: ""
        val left = if (until > 0) ((until - now) / 86400).toInt() else 0
        return Result(true, "offline_ok",
            "Chave válida (offline por mais $left dia(s)).", label, role, offline = true)
    }

    // -------------------------------------------------------------------------
    //  auditoria
    // -------------------------------------------------------------------------

    private fun logEvent(db: TursoClient, keyId: Long?, prefix: String, result: String, c: Context, detail: String) {
        try {
            db.run(
                "INSERT INTO otm_key_events (key_id, key_prefix, result, device_id, model, app_version, detail) " +
                    "VALUES (?,?,?,?,?,?,?)",
                listOf(keyId, prefix, result, deviceId(c),
                    "${Build.MANUFACTURER} ${Build.MODEL}".trim(), BuildConfig.VERSION_NAME, detail)
            )
        } catch (_: Throwable) { /* auditoria não pode impedir o login */ }
    }

    private fun nowUtc(): String = utcNow()

    /** Agora em texto UTC, no mesmo formato que o banco usa (`datetime('now')`). */
    fun utcNow(): String {
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
        fmt.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return fmt.format(java.util.Date())
    }

    /** Daqui a N dias em texto UTC; N<=0 devolve null (vitalício). */
    fun utcPlusDays(days: Long): String? {
        if (days <= 0) return null
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
        fmt.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return fmt.format(java.util.Date(System.currentTimeMillis() + days * 86400_000L))
    }

    /** N dias atrás em texto UTC (para recortes de "última semana"). */
    fun utcDaysAgo(days: Long): String {
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
        fmt.timeZone = java.util.TimeZone.getTimeZone("UTC")
        return fmt.format(java.util.Date(System.currentTimeMillis() - days * 86400_000L))
    }

    /**
     * Daqui a N dias, contando a partir de [from] quando ele ainda não venceu
     * (renovar não pode encurtar o prazo de quem já pagou); se [from] já passou,
     * conta de hoje. Devolve null quando N<=0 e [from] vazio (vitalício).
     */
    fun utcPlusDaysFrom(days: Long, from: String?): String? {
        if (days <= 0) return from
        val fmt = java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
        fmt.timeZone = java.util.TimeZone.getTimeZone("UTC")
        val base = from?.let { try { fmt.parse(it) } catch (_: Throwable) { null } }
        val now = System.currentTimeMillis()
        val start = if (base != null && base.time > now) base.time else now
        return fmt.format(java.util.Date(start + days * 86400_000L))
    }
}
