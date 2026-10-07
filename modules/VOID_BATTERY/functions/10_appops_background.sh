#!/system/bin/sh
# VOID BATTERY v9.1 — AppOps Background Restriction

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0
[ "$VB_PROFILE" = "BALANCED" ] && return 0

if [ "${VB_MANAGE_BACKGROUND_DATA:-false}" != "true" ]; then
    vb_log "APPOPS" "Background AppOps left under Android/OEM control"
    return 0
fi

vb_log "APPOPS" "Background restriction — $VB_PROFILE"

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
    cmd appops set "$_p" RUN_IN_BACKGROUND ignore >/dev/null 2>&1
    cmd appops set "$_p" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
done
