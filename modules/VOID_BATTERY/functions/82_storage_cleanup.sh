#!/system/bin/sh
# VOID BATTERY v9.1 — Storage Cleanup
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        pm trim-caches 1G >/dev/null 2>&1
        vb_log "STORE" "Cache trimmed (1GB)"
        ;;
    *)
        pm trim-caches 500M >/dev/null 2>&1
        vb_log "STORE" "Cache trimmed (500MB)"
        ;;
esac
