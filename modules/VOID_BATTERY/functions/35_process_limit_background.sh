#!/system/bin/sh
# VOID BATTERY v9.1 — Background Process Limiter
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

case "$VB_PROFILE" in
    CRITICAL)   _l=1 ;;
    POWERSAVE)  _l=2 ;;
    ECO)        _l=3 ;;
    IDLE)       _l=4 ;;
    BALANCED)   _l=-1 ;;
esac

vb_settings global background_process_limit "$_l"
vb_log "PROC" "BG limit=$_l"
