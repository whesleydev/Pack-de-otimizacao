#!/system/bin/sh
# VOID BATTERY v9.1 — Alarm Manager Tuning
# IMPROVED: Added BALANCED profile — batches alarms to reduce wakeups

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL)
        vb_devconfig alarm_manager min_futurity_ms 10000
        vb_devconfig alarm_manager min_interval_ms 60000
        vb_devconfig alarm_manager allow_while_idle_quota 3
        vb_devconfig alarm_manager allow_while_idle_compat_quota 3
        vb_devconfig alarm_manager allow_while_idle_window_ms 20000
        ;;
    POWERSAVE)
        vb_devconfig alarm_manager min_futurity_ms 5000
        vb_devconfig alarm_manager min_interval_ms 30000
        vb_devconfig alarm_manager allow_while_idle_quota 5
        vb_devconfig alarm_manager allow_while_idle_compat_quota 5
        ;;
    ECO|IDLE)
        vb_devconfig alarm_manager min_futurity_ms 5000
        vb_devconfig alarm_manager allow_while_idle_quota 8
        vb_devconfig alarm_manager allow_while_idle_compat_quota 8
        ;;
    BALANCED)
        # IMPROVED: Gentle alarm batching — reduces wakeups
        vb_devconfig alarm_manager min_futurity_ms 5000
        vb_devconfig alarm_manager allow_while_idle_quota 10
        vb_devconfig alarm_manager allow_while_idle_compat_quota 10
        ;;
esac
vb_log "ALARM" "Alarm manager tuned"
