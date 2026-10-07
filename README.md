# Pack de Otimização

Pack de otimização para Android em **4 níveis** — de copiar-e-colar no Brevent até um
plugin com interface web no AxManager. Reúne comandos ADB, perfis de sensibilidade para
**Free Fire** e um sistema de **snapshot** para reverter tudo quando quiser.

> ⚠️ **Aviso:** alterações em `settings`, `prop` e `pm` podem afetar o comportamento do
> aparelho. **Salve um snapshot antes** (`sh scripts/snapshot.sh save`) e use
> `restore_all` para reverter. Ajustes de toque variam por modelo/ROM — teste no treino.

📖 **Tutorial completo:** [`docs/tutorial.md`](docs/tutorial.md) — explica cada nível e
o que cada comando faz.

---

## Os 4 níveis

| Nível | O que é | Precisa de | Pasta |
|-------|---------|-----------|-------|
| **1** | Arquivos `.txt` para copiar e colar | Brevent | [`nivel-1-txt/`](nivel-1-txt/) |
| **2** | Scripts `sh` (automação) | Shizuku ou root | [`nivel-2-sh/`](nivel-2-sh/) |
| **3** | Plugin AxManager em loop (roda 24h) | gerenciador | [`plugins/01-service-loop/`](plugins/01-service-loop/) |
| **4** | Plugin AxManager configurável com WebUI | gerenciador | [`plugins/02-webui-control/`](plugins/02-webui-control/) |

---

## O que tem no pack

| Área | O que faz |
|------|-----------|
| Performance | animações 0.5x/0, GPU forçada, blur/transparência off |
| Rede | buffers TCP, DNS Cloudflare, Wi-Fi scan off |
| Bateria | Doze e modo economia |
| Jogo | Game Mode performance, downscale, AOT |
| Free Fire | preparar/abrir, fechar apps de fundo |
| Sensibilidade | perfis de toque/mira (balanced, headshot, spray, sniper, speed) |
| Freezer | `cached_apps_freezer` e congelamento de apps — funciona no Brevent |
| Sistema | DND, refresh de tela, limpeza de cache |
| Snapshot | salva o estado atual e reverte a qualquer momento |

A pasta `modules/` guarda os módulos Magisk/KernelSU/AxManager que fazem parte do pack
(origem de cada um nos créditos). A pasta `releases/` é para os zips publicados via
GitHub Releases.

---

## Requisitos

- Android 11+ (a maioria dos tweaks)
- **Um** dos métodos de acesso:
  - PC com **ADB** (depuração sem fio ou USB)
  - **Brevent** (app, sem PC)
  - **Termux** + **Shizuku** (sem PC, com shell privilegiado)
  - **root** (Magisk/KernelSU/APatch)
- `sh` (qualquer shell Android serve)

---

## Início rápido

Clone e entre na pasta:

```sh
git clone https://github.com/whesleydev/Pack-de-otimizacao.git
cd Pack-de-otimizacao
```

### 1. ADB (PC)

```sh
# pareamento sem fio (Android 11+)
adb pair <ip>:<porta-pareamento>
adb connect <ip>:<porta-conexao>

# menu completo
sh scripts/menu.sh

# ou comandos diretos
sh scripts/adb-tweaks.sh all
sh scripts/ff-touch.sh headshot
```

### 2. Brevent (sem PC)

O Brevent já executa comandos `settings`/`pm` internamente. Use os comandos deste pack
na área de shell/execução do Brevent, ou copie os comandos de `scripts/adb-tweaks.sh`
(remova o prefixo de transporte). Detalhes em [`docs/brevent.md`](docs/brevent.md).

### 3. Termux + Shizuku (sem PC)

```sh
pkg install curl
# baixe o rish do Shizuku e deixe no PATH
sh scripts/menu.sh          # detecta o rish automaticamente
```

Detalhes em [`docs/termux-shizuku.md`](docs/termux-shizuku.md).

### 4. Root

```sh
su -c 'sh scripts/adb-tweaks.sh perf'
```

### 5. Plugin AxManager (níveis 3 e 4)

```sh
sh scripts/build-modules.sh
# instale releases/01-service-loop.zip ou releases/02-webui-control.zip
```

---

## Snapshot (salvar / reverter)

Antes de aplicar qualquer coisa, salve o estado atual. Se não gostar, volta com um
comando:

```sh
sh scripts/snapshot.sh save              # salva
sh scripts/snapshot.sh list              # lista
sh scripts/snapshot.sh diff latest       # compara com o atual
sh scripts/snapshot.sh restore latest    # volta tudo
```

---

## Comandos

### `scripts/adb-tweaks.sh`

```sh
sh scripts/adb-tweaks.sh list                 # lista os grupos
sh scripts/adb-tweaks.sh perf                 # um grupo
sh scripts/adb-tweaks.sh perf gpu net         # vários grupos
sh scripts/adb-tweaks.sh all                  # tudo
sh scripts/adb-tweaks.sh touch 110 400 0      # grupo com parâmetros
sh scripts/adb-tweaks.sh raw "settings get global window_animation_scale"
sh scripts/adb-tweaks.sh restore_all          # reverte tudo
```

Grupos: `perf perf_max gpu net net_reset wifi battery battery_off game ff ff_open
freezer freezer_off freeze_apps unfreeze_apps dnd dnd_off screen touch fluidez clean aot restore_all`

### `scripts/ff-touch.sh`

```sh
sh scripts/ff-touch.sh list
sh scripts/ff-touch.sh balanced     # geral
sh scripts/ff-touch.sh headshot     # mira rápida
sh scripts/ff-touch.sh spray        # controle de recuo
sh scripts/ff-touch.sh sniper       # mira precisa
sh scripts/ff-touch.sh speed        # máxima reatividade
sh scripts/ff-touch.sh custom 110 350 0 4
sh scripts/ff-touch.sh restore
```

### Forçar modo de execução

Se a detecção automática errar o transporte:

```sh
OTM_MODE=adb sh scripts/menu.sh     # adb | rish | su | local
OTM_NO_COLOR=1 sh scripts/menu.sh   # sem cores
```

---

## Restaurar

Há duas formas de reverter:

```sh
sh scripts/adb-tweaks.sh restore_all   # desfaz os tweaks do pack
sh scripts/snapshot.sh restore latest  # volta ao snapshot que você salvou
```

O `restore_all` desfaz os `settings`, desliga o `cached_apps_freezer` e solta o Doze.
Apps congelados com `freeze_apps` são liberados por `unfreeze_apps`. O `snapshot restore`
devolve o estado exato salvo antes — inclusive coisas fora do pack.

---

## Estrutura

```
nivel-1-txt/      arquivos .txt para copiar e colar no Brevent
nivel-2-sh/       entry point sh (Shizuku/root)
scripts/
  common.sh       biblioteca (transporte adb/rish/su/local + backup)
  adb-tweaks.sh   biblioteca de comandos ADB
  ff-touch.sh     perfis de sensibilidade
  snapshot.sh     salvar / reverter o estado do aparelho
  menu.sh         menu unificado
  build-modules.sh empacota módulos e plugins
plugins/
  01-service-loop/  plugin AxManager com loop em background
  02-webui-control/ plugin AxManager configurável com WebUI
docs/             tutorial, guias por método (brevent, termux-shizuku)
modules/          módulos Magisk/KernelSU/AxManager do pack
releases/         zips publicados (via GitHub Releases)
```

---

## Créditos

Os módulos em `modules/` são de terceiros e mantêm a autoria original:

- **NexaCore** — Enrique Brach
- **WS7_OFF7** — WS7_OFF7
- **VeuLexier** — @Reiieja
- **BEN UNIVERSAL** — trhieuhoc
- demais módulos: ver `module.prop` de cada um

Os scripts em `scripts/` (comandos ADB, perfis de toque e menu) fazem parte deste pack.

## Licença

MIT — veja [`LICENSE`](LICENSE).