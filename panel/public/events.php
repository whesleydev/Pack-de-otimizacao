<?php
// =============================================================================
//  events.php - Histórico de tentativas de validação de chave.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

$result = otm_get('result');
$q      = otm_get('q');
$page   = max(1, otm_int($_GET['p'] ?? 1));
$per    = 50;

// --- ações (POST) -------------------------------------------------------------
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    otm_require_write();
    $act = otm_post('act');
    if ($act === 'clear_days') {
        $dias = max(1, otm_int($_POST['days'] ?? 30));
        $limite = gmdate('Y-m-d H:i:s', time() - $dias * 86400);
        $db->run('DELETE FROM otm_key_events WHERE created_at < ?', [$limite]);
        $audit->log('event.clear', 'event', '', "apagou tentativas com mais de $dias dia(s)", $me);
        otm_redirect('events.php?ok=' . urlencode("Tentativas com mais de $dias dia(s) apagadas."));
    }
    if ($act === 'clear_all') {
        $db->run('DELETE FROM otm_key_events');
        $audit->log('event.clear', 'event', '', 'apagou todas as tentativas', $me);
        otm_redirect('events.php?ok=' . urlencode('Histórico de tentativas apagado.'));
    }
    if ($act === 'rm' && otm_int($_POST['id'] ?? 0) > 0) {
        $eid = otm_int($_POST['id']);
        $db->run('DELETE FROM otm_key_events WHERE id = ?', [$eid]);
        $audit->log('event.delete', 'event', (string)$eid, 'apagou tentativa', $me);
        otm_redirect('events.php?ok=' . urlencode('Tentativa apagada.'));
    }
}

$where = [];
$args  = [];
if ($result !== '') { $where[] = 'e.result = ?'; $args[] = $result; }
if ($q !== '') {
    $where[] = '(e.key_prefix LIKE ? OR e.device_id LIKE ? OR e.ip LIKE ?)';
    $like = '%' . $q . '%';
    array_push($args, $like, $like, $like);
}
$w = $where ? ' WHERE ' . implode(' AND ', $where) : '';

$total = (int)$db->scalar('SELECT COUNT(*) FROM otm_key_events e' . $w, $args);
$rows  = $db->all(
    'SELECT e.*, k.label FROM otm_key_events e LEFT JOIN otm_keys k ON k.id = e.key_id' . $w .
    ' ORDER BY e.created_at DESC LIMIT ? OFFSET ?',
    [...$args, $per, ($page - 1) * $per]
);
$pages = max(1, (int)ceil($total / $per));

$title = 'Tentativas';
require __DIR__ . '/../src/layout.php';
?>

<h1>Tentativas de acesso</h1>
<div class="sub"><?= $total ?> registro(s). Cada abertura do app gera uma linha aqui.</div>

<form class="bar" method="get" action="events.php">
  <div class="fld"><label>Buscar</label><input type="text" name="q" value="<?= otm_e($q) ?>" placeholder="prefixo, aparelho, IP…"></div>
  <div class="fld"><label>Resultado</label>
    <select name="result">
      <?php foreach (['' => 'todos', 'ok' => 'ok', 'expired' => 'expirada', 'revoked' => 'revogada',
                      'device_limit' => 'limite de aparelhos', 'use_limit' => 'limite de usos',
                      'blocked' => 'aparelho bloqueado', 'unknown' => 'desconhecida'] as $v => $l): ?>
        <option value="<?= otm_e($v) ?>"<?= $result === $v ? ' selected' : '' ?>><?= otm_e($l) ?></option>
      <?php endforeach; ?>
    </select>
  </div>
  <div class="fld"><label>&nbsp;</label><button class="btn" type="submit">filtrar</button></div>
  <div class="fld"><label>&nbsp;</label><a class="btn ghost" href="events.php">limpar filtros</a></div>
</form>

<?= otm_flash() ?>

<?php if ($auth->canWrite()): ?>
  <form class="bar" method="post" action="events.php">
    <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
    <div class="fld narrow"><label>Apagar mais antigas que</label>
      <input type="number" name="days" min="1" value="30"></div>
    <div class="fld"><label>&nbsp;</label>
      <button class="btn ghost" type="submit" name="act" value="clear_days">apagar antigas</button></div>
    <div class="fld"><label>&nbsp;</label>
      <button class="btn danger" type="submit" name="act" value="clear_all"
              onclick="return confirm('Apagar TODO o histórico de tentativas? Não dá para desfazer.')">apagar tudo</button></div>
  </form>
<?php endif; ?>

<table class="grid">
  <tr><th>Quando</th><th>Chave</th><th>Nome</th><th>Resultado</th><th>Aparelho</th><th>Modelo</th><th>App</th><th>IP</th><th>Detalhe</th><?php if ($auth->canWrite()): ?><th></th><?php endif; ?></tr>
  <?php if (!$rows): ?>
    <tr><td class="empty" colspan="<?= $auth->canWrite() ? 10 : 9 ?>">Nenhuma tentativa registrada.</td></tr>
  <?php else: foreach ($rows as $e): ?>
    <tr>
      <td class="nowrap mono"><?= otm_e(otm_fmt_dt($e['created_at'])) ?></td>
      <td class="mono"><?= $e['key_id'] ? '<a href="key_view.php?id=' . (int)$e['key_id'] . '">' . otm_e((string)$e['key_prefix']) . '</a>' : otm_e((string)$e['key_prefix']) ?></td>
      <td><?= otm_e((string)($e['label'] ?: '—')) ?></td>
      <td><span class="mono"><?= otm_e((string)$e['result']) ?></span></td>
      <td class="mono"><?= otm_e((string)($e['device_id'] ?: '—')) ?></td>
      <td><?= otm_e((string)($e['model'] ?: '—')) ?></td>
      <td class="muted"><?= otm_e((string)($e['app_version'] ?: '—')) ?></td>
      <td class="mono"><?= otm_e((string)$e['ip']) ?></td>
      <td class="muted"><?= otm_e((string)$e['detail']) ?></td>
      <?php if ($auth->canWrite()): ?>
        <td class="nowrap"><?= otm_action_button('events.php', ['id' => $e['id'], 'act' => 'rm'], 'apagar',
                                                'btn danger sm', 'Apagar esta tentativa?') ?></td>
      <?php endif; ?>
    </tr>
  <?php endforeach; endif; ?>
</table>

<?php if ($pages > 1): ?>
  <div class="pager">
    <?php for ($i = 1; $i <= min($pages, 30); $i++): ?>
      <?php if ($i === $page): ?><span class="cur"><?= $i ?></span>
      <?php else: ?><a href="events.php?<?= otm_e(http_build_query(['q'=>$q,'result'=>$result,'p'=>$i])) ?>"><?= $i ?></a><?php endif; ?>
    <?php endfor; ?>
    <span class="muted">página <?= $page ?> de <?= $pages ?></span>
  </div>
<?php endif; ?>

<?php otm_layout_end(); ?>
