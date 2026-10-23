<?php
// =============================================================================
//  login.php - Entrada no painel (usuário + senha do administrador).
//
//  Primeiro acesso: crie o dono pelo terminal —
//      php panel/bin/admin.php add whesley --role owner
// =============================================================================

declare(strict_types=1);

require_once __DIR__ . '/../src/bootstrap.php';

otm_session_start();

$db   = otm_db();
$auth = new Auth($db);

// já logado? vai para a visão geral
if ($auth->check()) otm_redirect('index.php');

$erro = '';
$next = (string)($_GET['next'] ?? 'index.php');
// só caminhos relativos: evita redirecionar para fora do painel
if ($next === '' || preg_match('~^(?:[a-z]+:|//)~i', $next)) $next = 'index.php';

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    $token = $_POST['_csrf'] ?? null;
    if (!$auth->csrfOk(is_string($token) ? $token : null)) {
        $erro = 'Sessão expirada. Tente de novo.';
    } else {
        $res = $auth->login(
            (string)($_POST['username'] ?? ''),
            (string)($_POST['password'] ?? ''),
            otm_client_ip(),
            (string)($_SERVER['HTTP_USER_AGENT'] ?? '')
        );
        if ($res['ok']) {
            $audit = new Audit($db);
            $audit->log('admin.login', 'admin', (string)($res['admin']['id'] ?? ''), 'login pelo painel', $res['admin']);
            otm_redirect($next);
        }
        $erro = (string)($res['error'] ?? 'Não consegui entrar.');
    }
}

$semAdmin = $auth->countAdmins() === 0;
?><!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Entrar · Painel 00deUdia</title>
<link rel="stylesheet" href="assets/admin.css">
</head>
<body>
<div class="login-wrap">
  <form class="login" method="post" action="login.php">
    <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
    <input type="hidden" name="next" value="<?= otm_e($next) ?>">
    <h1>Painel de chaves</h1>
    <div class="sub">00deUdia Otimizações · administração</div>

    <?php if ($erro !== ''): ?><?= otm_msg('err', otm_e($erro)) ?><?php endif; ?>
    <?php if ($semAdmin): ?>
      <?= otm_msg('warn', 'Ainda não existe administrador. Crie o primeiro pelo terminal:<br><code>php panel/bin/admin.php add SEU_USUARIO --role owner</code>') ?>
    <?php endif; ?>

    <div class="fld">
      <label for="username">Usuário</label>
      <input id="username" name="username" type="text" autocomplete="username" autofocus required>
    </div>
    <div class="fld">
      <label for="password">Senha</label>
      <input id="password" name="password" type="password" autocomplete="current-password" required>
    </div>
    <button class="btn" type="submit">entrar</button>
  </form>
</div>
</body>
</html>
