<?php
// =============================================================================
//  plans.php - CRUD dos planos (presets de duração e limites).
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    otm_require_write();
    $act = otm_post('act');
    $id  = otm_int($_POST['id'] ?? 0);

    $days = static function (string $raw): ?int {
        return in_array($raw, ['', 'vitalicio', 'never'], true) ? null : max(0, (int)$raw);
    };

    if ($act === 'create' || $act === 'update') {
        $slug = strtolower(preg_replace('/[^a-z0-9]+/i', '-', otm_post('name')) ?? '');
        $slug = trim((string)$slug, '-');
        if ($slug === '') $slug = 'plano-' . substr(bin2hex(random_bytes(3)), 0, 5);
        $data = [
            otm_str(otm_post('name'), 80),
            otm_str(otm_post('description'), 200),
            $days(otm_post('duration_days')),
            max(0, otm_int($_POST['max_devices'] ?? 1)),
            max(0, otm_int($_POST['max_uses'] ?? 0)),
            max(0, otm_int($_POST['price_cents'] ?? 0)),
            otm_int($_POST['is_active'] ?? 0) ? 1 : 0,
            otm_int($_POST['sort_order'] ?? 0),
        ];
        if ($act === 'create') {
            $newId = $db->insert(
                'INSERT INTO otm_plans (name, description, duration_days, max_devices, max_uses, price_cents, is_active, sort_order, slug, created_at)
                 VALUES (?,?,?,?,?,?,?,?,?,?)',
                [...$data, $slug, otm_now()]
            );
            $audit->log('plan.create', 'plan', (string)$newId, 'criou plano ' . $data[0], $me);
            otm_redirect('plans.php?ok=' . urlencode('Plano criado.'));
        }
        $db->run('UPDATE otm_plans SET name=?, description=?, duration_days=?, max_devices=?, max_uses=?, price_cents=?, is_active=?, sort_order=?, updated_at=? WHERE id=?',
                 [...$data, otm_now(), $id]);
        $audit->log('plan.update', 'plan', (string)$id, 'editou plano ' . $data[0], $me);
        otm_redirect('plans.php?ok=' . urlencode('Plano atualizado.'));
    }

    if ($act === 'toggle' && $id > 0) {
        $db->run('UPDATE otm_plans SET is_active = 1 - is_active, updated_at = ? WHERE id = ?', [otm_now(), $id]);
        $audit->log('plan.toggle', 'plan', (string)$id, 'alternou plano', $me);
        otm_redirect('plans.php?ok=' . urlencode('Plano atualizado.'));
    }
    if ($act === 'rm' && $id > 0) {
        $used = (int)$db->scalar('SELECT COUNT(*) FROM otm_keys WHERE plan_id = ?', [$id]);
        if ($used > 0) {
            otm_redirect('plans.php?erro=' . urlencode("Plano em uso por $used chave(s). Desative em vez de apagar."));
        }
        $db->run('DELETE FROM otm_plans WHERE id = ?', [$id]);
        $audit->log('plan.delete', 'plan', (string)$id, 'apagou plano', $me);
        otm_redirect('plans.php?ok=' . urlencode('Plano apagado.'));
    }
}

$editId = otm_int($_GET['edit'] ?? 0);
$edit   = $editId ? $db->one('SELECT * FROM otm_plans WHERE id = ?', [$editId]) : null;
$plans  = $db->all(
    'SELECT p.*, (SELECT COUNT(*) FROM otm_keys k WHERE k.plan_id = p.id) AS used
       FROM otm_plans p ORDER BY p.sort_order, p.id'
);

$title = 'Planos';
require __DIR__ . '/../src/layout.php';
?>

<h1>Planos</h1>
<div class="sub">Modelos prontos para criar chaves rapidamente. Mudar um plano não altera chaves já criadas.</div>

<?= otm_flash() ?>

<table class="grid">
  <tr><th>Ordem</th><th>Plano</th><th>Duração</th><th>Aparelhos</th><th>Usos</th><th>Preço</th><th>Chaves</th><th>Situação</th><th>Ações</th></tr>
  <?php foreach ($plans as $p): ?>
    <tr>
      <td class="num"><?= (int)$p['sort_order'] ?></td>
      <td><b><?= otm_e((string)$p['name']) ?></b><br><span class="muted mono"><?= otm_e((string)$p['slug']) ?></span></td>
      <td><?= $p['duration_days'] === null ? 'vitalício' : (int)$p['duration_days'] . ' dias' ?></td>
      <td class="num"><?= (int)$p['max_devices'] === 0 ? '∞' : (int)$p['max_devices'] ?></td>
      <td class="num"><?= (int)$p['max_uses'] === 0 ? '∞' : (int)$p['max_uses'] ?></td>
      <td class="num"><?= (int)$p['price_cents'] > 0 ? 'R$ ' . number_format((int)$p['price_cents'] / 100, 2, ',', '.') : '—' ?></td>
      <td class="num"><?= (int)$p['used'] ?></td>
      <td><span class="tag <?= (int)$p['is_active'] === 1 ? 'active' : 'viewer' ?>"><?= (int)$p['is_active'] === 1 ? 'ativo' : 'inativo' ?></span></td>
      <td class="nowrap">
        <?php if ($auth->canWrite()): ?>
          <div class="actions">
            <a class="btn ghost sm" href="plans.php?edit=<?= (int)$p['id'] ?>">editar</a>
            <?= otm_action_button('plans.php', ['id' => $p['id'], 'act' => 'toggle'], (int)$p['is_active'] === 1 ? 'desativar' : 'ativar') ?>
            <?= otm_action_button('plans.php', ['id' => $p['id'], 'act' => 'rm'], 'apagar', 'btn danger sm', 'Apagar o plano ' . $p['name'] . '?') ?>
          </div>
        <?php endif; ?>
      </td>
    </tr>
  <?php endforeach; ?>
</table>

<?php if ($auth->canWrite()): ?>
<h2><?= $edit ? 'Editar plano' : 'Novo plano' ?></h2>
<form class="frm" method="post" action="plans.php">
  <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
  <input type="hidden" name="act" value="<?= $edit ? 'update' : 'create' ?>">
  <?php if ($edit): ?><input type="hidden" name="id" value="<?= (int)$edit['id'] ?>"><?php endif; ?>

  <div class="row">
    <div class="fld"><label>Nome</label><input type="text" name="name" maxlength="80" required value="<?= otm_e((string)($edit['name'] ?? '')) ?>"></div>
    <div class="fld"><label>Descrição</label><input type="text" name="description" maxlength="200" value="<?= otm_e((string)($edit['description'] ?? '')) ?>"></div>
  </div>
  <div class="row">
    <div class="fld narrow"><label>Dias</label><input type="text" name="duration_days" value="<?= $edit ? ($edit['duration_days'] === null ? 'vitalicio' : (int)$edit['duration_days']) : '30' ?>"><span class="hint">ou <b>vitalicio</b></span></div>
    <div class="fld narrow"><label>Aparelhos</label><input type="number" name="max_devices" min="0" value="<?= (int)($edit['max_devices'] ?? 1) ?>"></div>
    <div class="fld narrow"><label>Usos</label><input type="number" name="max_uses" min="0" value="<?= (int)($edit['max_uses'] ?? 0) ?>"></div>
    <div class="fld narrow"><label>Preço (centavos)</label><input type="number" name="price_cents" min="0" value="<?= (int)($edit['price_cents'] ?? 0) ?>"></div>
    <div class="fld narrow"><label>Ordem</label><input type="number" name="sort_order" value="<?= (int)($edit['sort_order'] ?? 0) ?>"></div>
  </div>
  <div class="row">
    <div class="fld narrow">
      <label>Ativo</label>
      <select name="is_active">
        <option value="1"<?= (int)($edit['is_active'] ?? 1) === 1 ? ' selected' : '' ?>>sim</option>
        <option value="0"<?= (int)($edit['is_active'] ?? 1) === 0 ? ' selected' : '' ?>>não</option>
      </select>
    </div>
  </div>
  <div class="actions">
    <button class="btn" type="submit"><?= $edit ? 'salvar' : 'criar plano' ?></button>
    <?php if ($edit): ?><a class="btn ghost" href="plans.php">cancelar</a><?php endif; ?>
  </div>
</form>
<?php endif; ?>

<?php otm_layout_end(); ?>
