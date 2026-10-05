#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Network Policy Optimizer
# Configure network policy controller for battery savings

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

if [ "${VB_MANAGE_BACKGROUND_DATA:-false}" != "true" ]; then
    vb_log "NETPOL" "Network policy left under Android/OEM control"
    return 0
fi

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig netpolicy network_switch_notification_daily_limit 0
        vb_devconfig netpolicy network_switch_notification_rate_limit_millis 86400000
        ;;
esac

# Restrict metered network access for non-essential apps
if [ "$VB_PROFILE" = "CRITICAL" ]; then
    echo "$VB_EXTREME" | while IFS= read -r _p; do
        [ -z "$_p" ] && continue
        vb_is_excluded "$_p" && continue
        vb_is_installed "$_p" || continue
        _uid=$(vb_get_uid "$_p")
        [ -n "$_uid" ] && cmd netpolicy set metered-network-blacklist "$_uid" true >/dev/null 2>&1
    done
fi
vb_log "NETPOL" "Network policy optimized"
