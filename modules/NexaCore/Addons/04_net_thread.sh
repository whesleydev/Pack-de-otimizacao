#!/system/bin/sh

apply() {
    settings put global wifi_suspend_optimizations_enabled 0
    settings put global wifi_watchdog_on 0
    settings put global netstats_poll_interval 86400000
}

reset() {
    settings delete global wifi_suspend_optimizations_enabled
    settings delete global wifi_watchdog_on
    settings delete global netstats_poll_interval
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