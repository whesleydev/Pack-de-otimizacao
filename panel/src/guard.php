<?php
// =============================================================================
//  Guard.php - Protege páginas e trata formulários.
//
//  Cada página do painel começa assim:
//      require __DIR__ . '/../src/guard.php';
//
//  O guard: sobe a sessão, exige login, valida CSRF nos POST e entrega
//  $auth / $db / $keys / $audit / $admin já prontos para a página usar.
// =============================================================================

declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';

otm_session_start();

$db    = otm_db();
$auth  = new Auth($db);
$audit = new Audit($db);
$keys  = new KeyService($db);

$admin = $auth->user();

// --- CSRF em todo POST --------------------------------------------------------
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    $token = $_POST['_csrf'] ?? ($_SERVER['HTTP_X_CSRF_TOKEN'] ?? null);
    if (!$auth->csrfOk(is_string($token) ? $token : null)) {
        http_response_code(419);
        if (otm_is_api()) otm_json(['ok' => false, 'error' => 'sessão expirada (CSRF)'], 419);
        exit('Sessão expirada. Recarregue a página e tente de novo.');
    }
}

/** Estamos atendendo uma chamada de API (JSON) e não uma página? */
function otm_is_api(): bool
{
    return str_contains((string)($_SERVER['REQUEST_URI'] ?? ''), '/api/')
        || str_contains((string)($_SERVER['HTTP_ACCEPT'] ?? ''), 'application/json');
}

/** Exige login. Chame no topo de cada página (menos login.php). */
function otm_require_login(): array
{
    global $auth, $admin;
    if ($admin === null) {
        $to = $_SERVER['REQUEST_URI'] ?? '/';
        otm_redirect('login.php?next=' . urlencode($to));
    }
    return $admin;
}

/** Exige permissão de escrita (viewer só olha). */
function otm_require_write(): void
{
    global $auth;
    otm_require_login();
    if (!$auth->canWrite()) {
        http_response_code(403);
        exit('Seu perfil é somente leitura.');
    }
}
