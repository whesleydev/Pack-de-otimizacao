#!/system/bin/sh
# VOID BATTERY v9.1 — Battery Health Report
_csv="$VB_REPORT_DIR/battery_health.csv"
[ ! -f "$_csv" ] && echo "timestamp,level,health,temperature,voltage,status" > "$_csv"

_ts=$(date '+%Y-%m-%d %H:%M:%S')
_h=$(vb_battery_health)
_v=$(vb_battery_voltage)
echo "$_ts,$VB_LEVEL,$_h,$VB_TEMP,$_v,$(vb_battery_status)" >> "$_csv"

_lines=$(wc -l < "$_csv" 2>/dev/null || echo 0)
[ "$_lines" -gt 2000 ] && {
    head -1 "$_csv" > "$_csv.tmp"
    tail -n 1500 "$_csv" >> "$_csv.tmp"
    mv "$_csv.tmp" "$_csv"
}
vb_log "HEALTH" "Recorded: ${VB_LEVEL}% ${VB_TEMP}C"
