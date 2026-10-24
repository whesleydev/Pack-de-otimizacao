<?php
// =============================================================================
//  validate.php - Endpoint que o APP chama para validar a chave no banco.
//
//  É a única porta pela qual o app fala com o banco. O token do Turso fica
//  aqui no servidor; o APK nunca vê esse token.
//
//  POST /api/validate.php
//      { "key": "00-XXXX-XXXX-XXXX",
//        "device_id": "abc123", "model": "Pixel 7", "android": "14", "app": "2.27.0" }
//
//  Resposta (sempre 200, com ok true/false):
//      { "ok": true,  "result": "ok", "label": "...", "expires_at": "...", "days_left": 30 }
//      { "ok": false, "result": "expired|revoked|device_limit|use_limit|blocked|unknown",
//        "message": "..." }
//
//  Códigos HTTP: 200 resposta normal · 400 corpo inválido · 429 excesso de
//  tentativas · 503 banco fora do ar. O app trata "sem rede" com o cache local.
// =============================================================================

declare(strict_types=1);

require_once __DIR__ . '/../../src/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');

// Só POST: a chave não deve aparecer em log de servidor/URL.
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    otm_json(['ok' => false, 'result' => 'error', 'message' => 'use POST'], 405);
}

$raw = file_get_contents('php://input') ?: '';
$in  = json_decode($raw, true);
if (!is_array($in)) {
    // aceita também formulário (curl -d key=...)
    $in = $_POST;
}
if (!is_array($in)) {
    otm_json(['ok' => false, 'result' => 'error', 'message' => 'corpo inválido'], 400);
}

$key = trim((string)($in['key'] ?? ''));
if ($key === '') {
    otm_json(['ok' => false, 'result' => 'error', 'message' => 'informe a chave'], 400);
}

$ip = otm_client_ip();

try {
    $db   = otm_db();
    $keys = new KeyService($db);

    // Freio simples: um mesmo IP não pode martelar o endpoint.
    if (!otm_rate_ok($db, 'validate', $ip, 120, 60)) {
        otm_json(['ok' => false, 'result' => 'rate_limit',
                  'message' => 'Muitas tentativas. Aguarde um instante.'], 429);
    }

    $res = $keys->validate($key, [
        'device_id'   => (string)($in['device_id'] ?? ''),
        'model'       => (string)($in['model'] ?? ''),
        'android_ver' => (string)($in['android'] ?? $in['android_ver'] ?? ''),
        'app_version' => (string)($in['app'] ?? $in['app_version'] ?? ''),
    ], $ip);

    $out = [
        'ok'         => $res['ok'],
        'result'     => $res['result'],
        'message'    => $res['message'],
        'label'      => $res['label'],
        'expires_at' => $res['expires_at'],
        'days_left'  => $res['days_left'],
        'server_time' => otm_now(),
    ];

    // Licença offline assinada: o app guarda e confere sozinho quando estiver
    // sem internet. Só sai quando a chave passou; se a licença não estiver
    // configurada, o app segue com o modo offline antigo (lista de hashes).
    if ($res['ok']) {
        try {
            $cfg   = [];
            foreach ($db->all('SELECT key, value FROM otm_settings') as $r) $cfg[(string)$r['key']] = (string)$r['value'];
            $grace = max(1, (int)($cfg['offline_days'] ?? 7));
            $row   = $db->one('SELECT * FROM otm_keys WHERE id = ?', [(int)$res['key_id']]);
            if ($row) {
                $out['lease'] = License::issue(License::claimsFor($row, [
                    'device_id' => (string)($in['device_id'] ?? ''),
                ], $grace));
                $out['offline_days'] = $grace;
            }
        } catch (Throwable $e) {
            error_log('[otm lease] ' . $e->getMessage()); // sem licença: o app usa o offline antigo
        }
    }

    otm_json($out);
} catch (Throwable $e) {
    error_log('[otm validate] ' . $e->getMessage());
    otm_json(['ok' => false, 'result' => 'server_error',
              'message' => 'Não consegui falar com o banco agora.'], 503);
}

/** Limite de N chamadas por janela de segundos, por IP. */
function otm_rate_ok(OtmDb $db, string $scope, string $ip, int $max, int $seconds): bool
{
    if ($ip === '') return true;
    try {
        $db->run("CREATE TABLE IF NOT EXISTS otm_rate (
                    k TEXT NOT NULL, win TEXT NOT NULL, n INTEGER NOT NULL DEFAULT 0,
                    PRIMARY KEY (k, win))");
        $win = gmdate('Y-m-d H:i:s', (int)(time() / $seconds) * $seconds);
        $db->run('INSERT INTO otm_rate (k, win, n) VALUES (?,?,1)
                  ON CONFLICT(k, win) DO UPDATE SET n = n + 1', [$scope . ':' . $ip, $win]);
        $n = (int)$db->scalar('SELECT n FROM otm_rate WHERE k = ? AND win = ?', [$scope . ':' . $ip, $win]);
        return $n <= $max;
    } catch (Throwable) {
        return true; // se a tabela de freio falhar, não bloqueia o cliente
    }
}
