#!/system/bin/sh
# VOID BATTERY v9.1 — Auto-Update Restriction
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings global package_verifier_enable 0
        vb_devconfig finsky auto_update_enabled false
        ;;
    *)
        vb_settings global package_verifier_enable 1
        vb_devconfig finsky auto_update_wifi_only true
        ;;
esac
vb_log "UPDATE" "Auto-update restricted"
