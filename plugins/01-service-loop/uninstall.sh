#!/system/bin/sh
# =============================================================================
#  uninstall.sh - Para o loop e reverte os tweaks.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm"

# pede para o loop parar
touch "$STATE/stop" 2>/dev/null
# mata o processo do service, se ainda estiver rodando
for p in $(pgrep -f "$DIR/service.sh" 2>/dev/null); do
    kill "$p" 2>/dev/null
done

# reverte tweaks leves
settings delete global window_animation_scale 2>/dev/null
settings delete global transition_animation_scale 2>/dev/null
settings delete global animator_duration_scale 2>/dev/null
settings put global force_gpu_rendering 0 2>/dev/null
settings put global disable_window_blurs 0 2>/dev/null
settings put global accessibility_reduce_transparency 0 2>/dev/null
settings put global game_driver_all_apps 0 2>/dev/null
settings put global private_dns_mode opportunistic 2>/dev/null

rm -f "$STATE/stop"
echo "Pack OTM removido; loop parado e tweaks revertidos."
