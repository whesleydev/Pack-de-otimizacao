#!/system/bin/sh
# VOID BATTERY v9.1 — Smart Reply & Notification Assistant Off
# Disables background processing of notification content for smart replies
# Saves CPU cycles on every notification — zero UX impact for most users

vb_log "SMARTREPLY" "Smart reply control — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        vb_devconfig systemui nas_generate_replies false
        vb_devconfig systemui nas_generate_actions false
        vb_devconfig notification_assistant generate_replies false
        vb_devconfig notification_assistant generate_actions false
        vb_log "SMARTREPLY" "Smart replies & actions disabled"
        ;;
    *)
        # BALANCED+: don't touch
        ;;
esac
