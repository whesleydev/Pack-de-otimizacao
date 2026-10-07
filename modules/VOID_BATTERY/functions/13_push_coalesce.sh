#!/system/bin/sh
# VOID BATTERY v9.1 — Push Heartbeat Coalesce

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL)   _w=900000; _m=900000 ;;
    POWERSAVE)  _w=600000; _m=600000 ;;
    ECO)        _w=420000; _m=480000 ;;
    *)          _w=300000; _m=360000 ;;
esac

vb_settings global gcm_wifi_heartbeat_interval_ms "$_w"
vb_settings global gcm_mobile_heartbeat_interval_ms "$_m"
vb_log "PUSH" "Heartbeat wifi=${_w} mobile=${_m}"
