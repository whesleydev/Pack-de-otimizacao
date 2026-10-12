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
```

## Comandos

```sh
sh tests/run.sh                 # testes (stubs de settings/cmd/am/getprop/su) — deve dar 0 falhas
sh scripts/build-modules.sh     # empacota 00 Otimizações/Modulos/ em releases/*.zip
sh scripts/build-plugins.sh     # empacota Plugins AxManager/ (Nossos + OSS) em releases/*.zip
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

- Revogar o token exposto no histórico e purgar o `apps_otm.zip` (`docs/SEGURANCA.md`).
- Benchmark real em aparelhos e preencher `docs/COMPATIBILIDADE.md`.
- Infra de venda/suporte (`docs/PRODUTO.md`, `docs/ROADMAP.md`).
