<?php
// =============================================================================
//  key_edit.php - Edita os campos de uma chave já criada.
//
//  Não dá para mudar o hash (a chave em texto não existe mais) nem a data de
//  criação. Duração tem tela própria no detalhe, porque recalcula a expiração.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();
otm_require_write();

$id = otm_int($_GET['id'] ?? $_POST['id'] ?? 0);
$k  = $id ? $keys->find($id) : null;
if (!$k) { http_response_code(404); exit('Chave não encontrada.'); }

$plans = $db->all('SELECT id, name FROM otm_plans ORDER BY sort_order');

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    $keys->update($id, [
        'label'         => otm_post('label'),
        'owner_contact' => otm_post('owner_contact'),
        'note'          => otm_post('note'),
        'plan_id'       => otm_int($_POST['plan_id'] ?? 0) ?: null,
        'max_devices'   => max(0, otm_int($_POST['max_devices'] ?? 1)),
        'max_uses'      => max(0, otm_int($_POST['max_uses'] ?? 0)),
    ]);
    $audit->log('key.update', 'key', (string)$id, 'editou dados de ' . $k['key_prefix'], $me);
    otm_redirect("key_view.php?id=$id&ok=" . urlencode('Chave atualizada.'));
}

$title = 'Editar ' . $k['key_prefix'];
require __DIR__ . '/../src/layout.php';
?>

<h1>Editar chave <span class="mono"><?= otm_e((string)$k['key_prefix']) ?></span></h1>
<div class="sub">Para mudar a vigência, use a tela <a href="key_view.php?id=<?= $id ?>">detalhe da chave</a>.</div>

<form class="frm" method="post" action="key_edit.php">
  <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
  <input type="hidden" name="id" value="<?= $id ?>">

  <div class="row">
    <div class="fld">
      <label for="label">Nome / cliente</label>
      <input id="label" name="label" type="text" maxlength="120" value="<?= otm_e((string)$k['label']) ?>">
    </div>
    <div class="fld">
      <label for="owner_contact">Contato</label>
      <input id="owner_contact" name="owner_contact" type="text" maxlength="160" value="<?= otm_e((string)$k['owner_contact']) ?>">
    </div>
  </div>

  <div class="row">
    <div class="fld">
      <label for="plan_id">Plano</label>
      <select id="plan_id" name="plan_id">
        <option value="0">— sem plano —</option>
        <?php foreach ($plans as $p): ?>
          <option value="<?= (int)$p['id'] ?>"<?= (int)$k['plan_id'] === (int)$p['id'] ? ' selected' : '' ?>>
            <?= otm_e((string)$p['name']) ?>
          </option>
        <?php endforeach; ?>
      </select>
    </div>
    <div class="fld narrow">
      <label for="max_devices">Aparelhos</label>
      <input id="max_devices" name="max_devices" type="number" min="0" value="<?= (int)$k['max_devices'] ?>">
      <span class="hint">0 = ilimitado</span>
    </div>
    <div class="fld narrow">
      <label for="max_uses">Limite de usos</label>
      <input id="max_uses" name="max_uses" type="number" min="0" value="<?= (int)$k['max_uses'] ?>">
      <span class="hint">0 = ilimitado</span>
    </div>
  </div>

  <div class="row">
    <div class="fld">
      <label for="note">Observação</label>
      <textarea id="note" name="note" maxlength="500"><?= otm_e((string)$k['note']) ?></textarea>
    </div>
  </div>

  <div class="actions">
    <button class="btn" type="submit">salvar</button>
    <a class="btn ghost" href="key_view.php?id=<?= $id ?>">cancelar</a>
  </div>
</form>

<?php otm_layout_end(); ?>
