#!/system/bin/sh
# =============================================================================
#  uninstall.sh - Para a limpeza (nada a reverter: só limpa).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm_cleaner"
[ -d "$STATE" ] || STATE="$DIR/state"

touch "$STATE/stop" 2>/dev/null
for p in $(pgrep -f "$DIR/service.sh" 2>/dev/null); do kill "$p" 2>/dev/null; done
rm -f "$STATE/stop"
echo "Limpeza & Memória removido; loop parado."
