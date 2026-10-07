#!/system/bin/sh
# ═══════════════════════════════════════════════════════════════
# VOID BATTERY v9.1-fix — Hybrid Adaptive Battery Engine
# No-Root / ADB Safe — 106 Smart Functions | Brightness Fix
# Fully Android mksh/toybox compatible
#
# ARCHITECTURE:
#   1. Source helpers.sh ONCE (all utility functions available)
#   2. Cache battery state from ONE dumpsys call
#   3. Source function files DIRECTLY in current shell (no subshells!)
#   4. All function stdout/stderr → log file
#   5. Only progress messages → AXManager screen (stdout)
# ═══════════════════════════════════════════════════════════════

MODPATH="${MODPATH:-${0%/*}}"

# ─── Source helpers ONCE ──────────────────────────────────────
. "$MODPATH/helpers.sh"

# ─── Create directories ──────────────────────────────────────
mkdir -p "$VB_LOG_DIR" "$VB_SNAP_DIR" "$VB_REPORT_DIR" 2>/dev/null

# ─── Load config ─────────────────────────────────────────────
[ -f "$MODPATH/config/voidbattery.conf" ] && . "$MODPATH/config/voidbattery.conf"
VB_LOW="${VB_LOW:-20}"
VB_HIGH="${VB_HIGH:-80}"
VB_CRIT="${VB_CRIT:-10}"
VB_PUSH_PROTECT="${VB_PUSH_PROTECT:-true}"
VB_DATA_SAVER="${VB_DATA_SAVER:-manual}"
VB_MANAGE_DATA_SAVER="${VB_MANAGE_DATA_SAVER:-false}"
VB_MANAGE_DOZE="${VB_MANAGE_DOZE:-false}"
VB_MANAGE_STANDBY="${VB_MANAGE_STANDBY:-false}"
VB_MANAGE_BACKGROUND_DATA="${VB_MANAGE_BACKGROUND_DATA:-false}"
VB_MANAGE_GMS="${VB_MANAGE_GMS:-false}"
VB_ALLOW_AGGRESSIVE_CRITICAL="${VB_ALLOW_AGGRESSIVE_CRITICAL:-false}"
VB_SKIP_WHEN_SCREEN_OFF="${VB_SKIP_WHEN_SCREEN_OFF:-true}"
VB_BLOAT="${VB_BLOAT:-0}"
VB_DRY_RUN="${VB_DRY_RUN:-0}"

# ─── Load app lists ──────────────────────────────────────────
VB_EXCLUDED=$(vb_load_list "$MODPATH/config/excluded_apps.txt")
VB_PUSH_APPS=$(vb_load_list "$MODPATH/config/push_critical_apps.txt")
VB_SOCIAL=$(vb_load_list "$MODPATH/config/social_apps.txt")
VB_MODERATE=$(vb_load_list "$MODPATH/config/moderate_apps.txt")
VB_EXTREME=$(vb_load_list "$MODPATH/config/extreme_apps.txt")

# ─── Cache battery state (ONE dumpsys call!) ──────────────────
_bat=$(dumpsys battery 2>/dev/null)
VB_LEVEL=$(echo "$_bat" | grep 'level:' | sed 's/[^0-9]//g' | head -1)
VB_LEVEL=${VB_LEVEL:-50}
_raw_temp=$(echo "$_bat" | grep 'temperature:' | sed 's/[^0-9]//g' | head -1)
VB_TEMP=$(( ${_raw_temp:-300} / 10 ))
_bat_status=$(echo "$_bat" | grep 'status:' | sed 's/[^0-9]//g' | head -1)
VB_CHARGING=0
[ "$_bat_status" = "2" ] || [ "$_bat_status" = "5" ] && VB_CHARGING=1
VB_VOLTAGE=$(echo "$_bat" | grep 'voltage:' | sed 's/[^0-9]//g' | head -1)
VB_HEALTH=$(echo "$_bat" | grep 'health:' | sed 's/[^0-9]//g' | head -1)
unset _bat _raw_temp _bat_status

# ─── Screen state (ONE dumpsys call) ─────────────────────────
VB_SCREEN=0
dumpsys power 2>/dev/null | grep -qE 'mWakefulness=Awake|Display Power: state=ON' && VB_SCREEN=1

# ─── Detect profile ──────────────────────────────────────────
if [ "$VB_CHARGING" = "1" ] && [ "$VB_LEVEL" -ge "$VB_HIGH" ]; then
    VB_PROFILE="PERFORMANCE"
elif [ "$VB_LEVEL" -le "$VB_CRIT" ]; then
    VB_PROFILE="CRITICAL"
elif [ "$VB_LEVEL" -le "$VB_LOW" ]; then
    VB_PROFILE="POWERSAVE"
elif [ "$VB_LEVEL" -le 40 ]; then
    VB_PROFILE="ECO"
elif [ "$VB_SCREEN" = "0" ] && [ "$VB_CHARGING" = "0" ]; then
    VB_PROFILE="IDLE"
else
    VB_PROFILE="BALANCED"
fi

# ─── Function Runner ─────────────────────────────────────────
# Sources function file DIRECTLY in current shell.
# No subshell = no fork overhead = no re-sourcing helpers.
# All stdout/stderr from the function → log file.
# Safe because functions use 'return', not 'exit'.
_vb_run() {
    _fn="$MODPATH/functions/${1}.sh"
    [ ! -f "$_fn" ] && return 0
    . "$_fn" >> "$VB_LOG" 2>&1
    return 0
}

# ─── MAIN ─────────────────────────────────────────────────────
_cmd="${1:-run}"

echo "═══════════════════════════════════════"
echo " VOID BATTERY v9.1-fix"
echo " Battery: ${VB_LEVEL}% | ${VB_TEMP}C"
echo " Profile: $VB_PROFILE"
echo " Mode: $_cmd"
echo "═══════════════════════════════════════"

vb_log "ENGINE" "=== Cycle Start | $_cmd | $VB_PROFILE | ${VB_LEVEL}% | ${VB_TEMP}C ==="

case "$_cmd" in
# ─── CORE (every 5 min) ──────────────────────────────────────
run)
    echo " [1/9] Safety & Doze..."
    _vb_run 01_safety_rollback
    _vb_run 02_doze_master
    _vb_run 03_smart_freezer

    echo " [2/9] App management..."
    _vb_run 04_app_standby_master
    _vb_run 05_gms_optimizer
    _vb_run 10_appops_background
    _vb_run 11_background_lite
    _vb_run 12_doze_whitelist_clean
    _vb_run 71_unused_app_hibernation
    _vb_run 77_app_drain_detector

    echo " [3/9] Network..."
    _vb_run 06_network_optimizer
    _vb_run 13_push_coalesce
    _vb_run 14_bluetooth_scan_throttle
    _vb_run 34_wifi_power_save
    _vb_run 40_smart_network_switch
    _vb_run 47_cellular_standby_optimize
    _vb_run 49_network_traffic_throttle
    _vb_run 52_nearby_scanning_off
    _vb_run 103_adaptive_connectivity
    _vb_run 109_background_data_restrict

    echo " [4/9] Display & UI..."
    _vb_run 07_display_optimizer
    _vb_run 21_adaptive_brightness
    _vb_run 45_screen_brightness_cap
    _vb_run 46_vibration_intensity
    _vb_run 48_window_animation_tune
    _vb_run 53_window_blur_off
    _vb_run 55_ambient_display_control
    _vb_run 56_wake_gesture_control
    _vb_run 65_display_power_manage
    _vb_run 24_charger_animation_off
    _vb_run 72_screen_timeout_adaptive

    echo " [5/9] Battery saver..."
    _vb_run 08_battery_saver_smart
    _vb_run 09_data_saver_mode
    _vb_run 23_battery_saver_policy
    _vb_run 22_adaptive_charging
    _vb_run 42_anomaly_detector
    _vb_run 66_smart_charging_protect
    _vb_run 70_emergency_ultra_save
    _vb_run 110_thermal_monitor

    echo " [6/9] System tuning..."
    _vb_run 15_sync_throttle
    _vb_run 16_wakelock_guard
    _vb_run 17_phantom_process_killer
    _vb_run 18_app_hibernation
    _vb_run 19_nnapi_offload_limit
    _vb_run 20_logcat_ringbuffer
    _vb_run 25_notification_batch
    _vb_run 27_job_scheduler_throttle
    _vb_run 28_broadcast_throttle
    _vb_run 29_backup_defer
    _vb_run 32_activity_manager_tune
    _vb_run 33_restrict_auto_update
    _vb_run 35_process_limit_background
    _vb_run 36_system_tracing_off
    _vb_run 37_debug_logging_off
    _vb_run 38_content_observer_throttle
    _vb_run 39_connectivity_power
    _vb_run 41_usage_stats_throttle
    _vb_run 43_sync_adapter_throttle
    _vb_run 44_idle_maintenance_defer
    _vb_run 50_abusive_app_restrict
    _vb_run 54_activity_logging_off
    _vb_run 57_performance_mode_off
    _vb_run 58_alarm_manager_tune
    _vb_run 59_location_accuracy_control
    _vb_run 60_app_compaction_tune
    _vb_run 61_power_hint_optimize
    _vb_run 63_network_policy_optimize
    _vb_run 64_thermal_config_tune
    _vb_run 67_runtime_optimization

    echo " [7/9] Smart services..."
    _vb_run 73_text_classifier_off
    _vb_run 74_smart_reply_off
    _vb_run 75_device_idle_light_tune
    _vb_run 76_memory_compaction_tune
    _vb_run 78_clipboard_cleanup
    _vb_run 79_print_spooler_disable
    _vb_run 95_account_sync_optimize
    _vb_run 96_notification_history_off
    _vb_run 97_app_prediction_off
    _vb_run 98_intent_filter_throttle
    _vb_run 99_media_scanner_throttle
    _vb_run 101_widget_refresh_throttle
    _vb_run 102_spell_checker_off
    _vb_run 105_motion_sensor_off
    _vb_run 106_battery_stats_reset
    _vb_run 107_usb_power_optimize
    _vb_run 108_google_services_restrict

    echo " [8/9] Per-app & vendor..."
    _vb_run 30_gps_background_limit
    _vb_run 31_camera_mic_background
    _vb_run 51_app_idle_enforce
    _vb_run 62_sensor_background_restrict
    _vb_run 26_samsung_gos_opt
    _vb_run 68_xiaomi_optimize
    _vb_run 69_oneplus_optimize
    _vb_run 111_location_power_optimize

    echo " [9/9] Cache & cleanup..."
    _vb_run 104_smart_cache_manager

    echo ""
    echo " Done! ${VB_LEVEL}% | $VB_PROFILE"
    echo "═══════════════════════════════════════"
    ;;

# ─── HEAVY (every 30 min) ────────────────────────────────────
heavy)
    echo " Running heavy tasks..."
    _vb_run 80_bloat_action
    _vb_run 81_fstrim_cron
    _vb_run 82_storage_cleanup
    _vb_run 83_media_session_cleanup
    _vb_run 84_overlay_cleanup
    _vb_run 85_notification_listener_audit
    _vb_run 86_multicast_lock_release
    _vb_run 87_package_manager_optimize
    _vb_run 88_dex_background_compile
    _vb_run 89_foreground_service_audit
    echo " Heavy tasks done!"
    ;;

# ─── REPORT (every 60 min) ───────────────────────────────────
report)
    echo " Generating reports..."
    _vb_run 90_battery_health_report
    _vb_run 91_discharge_logger
    _vb_run 92_wakelock_detective
    _vb_run 93_session_report
    _vb_run 94_battery_usage_report
    _vb_run 100_accessibility_audit
    echo " Reports saved to /sdcard/VOID_BATTERY/reports/"
    ;;

# ─── ALL ──────────────────────────────────────────────────────
all)
    sh "$MODPATH/action.sh" run
    sh "$MODPATH/action.sh" heavy
    sh "$MODPATH/action.sh" report
    ;;

# ─── STATUS ──────────────────────────────────────────────────
status)
    _fc=0
    for _f in "$MODPATH"/functions/*.sh; do [ -f "$_f" ] && _fc=$((_fc+1)); done
    echo " Functions: $_fc"
    echo " Log: $VB_LOG"
    ;;

*)
    echo "Usage: action.sh {run|heavy|report|all|status}"
    ;;
esac

vb_log "ENGINE" "=== Cycle Done | $_cmd ==="
