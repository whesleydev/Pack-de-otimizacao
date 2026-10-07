#!/system/bin/sh
# VOID BATTERY v9.1 — Broadcast Throttle
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig activity_manager bcast_defer_delay 60000
        vb_devconfig activity_manager defer_boot_completed_broadcast 60000
        ;;
    ECO|IDLE)
        vb_devconfig activity_manager bcast_defer_delay 30000
        vb_devconfig activity_manager defer_boot_completed_broadcast 30000
        ;;
    *)
        vb_devconfig activity_manager bcast_defer_delay 15000
        ;;
esac
vb_log "BCAST" "Broadcast throttled"
