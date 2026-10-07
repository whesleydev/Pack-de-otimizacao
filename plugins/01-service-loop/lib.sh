#!/system/bin/sh
# =============================================================================
#  lib.sh - Funções do pack no contexto do módulo (root).
#  Carregado por apply.sh e service.sh.
#  Config lida de $STATE/config (gerada no primeiro boot).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm"
mkdir -p "$STATE" 2>/dev/null || STATE="$DIR/state"
mkdir -p "$STATE" 2>/dev/null
CFG="$STATE/config"

# config padrão
LOAD_KILL=1        # fecha apps de fundo
CLEAN_INTERVAL=300 # segundos entre limpezas
LOOP_INTERVAL=60   # segundos entre reaplicações do core
ENABLE_DNS=1
ENABLE_TOUCH=1
ENABLE_DOZE=0
ENABLE_GAMETUNE=0
GT_PKG=com.dts.freefireth
GT_DS=0.9
GT_FPS=0

[ -f "$CFG" ] && . "$CFG" 2>/dev/null

log() { echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$STATE/loop.log"; }

boot_wait() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
    until [ -d "/sdcard/Android" ] || [ -d "/storage/emulated/0/Android" ]; do sleep 1; done
}

apply_core() {
    settings put global window_animation_scale 0.5
    settings put global transition_animation_scale 0.5
    settings put global animator_duration_scale 0.5
    settings put global force_gpu_rendering 1
    settings put global disable_window_blurs 1
    settings put global accessibility_reduce_transparency 1
    settings put global game_driver_all_apps 1

    [ "$ENABLE_DNS" = "1" ] && {
        settings put global private_dns_mode hostname
        settings put global private_dns_specifier dns.cloudflare.com
    }

    [ "$ENABLE_TOUCH" = "1" ] && {
        settings put system touch_responsiveness 110
        settings put system long_press_timeout 350
        settings put system pointer_speed 0
        settings put system touch_slop 4
        setprop persist.sys.touch.sensitivity 1
    }

    cmd game set --mode performance com.dts.freefireth  >/dev/null 2>&1
    cmd game set --mode performance com.dts.freefiremax >/dev/null 2>&1
    setprop debug.hwui.renderer skiagl

    [ "$ENABLE_GAMETUNE" = "1" ] && [ -n "$GT_PKG" ] && {
        if [ "$GT_FPS" != "0" ]; then
            device_config put game_overlay "$GT_PKG" \
                "mode=2,fps=$GT_FPS,downscaleFactor=$GT_DS:mode=3,fps=$GT_FPS,downscaleFactor=$GT_DS" >/dev/null 2>&1
        else
            device_config put game_overlay "$GT_PKG" \
                "mode=2,downscaleFactor=$GT_DS:mode=3,downscaleFactor=$GT_DS" >/dev/null 2>&1
        fi
    }
}

kill_background_apps() {
    [ "$LOAD_KILL" = "1" ] || return 0
    for a in com.instagram.android com.facebook.katana com.facebook.orca \
             com.ss.android.ugc.trill com.ss.android.ugc.aweme com.twitter.android \
             com.google.android.youtube com.android.chrome com.spotify.music com.discord; do
        am force-stop "$a" >/dev/null 2>&1
    done
}

clean_memory() {
    cmd activity trim-caches >/dev/null 2>&1
    pm trim-caches 999999999 >/dev/null 2>&1
    logcat -c >/dev/null 2>&1
    sync >/dev/null 2>&1
}

apply_doze() {
    [ "$ENABLE_DOZE" = "1" ] && dumpsys deviceidle enable >/dev/null 2>&1
    return 0
}

save_default_config() {
    [ -f "$CFG" ] && return 0
    {
        echo "LOAD_KILL=$LOAD_KILL"
        echo "CLEAN_INTERVAL=$CLEAN_INTERVAL"
        echo "LOOP_INTERVAL=$LOOP_INTERVAL"
        echo "ENABLE_DNS=$ENABLE_DNS"
        echo "ENABLE_TOUCH=$ENABLE_TOUCH"
        echo "ENABLE_DOZE=$ENABLE_DOZE"
        echo "ENABLE_GAMETUNE=$ENABLE_GAMETUNE"
        echo "GT_PKG=$GT_PKG"
        echo "GT_DS=$GT_DS"
        echo "GT_FPS=$GT_FPS"
    } > "$CFG"
}

free_ram_mb() {
    while read -r line; do
        case "$line" in
            MemAvailable:*) set -- $line; echo $(( $2 / 1024 )); return ;;
        esac
    done < /proc/meminfo
    echo 0
}
