# Game Scale - installer (sourced by AxManager)

prop() { sed -n "s/^$1=//p" "$MODPATH/module.prop" 2>/dev/null | head -n1; }
line() { ui_print "  ------------------------------------------"; }
pause() { sleep 0.15 2>/dev/null; }

NAME="$(prop name)";       [ -z "$NAME" ] && NAME="Game Scale"
VER="$(prop version)";     [ -z "$VER" ] && VER="v1.4.1"
AUTH="$(prop author)";     [ -z "$AUTH" ] && AUTH="Philip Nghia"

ui_print ""
ui_print "  =========================================="
ui_print "   G A M E   S C A L E"
ui_print "   Per-app resolution scaler  |  WebUI"
ui_print "  =========================================="
ui_print "   Version : $VER"
ui_print "   Author  : $AUTH"
ui_print "  =========================================="
pause

ui_print ""
ui_print "  [1/3] Kiem tra thiet bi"
line
ui_print "   Hang     : $(getprop ro.product.manufacturer)"
ui_print "   Model    : $(getprop ro.product.model)"
ui_print "   Android  : $(getprop ro.build.version.release) (API $API)"
ui_print "   CPU ABI  : $ARCH"
ui_print "   AxManager: server $AXERONVER"
pause

if [ -n "$API" ] && [ "$API" -lt 31 ]; then
  ui_print ""
  abort "  ! Can Android 12 (API 31) tro len de dung Game Mode."
fi
ui_print "   [ OK ] Phien ban Android tuong thich"

GM="$(cmd game help 2>&1)"
case "$GM" in
  ""|*"find service"*|*"not found"*)
    ui_print "   [ !! ] Khong kiem tra duoc Game Mode (van tiep tuc)" ;;
  *)
    ui_print "   [ OK ] Dich vu Game Mode san sang" ;;
esac
pause

ui_print ""
ui_print "  [2/3] Kiem tra tap tin"
line
if [ -f "$MODPATH/webroot/index.html" ]; then
  ui_print "   [ OK ] WebUI (webroot/index.html)"
else
  abort "  ! Thieu webroot/index.html, goi cai dat bi loi."
fi
[ -f "$MODPATH/banner.png" ] && ui_print "   [ OK ] Banner"
[ -f "$MODPATH/module.prop" ] && ui_print "   [ OK ] module.prop"
pause

ui_print ""
ui_print "  [3/3] Hoan tat"
line
ui_print "   Da cai dat $NAME $VER"
ui_print ""
ui_print "   Cach dung:"
ui_print "    1. Mo AxManager > Plugin > $NAME"
ui_print "    2. Mo WebUI, chon game va dat ti le"
ui_print "    3. Bam Ap dung roi mo lai game"
ui_print ""
ui_print "   Luu y: Android thuong chi ho tro 0.3 - 0.9."
ui_print "  =========================================="
ui_print ""
