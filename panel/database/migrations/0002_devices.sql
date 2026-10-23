-- =============================================================================
--  0002_devices.sql - Aparelhos que usaram cada chave.
--
--  Serve para dois fins: (1) limitar quantos aparelhos a chave libera
--  (otm_keys.max_devices) e (2) dar suporte — saber em que celular a chave
--  está rodando quando o cliente reclama.
--
--  device_id é um identificador estável enviado pelo app (Android ID + modelo).
-- =============================================================================

CREATE TABLE IF NOT EXISTS otm_key_devices (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    key_id       INTEGER NOT NULL REFERENCES otm_keys(id) ON DELETE CASCADE,
    device_id    TEXT    NOT NULL,               -- identificador estável do aparelho
    model        TEXT    NOT NULL DEFAULT '',
    android_ver  TEXT    NOT NULL DEFAULT '',
    app_version  TEXT    NOT NULL DEFAULT '',
    first_seen_at TEXT   NOT NULL DEFAULT (datetime('now')),
    last_seen_at  TEXT   NOT NULL DEFAULT (datetime('now')),
    last_ip       TEXT    NOT NULL DEFAULT '',
    blocked_at    TEXT,                          -- NULL = permitido
    UNIQUE (key_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_otm_devices_key    ON otm_key_devices (key_id);
CREATE INDEX IF NOT EXISTS idx_otm_devices_device ON otm_key_devices (device_id);
