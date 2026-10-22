#!/system/bin/sh
# =============================================================================
#  action.sh - Botão de ação: status, temperatura e trava térmica.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

echo "=================================================="
echo "  Pack OTM · Bateria & Térmico"
echo "=================================================="
if [ -f "$STATE/thermal_stop" ]; then
    echo "  Estado:      PARADO (trava térmica atuou)"
else
    echo "  Estado:      $( [ -f "$STATE/stop" ] && echo PARADO || echo ATIVO )"
fi
echo "  Temperatura: $(read_temp_c)°C  (limite: ${THERMAL_MAX_C}°C)"
echo "  Carregando:  $(is_charging && echo sim || echo nao)"
echo "  Doze:        $( [ "$ENABLE_DOZE" = "1" ] && echo ligado || echo desligado )"
echo "  Config:      $CFG"
echo "--------------------------------------------------"
echo "  Log recente:"
tail -n 8 "$STATE/loop.log" 2>/dev/null | sed 's/^/    /'
echo "=================================================="
