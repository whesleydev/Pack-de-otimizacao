#!/system/bin/sh
# VOID BATTERY v9.1 — Backup Deferral
if [ "$VB_CHARGING" = "0" ]; then
    case "$VB_PROFILE" in
        CRITICAL|POWERSAVE|ECO)
            vb_settings secure backup_enabled 0
            vb_log "BACKUP" "Deferred (not charging)"
            ;;
    esac
else
    vb_settings secure backup_enabled 1
fi
