#!/system/bin/sh
# VOID BATTERY v9.1 — Motion Sensor Background Restriction
# Disables background step counter, accelerometer wake events
# Front-facing apps still use sensors — only background polling stops

vb_log "MOTION" "Motion sensor background control — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Disable step counter / fitness background processing
        vb_devconfig activity_recognition activity_recognition_enabled false
        # Restrict sensor access for background apps
        for _pkg in $(pm list packages -3 2>/dev/null | sed 's/package://'); do
            vb_is_excluded "$_pkg" && continue
            vb_is_foreground "$_pkg" && continue
            appops set "$_pkg" ACTIVITY_RECOGNITION ignore 2>/dev/null
        done
        vb_log "MOTION" "Background motion sensors restricted"
        ;;
    ECO)
        vb_devconfig activity_recognition activity_recognition_enabled false
        vb_log "MOTION" "Activity recognition off"
        ;;
    *)
        # BALANCED+: sensors operate normally
        ;;
esac
