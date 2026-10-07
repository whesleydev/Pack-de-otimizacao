#!/system/bin/sh
# VOID BATTERY v9.1 — Discharge Logger
_csv="$VB_REPORT_DIR/discharge_curve.csv"
[ ! -f "$_csv" ] && echo "timestamp,level,temp,voltage,screen,profile" > "$_csv"

echo "$(date '+%Y-%m-%d %H:%M:%S'),$VB_LEVEL,$VB_TEMP,$(vb_battery_voltage),$VB_SCREEN,$VB_PROFILE" >> "$_csv"

_lines=$(wc -l < "$_csv" 2>/dev/null || echo 0)
[ "$_lines" -gt 5000 ] && {
    head -1 "$_csv" > "$_csv.tmp"
    tail -n 4000 "$_csv" >> "$_csv.tmp"
    mv "$_csv.tmp" "$_csv"
}
