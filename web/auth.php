<?php
// =============================================================================
//  auth.php - Login do painel 00deUdia Otimizações.
//
//  Sem login não se vê nem executa nada: index.php e api.php exigem sessão.
//  A senha é guardada com hash (password_hash) em ~/.packotm/web/auth.json,
//  nunca em texto puro e nunca versionada.
//
//  Padrão de fábrica: usuário e senha "00deUdia" (troque em Configs > Segurança
//  ou com `sh main.sh web senha`).
// =============================================================================

declare(strict_types=1);

const OTM_DEFAULT_USER = '00deUdia';
const OTM_DEFAULT_PASS = '00deUdia';
const OTM_SESSION_NAME = 'otm_sess';

function otm_auth_file(): string {
    $home = getenv('HOME') ?: sys_get_temp_dir();
    $dir = $home . '/.packotm/web';
    if (!is_dir($dir)) @mkdir($dir, 0700, true);
    return $dir . '/auth.json';
}

// --- estado -------------------------------------------------------------------
function otm_auth_load(): array {
    $f = otm_auth_file();
    if (is_file($f)) {
        $j = json_decode((string)file_get_contents($f), true);
        if (is_array($j) && isset($j['user'], $j['hash'])) return $j;
    }
    // primeira vez: cria com o padrão de fábrica
    $data = ['user' => OTM_DEFAULT_USER, 'hash' => password_hash(OTM_DEFAULT_PASS, PASSWORD_DEFAULT)];
    otm_auth_save($data);
    return $data;
}

function otm_auth_save(array $data): void {
    $f = otm_auth_file();
    @file_put_contents($f, json_encode($data, JSON_PRETTY_PRINT), LOCK_EX);
    @chmod($f, 0600);
}

function otm_auth_set(string $user, string $pass): void {
    otm_auth_save(['user' => $user, 'hash' => password_hash($pass, PASSWORD_DEFAULT)]);
}

// --- sessão -------------------------------------------------------------------
function otm_auth_start(): void {
    if (session_status() === PHP_SESSION_ACTIVE) return;
    if (headers_sent()) return;
    session_name(OTM_SESSION_NAME);
    session_set_cookie_params([
        'lifetime' => 0,
        'path'     => '/',
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    @session_start();
}

function otm_auth_logged_in(): bool {
    otm_auth_start();
    return !empty($_SESSION['otm_user']);
}

function otm_auth_user(): string {
    otm_auth_start();
    return (string)($_SESSION['otm_user'] ?? '');
}

function otm_auth_login(string $user, string $pass): bool {
    $a = otm_auth_load();
    if (!hash_equals((string)$a['user'], $user)) return false;
    if (!password_verify($pass, (string)$a['hash'])) return false;
    otm_auth_start();
    session_regenerate_id(true);
    $_SESSION['otm_user'] = $user;
    // mantém o token do servidor para a API (defesa em profundidade)
    $tf = __DIR__ . '/.token';
    if (is_file($tf)) {
        $tok = trim((string)file_get_contents($tf));
        if ($tok !== '') setcookie('otm_token', $tok, 0, '/');
    }
    return true;
}

function otm_auth_logout(): void {
    otm_auth_start();
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(OTM_SESSION_NAME, '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
    }
    @session_destroy();
}

// token de CSRF amarrado à sessão (usado no formulário de login e nas ações)
function otm_csrf(): string {
    otm_auth_start();
    if (empty($_SESSION['otm_csrf'])) $_SESSION['otm_csrf'] = bin2hex(random_bytes(16));
    return (string)$_SESSION['otm_csrf'];
}
function otm_csrf_ok(?string $t): bool {
    otm_auth_start();
    return is_string($t) && !empty($_SESSION['otm_csrf']) && hash_equals((string)$_SESSION['otm_csrf'], $t);
}
