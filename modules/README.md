# Módulos do pack

Módulos para **Magisk / KernelSU / APatch / AxManager**. Cada pasta é a fonte do módulo
(`module.prop`, `customize.sh`, `service.sh`, `action.sh`, `webroot/`). Os zips de
instalação são gerados por `scripts/build-modules.sh` e publicados em Releases.

## Lista

| Pasta | Nome | Versão | Autor |
|-------|------|--------|-------|
| `Astrax` | Astrax | v2-Eclipse | t.me/BillyNutDemarco |
| `AxVision_Hawk` | AxVision: Hawk | v1052-180926-S | @ReiiEja |
| `BEN_UNIVERSAL` | BEN UNIVERSAL | v4.6 | trhieuhoc |
| `CPU_GPU_Web_Panel_Itachi_Edition` | CPU & GPU Web Panel (Itachi Edition) | v5.0 | Jhonzxit |
| `Celestial-Game-Opt` | Celestial Game Opt | 3.4 | Kzyoo |
| `Game_Scale` | Game Scale | v1.4.1 | Philip Nghia |
| `Gms_Tweaker` | Gms Tweaker | 0.1 (alpha) | ERINE 433 |
| `Kang` | Kang | 8.5.0 | @illumi |
| `MOs_Premium_v15_Full-Stack_FPS_Engine` | MOs Premium v15 — Full-Stack FPS Engine | v15.0 | jogominecraft1234 |
| `NOVA_TOUCH` | NOVA TOUCH | 1.0 | trhieuhoc |
| `NexaCore` | NexaCore | 2.0.0 | Enrique Brach |
| `Phoenix` | Phoenix | v3.0 | By_Rafael_System |
| `VOID_BATTERY` | VOID BATTERY | v9.1 | VOID PERF |
| `VOID_TOUCH_Ultra` | VOID TOUCH Ultra | v5.1.0 | VOID DEV |
| `VeuLexier` | VeuLexier | V1.7.6-DexOtSmt | @Reiieja |
| `WS7_OFF7` | WS7_OFF7 | 6.0.0 | WS7_OFF7 |

> A autoria de cada módulo pertence aos respectivos autores. Este repositório apenas
> reúne e organiza o pack; o conteúdo dos módulos não é de autoria do mantenedor.

## Instalar

1. Gere os zips:
   ```sh
   sh scripts/build-modules.sh
   ```
2. Copie o `.zip` desejado para o celular.
3. Abra o gerenciador (Magisk / KernelSU / APatch / AxManager) → **Instalar a partir
   do armazenamento** → selecione o zip → reinicie.

## Segurança

Módulos com root executam scripts durante o boot. Instale apenas o que você reconhece e
mantenha backup do boot/DTBO antes de mexer em módulos de sistema agressivos.
