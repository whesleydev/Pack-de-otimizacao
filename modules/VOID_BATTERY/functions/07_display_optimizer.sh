#!/system/bin/sh
# VOID BATTERY v9.1 — Display Optimizer

vb_log "DISP" "Display optimization — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL)   _a=0.25 ;;
    POWERSAVE)  _a=0.5 ;;
    ECO)        _a=0.5 ;;
    IDLE)       _a=0.5 ;;
    BALANCED)   _a=0.7 ;;
    PERFORMANCE) _a=1.0 ;;
esac

vb_settings global window_animation_scale "$_a"
vb_settings global transition_animation_scale "$_a"
vb_settings global animator_duration_scale "$_a"

# Refresh rate (don't touch in PERFORMANCE)
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings system peak_refresh_rate 60.0
        vb_settings system min_refresh_rate 60.0
        ;;
    ECO|IDLE)
        vb_settings system peak_refresh_rate 90.0
        vb_settings system min_refresh_rate 60.0
        ;;
    BALANCED)
        vb_settings system peak_refresh_rate 120.0
        vb_settings system min_refresh_rate 60.0
        ;;
esac

vb_log "DISP" "Animations=${_a}x"
