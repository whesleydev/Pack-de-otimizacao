#!/system/bin/sh
# VOID BATTERY v9.1 — Network Traffic Throttle
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0
[ "$VB_PROFILE" = "BALANCED" ] && return 0

_w=$(dumpsys connectivity 2>/dev/null | grep -c 'type: WIFI.*CONNECTED')
[ "$_w" -gt 0 ] && return 0

_target=""
case "$VB_PROFILE" in
    CRITICAL)   _target="$VB_EXTREME" ;;
    POWERSAVE)  _target="$VB_MODERATE" ;;
    ECO|IDLE)   _target="$VB_SOCIAL" ;;
esac

echo "$_target" | while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    vb_is_excluded "$_p" && continue
    vb_is_installed "$_p" || continue
    _uid=$(vb_get_uid "$_p")
    [ -n "$_uid" ] && cmd netpolicy add restrict-background-blacklist "$_uid" >/dev/null 2>&1
done
vb_log "TRAFFIC" "Traffic throttled on mobile"
