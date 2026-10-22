#!/system/bin/sh
# =============================================================================
#  service.sh - Aplica a economia no boot e vigia a temperatura.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
boot_wait
rm -f "$STATE/thermal_stop"
apply_battery
log "service: iniciado (watch=${ENABLE_THERMAL_WATCH}, max=${THERMAL_MAX_C}°C)"

while :; do
    sleep "$WATCH_INTERVAL"
    [ -f "$STATE/stop" ] && { log "service: stop pedido"; break; }
    thermal_watch
    [ -f "$STATE/thermal_stop" ] && { log "service: parado pela trava térmica"; break; }
done
