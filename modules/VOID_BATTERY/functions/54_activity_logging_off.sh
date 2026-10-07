#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Activity Logging Off
# Reduces CPU/IO from activity start logging

vb_settings global activity_starts_logging_enabled 0

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig interaction_jank_monitor enabled false
        ;;
esac
vb_log "ACTLOG" "Activity logging disabled"
