#!/system/bin/sh
SKIPUNZIP=1

ui_print " "
ui_print "┌─────────────────────────────────────────────────────────┐"
ui_print "│                                                         │"
ui_print "│                        )                               │"
ui_print "│                     ) (:                               │"
ui_print "│                   (   ) )                              │"
ui_print "│                    \`-._.-'                             │"
ui_print "│                                                         │"
ui_print "│    |--\  |  |  /--\  |--  |\  |  |  \ /              │"
ui_print "│    |--/  |--|  |  |  |--  | \ |  |   X               │"
ui_print "│    |     |  |  \__/  |__  |  \|  |  / \              │"
ui_print "│                                                         │"
ui_print "│           Gaming Performance Optimizer                 │"
ui_print "│         System Optimizer · Boost · DNS · No Root           │"
ui_print "│                                                         │"
ui_print "├─────────────────────────────────────────────────────────┤"
ui_print "│  Version   : v3.0                                       │"
ui_print "│  Author    : By_Rafael_System                           │"
ui_print "│  Telegram  : t.me/proyect_diablo                        │"
ui_print "│  GitHub    : github.com/ByRafaelSystem                  │"
ui_print "├─────────────────────────────────────────────────────────┤"
ui_print "│                                                         │"

# Extract files
unzip -o "$ZIPFILE" -x 'META-INF/*' -d "$MODPATH" >&2

ui_print "│  [*] Module files deployed                              │"

# Permissions
set_perm_recursive "$MODPATH" root root 0755 0644
set_perm "$MODPATH/service.sh" root root 0755
set_perm "$MODPATH/uninstall.sh" root root 0755

ui_print "│  [*] Permissions configured                             │"
ui_print "│  [*] Phoenix is ready                                   │"
ui_print "│                                                         │"
ui_print "└─────────────────────────────────────────────────────────┘"
ui_print " "

# ── Notificación de instalación (estilo GoodPing) ─────────────────────────────
# Espera a que el sistema esté listo antes de enviar la notificación
(
  i=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 30 ]; do
    sleep 2
    i=$((i + 1))
  done
  cmd notification post -S bigtext -t 'Phoenix 🔥' 'PhoenixBoost' " Instalado correctamente ✅"
) &
