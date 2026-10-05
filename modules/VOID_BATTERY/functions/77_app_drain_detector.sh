#!/system/bin/sh
# VOID BATTERY v9.1 — App Battery Drain Detector
# Identifies apps consuming excessive CPU in background and restricts them
# Only acts on clear offenders — never touches user-active apps

vb_rate_ok "drain_detect" 1800 || return 0

vb_log "DRAIN" "Scanning for battery drain offenders — $VB_PROFILE"

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE|ECO)
        _threshold=5 ;;
    *)
        return 0 ;;
esac

_report="$VB_REPORT_DIR/drain_offenders.txt"
echo "=== Drain Report $(date '+%Y-%m-%d %H:%M') ===" > "$_report"

# Find apps with excessive CPU in background
_count=0
dumpsys cpuinfo 2>/dev/null | grep -E '^\s*[0-9]+%' | head -20 | while IFS= read -r _line; do
    _cpu=$(echo "$_line" | sed 's/%.*//' | tr -d ' ')
    _proc=$(echo "$_line" | sed 's/.*: //')
    _pkg=$(echo "$_proc" | sed 's/:.*//')

    [ -z "$_cpu" ] && continue
    [ "$_cpu" -lt "$_threshold" ] 2>/dev/null && continue

    # Skip if foreground or excluded
    vb_is_excluded "$_pkg" && continue
    vb_is_foreground "$_pkg" && continue

    echo "  OFFENDER: $_pkg using ${_cpu}% CPU" >> "$_report"
    if [ "${VB_MANAGE_STANDBY:-false}" = "true" ]; then
        am set-inactive "$_pkg" true 2>/dev/null
        _count=$(( _count + 1 ))
    fi
done

if [ "${VB_MANAGE_STANDBY:-false}" = "true" ]; then
    vb_log "DRAIN" "Detected and restricted drain offenders"
else
    vb_log "DRAIN" "Drain report generated; no apps restricted"
fi
