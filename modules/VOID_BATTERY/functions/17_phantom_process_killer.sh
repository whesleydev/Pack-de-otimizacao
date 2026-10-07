#!/system/bin/sh
# VOID BATTERY v9.1 — Phantom Process Limiter

case "$VB_PROFILE" in
    CRITICAL)    _m=4 ;;
    POWERSAVE)   _m=6 ;;
    ECO)         _m=8 ;;
    IDLE)        _m=12 ;;
    BALANCED)    _m=16 ;;
    PERFORMANCE) _m=32 ;;
esac

vb_devconfig activity_manager max_phantom_processes "$_m"
vb_log "PHANTOM" "Limit=$_m"
