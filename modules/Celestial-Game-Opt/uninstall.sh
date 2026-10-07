#!/system/bin/sh
# Don't modify anything after this
touch /data/local/tmp/cgo_reset.flag

RESET_SCRIPT="/data/local/tmp/.cgo_reset_$$.sh"
cat > "$RESET_SCRIPT" <<'EOF'
sync
for b in $(seq 4 14); do service call sensor_privacy $b i32 0; done
cmd power set-mode 0
settings list system | grep -q game_do_not_disturb && settings put system game_do_not_disturb 0
settings list system | grep -q game_scene_more_fps && settings put system game_scene_more_fps 0
settings list system | grep -q gamecube_background_call_state && settings put system gamecube_background_call_state 0
settings list system | grep -q gamecube_block_notification_on && settings put system gamecube_block_notification_on 0
settings list system | grep -q gamecube_block_notification_state && settings put system gamecube_block_notification_state 0
settings list system | grep -q gamecube_competition_mode_state && settings put system gamecube_competition_mode_state 0
settings list system | grep -q gamecube_competition_system_state && settings put system gamecube_competition_system_state 0
settings list system | grep -q call_feedback && settings put system call_feedback 1
settings list system | grep -q call_feedback && settings put system call_log 1
settings put global cached_apps_freezer 0
settings put global low_power 0
settings put global low_power_sticky 0
settings put global app_standby_enabled 1
settings put global window_animation_scale 1.0
settings put global transition_animation_scale 1.0
settings put global animator_duration_scale 1.0
settings put secure long_press_timeout 300
settings put secure multi_press_timeout 300
settings put global private_dns_specifier ""
settings put global private_dns_mode off
settings put global activity_starts_logging_enabled 1
settings put global activity_manager_constants 0
sfdo force-client-composition disabled
cmd devicestoragemonitor reset
settings put global job_scheduler_constants 0
settings put global job_scheduler_time_controller_constants 0
settings put global job_scheduler_quota_controller_constants max_job_count_per_rate_limiting_window=10,rate_limiting_window_ms=60000,max_job_count_active=75,max_session_count_active=75
for rate in peak min; do settings put system ${rate}_refresh_rate 60; done
settings list secure | grep -q user_refresh_rate && settings put secure user_refresh_rate 60
getprop ro.tranos.version && settings put system tran_refresh_mode 10000
settings list secure | grep -q miui_refresh_rate && settings put secure miui_refresh_rate 60
for prop in settings_enable_monitor_phantom_procs fstrim_mandatory_interval kernel_cpu_thread_reader; do settings delete global $prop; done
for e in $(cmd device_config list | cut -f1 -d=); do
  cmd device_config delete "${e%/*}" "${e#*/}" &
  cmd device_config clear_override "${e%/*}" "${e#*/}" &
done
NET_LIST="netpolicy_override_enabled netpolicy_quota_enabled netpolicy_quota_frac_jobs netpolicy_quota_frac_multipath netpolicy_quota_limited netpolicy_quota_unlimited netstats_augment_enabled netstats_combine_subtype_enabled netstats_dev_bucket_duration netstats_dev_delete_age netstats_dev_persist_bytes netstats_dev_rotate_age netstats_enabled netstats_global_alert_bytes netstats_poll_interval netstats_sample_enabled netstats_time_cache_max_age netstats_uid_bucket_duration netstats_uid_delete_age netstats_uid_persist_bytes netstats_uid_rotate_age netstats_uid_tag_bucket_duration netstats_uid_tag_delete_age netstats_uid_tag_persist_bytes netstats_uid_tag_rotate_age network_avoid_bad_wifi network_default_daily_multipath_quota_bytes network_location_opt_in network_metered_multipath_preference network_preference network_recommendations_enabled network_recommendations_package network_scorer_app network_scoring_provisioned network_scoring_ui_enabled network_switch_notification_daily_limit network_switch_notification_rate_limit_millis network_watchlist_enabled network_watchlist_last_report_time"
for net in $NET_LIST; do settings delete global $net; done
cmd binder_calls_stats --reset
cmd looper_stats reset
cmd window tracing size 0
cmd autofill reset
dumpsys procstats --reset
cmd display set-user-disabled-hdr-types
cmd display set-match-content-frame-rate-pref 0
cmd thermalservice reset
cmd ufw settings set-preload-disable all false
cmd ufw settings set-mem-reclaim-args 0 0
for app in $(dumpsys game 2>/dev/null | grep -oE 'Name:[a-zA-Z0-9._]+' | sed 's/Name://'); do
    cmd game reset "$app"
    cmd device_config delete game_overlay "$app"
done
for a in $(cmd package list packages -a | grep "gms" | grep -v "revanced" | cut -d: -f2); do
    dumpsys deviceidle whitelist +"$a"
    cmd activity set-inactive --user 0 "$a" false
    cmd activity compat reset-all "$a"
    cmd activity set-standby-bucket --user 0 "$a" active
    cmd app_hibernation set-state "$a" false
    cmd activity set-bg-restriction-level --user 0 "$a" unrestricted
    cmd tare set-vip 0 "$a" false
    cmd activity set-foreground-service-delegate --user 0 "$a" start
    cmd activity unfreeze --sticky "$(pidof $a)"
    cmd jobscheduler cancel "$a"
done
for uid in $(pm list packages -U | grep "gms" | grep -v "revanced" | sed 's/.*uid://' | tr -d ' '); do
    cmd netpolicy remove restrict-background-blacklist "$uid"
done
for drv in angle_gl_driver_selection_pkgs angle_gl_driver_selection_values game_driver_opt_in_apps game_driver_opt_out_apps updatable_driver_production_opt_in_apps updatable_driver_production_opt_out_apps; do
    settings delete global $drv
done
EOF

nice -n 19 ionice -c3 setsid sh "$RESET_SCRIPT" >/dev/null 2>&1 &
RESET_PID=$!
wait "$RESET_PID"

rm -f "$RESET_SCRIPT"
rm -f /data/local/tmp/kazuyoo_*
rm -f /data/local/tmp/.kazuyoo_*
rm -f /data/local/tmp/gamelist.txt
rm -f /data/local/tmp/svc_server*
rm -f /data/local/tmp/rc_server*
[ -n "$AXERONXBIN" ] && rm -f "$AXERONXBIN"/kazuyoo*
[ -n "$AXERONXBIN" ] && rm -f "$AXERONXBIN"/cgo_engine*
[ -n "$AXERONXBIN" ] && rm -f "$AXERONXBIN"/RC*
pkill -9 -f cgo_engine
pkill -9 -f kazuyoo
pkill -9 -f RC
