<?php
// =============================================================================
//  hashes.php - Lista de hashes das chaves ativas (validação offline do app).
//
//  O app guarda essa lista e, quando está sem internet, aceita uma chave que
//  esteja nela. O endpoint de validação (validate.php) continua sendo a fonte
//  da verdade quando há rede.
//
//  Isso NÃO expõe chave nenhuma: só o SHA-256, que não permite reconstruir a
//  chave. Serve apenas para o app dizer "sim/não" localmente.
//
//  Protegido por um segredo compartilhado (otm_settings: sync_token) para não
//  entregar o catálogo de hashes a qualquer um. Sem segredo configurado, nega.
//
//  GET /api/hashes.php?token=SEGREDO
//      { "updated": 1792776687, "count": 3, "hashes": ["...","..."] }
// =============================================================================

declare(strict_types=1);

require_once __DIR__ . '/../../src/bootstrap.php';

header('Content-Type: application/json; charset=utf-8');
header('X-Content-Type-Options: nosniff');
header('Cache-Control: no-store');

try {
    $db = otm_db();
} catch (Throwable $e) {
    otm_json(['ok' => false, 'error' => 'banco indisponível'], 503);
}

$expected = (string)($db->scalar("SELECT value FROM otm_settings WHERE key = 'sync_token'") ?? '');
$given    = (string)($_GET['token'] ?? ($_SERVER['HTTP_X_OTM_SYNC'] ?? ''));

if ($expected === '') {
    otm_json(['ok' => false, 'error' => 'sincronização desativada (defina o segredo sync_token nos ajustes)'], 403);
}
if (!hash_equals($expected, $given)) {
    otm_json(['ok' => false, 'error' => 'segredo inválido'], 403);
}

$keys = new KeyService($db);
$now  = otm_now();

$rows = $db->all(
    'SELECT key_hash FROM otm_keys
      WHERE revoked_at IS NULL
        AND (expires_at IS NULL OR expires_at > ?)
        AND (max_uses = 0 OR uses_count < max_uses)',
    [$now]
);

otm_json([
    'ok'      => true,
    'updated' => time(),
    'count'   => count($rows),
    'hashes'  => array_values(array_map(static fn(array $r) => (string)$r['key_hash'], $rows)),
]);
