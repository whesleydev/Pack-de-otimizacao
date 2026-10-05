#!/system/bin/sh
SKIPUNZIP=0

ui_print "═══════════════════════════════════════"
ui_print "   VOID BATTERY v9.1"
ui_print "   Ultimate Battery Optimizer"
ui_print "   106 Functions — No Root Required"
ui_print "═══════════════════════════════════════"
ui_print ""

DEVICE=$(getprop ro.product.model 2>/dev/null)
ANDROID=$(getprop ro.build.version.release 2>/dev/null)
SDK=$(getprop ro.build.version.sdk 2>/dev/null)
BRAND=$(getprop ro.product.brand 2>/dev/null | tr 'A-Z' 'a-z')

ui_print " Device:  $DEVICE"
ui_print " Android: $ANDROID (SDK $SDK)"
ui_print " Brand:   $BRAND"
ui_print ""

if [ "${SDK:-0}" -lt 26 ] 2>/dev/null; then
    ui_print " ERROR: Android 8.0+ required"
    abort
fi

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm_recursive "$MODPATH/system/bin" 0 0 0755 0755

for _f in "$MODPATH"/*.sh "$MODPATH"/functions/*.sh "$MODPATH"/tools/*.sh; do
    [ -f "$_f" ] && set_perm "$_f" 0 0 0755
done

mkdir -p /sdcard/VOID_BATTERY

_fc=0
for _f in "$MODPATH"/functions/*.sh; do [ -f "$_f" ] && _fc=$((_fc+1)); done

ui_print " OK  $_fc optimization functions installed"
ui_print " OK  Android shell compatible engine"
ui_print " OK  Safe rollback system enabled"
ui_print ""

VFILE="$MODPATH/config/vendors/${BRAND}.txt"
if [ -f "$VFILE" ]; then
    _bc=0
    while IFS= read -r _l; do
        echo "$_l" | grep -q '^\s*#' && continue
        [ -z "$_l" ] && continue
        _bc=$((_bc+1))
    done < "$VFILE"
    ui_print " OK  $BRAND vendor profile ($BC bloatware entries)"
    ui_print "     Set VB_BLOAT=1 in config to activate"
fi

ui_print ""
ui_print " Logs:   /sdcard/VOID_BATTERY/"
ui_print " Status: voidbattery-info"
ui_print ""
ui_print "═══════════════════════════════════════"
ui_print "   Installation Complete!"
ui_print "═══════════════════════════════════════"
