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
  `refresh_fixed` (trava min=peak numa taxa), `perfmode` (modo desempenho fixo) e
  `telemetry on|off` (logpersist + scans sempre-disponível).
  Tudo registra reversão no escopo próprio (`~/.packotm/undo/turbo.sh`), revertido por
  `pack.sh restore` / `adb-tweaks.sh restore_all`.
- `scripts/debloat.sh preview [alvo]` — mostra o que seria removido, com o motivo de
  cada pacote, e só o que existe de fato no aparelho, sem alterar nada. `alvo` pode ser
  `universal`, uma marca (`samsung`, `xiaomi`, ...), `marca` (detecta) ou um perfil
  (`leve|medio|pesado`). O perfil antigo mantém a classificação SAFE/CAUTION/DANGEROUS
  em `risk_of`.
- `scripts/dns.sh bench` — mede a latência de cada perfil de DNS (não altera nada).
- **Debloat** (`scripts/debloat.sh` + `scripts/debloat-lists.sh`, categoria própria no
  painel) — remove bloatware de fábrica por lista curada, sem root. `debloat-lists.sh` é
  **só dados**: 12 listas (uma `universal` + 11 por marca: samsung, xiaomi, motorola,
  oneplus, realme, vivo, huawei, asus, sony, lg, transsion), 433 pacotes no total, cada
  linha no formato `pacote|motivo`. Fonte: banco do **Universal Android Debloater** (UAD,
  `uad_lists.json`); só entram pacotes com veredito `Recommended`. Aplicação por
  `pm uninstall -k --user 0` (reversível com `install-existing`), registrada em
  `~/.packotm/debloat/off.sh` e revertida por `debloat.sh off` / `pack.sh restore`.
  Subcomandos: `universal`, `<marca>`, `marca` (detecta pelo `ro.product.manufacturer`),
  `marcas`, `preview [alvo]`. **Proteção em duas camadas**: as listas já são filtradas
  (nunca contêm câmera, galeria, telefone, mensagens, contatos, teclado, Bluetooth, NFC,
  Wi-Fi, launcher, SystemUI, Settings, GMS/Play, biometria, pagamento, atualização,
  acessibilidade ou qualquer coisa marcada `Unsafe` pelo UAD) **e** `d_protected()` em
  tempo de execução recusa qualquer pacote que case com `DBL_KEEP`/`DBL_NEVER`, mesmo que
  escape de uma lista. Categoria **Debloat** (14 ações): universal, da minha marca, por
  marca (escolher), prévia, perfis leve/médio/pesado, reverter tudo e as ações por app
  (desativar, reativar, desinstalar, reinstalar, restringir, tirar restrição).

`main.sh` (raiz) é a **entrada alternativa**: baixa os recursos full (`codeload` do
GitHub), sobe o **servidor web** (`php -S`) e abre o **painel PHP** (`web/`). Não aplica
otimizações — quem faz isso é o `pack.sh`.

O **painel web** (`web/lib.php` + `web/api.php` + `web/index.php`) — marca
**Trix** — controla o pack pelo navegador. Regras ao mexer nele:
- `web/lib.php` guarda o **registro de ações** (id, grupo, argv, params, confirm, risco).
  Para expor uma ação nova, adicione ao registro — **não** invente execução de comando cru.
- `web/index.php` é **renderizado no servidor (PHP)**: o menu de categorias e os cards de
  ação saem prontos no HTML. O JS só troca de categoria, executa e mostra saída/modal.
  Mantenha o visual **clean**, a paleta própria e o CSS **responsivo** (gaveta no celular,
  tema claro/escuro) ao mexer.
- `web/index.php` e `web/api.php` **exigem login** (usuário e senha, `web/auth.php`, sessão PHP).
  A senha é guardada só como **hash** (`password_hash`) em `~/.packotm/web/auth.json`
  (nunca em texto puro, nunca versionado, `chmod 600`); a credencial inicial fica em
  `OTM_DEFAULT_USER`/`OTM_DEFAULT_HASH` (`web/auth.php`). A tela de entrada (`web/login.php`)
  usa **CSRF** (`otm_csrf`).
- `web/api.php` aceita a **sessão do painel** ou o **token do servidor** (`web/.token`) no cabeçalho
  `X-Otm-Token` / em `?token=` (para scripts e integrações), e só roda scripts da lista branca
  `otm_allowed_scripts()`. Parâmetros são validados por tipo (pkg/host/int/float/enum).
  Nunca passe input do usuário direto para o shell.
- Ações com `confirm:true` exigem `confirm=1` no POST (o `index.php` mostra o modal).
- `web/.token`, `web/.state/` e `web/auth.json` são **locais** (no `.gitignore` e removidos do zip).

### Painel de administração (`panel/`)

`panel/` é o painel interno da equipe, com acesso por **usuário e senha de administrador**
guardados no banco. Estrutura:

```
panel/
  bin/          CLIs: admin.php, migrate.php
  config/       config.php, turso.php (segredo, fora do git), local.php
  database/     migrations/*.sql (0001_admins, 0002_panel)
  public/       páginas (login, index, audit, settings, admins, logout)
  src/          OtmDb (contrato), Turso (remoto), Db (SQLite local), Auth, Audit, Helpers, layout
```

Regras:
- **Dois bancos, um código.** `OtmDb` é o contrato; `Turso` (HTTP, produção) e `Db`
  (SQLite local) implementam. `otm_db()` escolhe: `OTM_LOCAL_DB` definido → SQLite;
  senão, se o Turso estiver configurado → Turso; senão → SQLite. `Auth`/`Audit`
  não sabem a diferença. **Nunca** use type hint de `Turso` em código novo — use `OtmDb`.
- **A senha do admin nunca é gravada em claro**: só o `password_hash` (bcrypt/argon2 do PHP).
  O login é feito por `Auth::login()` (`src/Auth.php`), que também grava tentativas e
  sessões (`otm_admin_sessions`, `otm_login_attempts`) e freia por IP.
- **Visual do painel é "sistema legado"**: cinza de janela, cantos retos, tabelas com
  grade completa, fonte de sistema pequena e densa. Tudo em `public/assets/admin.css`
  (CSS puro, sem framework). Barra de título azul no topo (`layout.php`) e barra de
  status no rodapé mostrando versão, banco em uso (`otm_db_label()`) e a hora. Ao mexer
  no CSS, mantenha as classes que as páginas usam (`.grid`, `.card`, `.btn`, `.tag`,
  `.frm`, `.dl`, `.bar`, `.pager`) e o modo estreito (`@media max-width: 760px`).
- **Tema claro/escuro no painel**: as cores saem de variáveis CSS em `:root` e
  `:root[data-theme="dark"]` (`admin.css`). O `layout.php` (e `login.php`) traz um
  script no `<head>` que aplica o tema antes da pintura, lendo `localStorage['otm-theme']`;
  sem escolha, vale `prefers-color-scheme`. O botão `#otmThemeBtn` só alterna o atributo
  `data-theme` no `<html>` e grava a escolha. Não coloque cores fixas nas páginas: use as
  variáveis, senão o modo escuro fica pela metade.
- **Exclusão no painel**: as ações destrutivas passam por `otm_require_write()` e CSRF,
  usam `otm_action_button(..., 'btn danger sm', 'Confirma?')` e sempre registram na
  auditoria. `audit.php` (limpar antigas / tudo, só dono) e `admins.php` (apagar admin, com
  trava contra apagar a si mesmo ou o último dono ativo). Ao apagar admin, remova também
  as sessões (`otm_admin_sessions`).
- **Cuidado ao testar exclusão contra o banco real**: sem `OTM_LOCAL_DB`, o painel grava
  no **Turso** (produção). Nunca aponte um teste destrutivo para lá. Prefira um SQLite
  temporário (`OTM_LOCAL_DB=/tmp/x.sqlite`) ou crie um alvo descartável. Se apagar algo
  por engano, `Audit` e os backups em `/tmp/otm-backup/` ajudam a reconstruir.
- **O token do Turso fica no servidor** (`panel/config/turso.php`, no `.gitignore`). O APK
  nunca o vê.
- Páginas do painel exigem **login de administrador** (`otm_admins`, senha com
  `password_hash`) + **CSRF**. Crie o primeiro com
  `php panel/bin/admin.php add SEU_USUARIO --role owner`.
- `otm_msg()` mora em `src/Helpers.php` (não no layout) porque a tela de login usa sem
  carregar o layout.

Comandos:

```sh
sh main.sh web migrate                     # aplica as migrations (Turso ou SQLite)
sh main.sh web admin add whesley --role owner
sh main.sh web admin list
OTM_LOCAL_DB=/tmp/painel.sqlite php panel/bin/migrate.php   # roda no SQLite local (sem rede)
```

`index.html` é o site público (um só arquivo, sem dependências): explica os 4 níveis, os
apps, os plugins/módulos e tem uma **área de comandos** com busca e botão de copiar.
Publique no GitHub Pages apontando para a raiz (o `index.html` fica na raiz).

## Comandos

O pipeline do painel (renderizar `web/index.php`, `scratch/gen_actions.php`,
`sync_app_panel.py`) precisa de **PHP**. Se `php` não estiver no PATH, o
`tests/run.sh` **pula** os testes do painel em silêncio e mostra falhas soltas
(`php: not found`) — não confie num "0 falharam" sem conferir que o PHP rodou.
Há um PHP estático no toolchain: `export PATH=/workspace/project/.toolchain/php:$PATH`.

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
- Transporte por `scripts/common.sh`: `OTM_MODE=adb|usb|rish|su|local` (auto-detectado).
  `usb` = `adb shell` no 1º aparelho do cabo (sem parear); `adb` = endereço fixo `OTM_ADB_SERIAL`.
  Quando o processo **já nasce privilegiado** (o app roda os scripts pelo Shizuku/ADB, uid
  2000, e não há `rish`/`adb` no PATH) a detecção devolve `RUN_MODE=direct` — é o modo que
  faz o botão "Clean Phone" funcionar. Sem isso o pack se dizia "sem shell" e recusava tudo.
- Reversão das otimizações profundas em `~/.packotm/deep/off.sh` (formato `<tag>\t<comando>`).
- Reversão das ações do dia a dia é **por escopo**: cada script chama `scope_begin <nome>`
  e grava em `~/.packotm/undo/<nome>.sh` (o escopo padrão segue em `~/.packotm/off.sh`).
  As linhas de reversão são **condicionais** (`[ "$(settings get ...)" = "<o que apliquei>" ] && ...`),
  então desfazer uma ação não apaga o que outra aplicou depois na mesma chave. O valor
  original do aparelho fica em `~/.packotm/origins` e é ele que `restore_all` restaura.
  `adb-tweaks.sh restore_all` percorre todos os escopos (`otm_undo_files`) e limpa tudo.
- Estado local nunca versionado (`~/.packotm`, `00 Otimizações/Plugins AxManager/**/state/`, `releases/*.zip`).
- CI em `.github/workflows/build.yml`: sintaxe + shellcheck + testes + segredos; release
  por tag `v*` publica `SHA256SUMS.txt` e usa `CHANGELOG.md` como corpo.

## Pendências que dependem do dono

- **Push para `origin/main`**: o `GITHUB_TOKEN` do ambiente é uma credencial de
  integração (GitHub App) e **não** serve para a API de releases
  (`Resource not accessible by integration`). Já o token embutido na URL do
  remote `origin`/`otm-push` tem escopo `repo` e admin no repo, e o `git push`
  passa por ele. Ainda assim, **não empurre direto para `main`**: use a branch de
  trabalho (`sem-root`) e deixe o merge para o dono.
- Revogar o token exposto no histórico e purgar o `apps_otm.zip` (`docs/SEGURANCA.md`).
- Benchmark real em aparelhos e preencher `docs/COMPATIBILIDADE.md`.
- Infra de venda/suporte (`docs/PRODUTO.md`, `docs/ROADMAP.md`).

## App Android (`app/`)

App companion (Kotlin, `com.otm.pack`) que roda o pack pelo Shizuku (root/ADB)
ou por ADB Wi-Fi (pareamento) / depuração USB (só autorizar, sem parear), com os
assets do pack embutidos.

O app é o painel web (Trix) dentro de uma WebView: nada de UI
nativa além do necessário para conectar e rodar os comandos.

- `PanelActivity` é o launcher: carrega `assets/panel/login.html` (tela de entrada)
  numa WebView; acertando o login, carrega `assets/panel/index.html` (o painel).
- **O binder do Shizuku chega DEPOIS do `onCreate`** (a resposta do
  `ShizukuProvider` volta por Binder). Checar `hasPermission()` só no `onCreate`
  faz o app concluir "não autorizado" com a permissão já concedida — e pedir de
  novo a cada abertura. Por isso `PanelActivity` registra
  `addBinderReceivedListenerSticky` + `addBinderDeadListener` e concentra a
  conexão silenciosa em `tryAutoConnectShizuku()`, chamada também no `onResume`
  (caso o usuário libere a permissão por fora, no app do Shizuku). Esse caminho
  **nunca** chama `requestPermission`; o pedido só sai do botão explícito.
  `ShizukuRunner.requestPermission` devolve `false` quando o binder ainda não
  chegou (antes lançava). Os listeners são removidos no `onDestroy`.
- Login por **usuário e senha**, validado localmente contra a constante `OTM_AUTH`
  (`sha256("usuario:senha")`) em `login.html`. O painel (`index.html`) tem guarda de
  sessão (`otm_session` no `localStorage`); o botão Sair limpa a sessão e volta ao login.
- A ponte `OTM.call("login"|"login_fail")` só avisa o app para tocar o áudio
  (`login_feito_com_sucesso.mp3` / `credenciais_incorretas.mp3`).
- Áudio segue a ação, não a tela: som do grupo no início, e no fim
  `perfil-aplicado-com-sucesso.mp3` ou `erro.mp3` conforme o resultado.
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
  O mesmo script também reescreve o objeto `ACTIONS` embutido no painel, então
  `php scratch/gen_actions.php app/src/main/assets/panel/actions.json
  app/src/main/assets/panel/index.html` mantém catálogo e HTML do app em sincronia.
  O painel do app é o HTML do PHP já renderizado. O pipeline é:
  `php -r 'require "web/auth.php"; otm_auth_login(<user>,<pass>); ob_start();
  include "web/index.php"; file_put_contents("/tmp/pan/web.html", ob_get_clean());'`
  → `python3 scratch/sync_app_panel.py /tmp/pan/web.html` (traz o nav, as seções
  novas, **remove as seções de grupo que sumiram do web** — ao renomear um grupo
  a seção antiga ficava órfã, com o link do menu junto — e o objeto `ACTIONS` do
  web para o app) → `python3 scratch/patch_app_panel.py`
  (tira as ações só de root e ajusta textos) → `php scratch/gen_actions.php
  app/src/main/assets/panel/actions.json app/src/main/assets/panel/index.html`.
  Ao mexer em `index.php`/`lib.php`, os dois painéis (`web/index.php` e
  `assets/panel/index.html`) precisam ficar em sincronia (o CSS/JS é o mesmo).
- Os scripts de `scripts/` são a fonte da verdade; o app embarca uma **cópia
  versionada** em `app/src/main/assets/pack/scripts` (task Gradle `syncPackAssets`
  no `preBuild`, que usa `Sync` para remover sobras). Como o espelho vai para o
  git, ele não se atualiza sozinho fora do Gradle: ao mexer em `scripts/`, rode
  `cp scripts/*.sh app/src/main/assets/pack/scripts/` (e apague os removidos). O
  teste `t_pack_scripts_mirror` em `tests/run.sh` compara os dois diretórios e
  confere que todo `argv[0]` de ação existe no espelho.
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
  Cada linha guarda o que a ação **tentou** (`applies`), o que **mudou**
  (`changed`), quantas **falharam** (`failed`), as `reasons` (as linhas do
  script que explicam a falha — `✕`/`X` com o valor lido) e a saída crua
  (`out`, cortada em 6000 caracteres). A linha com detalhe é clicável
  (`.logsrow.has-det`) e abre as razões + a saída. O mesmo formato é gravado
  pelo PHP (`otm_log`) e pelo Kotlin (`logAppend`), e o teste `t_logs` falha se
  os dois lados divergirem.
  Como a saída crua entra no log, o arquivo é **podado**: acima de ~1,5 MB
  ficam as últimas 800 execuções (`otm_log_trim`/`trimLog`, `LOG_MAX`), no
  mesmo limite dos dois lados.
- **Painel flutuante (overlay sobre o jogo).** `OverlayService` (janela
  `TYPE_APPLICATION_OVERLAY`, precisa de `SYSTEM_ALERT_WINDOW`) mostra o painel
  por cima do Free Fire. O título é só **"00"** e o conteúdo é organizado em
  **abas** por categoria — `TABS` = `Monitor`, `Toque`, `Motor`, `Processos`,
  `Atalhos` (a aba **Sensi saiu**: o overlay aplica o headshot da sensi, mas não
  lê mais o `sensi.sh`).
  A aba **Monitor** lê o `panel-stats.sh` e se atualiza sozinha a cada 4 s
  (enquanto estiver aberta: `monitorBox` é zerado no `selectTab` para o
  `postDelayed` parar). O FPS mostrado é **real**, do `SurfaceFlinger`
  (`fps.sh` / `otm_fps_measure`): `fps = (frames-1)/(último-primeiro)` sobre os
  carimbos de apresentação — nunca a taxa da tela fingindo ser FPS. Sem frames
  (jogo no menu, camada trocada, app fora da tela) mostra **"—"**, não um número
  inventado. O mesmo card existe na Home do painel (app e `web/index.php`) via
  a chave `fps` do stats.
  A ordem de `TABS` **tem de casar** com o `when` do `tabView`: a barra passa o
  índice do rótulo, então fora de sincronia o conteúdo sai na aba errada (foi
  assim que o FPS ficou escondido em "Processos" e "Monitor" abria o toque). O
  `tests/run.sh` compara as duas ordens justamente por isso.
  **Tamanho**: largura **fixa** (`panelWidth`, ~46% da tela com piso/teto em dp)
  — com `WRAP_CONTENT` cada aba media um tamanho e o painel pulava ao trocar de
  aba. Altura acompanha o conteúdo até `panelMaxHeight` (~50% da tela). A bolha
  de minimizado é quadrado fixo (`BUBBLE_DP`, 46 dp): o ícone é *adaptive icon*
  e solto num `ImageView` não tem tamanho confiável (saía enorme).
  A aba **Atalhos** tem a seção **Jogo** com o downscale do `game-per-app.sh`
  (`GAME_SCALES` = `fps` 0.9 / `balanced` 0.75 / `max` 0.5, mais "Reset
  resolução" e "Ver tuning"). O overlay sempre passa **`auto`** como pacote:
  ele não sabe qual é o jogo, e o script resolve (jogo escolhido no pack, senão
  o app em primeiro plano). `auto` vale para `apply`, `custom`, `mode`, `show` e
  `reset` — todos passam por `_resolver_pkg`, que devolve o pacote por variável
  (`RESOLVED_PKG`), **não** por stdout: capturar com `$( )` engoliria a mensagem
  de erro junto com o valor.
  A aba **Processos** é o gerenciador de segundo plano para o meio da partida:
  seletor de limite (`PROC_LIMITS` → `adb-tweaks.sh proc_limit`), "Encerrar
  todos" (`proc-mgr.sh kill`), "RAM agora" (`ram-boost.sh boost normal`), criar
  a exceção do app em 1º plano (`proc-mgr.sh keep-fg`), ver as exceções e a lista
  de **apps rodando agora** com a RAM de cada um. A lista vem do
  `proc-mgr.sh list` (linhas `#OTM-PROC`, lidas por `parseProcList`), o nome
  legível vem do `PackageManager` (`getApplicationLabel`, com o pacote como
  reserva) e cada linha traz um chip "exceção"/"não encerra" que chama
  `proc-mgr.sh keep|unkeep`.
  A seção **Todos os apps** (lista `procAllBox`) usa `proc-mgr.sh apps` (linhas
  `#OTM-APP pkg=… protected=…`): todos os apps de usuário **instalados**, não só
  os que estão rodando — é assim que se protege um app que ainda vai abrir
  (banco, por exemplo). `parseProcList` aceita os dois prefixos e ordena por RAM
  quando há RAM na lista, senão alfabeticamente.
  O visual segue o tema do painel: fundo arredondado, `setBackgroundBlurRadius`
  (Android 12+), botões de vidro (pílula translúcida) e a cor/fonte escolhidas
  na engrenagem. Cor e fonte vêm de `OtmUi` (SharedPreferences `otm-ui`), que o
  WebView alimenta pela ponte `ui_prefs`; `OtmUi.onChanged` faz o overlay se
  redesenhar na hora. As cores do overlay são **Strings hex** (helpers `col()`,
  `accentA(alpha)`), não `Int`, e as fontes empacotadas são carregadas por
  `FONT_FILES` (ver *Aparência*). O overlay usa o **mesmo executor** do painel
  (`OtmExec.run` + `OtmRunner.current`), senão divergiria do painel.
- **Armadilhas do painel (já custaram bug).** Três coisas que o CSS/JS do painel
  não perdoa, porque o HTML é gerado (`web/index.php` → `scratch/`):
  (1) **CSS não pode depender de `.card-choice`** para layout de `.opts`: nem todo
  card de opções tem essa classe (o de Perfil de Desempenho não tem), e o cartão
  empilha os botões. Use `.opts{display:flex...}` solto. O teste em `t_vitality`
  acusa se voltar a `.card-choice .opts`.
  (2) **Handler de botão que ignora `a.confirm`**: `data-vital-go` chamava
  `doRun(a, {}, false, b)` com `false` fixo, então a única ação com `confirm`
  (`vital.optimize`) pulava o modal e o `runImpl` do Android respondia "esta ação
  pede confirmação". O certo é abrir o modal (`askConfirm`) quando `a.confirm` e
  deixar o `runPending` reexecutar com `confirmed=true`. Ao mexer em `web/index.php`,
  replique em `assets/panel/index.html` (os dois têm o mesmo CSS/JS).
  (3) **O rodapé com os créditos sobe para o meio da tela em páginas/abas curtas**
  se o `body` não for coluna flexível: o conteúdo acaba e o rodapé para logo
  abaixo dele, no meio do vazio. O `body` precisa de
  `display:flex; flex-direction:column` e o miolo de `flex:1 0 auto` (o painel usa
  `.layout`, o login usa `.wrap{margin:auto}`, o guia usa `main.wrap`). O teste
  `t_footer_sticky` cobre as cinco páginas (`assets/panel/index.html`,
  `web/index.php`, `web/login.php`, `index.html`, `public/guia.html`).
- **Efeitos visuais desligados pelas ações de desempenho (já custou bug).** Todo
  ajuste de performance (`perf`, `gpu`, `fluidez`, `clean`, `smart-opt` e o pack
  recomendado) grava `disable_window_blurs=1` e
  `accessibility_reduce_transparency=1`. Isso mata o desfoque atrás do teclado,
  da barra de navegação e das notificações e a transparência do sistema — o
  usuário sente como "interface seca". Dois cuidados: (1) **tudo que mexe nesses
  dois settings tem de usar `bkp_set`**, nunca `sh_run`, senão fica fora do
  arquivo de reversão e nem o "Reverter TUDO" devolve (foi o caso do `fluidez`);
  (2) o grupo `effects <on|off|status>` (`adb-tweaks.sh`) é o card do painel que
  liga/desliga na mão. O `panel-state.sh` expõe `blur`/`reduce_transparency`
  como `on`/`off`, tratando **ausente = `on`** (o padrão do Android é o efeito
  ligado, e `settings get` devolve `null` quando nunca foi escrito). O teste
  `t_effects` cobre isso. O modo imersivo do `window_tweaks` (`policy_control`)
  tinha o mesmo defeito e agora também entra na reversão.
- **Limite de processos: onde o Android realmente lê (já custou bug).** O pack
  escrevia `max_cached_processes` no setting `activity_manager_constants` e o
  aparelho continuava em "Padrão". Motivo: a partir do Android 10 a plataforma lê
  de **`device_config activity_manager max_cached_processes`** (o Dev Options usa
  um override interno do ActivityManager e o setting só serve de legado). O
  caminho certo é `proc_limit_set`/`proc_limit_get` em `common.sh`: escreve no
  `device_config`, mantém o setting em sincronia para Androids antigos e **lê de
  volta** — `proc_limit_get` devolve o valor real e `otm_v_report` marca falha
  quando não pegou. Não volte a chamar `am_set max_cached_processes=<n>` direto:
  o teste `t_proc_limit` procura exatamente esse padrão em `scripts/`.
- **Pareamento ADB por Wi-Fi (já custou bug).** Três armadilhas que quebram o
  "só o código de 6 números" (`AdbRunner.kt` / `WifiDialog.kt`), todas invisíveis
  sem device (a lib engole os erros):
  (1) **Chave × certificado desencontrados.** O TLS do pareamento assina com a
  privada e apresenta o certificado. Se o certificado sair de um par novo (era o
  que acontecia quando o `adbcert.pem` faltava e a privada vinha do disco), o
  handshake morre com `SignatureException`. O certificado tem de ser derivado da
  **mesma** privada — daí o `publicFrom(RSAPrivateCrtKey)` reconstruir a pública,
  já que o PKCS#8 guardado não a traz. Um `.pem` de par antigo é descartado quando
  `cert.publicKey != adbKeyPair.public`.
  (2) **`NsdManager` entrega os eventos no Looper de quem o criou.** A descoberta
  precisa rodar em `Dispatchers.Main`; em `Dispatchers.IO` o callback nunca chega e
  o `start()` fica mudo (a lib ainda deixa `onStartDiscoveryFailed` vazio).
  (3) **Descoberta sem permissão falha em silêncio.** Android 13+ exige
  `NEARBY_WIFI_DEVICES` e o 12- exige `ACCESS_FINE_LOCATION`; o multicast ainda
  precisa de `CHANGE_WIFI_MULTICAST_STATE` + `MulticastLock` segurado. Há um plano B
  de mDNS próprio (`discoverViaMulticast`/`parseMdnsAnswer`) porque o NsdManager do
  sistema falha em algumas redes. Lembrar: no cabeçalho SRV a porta está no
  **offset 4** (prioridade,peso,porta), não no 0.
  O pareamento também usa API oculta do Conscrypt (`exportKeyingMaterial`, TLS 1.3),
  liberada pelo `OtmApp` (`HiddenApiBypass.addHiddenApiExemptions("L")` + `PRNGFixes`).
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
  só leitura + encerrar/exceções — limite de RAM, `cpuset`, `nice` e `SIGSTOP`
  exigem root e **saíram** do pack. Comandos: `top [n]` (mais CPU/RAM via
  `/proc`), `list [n]` (apps de usuário rodando, com RAM e o estado da exceção),
  `info <pkg>`, `kill` (encerra o 2º plano poupando exceções/1º plano/jogo),
  `keep <pkg>` / `unkeep <pkg>` / `keep-fg` / `keep-list` / `keep-clear`
  (exceções "X app não encerra", guardadas em `$ST/procmgr/keep`). A categoria
  **Processos** agrupa essas ações.
  `list` imprime uma linha legível por máquina por app rodando
  (`#OTM-PROC pkg=<pacote> ram=<MB> protected=<0|1>`), que é o que a aba
  **Processos** do painel flutuante lê para montar a lista com nome e RAM.
  As exceções entram no `otm_keep_list` (`common.sh`): valem para o "Encerrar
  todos" do flutuante **e** para o `clean.sh`/`ram-boost.sh`/`game-clean.sh`.
- **Anti-relog** (`scripts/keep-alive.sh`, na whitelist do `lib.php`): impede o
  app/jogo de "relogar" (abrir do zero e pedir login) ao ser morto em segundo
  plano. `on <pkg> [jogo]` isenta do Doze, libera `RUN_IN_BACKGROUND`/
  `RUN_ANY_IN_BACKGROUND`/`START_FOREGROUND`/`WAKE_LOCK`, põe no balde `active`,
  tira do congelador/cache freezer e, com root, sobe a prioridade de memória dos
  processos (`ka_oom_prio`, `oom_score_adj=-900`, com a reversão guardada por PID);
  `off <pkg>` desfaz; `status <pkg>` lê tudo de volta; `list` e `restore` gerenciam a
  lista guardada em `$ST/keepalive/apps`. Usa `ka_run`/`bkp_raw` (reversível) e
  `require_shell` (sem Shizuku/ADB/root avisa e não aplica). Categoria **Processos**.
- **Game Clean** (`scripts/game-clean.sh`, na whitelist do `lib.php`): junta o
  "modo partida" num clique. `on [pkg] [max]` encerra apps de fundo (poupando o
  jogo e os protegidos no anti-relog), poda cache/dexopt, põe a RAM no perfil
  gaming (`max_cached_processes=8`), chama `keep-alive.sh on <pkg> jogo`, isenta
  do Doze, liga Game Mode performance + driver, silencia heads-up/bolhas + Não
  Perturbe e corta telemetria/scans. O modo `max` também encerra apps de mídia/chat
  conhecidos (`GC_EXTRA`). `off [pkg]` desfaz (usa o escopo próprio `~/.packotm/undo/game-clean.sh`
  de `bkp_set`/`bkp_raw` e o `keep-alive.sh off`) e `status [pkg]` lê tudo de volta. Estado em
  `$ST/gameclean/applied`. Categoria **Apps e jogos** (grupo de escolha `gameclean`).
- **Jogo do modo gamer** (`adb-tweaks.sh game_open [pkg]`): o "modo gamer" abria
  sempre o Free Fire. Agora o usuário escolhe o jogo (FF, FF MAX, CODM, Minecraft,
  qualquer instalado) pelo seletor de apps da Home; o pacote fica salvo em
  `$ST/game/pkg` e vale nas próximas vezes. `game_open` chama `game_keepalive` e
  depois abre o jogo por `cmd package resolve-activity` (com `monkey` de reserva),
  sem depender da Activity de cada jogo. Sem argumento usa o salvo (padrão
  `com.dts.freefireth`); pacote inválido é recusado. `game()` também cobre o jogo
  escolhido. `ff_open` segue existindo (abre o Free Fire fixo).
- **Anti-relog do modo gamer** (`adb-tweaks.sh game_keepalive [pkg]`, grupo próprio
  e ação `game.keepalive` no `lib.php`): junta o que impede o jogo de relogar.
  Deixa o jogo **sem restrição de bateria** (`perm_pkg`: Doze, 2º plano, wake lock),
  limita o aparelho a **no máximo 4 apps em 2º plano** (`am_set max_cached_processes=4`),
  põe no balde `active`, desliga o `cached_apps_freezer`, chama `keep-alive.sh on
  <pkg> jogo` e liga o Game Mode performance. `game_open` e `game()` usam essa
  função, então o ajuste vem junto. Card da Home usa `runGameHome()` — não
  `runActionById('ff_open')`.
- **Constantes do ActivityManager** (`common.sh am_constants_merge`/`am_set`):
  `settings put global activity_manager_constants` substitui a string inteira.
  Gravar só `max_cached_processes=4` apagava o `max_phantom_processes` e outros
  ajustes. `am_set` mescla com o que já existe (preserva as demais chaves e
  atualiza só as informadas); `perf`, `mem` e `game-clean` passaram a usá-lo.
- **Liberar RAM** (`scripts/ram-boost.sh`, na whitelist do `lib.php`): libera memória
  de verdade (ação pontual, nada a reverter). `boost [normal|max]` encerra os apps de
  3º plano via `otm_bg_kill` (poupa o jogo e os protegidos no anti-relog), poda o cache
  (`otm_cache_trim`), roda `am kill-all` e, com root, solta o pagecache
  (`otm_drop_caches`). Mostra a RAM livre antes/depois (`otm_ram_livre_mb`, de
  `/proc/meminfo`). O modo `max` também encerra apps de mídia/chat (`RB_EXTRA`).
  `status` mostra RAM livre/total, o perfil de cache e quem está protegido. Exige
  shell (`require_shell`). Categoria **Desempenho** (grupo de escolha `ramboost`).
- **Otimizador Inteligente** (`scripts/smart-opt.sh`, na whitelist do `lib.php`):
  em vez de aplicar o mesmo pacote para todo aparelho, ele **lê o aparelho de ponta
  a ponta** e decide item por item. O comando principal é **`auto`** — é ele que a
  ação do painel (**"Otimizador inteligente"**, `smart.auto`) roda: lê, decide e
  aplica tudo numa tacada. Ações: `auto` (faz tudo), `analyze` (relatório só-leitura: modelo,
  Android/API/kernel, família de SoC, GPU, núcleos e frequência de pico, RAM, taxa de
  tela suportada, armazenamento, térmico, bateria, zram, governor, MGLRU, BBR, apps de
  usuário — e uma **nota 0..100** + classe `topo|alto|medio|entrada`), `plan [perfil]`
  (mostra o que seria aplicado e o motivo, sem alterar nada), `apply [perfil]`,
  `status` e `restore`. Perfis: `auto` (padrão; vira `jogo` se há jogo escolhido, senão
  `desempenho` em aparelho forte e `equilibrado` no resto), `equilibrado`,
  `desempenho`, `jogo` (liga o anti-relog no jogo salvo) e `bateria` (tela em 60Hz).
  A decisão varia com o aparelho: apps em cache (4 no jogo, 8/16/24/32 por classe),
  renderizador (Vulkan em API>=30 com Adreno/Mali, GL no resto), taxa de tela (a maior
  lida; se não der para ler, fica no automático em vez de chutar), fase da limpeza e
  Phantom Process Killer (off com RAM>=6GB). A aplicação **delega** aos módulos já
  testados (`adb-tweaks perf/perf_max/renderer/doze/game_keepalive/game_focus`,
  `turbo refresh_fixed`, `clean now`) e depois **lê
  de volta** alguns ajustes (`so_verify`) para o painel não achar que "nada mudou"
  (`#OTM-RESULT`). Perfil aplicado em `$ST/smart/last`. Categoria **Geral**: uma
  **ação única**, `smart.auto` ("Otimizador inteligente"), mais um botão de mesmo
  nome na Home dos dois painéis. `pack.sh smart [<acao>]` delega (sem argumento
  roda `auto`). **Debloat não faz parte do `auto`**: remover app de fábrica é decisão
  do usuário e tem categoria própria (ver abaixo).

  **Medir para provar (`bench`/`compare`).** O `auto` não termina mais em "confie
  em mim": ele mede antes, aplica e mede depois (`so_measure`), dizendo se
  MELHOROU, PIOROU ou ficou ESTÁVEL — e avisa para reverter se piorar. As ações
  `bench [perfil]` (mede → aplica → mede, com 3 amostras de cada) e
  `compare [perfil]` (testa os candidatos — Vulkan x GL e a maior taxa x 90Hz —
  e deixa aplicada a combinação de melhor nota) são as que fecham o ciclo. A
  medição nunca chuta: campo que o aparelho não expõe entra como "desconhecido" e
  a comparação só considera o que foi lido. É o mesmo `so_measure` nos três
  comandos, então `analyze`, `bench` e `compare` falam a mesma língua. No painel
  ficam em `smart.report` (analisar), `smart.decide` (ver o plano), `smart.bench`
  e `smart.compare` — além de `smart.state` (o que está ativo).

### Dispositivos: resolução de tela (`scripts/resolution.sh`)

Categoria **Dispositivos** (grupo próprio, `res.*` no `lib.php`). Reduzir a
resolução **lógica** (não a física) é o ajuste que mais rende FPS em jogo pesado:
menos pixels para a mesma GPU desenhar. `resolution.sh` tem `list` (degraus de
mercado + a resolução de fábrica), `current` (fábrica x override x densidade),
`apply <WxH>`, `custom <W>x<H>` e `reset` (volta à de fábrica). A **resolução de
fábrica é guardada antes do primeiro override** (`$ST/resolution/factory`), então
o `reset` volta ao valor certo mesmo depois de vários testes — não ao "padrão de
mercado". A validação recusa valores absurdos ("pequena demais"/"grande demais"/
formato inválido) em vez de aceitar qualquer coisa. `auto` desce para 1080p só em
tela QHD; em tela pequena não mexe (já renderiza pouco). É tudo `wm size` (não
precisa de root). No painel flutuante a resolução também aparece na aba **Motor**,
porque é um ajuste para mexer no meio da partida.

### Vitalidade: cuidar para durar (`scripts/vitality.sh`)

O pack inteiro "tira o freio" (mais FPS, mais desempenho) e tinha **dezenas** de ações
de energia todas na mesma direção: `perm.battery` desliga a economia, `game.keepalive`
tira a restrição de bateria, `doze.off` desliga o sono profundo, `keep.on` mantém app
vivo. Nada olhava para o **longo prazo**. `vitality.sh` é o único que olha — e faz o
oposto: mede a saúde real da bateria, reduz agressão e avisa hábitos que desgastam.
Nada aqui força o celular.

**O dado que faltava.** O Android expõe `charge_full` (capacidade atual) e
`charge_full_design` (de fábrica) em `/sys/class/power_supply/*/`. A razão entre os
dois é a **saúde real** da bateria — o número que o Android esconde. O pack nunca leu
isso. `cycle_count` (ciclos) também é lido. Leitura **em camadas**: tenta `battery`,
`bms`, `Battery`, `main`; o que não existir devolve vazio. Se não der para ler, o
painel diz "sem leitura" — nunca inventa número.

**Nota de vitalidade 0..100.** Base = saúde. Penaliza ciclos (>800: −12; >400: −6) e
calor (≥43 °C: −10; ≥40 °C: −5). Sem leitura de saúde, a nota é vazia (não existe
nota falsa). Rótulos: excelente ≥90, saudável ≥75, atenção ≥60, desgastada ≥40,
troque a bateria abaixo disso.

**Modo longevidade** (`care on`) — reduz agressão, tudo reaproveitando ajustes que o
pack já usa, mas a favor da durabilidade: doze afinado (`device_idle_constants` +
`deviceidle enable light/deep`), tela em **60 Hz** (`peak_refresh_rate`/
`min_refresh_rate` — taxa alta é um dos maiores consumos contínuos), scans de
Wi-Fi/BLE "sempre disponível" desligados e a **economia de energia do sistema
LIGADA** (`adaptive_battery_management_enabled 1` — o pack a desligava em
`perm_battery`). `care off` volta ao padrão. Reversão no escopo `vitality`.

**Guardião de carga** (`guard`, e o `tick` no poll) — não muda nada, só mede e avisa:
conta cargas **acima de 80%** e cargas **com calor** (≥43 °C na tomada). Calor + carga
é o que mais encurta a vida da célula. Avisa **uma vez por ciclo**: uma flag em disco
(`f_high80`, `f_hotcharge`) só dispara de novo depois que o valor volta ao normal
(≤75%, ≤38 °C). Sem root não dá para limitar a carga em 80% — mas dá para saber
quando você passou.

**Arquitetura.** Igual à do poll do painel: **tick idempotente**, sem processo
residente nem serviço em segundo plano (é o que trava aparelho). `panel-state.sh` e
`panel-stats.sh` chamam `vitality.sh tick` no poll de 4 s e publicam `vital_health`,
`vital_cycles`, `vital_temp`, `vital_score`, `vital_care`, `vital_w80`, `vital_whot`,
`vital_alert`. O JS `renderVital()` desenha o cockpit: nota grande, selo colorido
(bom/atenção/ruim), barra com marca em 75%, saúde/ciclos/temperatura/cargas altas.

**Ações** (`lib.php`, grupo `Vitalidade`): `vital.optimize` (o botão único "Otimizar
saúde do telefone": liga o cuidado e mostra o diagnóstico numa tela só; `careful` +
confirmação), `vital.diag` (só leitura), `vital.care_on` (`careful`), `vital.care_off`
(`safe`), `vital.care_status`, `vital.guard`, `vital.status`. `vitality.sh` está na
whitelist.

**Uma só linha de resultado.** `vital.optimize` reaproveita `_care_apply` (o mesmo
código do `care on`, sem duplicar) e chama `cmd_diag`, mas o `#OTM-RESULT` sai UMA
vez, no fim do script — o painel lê a primeira e o `grep -c` do teste trava isso.

**Testes:** `t_vitality` (`tests/run.sh`) cobre o motor sem aparelho — via
`OTM_VIT_HEALTH/CYCLES/TEMP/LEVEL/STATUS` (leituras injetadas) e `OTM_MODE=direct`.
Verifica: nota por saúde, penalidade de ciclos e calor, ausência de nota sem leitura,
falha segura (lixo/999% → vazio, sem erro de shell), guardião (avisa uma vez, reavisa
no ciclo seguinte, conta), `care on` aplicando de verdade (stubs de `settings`) e
reversível, `diag` com `applies=0` (só leitura), registro das ações, remoção do que
forçava, e paridade web↔app do card e do JS.

**Relação com o Perfil de Desempenho:** são cards SEPARADOS e independentes.
O card "Perfil de Desempenho" (`data-perfmode-card`, ações `turbo.perfmode_on/off`)
continua existindo e é para quem QUER o máximo (mais FPS, esquenta mais). O card
"Saúde do telefone" (`data-vital-card`, grupo `Vitalidade`) é o oposto: cuida para
durar. Nenhum dos dois substitui o outro — e **nada do pack original pode ser
removido** (há guarda de regressão em `t_vitality`).

### Bug histórico: handler global de `.opt` (ainda vale como regra)

O card antigo de Perfil de Desempenho ficou "morto" porque `document.querySelectorAll(".opt")`
ligava o clique de **todos** os `.opt` da página, sobrescrevendo o `onclick` dos que têm
handler próprio. Regra: o handler global é escopado a `.card-choice .opt`, e o visual de
selecionado é o `aria-pressed="true"` (não existe CSS para `.active`). Botão que só chama
`toast()` e não chama `doRun` é enfeite.
- **Clean 2.0** (`scripts/clean.sh`, na whitelist do `lib.php`): motor único de
  limpeza em fases, com verificação real. `scan` só lê (RAM, espaço em `/data`, cache
  por app com root); `now fundo` libera RAM (encerra o 2º plano via `otm_bg_kill`
  poupando o jogo/protegidos, poda cache com `otm_cache_trim`, `am kill-all` e
  `otm_drop_caches`); `now suave` (padrão) soma a suavização **sem root** (animações
  0x, `disable_window_blurs`, `accessibility_reduce_transparency`, doze mais rápido,
  sem scan Wi-Fi). Só existem essas duas fases: `fundo` e `suave` (a antiga `normal`,
  que exigia root, foi removida).
  `status` mostra o estado; `off` desfaz a suavização (settings do escopo próprio
  `~/.packotm/undo/clean.sh` + os módulos do deep-tune). Estado em `$ST/clean/applied`.
  O `clean`/`clean_scan` do `adb-tweaks.sh` delegam para cá (o antigo `clean` inline e o grupo `aot` foram
  removidos; o `clean.deep` saiu junto com as ações root). Categoria **Desempenho**
  (`clean`, `clean.scan`, `clean.undo`).
- Configurações do painel (engrenagem): permissões, tema, cor de destaque, fonte,
  DPI e som ficam em `localStorage` (`otm-theme`/`otm-accent`/`otm-font`/
  `otm-scale`/`otm-sound`) e são aplicados antes do resto do JS (`initAppearance`).
  A ação de registro `appearance` (`"ui" => "appearance"` em `lib.php`) abre o
  modal; por não ter `argv`, `PackBridge` a ignora (o painel trata a UI). Ligar o
  som usa `ativando.mp3`; conectar usa o áudio de pareamento. O DPI é
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
  mostra "—" + o aviso `#usageHint`; nada é inventado. O atalho para liberar o
  uso é o `#btnUsagePerm` da Home (`openUsageSettings`); ele **saiu** de Configs
  → Permissões (a engrenagem ficou só com o botão do pack).
- Home (painel): as métricas ficam em **dois grupos** (`.stat-group` + `.glabel`):
  *Sistema agora* (RAM/CPU/bateria/armazenamento/tela/tempo ligado) e *Uso do
  aparelho* (`fg`/`usage`). O grupo de uso traz o selo `#usageNeed` e o botão
  `#btnUsagePerm` (→ `openUsageSettings`), que somem quando `usage_granted` é true.
  O botão `#btnRefreshStats` fica no cabeçalho (`.boxhead`) e o `#liveBadge` mostra
  "ao vivo · há N s". Tudo é escondido/mostrado por `renderStats` (não há `esc()`).
- Permissões/segundo plano: a engrenagem tem **um botão só**, "Conceder
  permissões ao pack" (`setPermApp` → `perm.app` → `adb-tweaks.sh perm_app`).
  Os botões "Aos Free Fire", "Ao meu jogo", "Bateria sem economia" e "Acesso a
  dados de uso" **saíram** das Configurações a pedido: as ações
  (`perm_ff|perm_game|perm_battery|perm_all`) continuam no catálogo/`lib.php`
  para quem chamar por elas. Os grupos seguem reversíveis (isenção do Doze via
  `cmd deviceidle whitelist`, `appops` de `RUN_IN_BACKGROUND`/
  `RUN_ANY_IN_BACKGROUND`/`WAKE_LOCK`/`START_FOREGROUND`, economia de
  bateria/App Standby desligadas). No lado nativo, `Permissions.kt` cuida só do
  que o app pede sozinho (canal de notificação, `POST_NOTIFICATIONS` no Android
  13+ e `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`), sem bloquear o painel.
  `PanelActivity.injectHeaderButtons` garante o botão "Conectar" após cada carga
  da página. O teste `t_perm_script` cobra que os quatro botões **não** voltem.
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
  As fontes são **empacotadas** (`.ttf` em `web/assets/fonts/` e no espelho
  `app/src/main/assets/panel/assets/fonts/`), nunca de CDN: sem internet a fonte
  continua valendo. Todas são OFL-1.1, então o crédito viaja junto do arquivo em
  `assets/fonts/CREDITS.md` (nos dois lados). O painel flutuante não tem WebView:
  ele carrega o mesmo `.ttf` com `Typeface.createFromAsset` pelo mapa
  `FONT_FILES` do `OverlayService` (chave do `FONTS` → arquivo), com cache e
  fallback para a fonte do sistema.
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
# toolchain em /workspace/project/.toolchain (JDK + SDK 34 + Gradle 8.7)
# o wrapper é o da RAIZ do repo (android/gradlew não tem o jar do wrapper)
export JAVA_HOME=/workspace/project/.toolchain/jdk
export ANDROID_HOME=/workspace/android-sdk          # ver local.properties (sdk.dir)
export GRADLE_USER_HOME=/workspace/project/.toolchain/gradle-home
./gradlew :app:assembleRelease --no-daemon
# saída: app/build/outputs/apk/release/app-release.apk (já assinado)
```

O build demora ~1 min com o cache do Gradle quente; rode em background
(`nohup ... > /tmp/build.log 2>&1 &`) para não bater no timeout do terminal.
Antes de buildar, espelhe os scripts (`cp scripts/*.sh
app/src/main/assets/pack/scripts/` e `cp VERSION app/src/main/assets/pack/VERSION`),
senão o APK sai com o pack velho.

Conferir o que ficou dentro do APK (não confie só no build verde):

```sh
python3 -c "import zipfile; z=zipfile.ZipFile('app/build/outputs/apk/release/app-release.apk');
print(z.read('assets/pack/VERSION').decode()); print(sorted(n for n in z.namelist() if 'panel' in n)[:5])"
# apksigner/aapt2 são scripts que precisam de `java` no PATH
export PATH=$JAVA_HOME/bin:$PATH
$ANDROID_HOME/build-tools/34.0.0/apksigner verify --print-certs <apk>
$ANDROID_HOME/build-tools/34.0.0/aapt2 dump badging <apk> | grep ^package
```

Assinatura (atualizar por cima, sem desinstalar): o `release` usa a keystore fixa
`keystore/otm-release.jks` (alias `otm`, senha `00deUdia`), configurada em
`app/build.gradle.kts`. A mesma chave assina toda versão, então o Android
aceita instalar a nova por cima da anterior. Não troque essa keystore sem avisar:
trocar a chave quebra a atualização e obriga a desinstalar. O `zipalign`/`apksigner`
manuais não são mais necessários (o Gradle assina no `assembleRelease`).

A versão do app acompanha `VERSION` (`versionName`/`versionCode` em
`app/build.gradle.kts`). Nome de exibição: "Trix". O APK é
publicado em `releases/` e em `serve/` (ambos ignoram `*.apk` no git; os
`.sha256` **são** versionados).

**Marca (nome/cor/logo).** A marca é "Trix" e a cor de destaque padrão é
**prata** (`#C7CCD6`); o laranja continua na paleta, só deixou de ser o padrão.
Ao trocar a marca, o mesmo valor aparece em vários lugares que precisam ficar
em sincronia: `strings.xml` (`app_name`), os `<title>` de `web/index.php`,
`web/login.php`, `app/src/main/assets/panel/index.html`,
`assets/panel/login.html` e `public/login.html`, o `setContentTitle` em
`OverlayService.kt`/`Permissions.kt` e a const `OtmExec.accent` (cor padrão do
painel flutuante). A cor padrão vive no `:root` dos **dois** painéis
(`--accent`/`--accent-ink`/`--ring`), no `themes.xml` (`colorPrimary`) e no
fallback `col()` do `OverlayService.kt`; o "accent" salvo usa `"prata"` como
padrão (`localStorage.getItem("otm-accent") || "prata"`). Cuidado ao editar o
bloco `:root`: ele tem um **comentário CSS de várias linhas** logo acima — um
`*/` sobrando quebra todo o CSS abaixo (o painel fica sem estilo e os testes não
pegam isso). Os ícones são gerados a partir da imagem com Pillow: os `mipmap-*`
levam a imagem inteira (quadrado e redondo, com máscara circular) e o
`drawable-xxxhdpi/ic_launcher_foreground.png` (432×432) leva **só o emblema**,
recortado pelo bbox do conteúdo (`limiar < 210`) e centralizado na safe zone de
66% — o fundo claro do logo preenche o resto, e o `ic_launcher_background` é
`#F8F6F1` (a cor do fundo da arte). O `monochrome` aponta para
`ic_launcher_monochrome.png` (silhueta com alfa): apontá-lo para o foreground
deixa um bloco sólido no tema monocromático.

Publicar o download: o repo **público** é `whesleydev/Pack-de-otimizacao`
(o `00-Otimizacao` é privado, então link de asset lá não abre para o usuário).
Crie a release pela API com o token do remote `origin`/`otm-push` (tem escopo
`repo` e admin no repo; o `GITHUB_TOKEN` do ambiente é de integração e devolve
`Resource not accessible by integration` na API de releases):

```sh
TOK=$(git remote get-url origin | sed -E 's#https://([^@]+)@.*#\1#')
# POST /repos/whesleydev/Pack-de-otimizacao/releases  {tag_name, name, body}
# POST https://uploads.github.com/repos/.../releases/<id>/assets?name=<arquivo>  (binário)
```

**O `GITHUB_TOKEN` do ambiente é de GitHub App e não escreve.** Ele lê a API
(`/user` responde `login: whesleydev`, `permissions.admin: true`) e os *checks*
de CI, mas `git push` devolve `403 Permission to ... denied` e
`POST /pulls` devolve `403` — não perca tempo com ele. Para **escrever** (push,
PR, release), use um PAT clássico com escopo `repo` (`ghp_...`) no lugar da URL:
`git remote set-url origin https://<token>@github.com/whesleydev/Pack-de-otimizacao.git`,
faça o push e **volte a URL sem token** (`git remote set-url origin
https://github.com/whesleydev/Pack-de-otimizacao.git`) para não deixar o segredo
no `.git/config`. O mesmo vale para o `otm-push`. A ferramenta `create_pr`
também usa o token do ambiente (falha com 403): crie o PR com
`POST /repos/<owner>/<repo>/pulls` via `urllib`/`curl` com o PAT.

Se a tag **já existir** (você já fez `git push origin <tag>`), não mande
`target_commitish` no POST: a API responde `422 Validation Failed
(field: target_commitish)`. A release então aponta para onde a tag aponta.
A release cria a tag no `target_commitish` no momento do POST. Se você criar a
release **antes** de terminar os commits, a tag fica num commit velho — mova com
`PATCH /repos/.../git/refs/tags/<tag>` com `{"sha": "<sha completo>", "force": true}`.
O link `releases/latest/download/<arquivo>` só funciona se for a release mais
recente; para citar uma versão fixa, use `releases/download/<tag>/<arquivo>`.
Confirme o link **baixando** o arquivo e comparando o SHA-256 (não confie só no
`201` do upload).

O CI (`.github/workflows/build.yml`, job `plugins`) **cria a release sozinho**
quando a tag `v*` chega: usa o `CHANGELOG.md` como corpo e sobe só os `.zip` de
`releases/` + o `SHA256SUMS.txt`. O **APK não é publicado pelo CI** — depois do
run ficar verde, anexe o APK e o `.sha256` no release já criado
(`POST https://uploads.github.com/.../releases/<id>/assets?name=<arquivo>`) e
renomeie a release para o padrão `"<versão> — <resumo>"` (o CI a cria com o nome
igual à tag). **Anexar o `.sha256` exige `Content-Type: text/plain`** — o
`--data-binary` puro manda `application/x-www-form-urlencoded` e a API responde
`422 content_type can't be ...`. **Mover a tag reescreve o corpo**: se você
empurrar mais um commit para a branch e mover a tag (o CI roda de novo no novo
SHA), ele sobrescreve o `body` e o `name` com o `CHANGELOG.md` inteiro — refaça o
`PATCH` do corpo depois que **esse** run terminar.
O `body_path: CHANGELOG.md` manda o **arquivo inteiro** (todas as
versões, ~60 KB) — o padrão das releases boas é só a seção da versão: corte com
`re.findall(r'^## \[<versão>\].*?(?=^## \[)', changelog, re.S|re.M)` e mande por
`PATCH /repos/.../releases/<id>` junto do `name` novo. Fluxo completo do release:
bump `VERSION`/`versionCode` → `git tag vX.Y.Z && git push origin vX.Y.Z` →
esperar o CI → anexar o APK → ajustar nome/corpo → atualizar `serve/index.html` e
os `.sha256` de `releases/` e `serve/`.

