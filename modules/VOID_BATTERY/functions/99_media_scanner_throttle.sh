#!/system/bin/sh
# VOID BATTERY v9.1 — Media Scanner Throttle
# Prevents media scanner from running during low-battery
# Media files are still indexed when battery recovers

vb_log "MEDIA" "Media scanner control — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Stop media scanner service
        am force-stop com.android.providers.media 2>/dev/null
        # Disable media scanner trigger broadcasts for background apps
        vb_devconfig storage media_scanner_enabled false
        vb_log "MEDIA" "Media scanner stopped (low battery)"
        ;;
    ECO)
        # Throttle but don't kill
        vb_devconfig storage media_scanner_scan_interval 3600000
        vb_log "MEDIA" "Media scanner throttled to 1h"
        ;;
    *)
        vb_devconfig storage media_scanner_enabled true
        ;;
esac
