# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).
Versionamento [SemVer](https://semver.org/lang/pt-BR/).

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
