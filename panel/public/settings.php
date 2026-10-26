<?php
// =============================================================================
//  settings.php - Ajustes gerais e teste de conexão com o banco.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';
$me = otm_require_login();

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
    otm_require_write();
    $pares = [
        'brand_name' => otm_post('brand_name'),
    ];
    foreach ($pares as $k => $v) {
        $db->run('INSERT INTO otm_settings (key, value, updated_at) VALUES (?,?,?)
                  ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at',
                 [$k, $v, otm_now()]);
    }
    $audit->log('settings.update', 'setting', '', 'atualizou ajustes', $me);
    otm_redirect('settings.php?ok=' . urlencode('Ajustes salvos.'));
}

$cfg = [];
foreach ($db->all('SELECT key, value FROM otm_settings') as $r) $cfg[(string)$r['key']] = (string)$r['value'];

// teste de conexão
$ping = null;
$pingErr = '';
try { $ping = otm_db()->ping(); } catch (Throwable $e) { $pingErr = $e->getMessage(); }

$title = 'Ajustes';
require __DIR__ . '/../src/layout.php';
?>

<h1>Ajustes</h1>
<div class="sub">Informações da conexão com o banco e ajustes do painel.</div>

<?= otm_flash() ?>

<div class="cols">
  <div class="c1">
    <h2>Padrões</h2>
    <form class="frm" method="post" action="settings.php">
      <input type="hidden" name="_csrf" value="<?= otm_e($auth->csrf()) ?>">
      <div class="row">
        <div class="fld"><label>Nome da marca</label>
          <input type="text" name="brand_name" value="<?= otm_e($cfg['brand_name'] ?? '00deUdia Otimizações') ?>"></div>
      </div>
      <?php if ($auth->canWrite()): ?>
        <div class="actions"><button class="btn" type="submit">salvar</button></div>
      <?php endif; ?>
    </form>
  </div>

  <div class="c2">
    <h2>Banco de dados</h2>
    <table class="grid">
      <tr><th>Item</th><th>Valor</th></tr>
      <tr><td>Conexão</td>
          <td><?= $ping !== null ? '<span class="tag active">ok</span> SQLite ' . otm_e($ping) : '<span class="tag revoked">falhou</span>' ?></td></tr>
      <tr><td>Tabelas do domínio</td><td class="num"><?= count(array_filter(otm_db()->tables(), fn($t) => str_starts_with($t, 'otm_'))) ?></td></tr>
      <tr><td>Endpoint</td><td class="mono muted"><?= otm_e(preg_replace('~^libsql://~', 'https://', (string)(otm_config('turso')['url'] ?? ''))) ?></td></tr>
    </table>
    <?php if ($pingErr !== ''): ?><?= otm_msg('err', otm_e($pingErr)) ?><?php endif; ?>
    <p class="muted">O token do banco fica em <span class="mono">panel/config/turso.php</span> (fora do git). O app nunca fala direto com o banco: ele chama o endpoint do painel.</p>
  </div>
</div>

<?php otm_layout_end(); ?>
