#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Abusive App Auto-Restriction
# From Aatricks/Android-battery-optimizer research
# Enables Android's built-in abusive app tracker

vb_devconfig activity_manager bg_auto_restrict_abusive_apps true
vb_devconfig activity_manager bg_current_drain_auto_restrict_abusive_apps_enabled true

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig activity_manager bg_current_drain_threshold_to_bg_restricted 20
        vb_devconfig activity_manager bg_prompt_fgs_on_long_running true
        ;;
    ECO|IDLE)
        vb_devconfig activity_manager bg_current_drain_threshold_to_bg_restricted 40
        ;;
esac

vb_log "ABUSE" "Abusive app auto-restriction enabled"
