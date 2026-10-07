#!/system/bin/sh
# VOID BATTERY v9.1 — Background Data Restrict per App
# IMPROVED: Added IDLE profile restriction for background data

vb_rate_ok "bgdata" 1800 || return 0

if [ "${VB_MANAGE_BACKGROUND_DATA:-false}" != "true" ]; then
    vb_log "BGDATA" "Per-app background data policies left unchanged"
    return 0
fi

vb_log "BGDATA" "Background data restriction — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        _count=0
        for _pkg in $(pm list packages -3 2>/dev/null | sed 's/package://'); do
            vb_is_excluded "$_pkg" && continue
            vb_is_push_critical "$_pkg" && continue
            vb_is_foreground "$_pkg" && continue

            _uid=$(vb_get_uid "$_pkg")
            [ -z "$_uid" ] && continue

            cmd netpolicy set-uid-policy "$_uid" 1 2>/dev/null
            _count=$(( _count + 1 ))

            # Limit to 30 apps per cycle to avoid slowdown
            [ "$_count" -ge 30 ] && break
        done
        vb_log "BGDATA" "Restricted $_count apps from background data"
        ;;
    ECO|IDLE)
        # IMPROVED: Restrict extreme AND moderate lists in ECO/IDLE
        _count=0
        echo "$VB_EXTREME" | while IFS= read -r _pkg; do
            [ -z "$_pkg" ] && continue
            vb_is_foreground "$_pkg" && continue
            _uid=$(vb_get_uid "$_pkg")
            [ -z "$_uid" ] && continue
            cmd netpolicy set-uid-policy "$_uid" 1 2>/dev/null
            _count=$(( _count + 1 ))
        done
        echo "$VB_MODERATE" | while IFS= read -r _pkg; do
            [ -z "$_pkg" ] && continue
            vb_is_excluded "$_pkg" && continue
            vb_is_push_critical "$_pkg" && continue
            vb_is_foreground "$_pkg" && continue
            _uid=$(vb_get_uid "$_pkg")
            [ -z "$_uid" ] && continue
            cmd netpolicy set-uid-policy "$_uid" 1 2>/dev/null
        done
        vb_log "BGDATA" "Restricted extreme+moderate apps from background data"
        ;;
    *)
        # BALANCED+: clear restrictions
        ;;
esac
