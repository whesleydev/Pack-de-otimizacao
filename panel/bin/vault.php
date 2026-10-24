<?php
// =============================================================================
//  vault.php - Cria a chave do cofre (KeyVault) que cifra as chaves do painel.
//
//  Uso:
//      php panel/bin/vault.php keygen           # cria/rotaciona config/vault.php
//      php panel/bin/vault.php status           # diz se o cofre está pronto
//
//  Sem config/vault.php o painel continua funcionando: só não consegue
//  reexibir chaves antigas (as novas também não são guardadas em texto).
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/bootstrap.php';

$cmd = $argv[1] ?? 'status';
$file = OTM_PANEL_ROOT . '/config/vault.php';

switch ($cmd) {
    case 'keygen':
        if (is_file($file) && !in_array('--force', $argv, true)) {
            fwrite(STDERR, "já existe $file — use --force para trocar (as chaves guardadas antes viram ilegíveis)\n");
            exit(1);
        }
        $key = KeyVault::generate();
        $php = "<?php\n// Chave do cofre (KeyVault): cifra a chave em texto das licenças.\n"
             . "// NÃO VAI PARA O GIT. Trocar isto invalida o que já foi cifrado.\n"
             . "return ['key' => " . var_export($key, true) . "];\n";
        if (@file_put_contents($file, $php, LOCK_EX) === false) {
            fwrite(STDERR, "não consegui escrever $file\n");
            exit(1);
        }
        @chmod($file, 0600);
        echo "✔ cofre criado em $file\n";
        echo "  guarde uma cópia: sem esta chave não dá para reexibir as chaves.\n";
        break;

    case 'status':
        if (KeyVault::isConfigured()) {
            echo "✔ cofre configurado (" . (is_file($file) ? 'config/vault.php' : 'variável de ambiente') . ")\n";
        } else {
            echo "• cofre DESLIGADO — rode: php panel/bin/vault.php keygen\n";
            exit(1);
        }
        break;

    default:
        fwrite(STDERR, "Uso: php panel/bin/vault.php keygen|status\n");
        exit(1);
}
