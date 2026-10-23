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
        ?><!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title><?= otm_e($title) ?> · Painel 00deUdia</title>
<link rel="stylesheet" href="assets/admin.css">
</head>
<body>
<div class="topbar">
  <span class="brand">00deUdia <small>· painel de chaves</small></span>
  <span class="spacer"></span>
  <span class="who">entrou como <b><?= otm_e((string)($admin['username'] ?? '')) ?></b>
    <span class="tag <?= otm_e((string)($admin['role'] ?? 'admin')) ?>"><?= otm_e((string)($admin['role'] ?? 'admin')) ?></span>
  </span>
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

    function otm_layout_end(): void
    {
        ?>
  </main>
</div>
</body>
</html>
<?php
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
