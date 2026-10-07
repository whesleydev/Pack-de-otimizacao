#!/system/bin/sh
# VOID BATTERY v9.1 — Battery Stats Optimization
# Reduces battery stats collection overhead and cleans stale entries
# Stats still work — just with less granularity to save CPU/storage

vb_rate_ok "batstats" 7200 || return 0

vb_log "BSTAT" "Battery stats optimization — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Increase battery stats collection interval
        vb_devconfig battery_stats max_history_items 50
        vb_devconfig battery_stats max_history_buffer 32768
        # Disable detailed per-proc stats
        vb_settings global battery_stats_collection_enabled 0
        vb_log "BSTAT" "Stats collection minimized"
        ;;
    ECO)
        vb_devconfig battery_stats max_history_items 100
        vb_devconfig battery_stats max_history_buffer 65536
        vb_log "BSTAT" "Stats collection reduced"
        ;;
    *)
        # BALANCED+: normal stats collection
        vb_settings global battery_stats_collection_enabled 1
        ;;
esac
