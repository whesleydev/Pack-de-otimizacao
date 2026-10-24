<?php
// =============================================================================
//  key_view.php - Detalhe de uma chave: dados, aparelhos e histórico.
//
//  É onde o suporte responde "por que a chave do cliente não entra?".
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

$id = otm_int($_GET['id'] ?? 0);
$k  = $id ? $keys->find($id) : null;
if (!$k) {
    http_response_code(404);
    exit('Chave não encontrada.');
}

// --- ações (POST) -------------------------------------------------------------
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    otm_require_write();
    $act = otm_post('act');
    switch ($act) {
        case 'revoke':
            $keys->revoke($id, otm_post('reason'));
            $audit->log('key.revoke', 'key', (string)$id, 'revogou ' . $k['key_prefix'], $me);
            otm_redirect("key_view.php?id=$id&ok=" . urlencode('Chave revogada.'));
        case 'restore':
            $keys->restore($id);
            $audit->log('key.restore', 'key', (string)$id, 'reativou ' . $k['key_prefix'], $me);
            otm_redirect("key_view.php?id=$id&ok=" . urlencode('Chave reativada.'));
        case 'extend':
            $d = otm_int($_POST['days'] ?? 30);
            $keys->extend($id, $d);
            $audit->log('key.extend', 'key', (string)$id, "+$d dia(s)", $me);
            otm_redirect("key_view.php?id=$id&ok=" . urlencode("Estendida em $d dia(s)."));
        case 'duration':
            $raw  = otm_post('duration_days');
            $days = in_array($raw, ['', 'vitalicio', 'never'], true) ? null : max(0, (int)$raw);
            $keys->setDuration($id, $days);
            $audit->log('key.duration', 'key', (string)$id, $days === null ? 'vitalícia' : "$days dias", $me);
            otm_redirect("key_view.php?id=$id&ok=" . urlencode('Duração atualizada.'));
        case 'forget_device':
            $keys->forgetDevice($id, otm_post('device_id'));
            $audit->log('key.device.forget', 'key', (string)$id, 'liberou aparelho ' . otm_post('device_id'), $me);
            otm_redirect("key_view.php?id=$id&ok=" . urlencode('Aparelho liberado (a vaga ficou livre).'));
        case 'block_device':
            $keys->blockDevice($id, otm_post('device_id'), true);
            $audit->log('key.device.block', 'key', (string)$id, 'bloqueou aparelho ' . otm_post('device_id'), $me);
            otm_redirect("key_view.php?id=$id&ok=" . urlencode('Aparelho bloqueado.'));
        case 'unblock_device':
            $keys->blockDevice($id, otm_post('device_id'), false);
            $audit->log('key.device.unblock', 'key', (string)$id, 'desbloqueou aparelho ' . otm_post('device_id'), $me);
            otm_redirect("key_view.php?id=$id&ok=" . urlencode('Aparelho desbloqueado.'));
        case 'rm':
            $keys->delete($id);
            $audit->log('key.delete', 'key', (string)$id, 'apagou ' . $k['key_prefix'], $me);
            otm_redirect('keys.php?ok=' . urlencode('Chave apagada.'));
    }
}

$devices = $keys->devices($id);
$events  = $keys->events($id, 40);
$k       = $keys->find($id); // recarrega após possíveis mudanças

$title = 'Chave ' . $k['key_prefix'];
require __DIR__ . '/../src/layout.php';
?>

<h1>Chave <span class="mono"><?= otm_e((string)$k['key_prefix']) ?></span> <?= otm_status_tag((string)$k['status']) ?></h1>
<div class="sub"><?= otm_e((string)($k['label'] ?: 'sem nome')) ?> · criada em <?= otm_e(otm_fmt_dt($k['created_at'])) ?></div>

<?= otm_flash() ?>

<?php $plain = $keys->plaintext($k); ?>
<h2>Chave para copiar</h2>
<?= otm_keybox($plain, (string)$k['key_prefix']) ?>

<div class="actions" style="margin-bottom:16px">
  <a class="btn ghost" href="keys.php">← voltar à lista</a>
  <?php if ($auth->canWrite()): ?>
    <a class="btn" href="key_edit.php?id=<?= $id ?>">editar</a>
    <?php if ((string)$k['status'] === 'revoked'): ?>
      <?= otm_action_button('key_view.php', ['id' => $id, 'act' => 'restore'], 'reativar') ?>
    <?php else: ?>
      <?= otm_action_button('key_view.php', ['id' => $id, 'act' => 'revoke'], 'revogar',
                            'btn danger', 'Revogar esta chave? O cliente perde o acesso.') ?>
    <?php endif; ?>
  <?php endif; ?>
</div>

<div class="cols">
  <div class="c1">
    <h2>Dados</h2>
    <dl class="dl">
      <dt>ID</dt><dd class="mono"><?= (int)$k['id'] ?></dd>
      <dt>Prefixo</dt><dd class="mono"><?= otm_e((string)$k['key_prefix']) ?></dd>
      <dt>Nome</dt><dd><?= otm_e((string)($k['label'] ?: '—')) ?></dd>
      <dt>Plano</dt><dd><?= otm_e((string)($k['plan_name'] ?: '—')) ?></dd>
      <dt>Situação</dt><dd><?= otm_status_tag((string)$k['status']) ?></dd>
      <dt>Criada em</dt><dd><?= otm_e(otm_fmt_dt($k['created_at'])) ?></dd>
      <dt>Primeiro uso</dt><dd><?= otm_e(otm_fmt_dt($k['activated_at'])) ?></dd>
      <dt>Expira em</dt>
      <dd><?= $k['expires_at'] ? otm_e(otm_fmt_dt((string)$k['expires_at'])) . ' <span class="muted">(' . (int)$k['days_left'] . ' dia[s])</span>' : '<span class="muted">nunca (vitalícia)</span>' ?></dd>
      <dt>Aparelhos</dt><dd><?= count($devices) ?> de <?= (int)$k['max_devices'] === 0 ? '∞' : (int)$k['max_devices'] ?></dd>
      <dt>Usos</dt><dd><?= (int)$k['uses_count'] ?><?= (int)$k['max_uses'] > 0 ? ' de ' . (int)$k['max_uses'] : ' <span class="muted">(ilimitado)</span>' ?></dd>
      <dt>Último uso</dt><dd><?= otm_e(otm_fmt_dt($k['last_used_at'])) ?></dd>
      <dt>Último IP</dt><dd class="mono"><?= otm_e((string)($k['last_seen_ip'] ?: '—')) ?></dd>
      <?php if (!empty($k['revoked_at'])): ?>
        <dt>Revogada em</dt><dd><?= otm_e(otm_fmt_dt($k['revoked_at'])) ?></dd>
        <dt>Motivo</dt><dd><?= otm_e((string)($k['revoked_reason'] ?: '—')) ?></dd>
      <?php endif; ?>
      <?php if (!empty($k['note'])): ?>
        <dt>Observação</dt><dd><?= nl2br(otm_e((string)$k['note'])) ?></dd>
      <?php endif; ?>
    </dl>

    <?php if ($auth->canWrite()): ?>
      <h2>Mudar duração</h2>
      <form class="frm" method="post" action="key_view.php?id=<?= $id ?>" style="padding:14px">
        <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
        <input type="hidden" name="act" value="duration">
        <div class="row">
          <div class="fld narrow">
            <label>Dias a partir de agora</label>
            <input type="text" name="duration_days"
                   value="<?= $k['duration_days'] === null ? 'vitalicio' : (int)$k['duration_days'] ?>">
          </div>
          <div class="fld narrow"><label>&nbsp;</label><button class="btn" type="submit">salvar</button></div>
        </div>
        <div class="hint">Recalcula a expiração a partir de agora. Use <b>vitalicio</b> para nunca expirar.</div>
      </form>

      <h2>Estender</h2>
      <form class="frm" method="post" action="key_view.php?id=<?= $id ?>" style="padding:14px">
        <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
        <input type="hidden" name="act" value="extend">
        <div class="row">
          <div class="fld narrow">
            <label>Adicionar dias</label>
            <input type="number" name="days" min="1" value="30">
          </div>
          <div class="fld narrow"><label>&nbsp;</label><button class="btn" type="submit">estender</button></div>
        </div>
        <div class="hint">Soma os dias em cima da data atual de expiração (não perde o tempo restante).</div>
      </form>
    <?php endif; ?>
  </div>

  <div class="c2">
    <h2>Aparelhos</h2>
    <table class="grid">
      <tr><th>Aparelho</th><th>Modelo</th><th>Visto</th><th></th></tr>
      <?php if (!$devices): ?>
        <tr><td class="empty" colspan="4">Nenhum aparelho usou esta chave ainda.</td></tr>
      <?php else: foreach ($devices as $d): ?>
        <tr>
          <td class="mono"><?= otm_e((string)$d['device_id']) ?>
              <?php if (!empty($d['blocked_at'])): ?><br><span class="tag revoked">bloqueado</span><?php endif; ?></td>
          <td><?= otm_e((string)($d['model'] ?: '—')) ?>
              <?php if (!empty($d['android_ver'])): ?><br><span class="muted">Android <?= otm_e((string)$d['android_ver']) ?></span><?php endif; ?></td>
          <td class="nowrap muted"><?= otm_e(otm_fmt_dt($d['last_seen_at'])) ?></td>
          <td class="nowrap">
            <?php if ($auth->canWrite()): ?>
              <?= otm_action_button('key_view.php', ['id' => $id, 'act' => 'forget_device', 'device_id' => $d['device_id']],
                                    'liberar', 'btn ghost sm', 'Liberar a vaga deste aparelho?') ?>
              <?php if (empty($d['blocked_at'])): ?>
                <?= otm_action_button('key_view.php', ['id' => $id, 'act' => 'block_device', 'device_id' => $d['device_id']],
                                      'bloquear', 'btn danger sm', 'Bloquear este aparelho?') ?>
              <?php else: ?>
                <?= otm_action_button('key_view.php', ['id' => $id, 'act' => 'unblock_device', 'device_id' => $d['device_id']],
                                      'desbloquear', 'btn ghost sm') ?>
              <?php endif; ?>
            <?php endif; ?>
          </td>
        </tr>
      <?php endforeach; endif; ?>
    </table>

    <h2>Histórico de tentativas</h2>
    <table class="grid">
      <tr><th>Quando</th><th>Resultado</th><th>Aparelho</th></tr>
      <?php if (!$events): ?>
        <tr><td class="empty" colspan="3">Sem tentativas registradas.</td></tr>
      <?php else: foreach ($events as $e): ?>
        <tr>
          <td class="nowrap mono"><?= otm_e(otm_fmt_dt($e['created_at'])) ?></td>
          <td><span class="mono"><?= otm_e((string)$e['result']) ?></span>
              <?php if (!empty($e['detail'])): ?><br><span class="muted"><?= otm_e((string)$e['detail']) ?></span><?php endif; ?></td>
          <td class="mono"><?= otm_e((string)($e['device_id'] ?: '—')) ?></td>
        </tr>
      <?php endforeach; endif; ?>
    </table>

    <?php if ($auth->canWrite()): ?>
      <hr class="soft">
      <?= otm_action_button('key_view.php', ['id' => $id, 'act' => 'rm'], 'apagar chave',
                            'btn danger', 'Apagar de vez? Esta ação não pode ser desfeita.') ?>
    <?php endif; ?>
  </div>
</div>

<?php otm_layout_end(); ?>
