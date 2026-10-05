#!/system/bin/sh
# VOID BATTERY v9.1 — Unused App Auto-Hibernation
# Hibernates apps not used in 3+ days to prevent background drain
# Does NOT uninstall or break apps — they wake instantly on user tap

vb_rate_ok "unused_hibernate" 7200 || return 0

if [ "${VB_MANAGE_STANDBY:-false}" != "true" ]; then
    vb_log "HIBERNATE" "Unused-app hibernation left under Android/OEM control"
    return 0
fi

vb_log "HIBERNATE" "Scanning unused apps — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        _days=3 ;;
    IDLE)
        _days=5 ;;
    *)
        return 0 ;;
esac

_now=$(date +%s)
_threshold=$(( _days * 86400 ))
_count=0

for _pkg in $(pm list packages -3 2>/dev/null | sed 's/package://'); do
    vb_is_excluded "$_pkg" && continue
    vb_is_foreground "$_pkg" && continue

    # Check last used time via usage stats
    _usage=$(dumpsys usagestats 2>/dev/null | grep -A1 "$_pkg" | grep 'lastTimeUsed' | head -1 | sed 's/[^0-9]//g')
    [ -z "$_usage" ] && continue
    _usage_sec=$(( _usage / 1000 ))
    _diff=$(( _now - _usage_sec ))

    if [ "$_diff" -gt "$_threshold" ]; then
        am set-inactive "$_pkg" true 2>/dev/null
        _count=$(( _count + 1 ))
    fi
done

vb_log "HIBERNATE" "Hibernated $_count unused apps (>${_days}d inactive)"
