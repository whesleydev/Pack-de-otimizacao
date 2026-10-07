#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Power Hint Optimizer
# Disables launch boost and other power hints that drain battery

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig activity_manager disable_launch_boost true
        vb_devconfig activity_manager proactive_kills_enabled true
        vb_settings global power_sounds_enabled 0
        ;;
    ECO|IDLE)
        vb_devconfig activity_manager disable_launch_boost true
        ;;
esac
vb_log "POWER" "Power hints optimized"
