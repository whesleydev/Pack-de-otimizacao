<?php
// =============================================================================
//  keys.php - Lista de chaves com filtros e ações rápidas.
//
//  É a tela mais usada: procurar o cliente, ver se a chave vale, revogar ou
//  liberar aparelho sem sair daqui.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

$q      = otm_get('q');
$status = otm_get('status');
$plan   = otm_int($_GET['plan'] ?? 0);
$order  = otm_get('order', 'recent');
$page   = max(1, otm_int($_GET['p'] ?? 1));
$per    = 25;

// --- ações rápidas (POST) -----------------------------------------------------
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    otm_require_write();
    $id  = otm_int($_POST['id'] ?? 0);
    $act = otm_post('act');
    $back = 'keys.php?' . http_build_query(array_filter([
        'q' => $q, 'status' => $status, 'plan' => $plan ?: null, 'order' => $order, 'p' => $page,
    ]));

    if ($id > 0) {
        $k = $keys->find($id);
        if ($k) {
            switch ($act) {
                case 'revoke':
                    $keys->revoke($id, otm_post('reason'));
                    $audit->log('key.revoke', 'key', (string)$id, 'revogou ' . $k['key_prefix'] . ' (' . $k['label'] . ')', $me);
                    otm_redirect($back . '&ok=' . urlencode('Chave ' . $k['key_prefix'] . ' revogada.'));
                case 'restore':
                    $keys->restore($id);
                    $audit->log('key.restore', 'key', (string)$id, 'reativou ' . $k['key_prefix'], $me);
                    otm_redirect($back . '&ok=' . urlencode('Chave ' . $k['key_prefix'] . ' reativada.'));
                case 'extend':
                    $d = otm_int($_POST['days'] ?? 30);
                    $keys->extend($id, $d);
                    $audit->log('key.extend', 'key', (string)$id, "+$d dia(s) em " . $k['key_prefix'], $me);
                    otm_redirect($back . '&ok=' . urlencode("Chave {$k['key_prefix']} estendida em $d dia(s)."));
                case 'rm':
                    $keys->delete($id);
                    $audit->log('key.delete', 'key', (string)$id, 'apagou ' . $k['key_prefix'] . ' (' . $k['label'] . ')', $me);
                    otm_redirect('keys.php?ok=' . urlencode('Chave ' . $k['key_prefix'] . ' apagada.'));
            }
        }
    }
    otm_redirect($back . '&erro=' . urlencode('Não consegui executar a ação.'));
}

// --- listagem -----------------------------------------------------------------
$res   = $keys->search(['q' => $q, 'status' => $status, 'plan' => $plan, 'order' => $order,
                        'limit' => $per, 'offset' => ($page - 1) * $per]);
$res['rows'] = $keys->attachDeviceCounts($res['rows']);
$plans = $db->all('SELECT id, name FROM otm_plans ORDER BY sort_order');
$pages = max(1, (int)ceil($res['total'] / $per));

$title = 'Chaves';
require __DIR__ . '/../src/layout.php';
?>

<h1>Chaves</h1>
<div class="sub"><?= (int)$res['total'] ?> chave(s) encontrada(s). Clique no prefixo para ver aparelhos e histórico.</div>

<?= otm_flash() ?>

<form class="bar" method="get" action="keys.php">
  <div class="fld"><label>Buscar</label><input type="text" name="q" value="<?= otm_e($q) ?>" placeholder="nome, contato, prefixo…"></div>
  <div class="fld"><label>Situação</label>
    <select name="status">
      <?php foreach (['' => 'todas', 'active' => 'ativas', 'expired' => 'expiradas',
                      'revoked' => 'revogadas', 'exhausted' => 'esgotadas'] as $v => $l): ?>
        <option value="<?= otm_e($v) ?>"<?= $status === $v ? ' selected' : '' ?>><?= otm_e($l) ?></option>
      <?php endforeach; ?>
    </select>
  </div>
  <div class="fld"><label>Plano</label>
    <select name="plan">
      <option value="0">todos</option>
      <?php foreach ($plans as $p): ?>
        <option value="<?= (int)$p['id'] ?>"<?= $plan === (int)$p['id'] ? ' selected' : '' ?>><?= otm_e((string)$p['name']) ?></option>
      <?php endforeach; ?>
    </select>
  </div>
  <div class="fld"><label>Ordem</label>
    <select name="order">
      <?php foreach (['recent' => 'mais recentes', 'oldest' => 'mais antigas',
                      'expiring' => 'quase vencendo', 'label' => 'nome (A-Z)'] as $v => $l): ?>
        <option value="<?= otm_e($v) ?>"<?= $order === $v ? ' selected' : '' ?>><?= otm_e($l) ?></option>
      <?php endforeach; ?>
    </select>
  </div>
  <div class="fld"><label>&nbsp;</label><button class="btn" type="submit">filtrar</button></div>
  <div class="fld"><label>&nbsp;</label><a class="btn ghost" href="keys.php">limpar</a></div>
  <div class="fld"><label>&nbsp;</label><a class="btn ghost" href="export.php?<?= otm_e(http_build_query(['q'=>$q,'status'=>$status,'plan'=>$plan?:null,'order'=>$order])) ?>">exportar CSV</a></div>
  <div class="fld"><label>&nbsp;</label><a class="btn" href="key_new.php">+ nova chave</a></div>
</form>

<table class="grid">
  <tr>
    <th>Prefixo</th><th>Nome</th><th>Contato</th><th>Situação</th><th>Expira</th>
    <th>Aparelhos</th><th>Usos</th><th>Último uso</th><th>Ações</th>
  </tr>
  <?php if (!$res['rows']): ?>
    <tr><td class="empty" colspan="9">Nenhuma chave com esses filtros. <a href="key_new.php">Criar uma chave</a>.</td></tr>
  <?php else: foreach ($res['rows'] as $k): ?>
    <tr class="rowlink" data-href="key_view.php?id=<?= (int)$k['id'] ?>">
      <td class="mono"><a href="key_view.php?id=<?= (int)$k['id'] ?>"><?= otm_e((string)$k['key_prefix']) ?></a></td>
      <td><?= otm_e((string)($k['label'] ?: '—')) ?>
          <?php if (!empty($k['plan_name'])): ?><br><span class="muted"><?= otm_e((string)$k['plan_name']) ?></span><?php endif; ?></td>
      <td class="muted"><?= otm_e((string)($k['owner_contact'] ?: '—')) ?></td>
      <td><?= otm_status_tag((string)$k['status']) ?></td>
      <td class="nowrap">
        <?= $k['expires_at'] ? otm_e(otm_fmt_dt((string)$k['expires_at'], 'd/m/Y')) : '<span class="muted">nunca</span>' ?>
        <?php if ($k['days_left'] !== null): ?>
          <br><span class="muted"><?= (int)$k['days_left'] ?> dia(s)</span>
        <?php endif; ?>
      </td>
      <td class="num"><?= (int)$k['device_count'] ?><?= (int)$k['max_devices'] > 0 ? ' / ' . (int)$k['max_devices'] : ' / ∞' ?></td>
      <td class="num"><?= (int)$k['uses_count'] ?><?= (int)$k['max_uses'] > 0 ? ' / ' . (int)$k['max_uses'] : '' ?></td>
      <td class="nowrap muted"><?= otm_e(otm_fmt_dt($k['last_used_at'])) ?></td>
      <td class="nowrap">
        <div class="actions">
          <a class="btn ghost sm" href="key_edit.php?id=<?= (int)$k['id'] ?>">editar</a>
          <?php if ($auth->canWrite()): ?>
            <?php if ((string)$k['status'] === 'revoked'): ?>
              <?= otm_action_button('keys.php', ['id' => $k['id'], 'act' => 'restore'], 'reativar') ?>
            <?php else: ?>
              <?= otm_action_button('keys.php', ['id' => $k['id'], 'act' => 'revoke'], 'revogar',
                                    'btn danger sm', 'Revogar ' . $k['key_prefix'] . '?') ?>
            <?php endif; ?>
            <?= otm_action_button('keys.php', ['id' => $k['id'], 'act' => 'extend', 'days' => 30], '+30d',
                                  'btn ghost sm', 'Estender ' . $k['key_prefix'] . ' em 30 dias?') ?>
          <?php endif; ?>
        </div>
      </td>
    </tr>
  <?php endforeach; endif; ?>
</table>

<?php if ($pages > 1): ?>
  <div class="pager">
    <?php for ($i = 1; $i <= $pages; $i++): ?>
      <?php if ($i === $page): ?>
        <span class="cur"><?= $i ?></span>
      <?php else: ?>
        <a href="keys.php?<?= otm_e(http_build_query(['q'=>$q,'status'=>$status,'plan'=>$plan?:null,'order'=>$order,'p'=>$i])) ?>"><?= $i ?></a>
      <?php endif; ?>
    <?php endfor; ?>
    <span class="muted">página <?= $page ?> de <?= $pages ?></span>
  </div>
<?php endif; ?>

<script>
// A linha inteira abre o detalhe da chave. Cliques em botões/links de ação
// seguem o caminho normal, sem navegar duas vezes.
document.querySelectorAll('tr.rowlink[data-href]').forEach(function (tr) {
  tr.style.cursor = 'pointer';
  tr.addEventListener('click', function (ev) {
    if (ev.target.closest('a, button, input, select, form')) return;
    window.location.href = tr.dataset.href;
  });
});
</script>

<?php otm_layout_end(); ?>
