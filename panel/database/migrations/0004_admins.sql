-- =============================================================================
--  0004_admins.sql - Quem entra no painel de administração.
--
--  Aqui SIM existe usuário e senha: o painel é ferramenta interna da equipe.
--  A senha é guardada só como hash (password_hash do PHP, bcrypt/argon2).
--  O "cliente" final continua entrando só com chave, no app.
-- =============================================================================

CREATE TABLE IF NOT EXISTS otm_admins (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    username      TEXT    NOT NULL UNIQUE,
    name          TEXT    NOT NULL DEFAULT '',
    email         TEXT    NOT NULL DEFAULT '',
    password_hash TEXT    NOT NULL,
    role          TEXT    NOT NULL DEFAULT 'admin',   -- owner|admin|viewer
    is_active     INTEGER NOT NULL DEFAULT 1,
    last_login_at TEXT,
    last_login_ip TEXT    NOT NULL DEFAULT '',
    created_at    TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at    TEXT
);

-- Sessões do painel: permite listar e derrubar acessos ativos.
CREATE TABLE IF NOT EXISTS otm_admin_sessions (
    id          TEXT    PRIMARY KEY,             -- id da sessão (opaco)
    admin_id    INTEGER NOT NULL REFERENCES otm_admins(id) ON DELETE CASCADE,
    ip          TEXT    NOT NULL DEFAULT '',
    user_agent  TEXT    NOT NULL DEFAULT '',
    created_at  TEXT    NOT NULL DEFAULT (datetime('now')),
    last_seen_at TEXT   NOT NULL DEFAULT (datetime('now')),
    expires_at  TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_otm_sessions_admin   ON otm_admin_sessions (admin_id);
CREATE INDEX IF NOT EXISTS idx_otm_sessions_expires ON otm_admin_sessions (expires_at);

-- Tentativas de login (freio contra força bruta).
CREATE TABLE IF NOT EXISTS otm_login_attempts (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    username   TEXT    NOT NULL DEFAULT '',
    ip         TEXT    NOT NULL DEFAULT '',
    ok         INTEGER NOT NULL DEFAULT 0,
    created_at TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_otm_attempts_ip  ON otm_login_attempts (ip, created_at DESC);
