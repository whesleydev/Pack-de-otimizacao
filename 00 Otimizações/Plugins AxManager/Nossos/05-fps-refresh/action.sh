#!/system/bin/sh
# =============================================================================
#  action.sh - Botão de ação: status do refresh/FPS.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

echo "=================================================="
echo "  Pack OTM · FPS & Refresh"
echo "=================================================="
echo "  Estado:       $( [ -f "$STATE/stop" ] && echo PARADO || echo ATIVO )"
echo "  Painel (max): $(panel_max_hz)Hz"
echo "  Alvo:         $( [ "$TARGET_HZ" = "0" ] && echo 'máximo do painel' || echo "${TARGET_HZ}Hz" )"
echo "  Modo de jogo: $( [ "$GAME_MODE" = "1" ] && echo ligado || echo desligado )"
echo "  Config:       $CFG"
echo "--------------------------------------------------"
echo "  Log recente:"
tail -n 8 "$STATE/loop.log" 2>/dev/null | sed 's/^/    /'
echo "=================================================="
