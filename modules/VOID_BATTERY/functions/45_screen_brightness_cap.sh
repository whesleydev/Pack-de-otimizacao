#!/system/bin/sh
# VOID BATTERY v9.1 — Brightness Cap
# FIX: Removed brightness capping — was causing brightness to fluctuate
# The module should NEVER override user's brightness level
vb_log "BRI" "Brightness cap: disabled (user control preserved)"
return 0
