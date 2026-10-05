#!/system/bin/sh
# VOID BATTERY v9.1 — Content Observer Throttle
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig content_capture content_capture_enabled false
        vb_devconfig textclassifier textclassifier_enabled false
        vb_devconfig attention_manager_service keep_screen_on_enabled false
        ;;
    ECO|IDLE)
        vb_devconfig content_capture content_capture_enabled false
        vb_devconfig textclassifier textclassifier_enabled true
        ;;
esac
vb_log "CONTENT" "Content observers throttled"
