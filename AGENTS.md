# AGENTS.md — Pack de Otimização

Guia para agentes que trabalharem neste repositório.

## Autor

**00deUdia** (GitHub `whesleydev`) — Discord `cute_axolotl_51194`,
perfil <https://discord.com/users/cute_axolotl_51194>, servidor <https://discord.gg/w9hFBeVKw8>.
O painel web e o site trazem esses créditos num rodapé com botões para o perfil e o servidor.

## O que é

Pack de otimização para Android (foco Free Fire) em 4 níveis:
`.txt` (Brevent), scripts `sh` (Shizuku/root), plugin AxManager em loop e plugin com WebUI.

## Princípios do projeto

- **Conteúdo próprio apenas.** Não redistribuir módulos de terceiros. Os módulos em
  `00 Otimizações/Modulos/` (WS7_OFF7, NexaCore, Astrax, NOVA TOUCH, VOID TOUCH Ultra, VeuLexier) e os
  5 plugins em `00 Otimizações/Plugins AxManager/Nossos/` são do autor do pack (MIT).
  A única exceção são os plugins de licença permissiva em `.../Terceiros-open-source/`
  (Apache-2.0, com `LICENSE` e créditos preservados em `CREDITS.md`).
- **Honestidade técnica.** Nada de placebo; risco declarado em `docs/AUDITORIA.md`.
- **Tudo reversível.** Cada mudança guarda o valor antigo antes de aplicar.

## Estrutura (topo)

```
00 Otimizações/
  Comandos Brevent/     nível 1 — .txt p/ copiar e colar no Brevent
  Scripts SH/           nível 2 — entry point sh (Shizuku/root)
  Plugins AxManager/    níveis 3 e 4 — plugins de módulo
    Nossos/               01-service-loop, 02-webui-control, 03-battery-thermal,
                          04-cleaner, 05-fps-refresh, 06-freezer
    Terceiros-open-source/ Stellar-Tweaks, Kang, Sakoiire, Aapt-for-Plugin (+CREDITS)
  Modulos/              módulos Magisk/KernelSU/AxManager do pack
scripts/ tests/ docs/ releases/
Apps/                   guia dos apps p/ instalar (Brevent, Shizuku, Termux, AxManager)
pack.sh                 MENU-MESTRE (raiz): atalho p/ scripts/pack.sh
index.html              site único (HTML+CSS+JS puro): guia + área de comandos
```

`scripts/pack.sh` é o **menu-mestre**: ponto único de entrada que delega para todos os
outros scripts (`adb-tweaks`, `deep-tune`, `debloat`, `ff-touch`, `game-per-app`,
`dns`, `modules`, `snapshot`, `bench`, `device-profile`, builds). Roda como menu
interativo (sem args) ou por linha de comando (`status`, `apply`, `restore`,
`debloat on medio`, `touch headshot`, `dns gaming`, `modules run WS7_OFF7`…).
O `00 Otimizações/Scripts SH/run.sh` (nível 2) é só um atalho para ele.

- `scripts/dns.sh` — DNS privado (DoT) por perfis: privacidade, bloqueio de anúncios,
  família, latência/gaming, custom e off. Reversível.
- `scripts/modules.sh` — descobre e executa os módulos/plugins da pasta
  (`run`/`info`/`actions`/`action`); executa o script avulso, não substitui instalar
  no gerenciador (boot/serviço/WebUI).
- `scripts/deep-tune.sh` — otimizações profundas. Cada módulo tem `on`/`off` e registra a
  reversão com uma **tag própria** (reverter um não mexe nos outros). Além dos módulos
  clássicos (angle/freq/thermal/io/mem/net/latency/debloat/gaming), tem os **extremos**
  (vm/sched/gpu/cores/input/idle/net2/zram/kernel/display/dalvik/dexopt) e o atalho
  `gaming extreme` (turbo + todos os avançados). Ao criar um módulo novo: use `DEEP_TAG`,
  `deep_begin`, `sys_write`/`sysctl_write` (guardam o valor antigo) e `deep_restore <tag>`.
  Módulos que dependem de root chamam `require_root`.
- `scripts/adb-tweaks.sh` — grupos de comandos via `settings`/`cmd` (sem root). Além dos
  clássicos, tem `obscure`, `mobile_net`, `notif`, `game_focus`/`game_focus_off` (DND
  extremo), `touch_multi <ms>` (janela multitouch) e `window_tweaks`. Para criar um grupo,
  escreva a função, registre em `GRUPOS` e use `bkp_set`/`bkp_raw` para a reversão.
- `scripts/turbo.sh` — recursos "turbo" sem root que faltavam: `art`/`art-all` (ART por
  app, speed-profile/speed), `dexopt-bg` (bg-dexopt-job), `standby` (App Standby Buckets),
  `hibernate` (estilo Hail: force-stop + set-inactive), `killbg`, `phantom on|off`
  (Phantom Process Killer), `trim` (cmd package trim-caches), `refresh`,
  `refresh_fixed` (trava min=peak numa taxa), `audio on|off` (buffer de áudio baixo,
  root), `mem_compact on|off` (compacta RAM sem matar apps, root), `boot on|off`
  (reaplicador no boot via Magisk service.d/init.d, root), `perfmode`
  (modo desempenho fixo) e `telemetry on|off` (logpersist + scans sempre-disponível).
  Tudo registra reversão em `~/.packotm/off.sh` (revertido por `pack.sh restore`).
  A persistência no boot usa `boot_add`/`boot_install` (helpers em `common.sh`):
  os ajustes que se perdem no reboot chamam `boot_add` com a linha de reaplicação.
- `scripts/debloat.sh preview <perfil>` — mostra o que o perfil faria com selo de risco
  por app (SAFE/CAUTION/DANGEROUS), sem alterar nada. Classificação em `risk_of`.
- `scripts/dns.sh bench` — mede a latência de cada perfil de DNS (não altera nada).

`main.sh` (raiz) é a **entrada alternativa**: baixa os recursos full (`codeload` do
GitHub), sobe o **servidor web** (`php -S`) e abre o **painel PHP** (`web/`). Não aplica
otimizações — quem faz isso é o `pack.sh`.

O **painel web** (`web/lib.php` + `web/api.php` + `web/index.php`) — marca
**00deUdia Otimizações** — controla o pack pelo navegador. Regras ao mexer nele:
- `web/lib.php` guarda o **registro de ações** (id, grupo, argv, params, confirm, risco).
  Para expor uma ação nova, adicione ao registro — **não** invente execução de comando cru.
- `web/index.php` é **renderizado no servidor (PHP)**: o menu de categorias e os cards de
  ação saem prontos no HTML. O JS só troca de categoria, executa e mostra saída/modal.
  Mantenha o visual **clean**, a paleta própria e o CSS **responsivo** (gaveta no celular,
  tema claro/escuro) ao mexer.
- `web/index.php` e `web/api.php` **exigem login** (`web/auth.php`, sessão PHP). A credencial
  inicial fica em `OTM_DEFAULT_USER`/`OTM_DEFAULT_PASS` (`web/auth.php`); a senha é guardada com
  `password_hash` em `~/.packotm/web/auth.json` (nunca em texto puro, nunca versionada). Troque
  com `sh main.sh web senha`. O formulário de login usa **CSRF** (`otm_csrf`).
- `web/api.php` também aceita o **token** (`web/.token`, gerado no `main.sh web start`) como
  defesa em profundidade, e só roda scripts da lista branca `otm_allowed_scripts()`. Parâmetros
  são validados por tipo (pkg/host/int/float/enum). Nunca passe input do usuário direto para o shell.
- Ações com `confirm:true` exigem `confirm=1` no POST (o `index.php` mostra o modal).
- `web/.token`, `web/.state/` e `web/auth.json` são **locais** (no `.gitignore` e removidos do zip).

`index.html` é o site público (um só arquivo, sem dependências): explica os 4 níveis, os
apps, os plugins/módulos e tem uma **área de comandos** com busca e botão de copiar.
Publique no GitHub Pages apontando para a raiz (o `index.html` fica na raiz).

## Comandos

```sh
sh tests/run.sh                 # testes (stubs de settings/cmd/am/getprop/su) — deve dar 0 falhas
sh pack.sh                      # MENU-MESTRE (interativo); ou: sh pack.sh status|apply|restore
sh scripts/build-modules.sh     # empacota 00 Otimizações/Modulos/ em releases/*.zip
sh scripts/build-plugins.sh     # empacota Plugins AxManager/ (Nossos + OSS) em releases/*.zip
sh scripts/build-pack.sh        # gera o zip único "Pack 00" completo em releases/
sh scripts/debloat.sh on medio  # debloat (leve|medio|pesado); off reverte
sh scripts/dns.sh list          # perfis de DNS (privacidade/ads/família/gaming)
sh scripts/modules.sh list      # lista módulos/plugins da pasta; run <nome> executa
sh main.sh web start            # sobe o painel web (PHP) e mostra a URL (acesso com login)
sh main.sh baixar               # baixa os recursos full do pack
sh scripts/check-secrets.sh     # falha se achar credencial
shellcheck -S error $(find scripts "00 Otimizações/Scripts SH" "00 Otimizações/Plugins AxManager/Nossos" tests -name '*.sh')
sh scripts/bench.sh save antes  # benchmark antes/depois
sh scripts/device-profile.sh    # perfil do aparelho (SoC/GPU)
```

## Convenções

- Shell POSIX (`#!/system/bin/sh`); roda em Android, então evite bashisms.
- Transporte por `scripts/common.sh`: `OTM_MODE=adb|rish|su|local` (auto-detectado).
- Reversão das otimizações profundas em `~/.packotm/deep/off.sh` (formato `<tag>\t<comando>`).
- Estado local nunca versionado (`~/.packotm`, `00 Otimizações/Plugins AxManager/**/state/`, `releases/*.zip`).
- CI em `.github/workflows/build.yml`: sintaxe + shellcheck + testes + segredos; release
  por tag `v*` publica `SHA256SUMS.txt` e usa `CHANGELOG.md` como corpo.

## Pendências que dependem do dono

- **Push para `origin/main`**: o `GITHUB_TOKEN` do ambiente é uma credencial de
  integração (GitHub App) **somente leitura** — `git push` e a API de refs retornam
  `403 Resource not accessible by integration`. Para publicar, o dono precisa conceder
  `Contents: Read and write` ao app/token, ou rodar o push a partir da própria máquina.
  Enquanto isso, use o bundle/patch gerados em `releases/` (ver abaixo).
- Revogar o token exposto no histórico e purgar o `apps_otm.zip` (`docs/SEGURANCA.md`).
- Benchmark real em aparelhos e preencher `docs/COMPATIBILIDADE.md`.
- Infra de venda/suporte (`docs/PRODUTO.md`, `docs/ROADMAP.md`).

## App Android (`android/`)

App companion (Kotlin, `com.otm.pack`) que roda o pack pelo Shizuku (root/ADB)
ou por ADB Wi-Fi (pareamento), com os assets do pack embutidos.

O app é o painel web (00deUdia Otimizações) dentro de uma WebView: nada de UI
nativa além do necessário para conectar e rodar os comandos.

- `PanelActivity` é o launcher: carrega `assets/panel/login.html` (tela de
  entrada) numa WebView e injeta "Conectar"/"Som" no cabeçalho do painel.
- Login do app: `assets/panel/login.html` confere `SHA-256("usuario:senha")`
  contra o hash embutido e guarda a sessão em `localStorage` (`otm_session`).
  O `index.html` tem uma guarda no `<head>` que manda de volta ao login quando
  não há sessão; o botão "Sair" limpa a sessão. Credencial: `00deUdia`/`159951`
  (hash gerado com `scratch/build_panel.py`, constante `OTM_AUTH_HASH`).
- Menu lateral do painel: `.side .panel` é `position:fixed` (trava na viewport,
  sem "escorregar" ao rolar); no mobile (`<=960px`) vira gaveta `position:static`
  dentro do `.side` fixo.
- `PackBridge` é a ponte `JavascriptInterface` (`OTM.call(kind, payload, cbId)`):
  o painel chama por JS em vez de `api.php`. A execução é assíncrona (corrotina)
  e devolve o resultado por `window.__otmResolve`. Monta a ação igual ao
  `otm_run` do `web/lib.php` (valida parâmetros, troca `{nome}`, roda
  `sh <script> <args>` com `HOME` na pasta de execução).
- Onde os scripts rodam: o Shizuku/ADB executa como usuário `shell` (uid 2000),
  que **não** lê `/data/user/0/com.otm.pack` (modo 0700). Por isso
  `PackAssets.ensureShellCopy` copia `assets/pack/scripts` + `VERSION` para
  `/data/local/tmp/otm-pack` (visível ao shell) e o `HOME` aponta para lá — o
  estado (`~/.packotm`) fica no mesmo lugar. A cópia local em `filesDir/pack`
  serve só para o app ler os `.txt` do nível 1. `PackAssets.EXEC_DIR` guarda o
  caminho.
- O catálogo do painel vem de `assets/panel/actions.json`, gerado de
  `web/lib.php` por `scratch/gen_actions.php` (regera após mexer nas ações).
  O painel do app é o HTML do PHP já renderizado (`scratch/render_panel.php` →
  `scratch/panel.html` → `scratch/build_panel.py`); ao mexer em
  `index.php`/`lib.php`, os dois painéis (`web/index.php` e
  `assets/panel/index.html`) precisam ficar em sincronia (o CSS/JS é o mesmo).
- **Opções lado a lado** (`otm_choices()` em `lib.php`): ações com `'choice' =>
  'renderer'` (renderizador), `'renderapp'` (driver gráfico por app), `'refresh'`
  (taxa de atualização), `'dns_fast'` (DNS rápido) ou `'touchprofile'` (perfis de
  toque) são fundidas num único cartão com botões; cada ação traz `option` (rótulo)
  e `state_value`/`state_backend_value`/`state_match` para o painel marcar a opção
  **em uso**. Ali o botão diz **"Selecionar"** (não "Executar"), porque é escolha
  de configuração. Um grupo com `'app' => true` mostra um **seletor de apps**
  (`type => 'pkg'`, o helper `otm_pkg_picker()`) antes dos botões; o `selectOption`
  do JS envia esses `data-p` como `params` da ação (ex.: `app.render` =
  `deep-tune.sh angle set <pkg> <driver>`). Os modos "multithread" compartilham o
  `hwui.renderer` e desempatam pelo backend (`state_backend`/`state_backend_value`).
  A escolha `refresh` casa pela chave `refresh_peak` de `panel-state.sh`.
- **Seletor de apps (nome + ícone), sem digitar pacote.** O input de `type => 'pkg'`
  virou um botão `.apppick` (`otm_pkg_picker()`), que abre o modal `#appModal` com
  a lista de apps instalados mostrando **nome e ícone** e busca por nome/pacote. No
  app, a ponte `apps_meta` (`appsMetaImpl()` no `PackBridge`) lê os apps com o
  `PackageManager` e devolve `{pkg,label,icon}` (ícone PNG em base64) — é o que
  permite mostrar o ícone sem digitar nada. No site (PC) o `otm_apps_meta()` usa
  `aapt` quando existe e devolve só o pacote quando não. O pacote escolhido vai num
  `input` escondido `data-p="pkg"`, lido pelo `collect()`/`collectChoice()` como
  qualquer outro parâmetro.
- **Terminal de verdade.** Nova aba **Terminal** (seção `#g-Terminal` + item no
  menu, renderizada no PHP) que executa o comando digitado pelo mesmo acesso do
  pack. No site, `api.php?do=term` → `otm_run_command()` (`sh -c`); no app, a
  ponte `term` (`termImpl()`) roda no shell privilegiado. Cada execução entra no
  log (`id => 'terminal'`), então aparece em **Logs**. Histórico local em
  `state/term.jsonl` (app) para as setas ↑/↓.
- **Logs completos.** O antigo botão "Console" virou **Logs** (`#btnLogs`), que
  abre o painel `#logspanel` e busca `log_all` (histórico **completo**, sem
  truncar) em vez de `log` (últimas 40). No app, `logAllImpl()`; no site,
  `otm_log_all()`. O botão "Histórico" foi unificado em Logs.
- **Taxa de atualização (Hz).** Cartão de escolha com 60/90/120/Automático
  (`refresh.60`/`refresh.90`/`refresh.120`/`refresh.auto` → `turbo.sh refresh_fixed
  <hz>` / `turbo.sh refresh auto`). A home mostra **"Taxa de tela"**: a taxa travada
  (`refresh_peak`) quando existe, senão a atual (`refresh_hz`) — antes mostrava a
  maior taxa suportada e parecia errado para quem usa 60Hz.
- **Estado real do aparelho** (`scripts/panel-state.sh`, na whitelist do
  `lib.php`): devolve uma linha JSON com renderizador em uso (e o backend
  `renderengine_backend`), toque atual, refresh (`refresh_hz`/`refresh_peak`),
  ANGLE e o host de DNS privado (`dns_host`). O painel consome via
  `api.php?action=state` (web) ou `OTM.call("state")` (app, `stateImpl()` no
  `PackBridge`). Nada fictício: campo ilegível volta `""` e a UI não mostra número
  inventado. Parâmetros com `'state' => '<chave>'` abrem o slider já no valor do
  aparelho.
- **Home com métricas reais** (`scripts/panel-stats.sh`, na whitelist do
  `lib.php`): lê RAM (`/proc/meminfo`), carga/núcleos/frequência de CPU, bateria
  (`dumpsys battery`), refresh, armazenamento (`df`) e uptime, devolvendo uma linha
  JSON. O painel consome via `api.php?action=stats` (web) ou `OTM.call("stats")`
  (app, `statsImpl()` no `PackBridge`) e faz *polling* a cada 4 s enquanto a Home
  está visível (`startStats`/`stopStats`). Só leitura; campo indisponível fica `""`
  e a UI mostra **—**. A Home é a seção `#Home` e é a primeira do menu.
- **Gerenciador de processos** (`scripts/proc-mgr.sh`, na whitelist do `lib.php`):
  `top [n]` (mais CPU/RAM via `/proc`), `info <pkg>`, `ram <pkg> <mb>`,
  `cpu <pkg> <grupo>`, `renice <pkg> <nice>`, `freeze`/`unfreeze`,
  `status`/`restore`. Sem root avisa e não aplica; a categoria **Processos**
  agrupa essas ações.
- **Anti-relog** (`scripts/keep-alive.sh`, na whitelist do `lib.php`): impede o
  app/jogo de "relogar" (abrir do zero e pedir login) ao ser morto em segundo
  plano. `on <pkg> [jogo]` isenta do Doze, libera `RUN_IN_BACKGROUND`/
  `RUN_ANY_IN_BACKGROUND`/`START_FOREGROUND`/`WAKE_LOCK`, põe no balde `active`,
  tira do congelador/cache freezer e (com root) baixa o `oom_score_adj`; `off
  <pkg>` desfaz; `status <pkg>` lê tudo de volta; `list` e `restore` gerenciam a
  lista guardada em `$ST/keepalive/apps`. Usa `ka_run`/`bkp_raw` (reversível) e
  `require_shell` (sem Shizuku/ADB/root avisa e não aplica). Categoria **Processos**.
- Configurações do painel (engrenagem): permissões, tema, cor de destaque, fonte,
  DPI e som ficam em `localStorage` (`otm-theme`/`otm-accent`/`otm-font`/
  `otm-scale`/`otm-sound`) e são aplicados antes do resto do JS (`initAppearance`).
  A ação de registro `appearance` (`"ui" => "appearance"` em `lib.php`) abre o
  modal; por não ter `argv`, `PackBridge` a ignora (o painel trata a UI). O som
  "login feito com sucesso" toca só quando a tela de login valida usuário/senha:
  o `login.html` chama `OTM.call("login")` e o `PackBridge` repassa para
  `onLogin`. Ligar o som usa `ativando.mp3`. O DPI é
  um `zoom` no `<html>` com `width: calc(100% / escala)` **só acima de 100%** e
  `html{overflow-x:clip}` para não reintroduzir o arrasto lateral (medido com
  Playwright/Chromium em 320/360/412/480px).
  A faixa do DPI é **60%–160%** (`setScale` min/max, clamp `0.6x..1.6x` em
  `setScaleQuiet`); o mínimo baixo é o que permite deixar a interface bem compacta.
  A compensação de largura (`width: 100%/escala`) só vale quando o zoom **aumenta**
  (`z > 1`); abaixo de 100% a largura fica em `100%`. Compensar abaixo de 100%
  deixava o conteúdo mais largo que a tela e reintroduzia o arrasto lateral — o
  teste `t_personalization` cobra a forma condicional (`z > 1 ? "calc(100% / ...`).
- Acesso a dados de uso: o app declara `PACKAGE_USAGE_STATS` e pede, uma vez por
  versão, a autorização do sistema (`Usage.openSettings`). `Usage.kt` lê pela API
  do Android (`UsageStatsManager`: `queryEvents` p/ primeiro plano,
  `queryAndAggregateUsageStats` p/ tempo de tela) e `PackBridge.statsImpl` funde
  isso no JSON de `panel-stats.sh` (`fg_label`, `fg_pkg`, `top_apps`, `screen_time`,
  `usage_granted`). Funciona **sem shell**. Sem autorização devolve vazio e o painel
  mostra "—" + o aviso `#usageHint`; nada é inventado. O botão fica em Configs →
  Permissões (`setPermUsage` → `OTM.call("usage")`).
- Home (painel): as métricas ficam em **dois grupos** (`.stat-group` + `.glabel`):
  *Sistema agora* (RAM/CPU/bateria/armazenamento/tela/tempo ligado) e *Uso do
  aparelho* (`fg`/`usage`). O grupo de uso traz o selo `#usageNeed` e o botão
  `#btnUsagePerm` (→ `openUsageSettings`), que somem quando `usage_granted` é true.
  O botão `#btnRefreshStats` fica no cabeçalho (`.boxhead`) e o `#liveBadge` mostra
  "ao vivo · há N s". Tudo é escondido/mostrado por `renderStats` (não há `esc()`).
- Permissões/segundo plano: a engrenagem lista o que o app precisa e tem botões
  que rodam `adb-tweaks.sh perm_app|perm_ff|perm_battery|perm_all` (grupos novos,
  reversíveis: entram na isenção do Doze via `cmd deviceidle whitelist`, ganham
  `appops` de `RUN_IN_BACKGROUND`/`RUN_ANY_IN_BACKGROUND`/`WAKE_LOCK`/
  `START_FOREGROUND` e desligam economia de bateria/App Standby). No lado nativo,
  `Permissions.kt` cuida só do que o app pede sozinho (canal de notificação,
  `POST_NOTIFICATIONS` no Android 13+ e `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`),
  sem bloquear o painel. `PanelActivity.injectHeaderButtons` garante o botão
  "Conectar" após cada carga da página.
- Arrasto lateral: o topo usa `min-height` + `flex-wrap` e a página usa
  `overflow-x:clip` (o `hidden` deixava o `body` virar contêiner de rolagem e o
  menu fixo ainda esticava a largura). Papel de parede: `contain` na camada
  visível sobre `cover` no fundo.
- Áudio: `SoundPlayer` toca MP3 de `assets/audio` via `MediaPlayer`+`openFd`
  (por isso o APK guarda os MP3 STORED, sem compressão — `noCompress += "mp3"` no
  `build.gradle.kts`; sem isso `openFd` lança e o som some). Usa
  `USAGE_MEDIA` (canal de **mídia**, não de sonificação): o canal de sonificação
  fica mudo em muitos aparelhos mesmo com o volume de mídia alto. Falhas vão para
  o logcat com a tag `SoundPlayer`. O botão de som do cabeçalho (`#otmSound`, ícone
  SVG) tem handler no shim (`build_panel.py`): liga/desliga via `setSound` e
  esmaece quando desligado. `SoundPlayer` cancela o timer do som anterior antes de
  agendar o próximo (senão o timer antigo cortava o som novo).
  `PackBridge.soundFor(grupo)` escolhe o som conforme o grupo da ação.
- Aparência: `ACCENTS`/`FONTS` em `web/index.php` são a fonte de verdade das cores
  de destaque (inclui **prata**) e fontes; os swatches/segmentos são casados por
  `data-accent`/`data-font` com essas chaves. O seletor de fonte quebra em várias
  linhas (`#setFont{flex-wrap:wrap}`) por ter 7 opções.
- Categorias do painel: são 7 grupos definidos em `otm_actions()` pelo campo `group`
  (`Geral`, `Display & Touch`, `Desempenho`, `DNS e rede`, `Processos`,
  `Apps e jogos`, `Sistema`) mais a **Home** (métricas, não é grupo de ações).
  A antiga `Rede e conexão` virou `DNS e rede` (`$GROUP_ALIAS` em `web/index.php`
  mantém o alias para ações legadas). A ordem de exibição
  vem de `$GROUP_ORDER` em `web/index.php` (com
  fallback para grupos fora da lista). `actions.json` do app é gerado a partir de
  `otm_actions()` (mesmo `group`). Ao renomear categoria, ajuste também
  `PackBridge.soundFor` (som por grupo) e os testes em `tests/run.sh`.
- Catálogo de DNS: são **39 perfis DoT** (todos com hostname verificado na fonte
  oficial) em `scripts/dns.sh` (`dns_profiles()`) e espelhados em `web/lib.php`
  (`$dns`). Cobre velocidade, privacidade, anti-anúncios, família, segurança e sem
  filtro (Cloudflare, Quad9, AdGuard, Mullvad, ControlD, DNS4EU, CleanBrowsing,
  OpenDNS, DNS.SB, CZ.NIC, Digitale Gesellschaft, RESTENA, Applied Privacy,
  UncensoredDNS, DNSForge, NextDNS, Google). O submenu (`dns_menu`) numera os
  perfis e reserva a última posição para `custom`; ao adicionar/remover perfil não
  há número fixo a ajustar. Os testes em `tests/run.sh` (`t_dns`) conferem cada
  hostname e o total (>=30).

Build local (sem Android Studio):

```sh
# toolchain em /workspace/project/.toolchain (JDK 21 + SDK 34 + Gradle 8.7)
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/workspace/project/.toolchain/sdk
cd android && GRADLE_USER_HOME=/workspace/project/.toolchain/gradle-home \
  ./gradlew :app:assembleRelease
# saída: app/build/outputs/apk/release/app-release.apk (já assinado)
```

Assinatura (atualizar por cima, sem desinstalar): o `release` usa a keystore fixa
`android/keystore/otm-release.jks` (alias `otm`, senha `00deUdia`), configurada em
`android/app/build.gradle.kts`. A mesma chave assina toda versão, então o Android
aceita instalar a nova por cima da anterior. Não troque essa keystore sem avisar:
trocar a chave quebra a atualização e obriga a desinstalar. O `zipalign`/`apksigner`
manuais não são mais necessários (o Gradle assina no `assembleRelease`).

A versão do app acompanha `VERSION` (`versionName`/`versionCode` em
`android/app/build.gradle.kts`). Nome de exibição: "00 Otimização". O APK é
publicado em `releases/` e em `serve/` (ambos ignoram `*.apk` no git).

