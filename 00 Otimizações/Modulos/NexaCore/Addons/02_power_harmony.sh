#!/system/bin/sh

apply() {
    settings put global ble_scan_always_available 0
    settings put global mobile_data_always_on 0
    settings put global adaptive_battery_management_enabled 1
    settings put global app_auto_restriction_enabled 1
    settings put global tether_offload_disabled 0
    settings put global battery_saver_constants "animation_disabled=true,vibration_disabled=true,sound_trigger_disabled=true,full_backup_disabled=true,keyvalue_backup_disabled=true,defer_full_backup=true,defer_keyvalue_backup=true"
}

reset() {
    settings delete global ble_scan_always_available
    settings delete global mobile_data_always_on
    settings delete global adaptive_battery_management_enabled
    settings delete global app_auto_restriction_enabled
    settings delete global tether_offload_disabled
    settings delete global battery_saver_constants
}

ACTION=$(echo "$1" | tr '[:upper:]' '[:lower:]')

case "$ACTION" in
    enable|on|apply|1)
        apply
        ;;
    reset|remove|off|disable|0)
        reset
        ;;
esac