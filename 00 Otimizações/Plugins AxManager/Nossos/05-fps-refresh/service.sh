#!/system/bin/sh
# =============================================================================
#  service.sh - Reafirma o refresh/game mode no boot (e uma vez por dia).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
boot_wait
apply_fps
log "service: iniciado"

while :; do
    sleep 3600
    [ -f "$STATE/stop" ] && { log "service: stop pedido"; break; }
    apply_fps
done
