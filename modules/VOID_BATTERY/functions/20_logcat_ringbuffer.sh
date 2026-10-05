#!/system/bin/sh
# VOID BATTERY v9.1 — Logcat Buffer

# Do not alter or maintain logcat buffers in no-log mode.
command -v void_logs_disabled >/dev/null 2>&1 && void_logs_disabled && exit 0

case "$VB_PROFILE" in
    CRITICAL)    _s="64K" ;;
    POWERSAVE)   _s="128K" ;;
    ECO|IDLE)    _s="256K" ;;
    BALANCED)    _s="512K" ;;
    PERFORMANCE) _s="1M" ;;
esac

logcat -G "$_s" >/dev/null 2>&1
vb_log "LOG" "Buffer=$_s"
