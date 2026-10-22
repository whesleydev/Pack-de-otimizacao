#!/system/bin/sh

apply() {
    settings put global fstrim_mandatory_interval 86400000
    setprop persist.sys.use_dithering 1
    setprop debug.performance.tuning 1
    cmd device_config put activity_manager process_start_async true >/dev/null 2>&1
    cmd device_config put activity_manager max_previous_time 60000 >/dev/null 2>&1
}

reset() {
    settings delete global fstrim_mandatory_interval
    setprop persist.sys.use_dithering ""
    setprop debug.performance.tuning ""
    cmd device_config delete activity_manager process_start_async >/dev/null 2>&1
    cmd device_config delete activity_manager max_previous_time >/dev/null 2>&1
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