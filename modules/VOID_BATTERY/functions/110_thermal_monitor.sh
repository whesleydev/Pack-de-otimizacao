#!/system/bin/sh
# VOID BATTERY v9.1 — Thermal Monitor & Auto-Cool
# Monitors device temperature and takes protective action
# Prevents thermal throttling damage without user disruption

vb_log "THERM" "Thermal monitor — ${VB_TEMP}C | $VB_PROFILE"

# Temperature-based actions (independent of profile)
if [ "${VB_TEMP:-30}" -ge 42 ]; then
    # HOT: force-stop heavy background apps
    vb_log "THERM" "CRITICAL HEAT: ${VB_TEMP}C — emergency cooling"
    for _pkg in $(dumpsys cpuinfo 2>/dev/null | grep -E '^\s*[5-9][0-9]%|^\s*100%' | sed 's/.*: //;s/:.*//' | head -5); do
        vb_is_excluded "$_pkg" && continue
        vb_is_foreground "$_pkg" && continue
        am force-stop "$_pkg" 2>/dev/null
        vb_log "THERM" "Force-stopped hot app: $_pkg"
    done
    # FIX: Removed brightness reduction — module should never change brightness
    # Only reduce refresh rate to lower heat
    vb_settings system peak_refresh_rate 60.0

elif [ "${VB_TEMP:-30}" -ge 38 ]; then
    # WARM: throttle background processing
    vb_log "THERM" "WARM: ${VB_TEMP}C — reducing load"
    vb_devconfig activity_manager max_cached_processes 16
    vb_settings system peak_refresh_rate 90.0

elif [ "${VB_TEMP:-30}" -le 25 ]; then
    # COOL: device is running cool, can relax
    vb_log "THERM" "COOL: ${VB_TEMP}C — normal operation"
fi
