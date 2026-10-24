<?php
// =============================================================================
//  License.php - Licença offline assinada ("lease") que o app guarda no aparelho.
//
//  Problema que isto resolve: o app precisa funcionar sem internet, mas não pode
//  virar "grátis para sempre". A lista de hashes sozinha não serve — ela diz
//  "esta chave existe", não "esta chave ainda vale". Então o painel entrega ao
//  app um bilhete assinado, com prazo, que o aparelho guarda e confere sozinho.
//
//  O bilhete é assinado com **Ed25519** (sodium). O servidor guarda a chave
//  privada (config/license.php, fora do git); o APK embarca só a pública. Assim
//  ninguém consegue forjar uma licença só lendo o APK — diferente de um HMAC,
//  cujo segredo teria que viajar junto.
//
//  Formato do bilhete (texto, fácil de guardar e logar):
//      OTM1.<payload_base64url>.<assinatura_base64url>
//
//  Payload (JSON, chaves curtas para o bilhete não crescer):
//      h   hash da chave (sha256)          d   id do aparelho
//      l   nome/rótulo                     k   id da chave no banco
//      e   validade da chave (ISO UTC)     i   emitido em (ISO UTC)
//      o   fim do uso offline (ISO UTC)    g   dias de folga offline
//      m   limite de usos (0 = sem limite) u   usos até agora
//      s   versão da licença (1)
//
//  O app NÃO confia no relógio local sozinho: ele guarda a última hora vista do
//  servidor e recusa se o relógio andar para trás. Sem isso, bastava voltar a
//  data do aparelho para esticar a licença.
// =============================================================================

declare(strict_types=1);

final class License
{
    /** Prefixo do bilhete — permite trocar o formato no futuro sem quebrar o app. */
    public const PREFIX = 'OTM1';
    public const VERSION = 1;

    /**
     * Carrega o par de chaves do servidor. Gera na primeira vez (se pedido).
     * @return array{public:string,secret:string}
     */
    public static function keys(bool $generate = false): array
    {
        $cfg = otm_config('license');
        $pub = (string)($cfg['public'] ?? otm_env('OTM_LICENSE_PUBLIC', ''));
        $sec = (string)($cfg['secret'] ?? otm_env('OTM_LICENSE_SECRET', ''));

        if (($pub === '' || $sec === '') && $generate) {
            return self::generate();
        }
        return ['public' => $pub, 'secret' => $sec];
    }

    /** Gera um par Ed25519 novo e grava em config/license.php (fora do git). */
    public static function generate(string $file = ''): array
    {
        if (!function_exists('sodium_crypto_sign_keypair')) {
            throw new RuntimeException('ext-sodium ausente: não dá para assinar a licença.');
        }
        $kp  = sodium_crypto_sign_keypair();
        $sec = sodium_crypto_sign_secretkey($kp);
        $pub = sodium_crypto_sign_publickey($kp);

        $out = ['public' => base64_encode($pub), 'secret' => base64_encode($sec)];
        $file = $file !== '' ? $file : OTM_PANEL_ROOT . '/config/license.php';

        $php = "<?php\n"
            . "// Par de chaves Ed25519 da licença offline. NÃO VAI PARA O GIT.\n"
            . "// Gere com: php panel/bin/license.php keygen\n"
            . "// A pública é embarcada no APK; a privada só existe aqui.\n"
            . "return [\n"
            . "    'public' => " . var_export($out['public'], true) . ",\n"
            . "    'secret' => " . var_export($out['secret'], true) . ",\n"
            . "];\n";
        if (@file_put_contents($file, $php) === false) {
            throw new RuntimeException("não consegui escrever $file");
        }
        @chmod($file, 0600);
        return $out;
    }

    /** Assina o payload e devolve o bilhete no formato OTM1.<payload>.<assinatura>. */
    public static function issue(array $claims): string
    {
        $keys = self::keys();
        if ($keys['secret'] === '') {
            throw new RuntimeException('sem chave privada de licença: rode "php panel/bin/license.php keygen".');
        }
        $payload = self::b64url(json_encode($claims, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE));
        $sig = sodium_crypto_sign_detached(
            self::PREFIX . '.' . $payload,
            base64_decode($keys['secret'])
        );
        return self::PREFIX . '.' . $payload . '.' . self::b64url($sig);
    }

    /**
     * Monta as claims de um bilhete a partir de uma chave já validada.
     *
     * @param array $row     linha de otm_keys (com expires_at, max_uses, uses_count…)
     * @param array $device  dados do aparelho (device_id)
     * @param int   $graceDays dias de uso offline depois da última validação online
     */
    public static function claimsFor(array $row, array $device, int $graceDays, int $now = 0): array
    {
        $now = $now > 0 ? $now : time();
        $graceDays = max(1, $graceDays);

        $expiresAt = (string)($row['expires_at'] ?? '');
        // Fim do uso offline = o que vencer primeiro: a validade da chave ou a
        // folga depois de agora. Chave vitalícia ainda assim expira offline.
        $offlineUntil = $now + $graceDays * 86400;
        if ($expiresAt !== '') {
            $ts = strtotime($expiresAt . ' UTC');
            if ($ts !== false && $ts < $offlineUntil) $offlineUntil = $ts;
        }

        return [
            's' => self::VERSION,
            'h' => (string)$row['key_hash'],
            'k' => (int)$row['id'],
            'l' => (string)($row['label'] ?? ''),
            'd' => (string)($device['device_id'] ?? ''),
            'e' => $expiresAt,
            'i' => gmdate('Y-m-d H:i:s', $now),
            'o' => gmdate('Y-m-d H:i:s', $offlineUntil),
            'g' => $graceDays,
            'm' => (int)($row['max_uses'] ?? 0),
            'u' => (int)($row['uses_count'] ?? 0),
        ];
    }

    /** Só para os testes: verifica um bilhete com a chave pública do servidor. */
    public static function verify(string $lease): bool
    {
        $parts = explode('.', $lease);
        if (count($parts) !== 3 || $parts[0] !== self::PREFIX) return false;
        $keys = self::keys();
        if ($keys['public'] === '') return false;
        $sig = self::b64urlDecode($parts[2]);
        if ($sig === null) return false;
        return sodium_crypto_sign_verify_detached(
            $sig,
            $parts[0] . '.' . $parts[1],
            base64_decode($keys['public'])
        );
    }

    private static function b64url(string $raw): string
    {
        return rtrim(strtr(base64_encode($raw), '+/', '-_'), '=');
    }

    private static function b64urlDecode(string $s): ?string
    {
        $s = strtr($s, '-_', '+/');
        $pad = strlen($s) % 4;
        if ($pad) $s .= str_repeat('=', 4 - $pad);
        $out = base64_decode($s, true);
        return $out === false ? null : $out;
    }
}
