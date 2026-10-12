#!/system/bin/sh
type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }
[ -n "$MODPATH" ] && DIRECT="$MODPATH" || DIRECT="$(cd "$(dirname "$0")" && pwd)"

ui_print "=================================================="
ui_print "  Pack OTM · Bateria & Térmico v1.0"
ui_print "  Economia + trava térmica automática (45°C)"
ui_print "=================================================="
chmod 755 "$DIRECT/service.sh" "$DIRECT/apply.sh" "$DIRECT/action.sh" "$DIRECT/lib.sh" 2>/dev/null
ui_print " [✔] Instalado. Vigia térmico inicia no próximo boot."
ui_print "     Botão de ação mostra temperatura e status."
ui_print "=================================================="
