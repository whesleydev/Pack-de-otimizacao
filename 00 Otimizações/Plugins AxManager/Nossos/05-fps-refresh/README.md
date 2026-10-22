# Pack OTM · FPS & Refresh

Plugin AxManager (e KernelSU/APatch/Magisk) que força a **taxa de atualização máxima**
do painel e liga o **modo de jogo** (performance + overlay de FPS) para os principais
jogos: Free Fire, Free Fire Max, CODM, MLBB, PUBG.

Tudo reversível: guarda o valor antigo de `peak_refresh_rate`/`min_refresh_rate` e
remove os overlays no uninstall.

## O que faz
- Detecta o máximo do painel e fixa `peak_refresh_rate`/`min_refresh_rate` nele.
- `cmd game set --mode performance` nos jogos da lista.
- `device_config game_overlay` com `fps` e `downscaleFactor` (opcional).

## Config — `/data/adb/packotm_fps/config`
```
TARGET_HZ=0            # 0 = máximo do painel; ou 60/90/120/144
FORCE_MAX_HZ=1
GAME_MODE=1
GAME_APPS="com.dts.freefireth com.dts.freefiremax com.activision.callofduty.shooter com.mobile.legends com.tencent.ig"
FPS_OVERLAY=1
FPS_DS=0.9
```

## Instalar
```sh
sh scripts/build-plugins.sh
```
O botão de ação mostra o Hz do painel e o log. `uninstall.sh` reverte tudo.

> Obs.: o jogo precisa estar com o FPS alto liberado nas configurações dele; o plugin
> libera o teto do sistema, mas não burla o limite do próprio jogo.
