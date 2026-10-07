#!/system/bin/sh
# VOID BATTERY v9.1 — Thermal Config Tuning
# FIX: Removed thermal_brightness_factor — was dimming the screen
# Only safe thermal power management kept

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        vb_devconfig connectivity_thermal_power_manager enabled true
        ;;
esac
vb_log "THERM" "Thermal config tuned (brightness untouched)"
