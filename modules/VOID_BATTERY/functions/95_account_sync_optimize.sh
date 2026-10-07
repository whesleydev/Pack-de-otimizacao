#!/system/bin/sh
# VOID BATTERY v9.1 — Account Sync Optimization
# Intelligently manages auto-sync to reduce background network/CPU usage
# Only adjusts sync frequency — never deletes accounts or data

vb_log "SYNC" "Account sync optimization — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL)
        # Disable auto-sync entirely in critical mode
        cmd content call --uri content://settings/global \
            --method PUT_global --arg account_sync_enabled --extra_value:i:0 2>/dev/null
        vb_settings global account_sync_enabled 0
        vb_log "SYNC" "Auto-sync disabled (critical)"
        ;;
    POWERSAVE)
        # Keep sync enabled but increase polling intervals
        vb_devconfig gms network_sync_interval 3600
        vb_log "SYNC" "Sync interval: 1h (powersave)"
        ;;
    ECO)
        vb_devconfig gms network_sync_interval 1800
        vb_log "SYNC" "Sync interval: 30m (eco)"
        ;;
    *)
        # Restore auto-sync
        vb_settings global account_sync_enabled 1
        ;;
esac
