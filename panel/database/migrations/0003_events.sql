-- =============================================================================
--  0003_events.sql - Histórico de cada tentativa de validação da chave.
--
--  O app chama o endpoint de validação a cada abertura. Guardamos o resultado
--  (ok / expirada / revogada / aparelho a mais / limite de uso) para o painel
--  responder "por que essa chave não entrou no aparelho do cliente".
-- =============================================================================

CREATE TABLE IF NOT EXISTS otm_key_events (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    key_id      INTEGER REFERENCES otm_keys(id) ON DELETE SET NULL,
    key_prefix  TEXT    NOT NULL DEFAULT '',   -- mesmo se a chave não existir
    result      TEXT    NOT NULL,              -- ok|expired|revoked|device_limit|use_limit|unknown|blocked
    device_id   TEXT    NOT NULL DEFAULT '',
    model       TEXT    NOT NULL DEFAULT '',
    app_version TEXT    NOT NULL DEFAULT '',
    ip          TEXT    NOT NULL DEFAULT '',
    detail      TEXT    NOT NULL DEFAULT '',
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_otm_events_key     ON otm_key_events (key_id);
CREATE INDEX IF NOT EXISTS idx_otm_events_created ON otm_key_events (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_otm_events_result  ON otm_key_events (result);
