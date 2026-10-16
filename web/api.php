<?php
// =============================================================================
//  api.php - Endpoint JSON do painel web.
//  Toda ação passa por otm_run(), que valida id + parâmetros (whitelist).
//  Protegido por token (arquivo .token na pasta web/, gerado pelo main.sh).
// =============================================================================

declare(strict_types=1);
require __DIR__ . '/lib.php';
require_once __DIR__ . '/auth.php';

header('X-Content-Type-Options: nosniff');

// --- autenticação -------------------------------------------------------------
// Vale o token do servidor (.token, gerado pelo main.sh) OU uma sessão logada
// no painel. Sem login e sem token, nada executa.
function otm_token_file(): string { return __DIR__ . '/.token'; }

function otm_check_token(): bool {
    // 1) sessão de login do painel
    if (otm_auth_logged_in()) return true;

    // 2) token do servidor (defesa em profundidade / acesso por URL com token)
    $f = otm_token_file();
    $expected = is_file($f) ? trim((string)file_get_contents($f)) : '';
    if ($expected === '') return false;         // sem token: exige login

    $sent = '';
    if (!empty($_SERVER['HTTP_X_OTM_TOKEN'])) $sent = trim((string)$_SERVER['HTTP_X_OTM_TOKEN']);
    elseif (isset($_GET['token']))           $sent = trim((string)$_GET['token']);
    elseif (isset($_COOKIE['otm_token']))    $sent = trim((string)$_COOKIE['otm_token']);

    if ($sent !== '' && hash_equals($expected, $sent)) {
        setcookie('otm_token', $sent, 0, '/');   // mantém a sessão do painel
        return true;
    }
    return false;
}

if (!otm_check_token()) {
    otm_json(['ok' => false, 'error' => 'acesso negado (entre no painel)'], 403);
    exit;
}

// --- roteamento ---------------------------------------------------------------
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$action = (string)($_GET['action'] ?? '');

if ($method === 'POST' && ($_GET['do'] ?? '') === 'run') {
    $raw = file_get_contents('php://input') ?: '';
    $body = json_decode($raw, true);
    if (!is_array($body)) {
        otm_json(['ok' => false, 'error' => 'JSON inválido'], 400);
        exit;
    }
    $id = (string)($body['id'] ?? '');
    $params = is_array($body['params'] ?? null) ? $body['params'] : [];
    $confirm = !empty($body['confirm']);
    $res = otm_run($id, $params, $confirm);
    otm_json($res, ($res['ok'] ?? false) ? 200 : 200);
    exit;
}

switch ($action) {
    case 'status':     otm_json(otm_status()); break;
    case 'dns_status': otm_json(otm_dns_status()); break;
    case 'state':      otm_json(['ok' => true, 'state' => otm_state_read()]); break;
    case 'mode':       otm_json(['ok' => true] + otm_mode()); break;
    case 'apps':       otm_json(['ok' => true, 'apps' => otm_apps()]); break;
    case 'modules':    otm_json(['ok' => true, 'modules' => otm_modules()]); break;
    case 'log':        otm_json(['ok' => true, 'log' => otm_log_read()]); break;
    case 'actions':    otm_json(['ok' => true, 'actions' => array_values(otm_actions())]); break;
    case 'info':
        otm_json(['ok' => true, 'root' => otm_root(),
                  'php' => PHP_VERSION, 'have_adb' => otm_have('adb'),
                  'have_timeout' => otm_have('timeout')]);
        break;
    default:
        otm_json(['ok' => false, 'error' => 'ação desconhecida'], 404);
}
