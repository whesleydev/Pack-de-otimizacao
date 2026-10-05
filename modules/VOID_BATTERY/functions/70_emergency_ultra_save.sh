#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Emergency Ultra-Save Mode
# Only activates at CRITICAL level — maximum battery preservation

[ "$VB_PROFILE" != "CRITICAL" ] && return 0

if [ "${VB_ALLOW_AGGRESSIVE_CRITICAL:-false}" != "true" ]; then
    vb_log "EMERG" "Emergency restrictions disabled by safe default"
    return 0
fi

vb_log "EMERG" "EMERGENCY MODE — ${VB_LEVEL}%"

# Force all non-essential apps to restricted standby
echo "$VB_EXTREME" | while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    vb_is_excluded "$_p" && continue
    vb_is_installed "$_p" || continue
    am set-standby-bucket "$_p" restricted >/dev/null 2>&1
    am set-inactive "$_p" true >/dev/null 2>&1
    cmd appops set "$_p" RUN_IN_BACKGROUND ignore >/dev/null 2>&1
    cmd appops set "$_p" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
    cmd appops set "$_p" WAKE_LOCK ignore >/dev/null 2>&1
done

# Kill background apps (except excluded)
echo "$VB_EXTREME" | while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    vb_is_excluded "$_p" && continue
    vb_is_foreground "$_p" && continue
    am kill "$_p" >/dev/null 2>&1
done

# Maximum Doze
dumpsys deviceidle force-idle >/dev/null 2>&1

vb_log "EMERG" "Emergency mode activated"
