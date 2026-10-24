-- =============================================================================
--  0006_key_vault.sql - Guarda a chave cifrada, para poder reexibi-la no painel.
--
--  Antes só existia o hash: se o cliente perdesse a chave, não havia como
--  mostrá-la de novo. Agora o texto vai cifrado em key_sealed (ver KeyVault).
--  Chaves criadas antes desta migração ficam com key_sealed vazio: o texto
--  delas se perdeu, não há como recuperar.
-- =============================================================================

ALTER TABLE otm_keys ADD COLUMN key_sealed TEXT NOT NULL DEFAULT '';
