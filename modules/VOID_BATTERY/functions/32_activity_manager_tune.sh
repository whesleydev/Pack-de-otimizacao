#!/system/bin/sh
# VOID BATTERY v9.1 — Activity Manager Tuning

case "$VB_PROFILE" in
    CRITICAL)
        vb_devconfig activity_manager max_cached_processes 8
        vb_devconfig activity_manager max_empty_time_millis 600000
        vb_devconfig activity_manager kill_bg_restricted_cached_idle true
        vb_devconfig activity_manager kill_bg_restricted_cached_idle_settle_time_ms 30000
        ;;
    POWERSAVE)
        vb_devconfig activity_manager max_cached_processes 12
        vb_devconfig activity_manager max_empty_time_millis 900000
        vb_devconfig activity_manager kill_bg_restricted_cached_idle true
        ;;
    ECO)
        vb_devconfig activity_manager max_cached_processes 16
        vb_devconfig activity_manager max_empty_time_millis 1200000
        ;;
    IDLE|BALANCED)
        vb_devconfig activity_manager max_cached_processes 24
        vb_devconfig activity_manager max_empty_time_millis 1800000
        ;;
    PERFORMANCE)
        vb_devconfig activity_manager max_cached_processes 32
        vb_devconfig activity_manager max_empty_time_millis 3600000
        ;;
esac
vb_log "AM" "Activity Manager tuned"
