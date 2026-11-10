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

require_once __DIR__ . '/backup.php';   // backup cifrado (arquivo + AES-GCM)

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
        'modules.sh', 'ff-touch.sh', 'game-per-app.sh', 'snapshot.sh', 'backup.sh',
        'turbo.sh', 'panel-state.sh', 'panel-stats.sh', 'proc-mgr.sh',
        'keep-alive.sh', 'game-clean.sh', 'ram-boost.sh', 'fps.sh',
        'clean.sh', 'bench.sh', 'device-profile.sh', 'config.sh',
        'profile-custom.sh', 'smart-opt.sh', 'vitality.sh',
        'profiles.sh', 'sensi.sh', 'hidden-tune.sh',
        'thermal-guard.sh', 'ai-opt.sh',
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

// --- grupos de escolha (opções lado a lado) -----------------------------------
// Ações marcadas com 'choice' viram UM cartão com as opções lado a lado (ex.:
// renderizador, perfis de toque). Cada ação vira um botão "Selecionar".
// 'state' aponta para a chave lida por panel-state.sh, o que marca a opção em uso.
function otm_choices(): array {
    return [
        'renderer' => [
            'title' => 'Motor gráfico (renderizador)',
            'desc'  => 'Escolha como a interface é desenhada. "Automático" deixa o sistema decidir (mais seguro). SkiaGL é o motor padrão e o mais compatível; Skia Vulkan costuma dar mais fluidez em aparelhos compatíveis. Os modos "multithread" desenham numa thread separada (mais suave, porém mais exigentes). No Android 10+ o motor OpenGL foi removido do sistema — a opção "OpenGL" só funciona em aparelho antigo. Se um app ficar com tela estranha, volte para "Automático".',
            'state' => 'renderer',
            'state_backend' => 'renderengine_backend',
            'risk'  => 'careful',
        ],
        'renderapp' => [
            'title' => 'Motor gráfico por app',
            'desc'  => 'Escolha o app e qual driver gráfico ele deve usar. ANGLE costuma dar mais desempenho em jogos; Nativo força o driver do fabricante (bom se o ANGLE der problema); Padrão devolve a decisão ao sistema. Vale por app — o resto do aparelho não muda.',
            'risk'  => 'careful',
            'app'   => true,
        ],
        'refresh' => [
            'title' => 'Taxa de atualização (Hz)',
            'desc'  => 'Trava a tela numa taxa fixa. Se você prefere 60Hz no dia a dia (economiza bateria), selecione 60. Uma taxa fixa também evita a tela oscilar (60↔90Hz) no meio da partida, o que causa micro-travada. "Automático" devolve a decisão ao sistema.',
            'state' => 'refresh_peak',
            'risk'  => 'careful',
        ],
        'dns_fast' => [
            'title' => 'DNS privado (escolha rápida)',
            'desc'  => 'Um DNS privado (DoT) deixa a navegação mais rápida e privada e pode bloquear anúncios. Escolha um perfil aqui, ou use a lista completa em "DNS e rede". Todos são reversíveis com "DNS automático".',
            'state' => 'dns_host',
            'risk'  => 'safe',
        ],
        'touchprofile' => [
            'title' => 'Sensibilidade do toque (perfis)',
            'desc'  => 'Perfis prontos de toque do sistema para o jogo. Teste um no treino, jogue e veja qual combina com você. Para calibrar na mão, use "Touch: personalizado". Reverta em "Restaurar touch".',
            'risk'  => 'careful',
        ],
        'gameclean' => [
            'title' => 'Game Clean (deixar o jogo limpo)',
            'desc'  => 'Um clique para entrar em "modo partida": encerra os apps de fundo (sem tocar no jogo nem nos protegidos), poda cache/dexopt, libera RAM, protege o jogo contra relog, liga o Game Mode em performance, silencia notificações e corta telemetria. Escolha o app e o modo. Reverta em "Desligar".',
            'risk'  => 'careful',
            'app'   => true,
        ],
        'dpi' => [
            'title' => 'DPI da tela (densidade)',
            'desc'  => 'Muda a densidade lógica da tela — o mesmo "Menor largura" das Opções do desenvolvedor, mas com faixa segura (300 a 600). Vale para o telefone inteiro. "Pequeno" deixa tudo menor (cabe mais, HUD/botões menores); "Grande" deixa maior, para tela pequena. Muda na hora. Volte em "Padrão".',
            'state' => 'dpi_profile',
            'risk'  => 'careful',
        ],
        'effects' => [
            'title' => 'Desfoque e transparência (efeitos visuais)',
            'desc'  => 'O "vidro fosco" atrás do teclado, da barra de navegação e das notificações, e o efeito de transparência do sistema. As otimizações de desempenho (performance, GPU, fluidez, clean, otimizador inteligente e o pack recomendado) desligam os dois para sobrar GPU/CPU — é por isso que depois de aplicar o pack a interface fica "seca" e o teclado parece diferente. Aqui você escolhe: mantenha ligado para o visual completo, ou desligue se preferir mais fluidez. O painel lê o estado real do aparelho.',
            'state' => 'blur',
            'risk'  => 'safe',
        ],
        'proclimit' => [
            'title' => 'Limite de processos em segundo plano',
            'desc'  => 'Quantos apps o sistema pode manter na memória ao mesmo tempo (o mesmo "Limite de processos em segundo plano" das Opções do desenvolvedor). Menos apps = mais RAM e CPU para o jogo; mais apps = multitarefa mais fluida no dia a dia. O painel lê de volta o valor que está valendo de verdade — não só o que foi escrito.',
            'state' => 'proc_limit',
            'risk'  => 'careful',
        ],
        'sysbars' => [
            'title' => 'Barras do sistema (barra de cima e de baixo)',
            'desc'  => 'A barra de baixo é a dos gestos (quadrado, bolinha, voltar) e a de cima é a de status (relógio, bateria, ícones). O pack recomendado e as ações de desempenho desligam o desfoque e o "Janelas / modo imersivo" esconde as barras — é por isso que depois de aplicar o pack a barra de baixo pode parecer "estranha" ou sumir. Aqui você escolhe o que fica visível. O painel lê o estado real do aparelho e marca o que está em uso.',
            'state' => 'sysbars',
            'risk'  => 'careful',
        ],
        'sysbars_icons' => [
            'title' => 'Barra de cima: ícones',
            'desc'  => 'Os ícones secundários da barra de status (rotação automática, fone, volume, alarme). Escondendo, sobra só o essencial: relógio, bateria, sinal e notificações — a barra de cima fica mais limpa e menos poluída no jogo. O painel lê o estado real do aparelho e marca o que está em uso.',
            'state' => 'sysbars_icons_clean',
            'risk'  => 'safe',
        ],
        'sysbars_battery' => [
            'title' => 'Barra de cima: bateria',
            'desc'  => 'Mostra o número da porcentagem ao lado do ícone da bateria, ou deixa só o ícone. Com o número você sabe quanto resta sem abrir as configurações; sem ele, a barra de cima fica mais discreta. O painel lê o estado real do aparelho e marca o que está em uso.',
            'state' => 'sysbars_battery',
            'risk'  => 'safe',
        ],
        'ramboost' => [
            'title' => 'Liberar RAM agora',
            'desc'  => 'Libera a memória de verdade: encerra os apps de fundo (sem tocar no jogo nem nos protegidos no anti-relog), poda o cache de todos os apps. Diferente de "RAM: perfil gaming", que só muda quantos apps o sistema deixa em cache — aqui a memória é liberada na hora. O painel mostra quanto foi liberado.',
            'risk'  => 'careful',
        ],
    ];
}

// --- INTERRUPTORES (liga/desliga) ---------------------------------------------
// O que o painel mostra como chave de ativar/desativar. Cada entrada junta o par
// de ações (on/off) que já existe no registro e a chave de estado REAL lida por
// panel-state.sh, para a chave nunca mentir: se o aparelho diz "ligado", ela
// aparece ligada mesmo que o usuário tenha mexido por fora.
//   on/off     -> ids de ação em otm_actions()
//   state      -> chave de otm_state_read() ('' = o aparelho não expõe)
//   on_values  -> valores da chave que significam LIGADO (case-insensitive)
//   neutral    -> true quando não há como saber o estado (chave mostra "?")
function otm_toggles(): array {
    return [
        // ----- Desempenho -----
        't.anim' => ['group' => 'Desempenho', 'title' => 'Animações rápidas',
            'desc' => 'Animações pela metade: a interface parece mais ágil.',
            'help' => 'Reduz a duração das animações do sistema para 0.5x. Não muda o desempenho real — só a sensação de velocidade.',
            'on' => 'perf', 'off' => 'perf_off', 'state' => 'anim_scale', 'on_values' => ['0.5']],
        't.anim_max' => ['group' => 'Desempenho', 'title' => 'Animações desligadas (extremo)',
            'desc' => 'Transições instantâneas, sem animação nenhuma.',
            'help' => 'Remove as animações de vez: tudo abre na hora. Bom em aparelho lento; o visual fica mais "seco".',
            'on' => 'perf_max', 'off' => 'perf_off', 'state' => 'anim_scale', 'on_values' => ['0', '0.0']],
        't.fluidez' => ['group' => 'Desempenho', 'title' => 'Fluidez geral',
            'desc' => 'Pacote de fluidez: toque, taxa de tela e animações.',
            'help' => 'Combina resposta de toque melhor, taxa de atualização no máximo e animações mais rápidas. É o "tudo para fluidez".',
            'on' => 'fluidez', 'off' => 'fluidez_off', 'state' => 'fluidez', 'on_values' => ['on']],
        't.battery' => ['group' => 'Desempenho', 'title' => 'Economia de bateria',
            'desc' => 'Liga a economia de energia e o repouso profundo.',
            'help' => 'Liga a economia de energia e força o aparelho a dormir mais fundo quando parado. Não use enquanto joga.',
            'on' => 'battery', 'off' => 'battery_off', 'state' => 'low_power', 'on_values' => ['1']],
        't.doze' => ['group' => 'Desempenho', 'title' => 'Sono profundo rápido',
            'desc' => 'Dorme de verdade ~2 min após apagar a tela.',
            'help' => 'Encurta o tempo até o Doze entrar: a tela apagou, o aparelho dorme e a bateria dura muito mais.',
            'on' => 'doze.on', 'off' => 'doze.off', 'state' => 'doze_custom', 'on_values' => ['on']],
        't.refresh' => ['group' => 'Desempenho', 'title' => 'Taxa de tela no máximo',
            'desc' => 'Trava a tela na maior taxa de atualização.',
            'help' => 'Trava a taxa de atualização no máximo do aparelho. Rolagem e jogo mais lisos; gasta um pouco mais de bateria.',
            'on' => 'turbo.refresh_max', 'off' => 'turbo.refresh_auto', 'state' => 'refresh_fixed', 'on_values' => ['on']],
        't.freeze' => ['group' => 'Desempenho', 'title' => 'Congelar apps em cache',
            'desc' => 'Pausa apps que você não está usando.',
            'help' => 'Liga o congelador do sistema: apps em cache ficam pausados em vez de gastar RAM e bateria.',
            'on' => 'freeze', 'off' => 'unfreeze', 'state' => 'freezer', 'on_values' => ['enabled']],
        't.telemetry' => ['group' => 'Desempenho', 'title' => 'Cortar telemetria e logs',
            'desc' => 'Desliga logs persistentes e varreduras "sempre disponível".',
            'help' => 'Desliga o log persistente, o log de Bluetooth e as varreduras de Wi-Fi/Bluetooth em segundo plano. Menos trabalho e mais privacidade.',
            'on' => 'turbo.telemetry_off', 'off' => 'turbo.telemetry_on', 'state' => 'logpersist', 'on_values' => ['off', '']],
        't.phantom' => ['group' => 'Desempenho', 'title' => 'Liberar processos em 2º plano',
            'desc' => 'Desliga o Phantom Killer (bom p/ Termux e serviços).',
            'help' => 'Desliga o Phantom Process Killer: apps como Termux, emuladores e servidores deixam de ter processos mortos pelo sistema.',
            'on' => 'turbo.phantom_off', 'off' => 'turbo.phantom_on', 'state' => 'phantom', 'on_values' => ['false']],
        't.perfmode' => ['group' => 'Desempenho', 'title' => 'Modo desempenho fixo',
            'desc' => 'Trava o aparelho em desempenho máximo.',
            'help' => 'Trava o aparelho em modo de desempenho (não reduz clocks por bateria). Mais FPS sustentado, mais calor e mais consumo.',
            'on' => 'turbo.perfmode_on', 'off' => 'turbo.perfmode_off', 'state' => 'fixed_perf', 'on_values' => ['on']],

        // ----- Sistema -----
        't.notif' => ['group' => 'Sistema', 'title' => 'Silenciar notificações pop-up',
            'desc' => 'Desliga os balões (heads-up) e as bolhas.',
            'help' => 'Desliga os balões (heads-up) e as bolhas de notificação. O sistema trabalha menos e sobra fluidez — bom para jogar.',
            'on' => 'adv.notif', 'off' => 'adv.notif_on', 'state' => 'heads_up', 'on_values' => ['0']],
        't.dnd' => ['group' => 'Sistema', 'title' => 'Não perturbe (DND)',
            'desc' => 'Silencia notificações sem bloquear alarmes.',
            'help' => 'Ativa o modo Não Perturbe: nada de notificação atrapalhando. Alarmes e contatos de emergência continuam passando.',
            'on' => 'dnd', 'off' => 'dnd_off', 'state' => 'dnd_zen', 'on_values' => ['1', '2', '3']],
        't.perm_pack' => ['group' => 'Sistema', 'title' => 'Permitir o app do pack em 2º plano',
            'desc' => 'O pack não é morto e continua aplicando sozinho.',
            'help' => 'Libera o app do pack do Doze, do congelamento e da economia de bateria: sem isso o Android mata o pack e ele "para de aplicar sozinho".',
            'on' => 'perm.app', 'off' => 'perm.app_off', 'state' => 'perm_pack', 'on_values' => ['1']],
        't.perm_ff' => ['group' => 'Sistema', 'title' => 'Permitir os Free Fire em 2º plano',
            'desc' => 'O jogo não é morto nem congelado no meio da partida.',
            'help' => 'Libera os Free Fire do Doze e da economia de bateria, evitando que o jogo feche ou "reloge" no meio da partida.',
            'on' => 'perm.ff', 'off' => 'perm.ff_off', 'state' => 'perm_ff', 'on_values' => ['1']],
        't.perm_battery' => ['group' => 'Sistema', 'title' => 'Bateria sem economia agressiva',
            'desc' => 'Desliga a economia e o App Standby.',
            'help' => 'Desliga a economia de bateria adaptativa e o App Standby, que costumam derrubar apps em segundo plano.',
            'on' => 'perm.battery', 'off' => 'perm.battery_off', 'state' => 'adaptive_batt', 'on_values' => ['0']],

        // ----- Otimizações que o Android esconde (hidden-tune.sh) -----
        // Cada interruptor acende pelo estado REAL lido em panel-state.sh (as
        // chaves "am_tuned"/"aot_tuned"/"ram_tuned" são derivadas: só valem
        // quando a marca do ajuste existe no aparelho).
        't.h_proc' => ['group' => 'Geral', 'title' => 'Constantes do ActivityManager',
            'desc' => 'Memória, jobs e serviços de 2º plano.',
            'help' => 'Mexe nas constantes internas do ActivityManager: cache de processos, limites de memória por app, tempos de serviço em segundo plano e a verificação periódica de CPU. É o ajuste de maior impacto para o sistema parar de "acordar à toa" e o jogo não ser fechado por falta de RAM.',
            'on' => 'hidden.proc_on', 'off' => 'hidden.proc_off', 'state' => 'am_tuned', 'on_values' => ['on']],
        't.h_verify' => ['group' => 'Geral', 'title' => 'Sem checagem de assinatura',
            'desc' => 'Não verifica os apps a cada instalação.',
            'help' => 'O verificador de pacotes confere a assinatura dos apps a cada instalação e em cada boot. Em aparelho com muitos apps isso custa tempo e leitura de disco. Desligar não afeta apps da Play Store (a loja tem o próprio controle).',
            'on' => 'hidden.verify_on', 'off' => 'hidden.verify_off', 'state' => 'pkg_verify', 'on_values' => ['0']],
        't.h_bg' => ['group' => 'Geral', 'title' => 'App Standby agressivo',
            'desc' => 'Restringe apps ociosos em 2º plano.',
            'help' => 'Põe apps ociosos em standby e restringe o que eles podem fazer em segundo plano. Reduz o consumo de CPU e bateria "à toa" sem impedir o app que você está usando.',
            'on' => 'hidden.bg_on', 'off' => 'hidden.bg_off', 'state' => 'app_standby', 'on_values' => ['1']],
        't.h_aot' => ['group' => 'Geral', 'title' => 'Compilar apps (AOT)',
            'desc' => 'Compila em código nativo: abre mais rápido.',
            'help' => 'Sem compilação, cada app é interpretado na primeira abertura e compila enquanto você usa — é a causa do "abre devagar e engasga". Aqui o sistema compila tudo em código nativo, com prioridade máxima para o jogo. Pode demorar alguns minutos e o ganho aparece nas próximas aberturas.',
            'on' => 'hidden.aot_on', 'off' => 'hidden.aot_off', 'state' => 'aot_tuned', 'on_values' => ['on']],
        't.h_ram' => ['group' => 'Geral', 'title' => 'Compactação de memória',
            'desc' => 'zRAM mais agressivo: sobra mais RAM.',
            'help' => 'Ajusta a compactação de memória (zRAM) e os limites de água do kernel. O sistema compacta a RAM em vez de fechar o app, então sobra mais memória para o jogo. Custa um pouco de CPU.',
            'on' => 'hidden.ram_on', 'off' => 'hidden.ram_off', 'state' => 'ram_tuned', 'on_values' => ['on']],
        't.h_gc' => ['group' => 'Geral', 'title' => 'Coleta de lixo sem travar',
            'desc' => 'GC em paralelo: menos engasgo no jogo.',
            'help' => 'Liga a coleta de lixo concorrente: o Android coleta memória em paralelo em vez de pausar o app. É o que causa aquela travada de meio segundo no meio da partida.',
            'on' => 'hidden.gc_on', 'off' => 'hidden.gc_off', 'state' => 'concurrent_gc', 'on_values' => ['1']],
        't.h_freezer' => ['group' => 'Geral', 'title' => 'Congelar apps em cache',
            'desc' => 'Congela em vez de matar (volta instantâneo).',
            'help' => 'Congela os apps que estão em cache: eles param de consumir CPU, mas voltam na hora em que você abre de novo (sem recarregar). É o que o Hail/Greenify fazem, aqui pelo mecanismo do próprio Android.',
            'on' => 'hidden.freezer_on', 'off' => 'hidden.freezer_off', 'state' => 'cache_freezer', 'on_values' => ['enabled']],
        't.h_gpu' => ['group' => 'Geral', 'title' => 'Driver gráfico liberado',
            'desc' => 'Driver de jogo para todos os apps.',
            'help' => 'Libera o driver gráfico de jogo para todos os apps. O driver de jogo fala mais direto com a GPU, tirando uma camada de tradução no caminho dos frames.',
            'on' => 'hidden.gpu_on', 'off' => 'hidden.gpu_off', 'state' => 'game_driver_all', 'on_values' => ['1']],
        't.h_netstats' => ['group' => 'Geral', 'title' => 'Sem estatísticas de rede',
            'desc' => 'O sistema para de gravar uso de dados.',
            'help' => 'O Android coleta o uso de dados de cada app o tempo todo e grava em disco. Parar isso reduz leitura/escrita no armazenamento e um pouco de CPU; só deixa de existir o gráfico de "uso de dados por app" nas configurações.',
            'on' => 'hidden.netstats_on', 'off' => 'hidden.netstats_off', 'state' => 'netstats', 'on_values' => ['0']],

        // ----- Gráficos e toque -----
        't.gfx_comp' => ['group' => 'Display & Touch', 'title' => 'Composição gráfica enxuta',
            'desc' => 'Menos camadas por frame: menos buffer intermediário.',
            'help' => 'Enxuga a composição (draw defer, scissor, buffer age) e desliga o blur. Cada camada a menos é uma composição a menos por frame. Vale sem root e sobrevive ao reboot.',
            'on' => 'gfx.comp_on', 'off' => 'gfx.comp_off', 'state' => 'gfx_comp', 'on_values' => ['on']],
        't.touch_resp' => ['group' => 'Display & Touch', 'title' => 'Resposta ao toque rápida',
            'desc' => 'Janelas curtas: o sistema reage na hora.',
            'help' => 'Encurta as janelas do toque (responsividade, slop, multitouch e long-press). É o "atraso" entre o dedo e o sistema reagir — não troca o perfil de mira.',
            'on' => 'touch.resp_on', 'off' => 'touch.resp_off', 'state' => 'touch_resp', 'on_values' => ['on']],
        't.fx_blur' => ['group' => 'Display & Touch', 'title' => 'Efeitos visuais',
            'desc' => 'Desfoque e transparência da interface.',
            'help' => 'Liga ou desliga o desfoque (blur) e a transparência do sistema. Desligado deixa a interface mais leve e sobra GPU para o jogo; ligado é o visual completo.',
            'on' => 'fx.blur_on', 'off' => 'fx.blur_off', 'state' => 'blur', 'on_values' => ['on']],
        't.angle_all' => ['group' => 'Display & Touch', 'title' => 'ANGLE em todos os apps',
            'desc' => 'Todo app usa ANGLE (OpenGL sobre Vulkan).',
            'help' => 'Faz TODOS os apps usarem a ANGLE (traduz OpenGL para Vulkan) em vez de só o app escolhido. Melhora a compatibilidade gráfica em aparelho com driver fraco; reabra o app/jogo depois.',
            'on' => 'gfx.angle_all_on', 'off' => 'gfx.angle_all_off', 'state' => 'angle_all', 'on_values' => ['1']],
        't.updatable_pre' => ['group' => 'Display & Touch', 'title' => 'Driver gráfico pré-lançamento',
            'desc' => 'Usa o driver atualizável em teste (mais novo).',
            'help' => 'Troca o driver gráfico atualizável do sistema pelo de pré-lançamento (mais novo, às vezes mais rápido e às vezes instável). Desligado volta ao driver estável.',
            'on' => 'gfx.updatable_pre', 'off' => 'gfx.updatable_prod', 'state' => 'updatable_driver', 'on_values' => ['1']],
        't.sysbars_icons' => ['group' => 'Display & Touch', 'title' => 'Esconder ícones da barra',
            'desc' => 'Tira os ícones secundários da barra de cima.',
            'help' => 'Esconde ícones secundários da barra de status (rotação, fone, volume, alarme). Sobra espaço e menos coisa para a barra redesenhar.',
            'on' => 'sysbars.icons_clean', 'off' => 'sysbars.icons_all', 'state' => 'sysbars_icons_clean', 'on_values' => ['clean']],
        't.sysbars_battery' => ['group' => 'Display & Touch', 'title' => 'Bateria em porcentagem',
            'desc' => 'Mostra o número da bateria na barra de cima.',
            'help' => 'Mostra a porcentagem da bateria ao lado do ícone na barra de status.',
            'on' => 'sysbars.battery_pct', 'off' => 'sysbars.battery_off', 'state' => 'sysbars_battery', 'on_values' => ['1']],
    ];
}

// --- registro de ações --------------------------------------------------------
// risco: safe | careful | root    confirm: pede confirmação no painel
/**
 * Opções do PERFIL PERSONALIZADO. É a fonte única das três pontas que precisam
 * casar: os parâmetros de `profile.custom.apply` (abaixo), a const CPROF do HTML
 * (web/index.php e o painel do app) e a ordem de PC_ORDER em
 * scripts/profile-custom.sh. Mexer na ordem aqui exige mexer lá.
 */
function otm_custom_profile_opts(): array {
    // kind: 'seg' (escolha entre opções) ou 'toggle' (chave liga/desliga).
    // No toggle só 'tgl' importa: o switch manda o valor de ligado/desligado, e
    // 'opts' (os rótulos) nunca aparece na tela.
    return [
        // --- escolha entre opções ---
        ['k' => 'anim',      't' => 'Animações',         's' => 'Transições e efeitos da interface.',
         'opts' => [['normal', 'Padrão'], ['half', '0.5x'], ['off', 'Desligadas']]],
        ['k' => 'ram',       't' => 'Apps em 2º plano',  's' => 'Quantos apps podem ficar abertos na memória.',
         'opts' => [['padrao', 'Padrão'], ['gaming', 'Gaming'], ['batata', 'Batata']]],
        ['k' => 'hz',        't' => 'Taxa da tela',      's' => 'Trava a tela numa taxa fixa para não oscilar.',
         'opts' => [['off', 'Automática'], ['60', '60 Hz'], ['90', '90 Hz'], ['120', '120 Hz'], ['144', '144 Hz']]],
        ['k' => 'touch',     't' => 'Perfil de toque',   's' => 'Ajuste de resposta do toque (bom no Free Fire).',
         'opts' => [['none', 'Nenhum'], ['balanced', 'Equilibrado'], ['headshot', 'Headshot'], ['spray', 'Spray'], ['sniper', 'Sniper'], ['speed', 'Velocidade']]],
        ['k' => 'clean',     't' => 'Limpeza',           's' => 'Limpa cache e libera RAM na hora.',
         'opts' => [['off', 'Nenhuma'], ['fundo', 'Fundo'], ['suave', 'Suave'], ['normal', 'Completa']]],
        ['k' => 'renderer',  't' => 'Motor gráfico',     's' => 'SkiaGL ou Skia Vulkan (o sistema ignora valores inválidos).',
         'opts' => [['nao', 'Não mexer'], ['skiagl', 'SkiaGL'], ['skiavk', 'Skia Vulkan']]],
        ['k' => 'dns',       't' => 'DNS privado',       's' => 'Servidor de DNS criptografado (DoT).',
         'opts' => [['nao', 'Não mexer'], ['cloudflare', 'Cloudflare'], ['adguard', 'AdGuard'], ['quad9', 'Quad9'], ['google', 'Google']]],
        ['k' => 'proc',      't' => 'Limite de processos', 's' => 'Máximo de apps em 2º plano (mais RAM ao jogo).',
         'opts' => [['nao', 'Não mexer'], ['4', '4 apps'], ['8', '8 apps'], ['16', '16 apps']]],
        ['k' => 'efeitos',   't' => 'Efeitos visuais',   's' => 'Desfoque e transparência da interface.',
         'opts' => [['nao', 'Não mexer'], ['ligados', 'Ligados'], ['leves', 'Desligados (leve)']]],
        ['k' => 'barras',    't' => 'Barras do sistema', 's' => 'Modo imersivo: esconde a barra de cima, a de baixo ou as duas.',
         'opts' => [['nao', 'Não mexer'], ['visiveis', 'Visíveis'], ['status', 'Só a de baixo'], ['nav', 'Só a de cima'], ['full', 'Imersivo']]],
        ['k' => 'touchlat',  't' => 'Latência de toque', 's' => 'Responsividade e janelas de toque (só o que o aparelho aceita).',
         'opts' => [['nao', 'Não mexer'], ['leve', 'Leve'], ['forte', 'Forte']]],

        // --- barra de status: ajuste fino (reusa o grupo `sysbars`) ---
        ['k' => 'barras_bat', 't' => 'Bateria em %',     's' => 'Mostra o número da bateria na barra de cima.',
         'opts' => [['nao', 'Não mexer'], ['on', 'Mostrar'], ['off', 'Esconder']]],
        ['k' => 'barras_relogio', 't' => 'Segundos no relógio', 's' => 'Relógio da barra de cima com segundos.',
         'opts' => [['nao', 'Não mexer'], ['on', 'Mostrar'], ['off', 'Esconder']]],
        ['k' => 'barras_icones', 't' => 'Ícones da barra', 's' => 'Esconde os ícones secundários (rotação, fone, volume, alarme).',
         'opts' => [['nao', 'Não mexer'], ['limpa', 'Esconder secundários']]],

        // --- toque: janela do multitouch (touch_multi) ---
        ['k' => 'touchmulti', 't' => 'Janela multitouch', 's' => 'Tempo que o aparelho espera entre toques simultâneos (ms).',
         'opts' => [['nao', 'Não mexer'], ['120', '120 ms'], ['200', '200 ms'], ['300', '300 ms']]],

        // --- compilação dos apps (ART / AOT) ---
        ['k' => 'art',       't' => 'Compilar apps (ART)', 's' => 'Recompila os apps de antemão: abre mais rápido, engasga menos. Demora.',
         'opts' => [['nao', 'Não mexer'], ['speed-profile', 'Equilibrada'], ['speed', 'Máxima (demora mais)']]],

        // --- chaves liga/desliga ---
        ['k' => 'telemetry', 't' => 'Desligar telemetria e logs', 's' => 'Corta logs e scans "sempre disponível" em 2º plano.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'off']],
        ['k' => 'hibernate', 't' => 'Hibernar apps',     's' => 'Suspende os apps de fundo para ganhar RAM.',
         'kind' => 'toggle', 'tgl' => ['off' => 'off', 'on' => 'on']],
        ['k' => 'gpu',       't' => 'Renderização por GPU', 's' => 'Força a GPU na interface e libera o driver do jogo.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'net',       't' => 'Rede / buffers TCP', 's' => 'DNS Cloudflare e buffers TCP maiores.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'latency',   't' => 'Latência / ping',   's' => 'BBR, low latency, ECN e fila curta: menos ping.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'wifi',      't' => 'Wi-Fi sem economia', 's' => 'Sem scan em 2º plano nem economia de energia.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'battery',   't' => 'Economia de bateria', 's' => 'Liga a economia de energia e o Doze.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'doze',      't' => 'Sono profundo rápido', 's' => 'Dorme ~2 min após a tela apagar (era ~30 min).',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'freezer',   't' => 'Congelar apps em cache', 's' => 'Congela o que está em cache para liberar CPU.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'dnd',       't' => 'Não perturbe',      's' => 'Silencia notificações sem bloquear alarmes.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'gamefocus', 't' => 'Foco de jogo',      's' => 'DND extremo: nada aparece por cima do jogo.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'notif',     't' => 'Menos notificações', 's' => 'Desliga heads-up e bolhas de notificação.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'perfmode',  't' => 'Modo desempenho fixo', 's' => 'Trava o aparelho em desempenho máximo (esquenta mais).',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'vitality',  't' => 'Longevidade da bateria', 's' => 'Cuida da bateria (limite de carga em 80%).',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'mobile',    't' => 'Rede móvel',        's' => 'Sem economia de dados e sem largar o Wi-Fi ruim.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'janelas',   't' => 'Transições 0.5x',   's' => 'Metade do tempo nas animações de janela.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],

        // --- limpeza profunda e segundo plano (turbo/deep-tune) ---
        ['k' => 'trim',      't' => 'Podar caches',      's' => 'Libera espaço podando caches sem apagar dados dos apps.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'killbg',    't' => 'Encerrar 2º plano', 's' => 'Fecha os apps de fundo agora (poupa o jogo).',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'phantom',   't' => 'Sem limite de processos fantasma', 's' => 'Desliga o Phantom Process Killer (bom p/ Termux e serviços).',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'debloat_bg', 't' => 'Restringir apps de fundo', 's' => 'Põe os apps de fundo em appops restrito + balde standby restrito.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],

        // --- gráficos e tela (deep-tune) ---
        ['k' => 'display',   't' => 'Display afinado (HWUI)', 's' => 'Ajusta o HWUI/SurfaceFlinger: rolagem mais lisa.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'dexopt',    't' => 'Recompilar apps (agendado)', 's' => 'Agenda a recompilação dos apps: o Android roda quando o aparelho estiver parado.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'gaming',    't' => 'Modo jogo profundo', 's' => 'Debloat profundo + ANGLE de uma vez.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],

        // --- tela e toque (extra) ---
        ['k' => 'obscure',   't' => 'Ajustes obscuros',  's' => 'Menos kills em 2º plano e o jogo fora do Doze.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
        ['k' => 'tela',      't' => 'Tela 10 min + 120 Hz', 's' => 'Tempo de tela maior e taxa fixa em 120 Hz.',
         'kind' => 'toggle', 'tgl' => ['off' => 'nao', 'on' => 'on']],
    ];
}

function otm_actions(): array {
    $A = [];

    $add = function (array $a) use (&$A) {
        $a += ['params' => [], 'confirm' => false, 'risk' => 'safe', 'argv' => [], 'help' => ''];
        $A[$a['id']] = $a;
    };

    // ----- Rápido -----
    $add(['id' => 'apply', 'group' => 'Geral', 'label' => 'Aplicar o pack recomendado',
          'desc' => 'O "faz tudo" para novato: performance, RAM, GPU, rede, latência, jogo, bateria e touch.',
          'help' => 'É o botão para quem comprou o app e não sabe o que usar: aplica de uma vez tudo o que é seguro e não precisa de root. Em ordem: performance e animações mais rápidas, GPU na interface, RAM ajustada, DNS privado e buffers de rede, ajustes de latência/ping (BBR, low latency, ECN), Wi-Fi, modo de jogo, anti-relog do jogo, silêncio de notificações, tela, fluidez, limpeza de cache/RAM e, no fim, o limite de processos em segundo plano (4 apps) — que é o que sobra mais RAM para o jogo. O debloat fica de fora de propósito (remover app de fábrica é decisão sua, tem aba própria). Depois de aplicar, se quiser mexer na mira, use a aba "Display & Touch" (que gera a sensi do seu aparelho) e, na próxima vez que abrir o app, use o "Clean phone" no dia a dia. Dá para desfazer em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'all'], 'confirm' => true, 'timeout' => 420]);
    $add(['id' => 'smart.auto', 'group' => 'Geral', 'label' => 'Otimizador inteligente',
          'desc' => 'Um botão só: analisa, decide, aplica e testa o que é melhor para ESTE aparelho.',
          'help' => 'Um botão só — o resto acontece por dentro, sem você escolher nada. Ele LÊ o aparelho inteiro (modelo, processador, GPU, núcleos e frequências, RAM, taxa de tela, armazenamento, térmico, bateria, zram, MGLRU, rede, governador e pressão de memória), calcula a nota e a classe, salva um snapshot de segurança, decide item por item o que faz sentido para AQUELE modelo e aplica. Depois MEDE antes x depois e ainda TESTA as combinações plausíveis (ex.: Vulkan x GL, a maior taxa x 90Hz) para ficar com a que der o melhor resultado. Cada teste fica guardado numa memória por aparelho: da próxima vez ele já começa pela combinação que venceu aqui e vai melhorando a cada execução. O debloat fica de fora de propósito (remover app de fábrica é decisão sua, tem aba própria). Pode demorar alguns minutos — é o tempo de medir e comparar no seu aparelho. Se você tem um jogo escolhido no Modo Competitivo, ele também liga o anti-relog. No fim mostra UM resultado. É tudo reversível em "Reverter TUDO".',
          'argv' => ['smart-opt.sh', 'auto'], 'risk' => 'careful', 'confirm' => true,
          'timeout' => 1800]);
    // --- IA local (script ai-opt.sh): o 3º caminho do card da Home ------------
    // O "otimizador que aprende" roda 100% no aparelho (bandit contextual): mede,
    // decide, aplica, mede de novo e guarda o que venceu. Nada sai do celular.
    $add(['id' => 'ai.apply', 'group' => 'Geral', 'card' => false,
          'label' => 'IA local: aplicar agora (1 ciclo)',
          'desc' => 'Um ciclo: mede, escolhe a ação, aplica e aprende com o resultado.',
          'help' => 'Roda UM ciclo do otimizador que aprende: lê o estado (bateria, temperatura, carga), escolhe uma ação entre os modos do pack (Competitivo, Fluido, Econômico ou "não mexer"), aplica, espera assentar, mede de novo e guarda o ganho medido. O que "melhor" quer dizer aqui é explícito: mais RAM livre e mais taxa de tela CONTAM A FAVOR; temperatura e carga do sistema CONTAM CONTRA. Assim ele não troca fluidez por calor. Tudo roda no seu aparelho — não baixa modelo e não manda nada para fora. Reversível em "Reverter TUDO".',
          'argv' => ['ai-opt.sh', 'apply'], 'risk' => 'careful', 'confirm' => true,
          'timeout' => 300]);
    $add(['id' => 'ai.train', 'group' => 'Geral', 'card' => false,
          'label' => 'IA local: treinar (3 ciclos)',
          'desc' => 'Roda 3 ciclos seguidos para o modelo começar a convergir.',
          'help' => 'Roda 3 ciclos do otimizador que aprende, um atrás do outro. Cada ciclo testa uma ação, mede o ganho e atualiza o modelo. Com poucos ciclos ele já para de testar o que não funciona e passa a repetir o que vence neste aparelho. É o mesmo `ai-opt.sh train`. Reversível em "Reverter TUDO".',
          'argv' => ['ai-opt.sh', 'train', '3'], 'risk' => 'careful', 'confirm' => true,
          'timeout' => 900]);
    $add(['id' => 'ai.status', 'group' => 'Geral', 'card' => false,
          'label' => 'IA local: ver o que aprendeu',
          'desc' => 'Mostra, por contexto, qual ação tem a melhor média neste aparelho.',
          'help' => 'Mostra o modelo aprendido: quantos ciclos já rodaram, quantos contextos distintos foram vistos e, para cada contexto (bateria/temperatura/carga), qual ação tem a melhor média de recompensa. É a transparência do aprendizado — você vê exatamente por que ele escolhe o que escolhe.',
          'argv' => ['ai-opt.sh', 'status']]);
    $add(['id' => 'ai.predict', 'group' => 'Geral', 'card' => false,
          'label' => 'IA local: qual ação agora',
          'desc' => 'Diz a ação que ele escolheria neste momento, sem aplicar nada.',
          'help' => 'Lê o estado atual, calcula o contexto e mostra qual ação o modelo escolheria agora — sem aplicar. Serve para conferir a decisão antes de deixar ele mexer.',
          'argv' => ['ai-opt.sh', 'predict']]);
    $add(['id' => 'ai.reset', 'group' => 'Geral', 'card' => false,
          'label' => 'IA local: esquecer o aprendizado',
          'desc' => 'Apaga o modelo local; o aparelho volta a aprender do zero.',
          'help' => 'Apaga o modelo aprendido neste aparelho. Útil depois de trocar de uso (ex.: parou de jogar) para ele não repetir uma escolha antiga que já não faz sentido. Não desfaz nenhuma otimização aplicada.',
          'argv' => ['ai-opt.sh', 'reset']]);
    // --- trava térmica preditiva (script thermal-guard.sh) --------------------
    // Age ANTES do throttling do kernel: projeta a subida da temperatura e baixa
    // o teto da CPU com antecedência. Reversível (devolve o teto original).
    $add(['id' => 'thermal.predict_on', 'group' => 'Desempenho', 'card' => false,
          'label' => 'Trava térmica preditiva: ligar (1 avaliação)',
          'desc' => 'Lê as zonas, projeta a subida e baixa o teto da CPU antes de esquentar.',
          'help' => 'A trava térmica que AGE ANTES. Em vez de esperar cruzar o limite do kernel (quando o jogo já engasga), ele lê a temperatura das zonas, calcula a inclinação (quanto sobe por segundo), projeta em quantos segundos vai cruzar o limite e, se faltar pouco, baixa o teto de frequência da CPU já. Quando esfria, devolve o teto. O limite vem do trip point do PRÓPRIO kernel quando existe. Reversível: o teto original é guardado.',
          'argv' => ['thermal-guard.sh', 'once'], 'risk' => 'careful', 'timeout' => 120]);
    $add(['id' => 'thermal.predict_status', 'group' => 'Desempenho', 'card' => false,
          'label' => 'Trava térmica preditiva: ver o estado',
          'desc' => 'Mostra zonas, limite, inclinação e a projeção de quando cruza o limite.',
          'help' => 'Mostra o que a trava térmica preditiva está vendo: a temperatura agora, o limite (do trip point do kernel), a inclinação em °C por segundo, a projeção de quantos segundos faltam para cruzar o limite e se o teto da CPU está contido no momento.',
          'argv' => ['thermal-guard.sh', 'status']]);
    $add(['id' => 'thermal.predict_off', 'group' => 'Desempenho', 'card' => false,
          'label' => 'Trava térmica preditiva: desligar',
          'desc' => 'Devolve o teto original de frequência da CPU.',
          'help' => 'Devolve o teto original de frequência de cada núcleo e encerra a contenção. Também é alcançado pelo "Reverter TUDO".',
          'argv' => ['thermal-guard.sh', 'off'], 'risk' => 'safe', 'timeout' => 60]);
    $add(['id' => 'smart.report', 'group' => 'Geral', 'card' => false, 'label' => 'Otimizador: analisar o aparelho',
          'desc' => 'Relatório completo do aparelho, sem alterar nada.',
          'help' => 'Lê o aparelho de ponta a ponta e mostra tudo: SoC, GPU, clusters de CPU com as frequências, RAM (total e livre), pressão de memória do kernel, taxa de tela, resolução lógica, armazenamento, térmico, bateria, zram em uso, governador, entropia, I/O e renderizador atual. Termina com a nota (0-100), a classe e a lista do que está segurando a nota. Não altera NADA — é só leitura.',
          'argv' => ['smart-opt.sh', 'analyze']]);
    $add(['id' => 'smart.decide', 'group' => 'Geral', 'card' => false, 'label' => 'Otimizador: ver o plano',
          'desc' => 'Mostra o que seria aplicado, item por item, e o motivo de cada escolha.',
          'help' => 'Mostra as decisões do otimizador para o seu aparelho, com o motivo de cada uma (por que Vulkan e não GL, por que 120Hz e não 144Hz, quantos apps em cache...). Nada é aplicado aqui — serve para você conferir antes. Você pode pedir um perfil específico.',
          'argv' => ['smart-opt.sh', 'plan', '{perfil}'],
          'params' => [['name' => 'perfil', 'type' => 'enum', 'label' => 'Perfil',
                         'options' => ['auto', 'equilibrado', 'desempenho', 'jogo', 'bateria'],
                         'default' => 'auto']]]);
    $add(['id' => 'smart.bench', 'group' => 'Geral', 'card' => false, 'label' => 'Otimizador: medir antes x depois',
          'desc' => 'Mede o desempenho, aplica o perfil e mede de novo, comparando os dois.',
          'help' => 'O teste que prova o resultado. Ele mede a nota de desempenho do aparelho (RAM livre, pressão de memória, carga de CPU, frequência e temperatura — 3 amostras de cada), aplica o perfil e mede de novo. No fim diz se MELHOROU, PIOROU ou ficou ESTÁVEL. Se piorar, avisa para reverter. É o "olha o número" em vez de "confie em mim".',
          'argv' => ['smart-opt.sh', 'bench', '{perfil}'],
          'params' => [['name' => 'perfil', 'type' => 'enum', 'label' => 'Perfil',
                         'options' => ['auto', 'equilibrado', 'desempenho', 'jogo', 'bateria'],
                         'default' => 'auto']],
          'risk' => 'careful', 'confirm' => true, 'timeout' => 900]);
    $add(['id' => 'smart.compare', 'group' => 'Geral', 'card' => false, 'label' => 'Otimizador: comparar combinações',
          'desc' => 'Testa caminhos diferentes (Vulkan x GL, 120Hz x 90Hz) e fica com o melhor.',
          'help' => 'Quando dois ajustes são plausíveis, este comando testa os dois no SEU aparelho e fica com o de melhor nota de desempenho. Ele alterna o renderizador (Vulkan/GL) e a taxa de tela (a maior x 90Hz, que esquenta menos) medindo cada combinação, e no fim deixa aplicada a vencedora. O que funciona melhor depende do aparelho — então, em vez de adivinhar, ele mede.',
          'argv' => ['smart-opt.sh', 'compare', '{perfil}'],
          'params' => [['name' => 'perfil', 'type' => 'enum', 'label' => 'Perfil',
                         'options' => ['auto', 'equilibrado', 'desempenho', 'jogo', 'bateria'],
                         'default' => 'auto']],
          'risk' => 'careful', 'confirm' => true, 'timeout' => 900]);
    $add(['id' => 'smart.state', 'group' => 'Geral', 'card' => false, 'label' => 'Otimizador: ver o que está ativo',
          'desc' => 'Mostra o perfil aplicado e o estado real dos ajustes agora.',
          'help' => 'Mostra o perfil que foi aplicado por último, a RAM em cache, o renderizador, a taxa de tela (mín/máx), a RAM livre e os apps no anti-relog. Só leitura.',
          'argv' => ['smart-opt.sh', 'status']]);
    $add(['id' => 'restore_all', 'group' => 'Geral', 'card' => false, 'label' => 'Reverter TUDO',
          'desc' => 'Desfaz níveis 2, otimizações profundas e debloat de uma vez.',
          'help' => 'Volta o aparelho ao estado de fábrica de configuração: desfaz as otimizações, as profundas (root) e o debloat. Use quando quiser "limpar" tudo o que o pack aplicou.',
          'argv' => ['pack.sh', 'restore'], 'confirm' => true, 'timeout' => 300]);
    // ----- backup seguro (arquivo criptografado no aparelho) -----
    // Fica DENTRO do card do otimizador (card => false): é a rede de segurança
    // dele. O arquivo vai para a pasta pública do app, criptografado, e pode ser
    // lido de volta para devolver TODAS as configurações de uma vez.
    $add(['id' => 'backup.export', 'group' => 'Geral', 'card' => false,
          'label' => 'Salvar configurações',
          'desc' => 'Salva um arquivo criptografado com as suas configurações.',
          'help' => 'Tira uma foto COMPLETA das configurações que o pack mexe (animações, RAM, taxa de tela, renderizador, toque, rede, bateria e o que mais estiver ativo), junta num arquivo .txt criptografado e guarda numa pasta do app no seu aparelho. É o ponto de retorno: com esse arquivo você volta exatamente como estava, mesmo depois de mexer em muita coisa. O arquivo é seu e fica no seu aparelho — a chave é gerada aqui e não sai dele.',
          'argv' => ['backup.sh', 'collect'], 'timeout' => 180]);
    $add(['id' => 'backup.import', 'group' => 'Geral', 'card' => false,
          'label' => 'Restaurar configurações',
          'desc' => 'Lê o arquivo criptografado e devolve as configurações salvas.',
          'help' => 'Lê o arquivo criptografado que você salvou e devolve TODAS as configurações de uma vez — animações, RAM, taxa de tela, renderizador, toque, rede, bateria e o resto. Serve para voltar ao estado da foto depois de qualquer mexida. Se você tem mais de um arquivo, ele restaura o mais recente; o painel mostra qual foi usado.',
          'argv' => ['backup.sh', 'restore'], 'confirm' => true, 'timeout' => 180]);
    $add(['id' => 'backup.list', 'group' => 'Geral', 'card' => false,
          'label' => 'Ver backups salvos',
          'desc' => 'Lista os arquivos de configuração guardados no aparelho.',
          'help' => 'Mostra os arquivos de configuração já salvos, com a data e o aparelho de onde vieram. Só leitura.',
          'argv' => ['backup.sh', 'list']]);

    $add(['id' => 'snapshot_save', 'group' => 'Geral', 'card' => false, 'label' => 'Salvar snapshot',
          'desc' => 'Tira uma foto das configurações atuais para poder voltar depois.',
          'help' => 'Guarda o estado atual das configurações num "snapshot". Se algo der errado, você restaura essa foto e volta exatamente como estava. Faça isso ANTES de mexer em qualquer coisa.',
          'argv' => ['snapshot.sh', 'save']]);

    // ----- DNS (perfis) -----
    // Espelha o catálogo de scripts/dns.sh (hostnames DoT verificados).
    $dns = [
        'cloudflare'        => ['Cloudflare', 'Privacidade e velocidade, sem registro.'],
        'quad9'             => ['Quad9', 'Privacidade e bloqueio de sites maliciosos.'],
        'adguard'           => ['AdGuard', 'Bloqueia anúncios e rastreadores.'],
        'adguard-family'    => ['AdGuard Família', 'Anúncios + bloqueio de conteúdo adulto.'],
        'adguard-unfiltered' => ['AdGuard sem filtro', 'Só privacidade, sem bloquear nada.'],
        'cloudflare-family' => ['Cloudflare Família', 'Bloqueia conteúdo adulto.'],
        'cloudflare-security' => ['Cloudflare Segurança', 'Bloqueia malware e phishing.'],
        'mullvad'           => ['Mullvad', 'Privacidade sem registro (anônimo).'],
        'mullvad-base'      => ['Mullvad Base', 'Ads + rastreadores + malware.'],
        'mullvad-adblock'   => ['Mullvad Ads', 'Ads + rastreadores.'],
        'mullvad-family'    => ['Mullvad Família', 'Adulto + apostas.'],
        'mullvad-extended'  => ['Mullvad Estendido', 'Ads + malware + redes sociais.'],
        'mullvad-all'       => ['Mullvad Tudo', 'Bloqueio máximo (tudo junto).'],
        'dnsforge'          => ['DNSForge', 'Bloqueia anúncios, sem guardar logs.'],
        'google'            => ['Google', 'Compatibilidade máxima com qualquer rede.'],
        'nextdns'           => ['NextDNS', 'Filtragem e privacidade configuráveis.'],
        'opendns'           => ['OpenDNS', 'Cisco OpenDNS: estável e confiável.'],
        'opendns-family'    => ['OpenDNS Família', 'FamilyShield: bloqueia conteúdo adulto.'],
        'cleanbrowsing-family'   => ['CleanBrowsing Família', 'Bloqueia conteúdo adulto e malware.'],
        'cleanbrowsing-security' => ['CleanBrowsing Segurança', 'Bloqueia só phishing e malware.'],
        'cleanbrowsing-adult'    => ['CleanBrowsing Adulto', 'Bloqueia somente conteúdo adulto.'],
        'controld-unfiltered' => ['ControlD sem filtro', 'ControlD sem bloquear nada.'],
        'controld-malware'  => ['ControlD Malware', 'Bloqueia só malware.'],
        'controld-ads'      => ['ControlD Ads', 'Malware + anúncios.'],
        'controld-social'   => ['ControlD + Redes', 'Malware + anúncios + redes sociais.'],
        'controld-family'   => ['ControlD Família', 'Adulto + drogas.'],
        'controld-oisd'     => ['ControlD + OISD', 'Lista OISD (bloqueio forte de ads).'],
        'dns4eu-protective' => ['DNS4EU Protetor', 'Malware/phishing, infraestrutura da UE.'],
        'dns4eu-child'      => ['DNS4EU Infantil', 'Proteção + conteúdo impróprio p/ criança.'],
        'dns4eu-noads'      => ['DNS4EU sem Ads', 'Proteção + sem anúncios.'],
        'dns4eu-child-noads' => ['DNS4EU Infantil + Ads', 'Criança + sem anúncios.'],
        'dns4eu-unfiltered' => ['DNS4EU sem filtro', 'Sem filtro, só privacidade/jurisdição.'],
        'dns-sb'            => ['DNS.SB', 'Alemanha, sem logs, DNSSEC.'],
        'cz-nic'            => ['CZ.NIC ODVR', 'Tchéquia, valida DNSSEC.'],
        'digitale-gesellschaft' => ['Digitale Gesellschaft', 'Suíça, sem logs, DNSSEC, TLS 1.3.'],
        'restena'           => ['RESTENA', 'Luxemburgo, sem logs.'],
        'applied-privacy'   => ['Applied Privacy', 'Áustria, sem logs.'],
        'uncensored'        => ['UncensoredDNS', 'Dinamarca, sem filtro nem censura.'],
        'gaming'            => ['Gaming', 'Baixa latência para jogos + rede otimizada.'],
    ];
    // Perfis da escolha rápida de DNS (os "conhecidos" de cada finalidade).
    // O 3º campo é o host DoT (igual ao de dns.sh) — o painel compara com o
    // host atual para marcar "Em uso".
    $dns_quick = [
        'cloudflare' => ['Cloudflare', 'Privacidade + velocidade. O mais equilibrado.', 'one.one.one.one'],
        'google'     => ['Google', 'Compatibilidade máxima com qualquer rede.', 'dns.google'],
        'quad9'      => ['Quad9', 'Privacidade + bloqueio de malware.', 'dns.quad9.net'],
        'adguard'    => ['AdGuard', 'Bloqueia anúncios e rastreadores.', 'dns.adguard-dns.com'],
        'mullvad-all' => ['Mullvad Tudo', 'Bloqueio máximo (ads + malware + família).', 'all.dns.mullvad.net'],
        'opendns-family' => ['OpenDNS Família', 'Bloqueia conteúdo adulto.', 'familyshield.opendns.com'],
        'gaming'     => ['Gaming', 'Baixa latência para jogos + rede otimizada.', 'one.one.one.one'],
    ];
    foreach ($dns as $k => $v) {
        $row = ['id' => "dns.$k", 'group' => 'DNS e rede', 'label' => $v[0], 'desc' => $v[1],
              'help' => 'DNS é o serviço que "traduz" endereços de sites. Um DNS privado (DoT) deixa sua navegação mais rápida, privada e pode bloquear anúncios/malware. Escolha um perfil e ele passa a valer para o aparelho todo. Volte ao normal em "DNS automático".',
              'argv' => ['dns.sh', $k]];
        if (isset($dns_quick[$k])) {
            $row['choice'] = 'dns_fast';
            $row['option'] = $v[0];
            $row['state_value'] = $dns_quick[$k][2];   // host DoT (marca "Em uso")
        }
        $add($row);
    }
    $add(['id' => 'dns.custom', 'group' => 'DNS e rede', 'label' => 'DNS personalizado (host DoT)',
          'desc' => 'Use qualquer hostname de DNS-over-TLS que você quiser.',
          'help' => 'Se você já tem um DNS privado favorito, digite aqui o hostname (ex.: dns.exemplo.com). Ele será usado como DNS do aparelho, com criptografia.',
          'argv' => ['dns.sh', 'custom', '{host}'],
          'params' => [['name' => 'host', 'type' => 'host', 'label' => 'Hostname DoT']]]);
    $add(['id' => 'dns.off', 'group' => 'DNS e rede', 'label' => 'DNS automático (desligar)',
          'desc' => 'Volta o DNS para o padrão da operadora.',
          'help' => 'Desliga o DNS privado e devolve o aparelho para o DNS automático da sua operadora/rede. Use se algum site parar de abrir.',
          'argv' => ['dns.sh', 'off']]);
    $add(['id' => 'dns.bench', 'group' => 'DNS e rede', 'label' => 'Benchmark de DNS',
          'desc' => 'Mede a latência de cada perfil de DNS.',
          'help' => 'Testa a latência (tempo de resposta) dos principais servidores de DNS e mostra qual está mais rápido na sua rede. Não altera nada — é só medição.',
          'argv' => ['dns.sh', 'bench'], 'timeout' => 180]);

    // ----- Latência / Ping (o que muda o ping de verdade) -----
    $add(['id' => 'latency.on', 'group' => 'Latência e ping', 'label' => 'Reduzir latência / ping',
          'desc' => 'Ajusta congestion control, buffers e low latency para o ping cair.',
          'help' => 'Ataque direto no atraso da rede: liga o congestion control BBR (quando o kernel tem), encurta os buffers de envio, liga o modo low latency e o ECN para o aparelho não esperar encher o pacote nem retransmitir à toa. O resultado aparece no ping do jogo (menos "trava" e menos atraso no tiro). Tudo reversível em "Latência: restaurar".',
          'argv' => ['adb-tweaks.sh', 'latency'], 'confirm' => true, 'risk' => 'careful', 'timeout' => 120]);
    $add(['id' => 'latency.off', 'group' => 'Latência e ping', 'label' => 'Latência: restaurar',
          'desc' => 'Devolve os parâmetros de rede do kernel ao padrão.',
          'help' => 'Desfaz os ajustes de latência, devolvendo o congestion control e os buffers ao padrão do aparelho. Reinicie o aparelho depois para o kernel reavaliar.',
          'argv' => ['adb-tweaks.sh', 'latency_reset']]);

    // ----- Limite de processos em segundo plano (Dev Options) -----
    // A ação que faltava: no Android 10+ o "Limite de processos em segundo plano"
    // mora em `device_config activity_manager max_cached_processes` — o pack
    // antes escrevia só no setting e o aparelho continuava em "Padrão".
    $add(['id' => 'proc.limit.status', 'group' => 'Processos', 'label' => 'Limite de processos: ver',
          'desc' => 'Mostra o valor REAL lido do aparelho (não o que o pack escreveu).',
          'help' => 'Mostra o limite de processos em segundo plano que está valendo de verdade no aparelho, lido de volta do sistema. Se aparecer "padrão", é porque o Android está no automático — o que era o problema antigo: o pack escrevia o valor e o aparelho ignorava.',
          'argv' => ['adb-tweaks.sh', 'proc_limit', 'status']]);
    $add(['id' => 'proc.limit.4', 'group' => 'Processos', 'label' => 'Limite de processos: 4 (jogo)',
          'desc' => 'Só 4 apps em segundo plano: mais RAM e CPU para o jogo.',
          'help' => 'Limita o aparelho a manter apenas 4 apps em segundo plano. Sobra mais memória e processador para o jogo, que é o que mais importa em partida. O valor é escrito onde o Android 10+ realmente lê e conferido na hora. Reverta em "Limite de processos: padrão".',
          'choice' => 'proclimit', 'option' => '4 (jogo)', 'state_value' => '4',
          'argv' => ['adb-tweaks.sh', 'proc_limit', '4'], 'confirm' => true, 'risk' => 'careful']);
    $add(['id' => 'proc.limit.8', 'group' => 'Processos', 'label' => 'Limite de processos: 8 (equilíbrio)',
          'desc' => 'Oito apps em segundo plano: equilíbrio entre jogar e multitarefa.',
          'help' => 'Deixa o sistema manter 8 apps em segundo plano: bom meio-termo entre liberar RAM para o jogo e ainda conseguir alternar entre apps sem eles recarregarem. Reverta em "Limite de processos: padrão".',
          'choice' => 'proclimit', 'option' => '8 (equilíbrio)', 'state_value' => '8',
          'argv' => ['adb-tweaks.sh', 'proc_limit', '8'], 'risk' => 'careful']);
    $add(['id' => 'proc.limit.32', 'group' => 'Processos', 'label' => 'Limite de processos: 32 (multitarefa)',
          'desc' => 'Muitos apps em segundo plano: prioriza o dia a dia.',
          'help' => 'Deixa o sistema manter até 32 apps em segundo plano. Alternar entre apps fica instantâneo, mas sobra menos RAM para o jogo. É o padrão de fábrica do Android. Reverta em "Limite de processos: padrão".',
          'choice' => 'proclimit', 'option' => '32 (multitarefa)', 'state_value' => '32',
          'argv' => ['adb-tweaks.sh', 'proc_limit', '32'], 'risk' => 'careful']);
    $add(['id' => 'proc.limit.off', 'group' => 'Processos', 'label' => 'Limite de processos: padrão',
          'desc' => 'Devolve a decisão ao sistema (automático).',
          'help' => 'Apaga o limite que o pack escreveu e devolve a decisão ao Android (que passa a calcular sozinho conforme a memória). Use se algum app parou de ficar aberto em segundo plano.',
          'choice' => 'proclimit', 'option' => 'Padrão (automático)', 'state_value' => 'padrão',
          'argv' => ['adb-tweaks.sh', 'proc_limit', 'padrao']]);

    // ----- Gerador de sensi (só leitura: calcula para o SEU aparelho) -----
    $add(['id' => 'overlay.sensi', 'group' => 'Flutuante', 'label' => 'Painel flutuante sobre o jogo',
          'desc' => 'Mostra a sensi e os perfis de toque por cima do jogo, sem sair da partida.',
          'help' => 'Abre o painel flutuante: uma janela arrastável que fica por cima do jogo com a sensi calculada para o seu aparelho (Geral, Ponto vermelho, mira 2x, 4x, AWM e o tamanho do botão de atirar), os cinco perfis de toque (Equilibrado, Headshot, Spray, Sniper, Speed) e atalhos de latência e limpeza de RAM. Assim você confere e troca o ajuste sem fechar o jogo. Na primeira vez o Android pede a permissão "aparecer por cima de outros apps". Toque de novo no botão para desligar.',
          'argv' => [], 'ui' => 'overlay']);
    $add(['id' => 'sensi.calc', 'group' => 'Display & Touch', 'label' => 'Gerar sensi do meu aparelho',
          'desc' => 'Calcula a sensi ideal para o seu aparelho, sem alterar nada.',
          'help' => 'Lê o seu aparelho (resolução, densidade/DPI, tamanho da tela, taxa de toque, taxa de atualização, SoC, RAM e o ajuste de toque já aplicado) e calcula uma sensi sob medida: Geral, Ponto vermelho, mira 2x, 4x, AWM, além do tamanho do botão de atirar (com teto de 50%, que é o que não deixa o botão feio/grande). NÃO altera nada no aparelho: só mostra os números para você digitar no jogo. Rode de novo se mudar a resolução.',
          'argv' => ['sensi.sh', 'calc'], 'timeout' => 90]);
    $add(['id' => 'sensi.analyze', 'group' => 'Display & Touch', 'label' => 'Sensi: ver o que foi lido',
          'desc' => 'Mostra as leituras e os fatores usados no cálculo da sensi.',
          'help' => 'Transparência total: mostra exatamente o que o gerador leu do seu aparelho (tela, DPI, polegadas, toque, Hz, SoC, RAM) e quais fatores aplicou em cada item. Assim você entende por que a sensi saiu daquele valor. Só leitura.',
          'argv' => ['sensi.sh', 'analyze'], 'timeout' => 90]);
    $add(['id' => 'sensi.headshot', 'group' => 'Display & Touch', 'label' => 'Sensi: perfil headshot',
          'desc' => 'Recalcula a sensi com foco em mira rápida na cabeça.',
          'help' => 'Mesma conta do gerador, com o perfil headshot: mira mais ágil para pegar a cabeça. Mostra os valores para digitar no jogo. Só leitura, nada é alterado no aparelho.',
          'argv' => ['sensi.sh', 'calc', 'headshot'], 'timeout' => 90]);
    $add(['id' => 'sensi.spray', 'group' => 'Display & Touch', 'label' => 'Sensi: perfil spray',
          'desc' => 'Recalcula a sensi com foco em controle de recuo.',
          'help' => 'Mesma conta do gerador, com o perfil spray: controle melhor no tiro contínuo (segurar o dedo atirando). Mostra os valores para digitar no jogo. Só leitura.',
          'argv' => ['sensi.sh', 'calc', 'spray'], 'timeout' => 90]);
    $add(['id' => 'sensi.sniper', 'group' => 'Display & Touch', 'label' => 'Sensi: perfil sniper',
          'desc' => 'Recalcula a sensi com foco em mira precisa de longe.',
          'help' => 'Mesma conta do gerador, com o perfil sniper: mira mais lenta e precisa para longa distância (AWM, mira 4x). Mostra os valores para digitar no jogo. Só leitura.',
          'argv' => ['sensi.sh', 'calc', 'sniper'], 'timeout' => 90]);
    $add(['id' => 'sensi.speed', 'group' => 'Display & Touch', 'label' => 'Sensi: perfil speed',
          'desc' => 'Recalcula a sensi com foco em reação máxima.',
          'help' => 'Mesma conta do gerador, com o perfil speed: resposta o mais rápida possível, para quem joga agressivo e vira rápido. Mostra os valores para digitar no jogo. Só leitura.',
          'argv' => ['sensi.sh', 'calc', 'speed'], 'timeout' => 90]);
    $add(['id' => 'sensi.ff', 'group' => 'Display & Touch', 'label' => 'Sensi: valores na ordem do FF',
          'desc' => 'Imprime só os números, na ordem da tela do Free Fire.',
          'help' => 'Imprime os cinco valores separados por espaço (Geral, Ponto vermelho, 2x, 4x, AWM) na mesma ordem em que o Free Fire pede, para você digitar rápido sem procurar. Só leitura.',
          'argv' => ['sensi.sh', 'ff'], 'timeout' => 90]);

    // ----- RAM / Limpeza -----
    $add(['id' => 'mem.padrao', 'group' => 'Desempenho', 'label' => 'RAM: perfil padrão',
          'desc' => 'Multitarefa: mantém mais apps prontos na memória (32 em cache).',
          'help' => 'Ajusta quantos apps o sistema pode manter na memória. O perfil padrão guarda mais apps abertos (bom para o dia a dia, alternar entre apps é mais rápido).',
          'argv' => ['adb-tweaks.sh', 'mem', 'padrao']]);
    $add(['id' => 'mem.gaming', 'group' => 'Desempenho', 'label' => 'RAM: perfil gaming',
          'desc' => 'Libera mais RAM para o jogo (só 8 apps em cache).',
          'help' => 'Deixa o sistema manter menos apps na memória para sobrar mais RAM para o jogo. Resultado: menos engasgo em partidas. Trade-off: alternar entre apps fica um pouco mais lento.',
          'argv' => ['adb-tweaks.sh', 'mem', 'gaming']]);
    $add(['id' => 'clean', 'group' => 'Desempenho', 'label' => 'Limpar cache e RAM',
          'desc' => 'Libera RAM de verdade (fundo + cache) e suaviza a interface.',
          'help' => 'Motor único de limpeza: encerra os apps que estão rodando atrás (sem tocar no jogo nem nos protegidos no anti-relog), poda o cache de todos os apps e libera a memória na hora. Depois aplica uma suavização leve e reversível (animações mais curtas, blur off, doze mais rápido). Nada de seus dados é apagado — só cache. Para reverter a suavização, use "Clean: desfazer suavização".',
          'argv' => ['adb-tweaks.sh', 'clean']]);
    $add(['id' => 'clean.scan', 'group' => 'Desempenho', 'label' => 'Clean: ver o que dá para limpar',
          'desc' => 'Mostra RAM e espaço livre — sem alterar nada.',
          'help' => 'Só lê o aparelho: quanto de RAM está livre, quanto espaço sobra no armazenamento. Serve para você ver o que a limpeza vai liberar antes de rodar. Não altera nada.',
          'argv' => ['adb-tweaks.sh', 'clean_scan']]);
        $add(['id' => 'clean.undo', 'group' => 'Desempenho', 'label' => 'Clean: desfazer suavização',
          'desc' => 'Desfaz os ajustes de suavização do Clean (a limpeza é pontual).',
          'help' => 'Restaura animações, blur, doze e Wi-Fi, voltando cada valor ao original. A liberação de RAM em si não precisa ser desfeita (é pontual).',
          'argv' => ['clean.sh', 'off']]);

    // ----- Liberar RAM de verdade + Resfriamento -----
    $add(['id' => 'ram.normal', 'group' => 'Desempenho', 'label' => 'Liberar RAM: normal',
          'desc' => 'Encerra o fundo, poda cache e solta pagecache. Mostra o ganho.',
          'help' => 'Libera memória na hora: encerra os apps que estão rodando atrás (sem tocar no jogo nem nos que você protegeu no anti-relog), apaga o cache de todos os apps e, com root, manda o kernel soltar o pagecache. Diferente de "RAM: perfil gaming" — aqui a RAM é liberada de verdade. O resultado mostra quantos MB sobraram.',
          'choice' => 'ramboost', 'option' => 'Normal',
          'argv' => ['ram-boost.sh', 'boost', 'normal'], 'risk' => 'careful', 'confirm' => true, 'timeout' => 120]);
    $add(['id' => 'ram.max', 'group' => 'Desempenho', 'label' => 'Liberar RAM: máximo',
          'desc' => 'Igual ao normal e ainda encerra apps de mídia/chat conhecidos.',
          'help' => 'A versão mais agressiva: além de tudo do normal, encerra também apps de mídia e chat conhecidos (Spotify, Discord, YouTube, Netflix, Twitch). Sobra o máximo de RAM. Use só quando quiser o aparelho 100% livre.',
          'choice' => 'ramboost', 'option' => 'Máximo',
          'argv' => ['ram-boost.sh', 'boost', 'max'], 'risk' => 'careful', 'confirm' => true, 'timeout' => 120]);
    $add(['id' => 'ram.status', 'group' => 'Desempenho', 'label' => 'Ver RAM livre',
          'desc' => 'Mostra a RAM em uso e quem está protegido. Só leitura.',
          'help' => 'Mostra quanta RAM está livre e em uso, o perfil de RAM em cache e quais apps estão protegidos no anti-relog. Tudo lido do aparelho.',
          'argv' => ['ram-boost.sh', 'status']]);
                
    // ----- Renderizador -----
    $add(['id' => 'gpu', 'group' => 'Display & Touch', 'label' => 'Aplicar conjunto GPU',
          'desc' => 'Renderizador + força GPU + remove desfoques.',
          'help' => 'Pacote gráfico completo: usa a GPU para desenhar a interface, remove os efeitos de desfoque (blur) que pesam e liga o driver de jogo. Deixa a navegação mais fluida.',
          'argv' => ['adb-tweaks.sh', 'gpu']]);
    $add(['id' => 'gpu.auto', 'group' => 'Display & Touch', 'label' => 'Renderizador: Automático (padrão)',
          'desc' => 'O sistema escolhe o melhor motor para o seu aparelho.',
          'help' => 'Devolve a decisão ao Android: o próprio sistema usa SkiaGL ou Skia Vulkan conforme o aparelho (no Android 10+ não existe mais o motor OpenGL). É a opção mais segura — use se algum app ficar com tela estranha nos outros modos.',
          'choice' => 'renderer', 'option' => 'Automático', 'state_value' => '', 'state_auto' => true,
          'argv' => ['adb-tweaks.sh', 'renderer', 'auto']]);
    $add(['id' => 'gpu.skiagl', 'group' => 'Display & Touch', 'label' => 'Renderizador: SkiaGL',
          'desc' => 'Skia sobre OpenGL. Equilíbrio entre fluidez e compatibilidade.',
          'help' => 'Usa a biblioteca Skia (mais moderna) rodando sobre OpenGL ES. É o motor padrão na maioria dos aparelhos e o mais compatível. Use se o Vulkan der problema.',
          'choice' => 'renderer', 'option' => 'SkiaGL', 'state_value' => 'skiagl',
          'argv' => ['adb-tweaks.sh', 'renderer', 'skiagl']]);
    $add(['id' => 'gpu.skiavk', 'group' => 'Display & Touch', 'label' => 'Renderizador: Skia Vulkan',
          'desc' => 'Skia sobre Vulkan. Costuma dar mais fluidez.',
          'help' => 'Usa Skia sobre Vulkan, a API gráfica mais moderna. Em aparelhos compatíveis dá a interface mais fluida. Se algum app travar ou mostrar artefatos, volte para "Automático" ou SkiaGL.',
          'choice' => 'renderer', 'option' => 'Skia Vulkan', 'state_value' => 'skiavk',
          'argv' => ['adb-tweaks.sh', 'renderer', 'skiavk']]);
    $add(['id' => 'gpu.skiagl_threaded', 'group' => 'Display & Touch', 'label' => 'Renderizador: SkiaGL multithread',
          'desc' => 'SkiaGL desenhando numa thread separada. Mais suave.',
          'help' => 'Usa SkiaGL e move a composição para uma thread separada (backend "skiaglthreaded"). Costuma deixar a rolagem mais suave em telas de alta taxa. O backend do compositor só passa a valer depois de REINICIAR o aparelho. É mais exigente: se esquentar ou instabilizar, volte para SkiaGL.',
          'choice' => 'renderer', 'option' => 'SkiaGL multithread', 'state_value' => 'skiagl', 'state_backend_value' => 'skiaglthreaded',
          'argv' => ['adb-tweaks.sh', 'renderer', 'skiagl-threaded']]);
    $add(['id' => 'gpu.skiavk_threaded', 'group' => 'Display & Touch', 'label' => 'Renderizador: Skia Vulkan multithread',
          'desc' => 'Skia Vulkan em thread separada. Máxima fluidez.',
          'help' => 'Usa Skia Vulkan com a composição numa thread separada (backend "skiavkthreaded"). O backend do compositor só passa a valer depois de REINICIAR o aparelho. É o modo mais fluido em aparelhos compatíveis, mas também o mais sensível ao driver. Se a tela piscar ou travar, volte para Skia Vulkan ou Automático.',
          'choice' => 'renderer', 'option' => 'Skia Vulkan multithread', 'state_value' => 'skiavk', 'state_backend_value' => 'skiavkthreaded',
          'argv' => ['adb-tweaks.sh', 'renderer', 'skiavk-threaded']]);
    $add(['id' => 'gpu.opengl', 'group' => 'Display & Touch', 'label' => 'Renderizador: OpenGL (só Android antigo)',
          'desc' => 'Motor antigo. Só funciona até o Android 9.',
          'help' => 'Força o motor OpenGL, que existia até o Android 9. No Android 10 ou mais novo ele foi REMOVIDO do sistema — a ação recusa em vez de fingir que aplicou. Em aparelhos antigos é o mais compatível.',
          'choice' => 'renderer', 'option' => 'OpenGL (antigo)', 'state_value' => 'opengl',
          'argv' => ['adb-tweaks.sh', 'renderer', 'opengl']]);
    $add(['id' => 'gpu.force', 'group' => 'Display & Touch', 'label' => 'Forçar renderização por GPU',
          'desc' => 'Usa a GPU para desenhar a interface (não a CPU).',
          'help' => 'Faz a interface ser desenhada pela GPU em vez da CPU. Isso libera a CPU para outras tarefas e deixa a rolagem mais suave.',
          'argv' => ['adb-tweaks.sh', 'raw', 'settings put global force_gpu_rendering 1']]);

    // ----- Motor gráfico por app (escolha o app e o driver) -----
    $add(['id' => 'app.render', 'group' => 'Display & Touch', 'label' => 'Escolher driver do app',
          'desc' => 'Escolha o app e o driver gráfico que ele deve usar.',
          'help' => 'Escolhe o driver gráfico de um app específico: ANGLE (OpenGL ES sobre Vulkan, costuma render mais FPS), Nativo (força o driver OpenGL ES do fabricante) ou Padrão (o sistema decide). É a mesma opção de "Driver gráfico" das Opções de desenvolvedor, mas aqui por app e sem root. Reabra o app depois.',
          'choice' => 'renderapp', 'option' => 'Driver do app',
          'argv' => ['deep-tune.sh', 'angle', 'set', '{pkg}', '{driver}'],
          'params' => [
              ['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo'],
              ['name' => 'driver', 'type' => 'enum', 'label' => 'Driver', 'options' => ['angle', 'native', 'default'], 'default' => 'angle'],
          ]]);

    // ----- Motor gráfico do aparelho (driver do sistema) -----
    // São as opções de "Driver gráfico" das Opções de desenvolvedor. O painel lê
    // o estado real (angle_all / game_driver_all / updatable_driver) e marca o
    // que está valendo — nada de mostrar a opção só porque foi tocada.
    $add(['id' => 'gfx.angle_all_on', 'group' => 'Display & Touch', 'label' => 'Motor gráfico: ANGLE em TODOS os apps',
          'desc' => 'Todos os apps passam a usar ANGLE (OpenGL ES sobre Vulkan).',
          'help' => 'Liga o ANGLE para todos os apps de uma vez, em vez de configurar um por um. Em aparelhos compatíveis, o ANGLE costuma dar mais FPS porque traduz o OpenGL para Vulkan. Se algum app ficar com gráfico estranho, volte em "ANGLE só por app".',
          'argv' => ['deep-tune.sh', 'gfxdriver', 'angle_all', 'on']]);
    $add(['id' => 'gfx.angle_all_off', 'group' => 'Display & Touch', 'label' => 'Motor gráfico: ANGLE só por app',
          'desc' => 'Devolve a escolha do driver para cada app (padrão).',
          'help' => 'Desliga o ANGLE global e devolve a decisão ao sistema e à lista por app. Use se você notou apps com gráfico estranho depois de ligar o ANGLE em todos.',
          'argv' => ['deep-tune.sh', 'gfxdriver', 'angle_all', 'off']]);
    $add(['id' => 'gfx.gamedriver_on', 'group' => 'Display & Touch', 'label' => 'Motor gráfico: driver de jogo (todos)',
          'desc' => 'Usa o driver gráfico de jogos do fabricante em todos os apps.',
          'help' => 'Liga o driver gráfico de jogos do fabricante (o mesmo "Driver de jogos" das Opções de desenvolvedor) para todos os apps. Alguns fabricantes entregam um driver mais novo por aqui; outros não expõem nada, e aí o ajuste não muda nada no aparelho — o painel avisa quando isso acontece.',
          'argv' => ['deep-tune.sh', 'gfxdriver', 'gamedriver', 'on']]);
    $add(['id' => 'gfx.gamedriver_off', 'group' => 'Display & Touch', 'label' => 'Motor gráfico: driver de jogo off',
          'desc' => 'Desliga o driver de jogos em todos os apps.',
          'help' => 'Desliga o driver gráfico de jogos do fabricante. Use se o aparelho ficou instável ou esquentando depois de ligar.',
          'argv' => ['deep-tune.sh', 'gfxdriver', 'gamedriver', 'off']]);
    $add(['id' => 'gfx.updatable_pre', 'group' => 'Display & Touch', 'label' => 'Motor gráfico: driver em pré-lançamento',
          'desc' => 'Pede ao sistema o driver gráfico mais novo (pré-lançamento).',
          'help' => 'Pede ao Android para usar o driver gráfico atualizável mais novo, em pré-lançamento (o mesmo "Driver atualizável do sistema" das Opções de desenvolvedor). Só tem efeito se o aparelho tiver um driver atualizável instalado; sem ele, nada muda e o painel informa.',
          'argv' => ['deep-tune.sh', 'gfxdriver', 'updatable', 'pre']]);
    $add(['id' => 'gfx.updatable_prod', 'group' => 'Display & Touch', 'label' => 'Motor gráfico: driver do sistema',
          'desc' => 'Volta a usar o driver gráfico estável do sistema.',
          'help' => 'Devolve a escolha do driver atualizável para o driver estável do sistema (produção), em vez do pré-lançamento. Reverta aqui se o pré-lançamento causou travamento ou artefato.',
          'argv' => ['deep-tune.sh', 'gfxdriver', 'updatable', 'producao']]);
    $add(['id' => 'gfx.status', 'group' => 'Display & Touch', 'label' => 'Motor gráfico: ver estado real',
          'desc' => 'Mostra o driver gráfico que está realmente em uso.',
          'help' => 'Mostra, lido do aparelho: se o ANGLE está ligado em todos os apps, se o driver de jogos está ligado, qual driver atualizável está escolhido e qual driver gráfico está instalado. Só leitura — nada fictício.',
          'argv' => ['deep-tune.sh', 'gfxdriver', 'status']]);

    // ----- Gráficos e toque (novos toggles, SEM root) -----
    $add(['id' => 'gfx.comp_on', 'group' => 'Display & Touch', 'label' => 'Composição gráfica enxuta',
          'desc' => 'Menos camadas por frame: menos buffer intermediário e sem blur.',
          'help' => 'Enxuga a composição: cada camada a menos é uma composição a menos por frame. São flags do sistema que valem sem root e continuam valendo depois de reiniciar (não é prop, que some no reboot). Combine com "Motor gráfico" para o resultado máximo. Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'gfx_comp']]);
    $add(['id' => 'gfx.comp_off', 'group' => 'Display & Touch', 'label' => 'Composição gráfica: padrão',
          'desc' => 'Devolve a composição ao padrão de fábrica.',
          'help' => 'Devolve as flags de composição (draw defer, scissor, buffer age, blur) ao padrão de fábrica.',
          'argv' => ['adb-tweaks.sh', 'gfx_comp_off']]);
    $add(['id' => 'gfx.fpsdaemon_on', 'group' => 'Display & Touch', 'label' => 'Travar a taxa da tela (sem daemon de FPS)',
          'desc' => 'Fixa a taxa no maior Hz da tela: o jogo não oscila de FPS.',
          'help' => 'Em vez de deixar o sistema oscilar a taxa (60 -> 90 -> 120) conforme a carga, fixa mín = máx no maior Hz que a SUA tela suporta. O jogo para de "cair" de FPS e a composição não reconfigura o modo de vídeo no meio da partida. Usa a lista do próprio aparelho, não inventa Hz. Reversível em "Daemon de FPS: automático".',
          'argv' => ['adb-tweaks.sh', 'fps_daemon', 'on']]);
    $add(['id' => 'gfx.fpsdaemon_off', 'group' => 'Display & Touch', 'label' => 'Daemon de FPS: automático',
          'desc' => 'Devolve a taxa da tela ao controle do sistema.',
          'help' => 'Apaga a taxa fixa e o sistema volta a escolher a taxa sozinho (modo automático).',
          'argv' => ['adb-tweaks.sh', 'fps_daemon', 'off']]);
    $add(['id' => 'gfx.fpsdaemon_status', 'group' => 'Display & Touch', 'card' => false, 'label' => 'Daemon de FPS: ver a taxa',
          'desc' => 'Mostra a taxa mínima e máxima em uso agora.',
          'help' => 'Mostra a taxa mínima e a máxima da tela neste momento. Só leitura.',
          'argv' => ['adb-tweaks.sh', 'fps_daemon', 'status']]);
    $add(['id' => 'touch.resp_on', 'group' => 'Display & Touch', 'label' => 'Resposta ao toque: rápida',
          'desc' => 'Janelas curtas de toque: o sistema reage na hora.',
          'help' => 'Encurta as janelas do toque (responsividade, slop, multitouch e long-press). É o "atraso" entre o dedo e o sistema reagir — não troca o perfil de mira (isso fica nos perfis de sensibilidade). Reversível em "Resposta ao toque: padrão".',
          'argv' => ['adb-tweaks.sh', 'touch_resp', 'on']]);
    $add(['id' => 'touch.resp_off', 'group' => 'Display & Touch', 'label' => 'Resposta ao toque: padrão',
          'desc' => 'Devolve as janelas de toque ao padrão.',
          'help' => 'Apaga os ajustes de janela de toque e devolve o aparelho ao padrão.',
          'argv' => ['adb-tweaks.sh', 'touch_resp', 'off']]);
    $add(['id' => 'thermal.guard', 'group' => 'Desempenho', 'label' => 'Trava térmica (sem root)',
          'desc' => 'Lê a temperatura e alivia a carga se passar do teto.',
          'help' => 'A versão sem root da trava térmica: não reescreve limites do kernel (isso exige root). Ele LÊ a temperatura real do aparelho (sensor do sistema ou bateria) e, se passar do teto, alivia a carga — devolve a taxa de tela ao padrão e religa o blur. Use antes de uma sessão longa de jogo. O teto é configurável (padrão 43 °C).',
          'argv' => ['adb-tweaks.sh', 'thermal_guard', 'on', '{celsius}'],
          'params' => [['name' => 'celsius', 'type' => 'int', 'label' => 'Teto (°C)',
                         'min' => 35, 'max' => 60, 'default' => 43]]]);

    // ----- Taxa de atualização (Hz) — escolha rápida -----
    $add(['id' => 'refresh.60', 'group' => 'Display & Touch', 'label' => '60Hz (economia)',
          'desc' => 'Trava a tela em 60Hz. Menos bateria, frametime estável.',
          'help' => 'Trava a tela em 60Hz. É a taxa do dia a dia para quem não precisa de mais: gasta menos bateria e esquenta menos. Em jogo, uma taxa fixa evita a tela oscilar (60↔90Hz), o que causa micro-travada. Reverte em "Automático".',
          'choice' => 'refresh', 'option' => '60Hz', 'state_value' => '60.0',
          'argv' => ['turbo.sh', 'refresh_fixed', '60'], 'risk' => 'careful']);
    $add(['id' => 'refresh.90', 'group' => 'Display & Touch', 'label' => '90Hz',
          'desc' => 'Trava a tela em 90Hz. Um meio-termo.',
          'help' => 'Trava a tela em 90Hz: mais fluido que 60Hz, gastando um pouco mais de bateria que o normal. Só funciona se a tela do aparelho suportar 90Hz. Reverte em "Automático".',
          'choice' => 'refresh', 'option' => '90Hz', 'state_value' => '90.0',
          'argv' => ['turbo.sh', 'refresh_fixed', '90'], 'risk' => 'careful']);
    $add(['id' => 'refresh.120', 'group' => 'Display & Touch', 'label' => '120Hz (máximo)',
          'desc' => 'Trava a tela na taxa mais alta. Mais fluidez.',
          'help' => 'Trava a tela em 120Hz, a maior taxa da maioria dos aparelhos: rolagem e jogo mais lisos. Gasta mais bateria. Só funciona se a tela suportar 120Hz. Reverte em "Automático".',
          'choice' => 'refresh', 'option' => '120Hz', 'state_value' => '120.0',
          'argv' => ['turbo.sh', 'refresh_fixed', '120'], 'risk' => 'careful']);
    $add(['id' => 'refresh.auto', 'group' => 'Display & Touch', 'label' => 'Automático',
          'desc' => 'O sistema decide a taxa conforme a tela e a bateria.',
          'help' => 'Remove a trava e devolve a decisão da taxa de atualização ao Android: ele escolhe conforme a tela e a bateria. Use se quiser voltar ao comportamento de fábrica.',
          'choice' => 'refresh', 'option' => 'Automático',
          'argv' => ['turbo.sh', 'refresh', 'auto'], 'risk' => 'safe']);

    // ----- Renderizador por app (Vulkan/OpenGL/ANGLE) -----
    $add(['id' => 'app.angle', 'group' => 'Apps e jogos', 'label' => 'Usar ANGLE (OpenGL para Vulkan) no app',
          'desc' => 'Faz o app usar Vulkan no lugar do OpenGL. Escolha o app/jogo.',
          'help' => 'ANGLE traduz os comandos de OpenGL para Vulkan. Em muitos jogos isso melhora o desempenho. Escolha o app na lista (ex.: com.dts.freefireth). Se piorar, use "Tirar ANGLE do app".',
          'argv' => ['deep-tune.sh', 'angle', 'add', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.angle_remove', 'group' => 'Apps e jogos', 'label' => 'Tirar ANGLE do app',
          'desc' => 'Volta o app a usar o driver gráfico nativo.',
          'help' => 'Remove o ANGLE do app escolhido, devolvendo ele ao driver nativo do aparelho. Use se o jogo ficou instável ou com gráfico estranho.',
          'argv' => ['deep-tune.sh', 'angle', 'remove', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.angle_reset', 'group' => 'Apps e jogos', 'label' => 'Resetar ANGLE (todos)',
          'desc' => 'Remove a seleção de ANGLE de todos os apps de uma vez.',
          'help' => 'Limpa tudo: nenhum app fica mais usando ANGLE. Bom para recomeçar do zero quando você não lembra quais apps configurou.',
          'argv' => ['deep-tune.sh', 'angle', 'reset'], 'confirm' => true]);
    $add(['id' => 'app.perf', 'group' => 'Apps e jogos', 'label' => 'Modo performance no app',
          'desc' => 'Prioriza o app/jogo escolhido (Game Mode).',
          'help' => 'Pede ao sistema para tratar o app como jogo: mais prioridade de CPU/GPU e menos interrupções. Escolha o pacote do jogo (ex.: com.dts.freefireth).',
          'argv' => ['game-per-app.sh', 'mode', '{pkg}', 'performance'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'app.downscale', 'group' => 'Apps e jogos', 'label' => 'Reduzir resolução do jogo (FPS)',
          'desc' => 'Renderiza em resolução menor para ganhar FPS. 1.0 = nativo.',
          'help' => 'Diminui a resolução interna do jogo (0.3 a 1.0) mantendo o tamanho na tela. Menos pixels = mais FPS e menos aquecimento. 0.9 é quase imperceptível e já ajuda. Reinicie o jogo depois.',
          'argv' => ['game-per-app.sh', 'custom', '{pkg}', '{scale}'],
          'params' => [
              ['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo'],
              ['name' => 'scale', 'type' => 'float', 'label' => 'Downscale', 'min' => 0.3, 'max' => 1.0, 'step' => 0.05, 'default' => 0.9],
          ], 'confirm' => true]);
    $add(['id' => 'app.reset', 'group' => 'Apps e jogos', 'label' => 'Resetar tuning do app',
          'desc' => 'Remove overlay, ANGLE e modo do app escolhido.',
          'help' => 'Desfaz tudo o que foi aplicado só nesse app (ANGLE, resolução, modo de jogo), voltando ao normal.',
          'argv' => ['game-per-app.sh', 'reset', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);

    // ----- Menor largura / DPI (densidade) do telefone -----
    // É o MESMO ajuste das "Opções do desenvolvedor" (Menor largura), mas o
    // alvo é o número que o usuário vê no aparelho (largura em dp), não a
    // densidade. O painel mostra o valor atual e o padrão; a faixa é relativa
    // ao aparelho. Vale para o sistema inteiro e é reversível em "padrão".
    $add(['id' => 'dpi.custom', 'group' => 'Apps e jogos', 'label' => 'Menor largura (DPI da tela)',
          'desc' => 'Ajusta a largura da interface — o mesmo "Menor largura" do Android.',
          'help' => 'Muda a largura lógica da tela: o mesmo número que aparece em "Menor largura" nas Opções do desenvolvedor do seu Android. Menor valor = tudo menor (cabe mais coisa, HUD e botões menores, mais campo de visão); maior valor = tudo maior (bom em tela pequena ou vista cansada). Vale para o telefone inteiro e muda na hora. O painel mostra a largura em uso agora e o padrão do seu aparelho; digite o valor que quiser. Para voltar ao normal, use "Menor largura: padrão".',
          'argv' => ['game-per-app.sh', 'dpi', '{dpi}'],
          'params' => [['name' => 'dpi', 'type' => 'int', 'label' => 'Menor largura (dp)', 'min' => 200, 'max' => 1000, 'default' => 400]],
          'risk' => 'careful', 'confirm' => true]);
    $add(['id' => 'dpi.padrao', 'group' => 'Apps e jogos', 'label' => 'Menor largura: padrão',
          'desc' => 'Volta a largura da interface ao padrão do aparelho.',
          'help' => 'Remove o ajuste e devolve a largura da tela ao padrão de fábrica do seu aparelho. Use quando terminar de jogar ou se a interface ficou estranha.',
          'argv' => ['game-per-app.sh', 'dpi', 'padrao'],
          'risk' => 'safe']);

    // ----- Game Clean (deixa o jogo limpo e otimizado) -----
    $add(['id' => 'clean.normal', 'group' => 'Apps e jogos', 'label' => 'Game Clean: limpeza normal',
          'desc' => 'Fecha o fundo, limpa cache/RAM e otimiza o jogo escolhido.',
          'help' => 'Deixa o jogo "clean": encerra os apps que estavam rodando atrás (sem tocar no jogo nem nos que você protegeu no anti-relog), poda o cache e o dexopt, libera RAM, protege o jogo contra relog, liga o Game Mode em performance, silencia notificações e corta telemetria. É o "entrar em modo partida" completo. Reverta em "Game Clean: desligar".',
          'choice' => 'gameclean', 'option' => 'Normal',
          'argv' => ['game-clean.sh', 'on', '{pkg}'], 'risk' => 'careful', 'confirm' => true,
          'timeout' => 300,
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'clean.max', 'group' => 'Apps e jogos', 'label' => 'Game Clean: máximo',
          'desc' => 'Igual ao normal, e ainda encerra apps de mídia/chat conhecidos.',
          'help' => 'A versão mais agressiva: além de tudo do modo normal, encerra também os apps de mídia e chat conhecidos (Spotify, Discord, YouTube, Netflix, Twitch) para sobrar o máximo de RAM e CPU. Use só quando quiser o aparelho 100% para o jogo.',
          'choice' => 'gameclean', 'option' => 'Máximo',
          'argv' => ['game-clean.sh', 'on', '{pkg}', 'max'], 'risk' => 'careful', 'confirm' => true,
          'timeout' => 300,
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'clean.off', 'group' => 'Apps e jogos', 'label' => 'Game Clean: desligar',
          'desc' => 'Desfaz o Game Clean e devolve o jogo ao normal.',
          'help' => 'Desfaz tudo o que o Game Clean aplicou: religa as notificações, volta a RAM ao normal, tira o jogo do Game Mode e do anti-relog. Use quando terminar de jogar.',
          'argv' => ['game-clean.sh', 'off', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'clean.status', 'group' => 'Apps e jogos', 'label' => 'Game Clean: ver estado',
          'desc' => 'Mostra o que o Game Clean aplicou no jogo escolhido.',
          'help' => 'Mostra, lido do aparelho, se o jogo está isento do Doze, o balde de standby, se as notificações estão silenciadas, o limite de RAM em cache e se o anti-relog está ativo. Só leitura.',
          'argv' => ['game-clean.sh', 'status', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);

    // ----- Touch / Free Fire -----
    // 'state_match' = tr,lp,ps,slop de cada perfil. O painel compara com os
    // valores reais lidos do aparelho e marca o perfil em uso.
    $touch = [
        'balanced' => ['Equilibrado', 'Ajuste geral, bom para a maioria.', '100,400,0,8'],
        'headshot' => ['Headshot', 'Resposta mais rápida: mira ágil.', '110,350,0,4'],
        'spray'    => ['Spray', 'Mais controle de recuo no tiro contínuo.', '105,300,0,6'],
        'sniper'   => ['Sniper', 'Mira precisa e estável para longa distância.', '95,500,-1,10'],
        'speed'    => ['Speed', 'Máxima reatividade: resposta imediata.', '120,300,1,2'],
    ];
    foreach ($touch as $k => $v) {
        $add(['id' => "touch.$k", 'group' => 'Display & Touch', 'label' => "Touch: {$v[0]}",
              'desc' => $v[1],
              'help' => 'Ajusta a sensibilidade e o tempo de resposta do toque do sistema (vale para o jogo todo). Cada perfil muda a rapidez da mira e a suavidade. Teste um, jogue e veja qual combina com você. Reverta em "Restaurar touch".',
              'choice' => 'touchprofile', 'option' => $v[0], 'state_match' => 'touch:' . $v[2],
              'argv' => ['ff-touch.sh', $k], 'risk' => 'careful']);
    }
    $add(['id' => 'touch.custom', 'group' => 'Display & Touch', 'label' => 'Touch: personalizado',
          'desc' => 'Ajuste fino dos 4 parâmetros do toque.',
          'help' => 'Para quem quer calibrar na mão: responsiveness (rapidez da resposta), long press (tempo de toque longo), pointer speed (velocidade do ponteiro) e touch slop (quanto o dedo pode tremer antes de contar como arrasto).',
          'argv' => ['ff-touch.sh', 'custom', '{tr}', '{lp}', '{ps}', '{slop}'],
          'params' => [
              ['name' => 'tr', 'type' => 'int', 'label' => 'responsiveness', 'min' => 50, 'max' => 200, 'default' => 110, 'state' => 'touch_responsiveness'],
              ['name' => 'lp', 'type' => 'int', 'label' => 'long press (ms)', 'min' => 100, 'max' => 800, 'default' => 350, 'state' => 'long_press_timeout'],
              ['name' => 'ps', 'type' => 'int', 'label' => 'pointer speed', 'min' => -5, 'max' => 5, 'default' => 0, 'state' => 'pointer_speed'],
              ['name' => 'slop', 'type' => 'int', 'label' => 'touch slop', 'min' => 0, 'max' => 30, 'default' => 4, 'state' => 'touch_slop'],
          ], 'risk' => 'careful']);
    $add(['id' => 'touch.restore', 'group' => 'Display & Touch', 'label' => 'Restaurar touch',
          'desc' => 'Apaga os ajustes de toque e volta ao padrão.',
          'help' => 'Remove todos os ajustes de sensibilidade/toque, devolvendo o toque ao padrão do aparelho.',
          'argv' => ['ff-touch.sh', 'restore']]);
    $add(['id' => 'touch.multi', 'group' => 'Display & Touch', 'label' => 'Toque: janela multitouch',
          'desc' => 'Define a janela de resposta com vários dedos (100–800 ms).',
          'help' => 'Define quanto tempo o sistema espera ao usar vários dedos. Menor = resposta mais imediata quando você usa 3–4 dedos (evita o toque "atrasar" no meio da ação). 100ms é o mais reativo; 800ms o mais tolerante. Reinicie o jogo depois.',
          'argv' => ['adb-tweaks.sh', 'touch_multi', '{ms}'],
          'params' => [['name' => 'ms', 'type' => 'int', 'label' => 'Milissegundos', 'min' => 100, 'max' => 800, 'default' => 300]],
          'risk' => 'careful']);
    $add(['id' => 'touch.latency', 'group' => 'Display & Touch', 'label' => 'Toque: latência fina',
          'desc' => 'Ajuste direto da responsividade do toque (1–1000, menor = mais rápido).',
          'help' => 'Ajusta direto a "responsividade" do toque: quanto menor o número, mais rápido o sistema responde ao seu dedo (e mais sensível fica). Deixe os outros campos em branco para mudar só a responsividade. Reverta em "Restaurar touch". Reinicie o jogo depois.',
          'argv' => ['adb-tweaks.sh', 'touch_latency', '{tr}', '{lp}', '{ps}', '{slop}'],
          'params' => [
              ['name' => 'tr', 'type' => 'int', 'label' => 'responsividade', 'min' => 1, 'max' => 1000, 'default' => 90],
              ['name' => 'lp', 'type' => 'int', 'label' => 'long press (ms)', 'min' => 50, 'max' => 1500, 'default' => 350],
              ['name' => 'ps', 'type' => 'int', 'label' => 'pointer speed', 'min' => -10, 'max' => 10, 'default' => 0],
              ['name' => 'slop', 'type' => 'int', 'label' => 'touch slop', 'min' => 0, 'max' => 50, 'default' => 4],
          ], 'risk' => 'careful']);
    $add(['id' => 'ff', 'group' => 'Apps e jogos', 'label' => 'Preparar e abrir o Free Fire',
          'desc' => 'Fecha apps de fundo, aplica o preset do FF e abre o jogo.',
          'help' => 'Prepara o aparelho para o Free Fire: fecha apps pesados que estavam abertos, aplica o modo de jogo e abre o FF. É o "entrar em modo partida" com um clique.',
          'argv' => ['adb-tweaks.sh', 'ff']]);
    $add(['id' => 'game_mode', 'group' => 'Apps e jogos', 'label' => 'Ligar Game Mode',
          'desc' => 'Ativa o modo de jogo do sistema.',
          'help' => 'Liga o modo de jogo do Android, que dá prioridade ao jogo em execução e segura interrupções. Vale para todos os jogos.',
          'argv' => ['adb-tweaks.sh', 'game']]);

    // ----- Performance / Tela / Bateria -----
    $add(['id' => 'gpu_off', 'group' => 'Display & Touch', 'card' => false, 'label' => 'Conjunto GPU: desligar',
          'desc' => 'Devolve a renderização por GPU e o driver de jogo ao sistema.',
          'help' => 'Desfaz o conjunto GPU: desliga a renderização forçada por GPU e o driver de jogo, devolvendo a decisão ao Android.',
          'argv' => ['adb-tweaks.sh', 'gpu_off']]);
    $add(['id' => 'perf', 'group' => 'Desempenho', 'card' => false, 'label' => 'Performance (animações 0.5x)',
          'desc' => 'Deixa as animações mais rápidas: interface parece mais ágil.',
          'help' => 'Reduz a duração das animações do sistema pela metade. O celular parece mais rápido sem mudar nada de verdade — só a sensação de velocidade melhora.',
          'argv' => ['adb-tweaks.sh', 'perf']]);
    $add(['id' => 'perf_max', 'group' => 'Desempenho', 'card' => false, 'label' => 'Performance extrema (animações 0)',
          'desc' => 'Remove as animações: transições instantâneas.',
          'help' => 'Desliga as animações de vez. Tudo abre instantaneamente. Ótimo para aparelhos lentos, mas o visual fica mais "seco".',
          'argv' => ['adb-tweaks.sh', 'perf_max']]);
    $add(['id' => 'perf_off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Performance: voltar ao padrão',
          'desc' => 'Devolve as animações ao tempo normal (1x).',
          'help' => 'Devolve as animações do sistema ao tempo de fábrica. Use quando quiser a interface "normal" de volta depois de acelerar.',
          'argv' => ['adb-tweaks.sh', 'perf_off']]);
    $add(['id' => 'fluidez', 'group' => 'Desempenho', 'card' => false, 'label' => 'Fluidez (toque + Hz + animações)',
          'desc' => 'Pacote geral de fluidez: toque, taxa de atualização e animações.',
          'help' => 'Combina vários ajustes que, juntos, deixam o uso mais fluido: resposta de toque melhor, taxa de atualização no máximo e animações mais rápidas. É o "tudo para fluidez".',
          'argv' => ['adb-tweaks.sh', 'fluidez']]);
    $add(['id' => 'fluidez_off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Fluidez: desligar',
          'desc' => 'Devolve animações, toque e taxa de tela ao padrão.',
          'help' => 'Desfaz o pacote de fluidez e devolve animações, janelas de toque e taxa de atualização ao padrão do aparelho.',
          'argv' => ['adb-tweaks.sh', 'fluidez_off']]);
    $add(['id' => 'dnd', 'group' => 'Desempenho', 'card' => false, 'label' => 'Não perturbe (DND)',
          'desc' => 'Silencia notificações durante o jogo.',
          'help' => 'Ativa o modo Não Perturbe: nada de notificações atrapalhando no meio da partida. Desligue com "Desligar DND" quando terminar.',
          'argv' => ['adb-tweaks.sh', 'dnd']]);
    $add(['id' => 'dnd_off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Desligar DND',
          'desc' => 'Volta a receber notificações normalmente.',
          'help' => 'Desliga o modo Não Perturbe e traz as notificações de volta.',
          'argv' => ['adb-tweaks.sh', 'dnd_off']]);
    $add(['id' => 'game_focus', 'group' => 'Display & Touch', 'label' => 'Foco de jogo (DND extremo)',
          'desc' => 'Silencia tudo na partida: heads-up, bolhas e som de notificação.',
          'help' => 'Modo foco total para jogar: ativa o Não Perturbe, desliga os balões (heads-up) e as bolhas de notificação. O sistema deixa de gastar CPU desenhando avisos em primeiro plano. Chamadas de contatos de emergência continuam passando. Reverta em "Foco de jogo: desligar".',
          'argv' => ['adb-tweaks.sh', 'game_focus'], 'risk' => 'careful']);
    $add(['id' => 'game_focus_off', 'group' => 'Display & Touch', 'label' => 'Foco de jogo: desligar',
          'desc' => 'Volta as notificações ao normal.',
          'help' => 'Desliga o modo foco de jogo e devolve as notificações normais.',
          'argv' => ['adb-tweaks.sh', 'game_focus_off']]);
    $add(['id' => 'screen', 'group' => 'Desempenho', 'label' => 'Tela / refresh alto',
          'desc' => 'Fixa a taxa de atualização no máximo do aparelho.',
          'help' => 'Trava a tela na maior taxa de atualização (Hz) que o aparelho suporta. Rolagem e jogo ficam mais suaves. Gasta um pouco mais de bateria.',
          'argv' => ['adb-tweaks.sh', 'screen']]);
    $add(['id' => 'screen_off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Tela: devolver taxa ao sistema',
          'desc' => 'Remove a trava de refresh e deixa o sistema decidir.',
          'help' => 'Apaga a trava de taxa de atualização e devolve o controle ao Android.',
          'argv' => ['adb-tweaks.sh', 'screen_off']]);
    $add(['id' => 'battery', 'group' => 'Desempenho', 'card' => false, 'label' => 'Economia de bateria',
          'desc' => 'Ativa o modo de economia e o repouso profundo (Doze).',
          'help' => 'Liga a economia de energia e força o aparelho a "dormir" mais fundo quando parado. Dura mais a bateria. NÃO use enquanto joga — pode derrubar o desempenho.',
          'argv' => ['adb-tweaks.sh', 'battery']]);
    $add(['id' => 'battery_off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Desligar economia',
          'desc' => 'Volta ao consumo normal (recomendado para jogar).',
          'help' => 'Desliga a economia de bateria e o repouso profundo. Use antes de jogar para o desempenho não ser limitado.',
          'argv' => ['adb-tweaks.sh', 'battery_off']]);

    // ----- Sono profundo (doze / idle) -----
    $add(['id' => 'doze.on', 'group' => 'Desempenho', 'card' => false, 'label' => 'Sono profundo: ligar',
          'desc' => 'Faz o aparelho dormir de verdade logo após a tela apagar.',
          'help' => 'O Android só "dorme fundo" (Doze) depois de uns 30 minutos parado. Aqui esse tempo é encurtado para cerca de 2 minutos: a tela apagou, o aparelho dorme e a bateria dura muito mais. Reverta em "Sono profundo: desligar" antes de precisar de notificações em tempo real.',
          'argv' => ['adb-tweaks.sh', 'doze', 'on'], 'risk' => 'careful', 'confirm' => true]);
    $add(['id' => 'doze.off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Sono profundo: desligar',
          'desc' => 'Volta os tempos de repouso ao padrão de fábrica.',
          'help' => 'Restaura os tempos normais do Doze. Use se estiver perdendo notificações de apps em segundo plano.',
          'argv' => ['adb-tweaks.sh', 'doze', 'off']]);
    $add(['id' => 'doze.status', 'group' => 'Sistema', 'label' => 'Ver estado do sono profundo',
          'desc' => 'Mostra o estado atual do Doze e as constantes em uso.',
          'help' => 'Mostra em que estado o repouso está agora (ativo/inativo) e quais tempos estão configurados. Só leitura.',
          'argv' => ['adb-tweaks.sh', 'doze', 'status']]);

    // ----- Gerenciador de processos (RAM e CPU) -----
    $add(['id' => 'proc.top', 'group' => 'Processos', 'label' => 'Processos que mais gastam',
          'desc' => 'Lista os apps que mais consomem CPU e RAM agora (dados reais).',
          'help' => 'Mostra os processos que mais estão usando a CPU e a memória neste momento, com os números lidos do próprio aparelho. Serve para você ver quem está pesando antes de congelar ou limitar. Nada é alterado.',
          'argv' => ['proc-mgr.sh', 'top', '{n}'],
          'params' => [['name' => 'n', 'type' => 'int', 'label' => 'Quantos', 'min' => 5, 'max' => 40, 'default' => 12]]]);
    $add(['id' => 'proc.info', 'group' => 'Processos', 'label' => 'Ver um app (PID/RAM/nice)',
          'desc' => 'Mostra PID, RAM, prioridade e oom do app escolhido.',
          'help' => 'Detalha o app escolhido: quantos processos tem, quanto de RAM está usando, a prioridade (nice) e o oom_score. Tudo lido do aparelho. Só leitura.',
          'argv' => ['proc-mgr.sh', 'info', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']]]);
    $add(['id' => 'proc.list', 'group' => 'Processos', 'label' => 'Apps rodando agora',
          'desc' => 'Lista os apps de usuário rodando neste momento, com a RAM de cada um.',
          'help' => 'Mostra os apps de usuário que estão rodando agora, com quanta RAM cada um ocupa, e marca os que estão protegidos. É a mesma lista que o painel flutuante mostra no meio da partida. Só leitura.',
          'argv' => ['proc-mgr.sh', 'list']]);
    $add(['id' => 'proc.kill', 'group' => 'Processos', 'label' => 'Encerrar todos em 2º plano',
          'desc' => 'Fecha os apps de fundo de uma vez, poupando as suas exceções.',
          'help' => 'Encerra de uma vez os apps que estão rodando em segundo plano e libera a RAM. Ficam de fora: o app em primeiro plano, o jogo do Modo Competitivo, o próprio pack e as suas exceções (procure "Exceção: não encerrar" abaixo). É o botão "encerrar todos" do painel flutuante.',
          'argv' => ['proc-mgr.sh', 'kill'],
          'risk' => 'careful']);
    $add(['id' => 'proc.keep', 'group' => 'Processos', 'label' => 'Exceção: app não encerrar',
          'desc' => 'Marca um app que NUNCA deve ser encerrado (ex.: uma live).',
          'help' => 'Cria uma exceção: o app escolhido nunca é encerrado pelo "Encerrar todos", pelo Clean, pelo RAM Boost nem pelo Game Clean. Serve para coisas que você não quer que fechem — por exemplo, uma live do TikTok rodando em segundo plano. Remova em "Exceção: remover".',
          'argv' => ['proc-mgr.sh', 'keep', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']]]);
    $add(['id' => 'proc.keep_fg', 'group' => 'Processos', 'label' => 'Exceção: app em 1º plano',
          'desc' => 'Cria a exceção para o app que está na tela agora.',
          'help' => 'Descobre qual app está em primeiro plano neste momento e cria a exceção para ele, sem você precisar procurar o pacote. Útil quando a live já está aberta.',
          'argv' => ['proc-mgr.sh', 'keep-fg']]);
    $add(['id' => 'proc.keep_list', 'group' => 'Processos', 'label' => 'Exceções (não encerrar)',
          'desc' => 'Lista os apps marcados como "não encerrar".',
          'help' => 'Lista as exceções: os apps que o pack nunca encerra, nem no "Encerrar todos" nem nas limpezas. Só leitura.',
          'argv' => ['proc-mgr.sh', 'keep-list']]);
    $add(['id' => 'proc.unkeep', 'group' => 'Processos', 'label' => 'Exceção: remover',
          'desc' => 'Tira o app da lista de "não encerrar".',
          'help' => 'Remove a exceção do app escolhido: ele volta a poder ser encerrado em segundo plano como os outros.',
          'argv' => ['proc-mgr.sh', 'unkeep', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']]]);
    $add(['id' => 'proc.keep_clear', 'group' => 'Processos', 'label' => 'Exceções: apagar todas',
          'desc' => 'Limpa de uma vez a lista de "não encerrar".',
          'help' => 'Apaga todas as exceções de uma vez, devolvendo o comportamento normal: nenhum app fica poupado além do jogo e do que está em primeiro plano.',
          'argv' => ['proc-mgr.sh', 'keep-clear'],
          'risk' => 'careful']);
                            
    // ----- Manter vivo (anti-relog) -----
    $add(['id' => 'keep.on', 'group' => 'Processos', 'label' => 'Manter app vivo (não relogar)',
          'desc' => 'Impede o app de fechar e pedir login de novo ao reabrir.',
          'help' => 'Quando você sai de um app, o Android pode matá-lo para liberar memória — ao voltar, ele abre do zero e pede login outra vez. Aqui o app escolhido fica protegido: isento do modo espera (Doze), liberado em segundo plano e wake lock, no balde ativo de standby e fora do congelador. Requer Shizuku/ADB. Reverta em "Deixar de manter o app".',
          'argv' => ['keep-alive.sh', 'on', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']],
          'risk' => 'careful']);
    $add(['id' => 'keep.game', 'group' => 'Processos', 'label' => 'Manter jogo vivo (não relogar)',
          'desc' => 'Igual ao anterior, e ainda libera o Game Mode do jogo.',
          'help' => 'Protege o jogo para ele não ser morto em segundo plano (o que causa relog e sair da partida) e ainda pede ao sistema para tratá-lo como jogo (Game Mode em performance). Escolha o pacote do jogo. Reverta em "Deixar de manter o app".',
          'argv' => ['keep-alive.sh', 'on', '{pkg}', 'jogo'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']],
          'risk' => 'careful']);
    $add(['id' => 'keep.off', 'group' => 'Processos', 'label' => 'Deixar de manter o app',
          'desc' => 'Devolve o app ao comportamento normal do sistema.',
          'help' => 'Remove a proteção anti-relog do app escolhido: ele volta a poder ser colocado em espera e encerrado em segundo plano como os outros. Use se o app estava consumindo bateria demais.',
          'argv' => ['keep-alive.sh', 'off', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']],
          'risk' => 'careful']);
    $add(['id' => 'keep.status', 'group' => 'Processos', 'label' => 'Ver estado anti-relog',
          'desc' => 'Mostra o que está aplicado para o app escolhido.',
          'help' => 'Mostra, lido do aparelho, se o app está isento do Doze, o que está liberado em segundo plano, o balde de standby, os processos (PIDs) e se o pack o guarda como protegido. Só leitura.',
          'argv' => ['keep-alive.sh', 'status', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'keep.list', 'group' => 'Processos', 'label' => 'Apps protegidos (anti-relog)',
          'desc' => 'Lista os apps que você marcou para não relogar.',
          'help' => 'Lista os apps que você protegeu contra relog. Só leitura.',
          'argv' => ['keep-alive.sh', 'list']]);
    $add(['id' => 'keep.restore', 'group' => 'Processos', 'label' => 'Devolver todos ao normal',
          'desc' => 'Tira a proteção anti-relog de todos os apps.',
          'help' => 'Remove a proteção anti-relog de TODOS os apps de uma vez, devolvendo o controle ao sistema. Use para recomeçar do zero.',
          'argv' => ['keep-alive.sh', 'restore'], 'risk' => 'careful', 'confirm' => true]);

    // ----- Congelar apps -----
    $add(['id' => 'freeze', 'group' => 'Desempenho', 'card' => false, 'label' => 'Congelar apps (cache freezer)',
          'desc' => 'Ativa o congelador do sistema e aplica a lista.',
          'help' => 'Liga o congelador de apps em cache do sistema: apps que você não está usando ficam pausados em vez de gastar RAM/bateria. Ótimo para liberar memória. Reverta em "Descongelar todos os apps".',
          'argv' => ['adb-tweaks.sh', 'freezer'], 'confirm' => true]);
    $add(['id' => 'unfreeze', 'group' => 'Desempenho', 'card' => false, 'label' => 'Descongelar todos os apps',
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

            $add(['id' => 'deep.detect', 'group' => 'Desempenho', 'label' => 'Detectar hardware',
          'desc' => 'Mostra CPU, GPU e kernel com recomendações.',
          'help' => 'Lê os dados de hardware do aparelho e sugere quais ajustes profundos fazem sentido. Só informa, não muda nada.',
          'argv' => ['deep-tune.sh', 'detect']]);

    $add(['id' => 'ext.display', 'group' => 'Display & Touch', 'label' => 'Display / HWUI (props)',
          'desc' => 'Props do SurfaceFlinger/HWUI que deixam a rolagem mais lisa. SEM root.',
          'help' => 'Ajusta props "debug.*" do SurfaceFlinger e do HWUI (buffer age, latch, backpressure, offsets de fase). Deixa a rolagem mais lisa.',
          'argv' => ['deep-tune.sh', 'display', 'on']]);
    $add(['id' => 'ext.display.off', 'group' => 'Display & Touch', 'label' => 'Display / HWUI — desligar',
          'desc' => 'Reverte as props de display.',
          'help' => 'Restaura as props de display/HWUI ao valor anterior.',
          'argv' => ['deep-tune.sh', 'display', 'off']]);
        $add(['id' => 'ext.dexopt', 'group' => 'Desempenho', 'label' => 'Recompilar apps (dexopt)',
          'desc' => 'Compila os apps antecipadamente (AOT). Demora, mas reduz engasgo.',
          'help' => 'Recompila todos os apps em modo speed (AOT). A primeira abertura fica mais fluida e some o engasgo do compilador em segundo plano. Demora vários minutos e esquenta; roda melhor com o celular na tomada.',
          'argv' => ['deep-tune.sh', 'dexopt', 'run'], 'timeout' => 900, 'risk' => 'careful', 'confirm' => true]);
    $add(['id' => 'ext.dexopt_status', 'group' => 'Desempenho', 'label' => 'Ver estado do dexopt',
          'desc' => 'Mostra como está a compilação dos apps.',
          'help' => 'Mostra o estado da compilação AOT dos apps (o que já foi otimizado). Só leitura.',
          'argv' => ['deep-tune.sh', 'dexopt', 'status']]);

    // ----- Avançado (sem root) — pouco conhecido -----
    $add(['id' => 'adv.obscure', 'group' => 'Desempenho', 'label' => 'Ajustes obscuros',
          'desc' => 'Menos kills em 2º plano e o jogo fora do Doze. SEM root.',
          'help' => 'Reúne knobs pouco conhecidos: standby de apps, whitelist do Doze para o Free Fire e ajustes de memória. Resultado: apps não são mortos à toa e o jogo não sofre com o repouso profundo.',
          'argv' => ['adb-tweaks.sh', 'obscure']]);
    $add(['id' => 'adv.mobile_net', 'group' => 'DNS e rede', 'label' => 'Rede móvel / economia de dados',
          'desc' => 'Desliga a economia de dados que estrangula a velocidade.',
          'help' => 'Desliga a economia de dados e evita trocar para um Wi-Fi ruim. Evita que o sistema limite a velocidade no meio do jogo.',
          'argv' => ['adb-tweaks.sh', 'mobile_net']]);
    $add(['id' => 'adv.mobile_net_off', 'group' => 'DNS e rede', 'card' => false, 'label' => 'Rede móvel: voltar ao padrão',
          'desc' => 'Religa a economia de dados e o comportamento padrão.',
          'help' => 'Devolve a economia de dados e as preferências de rede móvel ao padrão do Android.',
          'argv' => ['adb-tweaks.sh', 'mobile_net_off']]);
    $add(['id' => 'adv.notif_on', 'group' => 'Sistema', 'card' => false, 'label' => 'Notificações: voltar ao normal',
          'desc' => 'Religa os balões (heads-up) e as bolhas.',
          'help' => 'Religa os balões (heads-up) e as bolhas de notificação, voltando ao comportamento padrão do Android.',
          'argv' => ['adb-tweaks.sh', 'notif_on']]);
    $add(['id' => 'adv.notif', 'group' => 'Sistema', 'card' => false, 'label' => 'Menos notificações (heads-up)',
          'desc' => 'Reduz o trabalho do sistema com notificações pop-up.',
          'help' => 'Desliga os balões (heads-up) e as bolhas de notificação. O sistema trabalha menos e sobra fluidez — bom para jogar.',
          'argv' => ['adb-tweaks.sh', 'notif']]);
    // ----- Efeitos visuais: desfoque e transparência (liga/desliga na mão) -----
    // O pack desliga os dois nas ações de desempenho. Sem este grupo, o usuário
    // não tinha como devolver o desfoque do teclado/barra sem editar settings.
    $add(['id' => 'fx.blur_on', 'group' => 'Display & Touch', 'label' => 'Efeitos visuais: LIGAR (visual completo)',
          'desc' => 'Devolve o desfoque do teclado, da barra e das notificações.',
          'help' => 'Liga o desfoque (blur) e a transparência do sistema. Use se você achou a interface "seca" ou o teclado estranho depois de aplicar o pack. O desfoque consome um pouco de GPU — em aparelho fraco, deixe desligado.',
          'choice' => 'effects', 'option' => 'Ligado (visual completo)', 'state_value' => 'on',
          'argv' => ['adb-tweaks.sh', 'effects', 'on']]);
    $add(['id' => 'fx.blur_off', 'group' => 'Display & Touch', 'label' => 'Efeitos visuais: DESLIGAR (mais fluidez)',
          'desc' => 'Tira o desfoque e a transparência: interface mais leve.',
          'help' => 'Desliga o desfoque (blur) e a transparência do sistema. A interface fica mais leve e sobra GPU/CPU para o jogo — é o que o pack recomendado já faz. Reverta em "Efeitos visuais: LIGAR".',
          'choice' => 'effects', 'option' => 'Desligado (mais fluidez)', 'state_value' => 'off',
          'argv' => ['adb-tweaks.sh', 'effects', 'off']]);
    $add(['id' => 'fx.blur_status', 'group' => 'Display & Touch', 'label' => 'Efeitos visuais: ver estado',
          'desc' => 'Mostra se o desfoque e a transparência estão ligados.',
          'help' => 'Mostra, lido do aparelho, se o desfoque (blur) e a transparência do sistema estão ligados ou desligados agora. Só leitura.',
          'argv' => ['adb-tweaks.sh', 'effects', 'status']]);

    // ----- Barras do sistema (barra de cima e de baixo) -----
    // O pack recomendado e as ações de desempenho mexem em coisas que mudam a
    // cara da barra de baixo (o desfoque) e o "Janelas / modo imersivo" esconde
    // as barras. Sem este grupo, o usuário não tinha como devolver a barra de
    // baixo ao normal sem editar settings na mão.
    $add(['id' => 'sysbars.on', 'group' => 'Display & Touch', 'label' => 'Barras: VISÍVEIS (padrão)',
          'desc' => 'Devolve a barra de cima e a de baixo (quadrado/bolinha).',
          'help' => 'Desliga o modo imersivo e devolve as duas barras do sistema. Use se a barra de baixo (quadrado, bolinha, voltar) sumiu ou ficou estranha depois de aplicar o pack. O painel lê o estado real do aparelho e marca o que está em uso.',
          'choice' => 'sysbars', 'option' => 'Visíveis (padrão)', 'state_value' => 'on',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'on']]);
    $add(['id' => 'sysbars.off', 'group' => 'Display & Touch', 'label' => 'Barras: esconder as DUAS (imersivo)',
          'desc' => 'Esconde a barra de cima e a de baixo: mais tela no jogo.',
          'help' => 'Ativa o modo imersivo: esconde a barra de status (relógio, bateria) e a barra de navegação. Sobra tela para o jogo. Deslize de baixo para cima ou de cima para baixo para elas aparecerem na hora. Reverta em "Barras: VISÍVEIS".',
          'choice' => 'sysbars', 'option' => 'Esconder as duas', 'state_value' => 'off',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'off']]);
    $add(['id' => 'sysbars.nav', 'group' => 'Display & Touch', 'label' => 'Barras: esconder só a de BAIXO',
          'desc' => 'Esconde só a barra de navegação (quadrado/bolinha).',
          'help' => 'Esconde apenas a barra de navegação, mantendo o relógio e a bateria à vista. Útil quando a barra de baixo atrapalha o jogo, mas você ainda quer ver as notificações.',
          'choice' => 'sysbars', 'option' => 'Só a de baixo', 'state_value' => 'nav',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'so_nav']]);
    $add(['id' => 'sysbars.status', 'group' => 'Display & Touch', 'label' => 'Barras: esconder só a de CIMA',
          'desc' => 'Esconde só a barra de status (relógio/bateria).',
          'help' => 'Esconde apenas a barra de cima (relógio, bateria, ícones), mantendo a navegação. Deixa a tela mais limpa sem tirar os botões de voltar.',
          'choice' => 'sysbars', 'option' => 'Só a de cima', 'state_value' => 'status',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'so_status']]);
    $add(['id' => 'sysbars.status_show', 'group' => 'Display & Touch', 'label' => 'Barras: ver estado',
          'desc' => 'Mostra, lido do aparelho, o que está escondido agora.',
          'help' => 'Mostra o estado real das barras: se estão visíveis, se o modo imersivo está ligado, quais ícones estão escondidos e se a bateria aparece em porcentagem. Só leitura. Os cards acima já mostram o estado sozinhos; este comando serve para ver o valor cru do aparelho.',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'status']]);
    $add(['id' => 'sysbars.icons_clean', 'group' => 'Display & Touch', 'label' => 'Barra de cima: esconder ícones extras',
          'desc' => 'Tira rotação, fone, volume e alarme da barra de status.',
          'help' => 'Esconde os ícones secundários da barra de cima (rotação automática, fone, volume, alarme), deixando só o essencial: relógio, bateria, sinal e notificações. Reverta em "Barra de cima: mostrar todos os ícones".',
          'choice' => 'sysbars_icons', 'option' => 'Só o essencial', 'state_value' => 'clean',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'clean']]);
    $add(['id' => 'sysbars.icons_all', 'group' => 'Display & Touch', 'label' => 'Barra de cima: mostrar todos os ícones',
          'desc' => 'Devolve todos os ícones da barra de status.',
          'help' => 'Remove a lista de ícones escondidos da barra de cima, devolvendo todos os indicadores (rotação, fone, volume, alarme).',
          'choice' => 'sysbars_icons', 'option' => 'Mostrar todos', 'state_value' => 'all',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'icons', 'none']]);
    $add(['id' => 'sysbars.battery_pct', 'group' => 'Display & Touch', 'label' => 'Barra de cima: bateria em %',
          'desc' => 'Mostra o número da bateria ao lado do ícone.',
          'help' => 'Mostra a porcentagem da bateria na barra de status. Útil para saber quanto resta sem abrir as configurações.',
          'choice' => 'sysbars_battery', 'option' => 'Número (%)', 'state_value' => '1',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'battery', 'on']]);
    $add(['id' => 'sysbars.battery_off', 'group' => 'Display & Touch', 'label' => 'Barra de cima: bateria só ícone',
          'desc' => 'Volta a mostrar só o ícone da bateria.',
          'help' => 'Esconde o número da porcentagem da bateria, deixando só o ícone. Reverta em "Barra de cima: bateria em %".',
          'choice' => 'sysbars_battery', 'option' => 'Só o ícone', 'state_value' => '0',
          'argv' => ['adb-tweaks.sh', 'sysbars', 'battery', 'off']]);

    $add(['id' => 'adv.window', 'group' => 'Display & Touch', 'label' => 'Janelas / transições rápidas',
          'desc' => 'Transições mais curtas: a interface responde na hora.',
          'help' => 'Reduz as animações de janela, transição e abertura para 0.5x: o aparelho parece mais rápido sem mudar nada de visual. NÃO esconde as barras — se você quer mais tela no jogo, use "Barras: esconder as duas (imersivo)" logo acima; se já escondeu e quer voltar, use "Barras: VISÍVEIS (padrão)".',
          'argv' => ['adb-tweaks.sh', 'window_tweaks']]);


    // ----- Turbo (sem root) — compilação, hibernação, caches, refresh -----
    $add(['id' => 'turbo.status', 'group' => 'Desempenho', 'label' => 'Estado do Turbo',
          'desc' => 'Mostra phantom killer, refresh, logs e scans em uma tela.',
          'help' => 'Resume o estado dos recursos turbo: Phantom Process Killer, taxa de atualização travada, logs persistentes e scans de Wi-Fi/Bluetooth "sempre disponível". Bom para conferir antes e depois de aplicar.',
          'argv' => ['turbo.sh', 'status']]);
    $add(['id' => 'fps.now', 'group' => 'Desempenho', 'label' => 'FPS real do jogo (agora)',
          'desc' => 'Lê o FPS de verdade do compositor, sem estimativa.',
          'help' => 'Mostra o FPS REAL do jogo lido do SurfaceFlinger: cada quadro apresentado é contado com o horário de verdade, então o número é medido, não estimado. Deixe o jogo aberto e em movimento (no menu parado o número fica vazio). Sem escolher app, ele usa o que está em primeiro plano.',
          'argv' => ['fps.sh', 'now', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo (opcional)']]]);
    $add(['id' => 'fps.layer', 'group' => 'Desempenho', 'card' => false, 'label' => 'FPS: ver a camada do app',
          'desc' => 'Mostra qual camada do compositor corresponde ao app.',
          'help' => 'Descobre a camada do SurfaceFlinger que pertence ao app escolhido. Serve para conferir se o FPS está sendo lido da camada certa quando o jogo tem mais de uma (ex.: vídeo + HUD).',
          'argv' => ['fps.sh', 'layer', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo (opcional)']]]);
    $add(['id' => 'fps.list', 'group' => 'Desempenho', 'card' => false, 'label' => 'FPS: listar camadas da tela',
          'desc' => 'Lista as camadas ativas do compositor agora.',
          'help' => 'Lista as camadas que o compositor está desenhando neste momento. Útil para achar o nome da camada de um jogo que não aparece pelo pacote.',
          'argv' => ['fps.sh', 'list']]);
    $add(['id' => 'turbo.art', 'group' => 'Desempenho', 'label' => 'Abrir apps mais rápido (compilar)',
          'desc' => 'Compila o app escolhido para ele abrir mais rápido.',
          'help' => 'Força o Android a pré-compilar (ART/AOT) o app escolhido, para ele abrir mais rápido e sem engasgo. Escolha o app pelo nome e ícone — não precisa digitar o pacote. "speed-profile" é o equilíbrio (abre rápido sem inflar o armazenamento); "speed" compila tudo (mais rápido ainda, ocupa mais espaço). Para desfazer, use "Recompilar todos os apps (ART)".',
          'argv' => ['turbo.sh', 'art', '{pkg}', '{mode}'],
          'params' => [
              ['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo'],
              ['name' => 'mode', 'type' => 'enum', 'label' => 'Modo',
               'options' => ['speed-profile', 'speed', 'everything'], 'default' => 'speed-profile']],
          'timeout' => 600, 'risk' => 'careful']);
    $add(['id' => 'turbo.art_all', 'group' => 'Desempenho', 'label' => 'Recompilar todos os apps (ART)',
          'desc' => 'Aplica speed-profile em todos os apps (melhora abertura geral).',
          'help' => 'Recompila todos os apps instalados em speed-profile. Deixa o sistema mais responsivo no geral. Demora vários minutos e consome bateria — rode com o aparelho carregando.',
          'argv' => ['turbo.sh', 'art-all', 'speed-profile'], 'timeout' => 900,
          'risk' => 'careful', 'confirm' => true]);
    $add(['id' => 'turbo.dexopt_bg', 'group' => 'Desempenho', 'label' => 'Disparar bg-dexopt-job',
          'desc' => 'Pede ao sistema a compilação ociosa dos apps agora.',
          'help' => 'Dispara o job de compilação em segundo plano do Android (bg-dexopt-job). Ele roda quando o aparelho estiver parado e compila os apps sem travar você.',
          'argv' => ['turbo.sh', 'dexopt-bg']]);
    $add(['id' => 'turbo.standby', 'group' => 'Desempenho', 'label' => 'App Standby Bucket',
          'desc' => 'Define a "prioridade" de um app no plano de fundo.',
          'help' => 'Cada app tem um bucket (caixa) que diz quanto ele pode rodar em segundo plano. "restricted" quase congela; "rare" deixa rodar pouco; "active" libera. Útil para segurar apps que gastam bateria sem desativá-los.',
          'argv' => ['turbo.sh', 'standby', '{pkg}', '{bucket}'],
          'params' => [
              ['name' => 'pkg', 'type' => 'pkg', 'label' => 'App'],
              ['name' => 'bucket', 'type' => 'enum', 'label' => 'Bucket',
               'options' => ['active', 'working', 'frequent', 'rare', 'restricted'], 'default' => 'rare']]]);
    $add(['id' => 'turbo.hibernate', 'group' => 'Desempenho', 'label' => 'Hibernar um app',
          'desc' => 'Suspende um app por completo (estilo Hail).',
          'help' => 'Hiberna o app: para ele na hora e o deixa inativo (não roda nem em segundo plano) até você abrir de novo. Igual ao app Hail. Ótimo para redes sociais que ficam acordando o aparelho.',
          'argv' => ['turbo.sh', 'hibernate', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App']], 'risk' => 'careful']);
    $add(['id' => 'turbo.hibernate_all', 'group' => 'Desempenho', 'label' => 'Hibernar todos os apps',
          'desc' => 'Hiberna todos os apps de usuário (poupando o jogo).',
          'help' => 'Hiberna de uma vez todos os apps que você instalou, exceto o Free Fire e uma allowlist. Libera bastante RAM e bateria. Reversível em "Descongelar agora" ou abrindo os apps.',
          'argv' => ['turbo.sh', 'hibernate', 'now'], 'risk' => 'careful', 'confirm' => true]);
    $add(['id' => 'turbo.killbg', 'group' => 'Desempenho', 'label' => 'Matar 2º plano (seletivo)',
          'desc' => 'Encerra apps em segundo plano, poupando o jogo.',
          'help' => 'Fecha os apps que estão rodando escondidos para liberar RAM na hora, sem mexer no Free Fire. É um "matar tudo" mais seguro que o do sistema.',
          'argv' => ['turbo.sh', 'killbg'], 'risk' => 'careful']);
    $add(['id' => 'turbo.phantom_on', 'group' => 'Desempenho', 'card' => false, 'label' => 'Phantom Killer: ligar',
          'desc' => 'Volta o limite de processos-fantasma ao padrão do Android.',
          'help' => 'O Phantom Process Killer mata processos "fantasma" (filhos de apps como Termux/emuladores). Aqui ele volta ao padrão do sistema. Use se você não precisa de serviços em segundo plano.',
          'argv' => ['turbo.sh', 'phantom', 'on']]);
    $add(['id' => 'turbo.phantom_off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Phantom Killer: desligar',
          'desc' => 'Desliga o limite (bom p/ Termux, emuladores e serviços).',
          'help' => 'Desliga o Phantom Process Killer: apps como Termux, emuladores e servidores deixam de ter processos mortos pelo sistema. Pode aumentar um pouco o uso de bateria.',
          'argv' => ['turbo.sh', 'phantom', 'off'], 'risk' => 'careful']);
    $add(['id' => 'turbo.trim', 'group' => 'Desempenho', 'label' => 'Poda de caches real',
          'desc' => 'Libera espaço dos caches sem apagar dados de apps.',
          'help' => 'Usa o trim-caches oficial do Android: apaga só arquivos de cache temporários, nunca seus dados, contas ou conversas. Mostra o espaço livre antes e depois.',
          'argv' => ['turbo.sh', 'trim']]);
    $add(['id' => 'turbo.refresh_max', 'group' => 'Desempenho', 'card' => false, 'label' => 'Refresh no máximo',
          'desc' => 'Trava a tela na maior taxa de atualização (ex.: 120Hz).',
          'help' => 'Trava a taxa de atualização no valor mais alto suportado pela tela. Rolagem e jogo ficam mais lisos. Gasta um pouco mais de bateria. Reverte em "Refresh automático".',
          'argv' => ['turbo.sh', 'refresh', 'max'], 'risk' => 'careful']);
    $add(['id' => 'turbo.refresh_auto', 'group' => 'Desempenho', 'card' => false, 'label' => 'Refresh automático',
          'desc' => 'Devolve o controle da taxa de atualização ao sistema.',
          'help' => 'Remove a trava de refresh e deixa o Android escolher a taxa conforme a tela e a bateria.',
          'argv' => ['turbo.sh', 'refresh', 'auto']]);
    $add(['id' => 'turbo.refresh_fixed', 'group' => 'Desempenho', 'label' => 'Refresh fixo (frametime)',
          'desc' => 'Trava a tela numa taxa fixa (60/90/120/144Hz) para estabilizar o frametime.',
          'help' => 'Trava a tela numa taxa fixa. Quando a taxa oscila (60↔120Hz) no meio da partida, o frametime "pula" e dá micro-travada mesmo com FPS alto. Travar em uma taxa deixa o frametime constante. Use "Refresh automático" para voltar ao dia a dia.',
          'argv' => ['turbo.sh', 'refresh_fixed', '{hz}'],
          'params' => [['name' => 'hz', 'type' => 'enum', 'label' => 'Taxa (Hz)',
                        'options' => ['60', '90', '120', '144'], 'default' => '120']],
          'risk' => 'careful']);
                            $add(['id' => 'turbo.perfmode_on', 'group' => 'Desempenho', 'card' => false, 'label' => 'Modo desempenho fixo: ligar',
          'desc' => 'Força o aparelho a priorizar desempenho.',
          'help' => 'Trava o aparelho em modo de desempenho (não reduz clocks por bateria). Mais FPS sustentado, mais calor e mais consumo. Reverte em "desligar".',
          'argv' => ['turbo.sh', 'perfmode', 'on'], 'risk' => 'careful']);
    $add(['id' => 'turbo.perfmode_off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Modo desempenho fixo: desligar',
          'desc' => 'Volta o controle de energia ao sistema.',
          'help' => 'Desliga o modo de desempenho fixo e devolve o gerenciamento de energia ao Android.',
          'argv' => ['turbo.sh', 'perfmode', 'off']]);

    // ----- Vitalidade: cuidar para durar -------------------------------------
    // O resto do pack "tira o freio". Estas ações fazem o oposto: medem a saúde
    // real da bateria, reduzem desgaste e avisam hábitos de carga que encurtam a
    // vida do aparelho. Nada aqui força o celular.
    $add(['id' => 'vital.optimize', 'group' => 'Geral', 'card' => false, 'label' => 'Otimizar saúde do telefone',
          'desc' => 'Um toque: liga o cuidado e mostra a saúde real da bateria.',
          'help' => 'O botão único do cuidado. Liga o modo longevidade (sono profundo afinado, tela em 60 Hz, menos varredura em segundo plano e a economia de energia do sistema de volta) e, na mesma tela, mostra a saúde REAL da bateria: capacidade atual contra a de fábrica, ciclos, temperatura e uma nota de 0 a 100. É para durar mais, não para forçar. Reversível em "Modo longevidade: desligar".',
          'argv' => ['vitality.sh', 'optimize'], 'risk' => 'careful', 'confirm' => true, 'timeout' => 180]);
    $add(['id' => 'vital.diag', 'group' => 'Geral', 'card' => false, 'label' => 'Saúde da bateria: ver diagnóstico',
          'desc' => 'Capacidade real, ciclos e desgaste da bateria.',
          'help' => 'Mostra a saúde REAL da bateria: compara a capacidade atual com a de fábrica (é o número que o Android esconde), a contagem de ciclos de carga, o nível, a temperatura e uma nota de vitalidade de 0 a 100. É a diferença entre "acho que está boa" e saber. Só leitura: não muda nada no aparelho.',
          'argv' => ['vitality.sh', 'diag'], 'timeout' => 60]);
    $add(['id' => 'vital.care_on', 'group' => 'Geral', 'card' => false, 'label' => 'Modo longevidade: ligar',
          'desc' => 'Reduz o desgaste: doze ativo, tela 60Hz, menos scans.',
          'help' => 'Liga o cuidado com a durabilidade: sono profundo afinado (dorme logo após a tela apagar), tela em 60Hz (taxa alta é um dos maiores consumos contínuos) e menos varredura de Wi-Fi/Bluetooth em segundo plano. Reduz agressão em vez de forçar desempenho, então o aparelho esquenta menos e dura mais. Totalmente reversível em "Modo longevidade: desligar".',
          'argv' => ['vitality.sh', 'care', 'on'], 'risk' => 'careful', 'timeout' => 120]);
    $add(['id' => 'vital.care_off', 'group' => 'Geral', 'card' => false, 'label' => 'Modo longevidade: desligar',
          'desc' => 'Volta doze, taxa da tela e scans ao padrão.',
          'help' => 'Desliga o modo longevidade e devolve o sono profundo, a taxa de atualização e as varreduras ao padrão de fábrica. Reversível.',
          'argv' => ['vitality.sh', 'care', 'off'], 'risk' => 'safe', 'timeout' => 60]);
    $add(['id' => 'vital.care_status', 'group' => 'Geral', 'card' => false, 'label' => 'Modo longevidade: ver estado',
          'desc' => 'Mostra se o modo longevidade está ligado.',
          'help' => 'Diz se o modo longevidade está ligado ou desligado, e resume a nota de vitalidade, a saúde da bateria e a temperatura agora. Só leitura.',
          'argv' => ['vitality.sh', 'care', 'status'], 'timeout' => 60]);
    $add(['id' => 'vital.guard', 'group' => 'Geral', 'card' => false, 'label' => 'Guardião de carga: ver hábitos',
          'desc' => 'Conta cargas acima de 80% e cargas com calor.',
          'help' => 'O guardião observa seus hábitos de carga e conta o que desgasta a bateria: quantas vezes você carregou acima de 80% e quantas carregou com o aparelho quente (calor + carga é o que mais encurta a vida da célula). Ele não muda nada: só mede e avisa. Sem root não é possível limitar a carga em 80%, mas dá para saber quando você passou.',
          'argv' => ['vitality.sh', 'guard'], 'timeout' => 60]);
    $add(['id' => 'vital.status', 'group' => 'Geral', 'card' => false, 'label' => 'Vitalidade: resumo',
          'desc' => 'Nota de vitalidade e situação geral do aparelho.',
          'help' => 'Resume tudo em uma tela: nota de vitalidade, saúde da bateria, ciclos, temperatura, se o modo longevidade está ligado e o alerta atual do guardião de carga. Só leitura.',
          'argv' => ['vitality.sh', 'status'], 'timeout' => 60]);
    $add(['id' => 'turbo.telemetry_off', 'group' => 'Desempenho', 'card' => false, 'label' => 'Telemetria e logs: desligar',
          'desc' => 'Desliga logs persistentes e scans "sempre disponível".',
          'help' => 'Desliga o log persistente (logpersist), o log de Bluetooth e as varreduras de Wi-Fi/Bluetooth "sempre disponível". Menos trabalho em segundo plano e mais privacidade. Reversível em "religar".',
          'argv' => ['turbo.sh', 'telemetry', 'off'], 'risk' => 'careful']);
    $add(['id' => 'turbo.telemetry_on', 'group' => 'Desempenho', 'card' => false, 'label' => 'Telemetria e logs: religar',
          'desc' => 'Volta os logs e scans ao padrão.',
          'help' => 'Religa os logs e as varreduras que o modo privacidade desligou, voltando ao comportamento padrão do Android.',
          'argv' => ['turbo.sh', 'telemetry', 'on']]);

    // ----- Jogo: modo desempenho genérico (Android 12+) -----
    $add(['id' => 'game.mode', 'group' => 'Apps e jogos', 'label' => 'Modo do jogo (genérico)',
          'desc' => 'Define performance/battery/standard para qualquer jogo ou app.',
          'help' => 'Usa o Game Mode do Android 12+: "performance" prioriza FPS, "battery" prioriza economia, "standard" deixa o sistema decidir. Funciona em qualquer app, não só no Free Fire.',
          'argv' => ['game-per-app.sh', 'mode', '{pkg}', '{mode}'],
          'params' => [
              ['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo'],
              ['name' => 'mode', 'type' => 'enum', 'label' => 'Modo',
               'options' => ['performance', 'standard', 'battery'], 'default' => 'performance']],
          'risk' => 'careful']);

    // ----- Debloat: preview com classificação de risco -----
    $add(['id' => 'debloat.preview', 'group' => 'Debloat', 'label' => 'Prévia: ver antes de remover',
          'desc' => 'Mostra exatamente o que seria removido, com o motivo, sem alterar nada.',
          'help' => 'A prévia lista, pacote por pacote, o que a remoção faria e POR QUE cada app está na lista (anúncios, jogo pré-instalado, app de operadora...). Ela também mostra só o que existe de fato no SEU aparelho. Nada é alterado. Use sempre antes de remover.',
          'argv' => ['debloat.sh', 'preview', '{alvo}'],
          'params' => [['name' => 'alvo', 'type' => 'enum', 'label' => 'Lista',
                        'options' => ['universal', 'marca', 'samsung', 'xiaomi', 'motorola',
                                      'oneplus', 'realme', 'vivo', 'huawei', 'asus', 'sony',
                                      'lg', 'transsion', 'leve', 'medio', 'pesado'],
                        'default' => 'universal']]]);

    // ----- Debloat curado: universal e por marca (listas do UAD) -----
    $add(['id' => 'debloat.universal', 'group' => 'Debloat', 'label' => 'Debloat universal',
          'desc' => 'Remove o bloat que vem em qualquer aparelho: Facebook, Amazon, Netflix, jogos.',
          'help' => 'Remove apps que praticamente toda fabricante empurra e você provavelmente nunca usou: Facebook (e os serviços escondidos dele), Amazon, Netflix, LinkedIn, Booking, eBay, jogos pré-instalados e afins. A lista é curada e só contém pacotes com veredito "Recommended" do Universal Android Debloater (a base usada pela comunidade). A remoção é por usuário e reversível em "Reverter tudo". Nada essencial (câmera, galeria, telefone, mensagens, teclado, Bluetooth, Play Services) entra nesta lista.',
          'argv' => ['debloat.sh', 'universal'], 'risk' => 'careful', 'confirm' => true, 'timeout' => 300]);

    $add(['id' => 'debloat.marca', 'group' => 'Debloat', 'label' => 'Debloat da minha marca',
          'desc' => 'Detecta a marca do aparelho e remove o bloat daquela fabricante.',
          'help' => 'Lê o fabricante do seu aparelho (Samsung, Xiaomi, Motorola, OnePlus, Realme, Vivo, Huawei, Asus, Sony, LG, Tecno...) e aplica a lista curada daquela marca: apps de loja, telemetria, assistentes redundantes, jogos e novidades pré-instaladas. É a lista que mais libera espaço e RAM, porque o bloat de fabricante é o que mais pesa. Reversível em "Reverter tudo".',
          'argv' => ['debloat.sh', 'marca'], 'risk' => 'careful', 'confirm' => true, 'timeout' => 300]);

    $add(['id' => 'debloat.brand', 'group' => 'Debloat', 'label' => 'Debloat por marca (escolher)',
          'desc' => 'Escolhe a marca na mão e remove o bloat dela.',
          'help' => 'Igual ao "Debloat da minha marca", mas você escolhe qual marca usar — útil quando o aparelho é de uma submarca ou quando você quer limpar um aparelho de outra pessoa.',
          'argv' => ['debloat.sh', '{marca}'],
          'params' => [['name' => 'marca', 'type' => 'enum', 'label' => 'Marca',
                        'options' => ['samsung', 'xiaomi', 'motorola', 'oneplus', 'realme',
                                      'vivo', 'huawei', 'asus', 'sony', 'lg', 'transsion'],
                        'default' => 'samsung']],
          'risk' => 'careful', 'confirm' => true, 'timeout' => 300]);

    $add(['id' => 'wifi_off', 'group' => 'DNS e rede', 'card' => false, 'label' => 'Wi-Fi: voltar ao padrão',
          'desc' => 'Religa a varredura e a economia de Wi-Fi.',
          'help' => 'Devolve a varredura de Wi-Fi em segundo plano e a economia de energia ao padrão do Android.',
          'argv' => ['adb-tweaks.sh', 'wifi_off']]);
    $add(['id' => 'net_tune', 'group' => 'DNS e rede', 'label' => 'Ajustes finos de conexão',
          'desc' => 'DNS DoT, servidor de hora e sem varredura de fundo.',
          'help' => 'Ajustes que deixam a conexão mais estável sem risco: DNS privado em modo hostname (DoT), servidor de hora fixo (relógio errado quebra TLS e derruba conexão), não largar o Wi-Fi bom pelo móvel e varredura de fundo desligada. Desligue a qualquer momento.',
          'argv' => ['adb-tweaks.sh', 'net_tune', 'on']]);
    $add(['id' => 'net_tune_off', 'group' => 'DNS e rede', 'card' => false, 'label' => 'Ajustes finos: desligar',
          'desc' => 'Devolve servidor de hora e preferências de rede ao padrão.',
          'help' => 'Desfaz os ajustes finos de conexão e devolve as preferências de rede ao padrão.',
          'argv' => ['adb-tweaks.sh', 'net_tune', 'off']]);
    // ----- Wi-Fi e rede -----
    $add(['id' => 'wifi', 'group' => 'DNS e rede', 'label' => 'Ajustes de Wi-Fi',
          'desc' => 'Desliga o scan de Wi-Fi em segundo plano e a economia agressiva.',
          'help' => 'O Android fica varrendo redes Wi-Fi o tempo todo, mesmo conectado. Isso gasta bateria e cria picos de uso da CPU. Aqui a varredura em segundo plano é desligada e a economia de energia do Wi-Fi é ligada. Reverte em "Rede: voltar ao automático".',
          'argv' => ['adb-tweaks.sh', 'wifi']]);
    $add(['id' => 'net', 'group' => 'DNS e rede', 'label' => 'Rede / TCP (DNS + buffers)',
          'desc' => 'DNS Cloudflare + buffers TCP maiores para menos travada em jogo.',
          'help' => 'Aumenta os buffers de rede (TCP) e troca o DNS para o Cloudflare. Resultado: menos picos de latência e carregamento mais estável. Não é o mesmo que o perfil de DNS gaming — aqui o foco é o buffer de rede.',
          'argv' => ['adb-tweaks.sh', 'net']]);
    $add(['id' => 'net_reset', 'group' => 'DNS e rede', 'label' => 'Rede: voltar ao automático',
          'desc' => 'Volta o DNS e a rede para o padrão da operadora.',
          'help' => 'Desfaz os ajustes de rede: DNS volta para automático e os buffers deixam de ser forçados. Use se a internet ficar estranha depois de aplicar.',
          'argv' => ['adb-tweaks.sh', 'net_reset']]);

    // ----- Congelar apps (extras) -----
    $add(['id' => 'freezer_off', 'group' => 'Desempenho', 'label' => 'Desligar o congelador',
          'desc' => 'Desliga o congelador de apps em cache do sistema.',
          'help' => 'O congelador do sistema (cached_apps_freezer) pausa apps em segundo plano para liberar RAM. Aqui ele é desligado — útil se algum app parou de receber notificações.',
          'argv' => ['adb-tweaks.sh', 'freezer_off']]);
    $add(['id' => 'freeze_now', 'group' => 'Desempenho', 'label' => 'Congelar agora (aplicar lista)',
          'desc' => 'Congela os apps da lista negra (menos a whitelist).',
          'help' => 'Aplica o congelamento na hora: os apps da lista negra são suspensos, exceto os protegidos pela whitelist. Ganha RAM livre. Reverte em "Descongelar agora".',
          'argv' => ['adb-tweaks.sh', 'freeze_apps'], 'confirm' => true, 'risk' => 'careful']);
    $add(['id' => 'unfreeze_now', 'group' => 'Desempenho', 'label' => 'Descongelar agora (todos)',
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
    $add(['id' => 'snapshot_list', 'group' => 'Geral', 'card' => false, 'label' => 'Ver snapshots salvos',
          'desc' => 'Lista os snapshots que você já tirou.',
          'help' => 'Mostra todas as fotos de configuração que você salvou, com data e id. Serve para escolher qual restaurar.',
          'argv' => ['snapshot.sh', 'list']]);
    $add(['id' => 'snapshot_diff', 'group' => 'Geral', 'card' => false, 'label' => 'Comparar com o último snapshot',
          'desc' => 'Mostra o que mudou desde o snapshot mais recente.',
          'help' => 'Compara as configurações atuais com o último snapshot e lista só o que mudou. Bom para conferir o que o pack alterou.',
          'argv' => ['snapshot.sh', 'diff', 'latest']]);
    $add(['id' => 'snapshot_restore', 'group' => 'Geral', 'card' => false, 'label' => 'Restaurar último snapshot',
          'desc' => 'Volta as configurações para o último snapshot salvo.',
          'help' => 'Devolve o aparelho ao estado do último snapshot: desfaz as mudanças feitas depois dele. É o "botão de voltar" mais seguro.',
          'argv' => ['snapshot.sh', 'restore', 'latest'], 'risk' => 'careful', 'confirm' => true]);

    // ----- Diagnóstico -----
    $add(['id' => 'diag.profile', 'group' => 'Sistema', 'label' => 'Perfil do aparelho (SoC/GPU)',
          'desc' => 'Detecta o processador, a GPU e o que combina com o seu aparelho.',
          'help' => 'Lê as informações do seu aparelho (família do processador, GPU, kernel) e recomenda quais otimizações profundas tendem a funcionar melhor. Não muda nada — só informa.',
          'argv' => ['device-profile.sh']]);
    $add(['id' => 'diag.profile_save', 'group' => 'Sistema', 'label' => 'Salvar perfil do aparelho',
          'desc' => 'Salva o relatório do aparelho num arquivo.',
          'help' => 'Gera um arquivo com o perfil completo do aparelho. Útil para guardar ou compartilhar ao pedir ajuda.',
          'argv' => ['device-profile.sh', 'save']]);
    $add(['id' => 'diag.deep_detect', 'group' => 'Sistema', 'label' => 'Detectar hardware',
          'desc' => 'Mostra CPU, GPU, kernel e recomendações.',
          'help' => 'Versão aprofundada da detecção, com detalhes de CPU, GPU, kernel e zonas térmicas. Só leitura.',
          'argv' => ['deep-tune.sh', 'detect']]);
    $add(['id' => 'diag.dns', 'group' => 'Sistema', 'label' => 'Ver DNS atual',
          'desc' => 'Mostra qual perfil de DNS está ativo agora.',
          'help' => 'Confere se o DNS privado está ligado e qual servidor está em uso.',
          'argv' => ['dns.sh', 'status']]);
    $add(['id' => 'diag.bench_before', 'group' => 'Sistema', 'label' => 'Benchmark: marcar ANTES',
          'desc' => 'Guarda o estado atual para comparar depois de otimizar.',
          'help' => 'Tira uma medida de referência antes de aplicar as otimizações. Depois use "marcar DEPOIS" para ver o ganho. Dica: use os nomes "antes" e "depois".',
          'argv' => ['bench.sh', 'save', '{label}'],
          'params' => [['name' => 'label', 'type' => 'name', 'label' => 'Rótulo', 'default' => 'antes']]]);
    $add(['id' => 'diag.bench_after', 'group' => 'Sistema', 'label' => 'Benchmark: marcar DEPOIS',
          'desc' => 'Mede de novo e compara com o "antes".',
          'help' => 'Coleta o estado atual e compara com a medida anterior, mostrando a diferença. Rode depois de aplicar o pack.',
          'argv' => ['bench.sh', 'run', '{label}'],
          'params' => [['name' => 'label', 'type' => 'name', 'label' => 'Rótulo', 'default' => 'depois']]]);
    $add(['id' => 'diag.bench_report', 'group' => 'Sistema', 'card' => false, 'label' => 'Benchmark: comparar duas medidas',
          'desc' => 'Mostra o relatório comparando dois rótulos salvos.',
          'help' => 'Gera o relatório comparativo entre duas medidas (por padrão "antes" e "depois"), com a diferença de RAM livre, temperatura, bateria, carga de CPU, frequência e refresh. É o "prove com número" do que mudou.',
          'argv' => ['bench.sh', 'report', '{a}', '{b}'],
          'params' => [
              ['name' => 'a', 'type' => 'name', 'label' => 'Antes', 'default' => 'antes'],
              ['name' => 'b', 'type' => 'name', 'label' => 'Depois', 'default' => 'depois']]]);
    $add(['id' => 'diag.bench_app', 'group' => 'Sistema', 'card' => false, 'label' => 'Benchmark: tempo de abrir um app',
          'desc' => 'Mede em milissegundos quanto um app leva para abrir.',
          'help' => 'Abre o app escolhido e mede o tempo até ele aparecer na tela, em milissegundos. Rode antes e depois de compilar (ART) ou de aplicar o pack para ver o ganho real de abertura.',
          'argv' => ['bench.sh', 'app', '{pkg}', '{n}'],
          'params' => [
              ['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo'],
              ['name' => 'n', 'type' => 'name', 'label' => 'Rótulo', 'default' => 'abertura']],
          'risk' => 'careful']);

    // ----- Módulos (plugins do pack) -----
    $add(['id' => 'module.run', 'group' => 'Sistema', 'label' => 'Executar um módulo',
          'desc' => 'Roda um dos módulos/plugins incluídos no pack.',
          'help' => 'Os módulos são os complementos (tweaks, touch, GPU, bateria). Digite o nome exato do módulo — veja a lista na aba Sistema. Ação reversível conforme o módulo.',
          'argv' => ['modules.sh', 'run', '{name}'],
          'params' => [['name' => 'name', 'type' => 'name', 'label' => 'Nome do módulo']],
          'risk' => 'careful', 'confirm' => true, 'timeout' => 180]);
    $add(['id' => 'module.list', 'group' => 'Sistema', 'label' => 'Listar módulos e plugins',
          'desc' => 'Mostra os módulos/plugins incluídos no pack.',
          'help' => 'Lista os módulos (Magisk/KernelSU/APatch/AxManager) e plugins que vieram na pasta do pack, com o nome exato de cada um. Use o nome daqui para "Executar um módulo". Só leitura.',
          'argv' => ['modules.sh', 'list']]);
    $add(['id' => 'module.info', 'group' => 'Sistema', 'card' => false, 'label' => 'Módulo: ver os scripts',
          'desc' => 'Mostra os scripts de um módulo (action, service, uninstall…).',
          'help' => 'Mostra quais scripts um módulo traz (action.sh, service.sh, uninstall.sh, apply.sh…) para você saber o que ele faz antes de executar. Só leitura.',
          'argv' => ['modules.sh', 'info', '{name}'],
          'params' => [['name' => 'name', 'type' => 'name', 'label' => 'Nome do módulo']]]);
    $add(['id' => 'module.actions', 'group' => 'Sistema', 'card' => false, 'label' => 'Módulo: listar executáveis',
          'desc' => 'Lista os scripts executáveis de um módulo.',
          'help' => 'Lista os scripts que podem ser rodados de um módulo, para usar com a execução de um script específico. Só leitura.',
          'argv' => ['modules.sh', 'actions', '{name}'],
          'params' => [['name' => 'name', 'type' => 'name', 'label' => 'Nome do módulo']]]);

    // ----- Touch: abrir o jogo -----
    $add(['id' => 'ff_open', 'group' => 'Display & Touch', 'label' => 'Abrir o Free Fire',
          'desc' => 'Abre o jogo (útil depois de aplicar os ajustes).',
          'help' => 'Manda o Free Fire abrir. Use depois de aplicar touch/modo de jogo para já entrar otimizado.',
          'argv' => ['adb-tweaks.sh', 'ff_open']]);
    $add(['id' => 'game_open', 'group' => 'Display & Touch', 'label' => 'Abrir o meu jogo (modo gamer)',
          'desc' => 'Abre o jogo que você escolher — FF, FF MAX, CODM, Minecraft, o que for.',
          'help' => 'Escolha o jogo e ele vira o "jogo do modo gamer". O pack deixa o jogo SEM RESTRIÇÃO de bateria, limita o aparelho a no máximo 4 apps em segundo plano (mais RAM livre para o jogo), tira o jogo do congelador e liga o anti-relog — assim ele não fecha e não volta para a tela de login quando você troca de app. Depois abre o jogo já em performance. A escolha fica salva: da próxima vez é só tocar de novo. Serve para qualquer jogo instalado, não só Free Fire.',
          'argv' => ['adb-tweaks.sh', 'game_open', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'Jogo', 'optional' => true]]]);
    $add(['id' => 'game.keepalive', 'group' => 'Display & Touch', 'label' => 'Meu jogo: bateria sem restrição + anti-relog',
          'desc' => 'Sem restrição de bateria, no máximo 4 apps em 2º plano e sem relogar.',
          'help' => 'Aplica só a proteção anti-relog ao jogo escolhido no modo gamer, sem abrir o jogo. Deixa ele SEM RESTRIÇÃO de bateria (fora do Doze e livre em segundo plano), limita o aparelho a no máximo 4 apps em segundo plano para sobrar RAM ao jogo, põe no balde ativo de standby, tira do congelador e, com root, sobe a prioridade de memória dos processos. É o ajuste que evita o jogo fechar e pedir login de novo no meio da partida. Reverta em "Deixar de manter o app" ou "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'game_keepalive', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'Jogo', 'optional' => true]],
          'risk' => 'careful']);

    // ----- Configs: como o pack fala com o Android (sem root) -----
    $add(['id' => 'config.set', 'group' => 'Sistema', 'label' => 'Definir conexão do pack',
          'desc' => 'Escolha como o pack acessa o Android: Shizuku (rish), depuração USB, ADB por Wi-Fi, root ou automático.',
          'help' => 'Define por onde o pack manda os comandos. Sem root, use o Shizuku (rish) no celular, a depuração USB no PC (cabo — no celular só aparece o aviso "Permitir depuração USB", sem parear) ou a depuração por Wi-Fi (ADB, informe o IP:porta do aparelho). "automático" deixa o pack detectar sozinho. Depois clique em "Testar conexão" para confirmar.',
          'argv' => ['config.sh', 'set', '{mode}', '{target}'],
          'params' => [
              ['name' => 'mode', 'type' => 'name', 'label' => 'Modo', 'default' => 'auto'],
              ['name' => 'target', 'type' => 'text', 'label' => 'Endereço (só p/ ADB Wi-Fi: host:porta)', 'optional' => true],
          ]]);
    $add(['id' => 'config.test', 'group' => 'Sistema', 'label' => 'Testar conexão',
          'desc' => 'Confere de verdade se o pack consegue mandar comandos ao aparelho.',
          'help' => 'Faz um teste real: lê o modelo do aparelho, a versão do Android e tenta ler/gravar um ajuste. Se falhar, diz o que falta (Shizuku ativo ou depuração por Wi-Fi ligada).',
          'argv' => ['config.sh', 'test']]);
    $add(['id' => 'config.show', 'group' => 'Sistema', 'label' => 'Ver configuração',
          'desc' => 'Mostra o modo atual e o que foi detectado.',
          'help' => 'Mostra o arquivo de configuração, o modo salvo e o que o pack detectou agora (Shizuku/ADB/root/local). Só leitura.',
          'argv' => ['config.sh', 'show']]);
    $add(['id' => 'config.reset', 'group' => 'Sistema', 'label' => 'Voltar ao automático',
          'desc' => 'Apaga a configuração e volta à detecção automática.',
          'help' => 'Remove o arquivo de configuração. O pack volta a detectar sozinho o melhor caminho (Shizuku, ADB, root ou local).',
          'argv' => ['config.sh', 'reset']]);

    // ----- Configs: permissões e segundo plano (feitas pelo shell) -----
    $add(['id' => 'perm.app', 'group' => 'Sistema', 'card' => false, 'label' => 'Permitir o app do pack',
          'desc' => 'Libera o app do pack para rodar em segundo plano, sem restrição de bateria e fora do Doze.',
          'help' => 'Sem isso o Android adormece o app do pack: as otimizações param sozinhas, o som não toca e o acesso cai. Aqui o app entra na lista de isenção do Doze, ganha permissão de rodar em segundo plano e de manter a CPU acordada. Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'perm_app'], 'timeout' => 120]);
    $add(['id' => 'perm.ff', 'group' => 'Sistema', 'card' => false, 'label' => 'Permitir os Free Fire',
          'desc' => 'Libera o Free Fire e o Free Fire MAX para rodar em segundo plano sem serem congelados.',
          'help' => 'Impede o sistema de congelar o Free Fire e o Free Fire MAX quando você troca de app ou a tela apaga — evita o jogo fechar no meio da partida. Também tira a restrição de bateria. Se o seu jogo é outro (CODM, Minecraft...), use "Permitir o meu jogo". Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'perm_ff'], 'timeout' => 120]);
    $add(['id' => 'perm.game', 'group' => 'Sistema', 'label' => 'Permitir o meu jogo',
          'desc' => 'Libera o jogo escolhido no modo gamer (o mesmo do botão da Home).',
          'help' => 'Aplica ao jogo escolhido no modo gamer a mesma isenção do Free Fire: fora do Doze, sem restrição de bateria e livre para rodar em segundo plano — assim ele não fecha quando você troca de app. Escolha o jogo na Home, em "Modo Competitivo". Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'perm_game', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'Jogo', 'optional' => true]],
          'timeout' => 120]);
    $add(['id' => 'perm.battery', 'group' => 'Sistema', 'card' => false, 'label' => 'Bateria sem economia agressiva',
          'desc' => 'Desliga a economia de energia e o App Standby (global, não só para um app).',
          'help' => 'Isto é global do aparelho, não é permissão de um app: desliga o modo de economia de energia (low_power), a gestão adaptativa de bateria e o App Standby (que suspende apps em segundo plano). É o que deixa o pack e o jogo "acordados" sem o sistema cortar o desempenho. NÃO use no dia a dia se você prioriza duração de bateria. Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'perm_battery'], 'timeout' => 120]);
    $add(['id' => 'perm.app_off', 'group' => 'Sistema', 'card' => false, 'label' => 'App do pack: remover isenções',
          'desc' => 'Devolve o app do pack ao controle normal de bateria.',
          'help' => 'Remove as isenções de segundo plano e de bateria do app do pack, devolvendo o controle ao Android.',
          'argv' => ['adb-tweaks.sh', 'perm_revoke', 'com.otm.pack']]);
    $add(['id' => 'perm.ff_off', 'group' => 'Sistema', 'card' => false, 'label' => 'Free Fire: remover isenções',
          'desc' => 'Devolve os Free Fire ao controle normal de bateria.',
          'help' => 'Remove as isenções de segundo plano e de bateria dos Free Fire, devolvendo o controle ao Android.',
          'argv' => ['adb-tweaks.sh', 'perm_revoke_ff']]);
    $add(['id' => 'perm.game_off', 'group' => 'Sistema', 'card' => false, 'label' => 'Meu jogo: remover isenções',
          'desc' => 'Devolve o jogo escolhido ao controle normal de bateria.',
          'help' => 'Remove as isenções de segundo plano e de bateria do jogo escolhido, devolvendo o controle ao Android.',
          'argv' => ['adb-tweaks.sh', 'perm_revoke_game', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'App/jogo']]]);
    $add(['id' => 'perm.battery_off', 'group' => 'Sistema', 'card' => false, 'label' => 'Bateria: voltar ao padrão',
          'desc' => 'Religa a economia de bateria e o App Standby.',
          'help' => 'Religa a economia de bateria adaptativa e o App Standby, devolvendo o gerenciamento de energia ao Android.',
          'argv' => ['adb-tweaks.sh', 'perm_battery_off']]);
    $add(['id' => 'perm.all', 'group' => 'Sistema', 'label' => 'Aplicar todas as permissões',
          'desc' => 'App do pack + Free Fire + bateria, de uma vez.',
          'help' => 'Faz tudo o que o pack precisa para funcionar em segundo plano: libera o app do pack, libera o Free Fire e desliga a economia agressiva de bateria. É o "recomendado" para quem não quer mexer um por um.',
          'argv' => ['adb-tweaks.sh', 'perm_all'], 'timeout' => 180]);

    // ----- Configs: aparência do painel (feita pelo próprio painel) -----
    $add(['id' => 'appearance', 'group' => 'Sistema', 'label' => 'Aparência e som',
          'desc' => 'Permissões, tema, cor, fonte, DPI e som do app.',
          'help' => 'Abre as configurações do painel: as permissões que o app precisa para funcionar (bateria, segundo plano, Doze), o tema (claro, escuro ou automático), a cor de destaque, a fonte, o DPI do app e ligar/desligar os sons. Fica salvo neste aparelho.',
          'argv' => [], 'ui' => 'appearance']);

    // ----- Perfil personalizado: o painel monta as opções e manda ligadas -----
    $add(['id' => 'profile.custom', 'group' => 'Geral', 'label' => 'Perfil personalizado',
          'desc' => 'Você escolhe o que aplicar: animações, RAM, Hz, toque, limpeza e muito mais.',
          'help' => 'Abre um menu onde você liga só o que quiser. São mais de 40 recursos independentes, agrupados por tema: desempenho (animações, ART/AOT, modo desempenho, telemetria), memória (limite de apps em 2º plano, hibernar, congelar, podar caches, encerrar 2º plano, processos fantasma), gráficos (GPU, motor gráfico, display/HWUI, modo jogo profundo), tela (taxa, resolução, barras do sistema, bateria em %, segundos no relógio), toque (perfil, latência, janela multitouch), rede (DNS, buffers TCP, latência/ping, Wi-Fi, rede móvel), bateria (economia, Doze, longevidade) e notificações (não perturbe, foco de jogo, menos notificações). Ao aplicar, o pack parte de um estado limpo e liga apenas os recursos marcados. Tudo é reversível em "Perfil personalizado: desligar".',
          'argv' => [], 'ui' => 'customprofile']);
    $add(['id' => 'profile.custom.apply', 'group' => 'Geral', 'card' => false, 'label' => 'Aplicar perfil personalizado',
          'desc' => 'Liga os recursos escolhidos no menu do perfil personalizado.',
          'help' => 'Aplica o conjunto que você montou no menu do perfil personalizado. O pack reverte o estado antes e liga só o que você marcou — nada além disso. São dezenas de ajustes independentes: desempenho, memória, gráficos, tela, toque, rede, bateria, notificações e limpeza.',
          // O argv sai da MESMA lista das opções: assim uma opção nova entra no
          // painel e no script sem ninguém precisar lembrar de mexer em dois
          // lugares (era assim que os dois ficavam fora de sincronia).
          'argv' => array_merge(
              ['profile-custom.sh', 'apply'],
              array_map(static fn(array $c): string => '{' . $c['k'] . '}', otm_custom_profile_opts()),
          ),
          'params' => array_map(static function (array $c): array {
              // No toggle o switch manda 'off' ou 'on'; nos dois casos o valor
              // enviado é o da chave 'tgl'. Por isso o default é sempre o
              // "desligado": ligar é escolha do usuário, nunca o de fábrica.
              $tgl = ($c['kind'] ?? 'seg') === 'toggle';
              $opts = $tgl ? [$c['tgl']['off'], $c['tgl']['on']] : array_column($c['opts'], 0);
              return ['name' => $c['k'], 'type' => 'enum', 'label' => $c['t'],
                      'options' => $opts, 'default' => $opts[0]];
          }, otm_custom_profile_opts()),
          'confirm' => true, 'risk' => 'careful', 'timeout' => 900]);
    $add(['id' => 'profile.custom.off', 'group' => 'Geral', 'card' => false, 'label' => 'Perfil personalizado: desligar',
          'desc' => 'Desfaz o perfil personalizado e volta o aparelho ao padrão.',
          'help' => 'Reverte tudo o que o perfil personalizado aplicou e devolve o aparelho ao estado de fábrica de configuração. A sua escolha de recursos fica salva para aplicar de novo depois.',
          'argv' => ['profile-custom.sh', 'off'], 'confirm' => true, 'risk' => 'safe', 'timeout' => 300]);

    // --- modos prontos (scripts/profiles.sh) ----------------------------------
    // Os cartões do "Game Lab" chamam ESTAS ações. Antes cada botão rodava uma
    // linha só (Batata = clean, Econômico = trocar Hz, Ultra Fluido = taxa de
    // tela), então o cartão prometia quatro itens e entregava um. Agora o modo
    // aplica o conjunto inteiro e cada um fica num escopo próprio: dá para
    // desfazer SÓ aquele modo (mode.off), sem mexer no resto.
    $add(['id' => 'mode.batata', 'group' => 'Geral', 'card' => false,
          'label' => 'Ativar Modo Batata',
          'desc' => 'Aparelho de 2-4GB: animações 0, poucos apps em 2º plano e RAM livre.',
          'help' => 'Aplica o conjunto inteiro do Modo Batata: animações desligadas (0x), no máximo 2 apps em segundo plano, ajustes obscuros (menos kills em 2º plano), recompilação dos apps agendada (dexopt) e limpeza de RAM. É tudo reversível em "Desativar modo ativo".',
          'argv' => ['profiles.sh', 'apply', 'batata'], 'confirm' => true, 'risk' => 'careful', 'timeout' => 900]);
    $add(['id' => 'mode.competitivo', 'group' => 'Geral', 'card' => false,
          'label' => 'Ativar Modo Competitivo',
          'desc' => 'Jogo: driver de jogo, anti-relog, DND, sensi e 4 apps em 2º plano.',
          'help' => 'Aplica o conjunto inteiro do Modo Competitivo e abre o jogo escolhido: driver de jogo para todos os apps, Não Perturbe, foco de jogo (DND extremo), latência de toque forte, perfil de toque "speed" e o anti-relog (jogo sem restrição de bateria, no máximo 4 apps em segundo plano e balde ativo). Escolha o jogo no campo do cartão. Reversível em "Desativar modo ativo".',
          'argv' => ['profiles.sh', 'apply', 'competitivo', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'Pacote do jogo', 'optional' => true]],
          'confirm' => true, 'risk' => 'careful', 'timeout' => 600]);
    $add(['id' => 'mode.fluido', 'group' => 'Geral', 'card' => false,
          'label' => 'Ativar Modo 90Hz/120Hz Ultra Fluido',
          'desc' => 'Taxa no pico, speed-profile, buffer de log mínimo e trava térmica.',
          'help' => 'Aplica o conjunto inteiro do Modo Ultra Fluido: taxa de atualização forçada no pico, animações 0 e toque sem atraso, GPU na interface, telemetria/log reduzidos ao mínimo, trava térmica preventiva, mais RAM livre e recompilação dos apps (speed-profile). Reversível em "Desativar modo ativo".',
          'argv' => ['profiles.sh', 'apply', 'fluido'], 'confirm' => true, 'risk' => 'careful', 'timeout' => 1200]);
    $add(['id' => 'mode.economico', 'group' => 'Geral', 'card' => false,
          'label' => 'Ativar Modo Econômico',
          'desc' => '60Hz, economia de energia, Doze rápido e menos 2º plano.',
          'help' => 'Aplica o conjunto inteiro do Modo Econômico: taxa de tela em 60Hz, economia de energia ligada, sono profundo (Doze) rápido, Wi-Fi sem economia/scan, menos apps em segundo plano e telemetria/log desligados. Reversível em "Desativar modo ativo".',
          'argv' => ['profiles.sh', 'apply', 'economico'], 'confirm' => true, 'risk' => 'careful', 'timeout' => 600]);
    $add(['id' => 'mode.off', 'group' => 'Geral', 'card' => false,
          'label' => 'Desativar modo ativo',
          'desc' => 'Desfaz SÓ o modo aplicado (Batata, Competitivo, Ultra Fluido ou Econômico).',
          'help' => 'Reverte apenas o que o modo ativo aplicou — sem tocar no que outras ações (ou outros modos já desfeitos) deixaram. O aparelho volta ao estado anterior a este modo.',
          'argv' => ['profiles.sh', 'off'], 'confirm' => true, 'risk' => 'safe', 'timeout' => 300]);
    $add(['id' => 'mode.status', 'group' => 'Geral', 'card' => false,
          'label' => 'Modos: ver o que está ativo',
          'desc' => 'Mostra o modo aplicado por último e os que estão ativos.',
          'help' => 'Mostra qual modo está ativo e quais têm reversão registrada. Só leitura.',
          'argv' => ['profiles.sh', 'status']]);

    // --- otimizações escondidas do Android (scripts/hidden-tune.sh) -----------
    // Ações sem card: quem chama são os interruptores da aba Geral (o par
    // liga/desliga de cada módulo). `hidden.all_on/all_off/trim` são chamadas
    // pelo bloco "otimizações escondidas" do painel.
    $add(['id' => 'hidden.proc_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Constantes do ActivityManager',
          'desc' => 'Ajusta memória, jobs e serviços de 2º plano (escondido).',
          'help' => 'Mexe nas constantes internas do ActivityManager: cache de processos, limites de memória por app, tempos de serviço em segundo plano e a verificação periódica de CPU. É o ajuste de maior impacto para o sistema parar de "acordar à toa" e o jogo não ser fechado por falta de RAM.',
          'argv' => ['hidden-tune.sh', 'proc', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.proc_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Constantes do ActivityManager: padrão',
          'desc' => 'Devolve as constantes ao padrão de fábrica.',
          'help' => 'Apaga a chave de constantes do ActivityManager e o sistema volta ao padrão de fábrica.',
          'argv' => ['hidden-tune.sh', 'proc', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.verify_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Menos checagem de assinatura',
          'desc' => 'Corta a verificação de pacotes a cada instalação.',
          'help' => 'O verificador de pacotes confere a assinatura dos apps a cada instalação e em cada boot. Em aparelho com muitos apps isso custa tempo e leitura de disco. Desligar não afeta apps da Play Store (a loja tem o próprio controle).',
          'argv' => ['hidden-tune.sh', 'verify', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.verify_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Checagem de assinatura: padrão',
          'desc' => 'Devolve a verificação de pacotes.',
          'help' => 'Volta a verificar a assinatura dos apps a cada instalação.',
          'argv' => ['hidden-tune.sh', 'verify', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.bg_on', 'group' => 'Geral', 'card' => false,
          'label' => 'App Standby agressivo',
          'desc' => 'Restringe apps ociosos em segundo plano.',
          'help' => 'Põe apps ociosos em standby e restringe o que eles podem fazer em segundo plano. Reduz o consumo de CPU e bateria "à toa" sem impedir o app que você está usando.',
          'argv' => ['hidden-tune.sh', 'bg', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.bg_off', 'group' => 'Geral', 'card' => false,
          'label' => 'App Standby: padrão',
          'desc' => 'Devolve a restrição de 2º plano ao padrão.',
          'help' => 'Volta a restrição automática de apps em segundo plano ao padrão do sistema.',
          'argv' => ['hidden-tune.sh', 'bg', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.aot_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Compilar apps (abre mais rápido)',
          'desc' => 'Compila os apps em código nativo (AOT).',
          'help' => 'Sem compilação, cada app é interpretado na primeira abertura e compila enquanto você usa — é a causa do "abre devagar e engasga". Aqui o sistema compila tudo em código nativo, com prioridade máxima para o jogo. Pode demorar alguns minutos e o ganho aparece nas próximas aberturas.',
          'argv' => ['hidden-tune.sh', 'aot', 'on'], 'risk' => 'safe', 'timeout' => 600]);
    $add(['id' => 'hidden.aot_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Compilação: padrão',
          'desc' => 'Volta a compilar só o perfil de uso.',
          'help' => 'Devolve o modo de compilação ao padrão (compila só o perfil de uso, não o app inteiro).',
          'argv' => ['hidden-tune.sh', 'aot', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.ram_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Compactação de memória',
          'desc' => 'zRAM mais agressivo e menos pressão de cache.',
          'help' => 'Ajusta a compactação de memória (zRAM) e os limites de água do kernel. O sistema compacta a RAM em vez de fechar o app, então sobra mais memória para o jogo. Custa um pouco de CPU.',
          'argv' => ['hidden-tune.sh', 'ram', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.ram_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Compactação: padrão',
          'desc' => 'Devolve a compactação ao padrão.',
          'help' => 'Devolve a compactação de memória ao padrão do sistema.',
          'argv' => ['hidden-tune.sh', 'ram', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.gc_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Coleta de lixo sem travar',
          'desc' => 'Coleta de lixo em paralelo (menos engasgo).',
          'help' => 'Liga a coleta de lixo concorrente: o Android coleta memória em paralelo em vez de pausar o app. É o que causa aquela travada de meio segundo no meio da partida.',
          'argv' => ['hidden-tune.sh', 'gc', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.gc_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Coleta de lixo: padrão',
          'desc' => 'Devolve a coleta de lixo ao padrão.',
          'help' => 'Devolve a coleta de lixo ao comportamento padrão do sistema.',
          'argv' => ['hidden-tune.sh', 'gc', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.freezer_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Congelar apps em cache',
          'desc' => 'Congela o que está em cache em vez de matar.',
          'help' => 'Congela os apps que estão em cache: eles param de consumir CPU, mas voltam na hora em que você abre de novo (sem recarregar). É o que o Hail/Greenify fazem, aqui pelo mecanismo do próprio Android.',
          'argv' => ['hidden-tune.sh', 'freezer', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.freezer_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Congelador: padrão',
          'desc' => 'Devolve o congelador ao padrão.',
          'help' => 'Devolve o congelamento de apps em cache ao padrão do sistema.',
          'argv' => ['hidden-tune.sh', 'freezer', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.gpu_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Driver gráfico para os apps',
          'desc' => 'Libera o driver de jogo para todos os apps.',
          'help' => 'Libera o driver gráfico de jogo para todos os apps. O driver de jogo fala mais direto com a GPU, tirando uma camada de tradução no caminho dos frames.',
          'argv' => ['hidden-tune.sh', 'gpu', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.gpu_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Driver gráfico: padrão',
          'desc' => 'Devolve o driver gráfico ao padrão.',
          'help' => 'Devolve a seleção de driver gráfico ao padrão do sistema.',
          'argv' => ['hidden-tune.sh', 'gpu', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.netstats_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Parar estatísticas de rede',
          'desc' => 'O sistema para de gravar o uso de dados por app.',
          'help' => 'O Android coleta o uso de dados de cada app o tempo todo e grava em disco. Parar isso reduz leitura/escrita no armazenamento e um pouco de CPU; só deixa de existir o gráfico de "uso de dados por app" nas configurações.',
          'argv' => ['hidden-tune.sh', 'netstats', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.netstats_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Estatísticas de rede: padrão',
          'desc' => 'Volta a coletar o uso de dados por app.',
          'help' => 'Volta a coletar as estatísticas de rede por app.',
          'argv' => ['hidden-tune.sh', 'netstats', 'off'], 'risk' => 'safe']);
    $add(['id' => 'hidden.trim', 'group' => 'Geral', 'card' => false,
          'label' => 'TRIM do armazenamento',
          'desc' => 'Limpa os blocos livres do armazenamento (uma vez).',
          'help' => 'Roda o TRIM sob demanda: o armazenamento avisa o chip quais blocos estão livres, o que mantém a velocidade de leitura com o tempo. É uma limpeza pontual e segura (não tem o que desfazer).',
          'argv' => ['hidden-tune.sh', 'trim', 'on'], 'risk' => 'safe']);
    $add(['id' => 'hidden.all_on', 'group' => 'Geral', 'card' => false,
          'label' => 'Aplicar TODAS as otimizações escondidas',
          'desc' => 'Liga de uma vez tudo que o Android esconde.',
          'help' => 'Liga de uma vez todos os ajustes escondidos: constantes do ActivityManager, verificador de pacotes, App Standby, compilação AOT, compactação de memória, coleta de lixo, congelador, driver gráfico, estatísticas de rede e TRIM. Tudo é reversível em "Reverter TUDO".',
          'argv' => ['hidden-tune.sh', 'all', 'on'], 'risk' => 'safe', 'timeout' => 900]);
    $add(['id' => 'hidden.all_off', 'group' => 'Geral', 'card' => false,
          'label' => 'Desligar TODAS as otimizações escondidas',
          'desc' => 'Devolve tudo ao padrão de fábrica.',
          'help' => 'Devolve todos os ajustes escondidos ao padrão de fábrica de uma vez.',
          'argv' => ['hidden-tune.sh', 'all', 'off'], 'risk' => 'safe', 'timeout' => 900]);

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
        if ($val === '') {
            if (!empty($p['optional'])) { $resolved['{' . $name . '}'] = ''; continue; }
            return ['ok' => false, 'out' => "faltou o parâmetro '$name'"];
        }
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
            case 'enum':
                if (!in_array($val, $p['options'] ?? [], true)) {
                    return ['ok' => false, 'out' => "$name inválido (use: " . implode('|', $p['options'] ?? []) . ")"];
                }
                break;
            default:
                if (!otm_valid_text($val)) return ['ok' => false, 'out' => "$name inválido"];
        }
        $resolved['{' . $name . '}'] = $val;
    }

    // monta o argv trocando os placeholders
    $argv = [];
    foreach ($a['argv'] as $piece) {
        if (isset($resolved[$piece])) {
            if ($resolved[$piece] === '') continue;   // parâmetro opcional vazio: não passa
            $argv[] = $resolved[$piece];
        } else {
            $argv[] = $piece;
        }
    }
    // backup cifrado: não roda script direto — o PHP cifra/decifra em volta
    // (mesmo desenho do app, onde quem cifra é o Keystore).
    if ($id === 'backup.export') { $r = otm_backup_export(); otm_log($id, $a['label'], ['backup.sh', 'collect'], $r); return $r + ['id' => $id, 'label' => $a['label']]; }
    if ($id === 'backup.import') { $r = otm_backup_import(); otm_log($id, $a['label'], ['backup.sh', 'restore'], $r); return $r + ['id' => $id, 'label' => $a['label']]; }
    if ($id === 'backup.list')   { $r = otm_backup_list();   return $r + ['id' => $id, 'label' => $a['label']]; }

    $script = $argv[0];
    $args = array_slice($argv, 1);

    $t = (int)($a['timeout'] ?? 60);
    $t0 = microtime(true);
    $r = otm_script($script, $args, $t);
    $durMs = (int)round((microtime(true) - $t0) * 1000);

    // verificação REAL: se o script informou quantas mudanças confirmou e nenhuma
    // pegou, isso é erro (não dá para dizer "feito" sem alterar o sistema).
    $v = otm_parse_result($r['out'] ?? '');
    $applies = (int)($v['applies'] ?? 0);
    $changed = (int)($v['changed'] ?? 0);
    $failed  = (int)($v['failed'] ?? 0);
    $applied = $applies > 0;                          // a ação tenta mexer no sistema
    $real    = !$applied || $changed > 0;             // ... e confirmou alguma mudança

    if ($applied && $changed === 0) {
        $r['ok'] = false;
        $r['out'] = trim(($r['out'] ?? '') . "\n\n[!] Nenhuma alteração real no sistema"
            . ($failed > 0 ? " ($failed tentativa(s) não pegaram)" : '') . "."
            . "\nConfira o acesso em Configs: sem Shizuku/ADB/root os ajustes não aplicam.");
        $r['code'] = $r['code'] ?? -1;
    }

    otm_log($id, $a['label'], $argv, $r + ['applies' => $applies, 'changed' => $changed, 'failed' => $failed, 'dur_ms' => $durMs]);
    return $r + ['id' => $id, 'label' => $a['label'], 'applies' => $applies,
                 'changed' => $changed, 'failed' => $failed, 'applied' => $applied, 'real' => $real];
}

// otm_parse_result: extrai a linha #OTM-RESULT ... da saída do script.
function otm_parse_result(string $out): array {
    if (preg_match('/#OTM-RESULT\b(.*)$/m', $out, $m)) {
        $kv = [];
        foreach (preg_split('/\s+/', trim($m[1])) as $tok) {
            if (strpos($tok, '=') === false) continue;
            [$k, $v] = explode('=', $tok, 2);
            $kv[$k] = $v;
        }
        return $kv;
    }
    return [];
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

// Metadados dos apps (nome + ícone) para o seletor com nome/ícone no painel web.
// No PC (site) não há API do Android; o nome/ícone saem do `aapt dump badging`
// quando o aapt existe. Sem aapt, devolve só o pacote (o seletor mostra o pacote).
function otm_apps_meta(): array {
    $pkgs = otm_apps();
    $haveAapt = otm_have('aapt');
    $out = [];
    foreach ($pkgs as $p) {
        $row = ['pkg' => $p, 'label' => '', 'icon' => ''];
        if ($haveAapt) {
            $r = otm_exec(['sh', '-c',
                "aapt dump badging '$p' 2>/dev/null | grep -m1 -E \"application-label:|application-label-pt:\" | head -1"], 8);
            if (preg_match("/application-label(?:-pt)?:\\s*'([^']*)'/", $r['out'], $m)) {
                $row['label'] = $m[1];
            }
        }
        $out[] = $row;
    }
    return $out;
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

// Estado REAL do aparelho para o painel (renderizador, toque, refresh...).
// Lê via panel-state.sh; devolve um array com chaves simples. Nada fictício:
// o que não foi possível ler volta como string vazia.
function otm_state_read(): array {
    $r = otm_script('panel-state.sh', [], 20);
    $line = '';
    foreach (explode("\n", (string)($r['out'] ?? '')) as $l) {
        $l = trim($l);
        if ($l !== '' && $l[0] === '{') { $line = $l; break; }
    }
    $j = $line !== '' ? json_decode($line, true) : null;
    return is_array($j) ? $j : [];
}

// Consumo REAL do aparelho para a home (RAM, CPU, bateria, refresh...).
// Lê via panel-stats.sh; campo que o aparelho não expõe volta "" (o painel
// mostra "—" em vez de inventar número).
function otm_stats_read(): array {
    $r = otm_script('panel-stats.sh', [], 20);
    $line = '';
    foreach (explode("\n", (string)($r['out'] ?? '')) as $l) {
        $l = trim($l);
        if ($l !== '' && $l[0] === '{') { $line = $l; break; }
    }
    $j = $line !== '' ? json_decode($line, true) : null;
    return is_array($j) ? $j : [];
}

// modo de acesso atual (rish/adb/su/local), lido do config.sh show
function otm_mode(): array {
    $r = otm_script('config.sh', ['show'], 25);
    $out = $r['out'] ?? '';
    $mode = '';
    if (preg_match('/detectado agora\s*:\s*(\S+)/', $out, $m)) $mode = $m[1];
    $priv = '';
    if (preg_match('/privilégio\s*:\s*([^\n]+)/u', $out, $m)) $priv = trim($m[1]);
    return ['mode' => $mode, 'priv' => $priv, 'text' => $out];
}

// --- log ----------------------------------------------------------------------
/**
 * Extrai da saída as linhas que explicam POR QUE algo falhou.
 *
 * Os scripts marcam a falha com "✕"/"X" e dizem o valor lido de volta (ex.:
 * "X tcp_congestion_control nao mudou (lido: cubic)"). Sem isso o log só dizia
 * "erro", sem dizer o que não pegou nem com que valor o aparelho ficou.
 */
function otm_fail_reasons(string $out): array {
    if ($out === '') return [];
    $out = preg_replace('/\x1b\[[0-9;]*m/', '', $out);   // tira cor ANSI
    $reasons = [];
    foreach (preg_split('/\r?\n/', $out) as $line) {
        $l = trim($line);
        if ($l === '') continue;
        $isFail = (bool)preg_match('/^[✕X]/u', $l)
            || (bool)preg_match('/(n[ãa]o (mudou|pegou|consegui|aceitou|encontrei|dispon[íi]vel|existe|permitido)'
                . '|falhou|falha\(s\)|sem acesso|denied|denial|not found)/iu', $l);
        if ($isFail) {
            $l = preg_replace('/^[✕X]\s*/u', '', $l);
            $reasons[] = $l;
        }
    }
    return array_slice(array_values(array_unique($reasons)), 0, 12);
}

function otm_log(string $id, string $label, array $argv, array $res): void {
    $out = (string)($res['out'] ?? '');
    $rec = [
        'ts' => date('c'),
        'id' => $id,
        'label' => $label,
        'cmd' => implode(' ', array_map(fn($x) => (strpos($x, ' ') !== false ? '"' . $x . '"' : $x), $argv)),
        'ok' => $res['ok'] ?? false,
        'code' => $res['code'] ?? null,
        // detalhe: o que o script tentou (applies/changed/failed) e a saída crua
        'applies' => $res['applies'] ?? null,
        'changed' => $res['changed'] ?? null,
        'failed' => $res['failed'] ?? null,
        'dur_ms' => $res['dur_ms'] ?? null,
        'reasons' => otm_fail_reasons($out),
        'out' => otm_clip($out, 6000),
    ];
    $f = otm_state() . '/log.jsonl';
    @file_put_contents($f, json_encode($rec, JSON_UNESCAPED_UNICODE) . "\n", FILE_APPEND);
    otm_log_trim($f);
}

/** Corta o texto sem depender do mbstring (que pode faltar no PHP do aparelho). */
function otm_clip(string $s, int $max): string {
    if (strlen($s) <= $max) return $s;
    $cut = substr($s, 0, $max);
    // não deixa um caractere UTF-8 cortado no meio
    return (string)preg_replace('/[\x80-\xBF]+$/', '', $cut) . "\n…(cortado)";
}

/**
 * O log agora guarda a saída crua de cada ação, então cresce rápido. Mantém as
 * últimas [otm_log_max] linhas: o histórico continua completo para o usuário e
 * o arquivo não vira um peso morto no aparelho.
 */
function otm_log_trim(string $file): void {
    if (!is_file($file) || filesize($file) < 1500000) return;
    $lines = file($file, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    $keep = array_slice($lines, -otm_log_max());
    @file_put_contents($file, implode("\n", $keep) . "\n");
}

function otm_log_max(): int { return 800; }

function otm_log_read(int $n = 40, bool $full = false): array {
    $f = otm_state() . '/log.jsonl';
    if (!is_file($f)) return [];
    $lines = file($f, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) ?: [];
    if (!$full) $lines = array_slice($lines, -$n);
    $out = [];
    foreach (array_reverse($lines) as $l) {
        $j = json_decode($l, true);
        if (is_array($j)) $out[] = $j;
    }
    return $out;
}

// Histórico COMPLETO (o painel mostra em "Logs", sem truncar).
function otm_log_all(): array {
    return otm_log_read(0, true);
}

// Terminal: executa um comando cru digitado pelo dono do painel. Diferente das
// ações (argv montado por whitelist), aqui o comando é livre — é o "terminal
// real". Só o dono do painel (login/token) alcança este endpoint.
function otm_run_command(string $cmd): array {
    $cmd = trim($cmd);
    if ($cmd === '') return ['ok' => false, 'code' => -1, 'out' => 'comando vazio'];
    if (strlen($cmd) > 2000) return ['ok' => false, 'code' => -1, 'out' => 'comando muito longo (máx. 2000)'];
    $t0 = microtime(true);
    $r = otm_exec(['sh', '-c', $cmd], 120);
    $r['dur_ms'] = (int)round((microtime(true) - $t0) * 1000);
    otm_log('terminal', 'Terminal: ' . substr($cmd, 0, 80), ['sh', '-c', $cmd], $r);
    return $r + ['cmd' => $cmd];
}

// --- JSON ---------------------------------------------------------------------
function otm_json($data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
}
