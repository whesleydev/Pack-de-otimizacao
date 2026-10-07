#!/system/bin/sh
# VOID BATTERY v9.1 — App Hibernation

if [ "${VB_MANAGE_STANDBY:-false}" != "true" ]; then
    vb_log "HIBER" "App hibernation left under Android/OEM control"
    return 0
fi

vb_devconfig app_hibernation app_hibernation_enabled true

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        vb_devconfig permissions auto_revoke_unused_apps_enabled true
        ;;
esac
vb_log "HIBER" "Hibernation enabled"
