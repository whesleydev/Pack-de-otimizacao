#!/system/bin/sh
# VOID BATTERY v9.1 — Notification History & Bubbles Off
# Disables notification history storage and bubble floating windows
# Reduces I/O writes and background processing per notification

vb_log "NOTHIST" "Notification history control — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        # Disable notification history (saves I/O and storage operations)
        vb_settings secure notification_history_enabled 0
        # Disable bubbles (prevents persistent overlay + service running)
        vb_settings secure notification_bubbles 0
        # Disable snoozing (removes timer-based wake events)
        vb_devconfig systemui notification_snooze_enabled false
        vb_log "NOTHIST" "Notification history, bubbles, snooze disabled"
        ;;
    *)
        # Don't touch — user might want these features
        ;;
esac
