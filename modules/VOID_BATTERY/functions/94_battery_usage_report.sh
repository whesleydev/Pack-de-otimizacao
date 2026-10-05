#!/system/bin/sh
# VOID BATTERY v9.1 — Battery Usage Report
_csv="$VB_REPORT_DIR/battery_usage.csv"
{
    echo "timestamp,package,events"
    _ts=$(date '+%Y-%m-%d %H:%M:%S')
    dumpsys batterystats 2>/dev/null | grep -oE 'proc=[a-z][a-z0-9_.]+' | \
        sed 's/proc=//' | sort | uniq -c | sort -rn | head -20 | \
        while read -r _cnt _p; do
            [ -z "$_p" ] && continue
            echo "$_ts,$_p,$_cnt"
        done
} > "$_csv" >/dev/null 2>&1
vb_log "BUSAGE" "Usage report generated"
