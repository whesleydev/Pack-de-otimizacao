#!/system/bin/sh
# VOID BATTERY v9.1 — Samsung Optimizer
_br=$(getprop ro.product.brand 2>/dev/null | tr 'A-Z' 'a-z')
[ "$_br" != "samsung" ] && return 0

vb_devconfig game_overlay game_optimization_service false
vb_settings global sem_enhanced_cpu_responsiveness 0
vb_settings global enhanced_processing 0
vb_settings system master_motion 0
vb_settings system motion_engine 0
vb_settings system air_motion_engine 0
vb_settings system air_motion_wake_up 0
vb_settings system intelligent_sleep_mode 1
vb_settings secure adaptive_sleep 1

# Samsung Game Home
vb_settings secure game_home_enable 0
vb_settings secure game_auto_temperature_control 0

vb_log "SAMSUNG" "Samsung optimized"
