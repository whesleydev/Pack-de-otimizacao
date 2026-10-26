-- =============================================================================
--  0002_panel.sql - Ajustes e auditoria do painel.
-- =============================================================================

-- Ajustes chave/valor do painel (nome da marca, etc.).
CREATE TABLE IF NOT EXISTS otm_settings (
    key        TEXT PRIMARY KEY,
    value      TEXT,
    updated_at TEXT
);

-- Auditoria das ações do painel: quem fez o quê, quando.
CREATE TABLE IF NOT EXISTS otm_audit (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    admin_id   INTEGER,
    actor      TEXT    NOT NULL DEFAULT '',
    action     TEXT    NOT NULL,              -- admin.create|admin.update|setting.update|…
    entity     TEXT    NOT NULL DEFAULT '',   -- admin|setting
    entity_id  TEXT    NOT NULL DEFAULT '',
    details    TEXT    NOT NULL DEFAULT '',
    ip         TEXT    NOT NULL DEFAULT '',
    created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_otm_audit_created ON otm_audit (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_otm_audit_entity  ON otm_audit (entity, entity_id);

-- -----------------------------------------------------------------------------
--  Ajustes iniciais do painel.
-- -----------------------------------------------------------------------------
INSERT OR IGNORE INTO otm_settings (key, value) VALUES
    ('brand_name', '00deUdia Otimizações');
