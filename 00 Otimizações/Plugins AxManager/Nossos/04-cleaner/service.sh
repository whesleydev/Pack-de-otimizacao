#!/system/bin/sh
# =============================================================================
#  service.sh - Limpeza periódica em segundo plano.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
boot_wait
run_clean
log "service: iniciado (intervalo=${CLEAN_INTERVAL}s)"

while :; do
    sleep "$CLEAN_INTERVAL"
    [ -f "$STATE/stop" ] && { log "service: stop pedido"; break; }
    run_clean
done
