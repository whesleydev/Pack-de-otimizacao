<?php
// =============================================================================
//  backup.php - Backup das configurações, cifrado, num arquivo só.
//
//  Mesmo desenho do lado do app (ver OtmBackupCore.kt): o script monta o estado
//  em texto, o PHP cifra com AES-256-GCM e grava o arquivo. Na volta, decifra e
//  manda o texto ao script, que devolve as configurações.
//
//  A chave é gerada aqui, aleatória, e fica em ~/.packotm/web/backup.key com
//  permissão 0600 — nunca vai para o arquivo nem para a rede. Como é o mesmo
//  formato de envelope do app, o arquivo é reconhecível dos dois lados; a chave
//  é que é de cada instalação (o backup de um lugar não abre em outro).
//
//  Formato:
//     -----BEGIN TRIX BACKUP-----
//     AES-256-GCM
//     <base64 do IV(12) + texto cifrado + tag(16)>
//     -----END TRIX BACKUP-----
// =============================================================================

declare(strict_types=1);

const OTM_BKP_HEADER = '-----BEGIN TRIX BACKUP-----';
const OTM_BKP_FOOTER = '-----END TRIX BACKUP-----';
const OTM_BKP_ALGO = 'AES-256-GCM';

function otm_backup_dir(): string {
    $home = getenv('HOME') ?: sys_get_temp_dir();
    $d = $home . '/.packotm/backups';
    if (!is_dir($d)) @mkdir($d, 0700, true);
    return $d;
}

function otm_backup_keyfile(): string {
    $home = getenv('HOME') ?: sys_get_temp_dir();
    $d = $home . '/.packotm/web';
    if (!is_dir($d)) @mkdir($d, 0700, true);
    return $d . '/backup.key';
}

/**
 * Chave de 256 bits. Criada na primeira vez, em arquivo 0600. Se o arquivo
 * existir com tamanho errado é porque foi corrompido — nesse caso NÃO geramos
 * outra em silêncio (os backups antigos ficariam ilegíveis sem aviso): a
 * decifragem falha e o usuário sabe o motivo.
 */
function otm_backup_key(): string {
    $f = otm_backup_keyfile();
    if (is_file($f)) {
        $k = (string)file_get_contents($f);
        if (strlen($k) === 32) return $k;
        throw new RuntimeException('a chave de backup está corrompida');
    }
    $k = random_bytes(32);
    file_put_contents($f, $k);
    @chmod($f, 0600);
    return $k;
}

function otm_backup_seal(string $plain): string {
    $key = otm_backup_key();
    $iv = random_bytes(12);
    $tag = '';
    $ct = openssl_encrypt($plain, 'aes-256-gcm', $key, OPENSSL_RAW_DATA, $iv, $tag, '', 16);
    if ($ct === false) throw new RuntimeException('não consegui cifrar o backup');
    $b64 = base64_encode($iv . $ct . $tag);
    return OTM_BKP_HEADER . "\n" . OTM_BKP_ALGO . "\n" . $b64 . "\n" . OTM_BKP_FOOTER . "\n";
}

function otm_backup_is_envelope(string $text): bool {
    foreach (preg_split('/\R/', $text) as $l) {
        if (trim($l) !== '') return trim($l) === OTM_BKP_HEADER;
    }
    return false;
}

function otm_backup_open(string $text): string {
    $lines = array_values(array_filter(array_map('trim', preg_split('/\R/', $text)), fn($l) => $l !== ''));
    if (count($lines) < 3 || $lines[0] !== OTM_BKP_HEADER) {
        throw new RuntimeException('este arquivo não é um backup do Trix');
    }
    if ($lines[1] !== OTM_BKP_ALGO) {
        throw new RuntimeException('criptografia não suportada: ' . $lines[1]);
    }
    $raw = base64_decode($lines[2], true);
    if ($raw === false || strlen($raw) <= 28) throw new RuntimeException('arquivo de backup corrompido');
    $iv  = substr($raw, 0, 12);
    $tag = substr($raw, -16);
    $ct  = substr($raw, 12, strlen($raw) - 28);
    $out = openssl_decrypt($ct, 'aes-256-gcm', otm_backup_key(), OPENSSL_RAW_DATA, $iv, $tag);
    if ($out === false) {
        throw new RuntimeException('não consegui abrir o backup: ele foi alterado ou pertence a outra instalação');
    }
    return $out;
}

// --- ações --------------------------------------------------------------------

function otm_backup_export(): array {
    $r = otm_script('backup.sh', ['collect'], 180);
    $plain = trim($r['out'] ?? '');
    if (strpos($plain, '#TRIX-BACKUP-V1') !== 0) {
        return ['ok' => false, 'code' => -1,
                'out' => "não consegui ler as configurações do aparelho.\n" . ($r['out'] ?? '')];
    }
    try {
        $cifrado = otm_backup_seal($plain);
    } catch (Throwable $e) {
        return ['ok' => false, 'code' => -1, 'out' => $e->getMessage()];
    }
    $nome = 'trix-config-' . date('Y-m-d_His') . '.txt';
    $dest = otm_backup_dir() . '/' . $nome;
    if (@file_put_contents($dest, $cifrado) === false) {
        return ['ok' => false, 'code' => -1, 'out' => "não consegui gravar o arquivo em $dest"];
    }
    @chmod($dest, 0600);
    $n = 0;
    foreach (explode("\n", $plain) as $l) {
        if (str_starts_with($l, 'global ') || str_starts_with($l, 'system ') || str_starts_with($l, 'setprop ')) $n++;
    }
    return ['ok' => true, 'code' => 0,
            'out' => "configurações salvas em $nome ($n chaves).\n\n"
                   . "Arquivo: $dest\n"
                   . "Guardado criptografado (AES-256-GCM). Para voltar depois, use \"Restaurar configurações\"."];
}

function otm_backup_import(): array {
    $arquivos = glob(otm_backup_dir() . '/*.txt') ?: [];
    if (!$arquivos) {
        return ['ok' => false, 'code' => -1,
                'out' => 'nenhum arquivo de configuração salvo. Use "Salvar configurações" antes.'];
    }
    usort($arquivos, fn($a, $b) => filemtime($b) <=> filemtime($a));
    $f = $arquivos[0];
    $texto = (string)file_get_contents($f);
    if (!otm_backup_is_envelope($texto)) {
        return ['ok' => false, 'code' => -1, 'out' => basename($f) . ' não é um backup do Trix — não vou aplicar.'];
    }
    try {
        $plain = otm_backup_open($texto);
    } catch (Throwable $e) {
        return ['ok' => false, 'code' => -1, 'out' => $e->getMessage()];
    }
    if (strpos($plain, '#TRIX-BACKUP-V1') !== 0) {
        return ['ok' => false, 'code' => -1, 'out' => 'o conteúdo do backup está vazio ou inválido'];
    }
    $tmp = tempnam(sys_get_temp_dir(), 'trix');
    file_put_contents($tmp, $plain);
    @chmod($tmp, 0600);
    $r = otm_script('backup.sh', ['restore', $tmp], 180);
    @unlink($tmp);
    $ok = ($r['code'] ?? -1) === 0 && strpos($r['out'] ?? '', 'restaur') !== false;
    return ['ok' => $ok, 'code' => $r['code'] ?? -1,
            'out' => ($ok ? 'configurações restauradas de ' . basename($f) . ".\n\n" : "falhou ao restaurar.\n\n")
                   . ($r['out'] ?? '')];
}

function otm_backup_list(): array {
    $arquivos = glob(otm_backup_dir() . '/*.txt') ?: [];
    usort($arquivos, fn($a, $b) => filemtime($b) <=> filemtime($a));
    if (!$arquivos) {
        return ['ok' => true, 'code' => 0,
                'out' => 'Nenhum arquivo salvo ainda. Toque em "Salvar configurações" para criar o primeiro.'];
    }
    $linhas = [];
    foreach ($arquivos as $f) {
        $linhas[] = '• ' . basename($f) . '  (' . filesize($f) . ' bytes)';
    }
    return ['ok' => true, 'code' => 0,
            'out' => implode("\n", $linhas) . "\n\nPasta: " . otm_backup_dir()];
}
