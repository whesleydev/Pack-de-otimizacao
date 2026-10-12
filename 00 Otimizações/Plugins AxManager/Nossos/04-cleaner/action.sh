#!/system/bin/sh
# =============================================================================
#  action.sh - Botão de ação: status e limpeza na hora.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

echo "=================================================="
echo "  Pack OTM · Limpeza & Memória"
echo "=================================================="
echo "  Estado:         $( [ -f "$STATE/stop" ] && echo PARADO || echo ATIVO )"
echo "  RAM livre:      $(free_ram_mb) MB"
echo "  Intervalo:      ${CLEAN_INTERVAL}s"
echo "  Config:         $CFG"
echo "--------------------------------------------------"
echo "  Log recente:"
tail -n 8 "$STATE/loop.log" 2>/dev/null | sed 's/^/    /'
echo "=================================================="
