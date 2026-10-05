#!/system/bin/sh
# VOID BATTERY v9.1 — Vibration Intensity (reduce, NOT disable)
case "$VB_PROFILE" in
    CRITICAL)
        vb_settings system haptic_feedback_intensity 0
        vb_settings system ring_vibration_intensity 1
        vb_settings system notification_vibration_intensity 0
        ;;
    POWERSAVE|ECO)
        vb_settings system haptic_feedback_intensity 1
        vb_settings system ring_vibration_intensity 2
        vb_settings system notification_vibration_intensity 1
        ;;
    IDLE|BALANCED)
        vb_settings system haptic_feedback_intensity 2
        vb_settings system ring_vibration_intensity 3
        vb_settings system notification_vibration_intensity 2
        ;;
esac
