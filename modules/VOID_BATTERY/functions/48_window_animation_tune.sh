#!/system/bin/sh
# VOID BATTERY v9.1 — Window Animation Tune
case "$VB_PROFILE" in
    CRITICAL)
        vb_devconfig window_manager predictive_back_anim false
        vb_devconfig window_manager freeform_window_management false
        ;;
    POWERSAVE|ECO)
        vb_devconfig window_manager predictive_back_anim false
        ;;
esac
