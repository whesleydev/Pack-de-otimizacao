-- =============================================================================
--  0007_key_role.sql - Papel da chave (dono vs. usuário comum).
--
--  Até aqui toda chave era igual. O app agora precisa distinguir quem pode
--  abrir a categoria "Admin" (gerenciar usuários e criar chaves) de quem só usa
--  o painel. 'owner' é o dono; 'admin' pode gerenciar; 'user' é o comum.
--
--  Chave antiga (sem papel) vira 'user' — ninguém ganha admin por engano.
-- =============================================================================

ALTER TABLE otm_keys ADD COLUMN role TEXT NOT NULL DEFAULT 'user';

CREATE INDEX IF NOT EXISTS idx_otm_keys_role ON otm_keys (role);
