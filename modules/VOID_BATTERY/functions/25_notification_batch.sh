#!/system/bin/sh
# VOID BATTERY v9.1 — Notification Batching
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig systemui notification_coalescing_enabled true
        ;;
    *)
        vb_devconfig systemui notification_coalescing_enabled false
        ;;
esac
