#!/system/bin/sh
# VOID BATTERY v9.1 — Multicast Lock Check
_locks=$(dumpsys wifi 2>/dev/null | grep -c 'MulticastLock')
[ "$_locks" -gt 0 ] && vb_log "MCAST" "$_locks multicast locks active"
