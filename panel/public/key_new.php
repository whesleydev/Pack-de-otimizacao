<?php
// =============================================================================
//  key_new.php - Cria uma chave nova, definindo duração e limites.
//
//  A chave em texto aparece UMA vez nesta tela. Depois disso só existe o hash
//  no banco — não há como recuperar. Se o cliente perder, gere outra.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();
otm_require_write();

$plans = $db->all('SELECT * FROM otm_plans WHERE is_active = 1 ORDER BY sort_order');
$erro  = '';
$criada = null;

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    $mode = otm_post('mode', 'custom');

    if ($mode === 'plan') {
        $pid = otm_int($_POST['plan_id'] ?? 0);
        $p   = $db->one('SELECT * FROM otm_plans WHERE id = ?', [$pid]);
        if (!$p) {
            $erro = 'Escolha um plano válido.';
        } else {
            $in = [
                'label'         => otm_post('label'),
                'owner_contact' => otm_post('owner_contact'),
                'note'          => otm_post('note'),
                'plan_id'       => $pid,
                'duration_days' => $p['duration_days'] === null ? null : (int)$p['duration_days'],
                'max_devices'   => (int)$p['max_devices'],
                'max_uses'      => (int)$p['max_uses'],
                'created_by'    => (string)$me['username'],
            ];
        }
    } else {
        $daysRaw = otm_post('duration_days');
        $in = [
            'label'         => otm_post('label'),
            'owner_contact' => otm_post('owner_contact'),
            'note'          => otm_post('note'),
            'plan_id'       => otm_int($_POST['plan_id'] ?? 0) ?: null,
            'duration_days' => in_array($daysRaw, ['', 'vitalicio', 'never'], true) ? null : max(0, (int)$daysRaw),
            'max_devices'   => max(0, otm_int($_POST['max_devices'] ?? 1)),
            'max_uses'      => max(0, otm_int($_POST['max_uses'] ?? 0)),
            'created_by'    => (string)$me['username'],
        ];
    }

    if ($erro === '') {
        $criada = $keys->create($in);
        $audit->log('key.create', 'key', (string)$criada['id'],
            'criou ' . $criada['row']['key_prefix'] . ' (' . $in['label'] . ')', $me);
    }
}

$title = 'Nova chave';
require __DIR__ . '/../src/layout.php';
?>

<h1>Nova chave</h1>
<div class="sub">A chave é mostrada uma única vez. Copie e entregue ao cliente.</div>

<?= otm_flash() ?>
<?php if ($erro !== ''): ?><?= otm_msg('err', otm_e($erro)) ?><?php endif; ?>

<?php if ($criada): $r = $criada['row']; ?>
  <div class="keybox">
    <div class="k"><?= otm_e($criada['key']) ?></div>
    <div class="w">⚠ Anote agora. Esta chave não é mostrada de novo — no banco fica só o hash.</div>
  </div>
  <table class="grid" style="max-width:760px">
    <tr><th>ID</th><th>Vigência</th><th>Aparelhos</th><th>Usos</th><th>Nome</th></tr>
    <tr>
      <td class="mono"><?= (int)$criada['id'] ?></td>
      <td><?= $r['expires_at'] ? otm_e(otm_fmt_dt((string)$r['expires_at'])) : 'vitalícia' ?></td>
      <td><?= (int)$r['max_devices'] === 0 ? 'ilimitado' : (int)$r['max_devices'] ?></td>
      <td><?= (int)$r['max_uses'] === 0 ? 'ilimitado' : (int)$r['max_uses'] ?></td>
      <td><?= otm_e((string)$r['label']) ?></td>
    </tr>
  </table>
  <div class="actions" style="margin-top:16px">
    <a class="btn" href="keys.php">ver todas as chaves</a>
    <a class="btn ghost" href="key_new.php">criar outra</a>
    <a class="btn ghost" href="key_view.php?id=<?= (int)$criada['id'] ?>">abrir detalhe</a>
  </div>

<?php else: ?>

  <form class="frm" method="post" action="key_new.php">
    <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">

    <div class="row">
      <div class="fld">
        <label for="label">Nome / cliente</label>
        <input id="label" name="label" type="text" maxlength="120" placeholder="Ex.: João Silva" required>
      </div>
      <div class="fld">
        <label for="owner_contact">Contato</label>
        <input id="owner_contact" name="owner_contact" type="text" maxlength="160" placeholder="telefone ou e-mail">
      </div>
    </div>

    <div class="row">
      <div class="fld">
        <label for="mode">Como definir a vigência</label>
        <select id="mode" name="mode" onchange="otmMode()">
          <option value="custom">Personalizada (dias / aparelhos)</option>
          <option value="plan">A partir de um plano</option>
        </select>
      </div>
    </div>

    <div id="blkPlan" style="display:none">
      <div class="row">
        <div class="fld">
          <label for="plan_id_p">Plano</label>
          <select id="plan_id_p" name="plan_id">
            <?php foreach ($plans as $p): ?>
              <option value="<?= (int)$p['id'] ?>">
                <?= otm_e((string)$p['name']) ?> —
                <?= $p['duration_days'] === null ? 'vitalício' : (int)$p['duration_days'] . ' dias' ?>,
                <?= (int)$p['max_devices'] ?> aparelho(s)
              </option>
            <?php endforeach; ?>
          </select>
        </div>
      </div>
    </div>

    <div id="blkCustom">
      <div class="row">
        <div class="fld narrow">
          <label for="duration_days">Duração (dias)</label>
          <input id="duration_days" name="duration_days" type="text" value="30" placeholder="30 ou vitalicio">
          <span class="hint">use <b>vitalicio</b> para nunca expirar</span>
        </div>
        <div class="fld narrow">
          <label for="max_devices">Aparelhos</label>
          <input id="max_devices" name="max_devices" type="number" min="0" value="1">
          <span class="hint">0 = ilimitado</span>
        </div>
        <div class="fld narrow">
          <label for="max_uses">Limite de usos</label>
          <input id="max_uses" name="max_uses" type="number" min="0" value="0">
          <span class="hint">0 = ilimitado</span>
        </div>
      </div>
    </div>

    <div class="row">
      <div class="fld">
        <label for="note">Observação</label>
        <textarea id="note" name="note" maxlength="500" placeholder="anotação interna (não aparece para o cliente)"></textarea>
      </div>
    </div>

    <div class="actions">
      <button class="btn" type="submit">criar chave</button>
      <a class="btn ghost" href="keys.php">cancelar</a>
    </div>
  </form>

  <script>
  function otmMode() {
    var m = document.getElementById('mode').value;
    document.getElementById('blkPlan').style.display   = (m === 'plan') ? '' : 'none';
    document.getElementById('blkCustom').style.display = (m === 'plan') ? 'none' : '';
    // campos ocultos não devem bloquear o envio
    document.getElementById('duration_days').disabled = (m === 'plan');
  }
  otmMode();
  </script>

<?php endif; ?>

<?php otm_layout_end(); ?>
