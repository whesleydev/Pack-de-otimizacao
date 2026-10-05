#!/system/bin/sh
# VOID BATTERY v9.1 — Memory Compaction & Trim
# Sends TRIM_MEMORY signals to background apps to free RAM
# Reduces swap pressure → fewer CPU wakes → better battery

vb_rate_ok "memtrim" 900 || return 0

vb_log "MEM" "Memory compaction — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Aggressive: compact all cached apps
        vb_devconfig activity_manager use_compaction true
        vb_devconfig activity_manager compact_action_1 4
        vb_devconfig activity_manager compact_action_2 4
        vb_devconfig activity_manager compact_throttle_1 500
        vb_devconfig activity_manager compact_throttle_2 5000

        # Force trim background apps
        am send-trim-memory --user current HIDDEN COMPLETE 2>/dev/null
        vb_log "MEM" "Aggressive compaction + TRIM_COMPLETE sent"
        ;;
    ECO|IDLE)
        vb_devconfig activity_manager use_compaction true
        vb_devconfig activity_manager compact_action_1 2
        vb_devconfig activity_manager compact_action_2 4

        am send-trim-memory --user current CACHED MODERATE 2>/dev/null
        vb_log "MEM" "Moderate compaction + TRIM_MODERATE sent"
        ;;
    *)
        vb_devconfig activity_manager use_compaction true
        ;;
esac
