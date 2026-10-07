#!/system/bin/sh
# VOID BATTERY v9.1 — Smart Freezer

vb_log "FREEZE" "Configuring freezer — $VB_PROFILE"

vb_devconfig activity_manager use_compaction true
vb_devconfig activity_manager use_freezer true
vb_devconfig activity_manager_native_boot use_freezer true

case "$VB_PROFILE" in
    CRITICAL)   _db=5000 ;;
    POWERSAVE)  _db=10000 ;;
    ECO)        _db=30000 ;;
    IDLE)       _db=15000 ;;
    BALANCED)   _db=60000 ;;
    PERFORMANCE) _db=120000 ;;
esac

vb_devconfig activity_manager freeze_debounce_timeout "$_db"
vb_settings global adaptive_battery_management_enabled 1

vb_log "FREEZE" "Freezer debounce=${_db}ms"
