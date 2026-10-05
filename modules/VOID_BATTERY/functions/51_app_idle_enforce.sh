#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] App Idle Enforcement
# Forces unused apps into idle state via am commands

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0
[ "$VB_PROFILE" = "BALANCED" ] && return 0

if [ "${VB_MANAGE_STANDBY:-false}" != "true" ]; then
    vb_log "AIDLE" "App idle left under Android/OEM control"
    return 0
fi

vb_log "AIDLE" "Enforcing app idle — $VB_PROFILE"

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
    vb_is_foreground "$_p" && continue
    am set-inactive "$_p" true >/dev/null 2>&1
    am make-uid-idle "$_p" >/dev/null 2>&1
done
vb_log "AIDLE" "App idle enforced"
