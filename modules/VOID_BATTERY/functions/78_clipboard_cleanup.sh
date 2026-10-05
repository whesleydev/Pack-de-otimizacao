#!/system/bin/sh
# VOID BATTERY v9.1 — Clipboard Service Cleanup
# Prevents clipboard service from holding references and waking
# Zero impact — clipboard works normally when user copies

vb_log "CLIP" "Clipboard cleanup — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Clear clipboard to prevent background clipboard listeners from processing
        am broadcast -a clipboardClearPrimary 2>/dev/null
        # Restrict clipboard access for background apps (Android 12+)
        vb_devconfig clipboard_service max_classification_length 0
        vb_log "CLIP" "Clipboard cleaned, classification disabled"
        ;;
    ECO)
        vb_devconfig clipboard_service max_classification_length 0
        vb_log "CLIP" "Clipboard classification disabled"
        ;;
    *)
        # Don't touch
        ;;
esac
