#!/system/bin/sh

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
MODDIR=$SCRIPT_DIR

CONFIG=$MODDIR/config.prop
GAMELIST=$MODDIR/gamelist.txt

# Expose MODDIR to WebUI
echo "$MODDIR" > /data/local/tmp/.phoenix_dir 2>/dev/null

# Read config from Android Settings (works without root)
PEAK_RATE=$(settings get global phoenix3_PEAK_RATE 2>/dev/null)
MIN_RATE=$(settings get global phoenix3_MIN_RATE 2>/dev/null)
SLEEP_INTERVAL=$(settings get global phoenix3_SLEEP_INTERVAL 2>/dev/null)
AUTO_BOOST=$(settings get global phoenix3_AUTO_BOOST 2>/dev/null)
DNS_SERVER=$(settings get global phoenix3_DNS_SERVER 2>/dev/null)
THERMAL_MODE=$(settings get global phoenix3_THERMAL_MODE 2>/dev/null)

# Fallback defaults
[ -z "$PEAK_RATE" ] || [ "$PEAK_RATE" = "null" ] && PEAK_RATE=120
[ -z "$MIN_RATE" ] || [ "$MIN_RATE" = "null" ] && MIN_RATE=60
[ -z "$SLEEP_INTERVAL" ] || [ "$SLEEP_INTERVAL" = "null" ] && SLEEP_INTERVAL=5
[ -z "$AUTO_BOOST" ] || [ "$AUTO_BOOST" = "null" ] && AUTO_BOOST=1

# Rebuild gamelist.txt from saved data on boot
GAMELIST_TMP=/data/local/tmp/.phoenix_gamelist
GAMELIST_PKGS=""

# Try tmp file first, then settings
if [ -f "$GAMELIST_TMP" ]; then
    GAMELIST_PKGS=$(cat "$GAMELIST_TMP" 2>/dev/null)
fi
if [ -z "$GAMELIST_PKGS" ] || [ "$GAMELIST_PKGS" = "null" ]; then
    GAMELIST_PKGS=$(settings get global phoenix3_GAMELIST 2>/dev/null)
fi

if [ -n "$GAMELIST_PKGS" ] && [ "$GAMELIST_PKGS" != "null" ]; then
    echo "# Phoenix Boost" > "$GAMELIST"
    echo "$GAMELIST_PKGS" | tr ',' '\n' | while IFS= read -r pkg; do
        pkg=$(echo "$pkg" | tr -d ' \r')
        [ -n "$pkg" ] && echo "$pkg" >> "$GAMELIST"
    done
    # Restore tmp file for WebUI
    echo "$GAMELIST_PKGS" > "$GAMELIST_TMP" 2>/dev/null
fi

# Re-apply persistent tweaks on boot
if [ -n "$DNS_SERVER" ] && [ "$DNS_SERVER" != "null" ]; then
    settings put global private_dns_mode hostname 2>/dev/null
    settings put global private_dns_specifier "$DNS_SERVER" 2>/dev/null
fi
if [ -n "$THERMAL_MODE" ] && [ "$THERMAL_MODE" != "null" ]; then
    cmd thermalservice override-status "$THERMAL_MODE" 2>/dev/null
fi

_read_pkg() {
    local raw
    raw=$(tr -d '\0' < "$1/cmdline" 2>/dev/null) || return
    echo "${raw%%:*}" | head -c 128
}

get_foreground_app() {
    [ -f "$GAMELIST" ] || return
    local pkg oom

    # Primary: dumpsys (non-root, works on Android 12+)
    pkg=$(dumpsys activity activities 2>/dev/null \
        | grep -m1 "mResumedActivity" \
        | sed 's/.*{[^ ]* [^ ]* \([^/]*\).*/\1/' \
        | tr -d ' ')
    if [ -n "$pkg" ] && grep -qxF "$pkg" "$GAMELIST" 2>/dev/null; then
        echo "$pkg"; return
    fi

    # Fallback: oom_score_adj (requiere shell privilegiado)
    for pid_dir in /proc/[0-9]*; do
        [ -f "$pid_dir/oom_score_adj" ] || continue
        oom=$(cat "$pid_dir/oom_score_adj" 2>/dev/null)
        [ "${oom:-1}" -le 0 ] 2>/dev/null || continue
        [ -f "$pid_dir/cmdline" ] || continue
        pkg=$(_read_pkg "$pid_dir")
        [ -z "$pkg" ] && continue
        grep -qxF "$pkg" "$GAMELIST" 2>/dev/null || continue
        echo "$pkg"; return
    done

    echo ""
}

do_boost() {
    settings put system peak_refresh_rate "$PEAK_RATE" 2>/dev/null
    settings put system min_refresh_rate "$PEAK_RATE" 2>/dev/null
    settings put global animator_duration_scale 0.5 2>/dev/null
    settings put global transition_animation_scale 0.5 2>/dev/null
    settings put global window_animation_scale 0.5 2>/dev/null
    echo "boosting" > /data/local/tmp/.phoenix_state 2>/dev/null
}

do_reset() {
    settings put system peak_refresh_rate "$PEAK_RATE" 2>/dev/null
    settings put system min_refresh_rate "$MIN_RATE" 2>/dev/null
    settings put global animator_duration_scale 1.0 2>/dev/null
    settings put global transition_animation_scale 1.0 2>/dev/null
    settings put global window_animation_scale 1.0 2>/dev/null
    echo "idle" > /data/local/tmp/.phoenix_state 2>/dev/null
}

echo "idle" > /data/local/tmp/.phoenix_state 2>/dev/null
echo $$ > /data/local/tmp/.phoenix_pid 2>/dev/null

# ── Notificación de servicio activo (estilo GoodPing) ─────────────────────────
cmd notification post -t 'Phoenix 🔥' 'PhoenixBoost' " Service active ✅" 2>/dev/null

GAME_ACTIVE=0

while true; do
    [ -f "$CONFIG" ] && . "$CONFIG"

    if [ "$AUTO_BOOST" = "1" ]; then
        MATCHED=$(get_foreground_app)
        if [ -n "$MATCHED" ]; then
            if [ "$GAME_ACTIVE" = "0" ]; then
                do_boost
                echo "$MATCHED" > /data/local/tmp/.phoenix_game 2>/dev/null
                cmd notification post -S bigtext -t 'Phoenix 🔥' 'PhoenixBoost' " Game detected: $MATCHED 🎮" 2>/dev/null
                GAME_ACTIVE=1
            fi
        else
            if [ "$GAME_ACTIVE" = "1" ]; then
                do_reset
                echo "" > /data/local/tmp/.phoenix_game 2>/dev/null
                cmd notification cancel 'PhoenixBoost' 2>/dev/null
                GAME_ACTIVE=0
            fi
        fi
    else
        if [ "$GAME_ACTIVE" = "1" ]; then
            do_reset
            echo "" > /data/local/tmp/.phoenix_game 2>/dev/null
            GAME_ACTIVE=0
        fi
    fi

    sleep "$SLEEP_INTERVAL"
done &

# Re-apply DNS on boot
DNS_SERVER=$(settings get global phoenix3_DNS_SERVER 2>/dev/null)
if [ -n "$DNS_SERVER" ] && [ "$DNS_SERVER" != "null" ] && [ "$DNS_SERVER" != "" ]; then
    settings put global private_dns_mode hostname 2>/dev/null
    settings put global private_dns_specifier "$DNS_SERVER" 2>/dev/null
fi
