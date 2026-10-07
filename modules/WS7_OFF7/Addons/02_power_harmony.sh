#!/system/bin/sh
apply() {
    settings put global ble_scan_always_available 0
    settings put global mobile_data_always_on 0
    settings put global adaptive_battery_management_enabled 1
}
reset() {
    settings delete global ble_scan_always_available
    settings delete global mobile_data_always_on
    settings delete global adaptive_battery_management_enabled
}
[ "$1" = "apply" ] || [ "$1" = "on" ] && apply || reset
