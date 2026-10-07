#!/system/bin/sh
# VOID BATTERY v9.1 — Debug Logging Reduction
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings global dropbox_max_files 50
        vb_settings global dropbox_age_seconds 86400
        vb_settings global dropbox_quota_kb 1024
        ;;
    ECO|IDLE)
        vb_settings global dropbox_max_files 100
        vb_settings global dropbox_age_seconds 172800
        ;;
esac
vb_settings global wifi_verbose_logging_enabled 0
vb_log "DEBUG" "Logging reduced"
