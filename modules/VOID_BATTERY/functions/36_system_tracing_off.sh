#!/system/bin/sh
# VOID BATTERY v9.1 — System Tracing Off
vb_settings global debug_app ""
vb_settings global wait_for_debugger 0
vb_devconfig statsd perfetto_bg_tracing_enabled false
vb_devconfig statsd enable_restricted_metric false
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings global adb_wifi_enabled 0
        ;;
esac
vb_log "TRACE" "Tracing disabled"
