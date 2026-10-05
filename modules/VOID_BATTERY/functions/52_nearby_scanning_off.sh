#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Nearby Scanning Off
# Disabling nearby scanning can nearly double battery life (Android Police research)

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

vb_settings system nearby_scanning_enabled 0
vb_settings system nearby_scanning_permission_allowed 0

vb_log "NEARBY" "Nearby scanning disabled"
