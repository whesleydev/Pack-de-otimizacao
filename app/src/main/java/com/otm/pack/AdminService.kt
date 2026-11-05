package com.otm.pack

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Gestão das chaves pelo próprio app (categoria "Admin", só para o dono).
 *
 * Faz o que o painel PHP fazia: listar usuários/chaves, criar, desativar
 * (revogar), reativar, excluir e ver a auditoria. Fala direto com o Turso.
 *
 * Toda operação exige sessão de dono ([KeyGate.isOwner]) — a checagem é feita
 * aqui, no nativo, e não no JavaScript, para a categoria não poder ser aberta
 * mexendo no HTML.
 */
object AdminService {

    private fun db() = TursoClient(BuildConfig.TURSO_URL, BuildConfig.TURSO_TOKEN)

    private fun deny(): JSONObject = JSONObject()
        .put("ok", false).put("error", "acesso restrito ao administrador")

    private fun requireOwner(c: Context): JSONObject? = if (KeyGate.isOwner(c)) null else deny()

    // -------------------------------------------------------------------------
    //  leitura
    // -------------------------------------------------------------------------

    /** Lista as chaves, mais recentes primeiro, com status calculado. */
    fun list(c: Context): JSONObject {
        requireOwner(c)?.let { return it }
        val rows = db().all(
            "SELECT id, key_prefix, key_tail, label, role, max_devices, max_uses, uses_count, " +
                "created_at, activated_at, expires_at, last_used_at, revoked_at, " +
                "(key_sealed IS NOT NULL AND key_sealed <> '') AS tem_chave, key_hash " +
                "FROM otm_keys ORDER BY created_at DESC LIMIT 500"
        )
        val arr = JSONArray()
        val now = KeyGate.utcNow()
        val meHash = KeyGate.sessionHash(c)
        val counts = HashMap<String, Int>()
        for (r in rows) {
            val devices = db().scalar(
                "SELECT COUNT(*) FROM otm_key_devices WHERE key_id = ?", listOf(r.optLong("id"))
            )?.toIntOrNull() ?: 0
            val status = statusOf(r, now)
            counts[status] = (counts[status] ?: 0) + 1
            arr.put(
                JSONObject()
                    .put("id", r.optLong("id"))
                    .put("prefix", r.optString("key_prefix"))
                    .put("tail", r.optString("key_tail"))
                    .put("mask", KeyGate.maskOf(r.optString("key_prefix"), r.optString("key_tail")))
                    .put("label", r.optString("label"))
                    .put("role", r.optString("role").ifBlank { "user" })
                    .put("status", status)
                    .put("devices", devices)
                    .put("maxDevices", r.optLong("max_devices"))
                    .put("uses", r.optLong("uses_count"))
                    .put("maxUses", r.optLong("max_uses"))
                    .put("createdAt", r.optString("created_at"))
                    .put("expiresAt", r.optString("expires_at"))
                    .put("lastUsedAt", r.optString("last_used_at"))
                    .put("sealed", r.optBoolean("tem_chave"))
                    .put("mine", meHash.isNotEmpty() && r.optString("key_hash") == meHash)
            )
        }
        val summary = JSONObject()
        for ((k, v) in counts) summary.put(k, v)
        return JSONObject().put("ok", true).put("keys", arr)
            .put("total", rows.size).put("summary", summary).put("db", db().isConfigured())
    }

    /** Devolve a chave em claro (do cofre cifrado) para copiar e reenviar. */
    fun reveal(c: Context, id: Long): JSONObject {
        requireOwner(c)?.let { return it }
        return revealOwn(c, id, enforceOwnership = false)
    }

    /**
     * Abre o cofre de uma chave. Quando [enforceOwnership] é true, só libera se
     * for a chave da sessão — assim um usuário comum consegue ver/copiar a
     * própria chave sem ganhar acesso à dos outros.
     */
    private fun revealOwn(c: Context, id: Long, enforceOwnership: Boolean): JSONObject {
        val row = db().one("SELECT key_hash, key_sealed FROM otm_keys WHERE id = ?", listOf(id))
            ?: return JSONObject().put("ok", false).put("error", "chave não encontrada")
        if (enforceOwnership && row.optString("key_hash") != KeyGate.sessionHash(c)) {
            return JSONObject().put("ok", false).put("error", "esta chave não é a sua")
        }
        val sealed = row.optString("key_sealed")
        if (sealed.isEmpty()) {
            return JSONObject().put("ok", false)
                .put("error", "Esta chave foi criada antes do cofre: só o prefixo ficou guardado.")
        }
        val key = KeyGate.unseal(sealed)
            ?: return JSONObject().put("ok", false).put("error", "Não consegui abrir o cofre desta chave.")
        return JSONObject().put("ok", true).put("key", key)
    }

    /** Perfil de quem está logado: usa a chave da sessão (não a lista de admin). */
    fun me(c: Context): JSONObject {
        if (!KeyGate.isLogged(c)) return JSONObject().put("ok", false).put("error", "sem sessão")
        val h = KeyGate.sessionHash(c)
        val row = if (db().isConfigured()) {
            try { db().one("SELECT * FROM otm_keys WHERE key_hash = ?", listOf(h)) } catch (_: Throwable) { null }
        } else null

        val devices = if (row != null) {
            try {
                db().scalar("SELECT COUNT(*) FROM otm_key_devices WHERE key_id = ?", listOf(row.optLong("id")))
                    ?.toIntOrNull() ?: 0
            } catch (_: Throwable) { 0 }
        } else 0

        return JSONObject()
            .put("ok", true)
            .put("role", KeyGate.sessionRole(c))
            .put("owner", KeyGate.isOwner(c))
            .put("label", KeyGate.sessionLabel(c))
            .put("prefix", KeyGate.sessionPrefix(c))
            .put("mask", KeyGate.sessionMask(c))
            .put("expiresAt", row?.optString("expires_at")?.takeIf { it.isNotEmpty() }
                ?: KeyGate.sessionExpires(c))
            .put("devices", devices)
            .put("maxDevices", row?.optLong("max_devices") ?: 0L)
            .put("uses", row?.optLong("uses_count") ?: 0L)
            .put("createdAt", row?.optString("created_at") ?: "")
            .put("id", row?.optLong("id") ?: 0L)
            .put("sealed", (row?.optString("key_sealed") ?: "").isNotEmpty())
            .put("db", db().isConfigured())
    }

    /** Só a própria chave (qualquer usuário logado). */
    fun revealMine(c: Context): JSONObject {
        if (!KeyGate.isLogged(c)) return JSONObject().put("ok", false).put("error", "sem sessão")
        val row = db().one("SELECT id FROM otm_keys WHERE key_hash = ?", listOf(KeyGate.sessionHash(c)))
            ?: return JSONObject().put("ok", false).put("error", "chave não encontrada no banco")
        return revealOwn(c, row.optLong("id"), enforceOwnership = true)
    }

    /** Detalhe de uma chave: campos + aparelhos. */
    fun detail(c: Context, id: Long): JSONObject {
        requireOwner(c)?.let { return it }
        val row = db().one("SELECT * FROM otm_keys WHERE id = ?", listOf(id))
            ?: return JSONObject().put("ok", false).put("error", "chave não encontrada")
        val k = JSONObject()
            .put("id", row.optLong("id"))
            .put("prefix", row.optString("key_prefix"))
            .put("tail", row.optString("key_tail"))
            .put("mask", KeyGate.maskOf(row.optString("key_prefix"), row.optString("key_tail")))
            .put("label", row.optString("label"))
            .put("note", row.optString("note"))
            .put("ownerContact", row.optString("owner_contact"))
            .put("role", row.optString("role").ifBlank { "user" })
            .put("maxDevices", row.optLong("max_devices"))
            .put("maxUses", row.optLong("max_uses"))
            .put("uses", row.optLong("uses_count"))
            .put("createdAt", row.optString("created_at"))
            .put("expiresAt", row.optString("expires_at"))
            .put("revokedAt", row.optString("revoked_at"))
            .put("revokedReason", row.optString("revoked_reason"))
            .put("sealed", row.optString("key_sealed").isNotEmpty())
            .put("status", statusOf(row, KeyGate.utcNow()))
            .put("mine", row.optString("key_hash") == KeyGate.sessionHash(c))

        val devs = JSONArray()
        for (d in db().all(
            "SELECT id, model, android_ver, app_version, first_seen_at, last_seen_at, blocked_at " +
                "FROM otm_key_devices WHERE key_id = ? ORDER BY last_seen_at DESC", listOf(id)
        )) {
            devs.put(JSONObject()
                .put("id", d.optLong("id"))
                .put("model", d.optString("model"))
                .put("android", d.optString("android_ver"))
                .put("app", d.optString("app_version"))
                .put("firstSeen", d.optString("first_seen_at"))
                .put("lastSeen", d.optString("last_seen_at"))
                .put("blocked", d.optString("blocked_at").isNotEmpty()))
        }
        return JSONObject().put("ok", true).put("key", k).put("devices", devs)
    }

    /** Bloqueia ou libera um aparelho específico de uma chave. */
    fun blockDevice(c: Context, deviceRowId: Long, blocked: Boolean): JSONObject {
        requireOwner(c)?.let { return it }
        db().run(
            "UPDATE otm_key_devices SET blocked_at = ? WHERE id = ?",
            listOf(if (blocked) KeyGate.utcNow() else null, deviceRowId)
        )
        return JSONObject().put("ok", true).put("blocked", blocked)
    }

    /** Remove um aparelho da lista (libera a vaga para outro). */
    fun removeDevice(c: Context, deviceRowId: Long): JSONObject {
        requireOwner(c)?.let { return it }
        db().run("DELETE FROM otm_key_devices WHERE id = ?", listOf(deviceRowId))
        return JSONObject().put("ok", true)
    }

    /** Planos cadastrados (para preencher a criação com um toque). */
    fun plans(c: Context): JSONObject {
        requireOwner(c)?.let { return it }
        val arr = JSONArray()
        for (p in db().all(
            "SELECT id, slug, name, description, duration_days, max_devices, max_uses, price_cents " +
                "FROM otm_plans WHERE COALESCE(is_active,1) = 1 ORDER BY COALESCE(sort_order,0), id"
        )) {
            arr.put(JSONObject()
                .put("id", p.optLong("id"))
                .put("slug", p.optString("slug"))
                .put("name", p.optString("name"))
                .put("description", p.optString("description"))
                .put("days", p.optLong("duration_days"))
                .put("devices", p.optLong("max_devices"))
                .put("uses", p.optLong("max_uses"))
                .put("priceCents", p.optLong("price_cents")))
        }
        return JSONObject().put("ok", true).put("plans", arr)
    }

    // -------------------------------------------------------------------------
    //  escrita
    // -------------------------------------------------------------------------

    /** Eventos recentes (auditoria). */
    fun audit(c: Context, limit: Int = 60): JSONObject {
        requireOwner(c)?.let { return it }
        val rows = db().all(
            "SELECT key_prefix, result, model, app_version, detail, created_at " +
                "FROM otm_key_events ORDER BY id DESC LIMIT ?",
            listOf(limit.coerceIn(1, 200))
        )
        val arr = JSONArray()
        for (r in rows) {
            arr.put(
                JSONObject()
                    .put("prefix", r.optString("key_prefix"))
                    .put("result", r.optString("result"))
                    .put("model", r.optString("model"))
                    .put("app", r.optString("app_version"))
                    .put("detail", r.optString("detail"))
                    .put("at", r.optString("created_at"))
            )
        }
        return JSONObject().put("ok", true).put("events", arr)
    }

    // -------------------------------------------------------------------------
    //  escrita
    // -------------------------------------------------------------------------

    /**
     * Cria uma chave nova. Devolve a chave em texto UMA vez (só o hash vai para
     * o banco). `role` pode ser "user", "admin" ou "owner": o dono precisa poder
     * gerar uma chave de dono nova para si, senão perde o acesso para sempre se
     * a única chave de dono se perder. Nunca rebaixa: um dono não vira admin.
     */
    fun create(
        c: Context,
        label: String,
        days: Long,
        maxDevices: Long,
        role: String,
        maxUses: Long = 0L,
        ownerContact: String = "",
        note: String = "",
    ): JSONObject {
        requireOwner(c)?.let { return it }
        val cleanLabel = label.trim().take(80).ifEmpty { "sem nome" }
        val cleanRole = when (role) {
            "owner" -> "owner"
            "admin" -> "admin"
            else -> "user"
        }
        val key = KeyGate.generate(cleanRole)
        val hash = KeyGate.hash(key)
        val prefix = KeyGate.prefixOf(key)
        val expires = KeyGate.utcPlusDays(days)

        val id = db().insert(
            "INSERT INTO otm_keys (key_hash, key_prefix, key_tail, label, role, max_devices, max_uses, " +
                "created_at, expires_at, created_by, key_sealed, owner_contact, note) " +
                "VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)",
            listOf(hash, prefix, KeyGate.tailOf(key), cleanLabel, cleanRole, maxDevices.coerceAtLeast(0),
                maxUses.coerceAtLeast(0), KeyGate.utcNow(), expires,
                "app:" + KeyGate.sessionLabel(c), KeyGate.seal(key),
                ownerContact.trim().take(120), note.trim().take(300))
        )
        if (id <= 0L) return JSONObject().put("ok", false).put("error", "não consegui gravar a chave")

        return JSONObject().put("ok", true).put("id", id)
            .put("key", key).put("prefix", prefix)
            .put("mask", KeyGate.maskOf(key))
            .put("label", cleanLabel).put("role", cleanRole)
            .put("expiresAt", expires ?: "")
    }

    /**
     * Edita uma chave: nome, papel, validade (em dias a partir de hoje), limite de
     * aparelhos, limite de usos, contato e observação. Campo ausente não é tocado
     * (só o que vier no `patch` muda). A chave em si (o texto) não muda — mudar o
     * texto invalidaria quem já entrou com ela.
     */
    fun update(c: Context, id: Long, patch: JSONObject): JSONObject {
        requireOwner(c)?.let { return it }
        val row = db().one("SELECT * FROM otm_keys WHERE id = ?", listOf(id))
            ?: return JSONObject().put("ok", false).put("error", "chave não encontrada")

        val sets = ArrayList<String>()
        val args = ArrayList<Any?>()

        if (patch.has("label")) {
            sets.add("label = ?"); args.add(patch.optString("label").trim().take(80).ifEmpty { "sem nome" })
        }
        if (patch.has("note")) {
            sets.add("note = ?"); args.add(patch.optString("note").trim().take(300))
        }
        if (patch.has("ownerContact")) {
            sets.add("owner_contact = ?"); args.add(patch.optString("ownerContact").trim().take(120))
        }
        if (patch.has("role")) {
            val r = patch.optString("role")
            val novo = if (r == "owner" || r == "admin") r else "user"
            // Não deixa rebaixar a própria chave: você se trancaria fora do Admin.
            if (novo != "owner" && isSelfKey(c, id)) {
                return JSONObject().put("ok", false)
                    .put("error", "você não pode rebaixar a chave com que está logado")
            }
            sets.add("role = ?"); args.add(novo)
        }
        if (patch.has("maxDevices")) {
            sets.add("max_devices = ?"); args.add(patch.optLong("maxDevices").coerceAtLeast(0))
        }
        if (patch.has("maxUses")) {
            sets.add("max_uses = ?"); args.add(patch.optLong("maxUses").coerceAtLeast(0))
        }
        if (patch.has("days")) {
            val d = patch.optLong("days", -1L)
            if (d < 0) {
                // não mexe
            } else {
                sets.add("expires_at = ?"); args.add(KeyGate.utcPlusDays(d))
            }
        }
        if (patch.has("extendDays")) {
            // empurra o vencimento a partir do que já valia (ou de hoje, se já venceu)
            val d = patch.optLong("extendDays").coerceAtLeast(0)
            if (d > 0) {
                val atual = row.optString("expires_at").ifEmpty { null }
                sets.add("expires_at = ?"); args.add(KeyGate.utcPlusDaysFrom(d, atual))
            }
        }
        if (sets.isEmpty()) return JSONObject().put("ok", false).put("error", "nada para mudar")

        args.add(id)
        val n = db().run("UPDATE otm_keys SET " + sets.joinToString(", ") + " WHERE id = ?", args)
        return JSONObject().put("ok", n >= 0).put("changed", n)
    }

    /** Revoga (desativa) ou reativa uma chave. Nunca mexe na chave da sessão. */
    fun setActive(c: Context, id: Long, active: Boolean, reason: String = ""): JSONObject {
        requireOwner(c)?.let { return it }
        if (isSelfKey(c, id)) return JSONObject().put("ok", false).put("error", "você não pode desativar a chave com que está logado")
        return if (active) {
            db().run("UPDATE otm_keys SET revoked_at = NULL, revoked_reason = '' WHERE id = ?", listOf(id))
            JSONObject().put("ok", true).put("status", "active")
        } else {
            db().run("UPDATE otm_keys SET revoked_at = ?, revoked_reason = ? WHERE id = ?",
                listOf(KeyGate.utcNow(), reason.trim().take(120), id))
            JSONObject().put("ok", true).put("status", "revoked")
        }
    }

    /** Exclui uma chave e o que pende dela. Nunca a da sessão. */
    fun delete(c: Context, id: Long): JSONObject {
        requireOwner(c)?.let { return it }
        if (isSelfKey(c, id)) return JSONObject().put("ok", false).put("error", "você não pode excluir a chave com que está logado")
        db().batch(
            listOf(
                "DELETE FROM otm_key_devices WHERE key_id = ?" to listOf(id),
                "DELETE FROM otm_keys WHERE id = ?" to listOf(id),
            )
        )
        return JSONObject().put("ok", true)
    }

    // -------------------------------------------------------------------------
    //  dashboard
    // -------------------------------------------------------------------------

    /**
     * Números do topo do painel: quantas chaves, em que estado, quantos
     * aparelhos, quantos usos, e o que andou acontecendo nos últimos 7 dias.
     *
     * Conta em SQL em vez de baixar as 500 chaves e somar no app: são poucas
     * consultas de agregação, e o painel abre na hora mesmo com a base grande.
     */
    fun dashboard(c: Context): JSONObject {
        requireOwner(c)?.let { return it }
        val db = db()
        val now = KeyGate.utcNow()
        val weekAgo = KeyGate.utcDaysAgo(7)
        val dayAgo = KeyGate.utcDaysAgo(1)

        val total = db.scalar("SELECT COUNT(*) FROM otm_keys")?.toLongOrNull() ?: 0L
        val revoked = db.scalar("SELECT COUNT(*) FROM otm_keys WHERE revoked_at IS NOT NULL")?.toLongOrNull() ?: 0L
        val expired = db.scalar(
            "SELECT COUNT(*) FROM otm_keys WHERE revoked_at IS NULL AND expires_at IS NOT NULL AND expires_at <> '' AND expires_at <= ?",
            listOf(now)
        )?.toLongOrNull() ?: 0L
        val exhausted = db.scalar(
            "SELECT COUNT(*) FROM otm_keys WHERE revoked_at IS NULL AND max_uses > 0 AND uses_count >= max_uses"
        )?.toLongOrNull() ?: 0L
        val active = db.scalar(
            "SELECT COUNT(*) FROM otm_keys WHERE revoked_at IS NULL AND activated_at IS NOT NULL " +
                "AND (expires_at IS NULL OR expires_at = '' OR expires_at > ?) AND (max_uses = 0 OR uses_count < max_uses)",
            listOf(now)
        )?.toLongOrNull() ?: 0L
        val scheduled = (total - active - expired - exhausted - revoked).coerceAtLeast(0L)
        val devices = db.scalar("SELECT COUNT(*) FROM otm_key_devices")?.toLongOrNull() ?: 0L
        val blocked = db.scalar("SELECT COUNT(*) FROM otm_key_devices WHERE blocked_at IS NOT NULL")?.toLongOrNull() ?: 0L
        val uses = db.scalar("SELECT COALESCE(SUM(uses_count), 0) FROM otm_keys")?.toLongOrNull() ?: 0L
        val owners = db.scalar("SELECT COUNT(*) FROM otm_keys WHERE role = 'owner' AND revoked_at IS NULL")?.toLongOrNull() ?: 0L
        val admins = db.scalar("SELECT COUNT(*) FROM otm_keys WHERE role = 'admin' AND revoked_at IS NULL")?.toLongOrNull() ?: 0L
        val users = db.scalar("SELECT COUNT(*) FROM otm_keys WHERE role = 'user' AND revoked_at IS NULL")?.toLongOrNull() ?: 0L

        val okWeek = db.scalar(
            "SELECT COUNT(*) FROM otm_key_events WHERE result = 'ok' AND created_at >= ?", listOf(weekAgo)
        )?.toLongOrNull() ?: 0L
        val failWeek = db.scalar(
            "SELECT COUNT(*) FROM otm_key_events WHERE result <> 'ok' AND created_at >= ?", listOf(weekAgo)
        )?.toLongOrNull() ?: 0L
        val okDay = db.scalar(
            "SELECT COUNT(*) FROM otm_key_events WHERE result = 'ok' AND created_at >= ?", listOf(dayAgo)
        )?.toLongOrNull() ?: 0L
        val newKeysWeek = db.scalar(
            "SELECT COUNT(*) FROM otm_keys WHERE created_at >= ?", listOf(weekAgo)
        )?.toLongOrNull() ?: 0L

        // Últimos 7 dias, um por linha, para o gráfico de barras do painel.
        val daily = JSONArray()
        val dia = java.text.SimpleDateFormat("yyyy-MM-dd", java.util.Locale.US).also {
            it.timeZone = java.util.TimeZone.getTimeZone("UTC")
        }
        for (i in 6 downTo 0) {
            val d = dia.format(java.util.Date(System.currentTimeMillis() - i * 86400_000L))
            val ok = db.scalar(
                "SELECT COUNT(*) FROM otm_key_events WHERE result = 'ok' AND substr(created_at, 1, 10) = ?",
                listOf(d)
            )?.toLongOrNull() ?: 0L
            daily.put(JSONObject().put("day", d).put("ok", ok))
        }

        val planos = JSONArray()
        for (p in db.all(
            "SELECT p.name, COUNT(k.id) AS n FROM otm_plans p " +
                "LEFT JOIN otm_keys k ON k.plan_id = p.id GROUP BY p.id ORDER BY n DESC LIMIT 12"
        )) {
            planos.put(JSONObject().put("name", p.optString("name")).put("count", p.optLong("n")))
        }

        val feedbackNovo = db.scalar("SELECT COUNT(*) FROM otm_feedback WHERE status = 'novo'")?.toLongOrNull() ?: 0L

        val summary = JSONObject()
            .put("active", active).put("scheduled", scheduled).put("expired", expired)
            .put("exhausted", exhausted).put("revoked", revoked)
        return JSONObject().put("ok", true)
            .put("total", total).put("devices", devices).put("blocked", blocked)
            .put("uses", uses).put("summary", summary)
            .put("roles", JSONObject().put("owner", owners).put("admin", admins).put("user", users))
            .put("okWeek", okWeek).put("failWeek", failWeek).put("okDay", okDay)
            .put("newKeysWeek", newKeysWeek).put("daily", daily).put("plans", planos)
            .put("feedbackNew", feedbackNovo)
            .put("db", db.isConfigured())
    }

    // -------------------------------------------------------------------------
    //  feedback (qualquer usuário logado pode escrever)
    // -------------------------------------------------------------------------

    private val FEEDBACK_KINDS = setOf("sugestao", "problema", "elogio", "duvida", "outro")

    /**
     * Registra um feedback/sugestão. Não exige dono: quem tem chave válida
     * pode falar. O autor é identificado pela chave da sessão (prefixo + fim),
     * sem guardar a chave em claro.
     */
    fun sendFeedback(c: Context, kind: String, message: String, contact: String): JSONObject {
        if (!KeyGate.isLogged(c)) return JSONObject().put("ok", false).put("error", "sem sessão")
        val msg = message.trim()
        if (msg.length < 3) return JSONObject().put("ok", false).put("error", "escreva um pouco mais")
        val k = FEEDBACK_KINDS.firstOrNull { it == kind.trim().lowercase() } ?: "sugestao"
        val db = db()
        if (!db.isConfigured()) return JSONObject().put("ok", false).put("error", "banco não configurado")
        val id = db.insert(
            "INSERT INTO otm_feedback (key_id, key_prefix, key_tail, author, kind, message, contact, " +
                "device_id, model, android_ver, app_version) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            listOf(
                rowIdOfSession(c), KeyGate.sessionPrefix(c), KeyGate.sessionTail(c),
                KeyGate.nick(c).ifBlank { KeyGate.sessionLabel(c) },
                k, msg.take(2000), contact.trim().take(120),
                KeyGate.deviceId(c), "${android.os.Build.MANUFACTURER} ${android.os.Build.MODEL}".trim(),
                android.os.Build.VERSION.RELEASE ?: "", BuildConfig.VERSION_NAME,
            )
        )
        if (id <= 0L) return JSONObject().put("ok", false).put("error", "não consegui enviar")
        return JSONObject().put("ok", true).put("id", id)
    }

    /** Id da chave da sessão (0 quando o banco não conhece a chave). */
    private fun rowIdOfSession(c: Context): Long =
        try { db().one("SELECT id FROM otm_keys WHERE key_hash = ?", listOf(KeyGate.sessionHash(c)))?.optLong("id") ?: 0L }
        catch (_: Throwable) { 0L }

    /** Lista os feedbacks do próprio usuário (pela chave da sessão). */
    fun feedbackMine(c: Context): JSONObject {
        if (!KeyGate.isLogged(c)) return JSONObject().put("ok", false).put("error", "sem sessão")
        val db = db()
        if (!db.isConfigured()) return JSONObject().put("ok", true).put("feedback", JSONArray())
        val rows = db.all(
            "SELECT id, kind, message, contact, status, reply, created_at FROM otm_feedback " +
                "WHERE key_id = ? ORDER BY created_at DESC LIMIT 100",
            listOf(rowIdOfSession(c))
        )
        val arr = JSONArray()
        for (r in rows) {
            arr.put(JSONObject()
                .put("id", r.optLong("id"))
                .put("kind", r.optString("kind"))
                .put("message", r.optString("message"))
                .put("contact", r.optString("contact"))
                .put("status", r.optString("status"))
                .put("reply", r.optString("reply"))
                .put("at", r.optString("created_at")))
        }
        return JSONObject().put("ok", true).put("feedback", arr)
    }

    /** Lista os feedbacks para o dono, mais recentes primeiro. */
    fun feedbackList(c: Context, status: String = ""): JSONObject {
        requireOwner(c)?.let { return it }
        val db = db()
        val f = status.trim().lowercase()
        val where = if (f.isEmpty() || f == "todos") "" else "WHERE status = ? "
        val args = if (where.isEmpty()) emptyList<Any?>() else listOf<Any?>(f)
        val rows = db.all(
            "SELECT id, key_prefix, key_tail, author, kind, message, contact, model, android_ver, " +
                "app_version, status, reply, created_at, seen_at FROM otm_feedback $where" +
                "ORDER BY created_at DESC LIMIT 300", args
        )
        val arr = JSONArray()
        for (r in rows) {
            arr.put(JSONObject()
                .put("id", r.optLong("id"))
                .put("mask", KeyGate.maskOf(r.optString("key_prefix"), r.optString("key_tail")))
                .put("author", r.optString("author"))
                .put("kind", r.optString("kind"))
                .put("message", r.optString("message"))
                .put("contact", r.optString("contact"))
                .put("model", r.optString("model"))
                .put("android", r.optString("android_ver"))
                .put("app", r.optString("app_version"))
                .put("status", r.optString("status"))
                .put("reply", r.optString("reply"))
                .put("at", r.optString("created_at")))
        }
        val novo = db.scalar("SELECT COUNT(*) FROM otm_feedback WHERE status = 'novo'")?.toLongOrNull() ?: 0L
        return JSONObject().put("ok", true).put("feedback", arr).put("novo", novo)
    }

    /** Marca um feedback como lido/resolvido/arquivado e guarda uma resposta. */
    fun feedbackUpdate(c: Context, id: Long, status: String, reply: String = ""): JSONObject {
        requireOwner(c)?.let { return it }
        if (id <= 0L) return JSONObject().put("ok", false).put("error", "id inválido")
        val s = when (status.trim().lowercase()) {
            "lido" -> "lido"
            "resolvido" -> "resolvido"
            "arquivado" -> "arquivado"
            "novo" -> "novo"
            else -> return JSONObject().put("ok", false).put("error", "estado desconhecido")
        }
        val sets = arrayListOf("status = ?", "updated_at = ?")
        val args = arrayListOf<Any?>(s, KeyGate.utcNow())
        if (reply.isNotEmpty()) { sets.add("reply = ?"); args.add(reply.trim().take(1000)) }
        if (s != "novo") { sets.add("seen_at = COALESCE(seen_at, ?)"); args.add(KeyGate.utcNow()) }
        args.add(id)
        val n = db().run("UPDATE otm_feedback SET " + sets.joinToString(", ") + " WHERE id = ?", args)
        return JSONObject().put("ok", n >= 0).put("status", s)
    }

    /** Exclui um feedback. */
    fun feedbackDelete(c: Context, id: Long): JSONObject {
        requireOwner(c)?.let { return it }
        if (id <= 0L) return JSONObject().put("ok", false).put("error", "id inválido")
        db().run("DELETE FROM otm_feedback WHERE id = ?", listOf(id))
        return JSONObject().put("ok", true)
    }

    // -------------------------------------------------------------------------

    private fun isOwnerKey(id: Long): Boolean =
        (db().scalar("SELECT role FROM otm_keys WHERE id = ?", listOf(id)) ?: "") == KeyGate.ROLE_OWNER

    /** A chave com que este aparelho está logado agora. */
    private fun isSelfKey(c: Context, id: Long): Boolean {
        val h = KeyGate.sessionHash(c)
        if (h.isEmpty()) return false
        return (db().scalar("SELECT key_hash FROM otm_keys WHERE id = ?", listOf(id)) ?: "") == h
    }

    private fun statusOf(r: JSONObject, now: String): String {
        if (r.optString("revoked_at").isNotEmpty()) return "revoked"
        val exp = r.optString("expires_at")
        if (exp.isNotEmpty() && exp <= now) return "expired"
        val maxUses = r.optLong("max_uses")
        if (maxUses > 0 && r.optLong("uses_count") >= maxUses) return "exhausted"
        if (r.optString("activated_at").isEmpty()) return "scheduled"
        return "active"
    }
}
