#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════
# VOID BATTERY v9.1 — Helper Functions (Optimized)
# Sourced ONCE by action.sh. Inherited by all functions.
# No bash-isms. No grep -oP. No export -f.
# ═══════════════════════════════════════════════════════════════

VB_LOG_DIR="/sdcard/VOID_BATTERY"
VB_LOG="$VB_LOG_DIR/engine.log"
# Create this file through ADB/Shizuku to disable operational log collection.
VB_DISABLE_LOGS_FILE="${VB_DISABLE_LOGS_FILE:-/data/local/tmp/void_battery_disable_logs}"
void_logs_disabled() { [ "${VB_DISABLE_LOGS:-0}" = "1" ] || [ -f "$VB_DISABLE_LOGS_FILE" ]; }
VB_SNAP_DIR="$VB_LOG_DIR/snapshots"
VB_REPORT_DIR="$VB_LOG_DIR/reports"

# ─── Logging (compact timestamp for speed) ───────────────────
vb_log() {
    void_logs_disabled && return 0
    echo "[$(date '+%H:%M:%S')] [$1] $2" >> "$VB_LOG" 2>/dev/null
}

# ─── Safe Settings Writes ────────────────────────────────────
vb_settings() {
    [ "${VB_DRY_RUN:-0}" = "1" ] && return 0
    settings put "$1" "$2" "$3" >/dev/null 2>&1
    return 0
}

vb_devconfig() {
    [ "${VB_DRY_RUN:-0}" = "1" ] && return 0
    cmd device_config put "$1" "$2" "$3" >/dev/null 2>&1
    return 0
}

# ─── App Checks ──────────────────────────────────────────────
vb_is_excluded() {
    echo "$VB_EXCLUDED" | grep -qxF "$1" && return 0
    [ "$VB_PUSH_PROTECT" = "true" ] && echo "$VB_PUSH_APPS" | grep -qxF "$1" && return 0
    return 1
}

vb_is_push_critical() {
    echo "$VB_PUSH_APPS" | grep -qxF "$1"
}

vb_is_installed() {
    pm path "$1" >/dev/null 2>&1
}

vb_is_foreground() {
    dumpsys activity processes 2>/dev/null | grep -q "foreground.*$1"
}

# ─── App List Loading ────────────────────────────────────────
vb_load_list() {
    [ -f "$1" ] && grep -v '^\s*#' "$1" | grep -v '^\s*$' | tr -d '\r' || echo ""
}

# ─── Rate Limiter ─────────────────────────────────────────────
vb_rate_ok() {
    _rf="$VB_LOG_DIR/.rate_${1}"
    _now=$(date +%s)
    _last=$(cat "$_rf" 2>/dev/null || echo 0)
    if [ $(( _now - _last )) -ge "${2:-300}" ]; then
        echo "$_now" > "$_rf"
        return 0
    fi
    return 1
}

# ─── Get UID ──────────────────────────────────────────────────
vb_get_uid() {
    dumpsys package "$1" 2>/dev/null | grep 'userId=' | head -1 | sed 's/.*userId=//;s/[^0-9].*//'
}
