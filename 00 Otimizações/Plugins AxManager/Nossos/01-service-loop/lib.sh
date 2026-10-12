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
# otimizações profundas
ENABLE_ANGLE=0
ANGLE_PKGS=com.dts.freefireth,com.dts.freefiremax
ENABLE_DEBLOAT=1
ENABLE_DEEP=0     # freq/io/mem/net/latency (sysfs, mais agressivo)
ENABLE_THERMAL=0  # ⚠️ afrouxa o térmico (esquenta mais)

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

    [ "$ENABLE_ANGLE" = "1" ] && [ -n "$ANGLE_PKGS" ] && {
        n=$(echo "$ANGLE_PKGS" | tr ',' '\n' | wc -l)
        vals=$(i=0; while [ "$i" -lt "$n" ]; do printf 'angle,'; i=$((i+1)); done | sed 's/,$//')
        settings put global angle_gl_driver_selection_pkgs "$ANGLE_PKGS" >/dev/null 2>&1
        settings put global angle_gl_driver_selection_values "$vals" >/dev/null 2>&1
    }
}

# --- otimizações profundas (sysfs/root), espelhando scripts/deep-tune.sh ------
# Guarda o valor antigo de cada sysfs ANTES de escrever, para o uninstall poder
# devolver exatamente o estado original (sem isso, não haveria reversão real).
DEEP_OFF="$STATE/deep_off.sh"
DEEP_MARK="$STATE/deep_mark"
DEEP_RECORD=0

_sys_write() {  # _sys_write <path> <novo>
    p="$1"; v="$2"
    [ -w "$p" ] || return 0
    if [ "$DEEP_RECORD" = "1" ]; then
        old=$(cat "$p" 2>/dev/null)
        [ -n "$old" ] && echo "echo '$old' > $p" >> "$DEEP_OFF"
    fi
    echo "$v" > "$p" 2>/dev/null
}

apply_deep() {
    # grava o estado original só na primeira vez; o loop reaplica sem duplicar
    if [ ! -f "$DEEP_MARK" ]; then
        : > "$DEEP_OFF"
        DEEP_RECORD=1
    fi

    [ "$ENABLE_DEBLOAT" = "1" ] && {
        for a in com.instagram.android com.facebook.katana com.facebook.orca \
                 com.ss.android.ugc.trill com.ss.android.ugc.aweme com.twitter.android \
                 com.google.android.youtube com.android.chrome com.spotify.music com.discord; do
            cmd appops set "$a" RUN_IN_BACKGROUND ignore >/dev/null 2>&1
            cmd appops set "$a" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
            am set-standby-bucket "$a" restricted >/dev/null 2>&1
        done
    }

    [ "$ENABLE_DEEP" = "1" ] && {
        for d in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
            _sys_write "$d/scaling_governor" performance
            mx=$(cat "$d/cpuinfo_max_freq" 2>/dev/null)
            [ -n "$mx" ] && _sys_write "$d/scaling_min_freq" "$mx"
        done
        for b in /sys/block/sd* /sys/block/mmcblk* /sys/block/ufs*; do
            _sys_write "$b/queue/scheduler" none
            _sys_write "$b/queue/read_ahead_kb" 4096
        done
        _sys_write /sys/kernel/mm/lru_gen/enabled 1
        _sys_write /proc/sys/vm/swappiness 100
        if sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
            if [ "$DEEP_RECORD" = "1" ]; then
                old=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
                [ -n "$old" ] && echo "sysctl -w net.ipv4.tcp_congestion_control=$old" >> "$DEEP_OFF"
            fi
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
        fi
        if [ "$DEEP_RECORD" = "1" ]; then
            old=$(getprop debug.sf.latch_unsignaled)
            echo "setprop debug.sf.latch_unsignaled '$old'" >> "$DEEP_OFF"
        fi
        setprop debug.sf.latch_unsignaled 1 >/dev/null 2>&1
    }

    [ "$ENABLE_THERMAL" = "1" ] && {
        for z in /sys/class/thermal/thermal_zone*; do
            case "$(cat "$z/type" 2>/dev/null)" in
                cpu|gpu|soc|tsens*|big*|little*|*skin*) ;;
                *) continue ;;
            esac
            for tp in "$z"/trip_point_*_temp; do
                [ -f "$tp" ] || continue
                old=$(cat "$tp" 2>/dev/null)
                case "$old" in ''|*[!0-9]*) continue ;; esac
                [ "$old" -ge 60000 ] && _sys_write "$tp" $((old + 5000))
            done
        done
    }

    [ "$DEEP_RECORD" = "1" ] && { command touch "$DEEP_MARK"; DEEP_RECORD=0; }
}

revert_deep() {
    if [ -s "$DEEP_OFF" ]; then
        while IFS= read -r c; do
            [ -z "$c" ] && continue
            sh -c "$c" >/dev/null 2>&1
        done < "$DEEP_OFF"
        rm -f "$DEEP_OFF"
    fi
    for a in com.instagram.android com.facebook.katana com.facebook.orca \
             com.ss.android.ugc.trill com.ss.android.ugc.aweme com.twitter.android \
             com.google.android.youtube com.android.chrome com.spotify.music com.discord; do
        cmd appops set "$a" RUN_IN_BACKGROUND allow >/dev/null 2>&1
        cmd appops set "$a" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
        am set-standby-bucket "$a" active >/dev/null 2>&1
    done
    settings delete global angle_gl_driver_selection_pkgs >/dev/null 2>&1
    settings delete global angle_gl_driver_selection_values >/dev/null 2>&1
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
        echo "ENABLE_ANGLE=$ENABLE_ANGLE"
        echo "ANGLE_PKGS=$ANGLE_PKGS"
        echo "ENABLE_DEBLOAT=$ENABLE_DEBLOAT"
        echo "ENABLE_DEEP=$ENABLE_DEEP"
        echo "ENABLE_THERMAL=$ENABLE_THERMAL"
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
