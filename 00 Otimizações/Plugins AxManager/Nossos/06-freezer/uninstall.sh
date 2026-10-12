#!/system/bin/sh
# =============================================================================
#  uninstall.sh - Para o serviço e DESCONGELA tudo (segurança).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm_freezer"
[ -d "$STATE" ] || STATE="$DIR/state"

touch "$STATE/stop" 2>/dev/null
for p in $(pgrep -f "$DIR/service.sh" 2>/dev/null); do kill "$p" 2>/dev/null; done

. "$DIR/lib.sh"
revert
rm -f "$STATE/stop"
echo "Congelar Apps removido; todos os apps descongelados."
