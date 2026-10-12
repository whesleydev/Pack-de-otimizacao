#!/system/bin/sh
# Reverção ao desinstalar.

DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/apply.sh" ] && sh "$DIR/apply.sh" restore >/dev/null 2>&1
rm -f /data/adb/packotm/stop 2>/dev/null
echo "Pack OTM WebUI removido; tweaks revertidos."
