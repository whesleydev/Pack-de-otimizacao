<?php
// =============================================================================
//  api.php - Endpoint JSON do painel web.
//  Toda ação passa por otm_run(), que valida id + parâmetros (whitelist).
//  Protegido por token (arquivo .token na pasta web/, gerado pelo main.sh).
// =============================================================================

declare(strict_types=1);
require __DIR__ . '/lib.php';
require_once __DIR__ . '/keys.php';

header('X-Content-Type-Options: nosniff');

// --- autenticação por chave ---------------------------------------------------
// Vale a sessão do painel (entrou com a chave) OU a chave enviada no cabeçalho
// X-Otm-Key / em ?key=. Sem chave válida, nada executa.
function otm_check_access(): bool {
    // 1) sessão do painel (a chave já foi validada no acesso)
    if (otm_key_logged_in()) return true;

    // 2) chave enviada direto (scripts, integrações, acesso por URL)
    $sent = '';
    if (!empty($_SERVER['HTTP_X_OTM_KEY']))  $sent = trim((string)$_SERVER['HTTP_X_OTM_KEY']);
    elseif (isset($_GET['key']))             $sent = trim((string)$_GET['key']);

    return $sent !== '' && otm_key_verify($sent) !== null;
}

if (!otm_check_access()) {
    otm_json(['ok' => false, 'error' => 'acesso negado (informe uma chave válida)'], 403);
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

// Terminal: executa um comando cru (só o dono do painel, já autenticado acima).
if ($method === 'POST' && ($_GET['do'] ?? '') === 'term') {
    $raw = file_get_contents('php://input') ?: '';
    $body = json_decode($raw, true);
    $cmd = is_array($body) ? (string)($body['cmd'] ?? '') : '';
    $res = otm_run_command($cmd);
    otm_json($res);
    exit;
}

switch ($action) {
    case 'status':     otm_json(otm_status()); break;
    case 'dns_status': otm_json(otm_dns_status()); break;
    case 'state':      otm_json(['ok' => true, 'state' => otm_state_read()]); break;
    case 'stats':      otm_json(['ok' => true, 'stats' => otm_stats_read()]); break;
    case 'mode':       otm_json(['ok' => true] + otm_mode()); break;
    case 'apps':       otm_json(['ok' => true, 'apps' => otm_apps()]); break;
    case 'apps_meta':  otm_json(['ok' => true, 'apps' => otm_apps_meta()]); break;
    case 'modules':    otm_json(['ok' => true, 'modules' => otm_modules()]); break;
    case 'log':        otm_json(['ok' => true, 'log' => otm_log_read()]); break;
    case 'log_all':    otm_json(['ok' => true, 'log' => otm_log_all()]); break;
    case 'actions':    otm_json(['ok' => true, 'actions' => array_values(otm_actions())]); break;
    case 'info':
        otm_json(['ok' => true, 'root' => otm_root(),
                  'php' => PHP_VERSION, 'have_adb' => otm_have('adb'),
                  'have_timeout' => otm_have('timeout')]);
        break;
    default:
        otm_json(['ok' => false, 'error' => 'ação desconhecida'], 404);
}
