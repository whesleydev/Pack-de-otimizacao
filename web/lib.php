<?php
// =============================================================================
//  lib.php - Núcleo do painel web do Pack de Otimização.
//
//  Regras de segurança:
//   - Só executa scripts que estão numa LISTA BRANCA (dentro de scripts/).
//   - Nunca recebe comando cru do navegador: monta o argv a partir de um
//     REGISTRO de ações e valida cada parâmetro (pacote, enum, número, host).
//   - Usa proc_open com array de argumentos (sem shell intermediário).
//   - Toda ação que mexe no aparelho é registrada em .state/log.jsonl.
//
//  O painel é uma casca fina: quem faz o trabalho são os scripts do pack.
// =============================================================================

declare(strict_types=1);

function otm_root(): string {
    return dirname(__DIR__);                       // web/ -> raiz do pack
}
function otm_scripts(): string { return otm_root() . '/scripts'; }
function otm_state(): string {
    $d = __DIR__ . '/.state';
    if (!is_dir($d)) @mkdir($d, 0775, true);
    return $d;
}

// --- utilidades ---------------------------------------------------------------
function otm_have(string $bin): bool {
    static $cache = [];
    if (!isset($cache[$bin])) {
        $out = [];
        @exec('command -v ' . escapeshellarg($bin) . ' 2>/dev/null', $out);
        $cache[$bin] = !empty($out);
    }
    return $cache[$bin];
}

// otm_exec: roda argv (array) e devolve [ok, code, out]
function otm_exec(array $argv, int $timeout = 60): array {
    $cmd = [];
    if (otm_have('timeout')) { $cmd[] = 'timeout'; $cmd[] = (string)$timeout; }
    $cmd = array_merge($cmd, $argv);

    $desc = [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']];
    $p = @proc_open($cmd, $desc, $pipes);
    if (!is_resource($p)) {
        return ['ok' => false, 'code' => -1, 'out' => 'não consegui iniciar o processo'];
    }
    fclose($pipes[0]);
    $out = stream_get_contents($pipes[1]);
    $err = stream_get_contents($pipes[2]);
    fclose($pipes[1]); fclose($pipes[2]);
    $code = proc_close($p);
    $txt = trim($out . ($err !== '' ? "\n" . $err : ''));
    return ['ok' => $code === 0, 'code' => $code, 'out' => $txt];
}

// roda um script do pack: otm_script('dns.sh', ['adguard'])
function otm_script(string $name, array $args = [], int $timeout = 60): array {
    $path = otm_scripts() . '/' . $name;
    if (!in_array($name, otm_allowed_scripts(), true) || !is_file($path)) {
        return ['ok' => false, 'code' => -1, 'out' => "script não permitido: $name"];
    }
    return otm_exec(array_merge(['sh', $path], $args), $timeout);
}

function otm_allowed_scripts(): array {
    return [
        'pack.sh', 'adb-tweaks.sh', 'deep-tune.sh', 'debloat.sh', 'dns.sh',
        'modules.sh', 'ff-touch.sh', 'game-per-app.sh', 'snapshot.sh',
        'bench.sh', 'device-profile.sh',
    ];
}

// --- validação de parâmetros --------------------------------------------------
function otm_valid_pkg(string $s): bool {
    return (bool)preg_match('/^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+)+$/', $s);
}
function otm_valid_host(string $s): bool {
    return (bool)preg_match('/^[A-Za-z0-9]([A-Za-z0-9.-]{0,61}[A-Za-z0-9])?$/', $s);
}
function otm_valid_name(string $s): bool {
    return (bool)preg_match('/^[A-Za-z0-9._-]{1,40}$/', $s);
}
function otm_valid_text(string $s): bool {
    return (bool)preg_match('/^[A-Za-z0-9 ._:-]{0,40}$/', $s);
}

// --- registro de ações --------------------------------------------------------
// risco: safe | careful | root    confirm: pede confirmação no painel
function otm_actions(): array {
    $A = [];

    $add = function (array $a) use (&$A) {
        $a += ['params' => [], 'confirm' => false, 'risk' => 'safe', 'argv' => []];
        $A[$a['id']] = $a;
    };

    // ----- Rápido -----
    $add(['id' => 'apply', 'group' => 'Rápido', 'label' => 'Aplicar o pack recomendado',
          'desc' => 'Aplica o conjunto seguro sem root (performance, RAM, GPU, rede, jogo).',
          'argv' => ['adb-tweaks.sh', 'all'], 'confirm' => true, 'timeout' => 300]);
    $add(['id' => 'restore_all', 'group' => 'Rápido', 'label' => 'Reverter TUDO',
          'desc' => 'Desfaz níveis 2, otimizações profundas e debloat.',
          'argv' => ['pack.sh', 'restore'], 'confirm' => true, 'timeout' => 300]);
    $add(['id' => 'snapshot_save', 'group' => 'Rápido', 'label' => 'Salvar snapshot',
          'desc' => 'Tira uma foto das configurações atuais para poder voltar.',
          'argv' => ['snapshot.sh', 'save']]);

    // ----- DNS (perfis) -----
    $dns = [
        'cloudflare'        => 'Privacidade + velocidade',
        'quad9'             => 'Privacidade + bloqueio de malware',
        'adguard'           => 'Bloqueio de anúncios e rastreadores',
        'adguard-family'    => 'Anúncios + conteúdo adulto',
        'cloudflare-family' => 'Família (conteúdo adulto)',
        'mullvad'           => 'Privacidade (sem registro)',
        'dnsforge'          => 'Bloqueio de anúncios (sem log)',
        'google'            => 'Compatibilidade máxima',
        'gaming'            => 'Baixa latência p/ jogos (+ TCP + scan off)',
    ];
    foreach ($dns as $k => $d) {
        $add(['id' => "dns.$k", 'group' => 'DNS', 'label' => $k, 'desc' => $d,
              'argv' => ['dns.sh', $k]]);
    }
    $add(['id' => 'dns.custom', 'group' => 'DNS', 'label' => 'DNS personalizado (host DoT)',
          'desc' => 'Use qualquer hostname de DNS-over-TLS.',
          'argv' => ['dns.sh', 'custom', '{host}'],
          'params' => [['name' => 'host', 'type' => 'host', 'label' => 'Hostname DoT']]]);
    $add(['id' => 'dns.off', 'group' => 'DNS', 'label' => 'DNS automático (desligar)',
          'desc' => 'Volta o DNS para o padrão da operadora.',
          'argv' => ['dns.sh', 'off']]);

    // ----- RAM / Limpeza -----
    $add(['id' => 'mem.padrao', 'group' => 'RAM / Limpeza', 'label' => 'RAM: perfil padrão',
          'desc' => 'Multitarefa (32 apps em cache).', 'argv' => ['adb-tweaks.sh', 'mem', 'padrao']]);
    $add(['id' => 'mem.gaming', 'group' => 'RAM / Limpeza', 'label' => 'RAM: perfil gaming',
          'desc' => 'Mais RAM livre para o jogo (8 apps em cache).', 'argv' => ['adb-tweaks.sh', 'mem', 'gaming']]);
    $add(['id' => 'clean', 'group' => 'RAM / Limpeza', 'label' => 'Limpar cache e RAM',
          'desc' => 'Cache de todos os apps, logs e processos em cache.', 'argv' => ['adb-tweaks.sh', 'clean']]);
    $add(['id' => 'clean.aot', 'group' => 'RAM / Limpeza', 'label' => 'Limpar dexopt (AOT)',
          'desc' => 'Recupera espaço e evita engasgo do compilador.', 'argv' => ['adb-tweaks.sh', 'aot']]);

    // ----- Renderizador -----
    $add(['id' => 'gpu', 'group' => 'Renderizador', 'label' => 'Aplicar conjunto GPU',
          'desc' => 'Renderizador + force GPU + remover blur.', 'argv' => ['adb-tweaks.sh', 'gpu']]);
    $add(['id' => 'gpu.opengl', 'group' => 'Renderizador', 'label' => 'Renderizador: OpenGL (padrão)',
          'desc' => 'Motor gráfico de fábrica.', 'argv' => ['adb-tweaks.sh', 'raw', 'setprop debug.hwui.renderer opengl']]);
    $add(['id' => 'gpu.skiagl', 'group' => 'Renderizador', 'label' => 'Renderizador: SkiaGL',
          'desc' => 'Skia sobre OpenGL.', 'argv' => ['adb-tweaks.sh', 'raw', 'setprop debug.hwui.renderer skiagl']]);
    $add(['id' => 'gpu.skiavk', 'group' => 'Renderizador', 'label' => 'Renderizador: Skia Vulkan',
          'desc' => 'Skia sobre Vulkan — costuma dar mais fluidez.', 'argv' => ['adb-tweaks.sh', 'raw', 'setprop debug.hwui.renderer skiavk']]);
    $add(['id' => 'gpu.force', 'group' => 'Renderizador', 'label' => 'Forçar renderização por GPU',
          'desc' => 'Usa a GPU para desenhar a interface.', 'argv' => ['adb-tweaks.sh', 'raw', 'settings put global force_gpu_rendering 1']]);

    // ----- Renderizador por app (Vulkan/OpenGL/ANGLE) -----
    $add(['id' => 'app.angle', 'group' => 'Por app / jogo', 'label' => 'Usar ANGLE (OpenGL→Vulkan) no app',
          'desc' => 'Traduz OpenGL para Vulkan. Escolha o app/jogo.',
          'argv' => ['deep-tune.sh', 'angle', 'add', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.angle_remove', 'group' => 'Por app / jogo', 'label' => 'Tirar ANGLE do app',
          'desc' => 'Volta o app a usar o driver nativo.',
          'argv' => ['deep-tune.sh', 'angle', 'remove', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.angle_reset', 'group' => 'Por app / jogo', 'label' => 'Resetar ANGLE (todos)',
          'desc' => 'Remove a seleção de ANGLE de todos os apps.',
          'argv' => ['deep-tune.sh', 'angle', 'reset'], 'confirm' => true]);
    $add(['id' => 'app.perf', 'group' => 'Por app / jogo', 'label' => 'Modo performance no app',
          'desc' => 'Prioriza o app/jogo (Game Mode).',
          'argv' => ['game-per-app.sh', 'mode', '{pkg}', 'performance'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.downscale', 'group' => 'Por app / jogo', 'label' => 'Reduzir resolução do jogo (FPS)',
          'desc' => 'Downscale 0.3–1.0 (1.0 = nativo). Reinicie o jogo.',
          'argv' => ['game-per-app.sh', 'custom', '{pkg}', '{scale}'],
          'params' => [
              ['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo'],
              ['name' => 'scale', 'type' => 'float', 'label' => 'Downscale', 'min' => 0.3, 'max' => 1.0, 'step' => 0.05, 'default' => 0.9],
          ], 'confirm' => true]);
    $add(['id' => 'app.reset', 'group' => 'Por app / jogo', 'label' => 'Resetar tuning do app',
          'desc' => 'Remove overlay/ANGLE/modo do app.',
          'argv' => ['game-per-app.sh', 'reset', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);

    // ----- Touch / Free Fire -----
    foreach (['balanced' => 'Equilíbrio geral', 'headshot' => 'Mira rápida',
              'spray' => 'Controle de recuo', 'sniper' => 'Mira precisa',
              'speed' => 'Máxima reatividade'] as $k => $d) {
        $add(['id' => "touch.$k", 'group' => 'Touch / Free Fire', 'label' => "Touch: $k",
              'desc' => $d, 'argv' => ['ff-touch.sh', $k], 'risk' => 'careful']);
    }
    $add(['id' => 'touch.custom', 'group' => 'Touch / Free Fire', 'label' => 'Touch: personalizado',
          'desc' => 'Ajuste fino dos 4 parâmetros.',
          'argv' => ['ff-touch.sh', 'custom', '{tr}', '{lp}', '{ps}', '{slop}'],
          'params' => [
              ['name' => 'tr', 'type' => 'int', 'label' => 'responsiveness', 'min' => 50, 'max' => 200, 'default' => 110],
              ['name' => 'lp', 'type' => 'int', 'label' => 'long press (ms)', 'min' => 100, 'max' => 800, 'default' => 350],
              ['name' => 'ps', 'type' => 'int', 'label' => 'pointer speed', 'min' => -5, 'max' => 5, 'default' => 0],
              ['name' => 'slop', 'type' => 'int', 'label' => 'touch slop', 'min' => 0, 'max' => 30, 'default' => 4],
          ], 'risk' => 'careful']);
    $add(['id' => 'touch.restore', 'group' => 'Touch / Free Fire', 'label' => 'Restaurar touch',
          'desc' => 'Apaga os ajustes de toque.', 'argv' => ['ff-touch.sh', 'restore']]);
    $add(['id' => 'ff', 'group' => 'Touch / Free Fire', 'label' => 'Preparar e abrir o Free Fire',
          'desc' => 'Aplica o preset do FF e abre o jogo.', 'argv' => ['adb-tweaks.sh', 'ff']]);
    $add(['id' => 'game_mode', 'group' => 'Touch / Free Fire', 'label' => 'Ligar Game Mode',
          'desc' => 'Modo de jogo do sistema.', 'argv' => ['adb-tweaks.sh', 'game']]);

    // ----- Performance / Tela / Bateria -----
    $add(['id' => 'perf', 'group' => 'Performance', 'label' => 'Performance (animações 0.5x)',
          'desc' => 'Interface mais rápida.', 'argv' => ['adb-tweaks.sh', 'perf']]);
    $add(['id' => 'perf_max', 'group' => 'Performance', 'label' => 'Performance extrema (animações 0)',
          'desc' => 'Efeito instantâneo.', 'argv' => ['adb-tweaks.sh', 'perf_max']]);
    $add(['id' => 'fluidez', 'group' => 'Performance', 'label' => 'Fluidez (toque + Hz + animações)',
          'desc' => 'Pacote de fluidez geral.', 'argv' => ['adb-tweaks.sh', 'fluidez']]);
    $add(['id' => 'dnd', 'group' => 'Performance', 'label' => 'Não perturbe (DND)',
          'desc' => 'Bloqueia notificações durante o jogo.', 'argv' => ['adb-tweaks.sh', 'dnd']]);
    $add(['id' => 'dnd_off', 'group' => 'Performance', 'label' => 'Desligar DND',
          'desc' => 'Volta as notificações.', 'argv' => ['adb-tweaks.sh', 'dnd_off']]);
    $add(['id' => 'screen', 'group' => 'Performance', 'label' => 'Tela / refresh alto',
          'desc' => 'Fixa o refresh no máximo do aparelho.', 'argv' => ['adb-tweaks.sh', 'screen']]);
    $add(['id' => 'battery', 'group' => 'Performance', 'label' => 'Economia de bateria',
          'desc' => 'Doze + economia. Não use em jogo.', 'argv' => ['adb-tweaks.sh', 'battery']]);
    $add(['id' => 'battery_off', 'group' => 'Performance', 'label' => 'Desligar economia',
          'desc' => 'Volta ao normal.', 'argv' => ['adb-tweaks.sh', 'battery_off']]);

    // ----- Congelar apps -----
    $add(['id' => 'freeze', 'group' => 'Congelar apps', 'label' => 'Congelar apps (cache freezer)',
          'desc' => 'Ativa o congelador do sistema e aplica a lista.',
          'argv' => ['adb-tweaks.sh', 'freezer'], 'confirm' => true]);
    $add(['id' => 'unfreeze', 'group' => 'Congelar apps', 'label' => 'Descongelar todos os apps',
          'desc' => 'Garante que nenhum app fique preso.', 'argv' => ['adb-tweaks.sh', 'unfreeze_apps']]);

    // ----- Debloat (perigo) -----
    foreach (['leve' => 'Desativa redes sociais de fundo',
              'medio' => 'Redes sociais + streaming',
              'pesado' => 'Redes + streaming + extras'] as $k => $d) {
        $add(['id' => "debloat.$k", 'group' => 'Debloat', 'label' => "Debloat: perfil $k",
              'desc' => $d . ' (reversível com Debloat: reverter)',
              'argv' => ['debloat.sh', 'on', $k], 'confirm' => true, 'risk' => 'careful', 'timeout' => 180]);
    }
    $add(['id' => 'debloat.off', 'group' => 'Debloat', 'label' => 'Debloat: reverter tudo',
          'desc' => 'Reativa tudo que o debloat desativou.', 'argv' => ['debloat.sh', 'off'], 'timeout' => 180]);

    // ----- Otimizações profundas (root) -----
    $deep = [
        'freq'    => ['Frequência CPU/GPU', 'Segura clocks altos (root).'],
        'io'      => ['I/O + memória', 'Scheduler e fstrim (root).'],
        'mem'     => ['Memória (MGLRU/zRAM/KSM)', 'Gerência de memória (root).'],
        'net'     => ['Rede BBR + fq_codel', 'Congestionamento moderno (root).'],
        'latency' => ['Reduzir latência (vsync)', 'SurfaceFlinger (root).'],
    ];
    foreach ($deep as $k => $v) {
        $add(['id' => "deep.$k", 'group' => 'Profundas (root)', 'label' => $v[0],
              'desc' => $v[1], 'argv' => ['deep-tune.sh', $k, 'on'], 'risk' => 'root', 'confirm' => true]);
        $add(['id' => "deep.$k.off", 'group' => 'Profundas (root)', 'label' => $v[0] . ' — desligar',
              'desc' => 'Reverte este módulo profundo.', 'argv' => ['deep-tune.sh', $k, 'off'], 'risk' => 'root']);
    }
    $add(['id' => 'deep.gaming', 'group' => 'Profundas (root)', 'label' => 'MODO JOGO TURBO',
          'desc' => 'Liga tudo de uma vez (freq, io, mem, net, latency).',
          'argv' => ['deep-tune.sh', 'gaming', 'on'], 'risk' => 'root', 'confirm' => true, 'timeout' => 180]);
    $add(['id' => 'deep.thermal', 'group' => 'Profundas (root)', 'label' => 'Ajustar limite térmico (⚠️)',
          'desc' => 'Deixa o aparelho esquentar mais para segurar o clock. Tem trava automática.',
          'argv' => ['deep-tune.sh', 'thermal', 'on'], 'risk' => 'root', 'confirm' => true]);
    $add(['id' => 'deep.detect', 'group' => 'Profundas (root)', 'label' => 'Detectar hardware',
          'desc' => 'Mostra CPU/GPU/kernel e recomendações.', 'argv' => ['deep-tune.sh', 'detect']]);

    return $A;
}

function otm_action(string $id): ?array {
    $all = otm_actions();
    return $all[$id] ?? null;
}

// --- execução de uma ação -----------------------------------------------------
function otm_run(string $id, array $params, bool $confirmed): array {
    $a = otm_action($id);
    if (!$a) return ['ok' => false, 'out' => "ação desconhecida: $id"];
    if (!empty($a['confirm']) && !$confirmed) {
        return ['ok' => false, 'need_confirm' => true, 'out' => 'esta ação pede confirmação'];
    }

    // valida e resolve os parâmetros
    $resolved = [];
    foreach ($a['params'] as $p) {
        $name = $p['name'];
        $val = trim((string)($params[$name] ?? ($p['default'] ?? '')));
        if ($val === '') return ['ok' => false, 'out' => "faltou o parâmetro '$name'"];
        switch ($p['type']) {
            case 'pkg':
                if (!otm_valid_pkg($val)) return ['ok' => false, 'out' => "pacote inválido: $val"];
                break;
            case 'host':
                if (!otm_valid_host($val)) return ['ok' => false, 'out' => "host inválido: $val"];
                break;
            case 'int':
                if (!preg_match('/^-?\d+$/', $val)) return ['ok' => false, 'out' => "$name não é número"];
                $n = (int)$val;
                if (isset($p['min']) && $n < $p['min']) return ['ok' => false, 'out' => "$name abaixo do mínimo"];
                if (isset($p['max']) && $n > $p['max']) return ['ok' => false, 'out' => "$name acima do máximo"];
                break;
            case 'float':
                if (!is_numeric($val)) return ['ok' => false, 'out' => "$name não é número"];
                $f = (float)$val;
                if (isset($p['min']) && $f < $p['min']) return ['ok' => false, 'out' => "$name abaixo do mínimo"];
                if (isset($p['max']) && $f > $p['max']) return ['ok' => false, 'out' => "$name acima do máximo"];
                $val = (string)$f;
                break;
            case 'name':
                if (!otm_valid_name($val)) return ['ok' => false, 'out' => "$name inválido"];
                break;
            default:
                if (!otm_valid_text($val)) return ['ok' => false, 'out' => "$name inválido"];
        }
        $resolved['{' . $name . '}'] = $val;
    }

    // monta o argv trocando os placeholders
    $argv = [];
    foreach ($a['argv'] as $piece) {
        $argv[] = $resolved[$piece] ?? $piece;
    }
    $script = $argv[0];
    $args = array_slice($argv, 1);

    $t = (int)($a['timeout'] ?? 60);
    $r = otm_script($script, $args, $t);
    otm_log($id, $a['label'], $argv, $r);
    return $r + ['id' => $id, 'label' => $a['label']];
}

// --- leitura de estado (status, apps, módulos) --------------------------------
function otm_status(): array {
    $r = otm_script('pack.sh', ['status'], 30);
    return ['text' => $r['out']];
}

function otm_apps(): array {
    $r = otm_script('adb-tweaks.sh', ['raw', 'pm list packages -3'], 30);
    $apps = [];
    foreach (explode("\n", $r['out']) as $line) {
        $line = trim($line);
        if ($line === '') continue;
        $line = preg_replace('/^package:/', '', $line);
        if (otm_valid_pkg($line)) $apps[] = $line;
    }
    sort($apps);
    return $apps;
}

function otm_modules(): array {
    $r = otm_script('modules.sh', ['list'], 30);
    $out = [];
    foreach (explode("\n", $r['out']) as $line) {
        $line = trim($line);
        if ($line === '' || strpos($line, '◆') !== false || strpos($line, '─') !== false
            || strpos($line, 'executar:') !== false || strpos($line, 'atalho:') !== false) continue;
        if (preg_match('/^(\S+)\s+(\S+)$/', $line, $m)) {
            $out[] = ['name' => $m[1], 'group' => $m[2]];
        }
    }
    return $out;
}

function otm_module_run(string $name): array {
    if (!otm_valid_name($name)) return ['ok' => false, 'out' => 'nome inválido'];
    $r = otm_script('modules.sh', ['run', $name], 180);
    otm_log('module.run', "Executar módulo $name", ['modules.sh', 'run', $name], $r);
    return $r;
}

function otm_dns_status(): array {
    $r = otm_script('dns.sh', ['status'], 20);
    return ['text' => $r['out']];
}

// --- log ----------------------------------------------------------------------
function otm_log(string $id, string $label, array $argv, array $res): void {
    $rec = [
        'ts' => date('c'),
        'id' => $id,
        'label' => $label,
        'cmd' => implode(' ', array_map(fn($x) => (strpos($x, ' ') !== false ? '"' . $x . '"' : $x), $argv)),
        'ok' => $res['ok'] ?? false,
        'code' => $res['code'] ?? null,
    ];
    @file_put_contents(otm_state() . '/log.jsonl', json_encode($rec, JSON_UNESCAPED_UNICODE) . "\n", FILE_APPEND);
}

function otm_log_read(int $n = 40): array {
    $f = otm_state() . '/log.jsonl';
    if (!is_file($f)) return [];
    $lines = file($f, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    $lines = array_slice($lines, -$n);
    $out = [];
    foreach (array_reverse($lines) as $l) {
        $j = json_decode($l, true);
        if (is_array($j)) $out[] = $j;
    }
    return $out;
}

// --- JSON ---------------------------------------------------------------------
function otm_json($data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
}
