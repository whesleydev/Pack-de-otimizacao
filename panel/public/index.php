<?php
// =============================================================================
//  index.php - Visão geral: números do sistema e atalhos.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
otm_require_login();

$s   = $keys->stats();
$plans = $db->all('SELECT * FROM otm_plans WHERE is_active = 1 ORDER BY sort_order');
$recent = $keys->recentEvents(12);

$title  = 'Visão geral';
require __DIR__ . '/../src/layout.php';
?>

<h1>Visão geral</h1>
<div class="sub">Situação das chaves de acesso do app 00deUdia Otimizações.</div>

<?= otm_flash() ?>

<div class="cards">
  <div class="card"><div class="k">Chaves ativas</div><div class="v ok"><?= (int)$s['active'] ?></div></div>
  <div class="card"><div class="k">Total de chaves</div><div class="v"><?= (int)$s['total'] ?></div></div>
  <div class="card"><div class="k">Expiradas</div><div class="v warn"><?= (int)$s['expired'] ?></div></div>
  <div class="card"><div class="k">Revogadas</div><div class="v err"><?= (int)$s['revoked'] ?></div></div>
  <div class="card"><div class="k">Aparelhos</div><div class="v info"><?= (int)$s['devices'] ?></div></div>
  <div class="card"><div class="k">Vencem em 7 dias</div><div class="v warn"><?= (int)$s['expiring7'] ?></div></div>
  <div class="card"><div class="k">Verificações 24h</div><div class="v"><?= (int)$s['checks24h'] ?></div></div>
  <div class="card"><div class="k">Falhas 24h</div><div class="v err"><?= (int)$s['fails24h'] ?></div></div>
</div>

<h2>Atalhos</h2>
<div class="actions">
  <a class="btn" href="key_new.php">criar chave</a>
  <a class="btn ghost" href="keys.php">ver todas as chaves</a>
  <a class="btn ghost" href="plans.php">planos</a>
  <a class="btn ghost" href="events.php">tentativas de acesso</a>
</div>

<h2>Últimas tentativas</h2>
<table class="grid">
  <tr><th>Quando</th><th>Chave</th><th>Nome</th><th>Resultado</th><th>Aparelho</th><th>IP</th></tr>
  <?php if (!$recent): ?>
    <tr><td class="empty" colspan="6">Nenhuma tentativa registrada ainda.</td></tr>
  <?php else: foreach ($recent as $e): ?>
    <tr>
      <td class="nowrap mono"><?= otm_e(otm_fmt_dt($e['created_at'])) ?></td>
      <td class="mono"><?= otm_e((string)$e['key_prefix']) ?></td>
      <td><?= otm_e((string)($e['label'] ?: '—')) ?></td>
      <td><?= otm_status_tag($e['result'] === 'ok' ? 'active' : ($e['result'] === 'expired' ? 'expired' : 'revoked')) ?>
          <span class="muted"><?= otm_e((string)$e['result']) ?></span></td>
      <td class="mono"><?= otm_e((string)($e['device_id'] ?: '—')) ?></td>
      <td class="mono"><?= otm_e((string)$e['ip']) ?></td>
    </tr>
  <?php endforeach; endif; ?>
</table>

<h2>Planos disponíveis</h2>
<table class="grid">
  <tr><th>Plano</th><th>Duração</th><th>Aparelhos</th><th>Descrição</th></tr>
  <?php foreach ($plans as $p): ?>
    <tr>
      <td><b><?= otm_e((string)$p['name']) ?></b> <span class="muted mono"><?= otm_e((string)$p['slug']) ?></span></td>
      <td><?= $p['duration_days'] === null ? 'vitalício' : (int)$p['duration_days'] . ' dias' ?></td>
      <td><?= (int)$p['max_devices'] === 0 ? 'ilimitado' : (int)$p['max_devices'] ?></td>
      <td class="muted"><?= otm_e((string)$p['description']) ?></td>
    </tr>
  <?php endforeach; ?>
</table>

<?php otm_layout_end(); ?>
