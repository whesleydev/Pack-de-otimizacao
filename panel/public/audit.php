<?php
// =============================================================================
//  audit.php - Log de auditoria: quem fez o quê no painel.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

// Limpeza do log: só o dono, e a própria limpeza fica registrada.
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    otm_require_write();
    if (!$auth->isOwner()) {
        otm_redirect('audit.php?erro=' . urlencode('Só o dono (owner) pode limpar a auditoria.'));
    }
    $act = otm_post('act');
    if ($act === 'prune') {
        $dias = max(1, otm_int($_POST['days'] ?? 90));
        $audit->log('audit.prune', 'audit', '', "apagou registros com mais de $dias dia(s)", $me);
        $restou = $audit->prune($dias);
        otm_redirect('audit.php?ok=' . urlencode("Registros com mais de $dias dia(s) apagados ($restou no total)."));
    }
    if ($act === 'clear') {
        $audit->clear();
        $audit->log('audit.clear', 'audit', '', 'apagou toda a auditoria', $me);
        otm_redirect('audit.php?ok=' . urlencode('Auditoria apagada.'));
    }
}

$page = max(1, otm_int($_GET['p'] ?? 1));
$per  = 60;
$total = $audit->count();
$rows  = $audit->recent($per, ($page - 1) * $per);
$pages = max(1, (int)ceil($total / $per));

$title = 'Auditoria';
require __DIR__ . '/../src/layout.php';
?>

<h1>Auditoria</h1>
<div class="sub"><?= $total ?> ação(ões) registrada(s).</div>

<?= otm_flash() ?>

<?php if ($auth->isOwner()): ?>
  <form class="bar" method="post" action="audit.php">
    <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
    <div class="fld narrow"><label>Apagar mais antigos que</label>
      <input type="number" name="days" min="1" value="90"></div>
    <div class="fld"><label>&nbsp;</label>
      <button class="btn ghost" type="submit" name="act" value="prune">apagar antigos</button></div>
    <div class="fld"><label>&nbsp;</label>
      <button class="btn danger" type="submit" name="act" value="clear"
              onclick="return confirm('Apagar TODA a auditoria? Não dá para desfazer.')">apagar tudo</button></div>
  </form>
<?php endif; ?>

<table class="grid">
  <tr><th>Quando</th><th>Quem</th><th>Ação</th><th>Alvo</th><th>Detalhe</th><th>IP</th></tr>
  <?php if (!$rows): ?>
    <tr><td class="empty" colspan="6">Nada registrado ainda.</td></tr>
  <?php else: foreach ($rows as $a): ?>
    <tr>
      <td class="nowrap mono"><?= otm_e(otm_fmt_dt($a['created_at'])) ?></td>
      <td><?= otm_e((string)$a['actor']) ?></td>
      <td class="mono"><?= otm_e((string)$a['action']) ?></td>
      <td class="mono"><?= otm_e((string)$a['entity']) ?><?= ($a['entity_id'] !== '' ? '#' . otm_e((string)$a['entity_id']) : '') ?></td>
      <td><?= otm_e((string)$a['details']) ?></td>
      <td class="mono"><?= otm_e((string)$a['ip']) ?></td>
    </tr>
  <?php endforeach; endif; ?>
</table>

<?php if ($pages > 1): ?>
  <div class="pager">
    <?php for ($i = 1; $i <= min($pages, 30); $i++): ?>
      <?php if ($i === $page): ?><span class="cur"><?= $i ?></span>
      <?php else: ?><a href="audit.php?p=<?= $i ?>"><?= $i ?></a><?php endif; ?>
    <?php endfor; ?>
    <span class="muted">página <?= $page ?> de <?= $pages ?></span>
  </div>
<?php endif; ?>

<?php otm_layout_end(); ?>
