<?php
// =============================================================================
//  config.php - Carrega arquivos de configuração e expõe otm_config().
//
//  Segredos (token do Turso, senha do banco) NÃO ficam no git: copie
//  config/turso.php.example para config/turso.php e preencha. O painel também
//  aceita as variáveis de ambiente TURSO_DATABASE_URL / TURSO_AUTH_TOKEN, que
//  têm prioridade em cima do arquivo quando definidas.
// =============================================================================

declare(strict_types=1);

if (!function_exists('otm_config')) {
    /**
     * Lê um arquivo de config (config/<name>.php) que devolve um array.
     * Fica em cache por requisição. Devolve [] se o arquivo não existir.
     */
    function otm_config(string $name, ?string $file = null): array
    {
        static $cache = [];
        $path = $file ?? __DIR__ . '/' . $name . '.php';
        if (array_key_exists($path, $cache)) return $cache[$path];
        $cfg = is_file($path) ? require $path : [];
        return $cache[$path] = (is_array($cfg) ? $cfg : []);
    }
}

if (!function_exists('otm_env')) {
    /** getenv com valor padrão e trim. */
    function otm_env(string $key, string $default = ''): string
    {
        $v = getenv($key);
        return ($v === false || $v === '') ? $default : trim((string)$v);
    }
}
