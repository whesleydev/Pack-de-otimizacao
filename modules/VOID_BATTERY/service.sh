#!/system/bin/sh
# VOID BATTERY v9.1 — Background Service
MODPATH="${0%/*}"
LOG="/sdcard/VOID_BATTERY/service.log"
mkdir -p /sdcard/VOID_BATTERY 2>/dev/null

# Wait for boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
done
sleep 30

echo "[$(date '+%Y-%m-%d %H:%M:%S')] VOID BATTERY v9.1 — Service started" >> "$LOG"

# Boot optimization
[ -f "$MODPATH/tools/boot_optimize.sh" ] && sh "$MODPATH/tools/boot_optimize.sh" "$MODPATH" >> "$LOG" 2>&1

# Load intervals
. "$MODPATH/config/voidbattery.conf" 2>/dev/null
_core=${VB_INTERVAL:-300}
_heavy=${VB_HEAVY_INTERVAL:-1800}
_report=${VB_REPORT_INTERVAL:-3600}
_counter=0

while true; do
    _counter=$(( _counter + 1 ))

    # Do not run a periodic optimization cycle while the screen is off by
    # default. This avoids the module itself becoming a source of wakeups and
    # prevents OriginOS from fighting repeated shell policy writes overnight.
    if [ "${VB_SKIP_WHEN_SCREEN_OFF:-true}" = "true" ]; then
        _awake=0
        dumpsys power 2>/dev/null | grep -qE 'mWakefulness=Awake|Display Power: state=ON' && _awake=1
        if [ "$_awake" = "0" ]; then
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cycle skipped: screen off" >> "$LOG"
            sleep "${VB_SCREEN_OFF_INTERVAL:-1800}"
            continue
        fi
    fi

    # Core — every cycle
    sh "$MODPATH/action.sh" run >> "$LOG" 2>&1

    # Heavy — every _heavy/_core cycles
    _hmod=$(( _heavy / _core ))
    [ "$_hmod" -lt 1 ] && _hmod=1
    [ $(( _counter % _hmod )) -eq 0 ] && sh "$MODPATH/action.sh" heavy >> "$LOG" 2>&1

    # Reports — every _report/_core cycles
    _rmod=$(( _report / _core ))
    [ "$_rmod" -lt 1 ] && _rmod=1
    [ $(( _counter % _rmod )) -eq 0 ] && sh "$MODPATH/action.sh" report >> "$LOG" 2>&1

    # Trim log
    _lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
    [ "$_lines" -gt 2000 ] && {
        tail -n 1500 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
    }

    sleep "$_core"
done
