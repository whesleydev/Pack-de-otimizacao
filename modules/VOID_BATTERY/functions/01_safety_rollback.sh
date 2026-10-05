#!/system/bin/sh
# VOID BATTERY v9.1 — Safety Rollback & Snapshot

# Only snapshot every hour
vb_rate_ok "snapshot" 3600 || return 0

vb_log "SNAP" "Creating settings snapshot"

{
    for _k in window_animation_scale transition_animation_scale animator_duration_scale \
        low_power low_power_sticky dynamic_power_savings_enabled low_power_trigger_level \
        wifi_scan_always_enabled ble_scan_always_enabled mobile_data_always_on \
        wifi_scan_interval_ms automatic_power_save_mode battery_saver_constants \
        app_standby_enabled disable_window_blurs activity_starts_logging_enabled \
        background_process_limit; do
        _v=$(settings get global "$_k" 2>/dev/null)
        [ "$_v" != "null" ] && [ -n "$_v" ] && echo "${_k}=${_v}"
    done
} > "$VB_SNAP_DIR/snap_global_latest.txt" >/dev/null 2>&1

{
    for _k in location_background_throttle_interval_ms doze_enabled \
        wake_gesture_enabled double_tap_to_wake; do
        _v=$(settings get secure "$_k" 2>/dev/null)
        [ "$_v" != "null" ] && [ -n "$_v" ] && echo "${_k}=${_v}"
    done
} > "$VB_SNAP_DIR/snap_secure_latest.txt" >/dev/null 2>&1

{
    for _k in haptic_feedback_enabled vibrate_when_ringing screen_brightness_mode \
        screen_off_timeout peak_refresh_rate lift_to_wake nearby_scanning_enabled; do
        _v=$(settings get system "$_k" 2>/dev/null)
        [ "$_v" != "null" ] && [ -n "$_v" ] && echo "${_k}=${_v}"
    done
} > "$VB_SNAP_DIR/snap_system_latest.txt" >/dev/null 2>&1

# Keep dated backup
cp "$VB_SNAP_DIR/snap_global_latest.txt" "$VB_SNAP_DIR/snap_$(date +%Y%m%d_%H%M).txt" >/dev/null 2>&1

# Cleanup old (keep 10)
_old=$(ls -t "$VB_SNAP_DIR"/snap_2*.txt 2>/dev/null | tail -n +11)
[ -n "$_old" ] && echo "$_old" | while IFS= read -r _f; do rm -f "$_f"; done

vb_log "SNAP" "Snapshot saved"
