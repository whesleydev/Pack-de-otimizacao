#!/system/bin/sh
# =============================================================================
#  action.sh - Botão de ação do gerenciador.
#  Mostra o status do loop e permite aplicar/limpar na hora.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

echo "=================================================="
echo "  Pack OTM · Service Loop"
echo "=================================================="
echo "  Estado:        $( [ -f "$STATE/stop" ] && echo PARADO || echo ATIVO )"
echo "  RAM livre:     $(free_ram_mb) MB"
echo "  Loop a cada:   ${LOOP_INTERVAL}s"
echo "  Limpeza a cada:${CLEAN_INTERVAL}s"
echo "  Config:        $CFG"
echo "--------------------------------------------------"
echo "  Log recente:"
tail -n 8 "$STATE/loop.log" 2>/dev/null | sed 's/^/    /'
echo "=================================================="
