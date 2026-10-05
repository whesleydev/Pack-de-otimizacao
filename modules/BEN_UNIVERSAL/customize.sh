#!/system/bin/sh
# BEN UNIVERSAL v4.6 • INITIALIZATION
U=$(id -u 2>/dev/null)
[ "$U" = "2000" ] || [ "$U" = "0" ] || exit 1
BASE="/sdcard/.ben_universal"; mkdir -p "$BASE" 2>/dev/null
if [ ! -f "$BASE/.v46_migrated" ]; then
 DIR="$(dirname "$0")"
 [ -f "$DIR/cleanup_legacy.sh" ] && /system/bin/sh "$DIR/cleanup_legacy.sh" 2>/dev/null
 touch "$BASE/.v46_migrated"
fi
echo "v4.6" > "$BASE/version"
echo "freefire-frame-stability" > "$BASE/profile"
echo "BEN UNIVERSAL v4.6 initialized successfully."
exit 0
