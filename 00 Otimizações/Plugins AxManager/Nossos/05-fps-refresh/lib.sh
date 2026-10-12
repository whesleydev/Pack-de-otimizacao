#!/system/bin/sh
# =============================================================================
#  lib.sh - FPS & Refresh. Guarda o valor antigo antes de escrever.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm_fps"
mkdir -p "$STATE" 2>/dev/null || STATE="$DIR/state"
mkdir -p "$STATE" 2>/dev/null
CFG="$STATE/config"

# config padrão
TARGET_HZ=0          # 0 = usa o máximo do painel
FORCE_MAX_HZ=1
GAME_MODE=1
GAME_APPS="com.dts.freefireth com.dts.freefiremax com.activision.callofduty.shooter com.mobile.legends com.tencent.ig"
FPS_OVERLAY=1        # mostra os FPS (device_config game_overlay)
FPS_DS=0.9

[ -f "$CFG" ] && . "$CFG" 2>/dev/null

log() { echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$STATE/loop.log"; }

save_default_config() {
    [ -f "$CFG" ] && return 0
    {
        echo "TARGET_HZ=$TARGET_HZ"
        echo "FORCE_MAX_HZ=$FORCE_MAX_HZ"
        echo "GAME_MODE=$GAME_MODE"
        echo "GAME_APPS=\"$GAME_APPS\""
        echo "FPS_OVERLAY=$FPS_OVERLAY"
        echo "FPS_DS=$FPS_DS"
    } > "$CFG"
}

boot_wait() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
}

panel_max_hz() {
    dumpsys display 2>/dev/null | tr ',' '\n' | sed -n 's/.*fps=\([0-9][0-9]*\).*/\1/p' | sort -n | tail -n 1
}

apply_fps() {
    hz="$TARGET_HZ"
    [ "$hz" = "0" ] && hz="$(panel_max_hz)"
    case "$hz" in ''|*[!0-9]*) hz="" ;; esac

    if [ "$FORCE_MAX_HZ" = "1" ] && [ -n "$hz" ]; then
        for k in peak_refresh_rate min_refresh_rate; do
            [ ! -f "$STATE/${k}_orig" ] && settings get system "$k" > "$STATE/${k}_orig" 2>/dev/null
        done
        settings put system peak_refresh_rate "$hz" >/dev/null 2>&1
        settings put system min_refresh_rate "$hz" >/dev/null 2>&1
    fi

    if [ "$GAME_MODE" = "1" ]; then
        for p in $GAME_APPS; do
            cmd game set --mode performance "$p" >/dev/null 2>&1
            if [ "$FPS_OVERLAY" = "1" ] && [ -n "$hz" ]; then
                device_config put game_overlay "$p" \
                    "mode=2,fps=$hz,downscaleFactor=$FPS_DS:mode=3,fps=$hz,downscaleFactor=$FPS_DS" >/dev/null 2>&1
            fi
        done
    fi
    log "fps: aplicado (hz=${hz:-?}, game_mode=$GAME_MODE, overlay=$FPS_OVERLAY)"
}

revert_fps() {
    if [ -f "$STATE/peak_refresh_rate_orig" ]; then
        settings put system peak_refresh_rate "$(cat "$STATE/peak_refresh_rate_orig")" >/dev/null 2>&1
    else
        settings delete system peak_refresh_rate >/dev/null 2>&1
    fi
    if [ -f "$STATE/min_refresh_rate_orig" ]; then
        settings put system min_refresh_rate "$(cat "$STATE/min_refresh_rate_orig")" >/dev/null 2>&1
    else
        settings delete system min_refresh_rate >/dev/null 2>&1
    fi
    rm -f "$STATE"/peak_refresh_rate_orig "$STATE"/min_refresh_rate_orig
    for p in $GAME_APPS; do
        device_config delete game_overlay "$p" >/dev/null 2>&1
        cmd game set --mode default "$p" >/dev/null 2>&1
    done
}
