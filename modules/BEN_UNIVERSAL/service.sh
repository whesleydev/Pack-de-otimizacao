#!/system/bin/sh
# BEN UNIVERSAL v4.6 • FREE FIRE FRAME STABILITY
BASE="/sdcard/.ben_universal"; PID="$BASE/daemon.pid"; STATE="$BASE/state"
mkdir -p "$BASE" 2>/dev/null
U=$(id -u 2>/dev/null)
[ "$U" = "2000" ] || [ "$U" = "0" ] || exit 0
if [ -f "$PID" ]; then OLD=$(cat "$PID" 2>/dev/null); [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null && exit 0; fi
(
 echo "$$" > "$PID"
 echo "v4.6-freefire-frame-stability" > "$STATE"
 trap 'rm -f "$PID"; exit 0' INT TERM EXIT
 while true; do sleep 600; done
) &
echo "$!" > "$PID"
exit 0
