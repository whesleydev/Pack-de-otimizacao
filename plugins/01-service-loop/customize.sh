#!/system/bin/sh

type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

[ -n "$MODPATH" ] && DIRECT="$MODPATH" || DIRECT="$(cd "$(dirname "$0")" && pwd)"

ui_print "=================================================="
ui_print "  Pack OTM · Service Loop v1.0"
ui_print "  Aplica o pack e mantém ativo em segundo plano"
ui_print "=================================================="

chmod 755 "$DIRECT/service.sh" "$DIRECT/apply.sh" "$DIRECT/action.sh" "$DIRECT/lib.sh" 2>/dev/null

# primeira aplicação durante a instalação (best-effort)
[ -f "$DIRECT/apply.sh" ] && sh "$DIRECT/apply.sh" >/dev/null 2>&1

ui_print " [✔] Instalado. O loop inicia no próximo boot."
ui_print "     Botão de ação mostra o status."
ui_print "=================================================="
