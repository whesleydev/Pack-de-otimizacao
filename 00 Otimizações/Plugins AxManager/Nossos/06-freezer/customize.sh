#!/system/bin/sh
type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }
[ -n "$MODPATH" ] && DIRECT="$MODPATH" || DIRECT="$(cd "$(dirname "$0")" && pwd)"

ui_print "=================================================="
ui_print "  Pack OTM · Congelar Apps v1.0"
ui_print "  Congela apps de fundo com whitelist"
ui_print "=================================================="
chmod 755 "$DIRECT/service.sh" "$DIRECT/apply.sh" "$DIRECT/action.sh" "$DIRECT/lib.sh" 2>/dev/null

# estado fixo p/ a WebUI e o serviço encontrarem as listas
mkdir -p /data/adb/packotm_freezer 2>/dev/null
sh "$DIRECT/apply.sh" save >/dev/null 2>&1
sh "$DIRECT/apply.sh" status >/dev/null 2>&1

ui_print " [✔] Instalado. Apps essenciais estão protegidos por padrão."
ui_print "     Use o botão de ação para ver/gerenciar a whitelist."
ui_print "=================================================="
