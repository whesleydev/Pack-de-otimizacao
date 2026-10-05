#!/system/bin/sh
# VOID BATTERY v9.1 — App Standby Enforcer

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

if [ "${VB_MANAGE_STANDBY:-false}" != "true" ]; then
    vb_log "STANDBY" "App Standby left under Android/OEM control"
    return 0
fi

vb_log "STANDBY" "Enforcing standby — $VB_PROFILE"

vb_settings global app_standby_enabled 1

# Select target apps by profile
_target=""
case "$VB_PROFILE" in
    CRITICAL)   _target="$VB_EXTREME" ;;
    POWERSAVE)  _target="$VB_MODERATE" ;;
    ECO)        _target="$VB_MODERATE" ;;
    IDLE)       _target="$VB_SOCIAL" ;;
    BALANCED)   _target="$VB_SOCIAL" ;;
esac

# Use 'restricted' bucket for CRITICAL (most aggressive: 1 job/day)
# Use 'rare' for others
_bucket="rare"
[ "$VB_PROFILE" = "CRITICAL" ] && _bucket="restricted"

echo "$_target" | while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    vb_is_excluded "$_p" && continue
    vb_is_installed "$_p" || continue
    am set-standby-bucket "$_p" "$_bucket" >/dev/null 2>&1
done

vb_log "STANDBY" "Buckets enforced ($_bucket)"
