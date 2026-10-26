<?php
// =============================================================================
//  Helpers.php - Funções soltas usadas em todo o painel.
//
//  Formatação de data, escape de HTML, leitura de parâmetros e resposta JSON.
//  Sem estado: só funções puras.
// =============================================================================

declare(strict_types=1);

// -----------------------------------------------------------------------------
//  entrada / saída
// -----------------------------------------------------------------------------

function otm_str(?string $v, int $max = 500): string
{
    return otm_substr(trim((string)$v), 0, $max);
}

/** substr seguro para UTF-8. Usa mbstring quando existe; senão, cai no substr
 *  (o painel não deve exigir a extensão mbstring para funcionar). */
function otm_substr(?string $v, int $start, ?int $len = null): string
{
    $v = (string)$v;
    if (function_exists('mb_substr')) return mb_substr($v, $start, $len);
    return $len === null ? substr($v, $start) : substr($v, $start, $len);
}

function otm_int($v, int $default = 0): int
{
    if ($v === null || $v === '' || !is_numeric($v)) return $default;
    return (int)$v;
}

function otm_post(string $k, string $default = ''): string
{
    return otm_str($_POST[$k] ?? $default);
}

function otm_get(string $k, string $default = ''): string
{
    return otm_str($_GET[$k] ?? $default);
}

function otm_e(?string $s): string
{
    return htmlspecialchars((string)$s, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

function otm_json($data, int $code = 200): void
{
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    header('X-Content-Type-Options: nosniff');
    echo json_encode($data, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    exit;
}

function otm_redirect(string $to): void
{
    header('Location: ' . $to);
    exit;
}

/** IP do cliente, olhando o cabeçalho de proxy quando existir. */
function otm_client_ip(): string
{
    foreach (['HTTP_CF_CONNECTING_IP', 'HTTP_X_FORWARDED_FOR', 'REMOTE_ADDR'] as $k) {
        if (empty($_SERVER[$k])) continue;
        $ip = trim(explode(',', (string)$_SERVER[$k])[0]);
        if (filter_var($ip, FILTER_VALIDATE_IP)) return $ip;
    }
    return '';
}

// -----------------------------------------------------------------------------
//  datas: o banco guarda texto UTC (datetime('now')), a tela mostra local
// -----------------------------------------------------------------------------

function otm_now(): string { return gmdate('Y-m-d H:i:s'); }

function otm_fmt_dt(?string $utc, string $fmt = 'd/m/Y H:i'): string
{
    if ($utc === null || $utc === '') return '—';
    $ts = strtotime($utc . ' UTC');
    return $ts === false ? '—' : date($fmt, $ts);
}

/** Dias restantes (null = nunca expira, negativo = expirada). */
function otm_days_left(?string $expiresUtc): ?int
{
    if ($expiresUtc === null || $expiresUtc === '') return null;
    $ts = strtotime($expiresUtc . ' UTC');
    if ($ts === false) return null;
    return (int)ceil(($ts - time()) / 86400);
}

/** Soma dias a agora (UTC). NULL days = NULL (vitalício). */
function otm_expiry_from_days(?int $days): ?string
{
    if ($days === null || $days <= 0) return null;
    return gmdate('Y-m-d H:i:s', time() + $days * 86400);
}

function otm_bytes(int $b): string
{
    $u = ['B', 'KB', 'MB', 'GB', 'TB'];
    $i = 0;
    while ($b >= 1024 && $i < count($u) - 1) { $b /= 1024; $i++; }
    return ($i === 0 ? (string)$b : number_format($b, 1, ',', '.')) . ' ' . $u[$i];
}

/** Caixa de aviso. $kind: ok|err|warn|info. Fica aqui (e não no layout) porque
 *  a tela de login usa sem carregar o layout. */
function otm_msg(string $kind, string $text): string
{
    return '<div class="msg ' . otm_e($kind) . '">' . $text . '</div>';
}
