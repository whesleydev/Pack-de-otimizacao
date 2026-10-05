#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Ambient Display Control
# Comprehensive ambient/AOD management (NOT forced in BALANCED/PERFORMANCE)

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings secure doze_enabled 0
        vb_settings secure doze_always_on 0
        vb_settings secure doze_pulse_on_pick_up 0
        vb_settings secure doze_pulse_on_double_tap 0
        vb_settings secure doze_pulse_on_long_press 0
        vb_settings secure doze_quick_pickup_gesture 0
        vb_settings global ambient_enabled 0
        vb_log "AOD" "AOD/Ambient fully disabled"
        ;;
    ECO)
        vb_settings secure doze_always_on 0
        vb_settings secure doze_pulse_on_pick_up 0
        vb_settings global ambient_enabled 0
        vb_log "AOD" "AOD disabled, ambient minimal"
        ;;
    IDLE)
        vb_settings secure doze_always_on 0
        vb_log "AOD" "AOD disabled (screen off)"
        ;;
    *)
        # Don't touch — respect user preference
        ;;
esac
