#!/system/bin/sh
# =============================================================================
#  service.sh - Congela a blacklist no boot e reafirma de tempo em tempo.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
_ensure_lists
boot_wait
rm -f "$STATE/stop"

[ "$ENABLE_FREEZER" = "1" ] && [ "$FREEZE_ON_BOOT" = "1" ] && freeze_all >/dev/null 2>&1
log "service: iniciado (modo=$FREEZE_MODE, intervalo=${FREEZE_INTERVAL}s)"

while :; do
    sleep "$FREEZE_INTERVAL"
    [ -f "$STATE/stop" ] && { log "service: stop pedido"; break; }
    [ "$ENABLE_FREEZER" = "1" ] || continue
    freeze_all >/dev/null 2>&1
done
