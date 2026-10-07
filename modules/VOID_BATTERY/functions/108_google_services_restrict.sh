#!/system/bin/sh
# VOID BATTERY v9.1 — Google Services Background Restrict
# IMPROVED: Added BALANCED/IDLE profile restrictions for analytics

vb_log "GSVC" "Google services restrict — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Disable Google analytics collection
        vb_devconfig gms analytics_collection_deactivated true
        vb_devconfig gms firebase_analytics_collection_deactivated true
        # Disable Google fitness background sync
        vb_devconfig gms fitness_auto_sync_enabled false
        # Disable device registration updates
        vb_devconfig gms device_registration_check_interval 86400000
        # Reduce checkin interval
        vb_devconfig gms checkin_interval 86400000
        # IMPROVED: Disable usage reporting
        vb_devconfig gms usage_reporting_enabled false
        vb_devconfig gms crash_upload_enabled false
        vb_log "GSVC" "GMS heavily restricted"
        ;;
    ECO)
        vb_devconfig gms analytics_collection_deactivated true
        vb_devconfig gms firebase_analytics_collection_deactivated true
        vb_devconfig gms checkin_interval 43200000
        vb_devconfig gms usage_reporting_enabled false
        vb_log "GSVC" "GMS analytics off, checkin 12h"
        ;;
    IDLE|BALANCED)
        # IMPROVED: Disable analytics and crash reporting even in BALANCED
        # This doesn't affect any user-facing features
        vb_devconfig gms analytics_collection_deactivated true
        vb_devconfig gms firebase_analytics_collection_deactivated true
        vb_devconfig gms usage_reporting_enabled false
        vb_devconfig gms crash_upload_enabled false
        vb_devconfig gms checkin_interval 21600000
        vb_log "GSVC" "GMS analytics off, checkin 6h (balanced)"
        ;;
esac
