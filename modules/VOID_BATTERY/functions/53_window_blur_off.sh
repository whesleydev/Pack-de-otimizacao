#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Window Blur Off
# Disables GPU-intensive window blur effects

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        vb_settings global disable_window_blurs 1
        ;;
    *)
        vb_settings global disable_window_blurs 0
        ;;
esac
vb_log "BLUR" "Window blur configured"
