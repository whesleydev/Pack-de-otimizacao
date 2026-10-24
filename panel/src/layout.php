<?php
// =============================================================================
//  layout.php - Cabeçalho, menu e rodapé do painel.
//
//  Uso numa página:
//      $title = 'Chaves';
//      require __DIR__ . '/../src/layout.php';   // imprime o topo
//      ... conteúdo ...
//      otm_layout_end();                          // imprime o rodapé
//
//  O menu marca sozinho a página atual pelo nome do arquivo.
// =============================================================================

declare(strict_types=1);

if (!function_exists('otm_layout_head')) {

    function otm_layout_head(string $title, array $admin, string $active = ''): void
    {
        $me   = basename((string)($_SERVER['SCRIPT_NAME'] ?? ''));
        $on   = static fn(string $f) => $f === $me ? ' class="on"' : '';
        $csrf = $_SESSION['otm_csrf'] ?? '';
        $role = (string)($admin['role'] ?? 'admin');
        ?><!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= otm_e($title) ?> · Painel 00deUdia</title>
<link rel="stylesheet" href="assets/admin.css">
<script>
// Aplica o tema antes da página pintar (evita o "flash" branco). A escolha
// fica em localStorage; sem escolha, o tema do sistema decide.
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
<div class="topbar">
  <span class="brand">00deUdia Otimizações <small>· painel de chaves</small></span>
  <span class="spacer"></span>
  <span class="who">usuário: <b><?= otm_e((string)($admin['username'] ?? '')) ?></b>
    <span class="tag <?= otm_e($role) ?>"><?= otm_e($role) ?></span>
  </span>
  <button class="btn themebtn" type="button" id="otmThemeBtn" title="Alternar tema claro/escuro">🌙</button>
  <form method="post" action="logout.php" style="margin:0">
    <input type="hidden" name="_csrf" value="<?= otm_e((string)$csrf) ?>">
    <button class="btn ghost sm" type="submit">sair</button>
  </form>
</div>
<div class="shell">
  <nav class="side">
    <div class="sec">Painel</div>
    <a href="index.php"<?= $on('index.php') ?>>Visão geral</a>
    <a href="keys.php"<?= $on('keys.php') ?>>Chaves</a>
    <a href="key_new.php"<?= $on('key_new.php') ?>>Nova chave</a>
    <div class="sec">Catálogo</div>
    <a href="plans.php"<?= $on('plans.php') ?>>Planos</a>
    <a href="events.php"<?= $on('events.php') ?>>Tentativas</a>
    <div class="sec">Sistema</div>
    <a href="audit.php"<?= $on('audit.php') ?>>Auditoria</a>
    <a href="settings.php"<?= $on('settings.php') ?>>Ajustes</a>
    <a href="admins.php"<?= $on('admins.php') ?>>Administradores</a>
  </nav>
  <main class="main">
<?php
    }

    function otm_layout_end(string $status = ''): void
    {
        ?>
  </main>
</div>
<div class="statusbar">
  <span>Painel 00deUdia <?= otm_e(OTM_PANEL_VERSION) ?></span>
  <span class="muted">banco: <?= otm_e(otm_db_label()) ?></span>
  <?php if ($status !== ''): ?><span><?= otm_e($status) ?></span><?php endif; ?>
  <span class="spacer"></span>
  <span class="muted"><?= otm_e(date('d/m/Y H:i')) ?></span>
</div>
<script>
// Botão de tema: alterna claro/escuro e guarda a escolha no navegador.
(function () {
  var btn = document.getElementById('otmThemeBtn');
  if (!btn) return;
  var isDark = function () { return document.documentElement.getAttribute('data-theme') === 'dark'; };
  var paint = function () { btn.textContent = isDark() ? '☀️' : '🌙'; };
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

// Copiar a chave para a área de transferência. Usa a API moderna quando o
// navegador permite (contexto seguro) e cai no execCommand quando não.
function otmCopyKey(id, btn) {
  var el = document.getElementById(id);
  if (!el) return;
  var txt = el.textContent || '';
  var done = function () {
    if (!btn) return;
    var old = btn.textContent;
    btn.textContent = 'copiado!';
    btn.disabled = true;
    setTimeout(function () { btn.textContent = old; btn.disabled = false; }, 1400);
  };
  var fallback = function () {
    try {
      var ta = document.createElement('textarea');
      ta.value = txt;
      ta.setAttribute('readonly', '');
      ta.style.position = 'fixed';
      ta.style.opacity = '0';
      document.body.appendChild(ta);
      ta.select();
      document.execCommand('copy');
      document.body.removeChild(ta);
      done();
    } catch (e) { window.prompt('Copie a chave:', txt); }
  };
  if (navigator.clipboard && window.isSecureContext) {
    navigator.clipboard.writeText(txt).then(done, fallback);
  } else {
    fallback();
  }
}
</script>
</body>
</html>
<?php
    }

    /** Nome curto do banco em uso, para a barra de status. */
    function otm_db_label(): string
    {
        $local = otm_env('OTM_LOCAL_DB', '');
        if ($local !== '') return 'sqlite local';
        $cfg = otm_config('turso');
        $url = (string)($cfg['url'] ?? otm_env('TURSO_DATABASE_URL', ''));
        $tok = (string)($cfg['token'] ?? otm_env('TURSO_AUTH_TOKEN', ''));
        return ($url !== '' && $tok !== '' && !str_contains($url, 'SEU-BANCO')) ? 'turso' : 'sqlite local';
    }

    /** Etiqueta do estado da chave. */
    function otm_status_tag(string $status): string
    {
        $label = [
            'active' => 'ativa', 'expired' => 'expirada',
            'revoked' => 'revogada', 'exhausted' => 'esgotada',
        ][$status] ?? $status;
        return '<span class="tag ' . otm_e($status) . '">' . otm_e($label) . '</span>';
    }

    /**
     * Bloco com a chave em texto e botão de copiar.
     *
     * A chave vem do cofre (KeyVault). Quando o cofre está desligado ou a chave
     * é anterior a ele, o texto não existe mais: mostramos o aviso em vez de um
     * campo vazio, para não parecer que o painel quebrou.
     */
    function otm_keybox(string $plain, string $prefix = ''): string
    {
        if ($plain === '') {
            return '<div class="keybox off"><div class="k muted">— chave não guardada —</div>'
                . '<div class="w">Esta chave foi criada antes do cofre ou o cofre está desligado '
                . '(<span class="mono">php panel/bin/vault.php keygen</span>). Só o hash existe; '
                . 'não há como exibir o texto. Gere uma chave nova.</div></div>';
        }
        $id = 'kb' . substr(sha1($plain), 0, 8);
        return '<div class="keybox">'
            . '<div class="k" id="' . $id . '">' . otm_e($plain) . '</div>'
            . '<div class="kbrow">'
            . '<button type="button" class="btn sm" onclick="otmCopyKey(\'' . $id . '\', this)">copiar chave</button>'
            . ($prefix !== '' ? '<span class="muted mono">' . otm_e($prefix) . '</span>' : '')
            . '</div></div>';
    }

    /** Botão de ação com confirmação (POST). */
    function otm_action_button(string $action, array $fields, string $label,
                               string $cls = 'btn ghost sm', string $confirm = ''): string
    {
        $csrf = (string)($_SESSION['otm_csrf'] ?? '');
        $h = '<form method="post" action="' . otm_e($action) . '" style="display:inline"';
        if ($confirm !== '') $h .= ' onsubmit="return confirm(' . otm_e(json_encode($confirm)) . ')"';
        $h .= '><input type="hidden" name="_csrf" value="' . otm_e($csrf) . '">';
        foreach ($fields as $k => $v) {
            $h .= '<input type="hidden" name="' . otm_e((string)$k) . '" value="' . otm_e((string)$v) . '">';
        }
        return $h . '<button class="' . otm_e($cls) . '" type="submit">' . otm_e($label) . '</button></form>';
    }

    /** Mensagens vindas da query string (padrão: ?ok=... / ?erro=...). */
    function otm_flash(): string
    {
        $h = '';
        if (!empty($_GET['ok']))    $h .= otm_msg('ok', otm_e((string)$_GET['ok']));
        if (!empty($_GET['erro']))  $h .= otm_msg('err', otm_e((string)$_GET['erro']));
        if (!empty($_GET['aviso'])) $h .= otm_msg('warn', otm_e((string)$_GET['aviso']));
        return $h;
    }
}

otm_layout_head($title ?? 'Painel', $admin ?? [], $active ?? '');
