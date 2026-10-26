<?php
// =============================================================================
//  migrate.php - Aplica as migrations do banco no Turso.
//
//  Uso:
//      php panel/bin/migrate.php            # aplica o que falta
//      php panel/bin/migrate.php --status   # mostra o que já rodou
//      php panel/bin/migrate.php --fresh    # apaga as tabelas do domínio e refaz
//
//  Cada arquivo database/migrations/NNNN_nome.sql roda UMA vez e fica
//  registrado em otm_migrations (nome + checksum). Mudou um arquivo já
//  aplicado? O migrador avisa em vez de reaplicar silenciosamente.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$argvOpt = $argv[1] ?? '';
$status  = in_array($argvOpt, ['--status', '-s'], true);
$fresh   = in_array($argvOpt, ['--fresh', '-f'], true);

$dir = OTM_PANEL_ROOT . '/database/migrations';
if (!is_dir($dir)) {
    fwrite(STDERR, "pasta de migrations não encontrada: $dir\n");
    exit(1);
}

try {
    $db = otm_db();
} catch (Throwable $e) {
    fwrite(STDERR, "não consegui falar com o Turso: " . $e->getMessage() . "\n");
    fwrite(STDERR, "confira panel/config/turso.php (copie do .example)\n");
    exit(1);
}

// --- tabela de controle -------------------------------------------------------
$db->run(
    "CREATE TABLE IF NOT EXISTS otm_migrations (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        name       TEXT NOT NULL UNIQUE,
        checksum   TEXT NOT NULL DEFAULT '',
        applied_at TEXT NOT NULL DEFAULT (datetime('now'))
     )"
);

$applied = [];
foreach ($db->all('SELECT name, checksum, applied_at FROM otm_migrations') as $r) {
    $applied[(string)$r['name']] = $r;
}

$files = glob($dir . '/*.sql') ?: [];
sort($files, SORT_STRING);

if ($fresh) {
    // Ordem inversa para respeitar dependências (FK).
    $tables = ['otm_settings', 'otm_audit', 'otm_admin_sessions', 'otm_login_attempts', 'otm_admins'];
    foreach ($tables as $t) $db->run("DROP TABLE IF EXISTS $t");
    $db->run('DELETE FROM otm_migrations');
    $applied = [];
    echo "• tabelas do domínio apagadas (--fresh)\n";
}

if ($status) {
    echo "migrations em $dir\n\n";
    foreach ($files as $f) {
        $name = basename($f);
        $sum  = hash_file('sha256', $f);
        if (isset($applied[$name])) {
            $mark = ($applied[$name]['checksum'] === $sum) ? 'ok ' : 'MUDOU';
            printf("  [%s] %-28s %s\n", $mark, $name, $applied[$name]['applied_at']);
        } else {
            printf("  [falta] %-28s\n", $name);
        }
    }
    exit(0);
}

// --- aplica -------------------------------------------------------------------
$ran = 0;
foreach ($files as $f) {
    $name = basename($f);
    $sql  = (string)file_get_contents($f);
    $sum  = hash('sha256', $sql);

    if (isset($applied[$name])) {
        if ($applied[$name]['checksum'] !== $sum) {
            echo "  ! $name já foi aplicada, mas o arquivo mudou (checksum diferente).\n";
            echo "    Use --fresh se for ambiente de teste, ou crie uma migration nova.\n";
        }
        continue;
    }

    // Executa comando por comando (o Turso aceita um statement por vez no pipeline).
    foreach (otm_split_sql($sql) as $stmt) {
        try {
            $db->run($stmt);
        } catch (Throwable $e) {
            fwrite(STDERR, "  x $name falhou: " . $e->getMessage() . "\n");
            fwrite(STDERR, "    comando: " . substr(preg_replace('/\s+/', ' ', $stmt), 0, 160) . "\n");
            exit(1);
        }
    }

    $db->run('INSERT INTO otm_migrations (name, checksum, applied_at) VALUES (?,?,?)',
             [$name, $sum, otm_now()]);
    printf("  + %s aplicada\n", $name);
    $ran++;
}

printf("\n%s — %d migration(ões) aplicada(s).\n", $ran ? 'pronto' : 'nada a fazer', $ran);

/** Quebra um arquivo .sql em comandos, respeitando comentários e strings. */
function otm_split_sql(string $sql): array
{
    $stmts = [];
    $buf   = '';
    $len   = strlen($sql);
    $inStr = false;
    $q     = '';

    for ($i = 0; $i < $len; $i++) {
        $c = $sql[$i];

        // comentário de linha
        if (!$inStr && $c === '-' && ($sql[$i + 1] ?? '') === '-') {
            while ($i < $len && $sql[$i] !== "\n") $i++;
            continue;
        }
        if (!$inStr && $c === '/' && ($sql[$i + 1] ?? '') === '*') {
            $i += 2;
            while ($i < $len && !($sql[$i] === '*' && ($sql[$i + 1] ?? '') === '/')) $i++;
            $i++;
            continue;
        }

        if ($inStr) {
            $buf .= $c;
            if ($c === $q) {
                // '' dentro de string é escape, não fim
                if (($sql[$i + 1] ?? '') === $q) { $buf .= $sql[++$i]; continue; }
                $inStr = false;
            }
            continue;
        }

        if ($c === "'" || $c === '"' || $c === '`') { $inStr = true; $q = $c; $buf .= $c; continue; }

        if ($c === ';') {
            $t = trim($buf);
            if ($t !== '') $stmts[] = $t;
            $buf = '';
            continue;
        }
        $buf .= $c;
    }
    $t = trim($buf);
    if ($t !== '') $stmts[] = $t;
    return $stmts;
}
