#!/system/bin/sh
# VOID BATTERY v9.1 — Adaptive Screen Timeout
# Adjusts screen timeout based on battery profile
# Uses reasonable values — never disrupts active use

vb_log "TIMEOUT" "Screen timeout — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL)
        # 15 seconds — minimal drain
        vb_settings system screen_off_timeout 15000
        vb_log "TIMEOUT" "Set to 15s (critical)"
        ;;
    POWERSAVE)
        # 30 seconds
        vb_settings system screen_off_timeout 30000
        vb_log "TIMEOUT" "Set to 30s (powersave)"
        ;;
    ECO)
        # 1 minute
        vb_settings system screen_off_timeout 60000
        vb_log "TIMEOUT" "Set to 60s (eco)"
        ;;
    IDLE)
        # 30 seconds — screen is off anyway
        vb_settings system screen_off_timeout 30000
        vb_log "TIMEOUT" "Set to 30s (idle)"
        ;;
    *)
        # BALANCED/PERFORMANCE: don't change user preference
        ;;
esac
