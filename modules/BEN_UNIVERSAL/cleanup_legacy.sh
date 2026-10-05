#!/system/bin/sh
BASE="/sdcard/.ben_universal"
mkdir -p "$BASE" 2>/dev/null
U=$(id -u 2>/dev/null)
[ "$U" = "2000" ] || [ "$U" = "0" ] || exit 1
[ -f "$BASE/daemon.pid" ] && P=$(cat "$BASE/daemon.pid" 2>/dev/null) && [ -n "$P" ] && kill "$P" 2>/dev/null
settings delete global cached_apps_freezer 2>/dev/null
settings delete global debug.sf.low_latency_mode 2>/dev/null
settings delete global hwui.use_vulkan 2>/dev/null
SDK=$(getprop ro.build.version.sdk 2>/dev/null); case "$SDK" in ''|*[!0-9]*) SDK=0;; esac
[ "$SDK" -ge 29 ] 2>/dev/null && cmd device_config delete activity_manager max_cached_processes 2>/dev/null
if [ "$SDK" -ge 31 ] 2>/dev/null; then
 for pkg in com.dts.freefireth com.dts.freefiremax com.dts.freefire; do cmd game mode standard "$pkg" 2>/dev/null; done
fi
rm -f "$BASE/daemon.pid" "$BASE/game.state"
echo "BEN v4.6 legacy cleanup completed."
