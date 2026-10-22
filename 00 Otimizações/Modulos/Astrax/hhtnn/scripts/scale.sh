#!/system/bin/sh
PKG="$1"
DS="$2"
[ -z "$PKG" ] && exit 1

b=$(getprop ro.build.version.release 2>/dev/null | cut -d. -f1)
b=${b:-12}
[ "$b" -lt 13 ] && exit 0

fps=$(settings get system peak_refresh_rate 2>/dev/null | cut -d. -f1)
[ -z "$fps" ] || [ "$fps" = "null" ] && fps=60

is_disable() { [ -z "$1" ] || [ "$1" = "disable" ] || [ "$1" = "1.0" ] || [ "$1" = "1" ]; }

if is_disable "$DS"; then
    device_config set_sync_disabled_for_tests none
    device_config delete game_overlay "$PKG" 2>/dev/null
    device_config clear_override game_overlay "$PKG" 2>/dev/null
    cmd game reset --mode 2 --user 0 "$PKG" 2>/dev/null
    cmd game reset --mode 3 --user 0 "$PKG" 2>/dev/null
    cmd game mode standard "$PKG" 2>/dev/null
    cmd game set --mode 2 "$PKG" 2>/dev/null
    cmd game mode performance "$PKG" 2>/dev/null
else
    device_config set_sync_disabled_for_tests persistent
    device_config delete game_overlay "$PKG" 2>/dev/null
    device_config put game_overlay "$PKG" "mode=2,fps=${fps},loadingBoost=2147483647,downscaleFactor=${DS}"
    device_config clear_override game_overlay "$PKG" 2>/dev/null
    cmd game set --mode 2 --downscale "$DS" "$PKG" 2>/dev/null
    cmd game mode performance "$PKG" 2>/dev/null
    sleep 0.4
    cmd activity force-stop "$PKG" 2>/dev/null
fi
