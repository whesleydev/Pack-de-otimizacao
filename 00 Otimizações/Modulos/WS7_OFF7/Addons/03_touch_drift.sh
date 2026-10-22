#!/system/bin/sh
apply() {
    settings put system touch_blocking_period 40
    settings put secure long_press_timeout 150
    settings put system pointer_speed 5
    cmd device_config put input block_untrusted_touches false >/dev/null 2>&1
    cmd device_config put input velocity_tracker_strategy impulse >/dev/null 2>&1
}
reset() {
    settings delete system touch_blocking_period
    settings delete secure long_press_timeout
    settings delete system pointer_speed
    cmd device_config delete input block_untrusted_touches >/dev/null 2>&1
    cmd device_config delete input velocity_tracker_strategy >/dev/null 2>&1
}
[ "$1" = "apply" ] || [ "$1" = "on" ] && apply || reset
