#!/system/bin/sh
# VOID BATTERY v9.1 — Smart Battery Saver (Hysteresis)

vb_log "SAVER" "Evaluating — ${VB_LEVEL}% Charging:$VB_CHARGING"

_sf="$VB_LOG_DIR/.saver_state"
_cur=$(cat "$_sf" 2>/dev/null || echo off)

if [ "$VB_CHARGING" = "1" ]; then
    [ "$_cur" = "on" ] && {
        vb_settings global low_power 0
        vb_settings global low_power_sticky 0
        echo off > "$_sf"
        vb_log "SAVER" "OFF (charging)"
    }
elif [ "$VB_LEVEL" -le 15 ]; then
    [ "$_cur" != "on" ] && {
        vb_settings global low_power 1
        vb_settings global low_power_sticky 1
        echo on > "$_sf"
        vb_log "SAVER" "ON (${VB_LEVEL}%)"
    }
elif [ "$VB_LEVEL" -ge 50 ] && [ "$_cur" = "on" ]; then
    vb_settings global low_power 0
    vb_settings global low_power_sticky 0
    echo off > "$_sf"
    vb_log "SAVER" "OFF (recovered ${VB_LEVEL}%)"
fi

vb_settings global automatic_power_save_mode 1
vb_settings global dynamic_power_savings_enabled 1
vb_settings global low_power_trigger_level 20
