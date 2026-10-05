#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] App Compaction Tuning
# Fine-tune how Android compresses cached apps in memory

vb_devconfig activity_manager use_compaction true

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig activity_manager compact_action_1 4
        vb_devconfig activity_manager compact_action_2 4
        vb_devconfig activity_manager compact_throttle_1 5000
        vb_devconfig activity_manager compact_throttle_2 10000
        vb_devconfig activity_manager compact_throttle_3 500
        vb_devconfig activity_manager compact_throttle_4 10000
        ;;
    ECO|IDLE)
        vb_devconfig activity_manager compact_action_1 2
        vb_devconfig activity_manager compact_action_2 4
        ;;
esac
vb_log "COMPACT" "App compaction tuned"
