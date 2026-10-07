#!/system/bin/sh
# VOID BATTERY v9.1 — GMS Optimizer
# IMPROVED: More comprehensive GMS restriction, heartbeat management

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

if [ "${VB_MANAGE_GMS:-false}" != "true" ]; then
    vb_log "GMS" "GMS/GSF left under Android/OEM control"
    return 0
fi

vb_log "GMS" "Optimizing GMS — $VB_PROFILE"

_g="com.google.android.gms"
_gsf="com.google.android.gsf"

# Remove from Doze whitelist (all non-PERFORMANCE profiles)
dumpsys deviceidle whitelist -"$_g" >/dev/null 2>&1
dumpsys deviceidle whitelist -"$_gsf" >/dev/null 2>&1

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        cmd appops set "$_g" RUN_IN_BACKGROUND ignore >/dev/null 2>&1
        cmd appops set "$_g" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
        cmd appops set "$_g" WAKE_LOCK ignore >/dev/null 2>&1
        # IMPROVED: Also restrict GMS location scanning
        cmd appops set "$_g" MONITOR_LOCATION ignore >/dev/null 2>&1
        cmd appops set "$_g" MONITOR_HIGH_POWER_LOCATION ignore >/dev/null 2>&1
        ;;
    ECO|IDLE)
        cmd appops set "$_g" RUN_IN_BACKGROUND ignore >/dev/null 2>&1
        cmd appops set "$_g" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
        # IMPROVED: Restrict location in background for ECO/IDLE
        cmd appops set "$_g" MONITOR_HIGH_POWER_LOCATION ignore >/dev/null 2>&1
        ;;
    BALANCED)
        cmd appops set "$_g" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
        ;;
esac

# IMPROVED: GMS heartbeat/checkin interval management
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig gms gms_heartbeat_interval_ms 1800000
        vb_devconfig gms gcm_heartbeat_interval_ms 1800000
        ;;
    ECO|IDLE|BALANCED)
        vb_devconfig gms gms_heartbeat_interval_ms 900000
        vb_devconfig gms gcm_heartbeat_interval_ms 900000
        ;;
esac

vb_devconfig gms device_doze true

vb_log "GMS" "GMS optimized"
