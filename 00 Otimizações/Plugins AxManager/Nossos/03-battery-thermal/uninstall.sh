#!/system/bin/sh
# =============================================================================
#  uninstall.sh - Para o vigia e reverte a economia.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm_battery"
[ -d "$STATE" ] || STATE="$DIR/state"

touch "$STATE/stop" 2>/dev/null
for p in $(pgrep -f "$DIR/service.sh" 2>/dev/null); do kill "$p" 2>/dev/null; done

. "$DIR/lib.sh"
revert_battery
rm -f "$STATE/stop" "$STATE/thermal_stop"
echo "Bateria & Térmico removido; economia revertida."
