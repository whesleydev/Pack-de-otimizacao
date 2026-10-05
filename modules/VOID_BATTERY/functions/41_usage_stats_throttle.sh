#!/system/bin/sh
# VOID BATTERY v9.1 — Usage Stats Throttle
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig usagestats usage_stats_collection_interval_ms 7200000
        ;;
    ECO|IDLE)
        vb_devconfig usagestats usage_stats_collection_interval_ms 3600000
        ;;
esac
