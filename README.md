# Pack de Otimização

> 🚀 **Novo por aqui?** Comece pelo **[COMECE AQUI](COMECE-AQUI.md)** — guia rápido,
> sem jargão, para deixar o celular mais rápido em 5 minutos.
>
> 🌐 **Site completo:** abra **[`index.html`](index.html)** — explica os apps, os 4 níveis,
> os plugins e traz uma **área de comandos** (cache, congelar apps, renderizador
> OpenGL/Vulkan/Skia/ANGLE, RAM, bateria, touch) com botão de copiar. É um só arquivo
> HTML/CSS/JS, sem dependências — funciona offline e dá para publicar no GitHub Pages.
>
> 📱 **Apps para instalar:** guia em **[`Apps/README.md`](Apps/README.md)** (Brevent,
> Shizuku, Termux, AxManager e root).

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

## 🎛️ Menu-mestre (comece por aqui)

Um único comando gerencia **tudo** — não precisa decorar caminho de script:

```sh
sh pack.sh          # abre o menu interativo (ou: sh "00 Otimizações/Scripts SH/run.sh")
sh pack.sh status   # mostra o que já está aplicado no aparelho
sh pack.sh apply    # aplica o conjunto recomendado (sem root)
sh pack.sh restore  # desfaz TUDO de uma vez
```

Pelo menu você chega em todos os módulos: performance, GPU, **DNS/rede (perfis)**,
bateria, Game Mode, Free Fire, RAM, tela, congelar apps, **debloat**, otimizações
profundas (root), perfis de toque, **executar módulos/plugins da pasta**, snapshots e
os builds. Cada opção tem um número; `0` sai.

### 🌐 DNS com perfis (privacidade, anúncios, latência)

A opção **13** abre um submenu de DNS privado (DNS-over-TLS, sem root). Escolha o perfil
que quiser:

| Perfil | Para quê |
|---|---|
| `cloudflare` | privacidade + velocidade |
| `quad9` | privacidade + bloqueio de malware |
| `adguard` | **bloqueio de anúncios** e rastreadores |
| `adguard-family` | anúncios + conteúdo adulto |
| `cloudflare-family` | família (conteúdo adulto) |
| `mullvad` | privacidade (sem registro) |
| `dnsforge` | bloqueio de anúncios (sem log) |
| `google` | compatibilidade máxima |
| `gaming` | **baixa latência** p/ jogos (+ buffers TCP + Wi-Fi scan off) |
| `custom <host>` | qualquer hostname DoT seu |
| `off` / `auto` | volta o DNS automático |

Pela linha de comando: `sh pack.sh dns adguard` · `sh pack.sh dns gaming` · `sh pack.sh dns off`.

### 🧩 Executar os módulos e plugins da pasta

A opção **80** lista tudo que já vem no pack e executa na hora:

```sh
sh pack.sh modules list              # lista módulos (Modulos/) e plugins (Plugins AxManager/)
sh pack.sh modules run WS7_OFF7      # executa a ação principal do módulo
sh pack.sh modules info 06-freezer   # vê os scripts disponíveis
sh pack.sh modules action 06-freezer uninstall.sh   # roda um script específico
```

> ⚠️ `run` executa o script avulso no shell atual. Para rodar em segundo plano, no boot
> ou com WebUI, **instale** o módulo no gerenciador (Magisk/KernelSU/APatch/AxManager).

> 💡 O `run.sh` do nível 2 é só um atalho para esse mesmo menu — os dois dão no mesmo lugar.

---

## 🖥️ Painel web — 00deUdia Otimizações (PHP)

Além do menu de terminal, o pack tem o painel **00deUdia Otimizações**, feito em **PHP**:
o menu e os cards são renderizados no servidor. Visual **clean**, com paleta própria
(tinta quente + laranja), **tema claro/escuro** (segue o sistema e dá pra trocar no botão ◐)
e **responsivo de verdade** (gaveta lateral no celular). Um comando sobe o servidor e te dá
uma URL (com token) para abrir no PC ou no celular, na mesma rede Wi-Fi:

```sh
sh main.sh              # abre o menu principal (baixar full, subir servidor, abrir painel)
sh main.sh web start    # sobe o painel e mostra a URL com token
sh main.sh web url      # só imprime a URL
sh main.sh web stop     # para o servidor
sh main.sh baixar       # baixa os recursos FULL do pack (código + módulos + plugins)
```

No painel você tem, com botões (e visual):

| Categoria | O que dá pra fazer |
|---|---|
| **Rápido** | aplicar o recomendado, reverter tudo, salvar/ver/comparar/restaurar snapshot |
| **DNS** | perfis (privacidade, **bloqueio de anúncios**, família, **latência/gaming**) ou um host seu |
| **RAM / Limpeza** | perfil padrão/gaming, limpar cache e RAM, limpar dexopt |
| **Renderizador** | trocar o motor: **OpenGL, SkiaGL, Skia Vulkan**, forçar GPU |
| **Por app / jogo** | escolher um app/jogo e usar **ANGLE (Vulkan)**, modo performance, **reduzir resolução (FPS)** ou resetar |
| **Touch / Free Fire** | perfis balanced/headshot/spray/sniper/speed, ajuste fino, abrir o jogo |
| **Performance** | animações, fluidez, tela/refresh, DND, bateria |
| **Wi-Fi e rede** | scan de Wi-Fi, buffers TCP/DNS, reset de rede |
| **Congelar apps** | congelar/descongelar apps de fundo |
| **Debloat** | ⚠️ perfis leve/médio/pesado + **por app** (desativar, reativar, desinstalar, reinstalar, restringir) |
| **Profundas (root)** | frequência, I/O, memória, rede BBR, latência, modo turbo, térmico |
| **Extremos (root)** | VM/kernel de memória, escalonador/EAS, GPU extrema, núcleos, input boost, idle, BBR2, zRAM zstd, kernel, display, Dalvik e **⚡ modo extremo (tudo)** |
| **Avançado (sem root)** | ajustes obscuros (standby/Doze), rede móvel, notificações e modo imersivo |
| **Diagnóstico** | perfil do aparelho (SoC/GPU), temperatura, DNS atual, benchmark antes/depois |
| **Módulos** | executar os complementos do pack |

Cada cartão tem um botão **?** que explica, em linguagem simples, o que a opção faz e como
reverter. O visual é **clean** com **efeito de vidro**, **tema claro/escuro** e o menu
lateral acompanha a rolagem no desktop (no celular vira uma gaveta).

**Segurança:** o painel só executa scripts de uma **lista branca** e valida cada
parâmetro (nunca recebe comando cru). O acesso é por **token** (arquivo `web/.token`,
gerado no primeiro start, **nunca vai no zip**). Ações de risco abrem um **modal** que
exige marcar "estou ciente". Requer **PHP** (Termux: `pkg install php`).

---

## Os 4 níveis

Tudo fica dentro de [`00 Otimizações/`](00%20Otimiza%C3%A7%C3%B5es/):

| Nível | O que é | Precisa de | Pasta |
|-------|---------|-----------|-------|
| **1** | Arquivos `.txt` para copiar e colar | Brevent | [`00 Otimizações/Comandos Brevent/`](00%20Otimiza%C3%A7%C3%B5es/Comandos%20Brevent/) |
| **2** | Scripts `sh` (automação) | Shizuku ou root | [`00 Otimizações/Scripts SH/`](00%20Otimiza%C3%A7%C3%B5es/Scripts%20SH/) |
| **3** | Plugin AxManager em loop (roda 24h) | gerenciador | [`.../Nossos/01-service-loop/`](00%20Otimiza%C3%A7%C3%B5es/Plugins%20AxManager/Nossos/01-service-loop/) |
| **4** | Plugin AxManager configurável com WebUI | gerenciador | [`.../Nossos/02-webui-control/`](00%20Otimiza%C3%A7%C3%B5es/Plugins%20AxManager/Nossos/02-webui-control/) |

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
| Congelar apps | congela apps de fundo com **whitelist** (nunca congela) + blacklist; descongela tudo num toque |
| Memória/RAM | limites de processos em cache (perfil padrão/gaming), MGLRU, zRAM, KSM (root) |
| Limpeza | cache (`pm trim-caches`), logs, `fstrim`, `drop_caches` (root) |
| Sistema | DND, refresh de tela, limpeza de cache |
| Snapshot | salva o estado atual e reverte a qualquer momento |

Os plugins em `Plugins AxManager/Nossos/` são **nossos** (6 plugins). Em
`Plugins AxManager/Terceiros-open-source/` há plugins de outros autores **só com licença
permissiva** (Apache-2.0), com os créditos em
[`CREDITS.md`](00%20Otimiza%C3%A7%C3%B5es/Plugins%20AxManager/Terceiros-open-source/CREDITS.md).
Não redistribuímos módulo de terceiro sem licença.

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
sh scripts/build-plugins.sh
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
sh scripts/deep-tune.sh extreme           # ⚡ TURBO + TODOS os avançados (esquenta muito)
sh scripts/deep-tune.sh thermal on        # ⚠️ afrouxa o limite térmico (root, esquenta)
sh scripts/deep-tune.sh restore           # desfaz tudo
```

**Módulos extremos / pouco conhecidos** (root, salvo onde indicado) — cada um tem `on`/`off`:

```sh
sh scripts/deep-tune.sh vm on       # gerenciador de memória do kernel (menos engasgo de I/O)
sh scripts/deep-tune.sh sched on    # escalonador/EAS + schedtune (resposta mais imediata)
sh scripts/deep-tune.sh gpu on      # GPU extrema: clock no topo, idle/throttling off
sh scripts/deep-tune.sh cores on    # núcleos sempre ligados (sem hotplug)
sh scripts/deep-tune.sh input on    # input/touch boost (CPU sobe no toque)
sh scripts/deep-tune.sh idle on     # cpuidle "menu" + sem idle profundo
sh scripts/deep-tune.sh net2 on     # BBR2 + MTU probing + slow-start off
sh scripts/deep-tune.sh zram on     # compressão zstd + mem_limit
sh scripts/deep-tune.sh kernel on   # desliga tracing/debug, sobe file-max/backlog
sh scripts/deep-tune.sh display on  # props HWUI/SurfaceFlinger (SEM root)
sh scripts/deep-tune.sh dalvik on   # heaps do ART + dex2oat speed
sh scripts/deep-tune.sh dexopt run  # recompila apps em AOT (SEM root, demora)
```

> ⚠️ `thermal`, `gaming` e `extreme` afrouxam a proteção térmica: mais FPS sustentado,
> **mais calor**. Exige confirmação explícita (`THERMAL_OK=1`) e tem **trava automática**:
> se a temperatura passar de 45 °C (`THERMAL_MAX_C`) ou o aparelho estiver carregando
> (`THERMAL_STOP_CHARGING=1`), o módulo se reverte sozinho.
>
> Os módulos `cores`, `idle`, `gpu` e `input` trocam **bateria/calor por desempenho**.
> Use jogando e com o aparelho ventilado. Tudo reverte com `deep-tune.sh restore` (ou o
> `off` do módulo, que não mexe nos outros).

### `scripts/debloat.sh` (remover bloatware, sem root)

Tira o peso dos apps que você não usa — de forma **reversível** (nada é apagado de
verdade). Desativa gerenciadores de fabricante e restringe o resto por `appops` +
`standby bucket` (o app não roda sozinho, mas continua abrindo).

```sh
sh scripts/debloat.sh list                 # lista apps de usuário (-3) e de sistema (-s)
sh scripts/debloat.sh on medio             # perfis: leve | medio | pesado
sh scripts/debloat.sh off                  # reverte TUDO que este módulo aplicou
sh scripts/debloat.sh status               # o que está aplicado agora
# por app:
sh scripts/debloat.sh disable   com.exemplo   # pm disable-user (volta com enable)
sh scripts/debloat.sh uninstall com.exemplo   # pm uninstall --user 0 (volta com restore)
sh scripts/debloat.sh restrict  com.exemplo   # corta o plano de fundo (appops/standby)
sh scripts/debloat.sh enable|restore|unrestrict com.exemplo
```

> `disable-user` e `uninstall --user 0` **não apagam** o app: somem do seu perfil e
> voltam com `enable` / `install-existing`. O módulo guarda cada reversão em
> `~/.packotm/debloat/off.sh` e o `off` executa tudo de trás para frente.

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
```

O CI (`.github/workflows/build.yml`) roda isso em cada push/PR: sintaxe, shellcheck,
testes e segredos. A release publica `SHA256SUMS.txt` e usa o
[`CHANGELOG.md`](CHANGELOG.md) como descrição.

---

## Estrutura

```
COMECE-AQUI.md    guia rapido para quem esta comecando
CHANGELOG.md      histórico de mudanças
VERSION           versão atual
00 Otimizações/   TUDO do pack, organizado por tipo:
  Comandos Brevent/   arquivos .txt para copiar e colar no Brevent
  Scripts SH/         entry point sh (Shizuku/root)
  Plugins AxManager/  plugins no formato de módulo:
    Nossos/             01-service-loop, 02-webui-control, 03-battery-thermal,
                        04-cleaner, 05-fps-refresh
    Terceiros-open-source/ Stellar-Tweaks, Kang, Sakoiire, Aapt-for-Plugin (+CREDITS)
  Modulos/            módulos Magisk/KernelSU/AxManager do pack (próprios)
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
  build-modules.sh empacota os módulos (00 Otimizações/Modulos/)
  build-plugins.sh empacota os plugins (Nossos/ + Terceiros-open-source/)
  check-secrets.sh  portão de qualidade (credenciais)
tests/run.sh      testes automatizados
docs/             tutorial, auditoria, compatibilidade, segurança, produto
releases/         zips publicados (via GitHub Releases)
```

---

## Créditos

Todo o conteúdo deste repositório é **próprio**: os scripts (`scripts/`), os perfis de
toque, o menu, os 5 plugins em `Plugins AxManager/Nossos/` e os módulos em `Modulos/`.

Os únicos itens de terceiros são os plugins de **licença permissiva** em
`Plugins AxManager/Terceiros-open-source/` (Stellar-Tweaks, Kang, Sakoiire,
Aapt-for-Plugin — todos Apache-2.0), com créditos e `LICENSE` preservados em
[`CREDITS.md`](00%20Otimiza%C3%A7%C3%B5es/Plugins%20AxManager/Terceiros-open-source/CREDITS.md).

Módulos do pack (próprios):

| Módulo | Autor | Versão |
|--------|-------|--------|
| WS7_OFF7 | WS7_OFF7 | 6.0.0 |
| NexaCore | Enrique Brach | 2.0.0 |
| Astrax | BillyNutDemarco | v2-Eclipse |
| NOVA TOUCH | trhieuhoc | 1.0 |
| VOID TOUCH Ultra | VOID DEV | v5.1.0 |
| VeuLexier | Reiieja | V1.7.6-DexOtSmt |

Para empacotar: `sh scripts/build-modules.sh` (módulos) e `sh scripts/build-plugins.sh`
(plugins).

## Licença

MIT — veja [`LICENSE`](LICENSE).