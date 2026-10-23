-- =============================================================================
--  0005_plans.sql - Presets de duração/limites para criar chaves rápido.
--
--  Em vez de digitar "30 dias, 1 aparelho" toda vez, o painel oferece planos
--  (Teste 7 dias, Mensal, Vitalício…). Criar uma chave a partir de um plano só
--  copia os valores para a chave — mudar o plano depois não altera chaves já
--  criadas (histórico fica fiel ao que foi vendido).
-- =============================================================================

CREATE TABLE IF NOT EXISTS otm_plans (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    slug          TEXT    NOT NULL UNIQUE,
    name          TEXT    NOT NULL,
    description   TEXT    NOT NULL DEFAULT '',
    duration_days INTEGER,                    -- NULL = vitalício
    max_devices   INTEGER NOT NULL DEFAULT 1,
    max_uses      INTEGER NOT NULL DEFAULT 0,
    price_cents   INTEGER NOT NULL DEFAULT 0,
    is_active     INTEGER NOT NULL DEFAULT 1,
    sort_order    INTEGER NOT NULL DEFAULT 0,
    created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT
);

-- Ajustes chave/valor do painel (nome da marca, prazos padrão, etc.).
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
    action     TEXT    NOT NULL,              -- key.create|key.revoke|key.update|…
    entity     TEXT    NOT NULL DEFAULT '',   -- key|plan|admin|setting
    entity_id  TEXT    NOT NULL DEFAULT '',
    details    TEXT    NOT NULL DEFAULT '',
    ip         TEXT    NOT NULL DEFAULT '',
    created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_otm_audit_created ON otm_audit (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_otm_audit_entity  ON otm_audit (entity, entity_id);

-- -----------------------------------------------------------------------------
--  Ajustes iniciais do painel.
--
--  Não há planos pré-cadastrados: os planos são seus, então você cria os que
--  fizer sentido em "Planos" (ou cria chaves sem plano). Assim o painel começa
--  limpo, sem nenhum dado de exemplo.
-- -----------------------------------------------------------------------------
INSERT OR IGNORE INTO otm_settings (key, value) VALUES
    ('brand_name',     '00deUdia Otimizações'),
    ('default_days',   '30'),
    ('default_devices','1'),
    ('require_device', '1');
