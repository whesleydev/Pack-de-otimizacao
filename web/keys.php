<?php
// =============================================================================
//  keys.php - Acesso por chave do painel (sem usuário e senha).
//
//  Não existe credencial pronta. Você cria as chaves com
//  `sh main.sh web key new`. Só o hash SHA-256 fica guardado em
//  ~/.packotm/web/keys.json — a chave em texto nunca é gravada em disco.
//
//  Entrar no painel: a chave vira uma sessão no navegador (cookie httpOnly).
//  Falar com a API: mande a chave no cabeçalho `X-Otm-Key`, em `?key=` ou use
//  a sessão do painel.
// =============================================================================

declare(strict_types=1);

// alfabeto sem letras ambíguas (sem I, L, O e U) para digitar sem erro
const OTM_KEY_ALPHABET = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
const OTM_KEY_PREFIX   = '00';
const OTM_KEY_GROUPS   = 3;   // 00-XXXX-XXXX-XXXX
const OTM_KEY_GLEN     = 4;
const OTM_SESSION_NAME = 'otm_sess';

// -----------------------------------------------------------------------------
//  estado
// -----------------------------------------------------------------------------
function otm_keys_dir(): string {
    $home = getenv('HOME') ?: sys_get_temp_dir();
    $dir = $home . '/.packotm/web';
    if (!is_dir($dir)) @mkdir($dir, 0700, true);
    return $dir;
}

function otm_keys_file(): string { return otm_keys_dir() . '/keys.json'; }

function otm_keys_load(): array {
    $f = otm_keys_file();
    if (!is_file($f)) return ['keys' => []];
    $j = json_decode((string)@file_get_contents($f), true);
    if (!is_array($j) || !isset($j['keys']) || !is_array($j['keys'])) return ['keys' => []];
    return $j;
}

function otm_keys_save(array $data): void {
    $f = otm_keys_file();
    @file_put_contents($f, json_encode($data, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE), LOCK_EX);
    @chmod($f, 0600);
}

// -----------------------------------------------------------------------------
//  chaves
// -----------------------------------------------------------------------------
function otm_key_hash(string $raw): string {
    // hash da forma canônica: assim digitar com espaços, sem hífen ou em
    // minúsculas dá no mesmo (o usuário não precisa acertar a pontuação).
    return hash('sha256', otm_key_normalize($raw));
}

/** Normaliza para o formato canônico 00-XXXX-XXXX-XXXX. */
function otm_key_normalize(string $raw): string {
    $s = strtoupper(preg_replace('/[^A-Za-z0-9]/', '', $raw) ?? '');
    $body = OTM_KEY_GROUPS * OTM_KEY_GLEN;
    // "00" também é caractere do alfabeto: só tira quando sobra corpo inteiro.
    if (str_starts_with($s, OTM_KEY_PREFIX) && strlen($s) > $body) {
        $s = substr($s, strlen(OTM_KEY_PREFIX));
    }
    $s = substr($s, 0, $body);
    $out = [];
    for ($i = 0; $i < OTM_KEY_GROUPS; $i++) {
        $chunk = substr($s, $i * OTM_KEY_GLEN, OTM_KEY_GLEN);
        if ($chunk === '') break;
        $out[] = $chunk;
    }
    return OTM_KEY_PREFIX . ($out ? '-' . implode('-', $out) : '');
}

/** Aceita só chaves bem formadas: 00-XXXX-XXXX-XXXX, alfabeto sem ambíguos. */
function otm_key_well_formed(string $raw): bool {
    return (bool)preg_match('/^' . OTM_KEY_PREFIX . '(-[' . OTM_KEY_ALPHABET . ']{' . OTM_KEY_GLEN . '}){' . OTM_KEY_GROUPS . '}$/', otm_key_normalize($raw));
}

function otm_key_generate(): string {
    $n = strlen(OTM_KEY_ALPHABET);
    $s = '';
    for ($i = 0; $i < OTM_KEY_GROUPS * OTM_KEY_GLEN; $i++) {
        $s .= OTM_KEY_ALPHABET[random_int(0, $n - 1)];
    }
    return otm_key_normalize($s);
}

/**
 * Cria uma chave nova. Devolve a chave em texto UMA vez — depois só o hash fica.
 * @return array{id:string,key:string,label:string,created:int}
 */
function otm_key_create(string $label = ''): array {
    $raw = otm_key_generate();
    $id  = bin2hex(random_bytes(4));
    $data = otm_keys_load();
    $data['keys'][] = [
        'id'       => $id,
        'hash'     => otm_key_hash($raw),
        'label'    => trim($label),
        'created'  => time(),
        'last_used' => null,
        'revoked'  => false,
    ];
    otm_keys_save($data);
    return ['id' => $id, 'key' => $raw, 'label' => trim($label), 'created' => time()];
}

function otm_key_list(): array {
    $data = otm_keys_load();
    $out = [];
    foreach ($data['keys'] as $k) {
        $out[] = [
            'id'        => (string)($k['id'] ?? ''),
            'label'     => (string)($k['label'] ?? ''),
            'created'   => (int)($k['created'] ?? 0),
            'last_used' => $k['last_used'] ?? null,
            'revoked'   => (bool)($k['revoked'] ?? false),
        ];
    }
    return $out;
}

/**
 * Só os hashes das chaves ativas. É o que o app recebe (assets/panel/keys.json)
 * para validar a chave localmente, sem levar a chave em texto para o APK.
 */
function otm_key_active_hashes(): array {
    $out = [];
    foreach (otm_keys_load()['keys'] as $k) {
        if (!empty($k['revoked'])) continue;
        $h = (string)($k['hash'] ?? '');
        if ($h !== '') $out[$h] = true;
    }
    return array_keys($out);
}

function otm_key_revoke(string $id): bool {
    $data = otm_keys_load();
    $hit = false;
    foreach ($data['keys'] as &$k) {
        if ((string)($k['id'] ?? '') === $id) { $k['revoked'] = true; $hit = true; }
    }
    unset($k);
    if ($hit) otm_keys_save($data);
    return $hit;
}

/** Quantas chaves ativas existem. Zero significa: crie a primeira. */
function otm_key_active_count(): int {
    $n = 0;
    foreach (otm_keys_load()['keys'] as $k) if (empty($k['revoked'])) $n++;
    return $n;
}

/** Confere a chave e marca o uso. Devolve o id quando vale. */
function otm_key_verify(string $raw): ?string {
    if (!otm_key_well_formed($raw)) return null;
    $h = otm_key_hash($raw);
    $data = otm_keys_load();
    $found = null;
    foreach ($data['keys'] as &$k) {
        if (!empty($k['revoked'])) continue;
        if (hash_equals((string)($k['hash'] ?? ''), $h)) { $k['last_used'] = time(); $found = (string)$k['id']; break; }
    }
    unset($k);
    if ($found !== null) otm_keys_save($data);
    return $found;
}

// -----------------------------------------------------------------------------
//  sessão
// -----------------------------------------------------------------------------
function otm_key_start(): void {
    if (session_status() === PHP_SESSION_ACTIVE) return;
    if (headers_sent()) return;
    session_name(OTM_SESSION_NAME);
    session_set_cookie_params([
        'lifetime' => 0,
        'path'     => '/',
        'httponly' => true,
        'samesite' => 'Lax',
    ]);
    @session_start();
}

function otm_key_logged_in(): bool {
    // o painel estático embutido no app é gerado por _render_static.php
    if (defined('OTM_STATIC_RENDER') && OTM_STATIC_RENDER) return true;
    otm_key_start();
    return !empty($_SESSION['otm_key_id']);
}

function otm_key_id(): string {
    otm_key_start();
    return (string)($_SESSION['otm_key_id'] ?? '');
}

/** Entra com uma chave. Devolve false se a chave não vale. */
function otm_key_login(string $raw): bool {
    $id = otm_key_verify($raw);
    if ($id === null) return false;
    otm_key_start();
    session_regenerate_id(true);
    $_SESSION['otm_key_id'] = $id;
    return true;
}

function otm_key_logout(): void {
    otm_key_start();
    $_SESSION = [];
    if (ini_get('session.use_cookies')) {
        $p = session_get_cookie_params();
        setcookie(OTM_SESSION_NAME, '', time() - 42000, $p['path'], $p['domain'], $p['secure'], $p['httponly']);
    }
    @session_destroy();
}

// token de CSRF amarrado à sessão (usado na tela de acesso e nas ações)
function otm_csrf(): string {
    otm_key_start();
    if (empty($_SESSION['otm_csrf'])) $_SESSION['otm_csrf'] = bin2hex(random_bytes(16));
    return (string)$_SESSION['otm_csrf'];
}

function otm_csrf_ok(?string $t): bool {
    otm_key_start();
    return is_string($t) && !empty($_SESSION['otm_csrf']) && hash_equals((string)$_SESSION['otm_csrf'], $t);
}
