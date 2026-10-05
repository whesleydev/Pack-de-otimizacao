#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] Foreground Service Audit
vb_log "FGSVC" "Auditing foreground services"

_fgs=$(dumpsys activity services 2>/dev/null | grep 'isForeground=true' | \
    sed 's/.*ServiceRecord{//;s/ .*//' | sort -u | head -20)

_cnt=0
echo "$_fgs" | while IFS= read -r _s; do
    [ -z "$_s" ] && continue
    _cnt=$((_cnt+1))
done

vb_log "FGSVC" "Active foreground services found"

if [ "$VB_PROFILE" = "CRITICAL" ] && [ "${VB_ALLOW_AGGRESSIVE_CRITICAL:-false}" = "true" ]; then
    dumpsys activity services 2>/dev/null | grep 'app=ProcessRecord' | \
        sed 's/.*://;s/\/.*//' | sort -u | while IFS= read -r _p; do
        [ -z "$_p" ] && continue
        vb_is_excluded "$_p" && continue
        vb_is_push_critical "$_p" && continue
        echo "$VB_EXTREME" | grep -qxF "$_p" && {
            am force-stop "$_p" >/dev/null 2>&1
            vb_log "FGSVC" "Stopped non-essential FG service: $_p"
        }
    done
fi
