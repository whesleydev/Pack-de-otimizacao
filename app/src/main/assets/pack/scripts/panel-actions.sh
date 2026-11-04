#!/bin/sh
# =============================================================================
#  panel-actions.sh - Regenera o catálogo do painel a partir de otm_actions().
#
#  A fonte única das ações é `web/lib.php` (função otm_actions()). O painel do
#  app precisa dos mesmos dados em dois lugares:
#    - app/src/main/assets/panel/actions.json  (lido pelo PackBridge no Kotlin)
#    - app/src/main/assets/panel/index.html     (a linha `const ACTIONS = {...}`)
#
#  Antes isso era copiado à mão e vivia saindo de sincronia. Este script lê a
#  fonte e reescreve os dois artefatos. Rode depois de mexer em otm_actions().
#
#  Uso:  sh scripts/panel-actions.sh
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
JSON="$ROOT/app/src/main/assets/panel/actions.json"
HTML="$ROOT/app/src/main/assets/panel/index.html"

command -v php >/dev/null 2>&1 || { echo "preciso do php no PATH" >&2; exit 1; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

cat > "$tmp" <<'PHP'
<?php
[$root, $json, $htmlPath] = array_slice($argv, 1);
require $root . '/web/lib.php';
$A = otm_actions();

$pretty = json_encode(array_values($A), JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE);
file_put_contents($json, $pretty . "\n");

$compact = json_encode($A, JSON_UNESCAPED_UNICODE);
$html = file_get_contents($htmlPath);
$line = 'const ACTIONS = ' . $compact . ';';
$novo = preg_replace('/^const ACTIONS = .*;$/m', $line, $html, 1, $n);
if ($n !== 1) { fwrite(STDERR, "nao achei a linha const ACTIONS no index.html\n"); exit(1); }
file_put_contents($htmlPath, $novo);
echo 'painel: ', count($A), " acoes (actions.json + const ACTIONS)\n";
PHP

php "$tmp" "$ROOT" "$JSON" "$HTML"

echo "ok: $JSON"
echo "ok: $HTML"
