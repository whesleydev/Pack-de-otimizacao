# Lista de comandos ADB

Comandos crus para copiar e colar — no **Brevent** (sem o prefixo de transporte) ou via
**ADB** (`adb shell "..."`). Organizados por área.

## Performance

```sh
settings put global window_animation_scale 0.5
settings put global transition_animation_scale 0.5
settings put global animator_duration_scale 0.5
settings put global force_gpu_rendering 1
settings put global disable_window_blurs 1
settings put global accessibility_reduce_transparency 1
settings put global activity_manager_constants max_cached_processes=32
setprop debug.hwui.renderer skiagl
settings put global game_driver_all_apps 1
```

Animações desligadas (extremo):

```sh
settings put global window_animation_scale 0
settings put global transition_animation_scale 0
settings put global animator_duration_scale 0
```

## Rede / DNS

```sh
settings put global private_dns_mode hostname
settings put global private_dns_specifier dns.cloudflare.com
settings put global wifi_scan_always_enabled 0
setprop net.tcp.buffersize.default 4096,87380,524288,4096,16384,110208
setprop net.tcp.buffersize.wifi 524288,1048576,2097152,262144,524288,1048576
setprop net.tcp.buffersize.lte 524288,1048576,2097152,262144,524288,1048576
setprop net.tcp.buffersize.hspa 4094,87380,524288,4096,16384,262144
```

Resetar DNS:

```sh
settings put global private_dns_mode opportunistic
settings delete global private_dns_specifier
```

## Bateria / Doze

```sh
settings put global low_power 1
settings put global adaptive_battery_management_enabled 0
dumpsys deviceidle enable
dumpsys deviceidle force-idle
```

Normal:

```sh
settings put global low_power 0
settings put global adaptive_battery_management_enabled 1
dumpsys deviceidle unforce
```

## Jogos

```sh
cmd game set --mode performance com.dts.freefireth
cmd game set --mode performance com.dts.freefiremax
cmd game set --downscale-factor 1 com.dts.freefireth
settings put global game_driver_all_apps 1
```

## Free Fire (fechar apps / abrir)

```sh
am force-stop com.instagram.android
am force-stop com.facebook.katana
am force-stop com.facebook.orca
am force-stop com.ss.android.ugc.trill
am force-stop com.ss.android.ugc.aweme
am force-stop com.twitter.android
am force-stop com.google.android.youtube
am force-stop com.android.chrome
am force-stop com.spotify.music
am force-stop com.discord

am start -n com.dts.freefireth/com.dts.freefireth.FFMainActivity
am start -n com.dts.freefiremax/com.dts.freefireth.FFMainActivity
```

## Freezer / congelamento (Brevent)

```sh
settings put global cached_apps_freezer enabled     # congelamento nativo (cache)
settings put global cached_apps_freezer disabled

pm list packages -3                                 # apps de terceiros
pm list packages -u -3                              # inclui desinstalados/suspensos
pm suspend --user 0 com.exemplo.app                 # congelar
pm unsuspend --user 0 com.exemplo.app               # descongelar
pm enable --user 0 com.exemplo.app                  # reativar
```

## Notificações / DND

```sh
settings put global heads_up_notifications_enabled 0
cmd notification set_dnd off
settings put global zen_mode 0
```

## Tela / refresh

```sh
settings put system screen_off_timeout 600000
settings put system peak_refresh_rate 120.0
settings put system min_refresh_rate 120.0
settings put system screen_brightness 200
```

## Sensibilidade / toque (Free Fire)

```sh
settings put system touch_responsiveness 110
settings put system long_press_timeout 350
settings put system pointer_speed 0
settings put system touch_slop 4
setprop persist.sys.touch.sensitivity 1
setprop persist.sys.input.touch.boost 1
```

Reverter:

```sh
settings delete system touch_slop
settings delete system touch_responsiveness
setprop persist.sys.touch.sensitivity 0
```

## Fluidez (animações 0, toque sem atraso, Hz máximo)

Inspirado no que o Sam Helper ajusta no Samsung — os nomes de settings são padrão,
então funciona em qualquer Android.

```sh
# animações zeradas (efeito instantâneo)
settings put global window_animation_scale 0
settings put global transition_animation_scale 0
settings put global animator_duration_scale 0

# long press: 100-250 ms (depende do aparelho; padrão = 500)
settings put system long_press_timeout 150

# multi press: 0 = sem espera entre toques (padrão = 300)
settings put system multi_press_timeout 0

# Hz no máximo permitido (troque pela taxa do seu aparelho)
settings put system peak_refresh_rate 120.0
settings put system min_refresh_rate 120.0
```

> Descubra o Hz máximo do seu aparelho: `settings get system peak_refresh_rate`.
> Em `multi_press_timeout 0`, apps que usam duplo-toque (zoom, curtir) podem registrar
> como dois toques separados — se incomodar, use `100`.

## Limpeza

```sh
pm trim-caches 999999999999
killall -9 dex2oat
sync
```

## AOT (root)

```sh
cmd package compile -m speed -f com.dts.freefireth
cmd package compile -m speed -f com.dts.freefiremax
```

## Restaurar tudo

```sh
settings delete global window_animation_scale
settings delete global transition_animation_scale
settings delete global animator_duration_scale
settings put global force_gpu_rendering 0
settings put global disable_window_blurs 0
settings put global accessibility_reduce_transparency 0
settings put global game_driver_all_apps 0
settings put global private_dns_mode opportunistic
settings put global low_power 0
settings put global adaptive_battery_management_enabled 1
settings put global cached_apps_freezer disabled
settings put global heads_up_notifications_enabled 1
dumpsys deviceidle unforce
```

> `setprop` não persiste após reiniciar o aparelho. `settings put` persiste.
