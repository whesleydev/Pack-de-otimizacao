#!/system/bin/sh
# VOID BATTERY v9.1 — Print Spooler & NFC Optimize
# Disables print spooler service running in background
# Also optimizes NFC when not actively used

vb_log "PRINT" "Print/NFC control — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        # Disable print spooler (wastes RAM and wakes)
        vb_is_installed "com.android.printspooler" && {
            am force-stop com.android.printspooler 2>/dev/null
            pm disable-user --user 0 com.android.printspooler 2>/dev/null
        }
        # Disable NFC background polling
        vb_settings global nfc_payment_foreground 1
        vb_log "PRINT" "Print spooler stopped, NFC optimized"
        ;;
    ECO)
        vb_settings global nfc_payment_foreground 1
        vb_log "PRINT" "NFC foreground-only"
        ;;
    *)
        # Re-enable print spooler if it was disabled
        pm enable com.android.printspooler 2>/dev/null
        ;;
esac
