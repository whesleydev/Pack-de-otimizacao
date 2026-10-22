#!/system/bin/sh
# =============================================================================
#  lib.sh - Bateria & Térmico (root). Config em $STATE/config.
#  Tudo reversível: guarda o valor antigo antes de escrever.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm_battery"
mkdir -p "$STATE" 2>/dev/null || STATE="$DIR/state"
mkdir -p "$STATE" 2>/dev/null
CFG="$STATE/config"
OFF="$STATE/off.sh"

# config padrão
ENABLE_DOZE=1
ENABLE_APPSTANDBY=1
ENABLE_BRIGHTNESS_CAP=0
BRIGHTNESS_CAP=70        # % máximo de brilho
ENABLE_THERMAL_WATCH=1
THERMAL_MAX_C=45         # acima disso, reverte
WATCH_INTERVAL=60

[ -f "$CFG" ] && . "$CFG" 2>/dev/null

log() { echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$STATE/loop.log"; }

save_default_config() {
    [ -f "$CFG" ] && return 0
    {
        echo "ENABLE_DOZE=$ENABLE_DOZE"
        echo "ENABLE_APPSTANDBY=$ENABLE_APPSTANDBY"
        echo "ENABLE_BRIGHTNESS_CAP=$ENABLE_BRIGHTNESS_CAP"
        echo "BRIGHTNESS_CAP=$BRIGHTNESS_CAP"
        echo "ENABLE_THERMAL_WATCH=$ENABLE_THERMAL_WATCH"
        echo "THERMAL_MAX_C=$THERMAL_MAX_C"
        echo "WATCH_INTERVAL=$WATCH_INTERVAL"
    } > "$CFG"
}

boot_wait() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
}

# --- leitura de temperatura (best-effort, varia por aparelho) ----------------
read_temp_c() {
    for z in /sys/class/thermal/thermal_zone*; do
        case "$(cat "$z/type" 2>/dev/null)" in
            cpu|gpu|soc|tsens*|big*|little*|*skin*|battery|*batt*) ;;
            *) continue ;;
        esac
        v=$(cat "$z/temp" 2>/dev/null)
        case "$v" in ''|*[!0-9-]*) continue ;; esac
        [ "$v" -gt 1000 ] && v=$((v / 1000))
        [ "$v" -gt 0 ] && [ "$v" -lt 120 ] && { echo "$v"; return; }
    done
    echo 0
}

is_charging() {
    for p in /sys/class/power_supply/*/status; do
        [ -f "$p" ] || continue
        case "$(cat "$p" 2>/dev/null)" in Charging|Full) return 0 ;; esac
    done
    return 1
}

_record() {  # _record <comando de restauração>
    echo "$1" >> "$OFF"
}

apply_battery() {
    if [ "$ENABLE_DOZE" = "1" ]; then
        dumpsys deviceidle enable >/dev/null 2>&1
        dumpsys deviceidle force-idle >/dev/null 2>&1
    fi

    if [ "$ENABLE_APPSTANDBY" = "1" ]; then
        for a in com.instagram.android com.facebook.katana com.facebook.orca \
                 com.twitter.android com.spotify.music com.netflix.mediaclient; do
            am set-standby-bucket "$a" restricted >/dev/null 2>&1
        done
    fi

    if [ "$ENABLE_BRIGHTNESS_CAP" = "1" ]; then
        cur=$(settings get system screen_brightness 2>/dev/null)
        case "$cur" in ''|*[!0-9]*) cur=128 ;; esac
        [ ! -f "$STATE/brightness_orig" ] && echo "$cur" > "$STATE/brightness_orig"
        max=$((255 * BRIGHTNESS_CAP / 100))
        [ "$cur" -gt "$max" ] && settings put system screen_brightness "$max" >/dev/null 2>&1
    fi
    log "battery: aplicado (temp=$(read_temp_c)°C, carregando=$(is_charging && echo sim || echo nao))"
}

revert_battery() {
    dumpsys deviceidle disable >/dev/null 2>&1
    for a in com.instagram.android com.facebook.katana com.facebook.orca \
             com.twitter.android com.spotify.music com.netflix.mediaclient; do
        am set-standby-bucket "$a" active >/dev/null 2>&1
    done
    if [ -f "$STATE/brightness_orig" ]; then
        settings put system screen_brightness "$(cat "$STATE/brightness_orig")" >/dev/null 2>&1
        rm -f "$STATE/brightness_orig"
    fi
}

# --- watchdog térmico: se esquentar demais, reverte a parte agressiva ---------
thermal_watch() {
    [ "$ENABLE_THERMAL_WATCH" = "1" ] || return 0
    t=$(read_temp_c)
    case "$t" in ''|*[!0-9]*) return 0 ;; esac
    [ "$t" -le 0 ] && return 0
    if [ "$t" -ge "$THERMAL_MAX_C" ] || is_charging; then
        log "thermal: ${t}°C >= ${THERMAL_MAX_C}°C (ou carregando) — revertendo"
        revert_battery
        touch "$STATE/thermal_stop"
    fi
}
