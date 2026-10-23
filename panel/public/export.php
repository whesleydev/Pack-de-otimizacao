<?php
// =============================================================================
//  export.php - Baixa a lista de chaves em CSV (para planilha/backup).
//
//  NÃO exporta o hash nem a chave em texto: só o que é seguro guardar
//  (prefixo, nome, contato, datas, situação).
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

$res = $keys->search([
    'q'      => otm_get('q'),
    'status' => otm_get('status'),
    'plan'   => otm_int($_GET['plan'] ?? 0),
    'order'  => otm_get('order', 'recent'),
    'limit'  => 200,
    'offset' => 0,
]);
$res['rows'] = $keys->attachDeviceCounts($res['rows']);

$audit->log('key.export', 'key', '', 'exportou ' . count($res['rows']) . ' chave(s) em CSV', $me);

$name = 'chaves-00deudia-' . date('Ymd-His') . '.csv';
header('Content-Type: text/csv; charset=utf-8');
header('Content-Disposition: attachment; filename="' . $name . '"');
header('X-Content-Type-Options: nosniff');

$out = fopen('php://output', 'w');
fprintf($out, chr(0xEF) . chr(0xBB) . chr(0xBF)); // BOM: Excel abre com acento certo
fputcsv($out, ['id', 'prefixo', 'nome', 'contato', 'plano', 'situacao', 'criada', 'expira',
               'dias_restantes', 'aparelhos', 'max_aparelhos', 'usos', 'max_usos', 'ultimo_uso', 'observacao'], ';');
foreach ($res['rows'] as $k) {
    fputcsv($out, [
        (int)$k['id'], (string)$k['key_prefix'], (string)$k['label'], (string)$k['owner_contact'],
        (string)($k['plan_name'] ?? ''), (string)$k['status'],
        otm_fmt_dt($k['created_at']), ($k['expires_at'] ? otm_fmt_dt((string)$k['expires_at']) : 'nunca'),
        ($k['days_left'] === null ? '' : (int)$k['days_left']),
        (int)$k['device_count'], (int)$k['max_devices'],
        (int)$k['uses_count'], (int)$k['max_uses'],
        otm_fmt_dt($k['last_used_at']), (string)$k['note'],
    ], ';');
}
fclose($out);
