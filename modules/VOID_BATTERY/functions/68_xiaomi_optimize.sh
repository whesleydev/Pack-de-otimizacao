#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Xiaomi/MIUI Optimizer
# NOTE: Does NOT change navigation mode — respects user preference
_br=$(getprop ro.product.brand 2>/dev/null | tr 'A-Z' 'a-z')
case "$_br" in
    xiaomi|redmi|poco) ;;
    *) return 0 ;;
esac

vb_log "XIAOMI" "MIUI optimization"

# MIUI-specific battery settings (navigation mode NOT touched)
vb_settings system miui_optimization true

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings global miui_app_launch_boost 0
        vb_settings global miui_idle_bg_optimization 1
        ;;
    ECO)
        vb_settings global miui_app_launch_boost 0
        ;;
esac

vb_log "XIAOMI" "MIUI optimized"
