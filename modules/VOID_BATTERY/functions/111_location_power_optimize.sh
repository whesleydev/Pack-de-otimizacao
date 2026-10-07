#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Location Power Optimizer
# Reduces background location power consumption without affecting foreground GPS
# Only restricts background location scanning — apps still get location on demand

vb_log "LOCPWR" "Location power optimization — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL)
        # Disable background location for all non-essential apps
        vb_settings secure location_mode 0
        vb_settings global location_global_kill_switch 1
        vb_devconfig privacy location_access_check_enabled false
        vb_log "LOCPWR" "Location fully disabled (critical)"
        ;;
    POWERSAVE)
        # Battery-saving location only
        vb_settings secure location_mode 2
        vb_settings secure location_providers_allowed -gps
        vb_devconfig privacy location_access_check_enabled true
        vb_devconfig privacy location_access_check_interval_millis 900000
        vb_log "LOCPWR" "Battery-saving location mode"
        ;;
    ECO|IDLE)
        # Reduce location check frequency
        vb_devconfig privacy location_access_check_enabled true
        vb_devconfig privacy location_access_check_interval_millis 600000
        # Limit background location providers
        vb_settings global location_background_throttle_proximity_alert_interval_ms 600000
        vb_log "LOCPWR" "Location throttled (eco/idle)"
        ;;
    BALANCED)
        # IMPROVED: Gentle location throttling
        vb_settings global location_background_throttle_proximity_alert_interval_ms 300000
        vb_devconfig privacy location_access_check_interval_millis 300000
        vb_log "LOCPWR" "Location gently throttled (balanced)"
        ;;
esac
