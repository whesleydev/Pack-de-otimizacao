#!/system/bin/sh
# VOID BATTERY v9.1 — App Prediction & Suggestion Service Off
# Disables ML-based app prediction that runs continuously in background
# App drawer still works fine — just without AI-sorted suggestions

vb_log "PREDICT" "App prediction control — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        # Disable app prediction service
        vb_devconfig launcher enable_people_tile_prediction false
        vb_devconfig launcher enable_app_prediction false
        vb_devconfig launcher enable_widget_prediction false
        vb_devconfig launcher enable_overview_actions false
        # Disable usage-based learning
        vb_devconfig app_prediction enable false
        vb_log "PREDICT" "All prediction services disabled"
        ;;
    *)
        # BALANCED+: leave enabled
        ;;
esac
