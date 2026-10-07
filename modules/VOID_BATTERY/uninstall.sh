#!/system/bin/sh
MODPATH="${0%/*}"
LOG="/sdcard/VOID_BATTERY/uninstall.log"

_log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"; }

_log "VOID BATTERY v9.1 — Uninstall started"

# Restore display
settings put global window_animation_scale 1.0 2>/dev/null
settings put global transition_animation_scale 1.0 2>/dev/null
settings put global animator_duration_scale 1.0 2>/dev/null
settings put global disable_window_blurs 0 2>/dev/null

# Restore battery saver
settings put global low_power 0 2>/dev/null
settings put global low_power_sticky 0 2>/dev/null
settings put global dynamic_power_savings_enabled 0 2>/dev/null
settings put global automatic_power_save_mode 0 2>/dev/null
settings delete global battery_saver_constants 2>/dev/null

# Restore Doze
settings delete global device_idle_constants 2>/dev/null
for _k in light_after_inactive_to inactive_to sensing_to locating_to \
    idle_after_inactive_to idle_to max_idle_to idle_factor wait_for_unlock \
    max_temp_app_allowlist_duration_ms idle_pending_to max_idle_pending_to \
    idle_pending_factor motion_inactive_to light_pre_idle_to light_idle_to \
    light_idle_factor light_max_idle_to light_idle_maintenance_min_budget \
    light_idle_maintenance_max_budget min_time_to_alarm; do
    cmd device_config delete deviceidle "$_k" 2>/dev/null
done
dumpsys deviceidle disable 2>/dev/null
dumpsys deviceidle enable 2>/dev/null

# Do not overwrite user/OEM network choices during uninstall. The previous
# release did this and could re-enable scans or alter OriginOS behavior.
_log "Network settings left under user/OEM control"

# Remove module-owned per-UID restrictions for known configured lists.
for _list in "$MODPATH/config/excluded_apps.txt" "$MODPATH/config/push_critical_apps.txt" "$MODPATH/config/social_apps.txt" "$MODPATH/config/moderate_apps.txt" "$MODPATH/config/extreme_apps.txt"; do
    [ -f "$_list" ] || continue
    while IFS= read -r _p; do
        case "$_p" in ''|\#*) continue ;; esac
        _uid=$(dumpsys package "$_p" 2>/dev/null | grep 'userId=' | head -1 | sed 's/.*userId=//;s/[^0-9].*//')
        [ -z "$_uid" ] && continue
        cmd netpolicy clearuidpolicy "$_uid" 2>/dev/null
        cmd netpolicy remove restrict-background-whitelist "$_uid" 2>/dev/null
        cmd appops set "$_p" RUN_IN_BACKGROUND default 2>/dev/null
        cmd appops set "$_p" RUN_ANY_IN_BACKGROUND default 2>/dev/null
        cmd appops set "$_p" WAKE_LOCK default 2>/dev/null
        am set-standby-bucket "$_p" active 2>/dev/null
        am set-inactive "$_p" false 2>/dev/null
    done < "$_list"
done

# Restore AppOps changed by the previous GMS optimizer.
for _p in com.google.android.gms com.google.android.gsf; do
    cmd appops set "$_p" RUN_IN_BACKGROUND default 2>/dev/null
    cmd appops set "$_p" RUN_ANY_IN_BACKGROUND default 2>/dev/null
    cmd appops set "$_p" WAKE_LOCK default 2>/dev/null
    cmd appops set "$_p" MONITOR_LOCATION default 2>/dev/null
    cmd appops set "$_p" MONITOR_HIGH_POWER_LOCATION default 2>/dev/null
done

# Restore display features
settings put system haptic_feedback_enabled 1 2>/dev/null
settings put system vibrate_when_ringing 1 2>/dev/null
settings put system screen_brightness_mode 1 2>/dev/null
settings put secure doze_enabled 1 2>/dev/null
settings put system lift_to_wake 1 2>/dev/null
settings put secure wake_gesture_enabled 1 2>/dev/null
settings put secure double_tap_to_wake 1 2>/dev/null
settings put system peak_refresh_rate 120.0 2>/dev/null
settings put system screen_off_timeout 60000 2>/dev/null

# Restore process limits without forcing App Standby globally.
settings delete global background_process_limit 2>/dev/null
_log "Global App Standby setting left under Android/OEM control"

# Restore sync
settings put global account_sync_enabled 1 2>/dev/null

# Restore notifications
settings put secure notification_history_enabled 1 2>/dev/null
settings put secure notification_bubbles 1 2>/dev/null

# Restore spell checker
settings put secure spell_checker_enabled 1 2>/dev/null

# Re-enable print spooler
pm enable com.android.printspooler 2>/dev/null

# Restore device_config namespaces
cmd device_config delete activity_manager max_cached_processes 2>/dev/null
cmd device_config delete activity_manager max_phantom_processes 2>/dev/null
cmd device_config delete activity_manager use_compaction 2>/dev/null
cmd device_config delete activity_manager use_freezer 2>/dev/null
cmd device_config delete activity_manager freeze_debounce_timeout 2>/dev/null
cmd device_config delete activity_manager bg_auto_restrict_abusive_apps 2>/dev/null
cmd device_config delete activity_manager bg_current_drain_auto_restrict_abusive_apps_enabled 2>/dev/null
cmd device_config delete activity_manager defer_boot_completed_broadcast 2>/dev/null
cmd device_config delete activity_manager boot_time_temp_allowlist_duration 2>/dev/null
cmd device_config delete activity_manager fg_to_bg_fgs_grace_duration 2>/dev/null
cmd device_config delete activity_manager fgs_start_foreground_timeout 2>/dev/null
cmd device_config delete app_hibernation app_hibernation_enabled 2>/dev/null
cmd device_config delete intelligence_aiai iorap_ml 2>/dev/null
cmd device_config delete smart_actions smart_actions 2>/dev/null
cmd device_config delete jobscheduler enable_api_quotas 2>/dev/null
cmd device_config delete systemui notification_coalescing_enabled 2>/dev/null
cmd device_config delete systemui notification_snooze_enabled 2>/dev/null
cmd device_config delete systemui nas_generate_replies 2>/dev/null
cmd device_config delete systemui nas_generate_actions 2>/dev/null
cmd device_config delete gms device_doze 2>/dev/null
cmd device_config delete gms analytics_collection_deactivated 2>/dev/null
cmd device_config delete gms checkin_interval 2>/dev/null
cmd device_config delete content_capture content_capture_enabled 2>/dev/null
cmd device_config delete textclassifier textclassifier_enabled 2>/dev/null
cmd device_config delete statsd perfetto_bg_tracing_enabled 2>/dev/null
cmd device_config delete launcher enable_app_prediction 2>/dev/null
cmd device_config delete launcher enable_widget_prediction 2>/dev/null
cmd device_config delete launcher widget_min_update_period 2>/dev/null
cmd device_config delete notification_assistant generate_replies 2>/dev/null
cmd device_config delete notification_assistant generate_actions 2>/dev/null
cmd device_config delete storage media_scanner_enabled 2>/dev/null

# Data Saver is a user-owned global setting. Do not force it on or off during
# uninstall; the user can change it from Android Settings.
_log "Data Saver left unchanged; user/OEM control preserved"

# Restore activity logging
settings put global activity_starts_logging_enabled 1 2>/dev/null

# Restore from snapshot
_snap="$VB_SNAP_DIR/snap_global_latest.txt"
if [ -f "$_snap" ]; then
    while IFS='=' read -r _k _v; do
        [ -z "$_k" ] && continue
        settings put global "$_k" "$_v" 2>/dev/null
    done < "$_snap"
    _log "Snapshot restored"
fi

_log "Uninstall complete — all settings restored"
