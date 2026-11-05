-- =============================================================================
--  0009_key_tail.sql - Fim da chave, para o rótulo "começo-····-fim".
--
--  A lista de chaves mostrava só o começo (`00-FWYE-····-····`), o que não
--  bastava para reconhecer a chave: duas chaves do mesmo dono ficavam idênticas
--  na tela. Agora guardamos também os 4 últimos caracteres e mostramos
--  `00-FWYE-····-99WV`.
--
--  Isto NÃO é a chave: são 4 caracteres do fim. O miolo (que é o que interessa
--  a quem rouba) continua escondido, e o valor completo segue só no cofre
--  (`key_sealed`) e no hash (`key_hash`). Não é possível reconstruir a chave a
--  partir do prefixo + fim.
-- =============================================================================

ALTER TABLE otm_keys ADD COLUMN key_tail TEXT NOT NULL DEFAULT '';

CREATE INDEX IF NOT EXISTS idx_otm_keys_tail ON otm_keys (key_tail);
