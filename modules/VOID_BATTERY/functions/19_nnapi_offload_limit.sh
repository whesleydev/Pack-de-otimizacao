#!/system/bin/sh
# VOID BATTERY v9.1 — Background ML Limiter

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

vb_devconfig intelligence_aiai iorap_ml false
vb_devconfig smart_actions smart_actions false

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig activity_manager background_ml_disabled true
        vb_devconfig on_device_intelligence enable false
        ;;
    ECO|IDLE)
        vb_devconfig activity_manager background_ml_disabled true
        ;;
esac
vb_log "ML" "Background ML limited"
