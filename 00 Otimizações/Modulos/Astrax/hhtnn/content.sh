#!/system/bin/sh
ASTRAX_DIR_TK="/storage/emulated/0/.astrax"
TK_ACTIVE_SCRIPT="$ASTRAX_DIR_TK/tk_active.sh"
tk_active=$(settings get global astrax_trace_killer_active)
if [ "$tk_active" = "1" ] && [ -f "$TK_ACTIVE_SCRIPT" ]; then
    sh "$TK_ACTIVE_SCRIPT"
fi

apply_on_boot=$(settings get global astrax_apply_on_boot)

if [ "$apply_on_boot" = "true" ]; then

status=$(settings get global astraxframepacingactive)

if [ "$status" = "1" ]; then
    refresh_rate=$(dumpsys display 2>/dev/null | grep -oE 'fps=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | sort -nu | tail -n1 | awk '{printf("%.0f\n",$1)}')
[ -z "$refresh_rate" ] && refresh_rate=60
[ "$refresh_rate" -lt 30 ] && refresh_rate=60
frame_ns=$((1000000000 / refresh_rate))
app_duration=$((frame_ns * 75 / 100))
sf_duration=$((frame_ns * 75 / 100))
setprop debug.sf.early.app.duration "$app_duration"
setprop debug.sf.earlyGl.app.duration "$app_duration"
setprop debug.sf.late.app.duration "$app_duration"
setprop debug.sf.early.sf.duration "$sf_duration"
setprop debug.sf.earlyGl.sf.duration "$sf_duration"
setprop debug.sf.late.sf.duration "$sf_duration"
setprop debug.sf.use_phase_offsets_as_durations 1
setprop debug.sf.enable_gl_backpressure 1
setprop debug.sf.latch_unsignaled 1
setprop debug.sf.enable_hwc_vds 0
cmd display set-match-content-frame-rate-pref 0
settings put --user 0 secure match_content_frame_rate 0

else
    :
fi

status=$(settings get global astraxframepacingactive)

if [ "$status" = "2" ]; then
    refresh_rate=$(dumpsys display 2>/dev/null | grep -oE 'fps=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | sort -nu | tail -n1 | awk '{printf("%.0f\n",$1)}')
[ -z "$refresh_rate" ] && refresh_rate=60
[ "$refresh_rate" -lt 30 ] && refresh_rate=60
frame_ns=$((1000000000 / refresh_rate))
app_duration=$((frame_ns * 85 / 100))
sf_duration=$((frame_ns * 85 / 100))
setprop debug.sf.early.app.duration "$app_duration"
setprop debug.sf.earlyGl.app.duration "$app_duration"
setprop debug.sf.late.app.duration "$app_duration"
setprop debug.sf.early.sf.duration "$sf_duration"
setprop debug.sf.earlyGl.sf.duration "$sf_duration"
setprop debug.sf.late.sf.duration "$sf_duration"
setprop debug.sf.use_phase_offsets_as_durations 1
setprop debug.sf.enable_gl_backpressure 1
setprop debug.sf.latch_unsignaled 1
setprop debug.sf.enable_hwc_vds 0
cmd display set-match-content-frame-rate-pref 1
settings put --user 0 secure match_content_frame_rate 1

else
    :
fi

status=$(settings get global astraxframepacingactive)

if [ "$status" = "3" ]; then
    refresh_rate=$(dumpsys display 2>/dev/null | grep -oE 'fps=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | sort -nu | tail -n1 | awk '{printf("%.0f\n",$1)}')
[ -z "$refresh_rate" ] && refresh_rate=60
[ "$refresh_rate" -lt 30 ] && refresh_rate=60
frame_ns=$((1000000000 / refresh_rate))
app_duration=$((frame_ns * 98 / 100))
sf_duration=$((frame_ns * 98 / 100))
setprop debug.sf.early.app.duration "$app_duration"
setprop debug.sf.earlyGl.app.duration "$app_duration"
setprop debug.sf.late.app.duration "$app_duration"
setprop debug.sf.early.sf.duration "$sf_duration"
setprop debug.sf.earlyGl.sf.duration "$sf_duration"
setprop debug.sf.late.sf.duration "$sf_duration"
setprop debug.sf.use_phase_offsets_as_durations 1
setprop debug.sf.enable_gl_backpressure 1
setprop debug.sf.latch_unsignaled 1
setprop debug.sf.enable_hwc_vds 0
cmd display set-match-content-frame-rate-pref 2
settings put --user 0 secure match_content_frame_rate 2

else
    :
fi

status=$(settings get global astraxprofilemode)

if [ "$status" = "2" ]; then
settings put global game_driver_all_apps 0
settings put global updatable_driver_all_apps 0
settings put global app_standby_enabled 1
settings put global low_power 1
cmd power set-fixed-performance-mode-enabled false
cmd power set-adaptive-power-saver-enabled true
cmd power set-mode 1
settings put global power_save_mode 1
settings put global adaptive_battery_management_enabled 1
dumpsys deviceidle enable all
settings put global app_standby_constants "strong_usage_duration=7200000,notification_seen_duration=86400000,system_interaction_duration=300000,prediction_timeout=43200000"
settings put global battery_saver_constants "advertise_is_enabled=true,enable_datasaver=false,enable_night_mode=true,disable_launch_boost=false,disable_vibration=false,disable_animation=false,disable_soundtrigger=true,defer_full_backup=true,defer_keyvalue_backup=true,enable_firewall=true,location_mode=2,enable_brightness_adjustment=false,force_all_apps_standby=true,force_background_check=true,disable_optional_sensors=true,disable_aod=true,enable_quick_doze=true"
settings put global device_idle_constants "inactive_to=600000,sensing_to=0,locating_to=0,idle_after_inactive_to=1800000,idle_to=10800000,quick_doze_delay_to=60000,light_after_inactive_to=180000,wait_for_unlock=true"
settings put global job_scheduler_constants "max_job_count_active=80,bg_normal_job_count=6,bg_moderate_job_count=12,bg_low_job_count=20,min_ready_jobs_count=2"
cmd thermalservice override-status 2
logcat -G 64k
cmd activity memory-factor set 2
cmd device_config put activity_manager low_swap_threshold_percent 0.4

else
    :
fi

status=$(settings get global astraxprofilemode)

if [ "$status" = "3" ]; then
settings put global game_driver_all_apps 1
settings put global updatable_driver_all_apps 1
settings put global app_standby_enabled 1
settings put global low_power 0
cmd power set-fixed-performance-mode-enabled false
cmd power set-adaptive-power-saver-enabled true
cmd power set-mode 0
settings put global power_save_mode 0
settings put global adaptive_battery_management_enabled 1
dumpsys deviceidle enable all
settings put global app_standby_constants "strong_usage_duration=14400000,notification_seen_duration=172800000,system_interaction_duration=600000,prediction_timeout=86400000"
settings put global battery_saver_constants "advertise_is_enabled=true,enable_datasaver=false,enable_night_mode=false,disable_launch_boost=false,disable_vibration=false,disable_animation=false,disable_soundtrigger=true,defer_full_backup=true,defer_keyvalue_backup=true,enable_firewall=false,location_mode=3,enable_brightness_adjustment=false,force_all_apps_standby=false,force_background_check=false,disable_optional_sensors=false,disable_aod=false,enable_quick_doze=true"
settings put global device_idle_constants "inactive_to=3600000,sensing_to=0,locating_to=0,idle_after_inactive_to=3600000,idle_to=14400000,quick_doze_delay_to=180000,light_after_inactive_to=600000,wait_for_unlock=true"
settings put global job_scheduler_constants "max_job_count_active=150,bg_normal_job_count=8,bg_moderate_job_count=16,bg_low_job_count=30,min_ready_jobs_count=4"
cmd thermalservice override-status 1
logcat -G 1m
cmd activity memory-factor set 1
cmd device_config put activity_manager low_swap_threshold_percent 0.6

else
    :
fi


status=$(settings get global astraxprofilemode)

if [ "$status" = "4" ]; then
settings put global game_driver_all_apps 1
settings put global updatable_driver_all_apps 1
settings put global app_standby_enabled 0
settings put global low_power 0
cmd power set-fixed-performance-mode-enabled true
cmd power set-adaptive-power-saver-enabled false
cmd power set-mode 0
settings put global power_save_mode 0
settings put global adaptive_battery_management_enabled 0
dumpsys deviceidle disable all
settings put global app_standby_constants "strong_usage_duration=43200000,notification_seen_duration=1209600000,system_interaction_duration=900000,prediction_timeout=172800000"
settings put global battery_saver_constants "advertise_is_enabled=false,enable_datasaver=false,enable_night_mode=false,disable_launch_boost=false,disable_vibration=false,disable_animation=false,disable_soundtrigger=false,defer_full_backup=false,defer_keyvalue_backup=false,enable_firewall=false,location_mode=0,enable_brightness_adjustment=false,adjust_brightness_factor=1.0,force_all_apps_standby=false,force_background_check=false,disable_optional_sensors=false,disable_aod=false,enable_quick_doze=false"
settings put global device_idle_constants "inactive_to=14400000,sensing_to=0,locating_to=0,idle_after_inactive_to=0,idle_to=172800000,quick_doze_delay_to=600000,light_after_inactive_to=600000,wait_for_unlock=false"
settings put global job_scheduler_constants "max_job_count_active=300,bg_normal_job_count=16,bg_moderate_job_count=32,bg_low_job_count=60,min_ready_jobs_count=8"
cmd thermalservice override-status 0
logcat -G 8m
cmd activity memory-factor set 0
cmd device_config put activity_manager low_swap_threshold_percent 0.8

else
    :
fi

status=$(settings get global astraxrenderer)

if [ "$status" = "1" ]; then
setprop debug.hwui.renderer opengl
setprop debug.renderengine.capture_skia_ms 0
setprop debug.renderengine.skia_atrace_enabled false
setprop debug.renderengine.skia_tracing_enabled false
setprop debug.renderengine.skia_use_perfetto_track_events false
setprop debug.hwui.skia_use_perfetto_track_events false
setprop debug.hwui.skia_tracing_enabled false
setprop debug.tracing.ctl.hwui.skia_tracing_enabled false
setprop debug.tracing.ctl.hwui.skia_use_perfetto_track_events false
setprop debug.tracing.ctl.renderengine.skia_tracing_enabled false
setprop debug.tracing.ctl.renderengine.skia_use_perfetto_track_events false  
setprop debug.renderengine.backend gles

else
    :
fi

status=$(settings get global astraxrenderer)

if [ "$status" = "2" ]; then
setprop debug.hwui.renderer skiagl
setprop debug.renderengine.capture_skia_ms 0
setprop debug.renderengine.skia_atrace_enabled false
setprop debug.renderengine.skia_tracing_enabled false
setprop debug.renderengine.skia_use_perfetto_track_events false
setprop debug.hwui.skia_use_perfetto_track_events false
setprop debug.hwui.skia_tracing_enabled false
setprop debug.tracing.ctl.hwui.skia_tracing_enabled false
setprop debug.tracing.ctl.hwui.skia_use_perfetto_track_events false
setprop debug.tracing.ctl.renderengine.skia_tracing_enabled false
setprop debug.tracing.ctl.renderengine.skia_use_perfetto_track_events false  
setprop debug.renderengine.backend skiaglthreaded

else
    :
fi

status=$(settings get global astraxrenderer)

if [ "$status" = "3" ]; then
setprop debug.hwui.renderer skiavk
setprop debug.renderengine.capture_skia_ms 0
setprop debug.renderengine.skia_atrace_enabled false
setprop debug.renderengine.skia_tracing_enabled false
setprop debug.renderengine.skia_use_perfetto_track_events false
setprop debug.hwui.skia_use_perfetto_track_events false
setprop debug.hwui.skia_tracing_enabled false
setprop debug.tracing.ctl.hwui.skia_tracing_enabled false
setprop debug.tracing.ctl.hwui.skia_use_perfetto_track_events false
setprop debug.tracing.ctl.renderengine.skia_tracing_enabled false
setprop debug.tracing.ctl.renderengine.skia_use_perfetto_track_events false  
setprop debug.renderengine.backend skiavkthreaded

else
    :
fi

p=$(settings get global astraxframepacingactive)
m=$(settings get global astraxprofilemode)
r=$(settings get global astraxrenderer)

if [ "$p" != "null" ] && [ "$m" != "null" ] && [ "$r" != "null" ]; then
    msg="Astrax Service:
     Full system configuration has been applied."
elif [ "$p" != "null" ] || [ "$m" != "null" ] || [ "$r" != "null" ]; then
    msg="Astrax Service:
     Partial system configuration has been applied."
else
    msg="Astrax Service:
     Active. No modifications selected."
fi

cmd notification post -S bigtext -t "ᯓAstrax" "★" "$msg"

usap_level=$(settings get global astrax_usap_pool_level)
if [ "$usap_level" != "null" ] && [ -n "$usap_level" ]; then
    case "$usap_level" in
        0) usap_min=1; usap_max=3; usap_delay=3000 ;;   
        1) usap_min=2; usap_max=4; usap_delay=1000 ;;   
        2) usap_min=3; usap_max=6; usap_delay=500  ;;   
        3) usap_min=4; usap_max=8; usap_delay=100  ;;   
        *) usap_min="" ;;
    esac
    if [ -n "$usap_min" ]; then
        device_config set_sync_disabled_for_tests persistent
        device_config put runtime_native usap_pool_enabled true
        device_config put runtime_native usap_pool_size_min "$usap_min"
        device_config put runtime_native usap_pool_size_max "$usap_max"
        device_config put runtime_native usap_pool_refill_delay_ms "$usap_delay"
    fi
fi

fi
