-- =============================================================================
--  0008_key_prefix_trix.sql - Prefixo da chave separa dono de usuário.
--
--  Regra nova: a chave do dono/admin começa com "00" (00-XXXX-XXXX-XXXX) e a do
--  usuário comum começa com "TRIX" (TRIX-XXXX-XXXX-XXXX). Assim dá para saber o
--  papel só de olhar a chave.
--
--  O prefixo é só rótulo: quem manda é a coluna `role`. Esta migração só acerta
--  o texto de `key_prefix` das chaves que já existiam (role <> 'owner'), que
--  ficaram com "00-" quando o formato era único. O hash não muda — a chave que o
--  usuário já tem continua valendo, digitada com TRIX na frente.
-- =============================================================================

UPDATE otm_keys
   SET key_prefix = 'TRIX-' || substr(key_prefix, 4)
 WHERE role <> 'owner'
   AND key_prefix LIKE '00-%';
