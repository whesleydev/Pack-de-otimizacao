<?php
// =============================================================================
//  buildprops.php - Escreve os segredos de build do app em local.properties.
//
//  O APK precisa saber (a) onde está o painel que valida a chave e (b) a chave
//  PÚBLICA Ed25519 da licença offline. Isso vai para local.properties (fora do
//  git) e o build lê de lá — sem precisar passar flag nenhuma.
//
//  Uso:
//      php panel/bin/buildprops.php --url http://192.168.0.10:8099
//      php panel/bin/buildprops.php --url https://painel.exemplo --token SEGREDO
//      php panel/bin/buildprops.php            # só preenche a chave da licença
//      php panel/bin/buildprops.php --show     # mostra o que está definido
//
//  A URL não leva /index.php nem /api: o app completa com /api/validate.php.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$file = dirname(OTM_PANEL_ROOT) . '/local.properties';

$opts = [];
for ($i = 1; $i < $argc; $i++) {
    $a = (string)$argv[$i];
    if (str_starts_with($a, '--')) {
        $k = substr($a, 2);
        $v = (str_contains($k, '=')) ? substr($k, strpos($k, '=') + 1) : '';
        $k = strstr($k, '=', true) ?: $k;
        if ($v === '' && isset($argv[$i + 1]) && !str_starts_with((string)$argv[$i + 1], '--')) {
            $v = (string)$argv[++$i];
        }
        $opts[$k] = $v;
    }
}

/** Lê as chaves que já existem no arquivo (para não perder o sdk.dir). */
$cur = [];
if (is_file($file)) {
    foreach (file($file, FILE_IGNORE_NEW_LINES) ?: [] as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || !str_contains($line, '=')) continue;
        [$k, $v] = explode('=', $line, 2);
        $cur[trim($k)] = trim($v);
    }
}

if (isset($opts['show'])) {
    foreach (['otmPanelUrl', 'otmSyncToken', 'otmLicensePub'] as $k) {
        $v = $cur[$k] ?? '';
        if ($k === 'otmSyncToken' && $v !== '') $v = substr($v, 0, 6) . '…';
        printf("%-14s %s\n", $k, $v !== '' ? $v : '(vazio)');
    }
    exit(0);
}

if (isset($opts['url'])) {
    $url = rtrim(trim((string)$opts['url']), '/');
    // aceita a URL do main.sh (com /index.php) e normaliza para a raiz.
    $url = preg_replace('~/index\.php$~', '', $url) ?? $url;
    if ($url !== '' && !preg_match('~^https?://~i', $url)) {
        fwrite(STDERR, "a URL precisa começar com http:// ou https://\n");
        exit(1);
    }
    $cur['otmPanelUrl'] = $url;
}

if (isset($opts['token'])) {
    $cur['otmSyncToken'] = trim((string)$opts['token']);
} elseif (!isset($opts['no-token'])) {
    // Sem --token, pega o segredo que o próprio painel usa (otm_settings).
    try {
        $tok = (string)(otm_db()->scalar("SELECT value FROM otm_settings WHERE key = 'sync_token'") ?? '');
        if ($tok !== '') $cur['otmSyncToken'] = $tok;
    } catch (Throwable) {
        // sem banco agora: mantém o que já estava no arquivo
    }
}

// A chave pública da licença vem do painel (config/license.php), se existir.
if (isset($opts['no-license'])) {
    unset($cur['otmLicensePub']);
} else {
    $pub = License::keys()['public'];
    if ($pub !== '') $cur['otmLicensePub'] = $pub;
}

// Grava preservando as demais linhas (sdk.dir etc.).
$lines = [];
$seen  = [];
foreach ($cur as $k => $v) {
    $lines[] = "$k=$v";
    $seen[$k] = true;
}
$out = "# Gerado/atualizado por panel/bin/buildprops.php — NÃO versionar.\n"
     . implode("\n", $lines) . "\n";

if (@file_put_contents($file, $out, LOCK_EX) === false) {
    fwrite(STDERR, "não consegui escrever $file\n");
    exit(1);
}
echo "✔ local.properties atualizado\n";
printf("  otmPanelUrl   : %s\n", $cur['otmPanelUrl'] ?? '(vazio — o app só valida offline)');
printf("  otmSyncToken  : %s\n", ($cur['otmSyncToken'] ?? '') !== '' ? '(definido)' : '(vazio)');
printf("  otmLicensePub : %s\n", ($cur['otmLicensePub'] ?? '') !== '' ? '(definido)' : '(vazio)');
echo "\nAgora rebuilde: cd app && ./gradlew :app:assembleRelease\n";
