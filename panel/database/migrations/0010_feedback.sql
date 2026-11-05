-- =============================================================================
--  0010_feedback.sql - Feedback, sugestões e problemas enviados pelo app.
--
--  Qualquer pessoa com uma chave válida pode mandar um recado: elogio, sugestão,
--  problema ou dúvida. O dono lê na aba Admin e marca como lido/resolvido.
--
--  `key_id` fica solto (SET NULL) para o histórico sobreviver à exclusão da
--  chave; `key_prefix`/`key_tail` guardam o rótulo de quem escreveu, e `device_id`
--  permite juntar relatos do mesmo aparelho. `author` é o apelido local (opcional).
-- =============================================================================

CREATE TABLE IF NOT EXISTS otm_feedback (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    key_id      INTEGER REFERENCES otm_keys(id) ON DELETE SET NULL,
    key_prefix  TEXT    NOT NULL DEFAULT '',
    key_tail    TEXT    NOT NULL DEFAULT '',
    author      TEXT    NOT NULL DEFAULT '',
    kind        TEXT    NOT NULL DEFAULT 'sugestao',   -- sugestao|problema|elogio|duvida|outro
    message     TEXT    NOT NULL,
    contact     TEXT    NOT NULL DEFAULT '',
    device_id   TEXT    NOT NULL DEFAULT '',
    model       TEXT    NOT NULL DEFAULT '',
    android_ver TEXT    NOT NULL DEFAULT '',
    app_version TEXT    NOT NULL DEFAULT '',
    status      TEXT    NOT NULL DEFAULT 'novo',        -- novo|lido|resolvido|arquivado
    reply       TEXT    NOT NULL DEFAULT '',
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT,
    seen_at     TEXT
);

CREATE INDEX IF NOT EXISTS idx_otm_feedback_status  ON otm_feedback (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_otm_feedback_created ON otm_feedback (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_otm_feedback_key     ON otm_feedback (key_id);
