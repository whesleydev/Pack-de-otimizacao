#!/system/bin/sh
# VOID BATTERY v9.1 — Connectivity Power
# IMPROVED: More aggressive netstats threshold for all profiles

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig connectivity connectivity_thermal_power_manager true
        vb_devconfig netstats persist_bytes_threshold 524288
        vb_devconfig netstats global_alert_bytes 2097152
        ;;
    ECO|IDLE)
        vb_devconfig connectivity connectivity_thermal_power_manager true
        vb_devconfig netstats persist_bytes_threshold 524288
        ;;
    BALANCED)
        # IMPROVED: Enable thermal power management for BALANCED
        vb_devconfig connectivity connectivity_thermal_power_manager true
        vb_devconfig netstats persist_bytes_threshold 1048576
        ;;
    PERFORMANCE)
        vb_devconfig connectivity connectivity_thermal_power_manager false
        ;;
esac
vb_log "CONN" "Connectivity power configured"
