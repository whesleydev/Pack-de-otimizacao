#!/system/bin/sh
# VOID BATTERY v9.1 — Sync Throttle
# IMPROVED: More effective sync delays per profile

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL)   _d=7200 ;;
    POWERSAVE)  _d=3600 ;;
    ECO)        _d=1800 ;;
    IDLE)       _d=1200 ;;
    BALANCED)   _d=900 ;;
    *)          _d=600 ;;
esac

vb_settings global sync_max_retry_delay_in_seconds "$_d"

# IMPROVED: Disable automatic sync for non-essential accounts when screen off
if [ "$VB_SCREEN" = "0" ] && [ "$VB_CHARGING" = "0" ]; then
    case "$VB_PROFILE" in
        CRITICAL|POWERSAVE)
            vb_devconfig content_captures smart_auto_sync_idle true
            ;;
    esac
fi

vb_log "SYNC" "Retry delay=${_d}s"
