# Don't modify anything after this
[[ -f "$INFO" ]] && {
  while read LINE; do
    if [[ "$(echo -n "$LINE" | tail -c 1)" == "~" ]]; then
      continue
    elif [[ -f "$LINE~" ]]; then
      mv -f "$LINE~" "$LINE"
    else
      rm -f "$LINE"
      while true; do
        LINE=$(dirname $LINE)
        [[ "$(ls -A $LINE 2>/dev/null)" ]] && break 1 || rm -rf "$LINE"
      done
    fi
  done < $INFO
  rm -f "$INFO"
}


echo ""
echo "█▓▒▒░░░NOVA TOUCH v1.0░░░▒▒▓█"
echo ""
sleep 0.5
# Simpan tanggal instalasi
date '+%Y-%m-%d %H:%M:%S' > /data/local/tmp/touch_tweak_install_date

INSTALL_DATE=$(cat /data/local/tmp/touch_tweak_install_date 2>/dev/null || echo "Unknown")

echo "┌────────────────────────────────────────────┐"
echo "│         DEVICE AND HARDWARE INFO           │"
echo "├────────────────────────────────────────────┤"
echo "│ 📱 Device   : $(getprop ro.product.manufacturer) $(getprop ro.product.model) │"
echo "│ ⚙️ CPU      : $(getprop ro.board.platform) │"
echo "│ 🎮 GPU      : $(getprop ro.hardware) │"
echo "│ 📲 Android  : $(getprop ro.build.version.release) │"
echo "│ 📅 Uninstall  : $INSTALL_DATE │"
echo "│ 🔰 Kernel   : $(uname -r) │"
echo "│ 🔹 Build    : $(getprop ro.build.display.id) │"
echo "│ 🛑 Root     : $(if [ $(id -u) -eq 0 ]; then echo 'Yes'; else echo 'No'; fi) │"
echo "│ 🔗 SELinux  : $(getenforce) │"
echo "└────────────────────────────────────────────┘"
echo ""
echo "█▓▒▒░░░WELCOME TO UNINSTALL░░░▒▒▓█"
echo ""
sleep 0.5
echo ""
echo "
███████╗░█████╗░░██████╗████████╗
██╔════╝██╔══██╗██╔════╝╚══██╔══╝
█████╗░░███████║╚█████╗░░░░██║░░░
██╔══╝░░██╔══██║░╚═══██╗░░░██║░░░
██║░░░░░██║░░██║██████╔╝░░░██║░░░
╚═╝░░░░░╚═╝░░╚═╝╚═════╝░░░░╚═╝░░░"
sleep 0.5
echo ""
echo "
████████╗░█████╗░██╗░░░██╗░█████╗░██╗░░██╗
╚══██╔══╝██╔══██╗██║░░░██║██╔══██╗██║░░██║
░░░██║░░░██║░░██║██║░░░██║██║░░╚═╝███████║
░░░██║░░░██║░░██║██║░░░██║██║░░██╗██╔══██║
░░░██║░░░╚█████╔╝╚██████╔╝╚█████╔╝██║░░██║
░░░╚═╝░░░░╚════╝░░╚═════╝░░╚════╝░╚═╝░░╚═╝"
sleep 0.5
echo ""
echo "
██╗░░░██╗██╗░░░██╗██╗██████╗░
██║░░░██║██║░░░██║██║██╔══██╗
╚██╗░██╔╝╚██╗░██╔╝██║██████╔╝
░╚████╔╝░░╚████╔╝░██║██╔═══╝░
░░╚██╔╝░░░░╚██╔╝░░██║██║░░░░░
░░░╚═╝░░░░░░╚═╝░░░╚═╝╚═╝░░░░░"
sleep 1.0
(
#V1.0
# Render lebih cepat setelah input
setprop debug.hwui.predictive_frame_timing ""
# Touch response stabilization
setprop debug.input.velocitytracker.strategy ""
# Sampling touch lebih tinggi
setprop ro.input.resample ""
setprop ro.surface_flinger.max_frame_buffer_acquired_buffers ""
) > /dev/null 2>&1

(
#V35.0
setprop debug.input.boost ""
setprop debug.input.latency ""
setprop debug.input.touchboost ""
setprop debug.sf.input_boost ""
setprop debug.sf.early_phase_offset_ns ""
setprop debug.sf.early_app_phase_offset_ns ""
setprop debug.input.sampling_rate 240
setprop debug.input.resample ""
setprop debug.input.dispatch_mode ""
setprop debug.input.drop_input ""
) > /dev/null 2>&1

(
#V34.0
setprop debug.touch.filter.tftype4.TouchDeadZone ""
setprop debug.touch.filter.tftype4.TouchSensitivity ""
setprop debug.touch.filter.tftype4.EdgeSensitivity ""
setprop debug.touch.filter.tftype4.CornerTouchOptimization ""
setprop debug.touch.filter.tftype4.MultiTouchEnhance ""
setprop debug.touch.filter.tftype4.MultiTouchArea ""
setprop debug.touch.filter.tftype4.DynamicCalibration ""
setprop debug.touch.filter.tftype4.LatencyBoost ""
setprop debug.touch.filter.tftype4.TouchResponseBoost ""
setprop debug.touch.filter.tftype4.TouchPowerManagement ""
setprop debug.touch.filter.tftype4.HapticFeedbackStrength ""
setprop debug.touch.filter.tftype4.AdaptiveTouchFiltering ""
setprop debug.touch.filter.tftype4.GestureDetection ""
setprop debug.touch.filter.tftype4.TouchNoiseFilter ""
setprop debug.touch.filter.tftype4.TouchThreshold ""
setprop debug.touch.filter.tftype4.FastTouchSpeedThreshold ""
) > /dev/null 2>&1

(
#V33
setprop debug.touch.filter.tftype4.Enabled ""
setprop debug.touch.filter.tftype4.MaxNumTouch ""
setprop debug.touch.filter.tftype4.AssumedDelayFactorA ""
setprop debug.touch.filter.tftype4.AssumedDelayFactorB ""
setprop debug.touch.filter.tftype4.AssumedDelayFactorC ""
setprop debug.touch.filter.tftype4.MaxSpeed ""
setprop debug.touch.filter.tftype4.PStablePositionFactor ""
setprop debug.touch.filter.tftype4.DirectivePriorityFactor ""
setprop debug.touch.filter.tftype4.LatestSpeedWeight ""
setprop debug.touch.filter.tftype4.GapResolver ""
setprop debug.touch.filter.tftype4.OrgSize ""
setprop debug.touch.filter.tftype4.AccSize ""
setprop debug.touch.filter.tftype4.AddInitialAcc ""
setprop debug.touch.filter.tftype4.DefaultInitialAcc ""
setprop debug.touch.filter.tftype4.DragRangeSize ""
setprop debug.touch.filter.tftype4.AccDrag interpolated
setprop debug.touch.filter.tftype4.NoAccDistanceMin ""
setprop debug.touch.filter.tftype4.NoAccDistanceMax ""
setprop debug.touch.filter.tftype4.NoAccRate ""
setprop debug.touch.filter.tftype4.PositionFactorA ""
setprop debug.touch.filter.tftype4.DirectivePriorityFactor ""
setprop debug.touch.filter.tftype4.DragRangeSize ""
setprop debug.touch.filter.tftype4.AccDrag ""
setprop debug.touch.filter.tftype4.NoAccDistanceMax ""
) > /dev/null 2>&1

(
#V32
# Reset touch settings ke default
settings delete global touch.sampling_rate
settings delete global touch.boost
settings delete global touch.delay
settings delete global touch.move_boost
settings delete global touch.responsiveness
settings delete global touch.gesture.smooth
settings delete global touch.latency_mode
# Reset device_config ke default
cmd device_config delete input_native input_boost_enable
cmd device_config delete input_native input_dispatch_fastpath
cmd device_config delete input_native touch_slop_boost
cmd device_config delete window_manager gesture_prediction_enable
) > /dev/null 2>&1

(
#V31
settings delete system touch.pressure.scale 
settings delete system touch.size.scale 
settings delete system touch.response_time 
settings delete system touch.sensitivity 
settings delete system touch.slop 
settings delete system touch.motion.filter 
settings delete system touch.gesture.sensitivity 
settings delete system touch.tap.delay 
settings delete system touch.stats 
setprop debug.sf.set_touch_timer_ms ""
setprop debug.input.dispatch_latency_ms ""
setprop debug.input.sampling_rate ""
setprop debug.egl.swapinterval ""
) > /dev/null 2>&1

#V30
(
settings delete global touch.response_curve 
settings delete global touch.latency_shield 
settings delete global touch.sample_rate 
settings delete system persist.sys.touch_predictive_engine 
settings delete system persist.sys.multi_touch_anticipation 
settings delete system persist.sys.zero_input_delay enabled
settings delete secure game.aim_lock_precision 
settings delete secure game.recoil_balance_stabilizer 
) > /dev/null 2>&1

(
# Reset device_config ke default
cmd device_config delete latency_tracker enabled
cmd device_config delete latency_tracker sampling_interval
cmd device_config delete interaction_jank_monitor enabled
cmd device_config delete interaction_jank_monitor sampling_interval
cmd device_config delete perfetto tracing_enabled
# Reset system property ke default (hapus override)
setprop debug.sf.high_speed_scroll_factor ""
setprop debug.touch.input_boost_enabled ""
setprop debug.touch.boost ""
#V28.0
# Balikin semua ke default / hapus key custom
device_config delete input max_event_latency_ms
device_config delete input dispatcher_low_latency
device_config delete input pointer_prediction_enabled
device_config delete input pointer_velocity_filter_enabled
device_config delete input pointer_resampling_filter_enabled
settings delete secure thermal_safety_mode
device_config delete activity_manager fixed_renew_buf_on_input
device_config delete input input_event_timeout_ms
device_config delete input input_dispatch_resolution_ns
settings delete global vsync_frame_interval
settings delete global vsync_event_phase_offset_ns
settings delete global sf_phase_offset_ns
device_config delete powerhal touch_boost_enabled
device_config delete powerhal launch_boost_enabled
device_config delete input ignore_window_animation_delay
#27.0
### SENSITIVITAS SENTUH DASAR
settings delete secure tap_duration_threshold
settings delete secure touch_blocking_period
### MULTI-TOUCH & SAMPLING
settings delete global multi_sampling_enabled
settings delete global multi_touch_enabled
settings delete global touchSamplingToggle
settings delete global sampling_interval_in_seconds
settings delete global touch_off_enabled
### TOUCH INPUT OPTIMIZATION
device_config delete input_native com.android.hardware.input.touch_resampling_enabled
device_config delete input_native com.android.hardware.input.touch_prediction_enabled
device_config delete input_native com.android.hardware.input.gesture_sampling_interval
device_config delete input_native com.android.hardware.input.event_sample_rate
device_config delete input_native com.android.hardware.input.pointer_resampling_filter_enabled
device_config delete com.android.hardware.input.touch_sampling_rate
### DISPLAY & REFRESH RATE CONTROL
device_config delete display_manager refresh_rate_mode
device_config delete display_manager peak_refresh_rate
device_config delete window_manager enable_high_refresh_rate
device_config delete window_manager max_refresh_rate
device_config delete window_manager min_refresh_rate
### GPU RENDERING & VSYNC
device_config delete gpu_composition force_gpu_rendering
device_config delete gpu_composition disable_hw_vsync
### UI THREAD BOOST
device_config delete aicore AicCommon__ui_thread_priority_boost
### OPSIONAL: AdServices
device_config delete adservices custom_error_code_sampling_enabled
device_config delete adservices measurement_throw_unknown_exception_sampling_rate
#V26.0
# Uninstall / Reset Device Config Overclock Touch & Refresh Rate Settings
device_config delete input native_boost_touch_input
device_config delete input boost_touch_dispatcher
device_config delete input filtered_accel_event_rate_hz
device_config delete input touch_sample_rate_hz
device_config delete input touch_resample_enabled
device_config delete input touch_screen_sample_interval_ms
device_config delete input latency_mode
device_config delete input max_touch_move_duration_ms
device_config delete input tap_duration
device_config delete input input_boost_duration_ms
device_config delete surfaceflinger refresh_rate
device_config delete surfaceflinger max_frame_buffer_acquired_count
device_config delete surfaceflinger frame_rate_multiple_threshold
device_config delete surfaceflinger max_frame_rate
device_config delete surfaceflinger min_frame_rate
device_config delete surfaceflinger peak_frame_rate
device_config delete surfaceflinger enable_refresh_rate_overlay
device_config delete surfaceflinger set_max_frame_rate_multiplier
device_config delete systemui accelerate_refresh_rate
device_config delete systemui min_refresh_rate_for_fps_boost
device_config delete systemui max_refresh_rate_for_fps_boost
device_config delete scheduler boost_display_refresh
device_config delete display dynamic_refresh_rate_enabled
device_config delete display enable_frame_rate_boosting
device_config delete activity_manager force_high_refresh_rate
#V25
setprop debug.perf_event_max_sample_rate ""
setprop debug.touchscreen.latency.scale "" 
setprop debug.tracing.block_touch_buffer ""
setprop debug.dyn_samplingrate "" 
setprop debug.dyn_sample_period ""
setprop debug.sf.luma_sampling ""
setprop debug.sf.layer_smoothness ""
setprop debug.sf.default_touch_timer_ms ""              
setprop debug.sf.set_touch_timer_ms ""
setprop debug.sf.region_sampling_timer_timeout_ns ""
setprop debug.sf.region_sampling_period_ns ""
setprop debug.sf.scroll_boost_refreshrate ""
setprop debug.sf.touch_boost_refreshrate ""
#V23
settings delete global touch.sampling_boost 
setprop debug.touch.sampling_boost ""
settings delete global display_high_refresh_rate 
settings delete global display.use_smooth_motion 
settings delete secure touch_exploration_enabled 
settings delete global power_mode_performance
setprop debug.windows.mgr.max_event_per_sec ""
settings delete global min_pointer_dur 
settings delete global max.fling_velocity 
settings delete global min.fling_velocity 
setprop debug.view.scroll_friction ""
settings delete global block_untrusted_touches 
#V22
settings delete global window_animation_scale
settings delete global transition_animation_scale
settings delete global animator_duration_scale
settings delete secure display_density_forced
settings delete system tap_duration
settings delete system view.scroll_friction
settings delete secure pointer_speed
#V21
settings delete system devices_virtual_input_input1_polling_rate 
settings delete global touch_sampling_rate
settings delete global input.sampling_rate
settings delete system persist.sys.touch.sampling_boost 
settings delete global input.delay 
settings delete global input.resampling 
settings delete global input.gesture_prediction 
settings delete global input.touch_boost
settings delete global min.touch.major 
settings delete global min.touch.minor 
settings delete system touch.boost 
settings delete system touch.responsive 
#V19
settings delete system touch_sampling_rate
settings delete system touch_size_calibration
settings delete system touch_stats
settings delete system touchX_debuggable 
settings delete system touch_boost_threshold 
settings delete system touch_feature_gamemode_enable 
settings delete system touch_input_sensitivity 
settings delete system touch_rate_control 
settings delete system touch_response_rate 
settings delete system touch_sampling_rate_override 
settings delete system touch_sensitivity
settings delete system touch_slop 
settings delete system touch_switch_set_touchscreen
settings delete system touch_tap_sensitivity 
settings delete system touchpanel_game_switch_enable
settings delete global surface_flinger.start_graphics_allocator_service
settings delete global surface_flinger.running_without_sync_framework
setprop debug.sf.luma_sampling ""
setprop debug.sf.disable_client_composition_cache ""
setprop debug.sf.disable_backpressure ""
setprop debug.sf.enable_gl_backpressure ""
setprop debug.sf.enable_layer_caching ""
setprop debug.sf.disable_client_composition_cache ""
setprop debug.sf.enable_gl_backpressure ""
setprop debug.sf.enable_hwc_vds ""
setprop debug.sf.hw ""
setprop debug.sf.predict_hwc_composition_strategy ""
setprop debug.sf.use_phase_offsets_as_durations ""
setprop debug.sf.use_phase_offsets_as_durations ""
setprop debug.sf.late.sf.duration ""
setprop debug.sf.late.app.duration ""
setprop debug.sf.treat_170m_as_sRGB ""
setprop debug.sf.earlyGl.app.duration ""
setprop debug.sf.frame_rate_multiple_threshold ""
setprop debug.boot.fps ""
setprop debug.performance.tuning ""
settings delete system view.scroll_friction
settings delete global windowsmgr.support_low_latency_touch
setprop debug.hwui.render_dirty_regions ""
setprop debug.hwui.disable_vsync ""
settings delete system haptic_feedback_intensity
settings delete global tactile_feedback_enabled
debug.sf.set_touch_timer_ms ""
settings delete global fw.bservice_enable 
settings delete global fw.bg_apps_limit
settings delete global fw.bservice_limit
settings delete global fw.bservice_age 
setprop debug.touch.pressure.scale ""
setprop debug.touch_move_opt ""
setprop debug.touch_vsync_opt ""
# Delete CMD configurations
# Remove input configurations
cmd device_config delete input default_key_press_repeat_rate
cmd device_config delete input filtered_accel_event_rate_hz
cmd device_config delete input touch_screen_sample_interval_ms
# Remove system UI configurations
cmd device_config delete systemui cg_frame_interval_millis
cmd device_config delete systemui low_power_refresh_rate_millis
cmd device_config delete systemui cg_max_frame_skip
# Remove system props
setprop debug.touch.size.bias 
setprop debug.MultitouchSettleInterval 
setprop debug.TapInterval 
setprop debug.TapSlop 
setprop debug.security.mdpp 
setprop debug.security.mdpp.result 
setprop debug.service.lgospd.enable 
setprop debug.service.pcsync.enable 
setprop debug.touch.deviceType 
setprop debug.boosterorientnosync 
setprop debug.performance.tuning 
setprop debug.egl.swapinterval 
# Remove global settings
settings delete global windowsmgr.max_events_per_sec
settings delete global min_pointer_dur
settings delete global product.multi_touch_enabled
settings delete global securestorage.knox
settings delete global sf.disable_smooth_effect
settings delete global block_untrusted_touches
settings delete global KeyRepeatDelay
settings delete global KeyRepeatTimeout
settings delete global window_animation_scale
settings delete global transition_animation_scale
settings delete global animator_duration_scale
settings delete global DragMinSwitchSpeed
settings delete global SwipeMaxWidthRatio
# Remove secure settings
settings delete secure touch_distance_scale
settings delete secure view_scroll_friction
settings delete secure multi_touch_enabled
settings delete secure assist_touch_gesture_enabled
settings delete secure touch_size_scale
settings delete secure show_rotation_suggestions
settings delete secure touch_size_bias
settings delete secure touch_exploration_enabled
settings delete secure touch_orientationAware
settings delete secure touch_pressure_scale
settings delete secure dev.pm.dyn_samplingrate
# Remove system settings
settings delete system af.resampler.quality
settings delete system scrollingcache
settings delete system show_touches
settings delete system vsync.disable.fps.limit
settings delete system table.framerate
settings delete system disable.hwc.delay
settings delete system Touc_xRotation
settings delete system touchswipedeadzone
settings delete system pointer_speed
settings delete system touchscreen_hovering
settings delete system touchscreen_sensitivity_mode
settings delete system touchscreen_pressure_calibration
settings delete system touchscreen_threshold
settings delete system touchfeature.gamemode.enable
settings delete system r.setframepace
settings delete system touch_switch_set_touchscreen
settings delete system touchpanel_game_switch_enable
settings delete system touchpanel_oppo_tp_direction
settings delete system touchpanel_oppo_tp_limit_enable
settings delete system use_dithering
settings delete system qti.inputopts.enable
settings delete system qti.inputopts.movetouchslop
settings delete system MovementSpeedRatio
settings delete system ZoomSpeedRatio
settings delete system SwipeTransitionAngleCosine
settings delete system mot.proximity.distance
settings delete system PointerVelocityControlParameters
settings delete system device.internal
settings delete system touchscreen_min_press_time
settings delete system touchscreen_gesture_mode
settings delete system touchscreen_pointer_speed
settings delete system touchscreen_sensitivity_threshold
settings delete system touchscreen_double_tap_speed
settings delete system touchscreen_sensitivity_scale
settings delete system SurfaceOrientation
settings delete system touch.size.calibration
settings delete system touch.size.scale
settings delete system touch.size.isSummed
settings delete system touch.orientation.calibration
settings delete system touch.distance.scale
settings delete system touch.coverage.calibration
settings delete system touch.pressure.scale
settings delete system touch.gesturemode
settings delete system MultitouchMinDistance
settings delete system scroll.accelerated.hw
settings delete system ui.hwframes
settings delete system force_high_end_gfx
settings delete system max_num_touch
settings delete system view.touch_slop
settings delete system maxeventspersec
settings delete system resampler.quality
settings delete system touch.sampling_rate
settings delete system adaptive_touch_sensitivity
settings delete system PressureForID
settings delete system QuietInterval
settings delete system AIM_SENSITIVITY_TRANSITION_TIME
settings delete system APP_SWITCH_DELAY_TIME
settings delete system AbsoluteXForID
settings delete system AccelerationX
settings delete system AccelerationY
settings delete system DoubleTouch
settings delete system PowerbuttonTapping
settings delete system touch.assistant.enabled
settings delete system type.touch_speed
settings delete system accuracy.control
) > /dev/null 2>&1

echo""
echo "REMOVE TOUCH ADAPTIVE ✅"
echo""
sleep 0.5
echo""
echo "REMOVE SENSITIFITAS GAMING ✅"
sleep 0.5
echo""
echo "REMOVE TOUCH SPEED ✅"
echo""
sleep 0.5
echo""
echo "ALL DELETE DONE✅"
echo""
sleep 0.5
echo""
echo "‼️MENGHAPUS SEMUA TWEAK PERMANENT‼️"
echo""
sleep 0.5
echo""
echo "DEV BENDEV GANTENG"
echo""
sleep 0.5
echo""
echo "THANKS"
echo""
sleep 0.5
echo""
echo "100% BENTROK ALL MODULE TOUCH"
echo""
sleep 0.5
echo""
echo "█▓▒▒░░░THANKS FOR USING MODULE ░░░▒▒▓█"
echo""

cmd notification post -S bigtext -t 'NOVA TOUCH' 'Tag' ' DONE UNINSTALL REMOVE ALL TWEAK' > /dev/null 2>&1