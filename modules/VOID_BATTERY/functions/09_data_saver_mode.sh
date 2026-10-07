#!/system/bin/sh
# VOID BATTERY v9.1 — Smart Data Saver

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

# Data Saver is a user-controlled global policy. Never rewrite it from the
# periodic daemon unless the user explicitly opts in.
if [ "${VB_MANAGE_DATA_SAVER:-false}" != "true" ] || [ "${VB_DATA_SAVER:-manual}" = "manual" ]; then
    vb_log "DATA" "Data Saver left unchanged (manual/user-controlled)"
    return 0
fi

vb_log "DATA" "Data saver — mode:$VB_DATA_SAVER"

if [ "$VB_DATA_SAVER" = "smart" ]; then
    _wifi=$(dumpsys connectivity 2>/dev/null | grep -c 'type: WIFI.*CONNECTED')
    if [ "$_wifi" -gt 0 ]; then
        cmd netpolicy set restrict-background false >/dev/null 2>&1
    else
        case "$VB_PROFILE" in
            CRITICAL|POWERSAVE|ECO)
                cmd netpolicy set restrict-background true >/dev/null 2>&1
                ;;
            *)
                cmd netpolicy set restrict-background false >/dev/null 2>&1
                ;;
        esac
    fi
elif [ "$VB_DATA_SAVER" = "always" ]; then
    cmd netpolicy set restrict-background true >/dev/null 2>&1
else
    cmd netpolicy set restrict-background false >/dev/null 2>&1
fi

# Whitelist push-critical
if [ "$VB_PUSH_PROTECT" = "true" ]; then
    echo "$VB_PUSH_APPS" | while IFS= read -r _p; do
        [ -z "$_p" ] && continue
        _uid=$(vb_get_uid "$_p")
        [ -n "$_uid" ] && cmd netpolicy add restrict-background-whitelist "$_uid" >/dev/null 2>&1
    done
fi
