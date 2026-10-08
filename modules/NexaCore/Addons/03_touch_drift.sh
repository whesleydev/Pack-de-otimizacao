#!/system/bin/sh

apply() {
    settings put system touch_sensitivity 1
    settings put secure tap_duration_threshold 0
    cmd device_config put input block_untrusted_touches false >/dev/null 2>&1
    cmd device_config put input_native_boot palm_rejection_enabled false >/dev/null 2>&1
    cmd device_config put input velocity_tracker_strategy impulse >/dev/null 2>&1
}

reset() {
    settings delete system touch_sensitivity
    settings delete secure tap_duration_threshold
    cmd device_config delete input block_untrusted_touches >/dev/null 2>&1
    cmd device_config delete input_native_boot palm_rejection_enabled >/dev/null 2>&1
    cmd device_config delete input velocity_tracker_strategy >/dev/null 2>&1
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