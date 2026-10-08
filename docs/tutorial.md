# Tutorial completo · Pack de Otimização

Guia do zero: o que é cada nível, o que cada coisa faz, como usar e como voltar atrás.
Leia uma vez inteiro; depois use como referência.

---

## Índice

1. [O que é o pack](#1-o-que-é-o-pack)
2. [Os 4 níveis](#2-os-4-níveis)
3. [Nível 1 — .txt no Brevent](#3-nível-1--txt-no-brevent)
4. [Nível 2 — sh + Shizuku](#4-nível-2--sh--shizuku)
5. [Nível 3 — plugin AxManager (loop)](#5-nível-3--plugin-axmanager-loop)
6. [Nível 4 — plugin AxManager (WebUI)](#6-nível-4--plugin-axmanager-webui)
7. [Snapshot: salvar e reverter](#7-snapshot-salvar-e-reverter)
8. [O que cada comando faz](#8-o-que-cada-comando-faz)
9. [Sensibilidade do Free Fire](#9-sensibilidade-do-free-fire)
10. [Solução de problemas](#10-solução-de-problemas)
11. [Segurança e bom senso](#11-segurança-e-bom-senso)

---

## 1. O que é o pack

Um conjunto de ajustes de Android que melhora **desempenho, latência de rede e
resposta do toque** — com foco em jogos e no **Free Fire**. Tudo é reversível.

O pack cresce em níveis: do mais simples (copiar e colar) ao mais avançado (plugin com
interface web). Você escolhe até onde quer ir.

---

## 2. Os 4 níveis

| Nível | Como | Precisa de | Melhor para |
|-------|------|-----------|-------------|
| **1** | Arquivos `.txt` | Brevent | quem quer só copiar e colar |
| **2** | Script `sh` | Shizuku ou root | automação por linha de comando |
| **3** | Plugin AxManager (loop) | gerenciador | "liga e esquece", roda 24h |
| **4** | Plugin AxManager (WebUI) | gerenciador | controle fino por interface |

Todos os níveis usam **os mesmos comandos** por baixo. A diferença é o conforto e o
grau de automação.

---

## 3. Nível 1 — .txt no Brevent

**O que é:** cada arquivo em [`nivel-1-txt/`](../nivel-1-txt/) é uma lista de comandos.
Você abre, copia tudo e cola no Brevent.

**Passo a passo:**

1. Instale o **Brevent** e conceda as permissões (ADB ou root — veja
   [`brevent.md`](brevent.md)).
2. Abra, por exemplo, `nivel-1-txt/10-free-fire.txt`.
3. Selecione tudo → copiar.
4. Cole na área de execução do Brevent → rode.
5. Para voltar: cole `99-restaurar-tudo.txt`.

**Arquivos (19 categorias):** performance geral, velocidade das animações, tela/display,
RAM/memória, bateria, gráficos/GPU, rede/DNS, Wi-Fi/dados, jogo/game mode, Free Fire,
sensibilidade/touch, congelar apps, descongelar apps, limpeza/cache, notificações/DND,
bloat/privacidade, sistema/logs e restaurar tudo. A lista completa está em
[`nivel-1-txt/README.md`](../nivel-1-txt/README.md).

> Neste nível não há automação: você roda quando quiser.

---

## 4. Nível 2 — sh + Shizuku

**O que é:** os scripts em `scripts/` rodam via **Shizuku** (`rish`), **root** ou
**ADB**, com detecção automática do transporte.

**Passo a passo:**

1. Instale o **Shizuku** e ative via ADB ou depuração sem fio.
2. No **Termux**, baixe o `rish` e deixe no `PATH` (veja
   [`termux-shizuku.md`](termux-shizuku.md)).
3. Rode:

```sh
sh nivel-2-sh/run.sh            # abre o menu
sh nivel-2-sh/run.sh all        # aplica tudo
sh nivel-2-sh/run.sh headshot   # perfil de sensibilidade
sh nivel-2-sh/run.sh fluidez    # fluidez (animações 0, toque, Hz)
sh nivel-2-sh/run.sh game apply com.dts.freefireth fps   # tuning por jogo
sh nivel-2-sh/run.sh save       # salva o estado atual (snapshot)
sh nivel-2-sh/run.sh restore    # volta o último snapshot
```

**Antes de aplicar qualquer coisa, salve um snapshot.** Assim você volta com um comando.

---

## 5. Nível 3 — plugin AxManager (loop)

**O que é:** um módulo instalável no **AxManager** (ou KernelSU/APatch/Magisk). Aplica
o pack e **fica rodando em segundo plano**, reafirmando os tweaks de tempo em tempo.

**Passo a passo:**

1. Empacote (ou pegue o zip em `releases/01-service-loop.zip`):

```sh
sh scripts/build-modules.sh
```

2. Instale `releases/01-service-loop.zip` pelo gerenciador.
3. Reinicie. O loop começa sozinho no boot.
4. Toque no **botão de ação** do módulo para ver status, RAM livre e log.

**Config** em `/data/adb/packotm/config`: intervalo do loop, intervalo de limpeza,
ligar/desligar DNS, touch e doze.

**Parar:** `touch /data/adb/packotm/stop`.

Detalhes em [`../plugins/01-service-loop/README.md`](../plugins/01-service-loop/README.md).

---

## 6. Nível 4 — plugin AxManager (WebUI)

**O que é:** o nível mais avançado. Um plugin com **interface web** onde você liga e
desliga cada módulo e ajusta valores, com status ao vivo.

**Passo a passo:**

1. Instale `releases/02-webui-control.zip` pelo gerenciador.
2. Abra a **WebUI** pelo gerenciador.
3. Ligue/desligue módulos, ajuste os valores, toque em **Aplicar**.
4. **Salvar config** grava para o próximo boot.

**A tela mostra:** RAM livre, bateria, temperatura e refresh. E permite configurar:
performance, gráficos, rede, game mode, freeze, DND, tela, touch e loop.

Detalhes em [`../plugins/02-webui-control/README.md`](../plugins/02-webui-control/README.md).

---

## 7. Snapshot: salvar e reverter

O `scripts/snapshot.sh` tira uma "foto" das configurações atuais e permite voltar a
qualquer momento — perfeito se você mexer em algo (velocidade da tela, toque) e não
gostar.

```sh
sh scripts/snapshot.sh save              # salva com data/hora
sh scripts/snapshot.sh save antes-do-ff  # salva com nome
sh scripts/snapshot.sh list              # lista os snapshots
sh scripts/snapshot.sh show latest       # mostra o que foi salvo
sh scripts/snapshot.sh diff latest       # compara com o estado atual
sh scripts/snapshot.sh restore latest    # volta tudo
sh scripts/snapshot.sh delete latest     # apaga um snapshot
```

Ficam em `~/.packotm/snapshots/<id>/` (`settings`, `props` e `meta`).

**Regra de ouro:** salve um snapshot **antes** de aplicar o pack. Se não gostar,
`restore latest` devolve tudo.

---

## 8. O que cada comando faz

### Performance
- `window_animation_scale`, `transition_animation_scale`, `animator_duration_scale` —
  velocidade das animações. 0.5 = mais rápido, 0 = instantâneo.
- `force_gpu_rendering` — força renderização por GPU (menos trabalho da CPU).
- `disable_window_blurs`, `accessibility_reduce_transparency` — remove desfoques.
- `debug.hwui.renderer skiagl` — renderizador de UI.

### Rede
- `private_dns_mode` / `private_dns_specifier` — DNS privado (Cloudflare).
- `wifi_scan_always_enabled 0` — para a varredura de Wi-Fi em background.
- `net.tcp.buffersize.*` — buffers TCP maiores (mais throughput/ping estável).

### Bateria
- `low_power` — modo economia.
- `dumpsys deviceidle` — Doze (adormece apps em background).

### Jogo / Free Fire
- `cmd game set --mode performance <pkg>` — Game Mode em performance.
- `game_driver_all_apps 1` — driver de jogo em todos os apps.
- `am force-stop <pkg>` — fecha apps pesados.
- `pm compile -m speed` / AOT — compila os jogos (root).

### Congelamento
- `cached_apps_freezer` — congela apps em cache.
- `pm suspend` / `pm unsuspend` — congela/descongela um app específico.

### Toque / sensibilidade
- `touch_responsiveness` — quão responsivo o toque é.
- `long_press_timeout` — tempo para "segurar". Faixa útil: 100–250 ms.
- `multi_press_timeout` — espera entre toques múltiplos. 0 = sem atraso.
- `pointer_speed` — velocidade do ponteiro.
- `touch_slop` — distância mínima para contar como arrasto (menor = mais preciso).

### Fluidez
- `window/transition/animator_duration_scale 0` — animações zeradas (efeito instantâneo).
- `long_press_timeout` — 100–250 ms (depende do aparelho; padrão 500).
- `multi_press_timeout 0` — sem espera entre toques.
- `peak_refresh_rate` / `min_refresh_rate` — trava a tela no Hz máximo permitido.

### Tuning por jogo (resolução / FPS / engine)
Mexe **só no jogo**, não no telefone. Usa as *Game Mode interventions* do Android 12+.
- `device_config put game_overlay <pkg> mode=2,downscaleFactor=0.9` — resolução interna.
  `0.9` quase não perde nitidez; `0.5` é o máximo ganho de FPS.
- `...,fps=60` — teto de FPS (Android 13+).
- `cmd game set --mode performance <pkg>` — coloca o jogo em performance.
- Reverter por jogo: `device_config delete game_overlay <pkg>`.

Perfis prontos no script: `fps` (0.9) · `balanced` (0.75) · `max` (0.5).

```sh
sh scripts/game-per-app.sh list
sh scripts/game-per-app.sh apply com.dts.freefireth fps
sh scripts/game-per-app.sh custom com.dts.freefireth 0.75 60
sh scripts/game-per-app.sh reset com.dts.freefireth
```

### Tela
- `peak_refresh_rate` / `min_refresh_rate` — taxa de atualização.
- `screen_off_timeout` — tempo até a tela apagar.

### Sistema
- `heads_up_notifications_enabled` — notificações que "pulam" na tela.
- `pm trim-caches`, `sm fstrim`, `sync` — limpeza e manutenção.

---

## 9. Sensibilidade do Free Fire

Perfis prontos em `scripts/ff-touch.sh`:

| Perfil | Para quem |
|--------|-----------|
| `balanced` | uso geral, equilibrado |
| `headshot` | mira rápida (capuz/cabeça) |
| `spray` | controlar o recuo (rajada) |
| `sniper` | mira precisa e lenta |
| `speed` | máxima reatividade |
| `custom` | você define os 4 valores |

```sh
sh scripts/ff-touch.sh headshot
sh scripts/ff-touch.sh custom 110 350 0 4   # responsiveness longpress pointer slop
```

**Importante:** não existe valor "certo" universal. Teste no **treino** do Free Fire,
ajuste um parâmetro por vez e salve um snapshot quando achar o ideal.

---

## 10. Solução de problemas

| Sintoma | Causa provável | Solução |
|---------|----------------|---------|
| "nenhum transporte" | sem ADB/Shizuku/root | ative um dos três, ou `OTM_MODE=local` |
| comandos sem efeito | transporte errado | `OTM_MODE=rish sh scripts/menu.sh` |
| toque trepidando | slop baixo demais | aumente `touch_slop` |
| jogo pior depois | bateria/doze ligado | rode `restore_all` |
| app não abre | congelado | `pm unsuspend <pkg>` |
| não sei o que mudei | — | `sh scripts/snapshot.sh diff latest` |

Reverter tudo: `sh scripts/adb-tweaks.sh restore_all` ou
`sh scripts/snapshot.sh restore latest`.

---

## 11. Otimizações profundas

Quando os `settings` já não dão mais ganho, o pack tem um módulo que mexe **mais fundo**
— e continua reversível. Tudo vive em `scripts/deep-tune.sh`:

```sh
sh scripts/deep-tune.sh detect              # o que o seu aparelho suporta
sh scripts/deep-tune.sh angle add <pkg>     # ANGLE/Vulkan por jogo (sem root) ★
sh scripts/deep-tune.sh debloat on          # appops + standby buckets (sem root)
sh scripts/deep-tune.sh gaming on <pkg>     # MODO JOGO TURBO (root: freq+io+mem+net+...)
sh scripts/deep-tune.sh restore             # desfaz tudo
```

Cada módulo guarda o **valor original** e tem o seu próprio "off" (`freq off`, `angle
reset`, ...). O `thermal` afrouxa o limite de temperatura: dá mais FPS sustentado, mas
**esquenta mais** — use só jogando e com o aparelho ventilado.

O documento [`AUDITORIA.md`](AUDITORIA.md) lista, para cada módulo, o comando exato, o
privilégio exigido, o ganho esperado, o risco e a reversão.

---

## 12. Segurança e bom senso

- **Sempre** salve um snapshot antes de aplicar.
- `setprop` não persiste após reiniciar; `settings put` persiste.
- Não use bateria/Doze junto com performance em partidas longas.
- `thermal`/`gaming` afrouxam o térmico: mais calor, mais risco. Reverta após jogar.
- Módulos de terceiros em `modules/` têm autoria própria (ver créditos).
- Você é responsável pelo que roda no seu aparelho. Teste antes.
