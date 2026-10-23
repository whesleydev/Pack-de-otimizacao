<?php
// =============================================================================
//  admin.php - CLI para gerenciar administradores do painel.
//
//  Uso:
//      php panel/bin/admin.php list
//      php panel/bin/admin.php add <usuario> [--role owner|admin|viewer] [--name N] [--email E]
//      php panel/bin/admin.php passwd <usuario>          # troca a senha
//      php panel/bin/admin.php disable <usuario>
//      php panel/bin/admin.php enable <usuario>
//
//  A senha é pedida no terminal (não aparece no histórico do shell).
//  Para automação/teste, use a variável OTM_PASSWORD.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$cmd  = $argv[1] ?? 'help';
$user = $argv[2] ?? '';

$opts = [];
for ($i = 3; $i < $argc; $i++) {
    if (str_starts_with((string)$argv[$i], '--')) {
        $k = substr((string)$argv[$i], 2);
        $v = ($i + 1 < $argc && !str_starts_with((string)$argv[$i + 1], '--')) ? (string)$argv[++$i] : '1';
        $opts[$k] = $v;
    }
}

$db   = otm_db();
$auth = new Auth($db);

/** Pede a senha: da variável OTM_PASSWORD ou do terminal (sem eco). */
function ask_password(): string
{
    $env = getenv('OTM_PASSWORD');
    if ($env !== false && $env !== '') return (string)$env;

    fwrite(STDOUT, "senha: ");
    $hide = stripos(PHP_OS_FAMILY, 'win') === false && function_exists('shell_exec');
    if ($hide) @shell_exec('stty -echo 2>/dev/null');
    $p = (string)fgets(STDIN);
    if ($hide) @shell_exec('stty echo 2>/dev/null');
    fwrite(STDOUT, "\n");
    return rtrim($p, "\r\n");
}

switch ($cmd) {
    case 'add':
        if ($user === '') { fwrite(STDERR, "informe o usuário\n"); exit(1); }
        $role = (string)($opts['role'] ?? 'admin');
        if (!in_array($role, ['owner', 'admin', 'viewer'], true)) {
            fwrite(STDERR, "role inválido (use owner, admin ou viewer)\n"); exit(1);
        }
        $pass = ask_password();
        if (strlen($pass) < 6) { fwrite(STDERR, "senha muito curta (mínimo 6 caracteres)\n"); exit(1); }
        $id = $auth->upsert($user, $pass, $role, (string)($opts['name'] ?? ''), (string)($opts['email'] ?? ''));
        printf("✔ admin '%s' salvo (id %d, papel %s)\n", strtolower($user), $id, $role);
        break;

    case 'passwd':
        if ($user === '') { fwrite(STDERR, "informe o usuário\n"); exit(1); }
        $pass = ask_password();
        if (strlen($pass) < 6) { fwrite(STDERR, "senha muito curta (mínimo 6 caracteres)\n"); exit(1); }
        $n = $db->run('UPDATE otm_admins SET password_hash = ?, updated_at = ? WHERE username = ?',
                      [password_hash($pass, PASSWORD_DEFAULT), otm_now(), strtolower($user)]);
        printf($n >= 0 ? "✔ senha de '%s' trocada\n" : "não achei '%s'\n", strtolower($user));
        break;

    case 'disable':
    case 'enable':
        if ($user === '') { fwrite(STDERR, "informe o usuário\n"); exit(1); }
        $db->run('UPDATE otm_admins SET is_active = ? WHERE username = ?',
                 [$cmd === 'enable' ? 1 : 0, strtolower($user)]);
        printf("✔ '%s' %s\n", strtolower($user), $cmd === 'enable' ? 'habilitado' : 'desabilitado');
        break;

    case 'list':
        $rows = $db->all('SELECT id, username, name, role, is_active, last_login_at FROM otm_admins ORDER BY id');
        if (!$rows) { echo "nenhum administrador cadastrado\n"; break; }
        printf("%-4s %-16s %-20s %-8s %-10s %s\n", 'id', 'usuario', 'nome', 'papel', 'situação', 'último acesso');
        foreach ($rows as $r) {
            printf("%-4d %-16s %-20s %-8s %-10s %s\n",
                (int)$r['id'], (string)$r['username'], (string)$r['name'], (string)$r['role'],
                ((int)$r['is_active'] === 1 ? 'ativo' : 'inativo'),
                otm_fmt_dt($r['last_login_at']));
        }
        break;

    default:
        echo <<<TXT
        Painel 00deUdia — administradores

          php panel/bin/admin.php list
          php panel/bin/admin.php add <usuario> [--role owner|admin|viewer] [--name "Nome"] [--email e@x]
          php panel/bin/admin.php passwd <usuario>
          php panel/bin/admin.php disable <usuario>
          php panel/bin/admin.php enable <usuario>

        A senha é pedida no terminal. Em script, defina OTM_PASSWORD.

        TXT;
}
