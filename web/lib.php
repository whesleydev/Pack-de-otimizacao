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
        $a += ['params' => [], 'confirm' => false, 'risk' => 'safe', 'argv' => [], 'help' => ''];
        $A[$a['id']] = $a;
    };

    // ----- Rápido -----
    $add(['id' => 'apply', 'group' => 'Rápido', 'label' => 'Aplicar o pack recomendado',
          'desc' => 'Aplica o conjunto seguro (sem root): performance, RAM, GPU, rede e jogo.',
          'help' => 'Liga de uma vez as otimizações seguras que não precisam de root: animações mais rápidas, GPU na interface, RAM ajustada, DNS/rede e modo de jogo. É o "faz tudo" para começar. Dá para desfazer em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'all'], 'confirm' => true, 'timeout' => 300]);
    $add(['id' => 'restore_all', 'group' => 'Rápido', 'label' => 'Reverter TUDO',
          'desc' => 'Desfaz níveis 2, otimizações profundas e debloat de uma vez.',
          'help' => 'Volta o aparelho ao estado de fábrica de configuração: desfaz as otimizações, as profundas (root) e o debloat. Use quando quiser "limpar" tudo o que o pack aplicou.',
          'argv' => ['pack.sh', 'restore'], 'confirm' => true, 'timeout' => 300]);
    $add(['id' => 'snapshot_save', 'group' => 'Rápido', 'label' => 'Salvar snapshot',
          'desc' => 'Tira uma foto das configurações atuais para poder voltar depois.',
          'help' => 'Guarda o estado atual das configurações num "snapshot". Se algo der errado, você restaura essa foto e volta exatamente como estava. Faça isso ANTES de mexer em qualquer coisa.',
          'argv' => ['snapshot.sh', 'save']]);

    // ----- DNS (perfis) -----
    $dns = [
        'cloudflare'        => ['Cloudflare', 'Privacidade e velocidade, sem registro.'],
        'quad9'             => ['Quad9', 'Privacidade e bloqueio de sites maliciosos.'],
        'adguard'           => ['AdGuard', 'Bloqueia anúncios e rastreadores.'],
        'adguard-family'    => ['AdGuard Família', 'Anúncios + bloqueio de conteúdo adulto.'],
        'cloudflare-family' => ['Cloudflare Família', 'Bloqueia conteúdo adulto.'],
        'mullvad'           => ['Mullvad', 'Privacidade sem registro (anônimo).'],
        'dnsforge'          => ['DNSForge', 'Bloqueia anúncios, sem guardar logs.'],
        'google'            => ['Google', 'Compatibilidade máxima com qualquer rede.'],
        'gaming'            => ['Gaming', 'Baixa latência para jogos + rede otimizada.'],
    ];
    foreach ($dns as $k => $v) {
        $add(['id' => "dns.$k", 'group' => 'DNS', 'label' => $v[0], 'desc' => $v[1],
              'help' => 'DNS é o serviço que "traduz" endereços de sites. Um DNS privado (DoT) deixa sua navegação mais rápida, privada e pode bloquear anúncios/malware. Escolha um perfil e ele passa a valer para o aparelho todo. Volte ao normal em "DNS automático".',
              'argv' => ['dns.sh', $k]]);
    }
    $add(['id' => 'dns.custom', 'group' => 'DNS', 'label' => 'DNS personalizado (host DoT)',
          'desc' => 'Use qualquer hostname de DNS-over-TLS que você quiser.',
          'help' => 'Se você já tem um DNS privado favorito, digite aqui o hostname (ex.: dns.exemplo.com). Ele será usado como DNS do aparelho, com criptografia.',
          'argv' => ['dns.sh', 'custom', '{host}'],
          'params' => [['name' => 'host', 'type' => 'host', 'label' => 'Hostname DoT']]]);
    $add(['id' => 'dns.off', 'group' => 'DNS', 'label' => 'DNS automático (desligar)',
          'desc' => 'Volta o DNS para o padrão da operadora.',
          'help' => 'Desliga o DNS privado e devolve o aparelho para o DNS automático da sua operadora/rede. Use se algum site parar de abrir.',
          'argv' => ['dns.sh', 'off']]);

    // ----- RAM / Limpeza -----
    $add(['id' => 'mem.padrao', 'group' => 'RAM / Limpeza', 'label' => 'RAM: perfil padrão',
          'desc' => 'Multitarefa: mantém mais apps prontos na memória (32 em cache).',
          'help' => 'Ajusta quantos apps o sistema pode manter na memória. O perfil padrão guarda mais apps abertos (bom para o dia a dia, alternar entre apps é mais rápido).',
          'argv' => ['adb-tweaks.sh', 'mem', 'padrao']]);
    $add(['id' => 'mem.gaming', 'group' => 'RAM / Limpeza', 'label' => 'RAM: perfil gaming',
          'desc' => 'Libera mais RAM para o jogo (só 8 apps em cache).',
          'help' => 'Deixa o sistema manter menos apps na memória para sobrar mais RAM para o jogo. Resultado: menos engasgo em partidas. Trade-off: alternar entre apps fica um pouco mais lento.',
          'argv' => ['adb-tweaks.sh', 'mem', 'gaming']]);
    $add(['id' => 'clean', 'group' => 'RAM / Limpeza', 'label' => 'Limpar cache e RAM',
          'desc' => 'Apaga o cache de todos os apps e libera a memória em uso.',
          'help' => 'Remove arquivos temporários (cache) e limpa processos parados na memória. Libera espaço e RAM na hora. Não apaga seus dados nem conversas — só cache.',
          'argv' => ['adb-tweaks.sh', 'clean']]);
    $add(['id' => 'clean.aot', 'group' => 'RAM / Limpeza', 'label' => 'Limpar dexopt (AOT)',
          'desc' => 'Recupera espaço e evita o compilador travar o aparelho.',
          'help' => 'O Android compila os apps em segundo plano e isso ocupa espaço e às vezes trava. Aqui essa compilação é limpa: recupera armazenamento. Os apps recompilam sozinhos quando você abre.',
          'argv' => ['adb-tweaks.sh', 'aot']]);

    // ----- Renderizador -----
    $add(['id' => 'gpu', 'group' => 'Renderizador', 'label' => 'Aplicar conjunto GPU',
          'desc' => 'Renderizador + força GPU + remove desfoques.',
          'help' => 'Pacote gráfico completo: usa a GPU para desenhar a interface, remove os efeitos de desfoque (blur) que pesam e liga o driver de jogo. Deixa a navegação mais fluida.',
          'argv' => ['adb-tweaks.sh', 'gpu']]);
    $add(['id' => 'gpu.opengl', 'group' => 'Renderizador', 'label' => 'Renderizador: OpenGL (padrão)',
          'desc' => 'Motor gráfico de fábrica. Mais compatível.',
          'help' => 'Volta o renderizador para o OpenGL, o padrão do Android. É o mais compatível — use se algum app ficar com tela estranha nos outros modos.',
          'argv' => ['adb-tweaks.sh', 'raw', 'setprop debug.hwui.renderer opengl']]);
    $add(['id' => 'gpu.skiagl', 'group' => 'Renderizador', 'label' => 'Renderizador: SkiaGL',
          'desc' => 'Skia sobre OpenGL. Equilíbrio entre fluidez e compatibilidade.',
          'help' => 'Usa a biblioteca Skia (mais moderna) rodando sobre OpenGL. Costuma ser um bom equilíbrio: mais fluido que o padrão sem arriscar tanto quanto o Vulkan.',
          'argv' => ['adb-tweaks.sh', 'raw', 'setprop debug.hwui.renderer skiagl']]);
    $add(['id' => 'gpu.skiavk', 'group' => 'Renderizador', 'label' => 'Renderizador: Skia Vulkan',
          'desc' => 'Skia sobre Vulkan. Costuma dar mais fluidez.',
          'help' => 'Usa Skia sobre Vulkan, a API gráfica mais moderna. Em aparelhos compatíveis dá a interface mais fluida. Se algum app travar ou mostrar artefatos, volte para OpenGL.',
          'argv' => ['adb-tweaks.sh', 'raw', 'setprop debug.hwui.renderer skiavk']]);
    $add(['id' => 'gpu.force', 'group' => 'Renderizador', 'label' => 'Forçar renderização por GPU',
          'desc' => 'Usa a GPU para desenhar a interface (não a CPU).',
          'help' => 'Faz a interface ser desenhada pela GPU em vez da CPU. Isso libera a CPU para outras tarefas e deixa a rolagem mais suave.',
          'argv' => ['adb-tweaks.sh', 'raw', 'settings put global force_gpu_rendering 1']]);

    // ----- Renderizador por app (Vulkan/OpenGL/ANGLE) -----
    $add(['id' => 'app.angle', 'group' => 'Por app / jogo', 'label' => 'Usar ANGLE (OpenGL→Vulkan) no app',
          'desc' => 'Faz o app usar Vulkan no lugar do OpenGL. Escolha o app/jogo.',
          'help' => 'ANGLE traduz os comandos de OpenGL para Vulkan. Em muitos jogos isso melhora o desempenho. Escolha o app na lista (ex.: com.dts.freefireth). Se piorar, use "Tirar ANGLE do app".',
          'argv' => ['deep-tune.sh', 'angle', 'add', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.angle_remove', 'group' => 'Por app / jogo', 'label' => 'Tirar ANGLE do app',
          'desc' => 'Volta o app a usar o driver gráfico nativo.',
          'help' => 'Remove o ANGLE do app escolhido, devolvendo ele ao driver nativo do aparelho. Use se o jogo ficou instável ou com gráfico estranho.',
          'argv' => ['deep-tune.sh', 'angle', 'remove', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.angle_reset', 'group' => 'Por app / jogo', 'label' => 'Resetar ANGLE (todos)',
          'desc' => 'Remove a seleção de ANGLE de todos os apps de uma vez.',
          'help' => 'Limpa tudo: nenhum app fica mais usando ANGLE. Bom para recomeçar do zero quando você não lembra quais apps configurou.',
          'argv' => ['deep-tune.sh', 'angle', 'reset'], 'confirm' => true]);
    $add(['id' => 'app.perf', 'group' => 'Por app / jogo', 'label' => 'Modo performance no app',
          'desc' => 'Prioriza o app/jogo escolhido (Game Mode).',
          'help' => 'Pede ao sistema para tratar o app como jogo: mais prioridade de CPU/GPU e menos interrupções. Escolha o pacote do jogo (ex.: com.dts.freefireth).',
          'argv' => ['game-per-app.sh', 'mode', '{pkg}', 'performance'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.downscale', 'group' => 'Por app / jogo', 'label' => 'Reduzir resolução do jogo (FPS)',
          'desc' => 'Renderiza em resolução menor para ganhar FPS. 1.0 = nativo.',
          'help' => 'Diminui a resolução interna do jogo (0.3 a 1.0) mantendo o tamanho na tela. Menos pixels = mais FPS e menos aquecimento. 0.9 é quase imperceptível e já ajuda. Reinicie o jogo depois.',
          'argv' => ['game-per-app.sh', 'custom', '{pkg}', '{scale}'],
          'params' => [
              ['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo'],
              ['name' => 'scale', 'type' => 'float', 'label' => 'Downscale', 'min' => 0.3, 'max' => 1.0, 'step' => 0.05, 'default' => 0.9],
          ], 'confirm' => true]);
    $add(['id' => 'app.reset', 'group' => 'Por app / jogo', 'label' => 'Resetar tuning do app',
          'desc' => 'Remove overlay, ANGLE e modo do app escolhido.',
          'help' => 'Desfaz tudo o que foi aplicado só nesse app (ANGLE, resolução, modo de jogo), voltando ao normal.',
          'argv' => ['game-per-app.sh', 'reset', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);

    // ----- Touch / Free Fire -----
    $touch = [
        'balanced' => ['Equilibrado', 'Ajuste geral, bom para a maioria.'],
        'headshot' => ['Headshot', 'Resposta mais rápida: mira ágil.'],
        'spray' => ['Spray', 'Mais controle de recuo no tiro contínuo.'],
        'sniper' => ['Sniper', 'Mira precisa e estável para longa distância.'],
        'speed' => ['Speed', 'Máxima reatividade: resposta imediata.'],
    ];
    foreach ($touch as $k => $v) {
        $add(['id' => "touch.$k", 'group' => 'Touch / Free Fire', 'label' => "Touch: {$v[0]}",
              'desc' => $v[1],
              'help' => 'Ajusta a sensibilidade e o tempo de resposta do toque do sistema (vale para o jogo todo). Cada perfil muda a rapidez da mira e a suavidade. Teste um, jogue e veja qual combina com você. Reverta em "Restaurar touch".',
              'argv' => ['ff-touch.sh', $k], 'risk' => 'careful']);
    }
    $add(['id' => 'touch.custom', 'group' => 'Touch / Free Fire', 'label' => 'Touch: personalizado',
          'desc' => 'Ajuste fino dos 4 parâmetros do toque.',
          'help' => 'Para quem quer calibrar na mão: responsiveness (rapidez da resposta), long press (tempo de toque longo), pointer speed (velocidade do ponteiro) e touch slop (quanto o dedo pode tremer antes de contar como arrasto).',
          'argv' => ['ff-touch.sh', 'custom', '{tr}', '{lp}', '{ps}', '{slop}'],
          'params' => [
              ['name' => 'tr', 'type' => 'int', 'label' => 'responsiveness', 'min' => 50, 'max' => 200, 'default' => 110],
              ['name' => 'lp', 'type' => 'int', 'label' => 'long press (ms)', 'min' => 100, 'max' => 800, 'default' => 350],
              ['name' => 'ps', 'type' => 'int', 'label' => 'pointer speed', 'min' => -5, 'max' => 5, 'default' => 0],
              ['name' => 'slop', 'type' => 'int', 'label' => 'touch slop', 'min' => 0, 'max' => 30, 'default' => 4],
          ], 'risk' => 'careful']);
    $add(['id' => 'touch.restore', 'group' => 'Touch / Free Fire', 'label' => 'Restaurar touch',
          'desc' => 'Apaga os ajustes de toque e volta ao padrão.',
          'help' => 'Remove todos os ajustes de sensibilidade/toque, devolvendo o toque ao padrão do aparelho.',
          'argv' => ['ff-touch.sh', 'restore']]);
    $add(['id' => 'ff', 'group' => 'Touch / Free Fire', 'label' => 'Preparar e abrir o Free Fire',
          'desc' => 'Fecha apps de fundo, aplica o preset do FF e abre o jogo.',
          'help' => 'Prepara o aparelho para o Free Fire: fecha apps pesados que estavam abertos, aplica o modo de jogo e abre o FF. É o "entrar em modo partida" com um clique.',
          'argv' => ['adb-tweaks.sh', 'ff']]);
    $add(['id' => 'game_mode', 'group' => 'Touch / Free Fire', 'label' => 'Ligar Game Mode',
          'desc' => 'Ativa o modo de jogo do sistema.',
          'help' => 'Liga o modo de jogo do Android, que dá prioridade ao jogo em execução e segura interrupções. Vale para todos os jogos.',
          'argv' => ['adb-tweaks.sh', 'game']]);

    // ----- Performance / Tela / Bateria -----
    $add(['id' => 'perf', 'group' => 'Performance', 'label' => 'Performance (animações 0.5x)',
          'desc' => 'Deixa as animações mais rápidas: interface parece mais ágil.',
          'help' => 'Reduz a duração das animações do sistema pela metade. O celular parece mais rápido sem mudar nada de verdade — só a sensação de velocidade melhora.',
          'argv' => ['adb-tweaks.sh', 'perf']]);
    $add(['id' => 'perf_max', 'group' => 'Performance', 'label' => 'Performance extrema (animações 0)',
          'desc' => 'Remove as animações: transições instantâneas.',
          'help' => 'Desliga as animações de vez. Tudo abre instantaneamente. Ótimo para aparelhos lentos, mas o visual fica mais "seco".',
          'argv' => ['adb-tweaks.sh', 'perf_max']]);
    $add(['id' => 'fluidez', 'group' => 'Performance', 'label' => 'Fluidez (toque + Hz + animações)',
          'desc' => 'Pacote geral de fluidez: toque, taxa de atualização e animações.',
          'help' => 'Combina vários ajustes que, juntos, deixam o uso mais fluido: resposta de toque melhor, taxa de atualização no máximo e animações mais rápidas. É o "tudo para fluidez".',
          'argv' => ['adb-tweaks.sh', 'fluidez']]);
    $add(['id' => 'dnd', 'group' => 'Performance', 'label' => 'Não perturbe (DND)',
          'desc' => 'Silencia notificações durante o jogo.',
          'help' => 'Ativa o modo Não Perturbe: nada de notificações atrapalhando no meio da partida. Desligue com "Desligar DND" quando terminar.',
          'argv' => ['adb-tweaks.sh', 'dnd']]);
    $add(['id' => 'dnd_off', 'group' => 'Performance', 'label' => 'Desligar DND',
          'desc' => 'Volta a receber notificações normalmente.',
          'help' => 'Desliga o modo Não Perturbe e traz as notificações de volta.',
          'argv' => ['adb-tweaks.sh', 'dnd_off']]);
    $add(['id' => 'screen', 'group' => 'Performance', 'label' => 'Tela / refresh alto',
          'desc' => 'Fixa a taxa de atualização no máximo do aparelho.',
          'help' => 'Trava a tela na maior taxa de atualização (Hz) que o aparelho suporta. Rolagem e jogo ficam mais suaves. Gasta um pouco mais de bateria.',
          'argv' => ['adb-tweaks.sh', 'screen']]);
    $add(['id' => 'battery', 'group' => 'Performance', 'label' => 'Economia de bateria',
          'desc' => 'Ativa o modo de economia e o repouso profundo (Doze).',
          'help' => 'Liga a economia de energia e força o aparelho a "dormir" mais fundo quando parado. Dura mais a bateria. NÃO use enquanto joga — pode derrubar o desempenho.',
          'argv' => ['adb-tweaks.sh', 'battery']]);
    $add(['id' => 'battery_off', 'group' => 'Performance', 'label' => 'Desligar economia',
          'desc' => 'Volta ao consumo normal (recomendado para jogar).',
          'help' => 'Desliga a economia de bateria e o repouso profundo. Use antes de jogar para o desempenho não ser limitado.',
          'argv' => ['adb-tweaks.sh', 'battery_off']]);

    // ----- Congelar apps -----
    $add(['id' => 'freeze', 'group' => 'Congelar apps', 'label' => 'Congelar apps (cache freezer)',
          'desc' => 'Ativa o congelador do sistema e aplica a lista.',
          'help' => 'Liga o congelador de apps em cache do sistema: apps que você não está usando ficam pausados em vez de gastar RAM/bateria. Ótimo para liberar memória. Reverta em "Descongelar todos os apps".',
          'argv' => ['adb-tweaks.sh', 'freezer'], 'confirm' => true]);
    $add(['id' => 'unfreeze', 'group' => 'Congelar apps', 'label' => 'Descongelar todos os apps',
          'desc' => 'Garante que nenhum app fique preso em segundo plano.',
          'help' => 'Acorda todos os apps e desliga o congelador. Use se algum app parou de notificar ou não abre direito.',
          'argv' => ['adb-tweaks.sh', 'unfreeze_apps']]);

    // ----- Debloat (perigo) -----
    $debloat = [
        'leve'   => ['Leve', 'Desativa redes sociais rodando em segundo plano.'],
        'medio'  => ['Médio', 'Redes sociais + apps de streaming.'],
        'pesado' => ['Pesado', 'Redes + streaming + apps extras.'],
    ];
    foreach ($debloat as $k => $v) {
        $add(['id' => "debloat.$k", 'group' => 'Debloat', 'label' => "Debloat: perfil {$v[0]}",
              'desc' => $v[1] . ' (reversível)',
              'help' => 'Debloat desativa apps de fábrica que você provavelmente não usa, liberando RAM, bateria e espaço. O perfil leve mexe só em redes sociais; o pesado mexe em mais apps. Tudo é reversível em "Debloat: reverter tudo".',
              'argv' => ['debloat.sh', 'on', $k], 'confirm' => true, 'risk' => 'careful', 'timeout' => 180]);
    }
    $add(['id' => 'debloat.off', 'group' => 'Debloat', 'label' => 'Debloat: reverter tudo',
          'desc' => 'Reativa tudo que o debloat desativou.',
          'help' => 'Traz de volta todos os apps que o debloat desativou, deixando o sistema como estava antes.',
          'argv' => ['debloat.sh', 'off'], 'timeout' => 180]);

    // ----- Otimizações profundas (root) -----
    $deep = [
        'freq'    => ['Frequência CPU/GPU', 'Segura clocks altos para não cair em jogo.', 'Mantém a CPU e a GPU em frequências mais altas por mais tempo, evitando quedas de desempenho no meio da partida. Só funciona com root.'],
        'io'      => ['I/O + memória', 'Ajusta leitura/escrita e faz fstrim.', 'Otimiza a forma como o sistema lê e grava dados (scheduler de I/O) e roda o fstrim, que mantém o armazenamento rápido.'],
        'mem'     => ['Memória (MGLRU/zRAM/KSM)', 'Gerência de memória mais eficiente.', 'Ajusta o gerenciamento de memória do kernel (reciclagem de páginas, compressão e deduplicação). Mais RAM útil e menos travadas.'],
        'net'     => ['Rede BBR + fq_codel', 'Congestionamento moderno: menos lag de rede.', 'Troca o controle de congestionamento da rede pelo BBR e a fila pelo fq_codel. Resultado: menos picos de ping em jogos online.'],
        'latency' => ['Reduzir latência (vsync)', 'Ajusta o SurfaceFlinger para menos atraso.', 'Mexe no SurfaceFlinger para reduzir o atraso entre o toque e o que aparece na tela. Sensação de resposta mais imediata.'],
    ];
    foreach ($deep as $k => $v) {
        $add(['id' => "deep.$k", 'group' => 'Profundas (root)', 'label' => $v[0],
              'desc' => $v[1], 'help' => $v[2] . ' Requer root e pede confirmação.',
              'argv' => ['deep-tune.sh', $k, 'on'], 'risk' => 'root', 'confirm' => true]);
        $add(['id' => "deep.$k.off", 'group' => 'Profundas (root)', 'label' => $v[0] . ' — desligar',
              'desc' => 'Reverte este módulo profundo.',
              'help' => 'Desliga só este ajuste profundo, deixando os outros como estão.',
              'argv' => ['deep-tune.sh', $k, 'off'], 'risk' => 'root']);
    }
    $add(['id' => 'deep.gaming', 'group' => 'Profundas (root)', 'label' => 'MODO JOGO TURBO',
          'desc' => 'Liga todas as otimizações profundas de uma vez.',
          'help' => 'Ativa de uma vez frequência, I/O, memória, rede e latência. É o "turbo" completo para jogar. Requer root. Desfaça com "Reverter TUDO" ou módulo por módulo.',
          'argv' => ['deep-tune.sh', 'gaming', 'on'], 'risk' => 'root', 'confirm' => true, 'timeout' => 180]);
    $add(['id' => 'deep.thermal', 'group' => 'Profundas (root)', 'label' => 'Ajustar limite térmico',
          'desc' => 'Deixa esquentar mais para segurar o clock (tem trava automática).',
          'help' => 'Sobe o limite de temperatura em que o aparelho começa a reduzir o desempenho. Isso segura o clock por mais tempo, mas o aparelho esquenta mais. Há uma trava automática de segurança.',
          'argv' => ['deep-tune.sh', 'thermal', 'on'], 'risk' => 'root', 'confirm' => true]);
    $add(['id' => 'deep.detect', 'group' => 'Profundas (root)', 'label' => 'Detectar hardware',
          'desc' => 'Mostra CPU, GPU e kernel com recomendações.',
          'help' => 'Lê os dados de hardware do aparelho e sugere quais ajustes profundos fazem sentido. Só informa, não muda nada.',
          'argv' => ['deep-tune.sh', 'detect']]);

    // ----- Wi-Fi e rede -----
    $add(['id' => 'wifi', 'group' => 'Wi-Fi e rede', 'label' => 'Ajustes de Wi-Fi',
          'desc' => 'Desliga o scan de Wi-Fi em segundo plano e a economia agressiva.',
          'help' => 'O Android fica varrendo redes Wi-Fi o tempo todo, mesmo conectado. Isso gasta bateria e cria picos de uso da CPU. Aqui a varredura em segundo plano é desligada e a economia de energia do Wi-Fi é ligada. Reverte em "Rede: voltar ao automático".',
          'argv' => ['adb-tweaks.sh', 'wifi']]);
    $add(['id' => 'net', 'group' => 'Wi-Fi e rede', 'label' => 'Rede / TCP (DNS + buffers)',
          'desc' => 'DNS Cloudflare + buffers TCP maiores para menos travada em jogo.',
          'help' => 'Aumenta os buffers de rede (TCP) e troca o DNS para o Cloudflare. Resultado: menos picos de latência e carregamento mais estável. Não é o mesmo que o perfil de DNS gaming — aqui o foco é o buffer de rede.',
          'argv' => ['adb-tweaks.sh', 'net']]);
    $add(['id' => 'net_reset', 'group' => 'Wi-Fi e rede', 'label' => 'Rede: voltar ao automático',
          'desc' => 'Volta o DNS e a rede para o padrão da operadora.',
          'help' => 'Desfaz os ajustes de rede: DNS volta para automático e os buffers deixam de ser forçados. Use se a internet ficar estranha depois de aplicar.',
          'argv' => ['adb-tweaks.sh', 'net_reset']]);

    // ----- Congelar apps (extras) -----
    $add(['id' => 'freezer_off', 'group' => 'Congelar apps', 'label' => 'Desligar o congelador',
          'desc' => 'Desliga o congelador de apps em cache do sistema.',
          'help' => 'O congelador do sistema (cached_apps_freezer) pausa apps em segundo plano para liberar RAM. Aqui ele é desligado — útil se algum app parou de receber notificações.',
          'argv' => ['adb-tweaks.sh', 'freezer_off']]);
    $add(['id' => 'freeze_now', 'group' => 'Congelar apps', 'label' => 'Congelar agora (aplicar lista)',
          'desc' => 'Congela os apps da lista negra (menos a whitelist).',
          'help' => 'Aplica o congelamento na hora: os apps da lista negra são suspensos, exceto os protegidos pela whitelist. Ganha RAM livre. Reverte em "Descongelar agora".',
          'argv' => ['adb-tweaks.sh', 'freeze_apps'], 'confirm' => true, 'risk' => 'careful']);
    $add(['id' => 'unfreeze_now', 'group' => 'Congelar apps', 'label' => 'Descongelar agora (todos)',
          'desc' => 'Acorda todos os apps e desliga o congelador.',
          'help' => 'Garante que nenhum app fique preso em segundo plano: reativa todos e desliga o congelador. Use se algo não abrir ou não notificar.',
          'argv' => ['adb-tweaks.sh', 'unfreeze_apps']]);

    // ----- Debloat por app -----
    $add(['id' => 'debloat.app.disable', 'group' => 'Debloat', 'label' => 'Desativar um app',
          'desc' => 'Desativa um app específico (some da gaveta, mas fica instalado).',
          'help' => 'Desativa só o app que você escolher. Ele para de rodar e de gastar bateria, mas continua instalado. Reversível em "Reativar um app".',
          'argv' => ['debloat.sh', 'disable', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']], 'risk' => 'careful', 'confirm' => true]);
    $add(['id' => 'debloat.app.enable', 'group' => 'Debloat', 'label' => 'Reativar um app',
          'desc' => 'Liga de novo um app que você desativou.',
          'help' => 'Traz de volta um app desativado. Ele volta a aparecer e a rodar normalmente.',
          'argv' => ['debloat.sh', 'enable', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']]]);
    $add(['id' => 'debloat.app.uninstall', 'group' => 'Debloat', 'label' => 'Desinstalar p/ o usuário',
          'desc' => 'Remove o app só para você (dá para reinstalar depois).',
          'help' => 'Desinstala o app apenas para o seu usuário — o sistema continua com a cópia e você pode reinstalar sem baixar de novo. Ótimo para tirar bloatware sem risco. Reversível em "Reinstalar app".',
          'argv' => ['debloat.sh', 'uninstall', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']], 'risk' => 'careful', 'confirm' => true]);
    $add(['id' => 'debloat.app.restore', 'group' => 'Debloat', 'label' => 'Reinstalar app',
          'desc' => 'Traz de volta um app que você desinstalou para o usuário.',
          'help' => 'Reinstala o app removido com "Desinstalar p/ o usuário", sem precisar baixar nada.',
          'argv' => ['debloat.sh', 'restore', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']]]);
    $add(['id' => 'debloat.app.restrict', 'group' => 'Debloat', 'label' => 'Restringir em 2º plano',
          'desc' => 'Impede o app de rodar escondido (modo restrito).',
          'help' => 'Coloca o app no modo restrito: ele não roda em segundo plano nem gasta bateria, mas continua abrindo normalmente quando você toca. Reversível em "Tirar restrição".',
          'argv' => ['debloat.sh', 'restrict', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']], 'risk' => 'careful']);
    $add(['id' => 'debloat.app.unrestrict', 'group' => 'Debloat', 'label' => 'Tirar restrição',
          'desc' => 'Devolve o app ao funcionamento normal.',
          'help' => 'Remove o modo restrito do app, deixando ele rodar em segundo plano de novo.',
          'argv' => ['debloat.sh', 'unrestrict', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']]]);

    // ----- Snapshots (extras) -----
    $add(['id' => 'snapshot_list', 'group' => 'Rápido', 'label' => 'Ver snapshots salvos',
          'desc' => 'Lista os snapshots que você já tirou.',
          'help' => 'Mostra todas as fotos de configuração que você salvou, com data e id. Serve para escolher qual restaurar.',
          'argv' => ['snapshot.sh', 'list']]);
    $add(['id' => 'snapshot_diff', 'group' => 'Rápido', 'label' => 'Comparar com o último snapshot',
          'desc' => 'Mostra o que mudou desde o snapshot mais recente.',
          'help' => 'Compara as configurações atuais com o último snapshot e lista só o que mudou. Bom para conferir o que o pack alterou.',
          'argv' => ['snapshot.sh', 'diff', 'latest']]);
    $add(['id' => 'snapshot_restore', 'group' => 'Rápido', 'label' => 'Restaurar último snapshot',
          'desc' => 'Volta as configurações para o último snapshot salvo.',
          'help' => 'Devolve o aparelho ao estado do último snapshot: desfaz as mudanças feitas depois dele. É o "botão de voltar" mais seguro.',
          'argv' => ['snapshot.sh', 'restore', 'latest'], 'risk' => 'careful', 'confirm' => true]);

    // ----- Diagnóstico -----
    $add(['id' => 'diag.profile', 'group' => 'Diagnóstico', 'label' => 'Perfil do aparelho (SoC/GPU)',
          'desc' => 'Detecta o processador, a GPU e o que combina com o seu aparelho.',
          'help' => 'Lê as informações do seu aparelho (família do processador, GPU, kernel) e recomenda quais otimizações profundas tendem a funcionar melhor. Não muda nada — só informa.',
          'argv' => ['device-profile.sh']]);
    $add(['id' => 'diag.profile_save', 'group' => 'Diagnóstico', 'label' => 'Salvar perfil do aparelho',
          'desc' => 'Salva o relatório do aparelho num arquivo.',
          'help' => 'Gera um arquivo com o perfil completo do aparelho. Útil para guardar ou compartilhar ao pedir ajuda.',
          'argv' => ['device-profile.sh', 'save']]);
    $add(['id' => 'diag.deep_detect', 'group' => 'Diagnóstico', 'label' => 'Detectar hardware (root)',
          'desc' => 'Mostra CPU, GPU, kernel e recomendações.',
          'help' => 'Versão aprofundada da detecção, com detalhes de CPU/GPU e sugestões de tuning. Só leitura.',
          'argv' => ['deep-tune.sh', 'detect']]);
    $add(['id' => 'diag.thermal', 'group' => 'Diagnóstico', 'label' => 'Ver temperatura atual',
          'desc' => 'Lê a temperatura do aparelho agora.',
          'help' => 'Mostra a temperatura atual (quando o aparelho expõe esse sensor). Bom para ver se o ajuste térmico passou do ponto.',
          'argv' => ['deep-tune.sh', 'thermal', 'temp']]);
    $add(['id' => 'diag.dns', 'group' => 'Diagnóstico', 'label' => 'Ver DNS atual',
          'desc' => 'Mostra qual perfil de DNS está ativo agora.',
          'help' => 'Confere se o DNS privado está ligado e qual servidor está em uso.',
          'argv' => ['dns.sh', 'status']]);
    $add(['id' => 'diag.bench_before', 'group' => 'Diagnóstico', 'label' => 'Benchmark: marcar ANTES',
          'desc' => 'Guarda o estado atual para comparar depois de otimizar.',
          'help' => 'Tira uma medida de referência antes de aplicar as otimizações. Depois use "marcar DEPOIS" para ver o ganho. Dica: use os nomes "antes" e "depois".',
          'argv' => ['bench.sh', 'save', '{label}'],
          'params' => [['name' => 'label', 'type' => 'name', 'label' => 'Rótulo', 'default' => 'antes']]]);
    $add(['id' => 'diag.bench_after', 'group' => 'Diagnóstico', 'label' => 'Benchmark: marcar DEPOIS',
          'desc' => 'Mede de novo e compara com o "antes".',
          'help' => 'Coleta o estado atual e compara com a medida anterior, mostrando a diferença. Rode depois de aplicar o pack.',
          'argv' => ['bench.sh', 'run', '{label}'],
          'params' => [['name' => 'label', 'type' => 'name', 'label' => 'Rótulo', 'default' => 'depois']]]);

    // ----- Módulos (plugins do pack) -----
    $add(['id' => 'module.run', 'group' => 'Módulos', 'label' => 'Executar um módulo',
          'desc' => 'Roda um dos módulos/plugins incluídos no pack.',
          'help' => 'Os módulos são os complementos (tweaks, touch, GPU, bateria). Digite o nome exato do módulo — veja a lista na aba Módulos. Ação reversível conforme o módulo.',
          'argv' => ['modules.sh', 'run', '{name}'],
          'params' => [['name' => 'name', 'type' => 'name', 'label' => 'Nome do módulo']],
          'risk' => 'careful', 'confirm' => true, 'timeout' => 180]);

    // ----- Touch: abrir o jogo -----
    $add(['id' => 'ff_open', 'group' => 'Touch / Free Fire', 'label' => 'Abrir o Free Fire',
          'desc' => 'Abre o jogo (útil depois de aplicar os ajustes).',
          'help' => 'Manda o Free Fire abrir. Use depois de aplicar touch/modo de jogo para já entrar otimizado.',
          'argv' => ['adb-tweaks.sh', 'ff_open']]);

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
