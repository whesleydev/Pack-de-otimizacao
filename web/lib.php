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
        'turbo.sh', 'panel-state.sh', 'panel-stats.sh', 'proc-mgr.sh',
        'keep-alive.sh', 'game-clean.sh', 'ram-boost.sh',
        'clean.sh', 'bench.sh', 'device-profile.sh', 'config.sh',
        'profile-custom.sh', 'smart-opt.sh', 'vitality.sh',
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

// --- registro de ações --------------------------------------------------------
// risco: safe | careful | root    confirm: pede confirmação no painel
function otm_actions(): array {
    $A = [];

    $add = function (array $a) use (&$A) {
        $a += ['params' => [], 'confirm' => false, 'risk' => 'safe', 'argv' => [], 'help' => ''];
        $A[$a['id']] = $a;
    };

    // ----- Rápido -----
    $add(['id' => 'apply', 'group' => 'Geral', 'label' => 'Aplicar o pack recomendado',
          'desc' => 'O "faz tudo" para novato: performance, RAM, GPU, rede, latência, jogo, bateria e touch.',
          'help' => 'É o botão para quem comprou o app e não sabe o que usar: aplica de uma vez tudo o que é seguro e não precisa de root. Em ordem: performance e animações mais rápidas, GPU na interface, RAM ajustada, DNS privado e buffers de rede, ajustes de latência/ping (BBR, low latency, ECN), Wi-Fi, modo de jogo, anti-relog do jogo, silêncio de notificações, tela, fluidez, limpeza de cache/RAM e, no fim, o limite de processos em segundo plano (4 apps) — que é o que sobra mais RAM para o jogo. O debloat fica de fora de propósito (remover app de fábrica é decisão sua, tem aba própria). Depois de aplicar, se quiser mexer na mira, use a aba "Sensi e mira" (que gera a sensi do seu aparelho) e, na próxima vez que abrir o app, use o "Clean phone" no dia a dia. Dá para desfazer em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'all'], 'confirm' => true, 'timeout' => 420]);
    $add(['id' => 'smart.auto', 'group' => 'Geral', 'label' => 'Otimizador inteligente',
          'desc' => 'Analisa o seu aparelho e aplica as melhores configurações para ele.',
          'help' => 'O "faz tudo" inteligente em um botão só. Ele primeiro LÊ o seu aparelho inteiro (modelo, processador, GPU, núcleos e frequência, RAM, taxa de tela, armazenamento, térmico, bateria, zram, Android e kernel) e calcula uma nota e a classe do aparelho. Depois decide item por item o que faz sentido para AQUELE modelo — não aplica o mesmo pacote para todo mundo — e aplica: animações, RAM sob medida, renderizador escolhido pela GPU, taxa de tela, limpeza e doze. (O debloat ficou de fora de propósito: remover app de fábrica é decisão sua e mora na aba Debloat.) Se você tem um jogo escolhido no Modo Competitivo, ele também liga o anti-relog (o jogo não fecha nem volta ao login). No fim, confere se os ajustes pegaram de verdade. É tudo reversível em "Reverter TUDO".',
          'argv' => ['smart-opt.sh', 'auto'], 'risk' => 'careful', 'confirm' => true,
          'timeout' => 420]);
    $add(['id' => 'restore_all', 'group' => 'Geral', 'label' => 'Reverter TUDO',
          'desc' => 'Desfaz níveis 2, otimizações profundas e debloat de uma vez.',
          'help' => 'Volta o aparelho ao estado de fábrica de configuração: desfaz as otimizações, as profundas (root) e o debloat. Use quando quiser "limpar" tudo o que o pack aplicou.',
          'argv' => ['pack.sh', 'restore'], 'confirm' => true, 'timeout' => 300]);
    $add(['id' => 'snapshot_save', 'group' => 'Geral', 'label' => 'Salvar snapshot',
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
    $add(['id' => 'overlay.sensi', 'group' => 'Sensi e mira', 'label' => 'Painel flutuante sobre o jogo',
          'desc' => 'Mostra a sensi e os perfis de toque por cima do jogo, sem sair da partida.',
          'help' => 'Abre o painel flutuante: uma janela arrastável que fica por cima do jogo com a sensi calculada para o seu aparelho (Geral, Ponto vermelho, mira 2x, 4x, AWM e o tamanho do botão de atirar), os cinco perfis de toque (Equilibrado, Headshot, Spray, Sniper, Speed) e atalhos de latência e limpeza de RAM. Assim você confere e troca o ajuste sem fechar o jogo. Na primeira vez o Android pede a permissão "aparecer por cima de outros apps". Toque de novo no botão para desligar.',
          'argv' => [], 'ui' => 'overlay']);
    $add(['id' => 'sensi.calc', 'group' => 'Sensi e mira', 'label' => 'Gerar sensi do meu aparelho',
          'desc' => 'Calcula a sensi ideal para o seu aparelho, sem alterar nada.',
          'help' => 'Lê o seu aparelho (resolução, densidade/DPI, tamanho da tela, taxa de toque, taxa de atualização, SoC, RAM e o ajuste de toque já aplicado) e calcula uma sensi sob medida: Geral, Ponto vermelho, mira 2x, 4x, AWM, além do tamanho do botão de atirar (com teto de 50%, que é o que não deixa o botão feio/grande). NÃO altera nada no aparelho: só mostra os números para você digitar no jogo. Rode de novo se mudar a resolução.',
          'argv' => ['sensi.sh', 'calc'], 'timeout' => 90]);
    $add(['id' => 'sensi.analyze', 'group' => 'Sensi e mira', 'label' => 'Sensi: ver o que foi lido',
          'desc' => 'Mostra as leituras e os fatores usados no cálculo da sensi.',
          'help' => 'Transparência total: mostra exatamente o que o gerador leu do seu aparelho (tela, DPI, polegadas, toque, Hz, SoC, RAM) e quais fatores aplicou em cada item. Assim você entende por que a sensi saiu daquele valor. Só leitura.',
          'argv' => ['sensi.sh', 'analyze'], 'timeout' => 90]);
    $add(['id' => 'sensi.headshot', 'group' => 'Sensi e mira', 'label' => 'Sensi: perfil headshot',
          'desc' => 'Recalcula a sensi com foco em mira rápida na cabeça.',
          'help' => 'Mesma conta do gerador, com o perfil headshot: mira mais ágil para pegar a cabeça. Mostra os valores para digitar no jogo. Só leitura, nada é alterado no aparelho.',
          'argv' => ['sensi.sh', 'calc', 'headshot'], 'timeout' => 90]);
    $add(['id' => 'sensi.spray', 'group' => 'Sensi e mira', 'label' => 'Sensi: perfil spray',
          'desc' => 'Recalcula a sensi com foco em controle de recuo.',
          'help' => 'Mesma conta do gerador, com o perfil spray: controle melhor no tiro contínuo (segurar o dedo atirando). Mostra os valores para digitar no jogo. Só leitura.',
          'argv' => ['sensi.sh', 'calc', 'spray'], 'timeout' => 90]);
    $add(['id' => 'sensi.sniper', 'group' => 'Sensi e mira', 'label' => 'Sensi: perfil sniper',
          'desc' => 'Recalcula a sensi com foco em mira precisa de longe.',
          'help' => 'Mesma conta do gerador, com o perfil sniper: mira mais lenta e precisa para longa distância (AWM, mira 4x). Mostra os valores para digitar no jogo. Só leitura.',
          'argv' => ['sensi.sh', 'calc', 'sniper'], 'timeout' => 90]);
    $add(['id' => 'sensi.speed', 'group' => 'Sensi e mira', 'label' => 'Sensi: perfil speed',
          'desc' => 'Recalcula a sensi com foco em reação máxima.',
          'help' => 'Mesma conta do gerador, com o perfil speed: resposta o mais rápida possível, para quem joga agressivo e vira rápido. Mostra os valores para digitar no jogo. Só leitura.',
          'argv' => ['sensi.sh', 'calc', 'speed'], 'timeout' => 90]);
    $add(['id' => 'sensi.ff', 'group' => 'Sensi e mira', 'label' => 'Sensi: valores na ordem do FF',
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
    $add(['id' => 'perf', 'group' => 'Desempenho', 'label' => 'Performance (animações 0.5x)',
          'desc' => 'Deixa as animações mais rápidas: interface parece mais ágil.',
          'help' => 'Reduz a duração das animações do sistema pela metade. O celular parece mais rápido sem mudar nada de verdade — só a sensação de velocidade melhora.',
          'argv' => ['adb-tweaks.sh', 'perf']]);
    $add(['id' => 'perf_max', 'group' => 'Desempenho', 'label' => 'Performance extrema (animações 0)',
          'desc' => 'Remove as animações: transições instantâneas.',
          'help' => 'Desliga as animações de vez. Tudo abre instantaneamente. Ótimo para aparelhos lentos, mas o visual fica mais "seco".',
          'argv' => ['adb-tweaks.sh', 'perf_max']]);
    $add(['id' => 'fluidez', 'group' => 'Desempenho', 'label' => 'Fluidez (toque + Hz + animações)',
          'desc' => 'Pacote geral de fluidez: toque, taxa de atualização e animações.',
          'help' => 'Combina vários ajustes que, juntos, deixam o uso mais fluido: resposta de toque melhor, taxa de atualização no máximo e animações mais rápidas. É o "tudo para fluidez".',
          'argv' => ['adb-tweaks.sh', 'fluidez']]);
    $add(['id' => 'dnd', 'group' => 'Desempenho', 'label' => 'Não perturbe (DND)',
          'desc' => 'Silencia notificações durante o jogo.',
          'help' => 'Ativa o modo Não Perturbe: nada de notificações atrapalhando no meio da partida. Desligue com "Desligar DND" quando terminar.',
          'argv' => ['adb-tweaks.sh', 'dnd']]);
    $add(['id' => 'dnd_off', 'group' => 'Desempenho', 'label' => 'Desligar DND',
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
    $add(['id' => 'battery', 'group' => 'Desempenho', 'label' => 'Economia de bateria',
          'desc' => 'Ativa o modo de economia e o repouso profundo (Doze).',
          'help' => 'Liga a economia de energia e força o aparelho a "dormir" mais fundo quando parado. Dura mais a bateria. NÃO use enquanto joga — pode derrubar o desempenho.',
          'argv' => ['adb-tweaks.sh', 'battery']]);
    $add(['id' => 'battery_off', 'group' => 'Desempenho', 'label' => 'Desligar economia',
          'desc' => 'Volta ao consumo normal (recomendado para jogar).',
          'help' => 'Desliga a economia de bateria e o repouso profundo. Use antes de jogar para o desempenho não ser limitado.',
          'argv' => ['adb-tweaks.sh', 'battery_off']]);

    // ----- Sono profundo (doze / idle) -----
    $add(['id' => 'doze.on', 'group' => 'Desempenho', 'label' => 'Sono profundo: ligar',
          'desc' => 'Faz o aparelho dormir de verdade logo após a tela apagar.',
          'help' => 'O Android só "dorme fundo" (Doze) depois de uns 30 minutos parado. Aqui esse tempo é encurtado para cerca de 2 minutos: a tela apagou, o aparelho dorme e a bateria dura muito mais. Reverta em "Sono profundo: desligar" antes de precisar de notificações em tempo real.',
          'argv' => ['adb-tweaks.sh', 'doze', 'on'], 'risk' => 'careful', 'confirm' => true]);
    $add(['id' => 'doze.off', 'group' => 'Desempenho', 'label' => 'Sono profundo: desligar',
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
    $add(['id' => 'freeze', 'group' => 'Desempenho', 'label' => 'Congelar apps (cache freezer)',
          'desc' => 'Ativa o congelador do sistema e aplica a lista.',
          'help' => 'Liga o congelador de apps em cache do sistema: apps que você não está usando ficam pausados em vez de gastar RAM/bateria. Ótimo para liberar memória. Reverta em "Descongelar todos os apps".',
          'argv' => ['adb-tweaks.sh', 'freezer'], 'confirm' => true]);
    $add(['id' => 'unfreeze', 'group' => 'Desempenho', 'label' => 'Descongelar todos os apps',
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
    $add(['id' => 'adv.notif', 'group' => 'Sistema', 'label' => 'Menos notificações (heads-up)',
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
    $add(['id' => 'turbo.phantom_on', 'group' => 'Desempenho', 'label' => 'Phantom Killer: ligar',
          'desc' => 'Volta o limite de processos-fantasma ao padrão do Android.',
          'help' => 'O Phantom Process Killer mata processos "fantasma" (filhos de apps como Termux/emuladores). Aqui ele volta ao padrão do sistema. Use se você não precisa de serviços em segundo plano.',
          'argv' => ['turbo.sh', 'phantom', 'on']]);
    $add(['id' => 'turbo.phantom_off', 'group' => 'Desempenho', 'label' => 'Phantom Killer: desligar',
          'desc' => 'Desliga o limite (bom p/ Termux, emuladores e serviços).',
          'help' => 'Desliga o Phantom Process Killer: apps como Termux, emuladores e servidores deixam de ter processos mortos pelo sistema. Pode aumentar um pouco o uso de bateria.',
          'argv' => ['turbo.sh', 'phantom', 'off'], 'risk' => 'careful']);
    $add(['id' => 'turbo.trim', 'group' => 'Desempenho', 'label' => 'Poda de caches real',
          'desc' => 'Libera espaço dos caches sem apagar dados de apps.',
          'help' => 'Usa o trim-caches oficial do Android: apaga só arquivos de cache temporários, nunca seus dados, contas ou conversas. Mostra o espaço livre antes e depois.',
          'argv' => ['turbo.sh', 'trim']]);
    $add(['id' => 'turbo.refresh_max', 'group' => 'Desempenho', 'label' => 'Refresh no máximo',
          'desc' => 'Trava a tela na maior taxa de atualização (ex.: 120Hz).',
          'help' => 'Trava a taxa de atualização no valor mais alto suportado pela tela. Rolagem e jogo ficam mais lisos. Gasta um pouco mais de bateria. Reverte em "Refresh automático".',
          'argv' => ['turbo.sh', 'refresh', 'max'], 'risk' => 'careful']);
    $add(['id' => 'turbo.refresh_auto', 'group' => 'Desempenho', 'label' => 'Refresh automático',
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
                            $add(['id' => 'turbo.perfmode_on', 'group' => 'Desempenho', 'label' => 'Modo desempenho fixo: ligar',
          'desc' => 'Força o aparelho a priorizar desempenho.',
          'help' => 'Trava o aparelho em modo de desempenho (não reduz clocks por bateria). Mais FPS sustentado, mais calor e mais consumo. Reverte em "desligar".',
          'argv' => ['turbo.sh', 'perfmode', 'on'], 'risk' => 'careful']);
    $add(['id' => 'turbo.perfmode_off', 'group' => 'Desempenho', 'label' => 'Modo desempenho fixo: desligar',
          'desc' => 'Volta o controle de energia ao sistema.',
          'help' => 'Desliga o modo de desempenho fixo e devolve o gerenciamento de energia ao Android.',
          'argv' => ['turbo.sh', 'perfmode', 'off']]);

    // ----- Vitalidade: cuidar para durar -------------------------------------
    // O resto do pack "tira o freio". Estas ações fazem o oposto: medem a saúde
    // real da bateria, reduzem desgaste e avisam hábitos de carga que encurtam a
    // vida do aparelho. Nada aqui força o celular.
    $add(['id' => 'vital.optimize', 'group' => 'Vitalidade', 'label' => 'Otimizar saúde do telefone',
          'desc' => 'Um toque: liga o cuidado e mostra a saúde real da bateria.',
          'help' => 'O botão único do cuidado. Liga o modo longevidade (sono profundo afinado, tela em 60 Hz, menos varredura em segundo plano e a economia de energia do sistema de volta) e, na mesma tela, mostra a saúde REAL da bateria: capacidade atual contra a de fábrica, ciclos, temperatura e uma nota de 0 a 100. É para durar mais, não para forçar. Reversível em "Modo longevidade: desligar".',
          'argv' => ['vitality.sh', 'optimize'], 'risk' => 'careful', 'confirm' => true, 'timeout' => 180]);
    $add(['id' => 'vital.diag', 'group' => 'Vitalidade', 'label' => 'Saúde da bateria: ver diagnóstico',
          'desc' => 'Capacidade real, ciclos e desgaste da bateria.',
          'help' => 'Mostra a saúde REAL da bateria: compara a capacidade atual com a de fábrica (é o número que o Android esconde), a contagem de ciclos de carga, o nível, a temperatura e uma nota de vitalidade de 0 a 100. É a diferença entre "acho que está boa" e saber. Só leitura: não muda nada no aparelho.',
          'argv' => ['vitality.sh', 'diag'], 'timeout' => 60]);
    $add(['id' => 'vital.care_on', 'group' => 'Vitalidade', 'label' => 'Modo longevidade: ligar',
          'desc' => 'Reduz o desgaste: doze ativo, tela 60Hz, menos scans.',
          'help' => 'Liga o cuidado com a durabilidade: sono profundo afinado (dorme logo após a tela apagar), tela em 60Hz (taxa alta é um dos maiores consumos contínuos) e menos varredura de Wi-Fi/Bluetooth em segundo plano. Reduz agressão em vez de forçar desempenho, então o aparelho esquenta menos e dura mais. Totalmente reversível em "Modo longevidade: desligar".',
          'argv' => ['vitality.sh', 'care', 'on'], 'risk' => 'careful', 'timeout' => 120]);
    $add(['id' => 'vital.care_off', 'group' => 'Vitalidade', 'label' => 'Modo longevidade: desligar',
          'desc' => 'Volta doze, taxa da tela e scans ao padrão.',
          'help' => 'Desliga o modo longevidade e devolve o sono profundo, a taxa de atualização e as varreduras ao padrão de fábrica. Reversível.',
          'argv' => ['vitality.sh', 'care', 'off'], 'risk' => 'safe', 'timeout' => 60]);
    $add(['id' => 'vital.care_status', 'group' => 'Vitalidade', 'label' => 'Modo longevidade: ver estado',
          'desc' => 'Mostra se o modo longevidade está ligado.',
          'help' => 'Diz se o modo longevidade está ligado ou desligado, e resume a nota de vitalidade, a saúde da bateria e a temperatura agora. Só leitura.',
          'argv' => ['vitality.sh', 'care', 'status'], 'timeout' => 60]);
    $add(['id' => 'vital.guard', 'group' => 'Vitalidade', 'label' => 'Guardião de carga: ver hábitos',
          'desc' => 'Conta cargas acima de 80% e cargas com calor.',
          'help' => 'O guardião observa seus hábitos de carga e conta o que desgasta a bateria: quantas vezes você carregou acima de 80% e quantas carregou com o aparelho quente (calor + carga é o que mais encurta a vida da célula). Ele não muda nada: só mede e avisa. Sem root não é possível limitar a carga em 80%, mas dá para saber quando você passou.',
          'argv' => ['vitality.sh', 'guard'], 'timeout' => 60]);
    $add(['id' => 'vital.status', 'group' => 'Vitalidade', 'label' => 'Vitalidade: resumo',
          'desc' => 'Nota de vitalidade e situação geral do aparelho.',
          'help' => 'Resume tudo em uma tela: nota de vitalidade, saúde da bateria, ciclos, temperatura, se o modo longevidade está ligado e o alerta atual do guardião de carga. Só leitura.',
          'argv' => ['vitality.sh', 'status'], 'timeout' => 60]);
    $add(['id' => 'turbo.telemetry_off', 'group' => 'Desempenho', 'label' => 'Telemetria e logs: desligar',
          'desc' => 'Desliga logs persistentes e scans "sempre disponível".',
          'help' => 'Desliga o log persistente (logpersist), o log de Bluetooth e as varreduras de Wi-Fi/Bluetooth "sempre disponível". Menos trabalho em segundo plano e mais privacidade. Reversível em "religar".',
          'argv' => ['turbo.sh', 'telemetry', 'off'], 'risk' => 'careful']);
    $add(['id' => 'turbo.telemetry_on', 'group' => 'Desempenho', 'label' => 'Telemetria e logs: religar',
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
    $add(['id' => 'snapshot_list', 'group' => 'Geral', 'label' => 'Ver snapshots salvos',
          'desc' => 'Lista os snapshots que você já tirou.',
          'help' => 'Mostra todas as fotos de configuração que você salvou, com data e id. Serve para escolher qual restaurar.',
          'argv' => ['snapshot.sh', 'list']]);
    $add(['id' => 'snapshot_diff', 'group' => 'Geral', 'label' => 'Comparar com o último snapshot',
          'desc' => 'Mostra o que mudou desde o snapshot mais recente.',
          'help' => 'Compara as configurações atuais com o último snapshot e lista só o que mudou. Bom para conferir o que o pack alterou.',
          'argv' => ['snapshot.sh', 'diff', 'latest']]);
    $add(['id' => 'snapshot_restore', 'group' => 'Geral', 'label' => 'Restaurar último snapshot',
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

    // ----- Módulos (plugins do pack) -----
    $add(['id' => 'module.run', 'group' => 'Geral', 'label' => 'Executar um módulo',
          'desc' => 'Roda um dos módulos/plugins incluídos no pack.',
          'help' => 'Os módulos são os complementos (tweaks, touch, GPU, bateria). Digite o nome exato do módulo — veja a lista na aba Geral. Ação reversível conforme o módulo.',
          'argv' => ['modules.sh', 'run', '{name}'],
          'params' => [['name' => 'name', 'type' => 'name', 'label' => 'Nome do módulo']],
          'risk' => 'careful', 'confirm' => true, 'timeout' => 180]);

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
    $add(['id' => 'perm.app', 'group' => 'Sistema', 'label' => 'Permitir o app do pack',
          'desc' => 'Libera o app do pack para rodar em segundo plano, sem restrição de bateria e fora do Doze.',
          'help' => 'Sem isso o Android adormece o app do pack: as otimizações param sozinhas, o som não toca e o acesso cai. Aqui o app entra na lista de isenção do Doze, ganha permissão de rodar em segundo plano e de manter a CPU acordada. Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'perm_app'], 'timeout' => 120]);
    $add(['id' => 'perm.ff', 'group' => 'Sistema', 'label' => 'Permitir os Free Fire',
          'desc' => 'Libera o Free Fire e o Free Fire MAX para rodar em segundo plano sem serem congelados.',
          'help' => 'Impede o sistema de congelar o Free Fire e o Free Fire MAX quando você troca de app ou a tela apaga — evita o jogo fechar no meio da partida. Também tira a restrição de bateria. Se o seu jogo é outro (CODM, Minecraft...), use "Permitir o meu jogo". Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'perm_ff'], 'timeout' => 120]);
    $add(['id' => 'perm.game', 'group' => 'Sistema', 'label' => 'Permitir o meu jogo',
          'desc' => 'Libera o jogo escolhido no modo gamer (o mesmo do botão da Home).',
          'help' => 'Aplica ao jogo escolhido no modo gamer a mesma isenção do Free Fire: fora do Doze, sem restrição de bateria e livre para rodar em segundo plano — assim ele não fecha quando você troca de app. Escolha o jogo na Home, em "Modo Competitivo". Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'perm_game', '{pkg}'],
          'params' => [['name' => 'pkg', 'type' => 'pkg', 'label' => 'Jogo', 'optional' => true]],
          'timeout' => 120]);
    $add(['id' => 'perm.battery', 'group' => 'Sistema', 'label' => 'Bateria sem economia agressiva',
          'desc' => 'Desliga a economia de energia e o App Standby (global, não só para um app).',
          'help' => 'Isto é global do aparelho, não é permissão de um app: desliga o modo de economia de energia (low_power), a gestão adaptativa de bateria e o App Standby (que suspende apps em segundo plano). É o que deixa o pack e o jogo "acordados" sem o sistema cortar o desempenho. NÃO use no dia a dia se você prioriza duração de bateria. Reversível em "Reverter TUDO".',
          'argv' => ['adb-tweaks.sh', 'perm_battery'], 'timeout' => 120]);
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
          'desc' => 'Você escolhe o que aplicar: animações, RAM, Hz, toque, limpeza.',
          'help' => 'Abre um menu onde você liga só o que quiser. Cada recurso é independente: animações (0x/0.5x), limite de apps em 2º plano (RAM), taxa de atualização da tela, perfil de toque, telemetria, limpeza de cache/RAM e hibernar apps de fundo. Ao aplicar, o pack parte de um estado limpo e liga apenas os recursos marcados. Tudo é reversível em "Perfil personalizado: desligar".',
          'argv' => [], 'ui' => 'customprofile']);
    $add(['id' => 'profile.custom.apply', 'group' => 'Geral', 'label' => 'Aplicar perfil personalizado',
          'desc' => 'Liga os recursos escolhidos no menu do perfil personalizado.',
          'help' => 'Aplica o conjunto que você montou no menu do perfil personalizado. O pack reverte o estado antes e liga só o que você marcou — nada além disso.',
          'argv' => ['profile-custom.sh', 'apply', '{anim}', '{ram}', '{hz}', '{touch}',
                     '{telemetry}', '{clean}', '{hibernate}'],
          'params' => [
              ['name' => 'anim', 'type' => 'enum', 'label' => 'Animações', 'options' => ['normal', 'half', 'off'], 'default' => 'normal'],
              ['name' => 'ram', 'type' => 'enum', 'label' => 'RAM', 'options' => ['padrao', 'gaming', 'batata'], 'default' => 'padrao'],
              ['name' => 'hz', 'type' => 'enum', 'label' => 'Taxa da tela', 'options' => ['off', '60', '90', '120', '144'], 'default' => 'off'],
              ['name' => 'touch', 'type' => 'enum', 'label' => 'Toque', 'options' => ['none', 'balanced', 'headshot', 'spray', 'sniper', 'speed'], 'default' => 'none'],
              ['name' => 'telemetry', 'type' => 'enum', 'label' => 'Telemetria', 'options' => ['on', 'off'], 'default' => 'on'],
              ['name' => 'clean', 'type' => 'enum', 'label' => 'Limpeza', 'options' => ['off', 'fundo', 'suave', 'normal'], 'default' => 'off'],
              ['name' => 'hibernate', 'type' => 'enum', 'label' => 'Hibernar apps', 'options' => ['off', 'on'], 'default' => 'off'],
          ],
          'confirm' => true, 'risk' => 'careful', 'timeout' => 300]);
    $add(['id' => 'profile.custom.off', 'group' => 'Geral', 'label' => 'Perfil personalizado: desligar',
          'desc' => 'Desfaz o perfil personalizado e volta o aparelho ao padrão.',
          'help' => 'Reverte tudo o que o perfil personalizado aplicou e devolve o aparelho ao estado de fábrica de configuração. A sua escolha de recursos fica salva para aplicar de novo depois.',
          'argv' => ['profile-custom.sh', 'off'], 'confirm' => true, 'risk' => 'safe', 'timeout' => 300]);

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
    $script = $argv[0];
    $args = array_slice($argv, 1);

    $t = (int)($a['timeout'] ?? 60);
    $r = otm_script($script, $args, $t);

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

    otm_log($id, $a['label'], $argv, $r + ['applies' => $applies, 'changed' => $changed, 'failed' => $failed]);
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
    $r = otm_exec(['sh', '-c', $cmd], 120);
    otm_log('terminal', 'Terminal: ' . substr($cmd, 0, 80), ['sh', '-c', $cmd], $r);
    return $r + ['cmd' => $cmd];
}

// --- JSON ---------------------------------------------------------------------
function otm_json($data, int $code = 200): void {
    http_response_code($code);
    header('Content-Type: application/json; charset=utf-8');
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
}
