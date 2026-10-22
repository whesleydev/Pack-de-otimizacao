#!/system/bin/sh
# =============================================================================
#  uninstall.sh - Para o serviço e reverte refresh/game mode.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm_fps"
[ -d "$STATE" ] || STATE="$DIR/state"

touch "$STATE/stop" 2>/dev/null
for p in $(pgrep -f "$DIR/service.sh" 2>/dev/null); do kill "$p" 2>/dev/null; done

. "$DIR/lib.sh"
revert_fps
rm -f "$STATE/stop"
echo "FPS & Refresh removido; refresh/game mode revertidos."
