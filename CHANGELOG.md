# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento [SemVer](https://semver.org/lang/pt-BR/).

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
