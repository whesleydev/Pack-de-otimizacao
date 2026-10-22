#!/system/bin/sh
type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }
[ -n "$MODPATH" ] && DIRECT="$MODPATH" || DIRECT="$(cd "$(dirname "$0")" && pwd)"

ui_print "=================================================="
ui_print "  Pack OTM · Limpeza & Memória v1.0"
ui_print "  Cache, logcat, fstrim e RAM em segundo plano"
ui_print "=================================================="
chmod 755 "$DIRECT/service.sh" "$DIRECT/apply.sh" "$DIRECT/action.sh" "$DIRECT/lib.sh" 2>/dev/null
ui_print " [✔] Instalado. Limpeza inicia no próximo boot."
ui_print "=================================================="
