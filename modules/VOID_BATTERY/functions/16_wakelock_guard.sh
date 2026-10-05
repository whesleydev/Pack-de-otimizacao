#!/system/bin/sh
# VOID BATTERY v9.1 — Wakelock Guard

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

if [ "${VB_ALLOW_AGGRESSIVE_CRITICAL:-false}" != "true" ]; then
    vb_log "WAKE" "Wakelock AppOps guard disabled by safe default"
    return 0
fi

case "$VB_PROFILE" in
    CRITICAL)   _n=15 ;;
    POWERSAVE)  _n=10 ;;
    ECO)        _n=7 ;;
    *)          _n=5 ;;
esac

dumpsys batterystats 2>/dev/null | grep -oE 'Wk [a-z][a-z0-9_.]+' | \
    sed 's/Wk //;s/:.*//' | sort | uniq -c | sort -rn | head -n "$_n" | \
    while read -r _cnt _p; do
        [ -z "$_p" ] && continue
        vb_is_excluded "$_p" && continue
        cmd appops set "$_p" WAKE_LOCK ignore >/dev/null 2>&1
    done
vb_log "WAKE" "Guard checked top $_n"
