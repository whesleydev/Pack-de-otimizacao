# Pack de Otimização

> 🚀 **Novo por aqui?** Comece pelo **[COMECE AQUI](COMECE-AQUI.md)** — guia rápido,
> sem jargão, para deixar o celular mais rápido em 5 minutos.

Pack de otimização para Android em **4 níveis** — de copiar-e-colar no Brevent até um
plugin com interface web no AxManager. Reúne comandos ADB, perfis de sensibilidade para
**Free Fire** e um sistema de **snapshot** para reverter tudo quando quiser.

> ⚠️ **Aviso:** alterações em `settings`, `prop` e `pm` podem afetar o comportamento do
> aparelho. **Salve um snapshot antes** (`sh scripts/snapshot.sh save`) e use
> `restore_all` para reverter. Ajustes de toque variam por modelo/ROM — teste no treino.

📦 **Baixar pronto:** os plugins dos níveis 3 e 4 estão na
[Release v1.1.0](https://github.com/whesleydev/Pack-de-otimizacao/releases/latest).

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
| Fluidez | animações 0, toque sem atraso, Hz máximo (estilo Sam Helper) |
| Tuning por jogo | resolução (downscale), teto de FPS e engine — **só no app**, sem mexer no telefone |
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
freezer freezer_off freeze_apps unfreeze_apps dnd dnd_off screen touch fluidez
game_tune clean aot restore_all`

### `scripts/game-per-app.sh` (tuning por jogo)

```sh
sh scripts/game-per-app.sh list
sh scripts/game-per-app.sh apply com.dts.freefireth fps       # 0.9
sh scripts/game-per-app.sh apply com.dts.freefireth balanced  # 0.75
sh scripts/game-per-app.sh apply com.dts.freefireth max       # 0.5
sh scripts/game-per-app.sh custom com.dts.freefireth 0.75 60  # downscale + teto FPS
sh scripts/game-per-app.sh show com.dts.freefireth
sh scripts/game-per-app.sh reset com.dts.freefireth
sh scripts/game-per-app.sh reset-all
```

> Mexe só no jogo (Game Mode interventions, Android 12+). Reinicie o jogo depois.

### `scripts/deep-tune.sh` (otimizações profundas)

Vai além dos `settings`: mexe em **sysfs (kernel), GPU, térmico, I/O e rede**. Tudo
reversível — cada valor antigo é guardado, e cada módulo tem seu próprio "off".

```sh
sh scripts/deep-tune.sh detect            # o que o aparelho suporta
sh scripts/deep-tune.sh angle add com.dts.freefireth   # ANGLE/Vulkan (sem root) ★
sh scripts/deep-tune.sh freq on           # frequência CPU/GPU no topo (root)
sh scripts/deep-tune.sh io on             # scheduler + fstrim (root)
sh scripts/deep-tune.sh mem on            # MGLRU + zRAM + KSM (root)
sh scripts/deep-tune.sh net on            # TCP BBR + fq_codel (root)
sh scripts/deep-tune.sh debloat on        # appops + buckets (sem root)
sh scripts/deep-tune.sh gaming on com.dts.freefireth  # MODO JOGO TURBO (tudo junto)
sh scripts/deep-tune.sh thermal on        # ⚠️ afrouxa o limite térmico (root, esquenta)
sh scripts/deep-tune.sh restore           # desfaz tudo
```

> ⚠️ `thermal` e `gaming` afrouxam a proteção térmica: mais FPS sustentado, **mais calor**.
> Exige confirmação explícita (`THERMAL_OK=1`) e tem **trava automática**: se a
> temperatura passar de 45 °C (`THERMAL_MAX_C`) ou o aparelho estiver carregando
> (`THERMAL_STOP_CHARGING=1`), o módulo se reverte sozinho.

### `scripts/bench.sh` (prova de resultado)

Mede o **antes e depois** de verdade, em vez de prometer número:

```sh
sh scripts/bench.sh save antes             # linha de base (RAM, temp, CPU, refresh)
sh scripts/bench.sh app com.dts.freefireth  # tempo de abertura (ms)
# ... aplica o pack ...
sh scripts/bench.sh run depois
sh scripts/bench.sh report antes depois    # relatório comparativo em Markdown
```

### `scripts/device-profile.sh` (compatibilidade)

Diz o que o seu aparelho suporta, por família de SoC:

```sh
sh scripts/device-profile.sh               # relatório
sh scripts/device-profile.sh save          # salva em ~/.packotm/perfil.txt
```

Veja [`docs/COMPATIBILIDADE.md`](docs/COMPATIBILIDADE.md).

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
sh scripts/deep-tune.sh restore        # desfaz as otimizações profundas
sh scripts/snapshot.sh restore latest  # volta ao snapshot que você salvou
```

O `restore_all` desfaz os `settings`, desliga o `cached_apps_freezer` e solta o Doze.
Apps congelados com `freeze_apps` são liberados por `unfreeze_apps`. O `snapshot restore`
devolve o estado exato salvo antes — inclusive coisas fora do pack.

Cada módulo profundo também tem o seu "off" individual (`deep-tune.sh freq off`,
`deep-tune.sh angle reset`, ...), então dá para desligar só o que incomodou.

---

## Auditoria

O pack é **honesto por princípio**: onde um comando é placebo, dependente de aparelho ou
arriscado, isso está declarado. O documento [`docs/AUDITORIA.md`](docs/AUDITORIA.md)
traz, para cada módulo: comando exato, privilégio exigido, ganho esperado, risco e
reversão — pronto para revisão técnica externa.

---

## Qualidade e garantias

```sh
sh tests/run.sh                # testes automatizados (stubs, apply->restore)
sh scripts/check-secrets.sh    # procura credenciais nos arquivos versionados
sh scripts/check-licenses.sh   # status de licença dos módulos de terceiros
```

O CI (`.github/workflows/build.yml`) roda isso em cada push/PR: sintaxe, shellcheck,
testes, segredos e licenças. A release publica `SHA256SUMS.txt` e usa o
[`CHANGELOG.md`](CHANGELOG.md) como descrição.

---

## Estrutura

```
COMECE-AQUI.md    guia rapido para quem esta comecando
CHANGELOG.md      histórico de mudanças
VERSION           versão atual
THIRD-PARTY-NOTICES.md  licenças dos módulos de terceiros
nivel-1-txt/      arquivos .txt para copiar e colar no Brevent
nivel-2-sh/       entry point sh (Shizuku/root)
scripts/
  common.sh       biblioteca (transporte adb/rish/su/local + backup)
  adb-tweaks.sh   biblioteca de comandos ADB
  deep-tune.sh    otimizações profundas (sysfs/kernel/GPU), reversível
  ff-touch.sh     perfis de sensibilidade
  game-per-app.sh tuning por jogo (resolução/FPS, só no app)
  bench.sh        benchmark antes/depois (prova de resultado)
  device-profile.sh perfil por SoC (compatibilidade)
  snapshot.sh     salvar / reverter o estado do aparelho
  menu.sh         menu unificado
  build-modules.sh empacota módulos e plugins
  check-secrets.sh / check-licenses.sh  portões de qualidade
tests/run.sh      testes automatizados
plugins/
  01-service-loop/  plugin AxManager com loop em background
  02-webui-control/ plugin AxManager configurável com WebUI
docs/             tutorial, auditoria, compatibilidade, segurança, produto
modules/          módulos Magisk/KernelSU/AxManager do pack
releases/         zips publicados (via GitHub Releases)
```

---

## Créditos

Os módulos em `modules/` são de terceiros e mantêm a autoria original. **Importante:**
a maioria **não tem licença declarada** — não redistribua nem venda sem permissão do
autor. Status completo em [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

- **NexaCore** — Enrique Brach
- **WS7_OFF7** — WS7_OFF7
- **VeuLexier** — @Reiieja
- **BEN UNIVERSAL** — trhieuhoc
- demais módulos: ver `module.prop` de cada um

Os scripts em `scripts/` (comandos ADB, perfis de toque e menu) fazem parte deste pack.

## Licença

MIT — veja [`LICENSE`](LICENSE). Os módulos de terceiros mantêm suas próprias licenças
(quando existem).