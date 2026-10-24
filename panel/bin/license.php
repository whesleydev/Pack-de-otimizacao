<?php
// =============================================================================
//  license.php - CLI da licença offline (chaves e conferência).
//
//  Uso:
//      php panel/bin/license.php keygen [--force]   # cria o par Ed25519
//      php panel/bin/license.php show               # mostra a chave pública (p/ o APK)
//      php panel/bin/license.php verify <bilhete>   # confere um bilhete
//      php panel/bin/license.php decode <bilhete>   # mostra o conteúdo (sem confiar)
//
//  O bilhete é o texto "OTM1....." que o app guarda no aparelho. Ele carrega a
//  validade e o prazo de uso offline — tudo assinado, então o app confere sem
//  precisar de internet.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$cmd = $argv[1] ?? 'help';
$arg = (string)($argv[2] ?? '');

switch ($cmd) {
    case 'keygen':
        // OTM_LICENSE_FILE permite gerar fora do config/ (útil em teste, para
        // não mexer no par de chaves de verdade do servidor).
        $file = otm_env('OTM_LICENSE_FILE', OTM_PANEL_ROOT . '/config/license.php');
        $force = in_array('--force', $argv, true);
        if (is_file($file) && !$force) {
            fwrite(STDERR, "já existe $file (use --force para trocar; isso invalida as licenças já emitidas)\n");
            exit(1);
        }
        try {
            $keys = License::generate($file);
        } catch (Throwable $e) {
            fwrite(STDERR, "erro: " . $e->getMessage() . "\n");
            exit(1);
        }
        printf("✔ par Ed25519 criado em %s\n", $file);
        printf("  chave privada: guardada só aqui (fora do git)\n");
        printf("  chave pública: %s\n", $keys['public']);
        printf("\nEmbargue a pública no build do APK:\n");
        printf("  ./gradlew :app:assembleRelease -PotmLicensePub=%s\n", $keys['public']);
        break;

    case 'show':
        $keys = License::keys();
        if ($keys['public'] === '') { fwrite(STDERR, "sem chave: rode 'php panel/bin/license.php keygen'\n"); exit(1); }
        echo $keys['public'], "\n";
        break;

    case 'verify':
        if ($arg === '') { fwrite(STDERR, "informe o bilhete\n"); exit(1); }
        echo License::verify($arg) ? "VÁLIDO (assinatura confere)\n" : "INVÁLIDO (assinatura não confere)\n";
        break;

    case 'decode':
        if ($arg === '') { fwrite(STDERR, "informe o bilhete\n"); exit(1); }
        $parts = explode('.', $arg);
        if (count($parts) !== 3 || $parts[0] !== License::PREFIX) { fwrite(STDERR, "formato inesperado\n"); exit(1); }
        $raw = strtr($parts[1], '-_', '+/');
        $raw .= str_repeat('=', (4 - strlen($raw) % 4) % 4);
        $j = json_decode((string)base64_decode($raw, true), true);
        if (!is_array($j)) { fwrite(STDERR, "payload ilegível\n"); exit(1); }
        printf("chave (hash) : %s\n", $j['h'] ?? '');
        printf("nome         : %s\n", $j['l'] ?? '');
        printf("aparelho     : %s\n", $j['d'] ?? '');
        printf("validade     : %s\n", ($j['e'] ?? '') !== '' ? $j['e'] : '(vitalícia)');
        printf("emitido em   : %s\n", $j['i'] ?? '');
        printf("offline até  : %s\n", $j['o'] ?? '');
        printf("folga offline: %s dia(s)\n", $j['g'] ?? '');
        printf("assinatura   : %s\n", License::verify($arg) ? 'confere' : 'NÃO confere');
        break;

    default:
        echo <<<TXT
        Painel 00deUdia — licença offline

          php panel/bin/license.php keygen [--force]   # cria o par Ed25519
          php panel/bin/license.php show               # mostra a chave pública
          php panel/bin/license.php verify <bilhete>   # confere a assinatura
          php panel/bin/license.php decode <bilhete>   # mostra o conteúdo

        TXT;
}
