#!/system/bin/sh
# VOID BATTERY v9.1 — Cellular Standby
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        _w=$(dumpsys connectivity 2>/dev/null | grep -c 'type: WIFI.*CONNECTED')
        [ "$_w" -gt 0 ] && vb_settings global mobile_data_always_on 0
        ;;
    ECO|IDLE)
        vb_settings global mobile_data_always_on 0
        ;;
esac
