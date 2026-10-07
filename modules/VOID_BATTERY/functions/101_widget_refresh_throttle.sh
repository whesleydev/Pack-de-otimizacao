#!/system/bin/sh
# VOID BATTERY v9.1 — Widget Refresh Throttle
# Reduces frequency of home screen widget updates
# Widgets still update — just less frequently in low battery

vb_log "WIDGET" "Widget refresh throttle — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Increase minimum widget update interval
        vb_devconfig launcher widget_min_update_period 3600000
        vb_devconfig appwidget min_update_period 3600000
        vb_log "WIDGET" "Widget updates: every 1h minimum"
        ;;
    ECO)
        vb_devconfig launcher widget_min_update_period 1800000
        vb_devconfig appwidget min_update_period 1800000
        vb_log "WIDGET" "Widget updates: every 30m minimum"
        ;;
    IDLE)
        vb_devconfig launcher widget_min_update_period 1800000
        vb_log "WIDGET" "Widget updates: every 30m (idle)"
        ;;
    *)
        # BALANCED+: default widget refresh
        ;;
esac
