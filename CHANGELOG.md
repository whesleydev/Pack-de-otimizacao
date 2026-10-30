# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento [SemVer](https://semver.org/lang/pt-BR/).

## [2.44.1] - 2026-10-30

### Corrigido
- **"Argument list too long" ao analisar o aparelho.** No Android o `printf`,
  `sed` e `grep` são binários do toybox (não são builtins do shell, ao contrário
  do `dash`/`bash` do PC). A leitura da taxa de tela mandava a saída inteira do
  `dumpsys display` — mais de **400 KB** num Samsung — como **argumento** do
  `printf`: o kernel recusa e o comando morre com `Argument list too long`. O erro
  aparecia numa linha distante da real, então parecia um bug aleatório no meio do
  fluxo `auto`. O novo `otm_echo` entrega o texto pelo **stdin** (via heredoc), que
  não tem esse limite, e substituiu todos os pontos que passavam dumps grandes por
  argv (`display_max_hz`, app em primeiro plano, camada do FPS, medição de FPS).
- **Nível de bateria virava um número gigante.** O `dumpsys battery` do Android 14+
  traz uma linha `level:` por UID (dezenas delas). O `awk` sem `exit` imprimia
  **todas** e o `_num` colava os dígitos num valor só (ex.: `808182838…`), que
  estourava a linha do painel. O novo `otm_batt_get`/`otm_batt_field` ancora na
  linha canônica (`level:`, `temperature:`, `status:`) e valida a faixa — o mesmo
  vale para a temperatura. O `_num` também foi limitado a 9 dígitos.
- **Linhas repetidas no fim do resumo.** O `printf` reaproveita o formato quando
  sobram argumentos: duas linhas do resumo tinham **um `%s` e dois argumentos**, e
  a frase inteira saía duplicada. O formato agora consome os dois.

### Adicionado
- Teste de regressão `t_smart_bigdump`: monta um `dumpsys display` de ~400 KB e um
  `dumpsys battery` com várias linhas `level:` e reprova se voltar o E2BIG, se a
  taxa de tela sumir ou se a bateria vier com dígitos colados.

## [2.44.0] - 2026-10-30

### Adicionado
- **Backup cifrado**: exportar/importar as preferências e o estado do otimizador
  protegidos por senha, com a chave no `AndroidKeyStore`.
- **Otimizador que aprende**: memória por assinatura de hardware, mede antes e
  depois e decide o perfil sozinho.

## [2.43.1] - 2026-10-22

### Corrigido
- **Botão do painel flutuante abria ao arrastar.** O guarda de toque (`tapOnly`)
  cancelava só no `pointercancel`, que o navegador nem sempre emite quando o dedo
  **começa** no botão e arrasta a página: o clique sintético do fim do scroll
  abria o flutuante sem querer. Agora o arrasto é detectado por três vias — a
  variação do dedo, a rolagem da página (`scroll`) e o `pointerleave` —, a
  tolerância subiu de 8px para 14px e o toque tem de ser curto (600 ms). Os seis
  `onclick` crus que furam o guarda viraram `data-qa`/`data-game-home`, que passam
  por ele.
- **Conexão ADB por Wi-Fi nunca completava.** `Permissions.askMdns()` pedia a
  permissão de descoberta e o diálogo de pareamento abria **na mesma hora**, antes
  de o usuário responder: o mDNS falhava em silêncio. O novo `askMdnsThen()` só
  abre o diálogo depois da resposta, e o `onRequestPermissionsResult` (que não
  tratava `REQ_MDNS`) agora resolve a permissão. O diálogo continua pedindo **só
  o código de 6 dígitos**.
- **"Conectado" era mentira.** `connect()` devolver `true` só diz que o socket
  abriu, não que o shell responde. `AdbRunner.verify()` testa de verdade e
  `connectAndVerify()` reconecta (o adbd demora a publicar o serviço após parear).
  A depuração USB também passou a verificar antes de anunciar sucesso.

### Adicionado
- **Perfil personalizado com 42 recursos** (era 28): barra de status (bateria em %,
  segundos no relógio, ícones secundários), janela multitouch, compilação ART,
  poda de caches, encerrar 2º plano, processos fantasma, restrição de apps de
  fundo, display/HWUI, recompilação agendada, modo jogo profundo, ajustes obscuros
  e tela 10 min + 120 Hz. O `argv` de `profile.custom.apply` agora é **derivado**
  da mesma lista das opções, então painel e script não têm como dessincronizar.

## [2.43.0] - 2026-10-22

### Adicionado
- **Perfil personalizado completo (28 recursos).** O menu do perfil personalizado
  passou de 7 para **28 ajustes independentes**, cobrindo desempenho, memória,
  gráficos, tela, toque, rede, bateria, notificações e limpeza. As chaves de
  escolha (`anim`, `ram`, `hz`, `touch`, `clean`, `renderer`, `dns`, `proc`,
  `efeitos`, `barras`, `res`, `touchlat`) e as de liga/desliga (`telemetry`,
  `hibernate`, `gpu`, `net`, `latency`, `wifi`, `battery`, `doze`, `freezer`,
  `dnd`, `gamefocus`, `notif`, `perfmode`, `vitality`, `mobile`, `janelas`) ficam
  na **mesma ordem** em três lugares que precisam casar: o `argv` de
  `profile.custom.apply` (`web/lib.php`), a const `CPROF` do HTML e o `PC_ORDER`
  do `scripts/profile-custom.sh`.

### Alterado
- **A aba Geral ficou enxuta: o otimizador virou um hub.** Antes ela misturava
  16 cards soltos (o `auto`, cinco comandos de leitura/teste do otimizador, quatro
  de snapshot, o `restore_all`, os módulos e dois cards enormes do perfil
  personalizado). Agora são 3: **Aplicar o pack recomendado**, **Otimizador
  inteligente** e **Perfil personalizado**. O card do otimizador concentra, num
  só lugar, o seletor de perfil e os botões de leitura (`Analisar aparelho`, `Ver
  plano`, `O que está ativo`), de teste (`Medir antes x depois`, `Comparar
  combinações`) e de snapshot/reversão (`Salvar snapshot`, `Ver snapshots`,
  `Comparar com o último`, `Restaurar último`, `Reverter TUDO`). O perfil
  escolhido no hub é repassado às ações que o aceitam (`smart.bench` etc.).
  As sub-ações levam `'card' => false` no `lib.php` e continuam no `ACTIONS` —
  só não desenham mais um card próprio. `module.run` passou para a aba
  **Sistema**.

### Corrigido
- **A telemetria nunca era desligada pelo perfil personalizado.** A chave
  `telemetry` estava declarada no menu, mas o `pc_apply` não a aplicava — marcar
  "desligar telemetria" não fazia nada. Agora ela é aplicada de verdade.
- **O interruptor de telemetria estava invertido.** Ligar o interruptor
  *religava* a telemetria, e desligá-lo não mexia em nada. Agora `nao` significa
  "não mexer" (padrão) e `off` desliga de fato — igual às outras chaves.
- **Arrastar a lista disparava o botão onde o dedo soltou.** O gatilho das ações
  usava `onclick` puro, que também dispara no "clique" sintético que o navegador
  emite no fim de um scroll. Os dois painéis (app e site) passam a exigir toque
  parado e curto (`tapOnly`, com `pointercancel`), o mesmo critério que os botões
  do cabeçalho já usavam.
- **O flutuante voltava a funcionar sozinho depois de o processo ser morto.** As
  próprias ações de limpeza podem encerrar o processo do painel; o transporte de
  shell (`OtmRunner.current`) voltava nulo e **toda** ação do flutuante dava erro
  no meio da partida. O serviço agora reconecta o Shizuku sozinho (a permissão já
  foi concedida) e o monitor não fica preso em erro.
- **"Exceção (1º plano)" e o jogo `auto` falhavam sem jogo escolhido.** Quando o
  `dumpsys` não dizia quem estava na tela (tela bloqueada, formato novo do
  Android), o `proc-mgr.sh keep-fg` e o `game-per-app.sh auto` devolviam erro em
  vez de cair no jogo escolhido / Free Fire — a mesma decisão do `game_open`.
- **A conexão por ADB Wi-Fi caía sempre no mesmo endereço.** O plano B (loopback)
  e o plano A (host descoberto) compartilhavam o mesmo gerenciador, e o segundo
  ficava com o endereço do primeiro. O endereço passa a ser reaplicado a cada
  chamada.
- **Conexão por depuração sem fio agora pede só o código.** O diálogo tinha um
  bloco "Avançado" com IP e portas para preencher na mão; as portas e o endereço
  são descobertos sozinhos pela rede (mDNS). Ficou só o campo do código de 6
  números, com uma segunda tentativa quando o mDNS perde a primeira resposta.
- **A ordem das chaves do perfil personalizado estava desalinhada entre o painel
  e o script**, o que fazia o valor de uma chave ser aplicado em outra. As três
  pontas foram realinhadas e há teste cobrindo a ordem.

## [2.42.1] - 2026-10-22

### Corrigido
- **Painel flutuante minimizado agora arrasta.** O ícone minimizado ficava preso
  no lugar: o clique para reabrir estava no `ImageView` de dentro da bolha, que
  virava "clickable" e engolia o toque antes de chegar ao container — onde vive o
  arrasto. O clique passou para o container, então dá para mover a bolha pela
  tela e um toque curto continua devolvendo o painel completo.
- **Fim dos cards repetidos no rodapé do painel.** Os cards de permissão
  (`Permitir o app do pack`, `Permitir os Free Fire`, `Permitir o meu jogo`,
  `Bateria sem economia agressiva`, `Aplicar todas as permissões` e
  `Aparência e som`) apareciam **duas vezes**: uma na aba Sistema, como deviam, e
  outra solta no fim do painel, fora de qualquer aba, empilhada junto com os
  créditos. Era um fragmento órfão que ficou entre o fim da seção Sistema e a
  seção seguinte; como não pertencia a grupo nenhum, o CSS que esconde as abas
  inativas não o alcançava e ele aparecia sempre. O fragmento foi removido e o
  gerador do painel (`sync_app_panel.py`) agora limpa órfãos e avisa se as
  seções ficarem desbalanceadas.

## [2.42.0] - 2026-10-22

### Alterado
- **O app agora se chama Trix.** Nome de exibição, notificações e os títulos das
  telas (painel, login e painel de administração) passam a usar **Trix** — antes
  "00 Otimização"/"00deUdia Otimizações". O `applicationId` continua
  `com.otm.pack`, então a instalação por cima da versão anterior funciona e os
  dados do aparelho são mantidos.
- **Logo nova.** O ícone do app passa a ser a logo enviada, em todas as
  densidades (mdpi a xxxhdpi, quadrado e redondo) e no ícone adaptativo do
  Android 8+ (foreground na área segura, fundo combinando com a arte e uma
  camada **monochrome** para o tema dinâmico — antes o "monochrome" reaproveitava
  o foreground e virava um bloco sólido no modo monocromático).
- **Cor padrão agora é prata.** O laranja deixa de ser a cor de destaque padrão e
  vira **prata** (`#C7CCD6`) no painel, no login, no tema do Android
  (`colorPrimary`) e no painel flutuante. O laranja **continua na paleta** — quem
  preferir troca em Aparência, e a escolha salva é respeitada (só o padrão muda).

## [2.41.2] - 2026-10-29

### Adicionado
- **Categoria Dispositivos: resolução de tela.** Aba nova no painel com os
  degraus de resolução de vários aparelhos (540p a 1440p) e resolução
  personalizada. Reduzir a resolução **lógica** é o ajuste que mais rende FPS em
  jogo pesado — a mesma GPU desenha menos pixels. A **resolução de fábrica é
  guardada antes do primeiro override**, então "Voltar à resolução de fábrica"
  devolve o valor certo do seu aparelho, mesmo depois de testar vários degraus.
  A validação recusa valores absurdos em vez de aceitar qualquer coisa. O
  "automático" só desce para 1080p em tela QHD; em tela pequena não mexe.
- **Otimizador: medir antes x depois.** O otimizador inteligente agora **mede** o
  aparelho antes e depois de aplicar e diz se **melhorou, piorou ou ficou
  estável** — em vez de só aplicar e confiar. Se piorar, avisa para reverter.
  Ações novas: **analisar** (relatório completo, sem alterar nada), **ver o
  plano** (o que seria aplicado e o motivo de cada escolha), **medir antes x
  depois** e **comparar combinações** (testa Vulkan x GL e a maior taxa x 90Hz
  no seu aparelho e fica com a de melhor nota).
- **Análise mais profunda do aparelho.** O relatório agora lê também a frequência
  por **cluster de CPU**, a **pressão de memória** do kernel, a **resolução
  lógica**, o **zram em uso**, o **MGLRU**, a **entropia** e o **I/O** — e mostra
  o que está **segurando** a nota.
- **Guia com os comandos de resolução.** A área de comandos do site ganhou a
  categoria **Resolução** (`wm size`): ver a atual, baixar para 1080p/720p e
  voltar à de fábrica, para quem prefere digitar o comando em vez de usar o
  painel.

### Mudado
- **Otimizador mais rigoroso nas escolhas.** A memória do kernel (swappiness)
  passou a acompanhar a RAM do aparelho e a limpeza muda de fase conforme a
  classe. Nada é chutado: o que o aparelho não expõe entra como "desconhecido" e
  a comparação só considera o que foi realmente lido.
- **A resolução também está no painel flutuante**, na aba **Motor** — é um
  ajuste para mexer no meio da partida, não só antes de abrir o jogo.

### Corrigido
- **O botão "Esconder topo" do flutuante não escondia a barra.** Ele chamava
  `sysbars status`, que é só leitura (mostra o estado), em vez de `so_status`,
  que aplica o modo imersivo na barra de cima. O botão parecia não fazer nada.

## [2.41.1] - 2026-10-29

### Corrigido
- **O painel flutuante abria a aba errada.** A lista de rótulos (`TABS`) e o
  `when` que escolhe o conteúdo estavam em ordens diferentes: a aba **Monitor**
  abria os perfis de **toque** e o **FPS real** ficava escondido dentro de
  **Processos**. Era o motivo de parecer que o FPS "não existia". Agora o
  índice de cada rótulo casa com o seu conteúdo — e o FPS abre na primeira aba.
- **O painel mudava de largura ao trocar de aba.** A janela era `WRAP_CONTENT`,
  então cada aba media um tamanho diferente e o painel "pulava" na tela. Agora a
  largura é **fixa** (~46% da tela, com piso/teto em dp) e a altura acompanha o
  conteúdo até um teto de ~50% — aba curta fica baixa, aba longa rola.

### Mudado
- **A bolha de minimizado tinha tamanho irregular.** O ícone do app é um
  *adaptive icon*, que usado direto num `ImageView` não tem tamanho confiável e
  saía enorme. Agora a bolha é um quadrado fixo de 46 dp, igual em qualquer
  aparelho e densidade.
- **Painel mais compacto e organizado**: botões e chips menores, as 5 abas em
  duas linhas (os rótulos não cabiam legíveis numa linha só) e espaçamento
  reduzido.
- **Aba Monitor com mais informação**: além de FPS, teto da tela, RAM, CPU,
  frequência, temperatura e bateria, agora mostra **núcleos**, **governador**,
  **saúde/ciclos da bateria** e **armazenamento**. O que o aparelho não expõe
  continua virando "—".

## [2.41.0] - 2026-10-29

### Corrigido
- **O `panel-stats.sh` quebrava o JSON quando o jogo escolhido não tinha
  pacote.** A leitura do jogo usava `tr -d '\n' < "$ST/game/pkg"`, mas o
  redirecionamento de entrada **não** cobria o caso do arquivo não existir: o
  erro ia para o stderr e a variável saía vazia no meio do JSON, derrubando o
  parse das métricas (CPU fora de 0..100 e JSON inválido). Agora a leitura é
  guardada por `[ -f "$ST/game/pkg" ]` e o valor sai limpo.
- **Os créditos ficavam no meio da tela quando a aba tinha pouco conteúdo.** Em
  telas curtas (a aba **Flutuante**, por exemplo) o conteúdo acabava e o rodapé
  com os créditos parava logo abaixo dele, no meio do vazio. A causa era o
  `body` não ser coluna flexível: o miolo não crescia para empurrar o rodapé
  para baixo. Agora o `body` é `display:flex; flex-direction:column` e o miolo
  usa `flex:1 0 auto` — o rodapé fica sempre no fim da tela. Corrigido no painel
  do app, no `web/index.php`, no `web/login.php`, na página do guia
  (`index.html`) e na cópia publicada (`public/guia.html`). O teste
  `t_footer_sticky` guarda a correção.
- **O app pedia a permissão do Shizuku a cada vez que era aberto, mesmo já
  autorizado.** O binder do Shizuku (a ponte com o serviço de shell) **chega
  depois** do `onCreate`: o app pergunta ao `ShizukuProvider` e a resposta volta
  por Binder. A checagem de permissão acontecia só no `onCreate`, quando a
  resposta ainda não tinha chegado — então o app concluía "não autorizado",
  mostrava a capa e pedia a permissão de novo, toda vez. Agora a conexão também
  é tentada **quando o binder chega** (`addBinderReceivedListenerSticky`), é
  refeita quando o usuário **volta para a tela** (`onResume`) e o runner é
  limpo quando o serviço do Shizuku reinicia (`addBinderDeadListener`). Se a
  permissão já foi concedida, o app conecta em silêncio e vai direto ao painel.
  O indicador de acesso do painel também é reconsultado quando a tela volta,
  para não continuar dizendo "sem acesso" depois de conectar.

### Removido
- **Saíram das Configurações os botões de permissão que não faziam sentido ali.**
  A engrenagem tinha "Aos Free Fire", "Ao meu jogo", "Bateria sem economia" e
  "Acesso a dados de uso" ao lado do botão do pack. Ficou **só o "Conceder
  permissões ao pack"**, que é o que o usuário precisa mexer. As ações em si
  continuam no catálogo (quem quiser chamar por elas ainda consegue), e o
  atalho "Liberar acesso a dados de uso" continua na Home, onde o dado aparece.

### Adicionado
- **FPS real do jogo, medido no compositor (aba "Monitor" do flutuante).** O
  flutuante ganhou uma aba **Monitor** que mostra FPS, RAM, CPU e bateria ao
  vivo, atualizando sozinha a cada 4 s enquanto está aberta. O FPS **não** é a
  taxa da tela disfarçada: sai dos carimbos de apresentação dos frames do
  `SurfaceFlinger` (`fps.sh`, `otm_fps_measure`), que é o número de frames que
  realmente apareceram. Quando o jogo não está na tela — ou a camada não expõe
  frames — o painel mostra **"—"** em vez de inventar um número. O mesmo valor
  aparece na Home do painel (app e web), no card **"FPS do jogo"**.
- **Reduzir a resolução do jogo pelo flutuante (mais FPS).** A aba **Atalhos**
  agora traz os três perfis de downscale do `game-per-app.sh` — **FPS (0.9)**,
  **Equilíbrio (0.75)** e **Máx (0.5)** — mais **Reset resolução** e **Ver
  tuning**. Renderizar menos pixels dá mais FPS e esquenta menos; o tamanho na
  tela não muda. O flutuante usa `auto`: o script resolve o jogo escolhido no
  pack (ou o app em primeiro plano), porque o overlay não tem como saber qual é
  o jogo. Vale para `apply`, `custom`, `mode`, `show` e `reset`.
- **Escolher QUALQUER app instalado para nunca ser encerrado.** A aba
  **Processos** ganhou a lista **"Todos os apps"** (`proc-mgr.sh apps`): mostra
  todos os apps de usuário instalados, não só os que estão rodando agora, e cada
  linha é um chip que liga/desliga a exceção com um toque. Antes só dava para
  proteger quem já estava vivo neste instante — o caso mais comum (proteger um
  app que ainda vai abrir, como o do banco) ficava de fora.
- **Gerenciador de processos no painel flutuante (aba "Processos").** O
  flutuante ganhou uma aba para mexer na memória **no meio da partida**,
  sem fechar o jogo: escolher quantos apps o sistema mantém em segundo plano
  (4 · jogo, 8 · meio, 32 · multitarefa ou Padrão), **"Encerrar todos"** (fecha o
  segundo plano poupando o jogo, o app em primeiro plano e as suas exceções),
  **"RAM agora"**, criar a exceção do **app em 1º plano** com um toque e ver a
  lista de **apps rodando agora** com a RAM de cada um. Em cada linha da lista há
  um chip **"exceção"/"não encerra"**: um toque marca/desmarca aquele app como
  "nunca encerrar" (útil para uma live que fecha quando você encerra tudo).
- **Exceções ("X app não encerra") valem para todas as limpezas.** A lista de
  exceções do gerenciador de processos entra no `otm_keep_list`, então o
  "Encerrar todos" do flutuante, o Clean, o RAM Boost e o Game Clean poupam os
  mesmos apps. Também estão no painel principal (grupo Processos): "Apps rodando
  agora", "Encerrar todos em 2º plano", "Exceção: app não encerrar", "Exceção:
  app em 1º plano", "Exceções (não encerrar)", "Exceção: remover" e "Exceções:
  apagar todas".
- **Aparência só-escura, com cor de destaque personalizada e fontes novas.** O
  app passou a ter uma identidade escura única: **não existe mais tema claro nem
  alternância** (o `<meta color-scheme>` é só `dark` e as cores escuras ficam
  direto no `:root`). Além das paletas prontas, dá para escolher **qualquer cor**
  (seletor do sistema + campo hex) — a cor do texto sobre o destaque e o anel de
  foco são calculados pelo brilho do hex.
- **Fontes empacotadas no app (9 famílias).** As fontes de destaque (Anton,
  Bebas Neue, Caveat, JetBrains Mono, Monocraft, Orbitron, Playfair Display,
  Press Start 2P e Russo One) vêm **dentro do app**, não de CDN: a fonte continua
  valendo **sem internet**. Todas são OFL-1.1 e o crédito acompanha o arquivo
  (`assets/fonts/CREDITS.md`).
- **O painel flutuante agora tem o mesmo visual do app.** Antes era um retângulo
  laranja chapado e igual para tudo. Agora ele usa a **mesma cor de destaque e a
  mesma fonte** escolhidas no painel (troca na hora, sem reabrir), os botões
  viraram pílulas de vidro e a janela pede *blur* por trás no Android 12+ (onde
  não há suporte, o fundo translúcido mantém o aspecto). A aba **Sensi** saiu do
  flutuante: ficam **Toque**, **Motor** e **Atalhos** (o headshot continua no
  botão de Atalhos, mas o overlay não lê mais o `sensi.sh`).
- **O log agora diz POR QUE algo falhou.** Cada execução guarda quantas
  tentativas pegaram, quantas falharam, as **razões** (as linhas do script que
  explicam a falha, com o valor lido de volta — ex.: "nao mudou (lido: cubic)")
  e a **saída crua**. Antes o log só dizia "erro", sem dizer o que não pegou nem
  com que valor o aparelho ficou. Como a saída crua entra no log, o arquivo é
  podado (últimas 800 execuções).
- **A aba "Flutuante" no painel, com um botão só: ligar o painel sobre o jogo.**
  A antiga categoria "Sensi e mira" virou **"Flutuante"** e ficou com um único
  cartão — ativar/desativar o overlay. As ações de **sensi** (gerar, analisar,
  perfis headshot/spray/sniper/speed e os valores na ordem do Free Fire) foram
  para **"Display & Touch"**, que é onde o resto dos ajustes de mira e toque já
  morava. Nada foi removido: só ficou no lugar certo.
- **O painel flutuante agora é organizado por categorias (abas).** Antes tudo
  saía numa lista corrida e, no meio da partida, achar um botão era lento. Agora
  cada aba mostra só o seu bloco — **Toque**, **Motor** e **Atalhos**. O visual
  ganhou fundo arredondado e as abas viram "chips" (a ativa fica destacada).
- **Escolha do motor de renderização dentro do painel flutuante.** A aba
  **Motor** traz Automático, SkiaGL, Skia Vulkan e as variantes multithread
  (SkiaGL MT / SkiaVK MT), chamando o mesmo `adb-tweaks.sh renderer` do painel
  principal — dá para trocar o renderizador sem fechar o jogo.
- **A limpeza inteligente agora poupa quem está na sua frente.** As limpezas
  (Clean, Liberar RAM e Game Clean) passaram a **nunca encerrar** o app em
  **primeiro plano** (o que está na tela), o **jogo escolhido** no Modo
  Competitivo, o **próprio app do pack** (que sustenta o painel flutuante) nem
  os apps protegidos no **anti-relog**. Antes, uma limpeza podia fechar o jogo
  ou o overlay no meio do uso.

### Corrigido
- **Trocar a aparência não movia o painel flutuante para o canto.** Ao recriar a
  janela com a cor/fonte novas, o overlay posicionava a janela **antes** de
  aplicá-la ao sistema, então o WindowManager ignorava a posição e o painel
  voltava para o canto. Agora a posição é copiada antes de recriar a janela, e o
  flutuante fica onde o usuário deixou.
- **O `sync_app_panel.py` não removia seções de grupo que sumiram do web.** Ao
  renomear um grupo (ex.: "Sensi e mira" → "Flutuante"), a seção antiga ficava
  órfã no painel do app, com o conteúdo velho e um item de menu morto. Agora o
  script apaga as seções do app que não existem mais no web (poupando as
  seções exclusivas do app, como Terminal e Vitalidade) e o link do menu junto.
- **A barra de navegação (a dos gestos: quadrado, bolinha, voltar) ficava
  diferente depois de aplicar o pack.** O grupo `window_tweaks` gravava
  `policy_control immersive.full=*`, que esconde as barras de cima e de baixo.
  Duas falhas se somavam: (1) a reversão só reconhecia o valor que a ação tinha
  escrito na **primeira** vez, então trocar de "imersivo" para "só a barra de
  baixo" deixava o guard preso no valor velho e o "Reverter TUDO" não devolvia
  nada — a barra ficava escondida de forma permanente; (2) não havia nenhuma
  forma de ver ou controlar isso no painel. Agora existe o grupo **"Barras do
  sistema"** (`adb-tweaks.sh sysbars`) com visíveis / esconder as duas / só a de
  cima / só a de baixo, além dos ícones da barra de cima e do percentual de
  bateria. O painel lê o estado **real** do aparelho (`panel-state.sh`) e marca
  qual opção está em uso. A reversão agora reposiciona o guard a cada escrita
  (`otm_undo_retarget` em `common.sh`), então o "Reverter TUDO" devolve as
  barras mesmo depois de trocar de modo várias vezes.
- **O "Limite de processos em segundo plano" finalmente pega no aparelho.** O pack
  gravava `max_cached_processes` no setting `activity_manager_constants`, mas no
  Android 10+ a plataforma lê esse valor de `device_config activity_manager
  max_cached_processes` (e o Dev Options usa um override interno do
  ActivityManager). Resultado: o aparelho continuava em "Padrão" mesmo depois do
  pack. Agora o valor é escrito **onde o Android lê de verdade** (o setting é
  mantido em sincronia para Androids antigos) e é **conferido lendo de volta** —
  se não pegar, aparece como falha em vez de "aplicado". Vale para o pack
  recomendado, o perfil de RAM, o Game Clean e o anti-relog do jogo.
- **A latência/ping entrou no pack recomendado.** Antes o `all` ajustava DNS e
  Wi-Fi, mas não mexia no que mais pesa no ping: congestion control e buffers
  TCP.
- **O "Reverter TUDO" não devolvia o desfoque do teclado e da barra.** As ações
  de desempenho (`perf`, `gpu`, `fluidez`, `clean`, otimizador inteligente e o
  pack recomendado) desligam `disable_window_blurs` e
  `accessibility_reduce_transparency`, mas o `fluidez` gravava os dois com
  `sh_run` em vez de `bkp_set` — fora do arquivo de reversão. Resultado: a
  interface ficava "seca" e o teclado/barra perdiam o desfoque **para sempre**,
  mesmo depois de reverter. Agora os dois entram na reversão.
- **O modo imersivo saiu do `window_tweaks` (e com ele o "esticado" do conteúdo).**
  O grupo de janelas/transições gravava `policy_control immersive.full=*` junto com
  as animações. Isso escondia as barras e fazia o conteúdo do app descer até debaixo
  da barra de gestos — a barra de pesquisa do YouTube, por exemplo, ficava atrás
  dela e não dava para tocar. Quem quiser esconder as barras usa o grupo explícito
  **"Barras do sistema"** (`sysbars`), que é reversível.
- **O motor gráfico dizia "aplicado" mesmo quando o sistema ignorava.** O pack
  aceitava `renderer opengl` e mostrava "renderizador: opengl" só porque o prop
  tinha ficado com esse texto. No Android o `debug.hwui.renderer` só entende
  **dois** valores — `skiagl` e `skiavk`; qualquer outro cai no SkiaGL em
  silêncio, e o pipeline OpenGL foi **removido no Android 10** (API 29). Agora:
  `renderer opengl` é **recusado** com aviso em API ≥ 29; a confirmação lê o prop
  e informa o que o sistema **vai usar de verdade**; e o novo modo **"Automático"**
  apaga o prop para devolver a decisão ao sistema (skiavk se o aparelho usa Vulkan,
  senão skiagl). O painel ganhou a opção "Automático (padrão)" e os textos deixaram
  de afirmar que "opengl é o padrão".
- **O pack recomendado religava o congelador que o anti-relog tinha desligado.** O
  `all` rodava `game` (que desliga o `cached_apps_freezer` para o jogo não ser
  congelado) **antes** de `freezer` (que o ligava de novo). Resultado: o jogo
  voltava a fechar sozinho e pedir login no meio da partida. A ordem agora é
  `freezer` antes de `game`.
- **O anti-relog só valia para quem já tinha escolhido um jogo.** Sem jogo salvo,
  o `game` não aplicava proteção nenhuma e o jogo relogava do mesmo jeito. Agora,
  sem escolha, ele protege o **Free Fire** por padrão.

### Adicionado
- **Renderizador "Automático" e controle separado do compositor.** O grupo
  `renderer` ganhou o modo `auto` (apaga `debug.hwui.renderer` e deixa o sistema
  escolher) e um comando próprio, `renderer_backend`, para o backend do
  compositor do SurfaceFlinger (`debug.renderengine.backend`). Este último é lido
  **uma vez no boot**, então o pack avisa que só vale depois de **reiniciar** —
  antes ele era escrito junto com o renderer e prometia efeito imediato.
- **Painel flutuante sobre o jogo (overlay).** Uma janela arrastável que fica por
  cima do Free Fire/CODM/etc., sem precisar fechar a partida: mostra a sensi
  calculada para o seu aparelho (Geral, Ponto vermelho, mira 2x, 4x, AWM e o
  tamanho do botão de atirar), os cinco perfis de toque (Equilibrado, Headshot,
  Spray, Sniper, Speed) e atalhos de latência e limpeza de RAM. Abre pelo card
  "Painel flutuante sobre o jogo" (Sensi e mira) ou pelo botão "Flutuante" no
  cabeçalho; toque de novo para desligar. Na primeira vez o Android pede a
  permissão "aparecer por cima de outros apps". É um serviço em primeiro plano
  (`TYPE_APPLICATION_OVERLAY`), usa o mesmo executor de scripts do painel
  (`OtmExec`) e não pede permissão sozinho: aproveita a conexão já feita no app.
- **O painel flutuante ficou legível: seções e minimizar para o ícone.** O painel
  se chama só **"00"** e os botões agora ficam em **seções com cabeçalho** (Sensi
  do seu aparelho, Perfil de toque, Atalhos) em vez de uma lista única — no meio
  da partida dava para se perder. Ao minimizar, o painel inteiro some e sobra
  **só o ícone do app**, que continua arrastável; um toque no ícone devolve o
  painel completo, no mesmo lugar da tela.
- **Categoria "Barras do sistema"** (Display & Touch): mostra/esconde as barras de
  cima e de baixo, esconde só uma delas, limpa os ícones secundários da barra de
  cima e liga o percentual de bateria. Cada bloco é um **card de ligar/desligar**
  (ícones: só o essencial / mostrar todos; bateria: número % / só o ícone), não
  botões soltos, e o painel marca a opção em uso lendo o estado real do aparelho.
- **Driver gráfico do sistema** (Display & Touch, por app e global):
  `deep-tune.sh gfxdriver` com `angle_all` (ANGLE em todos os apps),
  `gamedriver` (driver de jogo do fabricante) e `updatable` (driver atualizável:
  produção / pré-lançamento / só no jogo escolhido). Tudo sem root, com leitura
  de confirmação e reversão que não empilha.
- **Card "Desfoque e transparência (efeitos visuais)"** (categoria Display &
  Touch): liga/desliga o desfoque (blur) do teclado, da barra de navegação e das
  notificações e a transparência do sistema, a qualquer momento. O painel lê o
  estado real do aparelho e marca o que está em uso. Antes não havia como
  devolver o visual sem editar settings na mão. Grupo novo no script:
  `adb-tweaks.sh effects <on|off|status>`.
- **Categoria "Latência e ping"** com "Reduzir latência / ping" e "Latência:
  restaurar": liga BBR (quando o kernel tem), encurta buffers, ativa low latency
  e ECN — cada chave é lida de volta e só conta como aplicada se realmente mudou
  (kernel sem a chave aparece como falha, não como sucesso).
- **Limite de processos em segundo plano no painel** (categoria Processos):
  ver o valor real, 4 (jogo), 8 (equilíbrio), 32 (multitarefa) e padrão. O
  `panel-state.sh` passou a expor `proc_limit` para o painel mostrar o número
  lido do aparelho.
- **Categoria "Sensi e mira": gerador de sensi do Free Fire sob medida.** Lê o
  aparelho (resolução, DPI, polegadas, taxa de toque, Hz, SoC, RAM e o ajuste de
  toque já aplicado) e calcula Geral, Ponto vermelho, 2x, 4x, AWM e o tamanho do
  botão de atirar (com teto de 50%, para não ficar grande). Perfis headshot,
  spray, sniper e speed. **Não altera nada no aparelho** — só mostra os números.
  Tem "ver o que foi lido" para o cálculo ficar transparente.
- **Pack recomendado mais completo:** agora aplica, em ordem, performance, RAM,
  GPU, rede, **latência/ping**, Wi-Fi, jogo, freezer, DND, tela, fluidez, tuning
  do jogo e, no fim, o limite de 4 processos em segundo plano e a limpeza suave.

### Corrigido
- **Pareamento ADB por Wi-Fi (só o código) voltou a funcionar.** Três causas
  foram tratadas de uma vez:
  - **Chave e certificado desencontrados:** o certificado autoassinado podia ser
    gerado de um par de chaves diferente do que assinava o TLS, e o handshake
    morria com `SignatureException` (`SelfSignedCert`/`AdbRunner`). Agora o
    certificado é sempre derivado da **mesma** chave privada lida do disco, e um
    `.pem` de par antigo é descartado ao detectar a incompatibilidade.
  - **APIs ocultas do Conscrypt:** o TLS 1.3 do pareamento usa
    `exportKeyingMaterial`; sem liberar as APIs ocultas o pareamento falha no
    Android 10+. Entrou o `OtmApp` (Application) com `HiddenApiBypass` +
    `PRNGFixes`, como no app de exemplo da própria libadb.
  - **Descoberta mDNS:** a busca pelo serviço de pareamento agora pede a
    permissão certa (13+: "Dispositivos próximos"; ≤12: localização), roda na
    thread principal (o `NsdManager` entrega eventos no Looper) e tem um plano B
    de consulta multicast própria, com o multicast segurado
    (`MulticastLock`). Antes a descoberta falhava em silêncio.

### Alterado
- **Sistema de chaves/licença removido.** O acesso voltou a ser **usuário e senha**,
  no app e no painel. Saíram do projeto o `KeyGate`/`License` do app, o `KeyService`/
  `KeyVault`/`License` do painel, o cofre, a licença offline assinada (Ed25519), a
  geração/sincronização de chaves (`keys.json`) e os comandos `web key`/`web vault`.
  O painel `panel/` ficou com o essencial: administradores, auditoria e ajustes.
- **Otimizador inteligente decide também pelo estado atual do aparelho:** passa a
  ler a RAM realmente livre, o *throttling* térmico (`dumpsys thermalservice`) e a
  economia de energia ligada. Com o aparelho apertado, segura mais o segundo plano
  e limpa mais fundo; já quente, aplica cautela e segura a taxa de tela.

### Removido
- **App:** `KeyGate.kt`, `License.kt`, `keys.json` e o campo de licença no
  `build.gradle.kts`. O painel volta a abrir na tela de login (`login.html`) e o
  `index.html` volta a ter guarda de sessão; o áudio `login_feito_com_sucesso.mp3`
  volta a tocar no login certo.
- **Painel (`panel/`):** `KeyService`, `KeyVault`, `License`, os CLIs `key.php`,
  `license.php`, `vault.php`, `buildprops.php`, as páginas de chave/plano/tentativa/
  exportação e as migrations do domínio de chaves. Sobraram `0001_admins.sql` e
  `0002_panel.sql` (ajustes e auditoria).
- **Painel web (`web/`):** `keys.php` e `access.php`; voltaram `auth.php` e `login.php`
  (login por usuário e senha, senha só como hash).
- **`main.sh`:** os comandos `web key ...`, `web vault`, `web adopt`, `web build` e
  `web props`.


## [2.26.1] - 2026-10-23

### Alterado
- **Acesso por chave no lugar de login e senha.** O painel web não pede mais usuário
  e senha: agora você cria uma chave (`sh main.sh web key new`) no formato
  `00-XXXX-XXXX-XXXX` e cola na tela de entrada. O servidor guarda só o **hash
  SHA-256** da chave em `~/.packotm/web/keys.json` (nunca em texto puro), com
  `sh main.sh web key list` e `sh main.sh web key revoke <id>` para gerenciar.
  A API também aceita a chave no cabeçalho `X-Otm-Key` (ou `?key=`).

### Removido
- Sistema de login e senha do painel web (`web/auth.php`, `web/login.php`) e a tela de
  login do app (`assets/panel/login.html`). O app abre o painel direto.
- Arquivo de token do servidor (`web/.token`) e o comando `sh main.sh web senha`.

## [2.25.0] - 2026-10-05

### Corrigido
- **ADB por Wi-Fi agora pede só o código de 6 números.** Antes o diálogo exigia
  endereço IP, porta de conexão, porta de pareamento e o código — confuso e
  desnecessário. Agora as portas são descobertas sozinhas pela rede (mDNS:
  `_adb-tls-pairing._tcp` e `_adb-tls-connect._tcp`), como nos apps que só pedem o
  código. Basta abrir *Depuração sem fio → Parear com código* e digitar o código.
- Os campos manuais (IP e portas) foram para um bloco **Avançado** opcional, para
  redes que bloqueiam mDNS ou para o ADB por TCP clássico.

### Adicionado
- Botão **Só conectar** no diálogo Wi-Fi: reaproveita a chave já pareada e dispensa
  digitar o código de novo.

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
