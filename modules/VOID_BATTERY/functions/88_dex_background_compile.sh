#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] DEX Background Compile
# Triggers bg-dexopt to reduce JIT overhead (huge battery impact)
# Only run when charging to avoid drain

[ "$VB_CHARGING" != "1" ] && return 0

vb_rate_ok "dexopt" 86400 || return 0

vb_log "DEX" "Triggering background DEX optimization (charging)"
cmd package bg-dexopt-job >/dev/null 2>&1 &
vb_log "DEX" "bg-dexopt-job triggered"
