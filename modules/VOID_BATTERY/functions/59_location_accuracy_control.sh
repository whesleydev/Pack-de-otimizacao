#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Location Accuracy Control
# Manages location update frequency and accuracy requirements

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL)
        vb_settings secure location_background_throttle_interval_ms 1800000
        vb_settings secure location_background_throttle_proximity_alert_interval_ms 1800000
        vb_devconfig location location_background_throttle_package_whitelist ""
        ;;
    POWERSAVE)
        vb_settings secure location_background_throttle_interval_ms 900000
        ;;
    ECO|IDLE)
        vb_settings secure location_background_throttle_interval_ms 600000
        ;;
    BALANCED)
        vb_settings secure location_background_throttle_interval_ms 300000
        ;;
esac
vb_log "LOC" "Location accuracy configured"
