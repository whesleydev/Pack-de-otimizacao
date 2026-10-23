-- =============================================================================
--  0001_keys.sql - Núcleo do sistema de chaves (licenças).
--
--  Uma "key" é a licença que o app usa para entrar. O que fica guardado é só o
--  SHA-256 (key_hash) — a chave em texto nunca é gravada, então vazamento do
--  banco não entrega chave utilizável.
--
--  Vigência: expires_at NULL = nunca expira. Revogar é diferente de expirar:
--  revoked_at marca que alguém cortou o acesso; expires_at é o fim natural.
-- =============================================================================

CREATE TABLE IF NOT EXISTS otm_keys (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    key_hash        TEXT    NOT NULL UNIQUE,          -- sha256(canonical)
    key_prefix      TEXT    NOT NULL,                 -- OTM-A1B2 (para identificar sem expor)
    label           TEXT    NOT NULL DEFAULT '',      -- nome de quem recebeu
    owner_contact   TEXT    NOT NULL DEFAULT '',      -- e-mail/telefone do dono
    note            TEXT    NOT NULL DEFAULT '',      -- observação livre
    plan_id         INTEGER,                          -- preset de duração (otm_plans)
    duration_days   INTEGER,                          -- duração aplicada na criação
    max_devices     INTEGER NOT NULL DEFAULT 1,       -- aparelhos simultâneos (0 = ilimitado)
    max_uses        INTEGER NOT NULL DEFAULT 0,       -- 0 = ilimitado
    uses_count      INTEGER NOT NULL DEFAULT 0,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    activated_at    TEXT,                             -- 1º uso válido
    expires_at      TEXT,                             -- NULL = nunca expira
    last_used_at    TEXT,
    last_seen_ip    TEXT    NOT NULL DEFAULT '',
    revoked_at      TEXT,                             -- NULL = ativa
    revoked_reason  TEXT    NOT NULL DEFAULT '',
    created_by      TEXT    NOT NULL DEFAULT ''       -- admin que criou
);

-- Nome herdado do projeto (otm_*) em todas as tabelas do domínio.
CREATE INDEX IF NOT EXISTS idx_otm_keys_hash      ON otm_keys (key_hash);
CREATE INDEX IF NOT EXISTS idx_otm_keys_revoked   ON otm_keys (revoked_at);
CREATE INDEX IF NOT EXISTS idx_otm_keys_expires   ON otm_keys (expires_at);
CREATE INDEX IF NOT EXISTS idx_otm_keys_created   ON otm_keys (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_otm_keys_plan      ON otm_keys (plan_id);
