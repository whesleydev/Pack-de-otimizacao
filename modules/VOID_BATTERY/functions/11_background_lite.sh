#!/system/bin/sh
# VOID BATTERY v9.1 — Background Offender Detection

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

if [ "${VB_MANAGE_BACKGROUND_DATA:-false}" != "true" ]; then
    vb_log "BGLITE" "Background AppOps detection disabled by safe default"
    return 0
fi

vb_log "BGLITE" "Scanning background — $VB_PROFILE"

_top=$(dumpsys activity processes 2>/dev/null | \
    grep -oE 'app=ProcessRecord\{[^ ]+ [0-9]+:[^/]+' | \
    sed 's/.*://;s/\/.*//' | sort | uniq -c | sort -rn | head -15)

echo "$_top" | while read -r _cnt _p; do
    [ -z "$_p" ] && continue
    vb_is_excluded "$_p" && continue
    vb_is_foreground "$_p" && continue
    case "$VB_PROFILE" in
        CRITICAL|POWERSAVE)
            cmd appops set "$_p" RUN_IN_BACKGROUND ignore >/dev/null 2>&1
            cmd appops set "$_p" WAKE_LOCK ignore >/dev/null 2>&1
            ;;
        ECO|IDLE)
            cmd appops set "$_p" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
            ;;
    esac
done
