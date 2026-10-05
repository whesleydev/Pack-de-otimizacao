#!/system/bin/sh
# VOID BATTERY v9.1 — Notification Listener Audit
_cnt=$(dumpsys notification 2>/dev/null | grep -c 'NotificationListenerService')
vb_log "NLIST" "Active listeners: $_cnt"
[ "$_cnt" -gt 5 ] && vb_log "NLIST" "WARNING: $_cnt listeners (high drain)"
