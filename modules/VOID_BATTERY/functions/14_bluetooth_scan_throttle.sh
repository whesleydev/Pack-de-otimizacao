#!/system/bin/sh
# VOID BATTERY v9.1 — BLE Scan Throttle

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL)
        vb_settings global ble_scan_always_enabled 0
        vb_settings global ble_scan_low_power_interval_ms 30000
        vb_settings global ble_scan_balanced_interval_ms 15000
        vb_settings global ble_scan_low_power_window_ms 1500
        ;;
    POWERSAVE|ECO)
        vb_settings global ble_scan_always_enabled 0
        vb_settings global ble_scan_low_power_interval_ms 20000
        vb_settings global ble_scan_balanced_interval_ms 10000
        ;;
    *)
        vb_settings global ble_scan_low_power_interval_ms 15000
        vb_settings global ble_scan_balanced_interval_ms 8000
        ;;
esac
vb_log "BT" "BLE scan throttled"
