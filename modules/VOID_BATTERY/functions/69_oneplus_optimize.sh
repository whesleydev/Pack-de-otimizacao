#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] OnePlus Optimizer
_br=$(getprop ro.product.brand 2>/dev/null | tr 'A-Z' 'a-z')
[ "$_br" != "oneplus" ] && return 0

vb_log "OP" "OnePlus optimization"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        vb_settings global op_voice_recording_supported_by_mcs 0
        vb_settings system oem_acc_sensor_position_algo_dir 0
        ;;
esac

vb_log "OP" "OnePlus optimized"
