#!/system/bin/sh
# VOID BATTERY v9.1 — Intent Filter & Broadcast Receiver Throttle
# Limits implicit broadcast receivers to reduce background wake events
# Only affects background apps — foreground apps work normally

vb_log "INTENT" "Intent filter throttle — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Enable strict implicit broadcast restrictions
        vb_devconfig activity_manager defer_boot_completed_broadcast 60000
        vb_devconfig activity_manager boot_time_temp_allowlist_duration 10000
        vb_devconfig activity_manager fg_to_bg_fgs_grace_duration 5000
        vb_devconfig activity_manager fgs_start_foreground_timeout 5000
        vb_log "INTENT" "Strict broadcast deferral (60s boot, 5s grace)"
        ;;
    ECO)
        vb_devconfig activity_manager defer_boot_completed_broadcast 30000
        vb_devconfig activity_manager boot_time_temp_allowlist_duration 20000
        vb_log "INTENT" "Moderate broadcast deferral"
        ;;
    *)
        # BALANCED+: default behavior
        ;;
esac
