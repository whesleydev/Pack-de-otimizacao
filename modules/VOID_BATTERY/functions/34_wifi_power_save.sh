#!/system/bin/sh
# VOID BATTERY v9.1 — WiFi Power Save
# IMPROVED: Enable wifi_power_save for BALANCED and ECO/IDLE

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings global wifi_sleep_policy 2
        vb_settings global wifi_scan_throttle_enabled 1
        vb_settings global wifi_verbose_logging_enabled 0
        vb_settings global wifi_power_save 1
        ;;
    ECO|IDLE)
        vb_settings global wifi_sleep_policy 2
        vb_settings global wifi_scan_throttle_enabled 1
        vb_settings global wifi_verbose_logging_enabled 0
        vb_settings global wifi_power_save 1
        ;;
    BALANCED)
        # IMPROVED: Enable wifi power save and scan throttle
        vb_settings global wifi_sleep_policy 0
        vb_settings global wifi_scan_throttle_enabled 1
        vb_settings global wifi_verbose_logging_enabled 0
        vb_settings global wifi_power_save 1
        ;;
    PERFORMANCE)
        vb_settings global wifi_sleep_policy 0
        ;;
esac
vb_log "WIFI" "Power save configured"
