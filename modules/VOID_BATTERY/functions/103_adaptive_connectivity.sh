#!/system/bin/sh
# VOID BATTERY v9.1 — Adaptive Connectivity Manager
# IMPROVED: Added BALANCED profile — reduces unnecessary network noise

vb_log "ACONN" "Adaptive connectivity — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL)
        # Minimize radio switching
        vb_settings global wifi_watchdog_on 0
        vb_settings global captive_portal_mode 0
        vb_settings global network_scoring_ui_enabled 0
        vb_settings global network_recommendations_enabled 0
        vb_settings global wifi_networks_available_notification_on 0
        vb_log "ACONN" "Network scoring/watchdog/portal OFF"
        ;;
    POWERSAVE|ECO)
        vb_settings global captive_portal_mode 0
        vb_settings global network_scoring_ui_enabled 0
        vb_settings global network_recommendations_enabled 0
        vb_settings global wifi_networks_available_notification_on 0
        vb_log "ACONN" "Portal/scoring/notifications OFF"
        ;;
    IDLE)
        # Screen off: minimize network noise
        vb_settings global network_recommendations_enabled 0
        vb_settings global wifi_networks_available_notification_on 0
        vb_log "ACONN" "Network notifications off (idle)"
        ;;
    BALANCED)
        # IMPROVED: Disable network recommendations and scoring
        # These generate constant background checks for "better" networks
        vb_settings global network_scoring_ui_enabled 0
        vb_settings global network_recommendations_enabled 0
        vb_settings global wifi_networks_available_notification_on 0
        vb_log "ACONN" "Network scoring/recommendations off (balanced)"
        ;;
    *)
        # PERFORMANCE: restore network features
        vb_settings global wifi_watchdog_on 1
        vb_settings global captive_portal_mode 1
        ;;
esac
