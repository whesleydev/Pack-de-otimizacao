# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [2.24.0] - 2026-10-05

### Adicionado
- **Conexão por Depuração USB (só autorizar, sem parear).** No app, o botão
  **Conectar** ganhou a opção *Depuração USB (só autorizar)*: ele acha o `adbd` no
  próprio aparelho (loopback `127.0.0.1:5555` ou pela rede via mDNS `_adb._tcp`) e
  conecta. No celular aparece **só** o aviso *"Permitir depuração USB"* — sem o
  código de pareamento da depuração sem fio. (`AdbRunner.connectLocal`, `PanelActivity`.)
- Novo modo de transporte `usb` em `scripts/config.sh` (`set usb`) e em
  `scripts/common.sh`: usa `adb shell` no 1º aparelho do cabo, sem exigir endereço.
  Para quem roda o pack pelo PC (`OTM_MODE=usb sh scripts/menu.sh`).

### Notas
- **Limite honesto:** conectar ao `adbd` por USB *dentro do próprio celular* (sem
  PC) não é possível sem root — a pilha USB do Android não expõe o `adbd` ao app.
  O modo USB vale para o **PC** (cabo) e para o app via ADB local/TCP ou Shizuku.
  No celular, o caminho sem root continua sendo o **Shizuku** (recomendado).

## [2.23.0] - 2026-10-05

### Adicionado
- **Clean 2.0 — motor único de limpeza (`scripts/clean.sh`).** Substitui o antigo
  `clean` do `adb-tweaks.sh` (que só fazia limpeza) por um motor em **fases**, com
  verificação real de cada passo (`#OTM-RESULT`):
  - `clean.sh scan` — só lê o que dá para liberar (RAM, espaço em `/data`, cache por
    app com root). Não altera nada.
  - `clean.sh now fundo` — libera RAM: encerra o 2º plano (poupando jogo e
    protegidos no anti-relog), poda o cache e solta o pagecache (root).
  - `clean.sh now suave` (padrão) — o de cima **+ suavização sem root**: animações
    0x, blur/transparência off, doze mais rápido, sem scan Wi-Fi em 2º plano.
  - `clean.sh now normal` — tudo **+ suavização profunda de CPU/GPU/I-O/VM** via
    `deep-tune.sh` (freq, gpu, mem, sched, input, io, vm, net2), quando há root.
  - `clean.sh status` / `clean.sh off` — estado e reversão da suavização.
- Novas ações no painel (categoria **Desempenho**): `Clean: ver o que dá para limpar`
  (`clean.scan`), `Clean profundo (CPU/GPU/I/O)` (`clean.deep`) e `Clean: desfazer
  suavização` (`clean.undo`).
- `scripts/clean.sh` entra na whitelist de scripts executáveis do painel.

### Corrigido
- **"Limpar cache e RAM" agora suaviza de verdade.** O `clean` deixa de ser só
  limpeza e passa a afinar CPU/GPU/I-O/VM (com root) — era o que faltava para o
  sistema ficar liso, não só com RAM livre.
- **`clean` passou a verificar.** Antes o `clean` não emitia `#OTM-RESULT`
  (`applies=0 changed=0`); agora cada passo é lido de volta e contado.
- **Removido o `clean.aot` / grupo `aot`.** Recompilar apps em AOT com
  `cmd package compile -m speed` era root + praticamente placebo (o Android 12+ já
  recompila em idle) e podia travar o aparelho. Saiu do catálogo e dos grupos.
- **Placebos fora do caminho principal da limpeza.** `logcat -c` (não libera RAM) e
  `sync` (só flush de buffer) saíram do `clean`; `sync` fica só como flush explícito
  no fim do `ram-boost.sh`.

## [2.22.0] - 2026-10-05

### Adicionado
- **Liberar RAM agora.** Novo módulo `scripts/ram-boost.sh` (`boost [normal|max]`,
  `status`) que libera memória de verdade: encerra os apps de fundo (poupa o jogo e
  quem você protegeu no anti-relog), poda o cache de todos os apps e, com root,
  manda o kernel soltar o pagecache/dentries (`/proc/sys/vm/drop_caches`). Mostra
  quanto de RAM foi liberado (lido de `/proc/meminfo`). Dois níveis: **Normal** e
  **Máximo** (este também encerra apps de mídia/chat conhecidos).
- **Modo resfriamento.** Novo módulo `scripts/cool-down.sh` (`on [normal|max]`,
  `off`, `status`) para usar quando o aparelho estiver quente: prende a CPU e a GPU
  no clock mínimo, baixa o brilho da tela e encerra os apps de fundo. No modo
  **Máximo** também desliga os núcleos extras. Tem um vigia que desliga sozinho ao
  esfriar (padrão 38°C) ou após o tempo máximo (padrão 30 min). Requer root e é
  totalmente reversível (`cool-down.sh off`).
- Categoria **Desempenho** ganhou os cartões de escolha `Liberar RAM` (Normal/Máximo)
  e `Resfriar aparelho` (Normal/Máximo), além de `Ver RAM livre` e `Ver temperatura`.
- Helpers reutilizáveis em `scripts/common.sh`: `otm_bg_kill`, `otm_cache_trim`,
  `otm_drop_caches`, `otm_ram_livre_mb` e `otm_temp`.

### Corrigido
- **"Limpar cache e RAM" não liberava RAM de verdade.** O `clean` e o `mem` do
  `adb-tweaks.sh` agora encerram os apps de 3º plano (`am force-stop`), podam o cache
  e, com root, soltam o pagecache — em vez de apenas ajustar o limite de apps em
  cache. Os dois passaram a reportar quantos MB de RAM foram liberados.
- **`pm list packages -3` era tratado como se não precisasse de privilégio.** O
  encerramento de apps de fundo agora só roda com shell (Shizuku/ADB/root), evitando
  tentativas inúteis em modo local.

## [2.21.0] - 2026-10-05

### Adicionado
- **Game Clean (deixar o jogo limpo e otimizado).** Novo módulo `scripts/game-clean.sh`
  que junta num só clique o "modo partida": encerra os apps de fundo (sem tocar no
  jogo nem nos que você protegeu no anti-relog), poda o cache e o dexopt, libera RAM
  no perfil gaming, protege o jogo contra relog (usa o anti-relog), isenta do Doze,
  liga o Game Mode em performance + driver de jogo, silencia heads-up/bolhas e liga
  o Não Perturbe, e corta telemetria/scans em segundo plano. Dois níveis: **Normal**
  e **Máximo** (este também encerra apps de mídia/chat conhecidos). Categoria
  **Apps e jogos** com um cartão de escolha: `Normal`, `Máximo`, além de
  `Game Clean: desligar` e `Game Clean: ver estado`. Tudo reversível.

### Corrigido
- **Reversão não guardava o valor original ao reaplicar um ajuste.** `bkp_set` (em
  `common.sh`) empilhava um novo backup a cada aplicação, então reaplicar um perfil
  (ex.: aplicar o Game Clean duas vezes) fazia o "Reverter TUDO" restaurar um valor
  intermediário em vez do original. Agora ele guarda só o primeiro valor de cada
  chave, mantendo a reversão fiel ao estado de fábrica.

### Notas
- `game-clean.sh` foi adicionado à whitelist do painel (`lib.php`), ao catálogo do
  app (`actions.json`) e tem testes próprios em `tests/run.sh` (`t_gameclean`).

## [2.20.0] - 2026-10-05

### Adicionado
- **Anti-relog (manter o app vivo).** Novo módulo `scripts/keep-alive.sh` que impede
  o app/jogo de ser morto ao sair para a tela inicial — o que fazia ele **abrir do
  zero e pedir login de novo** (ou sair da partida) ao voltar. Para o app escolhido,
  ele isenta do Doze, libera segundo plano e wake lock, coloca no balde ativo de
  standby, tira do congelador/cache freezer e, com root, baixa o `oom_score_adj`.
  Nada de valor inventado: cada item é aplicado e lido de volta. Reversível com
  "Deixar de manter o app" ou "Devolver todos ao normal". Categoria **Processos**:
  `Manter app vivo (não relogar)`, `Manter jogo vivo (não relogar)` (também libera o
  Game Mode), `Deixar de manter o app`, `Ver estado anti-relog`, `Apps protegidos
  (anti-relog)` e `Devolver todos ao normal`.

### Notas
- `keep-alive.sh` foi adicionado à whitelist de scripts do painel (`lib.php`) e ao
  catálogo do app (`actions.json`), com testes próprios em `tests/run.sh` (`t_keepalive`).

## [2.19.0] - 2026-10-05

### Corrigido
- **Taxa de atualização aparecia errada.** A home mostrava a maior taxa que a
  tela suporta (ex.: 90Hz) mesmo com o aparelho usando 60Hz. Agora ela mostra a
  taxa **em uso**: se você travou uma taxa, aparece a taxa travada; senão, a taxa
  atual lida do sistema. A métrica virou **"Taxa de tela"**, com a legenda dizendo
  se está "travada (fixa)" ou é a "taxa atual".

### Adicionado
- **Escolha da taxa de atualização (Hz).** Novo cartão com **60Hz, 90Hz, 120Hz e
  Automático**. Quem prefere 60Hz no dia a dia (economiza bateria) escolhe 60 com
  um toque; o painel marca qual está em uso. Uma taxa fixa também evita a tela
  oscilar (60↔90Hz) no meio da partida.
- **Seletor de apps com nome e ícone.** Onde antes era preciso digitar o pacote
  (`com.exemplo.app`), agora abre uma lista com o **nome e o ícone** de cada app
  instalado, com busca por nome ou pacote. Vale para o **driver gráfico por app**
  e para **"Abrir apps mais rápido"** (compilação ART). O ícone vem do próprio
  Android (PackageManager) e é exibido no painel.
- **Terminal de verdade.** Nova aba **Terminal** para rodar comandos no aparelho
  pelo mesmo acesso do pack (Shizuku, ADB por Wi-Fi ou root), com histórico pelas
  setas ↑/↓ e saída na tela. O histórico também entra em **Logs**.
- **Logs completos.** O antigo botão "Console" virou **Logs**, com painel próprio
  que mostra o **histórico completo** (sem truncar), com data/hora, resultado e o
  comando de cada entrada. O botão "Histórico" foi unificado nele.
- **"Abrir apps mais rápido".** O cartão de compilação por app (ART/AOT) ficou
  mais claro: escolha o app pelo nome/ícone e o modo (speed-profile, speed,
  everything).

### Alterado
- **Rodapé de créditos organizado.** O Discord deixou de ser uma linha solta com
  botões repetidos: agora tem o bloco **Créditos** (criador + usuário) e os botões
  **Meu Discord** e **Servidor** agrupados e alinhados.

## [2.18.0] - 2026-10-05

### Corrigido
- **DNS recomendado deixava o aparelho sem internet.** O pack (e o perfil
  "Gaming") apontava o DNS privado para `1dot1dot1dot1.cloudflare-dns.com`, um
  host que saiu do ar: sem resolver, o Android não conectava a nada. Agora o host
  é o `one.one.one.one` (o endereço DoT estável do Cloudflare). Quem já tinha
  ficado sem internet volta ao normal com "DNS automático" ou escolhendo outro
  perfil na categoria **DNS e rede**.

### Adicionado
- **Mais motores gráficos (renderizadores).** Além de OpenGL, SkiaGL e Skia
  Vulkan, entram **SkiaGL multithread** e **Skia Vulkan multithread** (composição
  numa thread separada). Cada opção grava o valor anterior do prop, então dá para
  voltar com "Reverter TUDO"; o painel marca qual está em uso (o backend
  desempata os modos multithread).
- **Mudança por app (renderizador).** Novo cartão **"Motor gráfico por app"**:
  escolha o app/jogo e o driver — **ANGLE**, **Nativo** ou **Padrão**. Usa as
  mesmas opções de "Driver gráfico" do desenvolvedor, por app e sem root
  (`deep-tune.sh angle set <pkg> angle|native|default`), com reversão.
- **DNS como escolha.** A categoria **DNS e rede** ganhou um cartão de escolha
  rápida (Cloudflare, Google, Quad9, AdGuard, Mullvad, OpenDNS Família, Gaming)
  no mesmo estilo do renderizador, com "Em uso" marcado pelo host real do
  aparelho. A lista completa de perfis continua logo abaixo.

## [2.17.0] - 2026-10-05

### Corrigido
- **Arrasto lateral com DPI baixa.** Ao reduzir o DPI abaixo de 100%, o painel
  esticava o conteúdo para além da tela (a largura era forçada a `100% / escala`)
  e a página voltava a arrastar de lado. Agora a compensação de largura só é
  aplicada quando o zoom **aumenta** (acima de 100%); abaixo disso o próprio zoom
  já encolhe tudo, então a largura fica em `100%`. Medido com Chromium em
  320/360/412/480px de largura, de 60% a 160% de DPI: nenhum estouro.

### Alterado
- **Home reorganizada, mais fácil de entender.** As métricas agora vêm em dois
  grupos rotulados — **Sistema agora** (RAM, CPU, bateria, armazenamento, tela,
  tempo ligado) e **Uso do aparelho** (app em primeiro plano e uso nas últimas
  24 h) — em vez de uma lista única de oito cartões misturados. O grupo de uso
  mostra um selo **"precisa do Acesso a dados de uso"** enquanto a permissão não
  é liberada, com um botão **Liberar** que abre a tela do sistema. O botão
  **Atualizar** foi para o cabeçalho do painel (no lugar de um botão solto no
  fim), e o indicador **ao vivo** mostra há quanto tempo os números foram lidos.

## [2.16.0] - 2026-10-05

### Adicionado
- **Acesso a dados de uso (`PACKAGE_USAGE_STATS`)**: o app agora pede, uma vez por
  versão, a autorização de "Acesso a dados de uso" (a tela do próprio Android) e
  passa a ler dados que só o sistema entrega por essa permissão. Com isso a Home
  ganhou dois cartões novos:
  - **App em primeiro plano** — qual app está na frente agora (nome + pacote).
  - **Uso nas últimas 24 h** — tempo de tela total e os apps que mais usaram.
  A leitura é feita direto pela API do Android (`UsageStatsManager`), então funciona
  **sem Shizuku/ADB/root**. Sem a autorização, os cartões mostram **—** e aparece
  um aviso explicando como liberar — o pack nunca inventa número.
- **Botão "Acesso a dados de uso"** em Configurações → Permissões, que abre a tela
  de autorização do sistema. Também entra no pedido automático da primeira abertura.

## [2.15.0] - 2026-10-05

### Adicionado
- **DPI bem menor no painel**: o controle "Tamanho da interface (DPI)" agora vai
  de **60% a 160%** (antes só subia, de 100% a 140%). Dá para deixar a interface
  bem compacta, do jeito que estava faltando — o mínimo de 100% ainda ficava grande.
  O ajuste continua salvo no aparelho (`otm-scale`) e vale para o painel do app e
  para o painel web, sem mexer no zoom do sistema.

### Alterado
- **Frase do topo do painel** reescrita: agora diz que o pack junta DNS, RAM,
  renderizador, touch do Free Fire, debloat e ajustes profundos "tudo num lugar só"
  e convida a deixar o celular "liso que nem sabão". Mantém a dica do **?** dos
  cartões.

## [2.14.0] - 2026-10-05

### Adicionado
- **Home com o consumo REAL do aparelho.** A primeira tela do painel agora mostra,
  ao vivo (atualiza a cada 4 s), RAM em uso, carga da CPU, bateria, armazenamento,
  tela (Hz) e tempo ligado — lidos do próprio celular (`scripts/panel-stats.sh`).
  O que o aparelho não informa aparece como **—**, nunca um número inventado.
  Inclui atalhos para as ações mais usadas (snapshot, limpar RAM, fluidez, abrir FF)
  e navegação direta para cada categoria.
- **Gerenciador de processos de verdade** (`scripts/proc-mgr.sh` + categoria
  **Processos** no painel): lista os apps que mais gastam CPU/RAM agora, mostra
  PID/RAM/nice/oom de um app e permite **limitar RAM**, **priorizar CPU**
  (`top-app`/`foreground`/`background`), **mudar o nice**, **congelar/descongelar**
  e **remover limites**. Tudo com dados reais de `/proc`; sem root, avisa e não
  finge que aplicou.
- **Sono profundo (Doze)** com cartões próprios: ligar e desligar as constantes de
  repouso (`device_idle_constants`) e ver o estado atual (`doze.status`).
- **Latência fina do toque** (`touch.latency`): ajuste direto da responsividade
  (1–1000) com sliders, junto dos demais parâmetros do toque. A chave é testada
  antes de aplicar — se o aparelho não expõe `touch_responsiveness`, o pack avisa
  em vez de registrar falha à toa.
- **Novos perfis de DNS**: agora são **39 perfis DoT** de alta qualidade, todos com
  hostname verificado na fonte oficial. Além dos já existentes, entraram AdGuard sem
  filtro, Cloudflare Segurança, Mullvad (base/ads/família/estendido/tudo), ControlD
  (sem filtro/malware/ads/redes/família/OISD), DNS4EU (protetor/infantil/sem-ads/
  infantil+ads/sem filtro — infraestrutura da UE), CleanBrowsing Adulto, DNS.SB,
  CZ.NIC ODVR, Digitale Gesellschaft (Suíça), RESTENA (Luxemburgo), Applied Privacy
  (Áustria) e UncensoredDNS (Dinamarca).
- **Nova categoria "DNS e rede"**: os perfis de DNS, o benchmark de latência, os
  ajustes de Wi-Fi, os buffers TCP e a economia de dados saíram de "Rede e conexão"
  e agora têm uma aba própria, para achar o DNS na hora.
- **Persistir no boot** (root): reaplica os ajustes aplicados sempre que o aparelho
  reinicia, via `/data/adb/service.d` (Magisk) ou `init.d`. `turbo.sh boot on|off|status`
  e cartões "Persistir no boot" na categoria Sistema.

### Alterado
- Menu lateral agora tem **7 categorias**, com **DNS e rede** (39 perfis de DNS) e
  **Processos** próprias; a Home é a primeira opção e abre as métricas antes de
  qualquer ajuste.

### Notas
- Versão `2.14.0` (`versionCode` 35).

## [2.13.0] - 2026-10-05

### Adicionado
- **O painel mostra o estado REAL do aparelho** (`scripts/panel-state.sh`): qual
  renderizador está de fato em uso (`debug.hwui.renderer`), se a GPU está forçada,
  e os valores ATUAIS do toque (`touch_responsiveness`, `long_press_timeout`,
  `pointer_speed`, `touch_slop`), o refresh (`min/peak_refresh_rate`) e o ANGLE
  por app. Nada de número fictício: o que não dá para ler volta em branco.
  Novo endpoint `api.php?action=state` e `stateImpl()` na ponte do app.

### Alterado
- **Renderizador e perfis de toque viraram opções lado a lado.** Em vez de vários
  cartões soltos, um único cartão com OpenGL / SkiaGL / Skia Vulkan (e outro com os
  5 perfis de toque), botões clicáveis que marcam a opção **em uso** e mostram
  **"Selecionar"** no lugar de "Executar" — afinal, ali você escolhe uma
  configuração, não aplica uma otimização.
- **Ajuste fino do toque agora tem slider arrastável** (arraste com o dedo) com
  campo numérico ao lado, para responsiveness, long press, pointer speed e touch
  slop. Os valores abrem já com o que está no aparelho.
- **Botão de tema ao lado da engrenagem** e visível no celular (antes sumia por
  causa do `hide-sm`).
- **Menu lateral redesenhado:** 5 categorias (Rede e conexão entrou em Desempenho),
  itens maiores, com contador em pílula e destaque melhor.
- **Painel mais leve:** removido o `backdrop-filter` por cartão e a animação de
  brilho do botão primário (eram as maiores fontes de travamento na rolagem).

### Notas
- Versão `2.13.0` (`versionCode` 34).

## [2.12.0] - 2026-10-05

### Adicionado
- **Refresh fixo** (`turbo.refresh_fixed`, 60/90/120/144Hz): trava min = peak para
  estabilizar o frametime quando a tela oscila de taxa no meio da partida.
- **Áudio de baixa latência** (`turbo.audio`, root): reduz o buffer de áudio
  (`audio.deep_buffer.media=0`) — ouvir passos/tiros mais cedo.
- **Compactação de memória** (`turbo.mem_compact`, root): recupera RAM compactando
  páginas ociosas, sem matar apps (`am kill-all` é evitado de propósito).
- **Foco de jogo / DND extremo** (`game_focus`): DND + heads-up + bolhas.
- **Janela multitouch** (`touch.multi`, 100–800 ms): resposta mais imediata com
  vários dedos.
- **Persistir no boot** (`turbo.boot`, root): reaplicador em Magisk `service.d` ou
  init.d que reaplica os ajustes após reiniciar.

### Notas
- Auditoria crítica do "app laranja"/NexaCore em `docs/ROADMAP.md` §12: boa parte
  dos itens já existia (ANGLE, SkiaGL/SkiaVK, frame pacing, Wi-Fi scan, DNS, DND);
  o que era placebo/inseguro ficou de fora.
- Versão `2.12.0` (`versionCode` 33).

## [2.11.0] - 2026-10-05

### Alterado
- **Painel reorganizado em 6 categorias** (antes eram 16, difíceis de achar):
  - **Geral** — aplicar/reverter o pack, snapshots e módulos.
  - **Display & Touch** — renderizador, resolução, display/HWUI e toque do Free Fire.
  - **Rede e conexão** — DNS privado, Wi-Fi, rede móvel e buffers TCP.
  - **Desempenho** — RAM, limpeza, turbo/RAM, tela/bateria, congelar apps e os
    ajustes profundos/extremos (root).
  - **Apps e jogos** — tuning por app/jogo (ANGLE, Game Mode, resolução), debloat
    por perfil e por app.
  - **Sistema** — conexão do pack, permissões, aparência, notificações e diagnóstico.
- Os avisos de voz seguem a categoria nova (som por assunto).
- Versão `2.11.0` (`versionCode` 32).

## [2.10.0] - 2026-10-05

### Corrigido
- **Avisos sonoros voltaram a tocar.** O `SoundPlayer` usava o canal de
  *sonificação* (`USAGE_ASSISTANCE_SONIFICATION`), que fica mudo em muitos
  aparelhos mesmo com o volume de mídia alto. Agora usa o canal de **mídia**
  (`USAGE_MEDIA`), então os avisos saem no volume normal do celular.
- **MP3 descomprimidos no APK.** Adicionado `noCompress += "mp3"` no
  `build.gradle.kts`; sem isso o `assets.openFd()` falha no APK release e o som
  some em silêncio.
- **Falhas de áudio não são mais engolidas.** O `SoundPlayer` agora registra no
  logcat (`Log.w("SoundPlayer", …)`) quando um som falha ou dá erro de mídia.

### Adicionado
- **Botão de som do cabeçalho funciona.** O botão (ícone SVG) do topo do app
  agora liga/desliga o som e mostra o estado (esmaece quando desligado); o
  estado sobrevive ao reload via `localStorage`.
- **Mais cores de destaque:** prata, dourado, ciano, grafite e âmbar (além das
  6 anteriores). A **prata** era o pedido.
- **Mais fontes:** condensada, arredondada, geométrica e humanista (além de
  sistema, serifa e mono). O seletor quebra em várias linhas no celular.

### Alterado
- Versão `2.10.0` (`versionCode` 31).

## [2.9.0] - 2026-10-05

### Adicionado
- **Dois avisos sonoros novos.** O app agora toca "pareamento feito com sucesso,
  faça login no sistema" ao conectar (Shizuku ou ADB por Wi-Fi) e "credenciais
  incorretas" quando o login do painel falha. A tela de login avisa o app
  (`OTM.call("login")` no acerto e `OTM.call("login_fail")` no erro), então cada
  caso toca o áudio certo. Os MP3 ficam guardados sem compressão no APK
  (`openFd` exige STORED).
- **Ícones profissionais no lugar dos emojis.** Painel do app, tela de login e
  painel web passaram a usar ícones SVG desenhados (traço/fill no estilo do tema)
  em vez de emojis e glifos. A engrenagem das Configs continua como está.
- **Atualização por cima, sem desinstalar.** O APK agora é assinado com uma
  keystore fixa e versionada no repositório (`android/keystore/otm-release.jks`),
  e o `build.gradle.kts` usa essa assinatura no `release`. Como a assinatura é a
  mesma em toda versão, dá para instalar a atualização por cima sem erro.

### Alterado
- Versão `2.9.0` (`versionCode` 30).

### Nota
- Quem tem a versão antiga (assinada com certificado de debug) precisa
  desinstalar **uma vez**. A partir da 2.9.0, todas as atualizações seguintes
  instalam por cima.

## [2.8.1] - 2026-10-05

### Corrigido
- **Som "login feito com sucesso" só no login certo.** Antes ele tocava ao ligar o
  som e ao conectar (Shizuku/ADB). Agora a tela de login avisa o app
  (`OTM.call("login")`) apenas quando o usuário e a senha conferem, e o app toca o
  aviso só nesse momento. Ligar o som usa "ativando" e conectar segue com o som
  do próprio fluxo.

## [2.8.0] - 2026-10-05

### Adicionado
- **Configs: permissões e segundo plano.** A engrenagem agora mostra as permissões
  que o app precisa (notificações, bateria sem restrição, rodar em segundo plano,
  isento do Doze e acesso por Shizuku/ADB) e tem botões para conceder de verdade:
  - **App do pack** (`perm.app`) e **Free Fire** (`perm.ff`): entram na lista de
    isenção do Doze e ganham permissão de segundo plano, wake lock e início em
    segundo plano via `appops`.
  - **Bateria sem economia** (`perm.battery`): desliga o modo de economia, o
    App Standby e a gestão adaptativa.
  - **Aplicar todas** (`perm.all`): faz os três de uma vez.
  Tudo reversível em "Reverter TUDO" (os comandos de desfazer vão para o backup).
- **Permissões do próprio app no Android.** O `AndroidManifest` declara
  `POST_NOTIFICATIONS`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` e
  `FOREGROUND_SERVICE`. O app cria um canal de notificação, pede para sair da
  otimização de bateria (uma vez por versão) e mostra uma notificação curta quando
  uma ação termina. Nada disso bloqueia o painel: recusar só custa som/avisos.
- **Personalização do app dentro do painel.** Além de tema, cor de destaque e som,
  a engrenagem ganhou **fonte** (sistema, serifa, mono), **DPI do app** (100% a
  140%) e **restaurar padrão**. Tudo salvo em `localStorage` (`otm-font`,
  `otm-scale`), aplicado tanto no app quanto no painel web.
- **Botão "Conectar" garantido no app.** O `PanelActivity` injeta o botão de
  conexão após cada carga da página, então ele nunca some mesmo se a página for
  atualizada.

### Corrigido
- **DPI sem arrasto lateral.** O zoom do DPI compensa a largura
  (`width: calc(100% / escala)`) e o `<html>` clipa o transbordo
  (`overflow-x: clip`), então aumentar o DPI não reintroduz o arrasto lateral.
- **Ação longa vira erro de verdade.** Uma ação aplicadora que não muda nada no
  sistema agora retorna `ok:false` no app (antes o resultado podia aparecer como
  sucesso mesmo sem efeito).

## [2.7.0] - 2026-10-05

### Adicionado
- **Botão de configurações (engrenagem)** no topo do painel (app e web), abrindo um
  modal com **tema** (claro/escuro/automático), **cor de destaque** (6 opções) e
  **som** (ligar/desligar). As preferências ficam salvas no aparelho
  (`localStorage`). O botão ◐ do topo continua como atalho de tema.
- **Card "Aparência e som"** na aba **Configs**, que abre o mesmo modal. É uma ação
  de interface (`"ui" => "appearance"` em `web/lib.php`), então aparece nos dois
  painéis sem depender de comando no shell.

### Corrigido
- **Arrasto lateral excessivo.** A barra do topo tinha mais largura que a tela
  (`scrollWidth` 674px num aparelho de 360px), o que permitia arrastar a página
  para o lado. Agora o topo usa `min-height` + `flex-wrap` (quebra em linhas em
  vez de estourar) e a página clipa o transbordo horizontal (`overflow-x:clip`),
  então não há mais arrasto lateral em nenhuma largura.
- **Botões do topo desorganizados.** Os botões não encolhem mais (`flex:none`),
  quebram em linhas alinhadas e ficaram mais compactos no celular; "Status",
  "Histórico" e o tema já se escondem nas telas estreitas.
- **Papel de parede cortado.** A imagem passou a aparecer **inteira**
  (`center/contain`) sobre um fundo que preenche a tela (`center/cover`), no
  painel, no login do app e no painel web. O véu de contraste ficou mais suave
  para o papel de parede aparecer melhor.
- **Sons.** O botão de som do app agora **liga/desliga** de verdade (antes só
  alternava um estado) e toca um aviso curto ao ligar. Um som novo não é mais
  cortado pelo temporizador do som anterior (`SoundPlayer` cancela o timer antes
  de agendar o próximo). A ponte ignora ações sem comando (como a de aparência).

## [2.6.0] - 2026-10-05

### Corrigido
- **App: "Permission denied" ao executar qualquer ação.** O Shizuku/ADB roda como
  usuário `shell` (uid 2000), que não consegue ler nem executar nada dentro de
  `/data/user/0/com.otm.pack` (modo 0700). Os scripts eram extraídos justamente
  ali, então `cd`/`sh` falhavam com `Permission denied` e o painel mostrava
  "Falhou". Agora `PackAssets.ensureShellCopy` copia `scripts/` + `VERSION` para
  **`/data/local/tmp/otm-pack`** (acessível ao shell) e o `HOME` aponta para lá,
  de modo que o estado (`~/.packotm`) também fica num lugar que o shell alcança.
  A cópia local em `filesDir/pack` continua servindo só para o app ler os `.txt`
  do nível 1 (que são enviados como comandos prontos, sem o shell tocar o arquivo).
  A cópia é refeita quando o selo de versão não bate (primeira vez, atualização
  ou reboot).

## [2.5.0] - 2026-10-05

### Adicionado
- **Tela de login no app Android** (`assets/panel/login.html`): entrada com a identidade
  visual do painel (efeito de vidro, animações, `prefers-reduced-motion`), mostrar/ocultar
  senha e erro de credencial. Credencial **`00deUdia` / `159951`**.
  - A senha **não** fica em texto no APK: o login confere `SHA-256("usuario:senha")` contra
    um hash embutido, com SHA-256 implementado em JS puro (não depende de `crypto.subtle`,
    que falta em WebViews antigas e em `file://`).
  - Sessão em `localStorage` (`otm_session`); o `index.html` tem guarda no `<head>` que
    volta ao login quando não há sessão. Botão **Sair** limpa a sessão.
  - `PanelActivity` abre `login.html` e só injeta "Conectar"/"Som" no cabeçalho do painel
    (a tela de login não recebe botões nativos).

### Corrigido
- **Menu lateral travado no lugar**: `.side .panel` agora é `position:fixed` na viewport.
  Antes, com `position:sticky` dentro do grid, o menu "escorregava" e pinava no rodapé ao
  rolar até o fim (ficava em `Y=-35px`, com o topo cortado). No mobile (`<=960px`) o painel
  volta a `position:static` dentro da gaveta fixa.

## [2.2.0] - 2026-10-05

### Adicionado
- **Login no painel web** — o **00deUdia Otimizações** agora pede usuário e senha antes de
  mostrar qualquer coisa. Tela de entrada com a identidade visual do painel (efeito de vidro,
  animações, `prefers-reduced-motion`) e botão **Sair** no topo.
  - Credencial inicial definida no código; troque com `sh main.sh web senha`.
  - Senha guardada com **`password_hash`** em `~/.packotm/web/auth.json` (nunca em texto puro,
    nunca versionada — está no `.gitignore`).
  - Sessão PHP com cookie `HttpOnly`/`SameSite=Lax` e **CSRF** no formulário.
  - A API (`web/api.php`) passa a exigir a **sessão logada** (o token `web/.token` continua
    valendo como defesa em profundidade). Sem login e sem token, nada executa.
- `main.sh web senha` (troca usuário/senha) e `main.sh web logout` (encerra a sessão).
- Testes `t_auth` (credencial inicial, senha errada, troca de senha, hash não-texto-puro) e
  cobertura do fluxo login→painel. Suíte: **137 testes**.

### Corrigido
- **Colisão de variável global** em `_with_timeout` (`t`) que quebrava a **verificação real**
  do `bkp_set` e fazia o painel relatar "nada mudou" mesmo quando aplicava. A verificação real
  (applies/changed/failed) agora funciona de ponta a ponta.
- `web_url` não coloca mais o token na URL (o acesso é por login).

## [2.1.0] - 2026-10-15

### Adicionado
- **Otimizações EXTREMAS e pouco conhecidas** — 11 módulos novos no `deep-tune.sh`,
  todos com reversão por módulo (tag própria) e ajuda em linguagem simples no painel:
  - `vm` — gerenciador de memória do kernel (vfs_cache_pressure, dirty, min_free_kbytes,
    watermark): menos engasgo de I/O e apps que reabrem rápido.
  - `sched` — escalonador/EAS: migração, granularidades e `schedtune` (boost no app em foco).
  - `gpu` — **GPU extrema**: trava clock no topo e desliga idle/throttling da GPU
    (Adreno/KGSL e Mali/devfreq). É o ajuste que mais segura FPS.
  - `cores` — desliga hotplug/core_ctl e mantém os núcleos ligados.
  - `input` — **input/touch boost**: sobe a CPU no instante do toque.
  - `idle` — governor de idle `menu` + desliga idle profundo (acorda mais rápido).
  - `net2` — **BBR2** + MTU probing + desliga slow-start após ocioso + buffers finos.
  - `zram` — compressão **zstd** + mem_limit + swappiness (mais RAM efetiva).
  - `kernel` — desliga tracing/debug do kernel e sobe file-max/backlog.
  - `display` — props `debug.*` do SurfaceFlinger/HWUI (**sem root**): rolagem mais lisa.
  - `dalvik` — heaps do ART e filtro de compilação `speed`.
  - `dexopt` — recompila os apps em AOT (`cmd package compile -m speed -a`).
- **`gaming extreme`** (e atalho `extreme`) — liga o turbo **e** todos os módulos avançados
  de uma vez. Avisa que esquenta muito. Reversível com `restore`.
- **4 grupos novos no `adb-tweaks.sh` (sem root)**: `obscure` (standby/Doze + whitelist do
  Free Fire), `mobile_net` (economia de dados off), `notif` (heads-up off) e
  `window_tweaks` (transições + modo imersivo).
- **Painel web**: duas categorias novas — **Extremos (root)** (25 ações, com botão de
  ligar/desligar por módulo) e **Avançado (sem root)** (4 ações). Registro: **118 ações
  em 15 grupos**. Ação **⚡ MODO EXTREMO (tudo)** com confirmação e timeout maior.
- **Menus** (`menu.sh` e `pack.sh`) ganharam as opções 40–58 / 101–124 para os módulos
  extremos, o modo extremo e os ajustes sem root.
- Testes: `t_extreme` (módulos avançados rodam e a reversão respeita a tag) e
  `t_adv_noroot` (grupos sem root aplicam e revertem). Suíte: **103 testes**.

## [2.0.0] - 2026-10-15

### Adicionado
- **`main.sh` (raiz) — menu principal alternativo**, diferente do `pack.sh`. Foco em:
  **baixar os recursos full** (pacote completo via codeload do GitHub, extrai com tar),
  **subir o servidor web** (painel PHP), **abrir o painel** no navegador, ver URL+token,
  parar/status do servidor, atualizar (git pull) e status geral. Uso: `sh main.sh web start`,
  `sh main.sh baixar`, `sh main.sh web url`.
- **Painel web em PHP (`web/`) — controle completo do pack pelo navegador.** Menu lateral
  por categorias, cards com botões, console de saída, histórico de ações e **modal de
  confirmação para ações de risco** (debloat, congelar, root, downscale).
  - `web/lib.php` — registro de **89 ações** em **13 grupos**: Rápido, **DNS (perfis)**,
    RAM/Limpeza, **Renderizador** (OpenGL/SkiaGL/Skia Vulkan/forçar GPU),
    **Por app/jogo** (ANGLE Vulkan, modo performance, downscale/FPS, reset),
    **Touch/Free Fire**, Performance, **Wi-Fi e rede**, Congelar apps, **Debloat**
    (perfil + por app: desativar/reativar/desinstalar/reinstalar/restringir),
    **Profundas (root)**, **Diagnóstico** (perfil do aparelho, temperatura, benchmark)
    e **Módulos**. Cada ação tem `desc` curta + `help` (explicação para o usuário).
  - `web/api.php` — endpoint JSON com **autenticação por token** (arquivo `web/.token`,
    gerado no primeiro `web start`), **lista branca de scripts** e **validação** de
    pacote/host/número. Nunca recebe comando cru: monta o argv a partir do registro.
  - `web/index.php` — painel **00deUdia Otimizações**, renderizado no servidor em PHP
    (menu de categorias e cards de ação saem prontos no HTML). Visual **clean** com
    **efeito de vidro** (glassmorphism), paleta própria (tinta quente + laranja),
    **tema claro/escuro** (segue o sistema, com botão para trocar), **menu lateral que
    acompanha a rolagem** (sticky, até o fim da tela) e **responsivo de verdade**
    (gaveta lateral no celular, grid fluido, campos que empilham, áreas de toque grandes).
  - **Botão de ajuda "?" em cada ação**: abre um modal explicando, em linguagem simples,
    o que aquela opção faz e como reverter.
  - Visual: **wallpaper** de fundo (`web/assets/wallpaper.jpeg`) e **banner** no topo
    (`web/assets/banner.jpeg`), com camadas de escurecimento para manter a legibilidade.
- Segurança: o token nunca vai no `.zip` (build remove `web/.token`); `.gitignore`
  cobre `web/.token` e `web/.state/`.
- Build do "Pack 00" agora inclui `main.sh` e `web/`.
- Testes `t_web` (main.sh, lint do PHP, cobertura do registro, validação anti-injeção,
  confirmação de risco, render no servidor, efeito de vidro e explicação em toda ação).
  Suíte: **83 testes**.

## [1.9.0] - 2026-10-15

### Adicionado
- **`scripts/dns.sh` — DNS privado com perfis** (DNS-over-TLS, sem root), integrado ao
  menu (opção **13**). Perfis: `cloudflare` (privacidade), `quad9` (malware),
  `adguard` (bloqueio de anúncios), `adguard-family`, `cloudflare-family`, `mullvad`,
  `dnsforge`, `google` (compatibilidade), `gaming` (baixa latência + buffers TCP +
  Wi-Fi scan off), `custom <host>` e `off`/`auto`. Submenu interativo + linha de comando;
  reversível (guarda o DNS antigo em `~/.packotm/off.sh`).
- **`scripts/modules.sh` — executar os módulos e plugins da pasta** (menu, opção **80**).
  Descobre tudo que tem `module.prop` em `00 Otimizações/Modulos/` e em
  `00 Otimizações/Plugins AxManager/`, mostra os scripts disponíveis
  (`action`/`apply`/`service`/`uninstall`/`restore`) e executa: `run <nome>`,
  `info`, `actions`, `action <nome> <script>`. Executa o script avulso no shell atual
  (o modo serviço/boot/WebUI continua exigindo instalar no gerenciador).
- Menu-mestre: novas opções **13** (DNS com perfis) e **80/81** (módulos/plugins);
  dispatch `dns` e `modules`; tratamento de **EOF** nos menus (não trava mais sem entrada).
- Site: 5 comandos novos de DNS (perfis) + nota de "rodar módulos sem instalar".
- Testes `t_dns` e `t_modules` (perfis aplicam/revertem; descoberta e execução).

## [1.8.0] - 2026-10-15

### Adicionado
- **Menu-mestre `scripts/pack.sh`** — ponto único de entrada que gerencia todos os
  outros scripts (`adb-tweaks`, `deep-tune`, `debloat`, `ff-touch`, `game-per-app`,
  `snapshot`, `bench`, `device-profile` e os builds). Funciona como **menu interativo**
  (numerado, com cabeçalho de status) e por **linha de comando** (`status`, `apply`,
  `restore`, `debloat on medio`, `touch headshot`, `snapshot save`, `test`, `build`…).
  - Tela de **status** mostra modo de execução, privilégio, SoC, versão, o que já está
    aplicado (deep, debloat) e quantos snapshots existem.
  - `apply` aplica o conjunto recomendado; `restore` desfaz **tudo** (níveis 2,
    profundas e debloat) de uma vez.
  - Delega com segurança para cada módulo — sem reimplementar nada.
- **Launcher `pack.sh` na raiz** — permite `sh pack.sh` de qualquer pasta.
- Teste `t_pack` (help, status, delegação ao debloat, atalho do nível 2).

### Corrigido
- **`00 Otimizações/Scripts SH/run.sh` (nível 2)** apontava para um caminho
  inexistente (`00 Otimizações/scripts`) desde a reorganização — o atalho estava
  quebrado. Agora ele localiza `scripts/` de forma robusta (aceita `OTM_SCRIPTS`) e
  delega ao menu-mestre. Os testes não executavam o `run.sh`, por isso passou batido.

## [1.7.0] - 2026-10-15

### Adicionado
- **Debloat / Bloatware** — área nova para tirar o peso dos apps que você não usa,
  **sem root** e **reversível** (nada é apagado de verdade):
  - **`scripts/debloat.sh`** — perfis `leve` / `medio` / `pesado`. Desativa
    gerenciadores de fabricante (Samsung GOS, Xiaomi Joyose, Motorola Gamemode) e
    restringe o resto por `appops` + `standby bucket`. Ações por app: `disable`,
    `enable`, `uninstall`, `restore`, `restrict`, `unrestrict`. Guarda cada reversão
    em `~/.packotm/debloat/off.sh`; o `off` executa tudo de trás para frente.
  - **`21-debloat-bloatware.txt`** (nível 1) — versão copiar-e-colar para o Brevent.
  - **Menu**: opções **32** (aplicar debloat) e **33** (reverter).
  - **Site** (`index.html`): nova categoria **Debloat / Bloatware** com **13 comandos**
    (`pm disable-user`, `pm uninstall --user 0`, `cmd package install-existing`,
    `appops`, `standby bucket`). Total vai a **72 comandos em 11 categorias**.
- Teste `t_debloat` (aplica perfil, registra reversão, reverte; valida `uninstall` →
  `install-existing`).

## [1.6.0] - 2026-10-15

### Adicionado
- **Site completo em `index.html`** — um único arquivo **HTML + CSS + JS puro**, sem
  dependências, que funciona offline e pode ir para o GitHub Pages. Explica os apps, os
  4 níveis, os plugins, os módulos e os perfis de touch.
  - **Área de comandos interativa**: 59 comandos em 10 categorias (Limpeza/Cache,
    RAM/Memória, Congelar apps, Renderizador, Performance/GPU, Rede/DNS, Bateria,
    Tela/Refresh, Touch/Free Fire, Restaurar), com **busca**, **filtro por categoria** e
    **botão de copiar** (com fallback para `file://`).
  - Cobre OpenGL / Vulkan / SkiaGL / SkiaVulkan / ANGLE, `pm trim-caches`,
    `pm suspend`/`unsuspend`, `cached_apps_freezer`, `drop_caches`, `fstrim`, perfis de
    RAM e de toque.
  - Cada comando tem selo de risco: **seguro**, **cuidado** ou **root**.
- **`Apps/README.md`** — guia dos aplicativos para instalar (Brevent, Shizuku, Termux,
  AxManager e root): o que fazem, pacote, onde baixar e como se ligam a cada nível.
- **`scripts/build-pack.sh`** — gera o **"Pack 00" completo em um único `.zip`** pronto
  para baixar e usar: reúne `00 Otimizações/` (níveis 1 a 4), `scripts/` (motor — o
  `run.sh` aponta para `../scripts`), `Apps/`, os zips de `releases/` e os guias.
  Sai em `releases/Pack-de-Otimizacao-00-v<VER>.zip` + `.sha256`.
- Novos testes `t_site_html` (estrutura + sintaxe do JS) e `t_build_pack` (conteúdo do zip).

### Alterado
- README e AGENTS.md agora apontam para o site (`index.html`), para `Apps/` e para o
  `build-pack.sh`.

## [1.5.0] - 2026-10-14

### Adicionado
- **Plugin `06-freezer` (Congelar Apps)** — congela apps de fundo para liberar RAM,
  com **whitelist** (apps que nunca são congelados) e **blacklist** (apps a congelar).
  - Modos `suspend` (estilo Brevent) e `soft` (`disable-user`).
  - Proteção embutida: sistema/essenciais (SystemUI, telefone, teclado, Play Store,
    gerenciadores de root, Termux) nunca são congelados, nem por comando direto.
  - Botão de ação com status; `uninstall.sh` **descongela tudo** antes de sair.
  - CLI completa: `freeze`, `unfreeze`, `wl-add/del`, `bl-add/del`, `freeze-app`,
    `unfreeze-app`, `status`, `restore`.

### Alterado
- **`.txt` revisados** (nível 1): RAM/memória (perfis padrão e gaming + MGLRU/zRAM/KSM),
  limpeza/cache (logs, `fstrim`, `drop_caches`, scheduler I/O), bateria (standby
  `restricted`), touch (5 perfis completos + multi_press), congelar/descongelar com
  whitelist, game mode respeitando whitelist, performance geral.
- **Programas (nível 2)**: `adb-tweaks.sh` ganhou congelamento real com whitelist
  (`freeze_apps`, `freeze_whitelist_add`, `freeze_whitelist_list`), modo `soft`, e o
  grupo **`mem`** (perfil padrão/gaming + MGLRU/KSM/swappiness). Menu e `run.sh`
  atualizados.
- `tests/run.sh`: novos stubs `pm`/`am` e teste `t_freezer_whitelist`
  (blacklist congela, whitelist e sistema protegidos). **28 testes**.

## [1.4.0] - 2026-10-12

### Adicionado
- **Estrutura `00 Otimizações/`** — todo o pack reunido e organizado por tipo:
  `Comandos Brevent/` (nível 1), `Scripts SH/` (nível 2), `Plugins AxManager/`
  (níveis 3 e 4) e `Modulos/`.
- **Plugins próprios novos**: **03-battery-thermal** (economia + trava térmica a
  45 °C), **04-cleaner** (limpeza de cache/log/fstrim) e **05-fps-refresh**
  (refresh máximo + modo de jogo, reversível).
- `00 Otimizações/Plugins AxManager/README.md` — índice dos plugins.
- `.../Terceiros-open-source/` — plugins de **licença permissiva** (Stellar-Tweaks,
  Kang, Sakoiire, Aapt-for-Plugin — Apache-2.0) com `CREDITS.md` e `LICENSE`
  preservados. Fonte do Stellar-Tweaks (v22.0) incluída.

### Alterado
- `scripts/build-plugins.sh` — varre `Plugins AxManager/` (Nossos + OSS) e empacota
  cada plugin com `module.prop`.
- `scripts/build-modules.sh` — aponta para `00 Otimizações/Modulos/`.
- CI e `tests/run.sh` — sintaxe cobre toda a árvore; shellcheck restrito ao nosso
  código (módulos/plugins de terceiros mantêm o estilo do autor); empacotamento
  valida os 5 plugins próprios + 3 de terceiros.
- README, COMECE-AQUI, AGENTS e docs apontam para os novos caminhos.

### Movido
- `nivel-1-txt/` → `00 Otimizações/Comandos Brevent/`.
- `nivel-2-sh/` → `00 Otimizações/Scripts SH/`.
- `plugins/` → `00 Otimizações/Plugins AxManager/Nossos/`.
- `modules/` → `00 Otimizações/Modulos/`.

## [1.3.0] - 2026-10-08

### Adicionado
- **Módulos do autor restaurados** em `00 Otimizações/Modulos/`: **WS7_OFF7**, **NexaCore**,
  **Astrax**, **NOVA TOUCH**, **VOID TOUCH Ultra**, **VeuLexier**.
- `scripts/build-modules.sh` — empacota os módulos próprios em `releases/<nome>.zip`.
- Teste `t_build_modules` no `tests/run.sh`.

### Alterado
- CI: job de empacotamento agora gera módulos **e** plugins (`pack`).
- README: tabela de créditos dos módulos do autor.

## [1.2.0] - 2026-10-08

### Removido
- **10 módulos de terceiros removidos do repositório** (AxVision_Hawk, BEN_UNIVERSAL,
  CPU_GPU_Web_Panel_Itachi_Edition, Celestial-Game-Opt, Game_Scale, Gms_Tweaker, Kang,
  MOs_Premium, Phoenix, VOID_BATTERY). O pack passa a conter **apenas conteúdo
  próprio**, eliminando o bloqueador legal de licenças.
- Removidos `THIRD-PARTY-NOTICES.md` e `scripts/check-licenses.sh` (não há mais
  terceiros para licenciar).

### Segurança
- **Removido do versionamento** o `apps_otm.zip` (continha dumps de conversa com um
  token `ghp_…` e zips de terceiros). Veja [`docs/SEGURANCA.md`](docs/SEGURANCA.md).
- Novo `scripts/check-secrets.sh` — varre arquivos versionados por credenciais.

### Adicionado
- `scripts/bench.sh` — benchmark antes/depois (RAM, temperatura, CPU, refresh,
  tempo de abertura de app) com relatório em Markdown.
- `tests/run.sh` — suíte automatizada com stubs (`settings`/`cmd`/`am`/`getprop`),
  cobrindo apply→restore, reversão por módulo e o marcador `deep_mark`.
- `scripts/device-profile.sh` — perfil do aparelho por SoC (compatibilidade).
- `scripts/build-plugins.sh` — empacota só os plugins do pack (níveis 3 e 4).
- `docs/SEGURANCA.md`, `docs/ROADMAP.md`, `docs/COMPATIBILIDADE.md`, `docs/PRODUTO.md`.

### Alterado
- `.github/workflows/build.yml` — CI em push/PR: sintaxe, shellcheck (`-S error`),
  testes e segredos; release publica checksums (`SHA256SUMS.txt`) e usa o
  `CHANGELOG.md` como corpo.
- Trava de segurança térmica: confirmação explícita (`THERMAL_OK=1`) e reversão
  automática do módulo `thermal` acima de `THERMAL_MAX_C` (45 °C) ou ao carregar.

## [1.1.0] - 2026-10-08

### Adicionado
- `scripts/deep-tune.sh` — otimizações profundas **reversíveis por módulo**:
  - `angle` (ANGLE/Vulkan por jogo, sem root), `debloat` (appops/standby, sem root)
  - `freq`, `io`, `mem`, `net`, `latency` (sysfs/kernel, root)
  - `thermal` (afrouxa limite térmico, root, com aviso de risco)
  - `gaming` (TURBO all-in-one), `detect`, `status`, `restore`
- Reversão real por *tag*: `freq off` reverte só a frequência, sem tocar no ANGLE.
- Integração nos plugins 01 (Service Loop) e 02 (WebUI Control) + UI web.
- `docs/AUDITORIA.md` — guia para auditoria externa (comando, risco, ganho, reversão).

### Corrigido
- `common.sh`: `su` pendurava esperando senha — detecção com timeout.
- `adb-tweaks.sh`: `debug.hwui.renderer` é propriedade (não `settings`); removido
  placebo `opengl_renderer`.
- Removidos placebos (`debug.performance.tuning`, `debug.egl.hw`, `debug.sf.hw`).
- Plugins: backup do estado profundo gravado **uma única vez** (marcador `deep_mark`),
  evitando que o loop de 24h duplicasse a reversão.

## [1.0.0] - 2026-10-05

### Adicionado
- Pack em 4 níveis: `.txt` (Brevent), scripts `sh` (Shizuku/root), plugin AxManager
  em loop e plugin com WebUI.
- Perfis de sensibilidade para Free Fire, snapshot/reversão, `COMECE-AQUI.md`.
