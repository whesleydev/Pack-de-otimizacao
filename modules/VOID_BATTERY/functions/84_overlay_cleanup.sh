#!/system/bin/sh
# VOID BATTERY v9.1 — Overlay Cleanup
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0
[ "$VB_PROFILE" = "BALANCED" ] && return 0

vb_log "OVERLAY" "Auditing overlays"
dumpsys package 2>/dev/null | grep -B1 'SYSTEM_ALERT_WINDOW' | \
    grep 'Package \[' | sed 's/.*\[//;s/\].*//' | while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    vb_is_excluded "$_p" && continue
    echo "$VB_SOCIAL" | grep -qxF "$_p" || continue
    cmd appops set "$_p" SYSTEM_ALERT_WINDOW ignore >/dev/null 2>&1
done
