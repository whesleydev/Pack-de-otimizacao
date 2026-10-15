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
  clássicos, tem `obscure`, `mobile_net`, `notif` e `window_tweaks`. Para criar um grupo,
  escreva a função, registre em `GRUPOS` e use `bkp_set`/`bkp_raw` para a reversão.
- `scripts/turbo.sh` — recursos "turbo" sem root que faltavam: `art`/`art-all` (ART por
  app, speed-profile/speed), `dexopt-bg` (bg-dexopt-job), `standby` (App Standby Buckets),
  `hibernate` (estilo Hail: force-stop + set-inactive), `killbg`, `phantom on|off`
  (Phantom Process Killer), `trim` (cmd package trim-caches), `refresh`, `perfmode`
  (modo desempenho fixo) e `telemetry on|off` (logpersist + scans sempre-disponível).
  Tudo registra reversão em `~/.packotm/off.sh` (revertido por `pack.sh restore`).
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
- O catálogo do painel vem de `assets/panel/actions.json` (gerado a partir de
  `web/lib.php`, via `scratch/actions.json`).
- Gerar o painel estático: `scratch/build_panel.py` (injeta a ponte em
  `scratch/panel.html`, o painel renderizado pelo PHP). Gerar ícones:
  `scratch/build_icons.py` (usa `scratch/logo.jpg`).
- Fontes em `android/app/src/main/java/com/otm/pack/`: `PanelActivity`,
  `PackBridge`, `WifiDialog`, `PackAssets` (extrai `assets/pack`/`assets/panel`
  para `filesDir` e copia os scripts para `/data/local/tmp/otm-pack`), `ShellRunner` + `ShizukuRunner` + `AdbRunner`, `SoundPlayer`,
  `SelfSignedCert`.
- AIDL oficial do Shizuku em `android/app/src/main/aidl/moe/shizuku/server/`.
- Assets: `assets/pack` (scripts/comandos), `assets/panel` (painel + catálogo) e
  `assets/audio` (avisos de voz).
- Áudio: `SoundPlayer` toca MP3 de `assets/audio` via `MediaPlayer`+`openFd`
  (por isso o APK guarda os MP3 STORED, sem compressão). O botão 🔊/🔇 silencia.
  `PackBridge.soundFor(grupo)` escolhe o som conforme o grupo da ação.

Build local (sem Android Studio):

```sh
# toolchain em /workspace/project/.toolchain (JDK 21 + SDK 34 + Gradle 8.7)
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64
export ANDROID_HOME=/workspace/project/.toolchain/sdk
cd android && GRADLE_USER_HOME=/workspace/project/.toolchain/.gradle \
  ./gradlew :app:assembleRelease
# saída: app/build/outputs/apk/release/app-release-unsigned.apk
# assinar (keystore de debug) + alinhar:
BT=$ANDROID_HOME/build-tools/34.0.0
$BT/zipalign -f 4 app-release-unsigned.apk /tmp/a.apk
$BT/apksigner sign --ks ~/.android/debug.keystore --ks-pass pass:android \
  --key-pass pass:android --ks-key-alias androiddebugkey --out out.apk /tmp/a.apk
```

A versão do app acompanha `VERSION` (`versionName`/`versionCode` em
`android/app/build.gradle.kts`). Nome de exibição: "00 Otimização". O APK é
publicado em `releases/` e em `serve/` (ambos ignoram `*.apk` no git).

