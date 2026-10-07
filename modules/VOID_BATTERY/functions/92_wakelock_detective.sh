#!/system/bin/sh
# VOID BATTERY v9.1 — Wakelock Report
_rpt="$VB_REPORT_DIR/wakelock_report.txt"
{
    echo "VOID BATTERY v9.1 — Wakelock Report"
    echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "---"
    echo "Top Partial Wakelocks:"
    dumpsys batterystats 2>/dev/null | grep -A2 'Partial wake' | head -30
    echo ""
    echo "Wake Reasons:"
    dumpsys batterystats 2>/dev/null | grep 'Wake reason' | head -20
} > "$_rpt" >/dev/null 2>&1
vb_log "WKDET" "Wakelock report saved"
