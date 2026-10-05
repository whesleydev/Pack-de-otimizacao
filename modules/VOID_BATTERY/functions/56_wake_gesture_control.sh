#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Wake Gesture Control
# Eliminates spurious screen-on events from sensors

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings system lift_to_wake 0
        vb_settings secure wake_gesture_enabled 0
        vb_settings secure double_tap_to_wake 0
        vb_settings secure aware_enabled 0
        vb_log "WAKE" "All wake gestures disabled"
        ;;
    ECO)
        vb_settings system lift_to_wake 0
        vb_settings secure aware_enabled 0
        vb_log "WAKE" "Lift-to-wake disabled"
        ;;
    *)
        # Don't touch — respect user preference
        ;;
esac
