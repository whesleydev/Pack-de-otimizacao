#!/system/bin/sh
# VOID BATTERY v9.1 — Text Classifier & Smart Services Off
# Disables background ML text classification that burns CPU silently
# User won't notice — smart text selection still works from OS cache

vb_log "TEXTCLS" "Text classifier control — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig textclassifier textclassifier_enabled false
        vb_devconfig content_capture content_capture_enabled false
        vb_devconfig smart_actions smart_actions false
        vb_devconfig intelligence_aiai iorap_ml false
        vb_devconfig attention_manager keep_screen_on_enabled false
        vb_log "TEXTCLS" "All ML services disabled"
        ;;
    ECO)
        vb_devconfig textclassifier textclassifier_enabled false
        vb_devconfig content_capture content_capture_enabled false
        vb_log "TEXTCLS" "Text classifier + content capture off"
        ;;
    *)
        # BALANCED+: leave enabled
        ;;
esac
