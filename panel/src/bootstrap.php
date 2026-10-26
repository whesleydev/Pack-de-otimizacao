<?php
// =============================================================================
//  bootstrap.php - Ponto único de carregamento do painel.
//
//  Todo arquivo do painel (páginas, API, CLI) começa com:
//      require __DIR__ . '/caminho/para/bootstrap.php';
//
//  Aqui ficam: autoload das classes de src/, config, sessão, e o atalho do
//  banco (otm_db()). Nada de regra de negócio aqui — só ligação de peças.
// =============================================================================

declare(strict_types=1);

if (defined('OTM_PANEL_BOOTED')) return;
define('OTM_PANEL_BOOTED', true);

define('OTM_PANEL_ROOT', dirname(__DIR__));
define('OTM_PANEL_SRC', __DIR__);

// Versão exibida na barra de status (lê o VERSION da raiz do projeto).
$otm_ver = @file_get_contents(dirname(OTM_PANEL_ROOT) . '/VERSION');
define('OTM_PANEL_VERSION', $otm_ver !== false ? trim($otm_ver) : 'dev');

// --- fuso: tudo em UTC no banco, horário local só na tela --------------------
date_default_timezone_set('America/Sao_Paulo');

// --- autoload simples: src/Foo.php -> class Foo ---------------------------------
spl_autoload_register(static function (string $class): void {
    if (!str_starts_with($class, 'Otm')) return;
    $file = OTM_PANEL_SRC . '/' . $class . '.php';
    if (is_file($file)) require $file;
});

require_once OTM_PANEL_ROOT . '/config/config.php';

// Classes sem namespace, nomes curtos (estilo legado): Turso, Db, Auth…
require_once OTM_PANEL_SRC . '/OtmDb.php';
foreach (['Turso', 'Db', 'Helpers', 'Auth', 'Audit', 'Guard'] as $c) {
    $f = OTM_PANEL_SRC . '/' . $c . '.php';
    if (is_file($f)) require_once $f;
}

/**
 * Conexão única por requisição.
 *
 * Ordem: se OTM_LOCAL_DB estiver definido (ou o Turso não estiver configurado),
 * usa o SQLite local; senão usa o Turso. Assim o painel roda igual nos dois —
 * o código acima não sabe a diferença.
 */
function otm_db(): OtmDb
{
    static $db = null;
    if ($db !== null) return $db;

    $local = otm_env('OTM_LOCAL_DB', '');
    if ($local !== '') return $db = Db::fromConfig();

    $cfg = otm_config('turso');
    $url = (string)($cfg['url'] ?? otm_env('TURSO_DATABASE_URL', ''));
    $tok = (string)($cfg['token'] ?? otm_env('TURSO_AUTH_TOKEN', ''));
    if ($url !== '' && $tok !== '' && !str_contains($url, 'SEU-BANCO')) {
        return $db = Turso::fromConfig();
    }

    // Sem Turso configurado: cai no arquivo local (útil para testar).
    return $db = Db::fromConfig();
}
