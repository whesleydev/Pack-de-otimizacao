#!/system/bin/sh
# VOID BATTERY v9.1 — Accessibility Service Audit
# Logs active accessibility services that drain battery
# Does NOT disable them — only reports for user awareness

vb_rate_ok "access_audit" 3600 || return 0

vb_log "A11Y" "Accessibility service audit"

_report="$VB_REPORT_DIR/accessibility_audit.txt"
echo "=== Accessibility Audit $(date '+%Y-%m-%d %H:%M') ===" > "$_report"

# Get enabled accessibility services
_services=$(settings get secure enabled_accessibility_services 2>/dev/null)

if [ -z "$_services" ] || [ "$_services" = "null" ]; then
    echo "  No accessibility services enabled — good for battery!" >> "$_report"
    vb_log "A11Y" "No accessibility services active"
    return 0
fi

_count=0
echo "$_services" | tr ':' '\n' | while IFS= read -r _svc; do
    [ -z "$_svc" ] && continue
    _pkg=$(echo "$_svc" | sed 's|/.*||')
    echo "  ACTIVE: $_svc" >> "$_report"
    _count=$(( _count + 1 ))
done

echo "" >> "$_report"
echo "  NOTE: Each accessibility service intercepts ALL UI events." >> "$_report"
echo "  They significantly impact battery life and performance." >> "$_report"
echo "  Disable any you don't actively need." >> "$_report"

vb_log "A11Y" "Audit complete — report saved"
