#!/system/bin/sh
# VOID BATTERY v9.1 — Bloatware Action (OPT-IN)
[ "$VB_BLOAT" != "1" ] && return 0

_br=$(getprop ro.product.brand 2>/dev/null | tr 'A-Z' 'a-z')
_vf="$MODPATH/config/vendors/${_br}.txt"
[ ! -f "$_vf" ] && return 0

vb_log "BLOAT" "Disabling bloatware for $_br"
_c=0
while IFS= read -r _p; do
    echo "$_p" | grep -q '^\s*#' && continue
    [ -z "$_p" ] && continue
    vb_is_installed "$_p" || continue
    pm disable-user --user 0 "$_p" >/dev/null 2>&1 && _c=$((_c+1))
done < "$_vf"
vb_log "BLOAT" "Disabled $_c packages"
