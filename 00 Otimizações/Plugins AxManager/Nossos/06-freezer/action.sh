#!/system/bin/sh
# =============================================================================
#  action.sh - Botão de ação: status + menu rápido do congelador.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

_ensure_lists
echo "=================================================="
echo "  Pack OTM · Congelar Apps"
echo "=================================================="
echo "  Serviço:       $( [ -f "$STATE/stop" ] && echo PARADO || echo ATIVO )"
echo "  Modo:          $FREEZE_MODE"
echo "  Cache freezer: $( [ "$CACHE_FREEZER" = "1" ] && echo ligado || echo desligado )"
echo "  Blacklist:     $(wc -l < "$BL_FILE" 2>/dev/null | tr -d ' ') apps"
echo "  Whitelist:     $(wc -l < "$WL_FILE" 2>/dev/null | tr -d ' ') apps"
echo "--------------------------------------------------"
echo "  Congelados agora:"
for p in $(freeze_list); do
    is_installed "$p" && echo "    • $p"
done
echo "--------------------------------------------------"
echo "  Log recente:"
tail -n 6 "$LOG" 2>/dev/null | sed 's/^/    /'
echo "=================================================="
