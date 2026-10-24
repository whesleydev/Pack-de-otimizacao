<?php
// =============================================================================
//  admins.php - Gerencia quem entra no painel (só o dono mexe).
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    otm_require_write();
    if (!$auth->isOwner()) {
        otm_redirect('admins.php?erro=' . urlencode('Só o dono (owner) pode mexer em administradores.'));
    }
    $act = otm_post('act');
    $id  = otm_int($_POST['id'] ?? 0);

    if ($act === 'create') {
        $user = strtolower(otm_post('username'));
        $pass = (string)($_POST['password'] ?? '');
        $role = in_array(otm_post('role'), ['owner', 'admin', 'viewer'], true) ? otm_post('role') : 'admin';
        if ($user === '' || strlen($pass) < 6) {
            otm_redirect('admins.php?erro=' . urlencode('Usuário vazio ou senha menor que 6 caracteres.'));
        }
        if ($db->one('SELECT id FROM otm_admins WHERE username = ?', [$user])) {
            otm_redirect('admins.php?erro=' . urlencode('Já existe um administrador com esse usuário.'));
        }
        $newId = $auth->upsert($user, $pass, $role, otm_post('name'), otm_post('email'));
        $audit->log('admin.create', 'admin', (string)$newId, "criou admin $user ($role)", $me);
        otm_redirect('admins.php?ok=' . urlencode('Administrador criado.'));
    }

    if ($act === 'role' && $id > 0) {
        $role = in_array(otm_post('role'), ['owner', 'admin', 'viewer'], true) ? otm_post('role') : 'admin';
        $db->run('UPDATE otm_admins SET role = ?, updated_at = ? WHERE id = ?', [$role, otm_now(), $id]);
        $audit->log('admin.role', 'admin', (string)$id, "papel -> $role", $me);
        otm_redirect('admins.php?ok=' . urlencode('Papel atualizado.'));
    }

    if ($act === 'passwd' && $id > 0) {
        $pass = (string)($_POST['password'] ?? '');
        if (strlen($pass) < 6) otm_redirect('admins.php?erro=' . urlencode('Senha menor que 6 caracteres.'));
        $db->run('UPDATE otm_admins SET password_hash = ?, updated_at = ? WHERE id = ?',
                 [password_hash($pass, PASSWORD_DEFAULT), otm_now(), $id]);
        $db->run('DELETE FROM otm_admin_sessions WHERE admin_id = ?', [$id]);
        $audit->log('admin.passwd', 'admin', (string)$id, 'trocou a senha', $me);
        otm_redirect('admins.php?ok=' . urlencode('Senha trocada (sessões encerradas).'));
    }

    if ($act === 'toggle' && $id > 0) {
        if ($id === (int)$me['id']) {
            otm_redirect('admins.php?erro=' . urlencode('Você não pode desativar a si mesmo.'));
        }
        $db->run('UPDATE otm_admins SET is_active = 1 - is_active, updated_at = ? WHERE id = ?', [otm_now(), $id]);
        $audit->log('admin.toggle', 'admin', (string)$id, 'alternou acesso', $me);
        otm_redirect('admins.php?ok=' . urlencode('Administrador atualizado.'));
    }

    if ($act === 'kill_sessions' && $id > 0) {
        $db->run('DELETE FROM otm_admin_sessions WHERE admin_id = ?', [$id]);
        $audit->log('admin.sessions.kill', 'admin', (string)$id, 'encerrou sessões', $me);
        otm_redirect('admins.php?ok=' . urlencode('Sessões encerradas.'));
    }

    if ($act === 'rm' && $id > 0) {
        if ($id === (int)$me['id']) {
            otm_redirect('admins.php?erro=' . urlencode('Você não pode apagar a si mesmo.'));
        }
        $alvo = $db->one('SELECT * FROM otm_admins WHERE id = ?', [$id]);
        if (!$alvo) {
            otm_redirect('admins.php?erro=' . urlencode('Administrador não encontrado.'));
        }
        // Nunca deixar o painel sem dono: se for o último owner ativo, barra.
        if ((string)$alvo['role'] === 'owner') {
            $outros = (int)$db->scalar(
                'SELECT COUNT(*) FROM otm_admins WHERE role = ? AND is_active = 1 AND id <> ?',
                ['owner', $id]
            );
            if ($outros === 0) {
                otm_redirect('admins.php?erro=' . urlencode('Este é o último dono. Promova outro antes de apagar.'));
            }
        }
        $db->run('DELETE FROM otm_admin_sessions WHERE admin_id = ?', [$id]);
        $db->run('DELETE FROM otm_admins WHERE id = ?', [$id]);
        $audit->log('admin.delete', 'admin', (string)$id, 'apagou admin ' . $alvo['username'], $me);
        otm_redirect('admins.php?ok=' . urlencode('Administrador apagado.'));
    }
}

$admins = $db->all('SELECT * FROM otm_admins ORDER BY id');
$sessions = [];
foreach ($db->all('SELECT admin_id, COUNT(*) n FROM otm_admin_sessions WHERE expires_at > ? GROUP BY admin_id', [otm_now()]) as $r) {
    $sessions[(int)$r['admin_id']] = (int)$r['n'];
}

$title = 'Administradores';
require __DIR__ . '/../src/layout.php';
?>

<h1>Administradores</h1>
<div class="sub">Quem pode entrar neste painel. O cliente final continua usando só a chave, no app.</div>

<?= otm_flash() ?>

<?php if (!$auth->isOwner()): ?><?= otm_msg('warn', 'Só o dono (owner) pode criar ou alterar administradores.') ?><?php endif; ?>

<table class="grid">
  <tr><th>ID</th><th>Usuário</th><th>Nome</th><th>E-mail</th><th>Papel</th><th>Sessões</th><th>Último acesso</th><th>Situação</th><th>Ações</th></tr>
  <?php foreach ($admins as $a): ?>
    <tr>
      <td class="num"><?= (int)$a['id'] ?></td>
      <td class="mono"><?= otm_e((string)$a['username']) ?><?= (int)$a['id'] === (int)$me['id'] ? ' <span class="muted">(você)</span>' : '' ?></td>
      <td><?= otm_e((string)$a['name']) ?></td>
      <td class="muted"><?= otm_e((string)$a['email']) ?></td>
      <td><span class="tag <?= otm_e((string)$a['role']) ?>"><?= otm_e((string)$a['role']) ?></span></td>
      <td class="num"><?= (int)($sessions[(int)$a['id']] ?? 0) ?></td>
      <td class="nowrap muted"><?= otm_e(otm_fmt_dt($a['last_login_at'])) ?></td>
      <td><span class="tag <?= (int)$a['is_active'] === 1 ? 'active' : 'viewer' ?>"><?= (int)$a['is_active'] === 1 ? 'ativo' : 'inativo' ?></span></td>
      <td class="nowrap">
        <?php if ($auth->isOwner()): ?>
          <div class="actions">
            <?= otm_action_button('admins.php', ['id' => $a['id'], 'act' => 'toggle'], (int)$a['is_active'] === 1 ? 'desativar' : 'ativar') ?>
            <?= otm_action_button('admins.php', ['id' => $a['id'], 'act' => 'kill_sessions'], 'derrubar sessões') ?>
            <?php if ((int)$a['id'] !== (int)$me['id']): ?>
              <?= otm_action_button('admins.php', ['id' => $a['id'], 'act' => 'rm'], 'apagar',
                                    'btn danger sm', 'Apagar o admin ' . $a['username'] . '? Não dá para desfazer.') ?>
            <?php endif; ?>
          </div>
        <?php endif; ?>
      </td>
    </tr>
  <?php endforeach; ?>
</table>

<?php if ($auth->isOwner()): ?>
<div class="cols" style="margin-top:22px">
  <div class="c1">
    <h2>Novo administrador</h2>
    <form class="frm" method="post" action="admins.php">
      <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
      <input type="hidden" name="act" value="create">
      <div class="row">
        <div class="fld"><label>Usuário</label><input type="text" name="username" required autocomplete="off"></div>
        <div class="fld"><label>Senha</label><input type="password" name="password" required autocomplete="new-password"><span class="hint">mínimo 6 caracteres</span></div>
      </div>
      <div class="row">
        <div class="fld"><label>Nome</label><input type="text" name="name"></div>
        <div class="fld"><label>E-mail</label><input type="email" name="email"></div>
        <div class="fld narrow"><label>Papel</label>
          <select name="role">
            <option value="admin">admin</option>
            <option value="viewer">viewer (só leitura)</option>
            <option value="owner">owner</option>
          </select>
        </div>
      </div>
      <div class="actions"><button class="btn" type="submit">criar</button></div>
    </form>
  </div>

  <div class="c2">
    <h2>Trocar senha</h2>
    <form class="frm" method="post" action="admins.php">
      <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
      <input type="hidden" name="act" value="passwd">
      <div class="row">
        <div class="fld"><label>Administrador</label>
          <select name="id">
            <?php foreach ($admins as $a): ?>
              <option value="<?= (int)$a['id'] ?>"><?= otm_e((string)$a['username']) ?></option>
            <?php endforeach; ?>
          </select>
        </div>
        <div class="fld"><label>Nova senha</label><input type="password" name="password" required autocomplete="new-password"></div>
      </div>
      <div class="actions"><button class="btn" type="submit">trocar senha</button></div>
    </form>
  </div>
</div>
<?php endif; ?>

<?php otm_layout_end(); ?>
