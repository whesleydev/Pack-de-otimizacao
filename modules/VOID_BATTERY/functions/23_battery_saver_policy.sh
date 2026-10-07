#!/system/bin/sh
# VOID BATTERY v9.1 — Battery Saver Policy (Research-Based)
# FIX: Set adjust_brightness_disabled=true in ALL profiles
# This prevents battery saver from dimming the screen

if [ "${VB_MANAGE_STANDBY:-false}" != "true" ]; then
    vb_log "POLICY" "Battery Saver policy left under Android/OEM control"
    return 0
fi

case "$VB_PROFILE" in
    CRITICAL)
        _p="advertise_is_enabled=true,vibration_disabled=true,animation_disabled=true,soundtrigger_disabled=true,firewall_disabled=false,adjust_brightness_disabled=true,launch_boost_disabled=true,datasaver_disabled=false,enable_night_mode=true,gps_mode=2,force_all_apps_standby=true,force_background_check=true,optional_sensors_disabled=true,aod_disabled=true,quick_doze_enabled=true"
        ;;
    POWERSAVE)
        _p="vibration_disabled=false,animation_disabled=true,soundtrigger_disabled=true,launch_boost_disabled=true,datasaver_disabled=false,adjust_brightness_disabled=true,gps_mode=1,force_all_apps_standby=true,optional_sensors_disabled=true,quick_doze_enabled=true"
        ;;
    ECO)
        _p="animation_disabled=false,launch_boost_disabled=true,datasaver_disabled=true,adjust_brightness_disabled=true,force_all_apps_standby=true,quick_doze_enabled=true"
        ;;
    *)
        return 0
        ;;
esac

vb_settings global battery_saver_constants "$_p"
vb_log "POLICY" "Saver policy applied (brightness untouched)"
