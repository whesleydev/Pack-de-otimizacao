#!/system/bin/sh
# VOID BATTERY v9.1 — Doze Master (Research-Based)
# Uses dual approach: legacy constants string + device_config
# IMPROVED: Better doze entry for BALANCED/ECO when screen off

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

if [ "${VB_MANAGE_DOZE:-false}" != "true" ]; then
    vb_log "DOZE" "Doze left under Android/OEM control"
    return 0
fi

vb_log "DOZE" "Configuring Doze — $VB_PROFILE"

# Dual approach: legacy string (most compatible) + device_config (modern)
case "$VB_PROFILE" in
    CRITICAL)
        # Ultra-aggressive: near-instant doze entry
        _cs="inactive_to=30000,sensing_to=0,locating_to=0,motion_inactive_to=30000,idle_after_inactive_to=0,idle_pending_to=10000,max_idle_pending_to=20000,idle_pending_factor=1.0,idle_to=60000,max_idle_to=3600000,idle_factor=1.5,min_time_to_alarm=30000,light_after_inactive_to=10000,light_pre_idle_to=10000,light_idle_to=300000,light_idle_factor=1.5,light_max_idle_to=900000,light_idle_maintenance_min_budget=10000,light_idle_maintenance_max_budget=20000,min_light_maintenance_time=3000,min_deep_maintenance_time=10000"
        ;;
    POWERSAVE)
        _cs="inactive_to=60000,sensing_to=30000,locating_to=15000,motion_inactive_to=60000,idle_after_inactive_to=30000,idle_pending_to=30000,max_idle_pending_to=60000,idle_pending_factor=1.5,idle_to=300000,max_idle_to=7200000,idle_factor=2.0,min_time_to_alarm=60000,light_after_inactive_to=30000,light_pre_idle_to=30000,light_idle_to=600000,light_idle_factor=1.5,light_max_idle_to=1800000,light_idle_maintenance_min_budget=15000,light_idle_maintenance_max_budget=30000"
        ;;
    ECO)
        _cs="inactive_to=120000,sensing_to=60000,locating_to=30000,motion_inactive_to=120000,idle_after_inactive_to=60000,idle_to=600000,max_idle_to=14400000,idle_factor=2.0,light_after_inactive_to=60000,light_idle_to=900000,light_max_idle_to=3600000"
        ;;
    IDLE)
        _cs="inactive_to=60000,sensing_to=30000,locating_to=15000,motion_inactive_to=60000,idle_after_inactive_to=30000,idle_to=300000,max_idle_to=10800000,idle_factor=2.0,light_after_inactive_to=30000,light_idle_to=600000,light_max_idle_to=1800000"
        ;;
    BALANCED)
        # IMPROVED: Faster doze entry without affecting active use
        _cs="inactive_to=120000,sensing_to=60000,locating_to=30000,motion_inactive_to=120000,idle_after_inactive_to=60000,idle_to=900000,max_idle_to=14400000,idle_factor=2.0,light_after_inactive_to=60000,light_pre_idle_to=120000,light_idle_to=900000,light_idle_factor=2.0,light_max_idle_to=3600000"
        ;;
esac

# Apply legacy string (works on ALL Android versions)
vb_settings global device_idle_constants "$_cs"

# Also try device_config (more granular, Android 9+)
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig deviceidle wait_for_unlock true
        vb_devconfig deviceidle max_temp_app_allowlist_duration_ms 30000
        ;;
    ECO|IDLE|BALANCED)
        # IMPROVED: Also set temp allowlist limit for all profiles
        vb_devconfig deviceidle max_temp_app_allowlist_duration_ms 60000
        ;;
esac

# Enable GMS deep doze
vb_devconfig gms device_doze true

# Force idle when screen off — IMPROVED: also for ECO and BALANCED
if [ "$VB_SCREEN" = "0" ] && [ "$VB_CHARGING" = "0" ]; then
    case "$VB_PROFILE" in
        CRITICAL|POWERSAVE)
            dumpsys deviceidle force-idle >/dev/null 2>&1
            vb_log "DOZE" "Forced into idle"
            ;;
        ECO|IDLE)
            dumpsys deviceidle step deep >/dev/null 2>&1
            vb_log "DOZE" "Stepped into deep idle"
            ;;
        BALANCED)
            # Safe: only step into light doze when screen off
            dumpsys deviceidle step light >/dev/null 2>&1
            vb_log "DOZE" "Stepped into light idle"
            ;;
    esac
fi

vb_log "DOZE" "Doze configured"
