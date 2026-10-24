<?php
// =============================================================================
//  KeyVault.php - Guarda a chave em texto, cifrada, para poder mostrá-la depois.
//
//  O banco continua guardando só o hash (é ele que valida). Este cofre é um
//  extra: permite ao painel reexibir e copiar a chave quando o cliente pede,
//  em vez de obrigar a gerar outra.
//
//  O texto NUNCA é gravado em claro: vai cifrado com XChaCha20-Poly1305
//  (sodium secretbox), usando uma chave que fica em config/vault.php — fora do
//  git. Sem esse arquivo o cofre não abre: um vazamento do banco sozinho não
//  expõe nenhuma chave.
// =============================================================================

declare(strict_types=1);

final class KeyVault
{
    private const PREFIX = 'v1:';
    private const NONCE_LEN = SODIUM_CRYPTO_SECRETBOX_NONCEBYTES;

    /**
     * Chave simétrica (base64). Vazia = cofre desligado.
     * A variável de ambiente tem prioridade sobre o arquivo — mesmo critério do
     * Turso —, o que também deixa os testes apontarem para uma chave própria.
     */
    public static function key(): string
    {
        $env = otm_env('OTM_VAULT_KEY', '');
        if ($env !== '') return $env;
        $cfg = otm_config('vault');
        return trim((string)($cfg['key'] ?? ''));
    }

    public static function isConfigured(): bool
    {
        return self::key() !== '';
    }

    /** Cifra a chave em texto. Devolve '' se o cofre não estiver configurado. */
    public static function seal(string $plain): string
    {
        $key = self::key();
        if ($key === '' || $plain === '') return '';

        $raw = base64_decode($key, true);
        if ($raw === false || strlen($raw) !== SODIUM_CRYPTO_SECRETBOX_KEYBYTES) return '';

        $nonce = random_bytes(self::NONCE_LEN);
        $box   = sodium_crypto_secretbox($plain, $nonce, $raw);
        return self::PREFIX . base64_encode($nonce . $box);
    }

    /** Abre o que `seal` guardou. Devolve '' se não der (sem chave, adulterado). */
    public static function open(?string $sealed): string
    {
        $sealed = (string)$sealed;
        if ($sealed === '' || !str_starts_with($sealed, self::PREFIX)) return '';

        $key = self::key();
        if ($key === '') return '';

        $raw = base64_decode($key, true);
        if ($raw === false || strlen($raw) !== SODIUM_CRYPTO_SECRETBOX_KEYBYTES) return '';

        $blob = base64_decode(substr($sealed, strlen(self::PREFIX)), true);
        if ($blob === false || strlen($blob) <= self::NONCE_LEN) return '';

        $nonce = substr($blob, 0, self::NONCE_LEN);
        $box   = substr($blob, self::NONCE_LEN);
        $out   = sodium_crypto_secretbox_open($box, $nonce, $raw);
        return $out === false ? '' : $out;
    }

    /** Gera uma chave nova para o config (uso: php panel/bin/vault.php keygen). */
    public static function generate(): string
    {
        return base64_encode(random_bytes(SODIUM_CRYPTO_SECRETBOX_KEYBYTES));
    }
}
