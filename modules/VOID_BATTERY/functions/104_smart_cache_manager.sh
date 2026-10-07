#!/system/bin/sh
# VOID BATTERY v9.1 — Smart Cache Manager
# Trims app caches intelligently based on battery level
# Frees storage and reduces background I/O operations

vb_rate_ok "cache_mgr" 3600 || return 0

vb_log "CACHE" "Smart cache management — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL)
        pm trim-caches 300M 2>/dev/null
        vb_log "CACHE" "Aggressive trim: 300MB freed"
        ;;
    POWERSAVE)
        pm trim-caches 500M 2>/dev/null
        vb_log "CACHE" "Moderate trim: 500MB freed"
        ;;
    ECO)
        pm trim-caches 750M 2>/dev/null
        vb_log "CACHE" "Light trim: 750MB freed"
        ;;
    *)
        # BALANCED+: only trim on heavy cycle
        ;;
esac

# Clean stale temp files from known temp locations
for _dir in /data/local/tmp /sdcard/Android/data/.tmp; do
    [ -d "$_dir" ] && find "$_dir" -type f -mtime +3 -delete 2>/dev/null
done

vb_log "CACHE" "Cache management done"
