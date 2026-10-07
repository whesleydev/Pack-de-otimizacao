#!/system/bin/sh
# VOID BATTERY v9.1 — Session Report
_rpt="$VB_REPORT_DIR/session_$(date +%Y%m%d).md"
{
    echo "# VOID BATTERY v9.1 — Session Report"
    echo "**Date:** $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo "## Status"
    echo "- Battery: ${VB_LEVEL}%"
    echo "- Temperature: ${VB_TEMP}C"
    echo "- Profile: $VB_PROFILE"
    echo "- Charging: $([ "$VB_CHARGING" = "1" ] && echo Yes || echo No)"
    echo ""
    echo "## Device"
    echo "- Model: $(getprop ro.product.model 2>/dev/null)"
    echo "- Android: $(getprop ro.build.version.release 2>/dev/null)"
    echo ""
    _fc=0
    for _f in "$MODPATH"/functions/*.sh; do [ -f "$_f" ] && _fc=$((_fc+1)); done
    echo "## Functions: $_fc active"
} > "$_rpt" >/dev/null 2>&1
vb_log "RPT" "Session report saved"
