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
<title>Entrar · Trix</title>
<link rel="stylesheet" href="assets/admin.css">
<script>
// Aplica o tema antes de pintar (mesma lógica do layout).
(function () {
  try {
    var t = localStorage.getItem('otm-theme');
    if (!t) t = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light';
    if (t === 'dark') document.documentElement.setAttribute('data-theme', 'dark');
  } catch (e) {}
})();
</script>
</head>
<body>
<div class="login-wrap">
  <form class="login" method="post" action="login.php">
    <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
    <input type="hidden" name="next" value="<?= otm_e($next) ?>">
    <h1>Painel</h1>
    <div class="sub">Trix · administração</div>

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
    <div class="theme-row">
      <button class="btn ghost sm" type="button" id="otmThemeBtn" title="Alternar tema claro/escuro">🌙 tema</button>
    </div>
  </form>
</div>
<script>
(function () {
  var btn = document.getElementById('otmThemeBtn');
  if (!btn) return;
  var isDark = function () { return document.documentElement.getAttribute('data-theme') === 'dark'; };
  var paint = function () { btn.textContent = isDark() ? '☀️ tema' : '🌙 tema'; };
  paint();
  btn.addEventListener('click', function () {
    if (isDark()) {
      document.documentElement.removeAttribute('data-theme');
      try { localStorage.setItem('otm-theme', 'light'); } catch (e) {}
    } else {
      document.documentElement.setAttribute('data-theme', 'dark');
      try { localStorage.setItem('otm-theme', 'dark'); } catch (e) {}
    }
    paint();
  });
})();
</script>
</body>
</html>
