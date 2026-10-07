#!/system/bin/sh
# VOID BATTERY v9.1 — FSTRIM (rate-limited)
vb_rate_ok "fstrim" 1800 || return 0
sm fstrim >/dev/null 2>&1 && vb_log "TRIM" "FSTRIM done" || vb_log "TRIM" "FSTRIM unavailable"
