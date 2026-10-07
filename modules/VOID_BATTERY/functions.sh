#!/system/bin/sh
MODPATH="${MODPATH:-${0%/*}}"
_d="$MODPATH/functions"
case "$1" in
    list)
        for _f in "$_d"/*.sh; do [ -f "$_f" ] && basename "$_f" .sh; done | sort
        ;;
    count)
        _c=0; for _f in "$_d"/*.sh; do [ -f "$_f" ] && _c=$((_c+1)); done; echo "$_c"
        ;;
    status)
        _c=0; for _f in "$_d"/*.sh; do [ -f "$_f" ] && _c=$((_c+1)); done
        echo "VOID BATTERY v9.1 — $_c functions"
        for _f in "$_d"/*.sh; do [ -f "$_f" ] && echo " + $(basename "$_f" .sh)"; done | sort
        ;;
esac
