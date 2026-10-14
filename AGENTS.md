# AGENTS.md — Pack de Otimização

Guia para agentes que trabalharem neste repositório.

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
  são validados por tipo (pkg/host/int/float). Nunca passe input do usuário direto para o shell.
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
