# Nível 3 · Plugin AxManager (Service Loop)

Plugin que aplica o pack e **fica rodando em segundo plano** reafirmando os tweaks
em loop — o "liga e esquece". Funciona no **AxManager**, KernelSU, APatch e Magisk.

## Como funciona

- `customize.sh` — na instalação, aplica o pack uma vez.
- `service.sh` — chamado no boot pelo gerenciador; aplica e entra num loop infinito.
- `action.sh` — botão de ação: mostra status, RAM livre e o log recente.
- `lib.sh` — funções compartilhadas (core, limpeza, doze).
- `uninstall.sh` — para o loop e reverte os tweaks.

## Configuração

No primeiro boot é criado `/data/adb/packotm/config`:

```sh
LOAD_KILL=1        # fecha apps de fundo (1/0)
CLEAN_INTERVAL=300 # segundos entre limpezas
LOOP_INTERVAL=60   # segundos entre reaplicações
ENABLE_DNS=1
ENABLE_TOUCH=1
ENABLE_DOZE=0
ENABLE_GAMETUNE=0  # tuning por jogo (0/1)
GT_PKG=com.dts.freefireth  # pacote do jogo
GT_DS=0.9          # downscale (0.5-1.0)
GT_FPS=0           # teto de FPS (0 = padrão)
# otimizações profundas
ENABLE_ANGLE=0     # ANGLE/Vulkan por jogo (sem root)
ANGLE_PKGS=com.dts.freefireth,com.dts.freefiremax
ENABLE_DEBLOAT=1   # appops + standby buckets (sem root)
ENABLE_DEEP=0      # freq/io/mem/net/latency via sysfs (root, agressivo)
ENABLE_THERMAL=0   # ⚠️ afrouxa o térmico (root, esquenta mais)
```

> As otimizações profundas guardam o valor original de cada sysfs em
> `/data/adb/packotm/deep_off.sh` e o `uninstall.sh` devolve tudo ao estado
> exato — inclusive desligando o debloat e o ANGLE.

Edite e reinicie (ou rode `sh /data/adb/packotm/apply.sh`).

## Parar

```sh
touch /data/adb/packotm/stop   # o loop encerra no próximo ciclo
```

## Instalar

Empacote a pasta como zip e instale pelo gerenciador, ou:

```sh
sh scripts/build-modules.sh   # também empacota os plugins
```
