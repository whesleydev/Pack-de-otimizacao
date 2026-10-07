#!/system/bin/sh
# VOID BATTERY v9.1 — Doze Whitelist Cleaner

[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

if [ "${VB_MANAGE_DOZE:-false}" != "true" ]; then
    vb_log "DOZEWL" "Doze whitelist preserved under Android/OEM control"
    return 0
fi

vb_log "DOZEWL" "Cleaning whitelist"

dumpsys deviceidle whitelist 2>/dev/null | \
    grep -oE '(system-excidle|system|user),[^ ]+' | \
    sed 's/^[^,]*,//' | while IFS= read -r _p; do
    [ -z "$_p" ] && continue
    vb_is_excluded "$_p" && continue
    dumpsys deviceidle whitelist -"$_p" >/dev/null 2>&1
done
