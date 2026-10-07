#!/system/bin/sh
# VOID BATTERY v9.1 — Smart Network Switch
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings global mobile_data_always_on 0
        vb_settings global wifi_watchdog_poor_network_test_enabled 0
        ;;
    ECO|IDLE)
        vb_settings global mobile_data_always_on 0
        ;;
    *)
        vb_settings global mobile_data_always_on 1
        ;;
esac
