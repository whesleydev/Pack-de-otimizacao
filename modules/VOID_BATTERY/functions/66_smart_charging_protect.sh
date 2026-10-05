#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Smart Charging Protection
# Protects long-term battery health via Android settings

vb_settings global adaptive_charging_enabled 1
vb_devconfig battery_saver adaptive_charging_enabled true

# Enable battery health monitoring
vb_devconfig battery_saver smart_battery_enabled true
vb_settings global app_restriction_enabled true

vb_log "CHGPROT" "Charging protection active"
