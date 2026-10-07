# Nível 4 · Plugin AxManager (WebUI Control)

Plugin configurável com **interface web** — o nível mais avançado. Abra o painel
pelo gerenciador, ligue/desligue módulos, ajuste sensibilidade e aplique.

## Como funciona

- `customize.sh` — instala e copia o motor para `/data/adb/packotm/apply.sh`.
- `apply.sh` — motor configurável: lê `webui.conf` e aplica só o que está ligado.
- `service.sh` — aplica no boot; se `CFG_LOOP=1`, reafirma a cada 120s.
- `webroot/` — a UI (`index.html`, `style.css`, `app.js`).

## A UI

- **Status ao vivo**: RAM livre, bateria, temperatura e refresh.
- **Módulos**: checkboxes para performance, gráficos, rede, game mode, freeze,
  DND, tela, touch e loop.
- **Ajustes**: animação, touch responsiveness, long press, pointer speed,
  touch slop e refresh.
- **Tuning por jogo**: liga/desliga e define pacote, downscale (resolução) e teto de FPS
  — mexe **só no jogo** (Game Mode interventions, Android 12+).
- **Ações**: Aplicar, Salvar config, Atualizar status e Restaurar tudo.

A UI conversa com o shell pela ponte `@kernelsu/api` (`exec`) do AxManager/KernelSU.

## Config (`/data/adb/packotm/webui.conf`)

```sh
CFG_PERF=1      # performance
CFG_GFX=1       # efeitos gráficos
CFG_NET=1       # DNS/rede
CFG_GAME=1      # game mode
CFG_FREEZE=0    # congelar apps
CFG_DND=0       # notificações
CFG_TV=1        # tela/refresh
CFG_TOUCH=1     # sensibilidade
CFG_LOOP=0      # loop em background
CFG_ANIM=0.5
CFG_TR=110      # touch responsiveness
CFG_LP=350      # long press (ms)
CFG_PS=0        # pointer speed
CFG_SLOP=4      # touch slop
CFG_HZ=0        # refresh (0 = não mexer)
CFG_GAMETUNE=0  # tuning por jogo (0/1)
CFG_GT_PKG=com.dts.freefireth  # pacote do jogo
CFG_GT_DS=0.9   # downscale da resolução (0.5-1.0)
CFG_GT_FPS=0    # teto de FPS (0 = padrão; Android 13+)
```

## Usar sem a UI (terminal)

```sh
sh /data/adb/packotm/apply.sh show          # mostra a config
sh /data/adb/packotm/apply.sh set CFG_TR 95 # muda um valor
sh /data/adb/packotm/apply.sh apply         # aplica
sh /data/adb/packotm/apply.sh restore       # reverte
```
