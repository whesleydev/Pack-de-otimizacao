#!/system/bin/sh
# VOID BATTERY v9.1 — USB Power Delivery Optimization
# Optimizes USB behavior to reduce power drain from data transfers
# Only affects background USB — active file transfers work normally

vb_log "USB" "USB power optimization — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Disable USB debugging if not actively used (saves power)
        vb_settings global adb_wifi_enabled 0
        # Disable USB audio routing to save power
        vb_settings global usb_audio_automatic_routing_disabled 1
        vb_log "USB" "USB optimized: WiFi ADB off, audio routing off"
        ;;
    ECO)
        vb_settings global adb_wifi_enabled 0
        vb_log "USB" "WiFi ADB disabled"
        ;;
    *)
        # BALANCED+: don't touch USB
        ;;
esac
