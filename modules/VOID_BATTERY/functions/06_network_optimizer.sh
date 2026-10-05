#!/system/bin/sh
# VOID BATTERY v9.1 — Network Optimizer (Consolidated)
# IMPROVED: Better power savings for BALANCED without connectivity impact

vb_log "NET" "Network optimization — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL)
        vb_settings global wifi_scan_always_enabled 0
        vb_settings global ble_scan_always_enabled 0
        vb_settings global mobile_data_always_on 0
        vb_settings global wifi_scan_interval_ms 600000
        vb_settings secure location_background_throttle_interval_ms 1800000
        vb_settings global wifi_power_save 1
        vb_settings global network_recommendations_enabled 0
        ;;
    POWERSAVE)
        vb_settings global wifi_scan_always_enabled 0
        vb_settings global ble_scan_always_enabled 0
        vb_settings global mobile_data_always_on 0
        vb_settings global wifi_scan_interval_ms 450000
        vb_settings secure location_background_throttle_interval_ms 900000
        vb_settings global wifi_power_save 1
        vb_settings global network_recommendations_enabled 0
        ;;
    ECO)
        vb_settings global wifi_scan_always_enabled 0
        vb_settings global ble_scan_always_enabled 0
        vb_settings global mobile_data_always_on 0
        vb_settings global wifi_scan_interval_ms 300000
        vb_settings secure location_background_throttle_interval_ms 600000
        vb_settings global wifi_power_save 1
        ;;
    IDLE)
        vb_settings global wifi_scan_always_enabled 0
        vb_settings global ble_scan_always_enabled 0
        vb_settings global mobile_data_always_on 0
        vb_settings global wifi_scan_interval_ms 300000
        vb_settings secure location_background_throttle_interval_ms 600000
        vb_settings global wifi_power_save 1
        ;;
    BALANCED)
        # IMPROVED: Disable always-scan for both WiFi and BLE
        # BLE always-scan is a silent battery killer — apps still scan on demand
        vb_settings global wifi_scan_always_enabled 0
        vb_settings global ble_scan_always_enabled 0
        vb_settings global mobile_data_always_on 1
        vb_settings global wifi_scan_interval_ms 180000
        vb_settings secure location_background_throttle_interval_ms 300000
        vb_settings global wifi_power_save 1
        ;;
    PERFORMANCE)
        vb_settings global wifi_scan_always_enabled 1
        vb_settings global ble_scan_always_enabled 1
        vb_settings global mobile_data_always_on 1
        ;;
esac

vb_log "NET" "Network configured"
