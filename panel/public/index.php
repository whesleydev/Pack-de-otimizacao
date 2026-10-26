<?php
// =============================================================================
//  index.php - Visão geral: quem entra no painel e atalhos.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

$admins = $db->all('SELECT id, username, name, email, role, is_active, last_login_at FROM otm_admins ORDER BY id');
$recent = $db->all('SELECT * FROM otm_audit ORDER BY id DESC LIMIT 12');

$title  = 'Visão geral';
require __DIR__ . '/../src/layout.php';
?>

<h1>Visão geral</h1>
<div class="sub">Situação do painel 00deUdia Otimizações.</div>

<?= otm_flash() ?>

<div class="cards">
  <div class="card"><div class="k">Administradores</div><div class="v ok"><?= count($admins) ?></div></div>
  <div class="card"><div class="k">Ativos</div><div class="v info"><?= count(array_filter($admins, fn($a) => (int)$a['is_active'] === 1)) ?></div></div>
  <div class="card"><div class="k">Você entrou como</div><div class="v"><?= otm_e((string)$me['username']) ?></div></div>
</div>

<h2>Atalhos</h2>
<div class="actions">
  <a class="btn" href="admins.php">administradores</a>
  <a class="btn ghost" href="audit.php">auditoria</a>
  <a class="btn ghost" href="settings.php">ajustes</a>
</div>

<h2>Administradores</h2>
<table class="grid">
  <tr><th>Usuário</th><th>Nome</th><th>Perfil</th><th>Situação</th><th>Último acesso</th></tr>
  <?php foreach ($admins as $a): ?>
    <tr>
      <td class="mono"><?= otm_e((string)$a['username']) ?></td>
      <td><?= otm_e((string)($a['name'] ?: '—')) ?></td>
      <td><?= otm_e((string)$a['role']) ?></td>
      <td><?= (int)$a['is_active'] === 1 ? 'ativo' : '<span class="muted">inativo</span>' ?></td>
      <td class="nowrap mono"><?= $a['last_login_at'] ? otm_e(otm_fmt_dt((string)$a['last_login_at'])) : '—' ?></td>
    </tr>
  <?php endforeach; ?>
</table>

<h2>Últimos registros</h2>
<table class="grid">
  <tr><th>Quando</th><th>Quem</th><th>Ação</th><th>Detalhe</th></tr>
  <?php if (!$recent): ?>
    <tr><td class="empty" colspan="4">Nenhum registro ainda.</td></tr>
  <?php else: foreach ($recent as $r): ?>
    <tr>
      <td class="nowrap mono"><?= otm_e(otm_fmt_dt((string)$r['created_at'])) ?></td>
      <td class="mono"><?= otm_e((string)($r['actor'] ?: '—')) ?></td>
      <td class="mono"><?= otm_e((string)$r['action']) ?></td>
      <td class="muted"><?= otm_e((string)$r['details']) ?></td>
    </tr>
  <?php endforeach; endif; ?>
</table>

<?php otm_layout_end(); ?>
