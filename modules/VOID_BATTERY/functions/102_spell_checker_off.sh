#!/system/bin/sh
# VOID BATTERY v9.1 — Spell Checker Background Off
# Disables background spell-check processing to save CPU
# Spell check still works inline when typing — only background analysis stops

vb_log "SPELL" "Spell checker control — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings secure spell_checker_enabled 0
        vb_log "SPELL" "Spell checker disabled (battery critical)"
        ;;
    ECO)
        # Leave enabled but stop background service
        vb_devconfig textclassifier spell_check_in_background false
        vb_log "SPELL" "Background spell check off"
        ;;
    *)
        # Don't touch — user typing experience preserved
        ;;
esac
