#!/system/bin/sh
# VOID BATTERY v9.1 — GPS Background Limiter
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

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
    cmd appops set "$_p" android:fine_location ignore >/dev/null 2>&1
    cmd appops set "$_p" android:monitor_high_power_location ignore >/dev/null 2>&1
done
vb_log "GPS" "Background GPS restricted"
