# Pack OTM · Bateria & Térmico

Plugin AxManager (também funciona em KernelSU/APatch/Magisk) que economiza bateria e
**vigia a temperatura**. Se o aparelho passar de 45 °C ou começar a carregar, ele
**reverte sozinho** a parte agressiva e para — nada de esquentar escondido.

## O que faz
- Ativa Doze e coloca apps pesados em standby restrito.
- (Opcional) limita o brilho máximo a 70%.
- Vigia a temperatura a cada 60s; acima de `THERMAL_MAX_C` (padrão 45 °C) reverte tudo.

## Config — `/data/adb/packotm_battery/config`
```
ENABLE_DOZE=1
ENABLE_APPSTANDBY=1
ENABLE_BRIGHTNESS_CAP=0
BRIGHTNESS_CAP=70
ENABLE_THERMAL_WATCH=1
THERMAL_MAX_C=45
WATCH_INTERVAL=60
```

## Instalar
Empacote a pasta como zip e instale pelo gerenciador, ou:
```sh
sh scripts/build-plugins.sh
```
O botão de ação mostra estado, temperatura e log. `uninstall.sh` reverte tudo.
