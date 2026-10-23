<?php
// =============================================================================
//  key.php - CLI para gerenciar chaves sem abrir o painel.
//
//  Uso:
//      php panel/bin/key.php list [--status active] [--q texto]
//      php panel/bin/key.php new [--label "Fulano"] [--days 30] [--devices 2] [--uses 0] [--plan mensal]
//      php panel/bin/key.php show <id>
//      php panel/bin/key.php duration <id> <dias|vitalicio>
//      php panel/bin/key.php extend <id> <dias>
//      php panel/bin/key.php revoke <id> [motivo]
//      php panel/bin/key.php restore <id>
//      php panel/bin/key.php rm <id>
//
//  A chave em texto só aparece UMA vez, no `new`. Depois só existe o hash.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$db   = otm_db();
$keys = new KeyService($db);

$cmd = $argv[1] ?? 'help';
$id  = isset($argv[2]) && ctype_digit((string)$argv[2]) ? (int)$argv[2] : 0;

$opts = [];
$json = false;
for ($i = 2; $i < $argc; $i++) {
    if ((string)$argv[$i] === '--json') { $json = true; continue; }
    if (str_starts_with((string)$argv[$i], '--')) {
        $k = substr((string)$argv[$i], 2);
        $v = ($i + 1 < $argc && !str_starts_with((string)$argv[$i + 1], '--')) ? (string)$argv[++$i] : '1';
        $opts[$k] = $v;
    }
}

/** Devolve em JSON (para scripts) ou em texto (para o terminal). */
function out(bool $json, array $data, callable $text): void
{
    if ($json) { echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES), "\n"; return; }
    $text($data);
}

switch ($cmd) {
    case 'new':
        $planId = null;
        if (!empty($opts['plan'])) {
            $p = $db->one('SELECT id, duration_days, max_devices, max_uses FROM otm_plans WHERE slug = ?', [(string)$opts['plan']]);
            if ($p) {
                $planId = (int)$p['id'];
                $opts['days']    ??= $p['duration_days'];
                $opts['devices'] ??= $p['max_devices'];
                $opts['uses']    ??= $p['max_uses'];
            } else {
                fwrite(STDERR, "plano '{$opts['plan']}' não existe (veja: key.php plans)\n"); exit(1);
            }
        }
        $days = array_key_exists('days', $opts)
            ? (in_array((string)$opts['days'], ['0', 'vitalicio', 'vitalício', 'never'], true) ? null : max(0, (int)$opts['days']))
            : 30;

        $c = $keys->create([
            'label'         => (string)($opts['label'] ?? ''),
            'owner_contact' => (string)($opts['contact'] ?? ''),
            'note'          => (string)($opts['note'] ?? ''),
            'plan_id'       => $planId,
            'duration_days' => $days,
            'max_devices'   => (int)($opts['devices'] ?? 1),
            'max_uses'      => (int)($opts['uses'] ?? 0),
            'created_by'    => 'cli',
        ]);
        $r = $c['row'];
        out($json, ['ok' => true, 'id' => $c['id'], 'key' => $c['key'],
                    'prefix' => $r['key_prefix'], 'expires_at' => $r['expires_at'],
                    'max_devices' => (int)$r['max_devices'], 'max_uses' => (int)$r['max_uses'],
                    'label' => (string)$r['label']], function (array $d) use ($c, $r): void {
            echo "\n  ✔ chave criada (guarde agora — não é mostrada de novo)\n\n";
            printf("     %s\n\n", $c['key']);
            printf("     id: %d\n", $c['id']);
            printf("     vigência: %s\n", $r['expires_at'] ? 'até ' . otm_fmt_dt($r['expires_at']) : 'vitalícia');
            printf("     aparelhos: %s\n", ((int)$r['max_devices'] === 0 ? 'ilimitado' : $r['max_devices']));
            printf("     usos: %s\n\n", ((int)$r['max_uses'] === 0 ? 'ilimitado' : $r['max_uses']));
        });
        break;

    case 'list':
        $f = ['q' => (string)($opts['q'] ?? ''), 'status' => (string)($opts['status'] ?? ''), 'limit' => 100];
        $res = $keys->search($f);
        out($json, ['ok' => true, 'total' => $res['total'], 'keys' => array_map(static fn(array $k) => [
            'id' => (int)$k['id'], 'prefix' => (string)$k['key_prefix'], 'label' => (string)$k['label'],
            'status' => (string)$k['status'], 'expires_at' => $k['expires_at'],
            'days_left' => $k['days_left'], 'max_devices' => (int)$k['max_devices'],
            'uses_count' => (int)$k['uses_count'], 'max_uses' => (int)$k['max_uses'],
        ], $res['rows'])], function (array $d) use ($res): void {
            if (!$res['rows']) { echo "nenhuma chave\n"; return; }
            printf("%-5s %-10s %-22s %-10s %-12s %-6s %s\n", 'id', 'prefixo', 'nome', 'situação', 'expira', 'apars', 'usos');
            foreach ($res['rows'] as $k) {
                printf("%-5d %-10s %-22s %-10s %-12s %-6s %s\n",
                    (int)$k['id'], (string)$k['key_prefix'],
                    otm_substr((string)($k['label'] ?: '(sem nome)'), 0, 21),
                    (string)$k['status'],
                    ($k['expires_at'] ? otm_fmt_dt($k['expires_at'], 'd/m/Y') : 'nunca'),
                    ((int)$k['max_devices'] === 0 ? '∞' : $k['max_devices']),
                    ((int)$k['max_uses'] === 0 ? (string)$k['uses_count'] : $k['uses_count'] . '/' . $k['max_uses'])
                );
            }
            printf("\n%d de %d chave(s)\n", count($res['rows']), $res['total']);
        });
        break;

    case 'show':
        $k = $id ? $keys->find($id) : null;
        if (!$k) { fwrite(STDERR, "chave não encontrada\n"); exit(1); }
        printf("id ........: %d\n", (int)$k['id']);
        printf("prefixo ...: %s\n", (string)$k['key_prefix']);
        printf("nome ......: %s\n", (string)$k['label']);
        printf("contato ...: %s\n", (string)$k['owner_contact']);
        printf("situação ..: %s\n", (string)$k['status']);
        printf("criada ....: %s\n", otm_fmt_dt($k['created_at']));
        printf("expira ....: %s%s\n", ($k['expires_at'] ? otm_fmt_dt($k['expires_at']) : 'nunca'),
               ($k['days_left'] !== null ? ' (' . $k['days_left'] . ' dia[s])' : ''));
        printf("usos ......: %d%s\n", (int)$k['uses_count'], ((int)$k['max_uses'] ? ' / ' . $k['max_uses'] : ''));
        $devs = $keys->devices($id);
        printf("aparelhos .: %d\n", count($devs));
        foreach ($devs as $d) printf("   - %s %s (visto %s)\n", $d['device_id'], $d['model'], otm_fmt_dt($d['last_seen_at']));
        break;

    case 'duration':
        $arg = (string)($argv[3] ?? '');
        $days = in_array($arg, ['vitalicio', 'vitalício', '0', 'never'], true) ? null : max(0, (int)$arg);
        $keys->setDuration($id, $days);
        printf("✔ chave %d: %s\n", $id, $days === null ? 'vitalícia' : $days . ' dia(s) a partir de agora');
        break;

    case 'extend':
        $d = max(0, (int)($argv[3] ?? 0));
        $keys->extend($id, $d);
        printf("✔ chave %d estendida em %d dia(s)\n", $id, $d);
        break;

    case 'revoke':
        $keys->revoke($id, (string)($argv[3] ?? ''));
        printf("✔ chave %d revogada\n", $id);
        break;

    case 'restore':
        $keys->restore($id);
        printf("✔ chave %d reativada\n", $id);
        break;

    case 'rm':
        $keys->delete($id);
        printf("✔ chave %d apagada\n", $id);
        break;

    case 'plans':
        foreach ($db->all('SELECT * FROM otm_plans WHERE is_active = 1 ORDER BY sort_order') as $p) {
            printf("  %-12s %-14s %-10s %s aparelho(s)\n", $p['slug'], $p['name'],
                ($p['duration_days'] === null ? 'vitalício' : $p['duration_days'] . ' dias'), $p['max_devices']);
        }
        break;

    case 'sync':
        // Gera o keys.json que o app usa para validar sem internet. O arquivo
        // é só uma lista de SHA-256 — não permite reconstruir nenhuma chave.
        $dest = (string)($opts['out'] ?? __DIR__ . '/../../app/src/main/assets/panel/keys.json');
        $rows = $db->all(
            'SELECT key_hash FROM otm_keys
              WHERE revoked_at IS NULL
                AND (expires_at IS NULL OR expires_at > ?)
                AND (max_uses = 0 OR uses_count < max_uses)',
            [otm_now()]
        );
        $hashes = array_values(array_map(static fn(array $r) => (string)$r['key_hash'], $rows));
        $dir = dirname($dest);
        if (!is_dir($dir)) @mkdir($dir, 0775, true);
        $ok = @file_put_contents($dest, json_encode(
            ['updated' => time(), 'count' => count($hashes), 'hashes' => $hashes],
            JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES
        ) . "\n");
        if ($ok === false) { fwrite(STDERR, "não consegui escrever em $dest\n"); exit(1); }
        printf("✔ %d chave(s) ativa(s) → %s\n", count($hashes), $dest);
        break;

    default:
        echo <<<TXT
        Painel 00deUdia — chaves

          php panel/bin/key.php list [--status active|expired|revoked|exhausted] [--q texto]
          php panel/bin/key.php new [--label "Fulano"] [--days 30|vitalicio] [--devices 2] [--uses 0] [--plan mensal]
          php panel/bin/key.php show <id>
          php panel/bin/key.php duration <id> <dias|vitalicio>
          php panel/bin/key.php extend <id> <dias>
          php panel/bin/key.php revoke <id> [motivo]
          php panel/bin/key.php restore <id>
          php panel/bin/key.php rm <id>
          php panel/bin/key.php plans
          php panel/bin/key.php sync [--out caminho/keys.json]

        TXT;
}
