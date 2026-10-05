#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Fixed Performance Mode Off
# Disables forced high-performance CPU mode

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

cmd power set-fixed-performance-mode-enabled false >/dev/null 2>&1
vb_log "PERF" "Fixed performance mode disabled"
