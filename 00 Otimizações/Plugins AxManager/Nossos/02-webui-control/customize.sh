#!/system/bin/sh

type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

[ -n "$MODPATH" ] && DIRECT="$MODPATH" || DIRECT="$(cd "$(dirname "$0")" && pwd)"

ui_print "=================================================="
ui_print "  Pack OTM · WebUI Control v1.1"
ui_print "  Painel configurável (abre pelo gerenciador)"
ui_print "=================================================="

chmod 755 "$DIRECT/service.sh" "$DIRECT/apply.sh" 2>/dev/null
chmod 644 "$DIRECT/webroot/index.html" "$DIRECT/webroot/style.css" "$DIRECT/webroot/app.js" 2>/dev/null

# instala o motor num caminho fixo para a WebUI chamar
mkdir -p /data/adb/packotm 2>/dev/null
cp -f "$DIRECT/apply.sh" /data/adb/packotm/apply.sh 2>/dev/null
chmod 755 /data/adb/packotm/apply.sh 2>/dev/null

# gera config padrão
sh /data/adb/packotm/apply.sh save >/dev/null 2>&1 || sh "$DIRECT/apply.sh" save >/dev/null 2>&1

ui_print " [✔] Instalado. Abra a WebUI pelo gerenciador para configurar."
ui_print "=================================================="
