#!/system/bin/sh
# VOID BATTERY v9.1 — Battery Anomaly Detector
vb_devconfig battery_saver anomaly_detection_enabled true
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig battery_saver anomaly_wakelock_threshold_ms 1800000
        ;;
    ECO|IDLE)
        vb_devconfig battery_saver anomaly_wakelock_threshold_ms 3600000
        ;;
esac
