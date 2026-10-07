#!/system/bin/sh
# VOID BATTERY v9.1 — Sync Adapter Throttle
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL)
        vb_devconfig content sync_manager_constants "initial_sync_retry_time_in_seconds=120,max_sync_retry_time_in_seconds=7200"
        ;;
    POWERSAVE)
        vb_devconfig content sync_manager_constants "initial_sync_retry_time_in_seconds=60,max_sync_retry_time_in_seconds=3600"
        ;;
esac
