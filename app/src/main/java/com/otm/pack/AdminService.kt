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
            "SELECT id, key_prefix, label, role, max_devices, max_uses, uses_count, " +
                "created_at, activated_at, expires_at, last_used_at, revoked_at " +
                "FROM otm_keys ORDER BY created_at DESC LIMIT 200"
        )
        val arr = JSONArray()
        val now = KeyGate.utcNow()
        for (r in rows) {
            val devices = db().scalar(
                "SELECT COUNT(*) FROM otm_key_devices WHERE key_id = ?", listOf(r.optLong("id"))
            )?.toIntOrNull() ?: 0
            arr.put(
                JSONObject()
                    .put("id", r.optLong("id"))
                    .put("prefix", r.optString("key_prefix"))
                    .put("label", r.optString("label"))
                    .put("role", r.optString("role").ifBlank { "user" })
                    .put("status", statusOf(r, now))
                    .put("devices", devices)
                    .put("maxDevices", r.optLong("max_devices"))
                    .put("uses", r.optLong("uses_count"))
                    .put("maxUses", r.optLong("max_uses"))
                    .put("createdAt", r.optString("created_at"))
                    .put("expiresAt", r.optString("expires_at"))
                    .put("lastUsedAt", r.optString("last_used_at"))
            )
        }
        return JSONObject().put("ok", true).put("keys", arr)
            .put("total", rows.size).put("db", db().isConfigured())
    }

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
     * o banco). `role` deve ser "user" ou "admin" (nunca "owner" por aqui).
     */
    fun create(c: Context, label: String, days: Long, maxDevices: Long, role: String): JSONObject {
        requireOwner(c)?.let { return it }
        val cleanLabel = label.trim().take(80).ifEmpty { "sem nome" }
        val cleanRole = if (role == "admin") "admin" else "user"
        val key = KeyGate.generate(cleanRole)
        val hash = KeyGate.hash(key)
        val prefix = KeyGate.prefixOf(key)
        val expires = KeyGate.utcPlusDays(days)

        val id = db().insert(
            "INSERT INTO otm_keys (key_hash, key_prefix, label, role, max_devices, max_uses, " +
                "created_at, expires_at, created_by) VALUES (?,?,?,?,?,?,?,?,?)",
            listOf(hash, prefix, cleanLabel, cleanRole, maxDevices.coerceAtLeast(0), 0L,
                KeyGate.utcNow(), expires, "app:" + KeyGate.sessionLabel(c))
        )
        if (id <= 0L) return JSONObject().put("ok", false).put("error", "não consegui gravar a chave")

        return JSONObject().put("ok", true).put("id", id)
            .put("key", key).put("prefix", prefix)
            .put("label", cleanLabel).put("role", cleanRole)
            .put("expiresAt", expires ?: "")
    }

    /** Revoga (desativa) ou reativa uma chave. Nunca mexe na chave do dono. */
    fun setActive(c: Context, id: Long, active: Boolean, reason: String = ""): JSONObject {
        requireOwner(c)?.let { return it }
        if (isOwnerKey(id)) return JSONObject().put("ok", false).put("error", "a chave do dono não pode ser desativada")
        return if (active) {
            db().run("UPDATE otm_keys SET revoked_at = NULL, revoked_reason = '' WHERE id = ?", listOf(id))
            JSONObject().put("ok", true).put("status", "active")
        } else {
            db().run("UPDATE otm_keys SET revoked_at = ?, revoked_reason = ? WHERE id = ?",
                listOf(KeyGate.utcNow(), reason.trim().take(120), id))
            JSONObject().put("ok", true).put("status", "revoked")
        }
    }

    /** Exclui uma chave e o que pende dela. Nunca a do dono. */
    fun delete(c: Context, id: Long): JSONObject {
        requireOwner(c)?.let { return it }
        if (isOwnerKey(id)) return JSONObject().put("ok", false).put("error", "a chave do dono não pode ser excluída")
        db().batch(
            listOf(
                "DELETE FROM otm_key_devices WHERE key_id = ?" to listOf(id),
                "DELETE FROM otm_keys WHERE id = ?" to listOf(id),
            )
        )
        return JSONObject().put("ok", true)
    }

    // -------------------------------------------------------------------------

    private fun isOwnerKey(id: Long): Boolean =
        (db().scalar("SELECT role FROM otm_keys WHERE id = ?", listOf(id)) ?: "") == KeyGate.ROLE_OWNER

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
