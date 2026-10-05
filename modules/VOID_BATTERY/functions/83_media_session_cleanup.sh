#!/system/bin/sh
# VOID BATTERY v9.1 — Media Session Cleanup
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

dumpsys media_session 2>/dev/null | grep 'package=' | \
    sed 's/.*package=//;s/[, ].*//' | sort -u | while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    vb_is_excluded "$_p" && continue
    _play=$(dumpsys media_session 2>/dev/null | grep -A5 "$_p" | grep -c 'state=playing')
    if [ "$_play" -eq 0 ]; then
        case "$VB_PROFILE" in
            CRITICAL|POWERSAVE)
                am force-stop "$_p" >/dev/null 2>&1
                vb_log "MEDIA" "Stopped idle: $_p"
                ;;
        esac
    fi
done
