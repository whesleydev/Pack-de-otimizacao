#!/system/bin/sh
# VOID BATTERY v9.1 — Display Power Management
# FIX: Removed brightness_ramp_decrease_factor and auto_brightness_enabled
# These were causing brightness fluctuation. Only safe display settings kept.

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        vb_devconfig display_manager adaptive_sleep_disabled false
        ;;
esac
vb_log "DISPWR" "Display power managed (brightness untouched)"
