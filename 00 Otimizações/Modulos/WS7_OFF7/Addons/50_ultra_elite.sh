#!/system/bin/sh
# WS7_OFF7 · 50+ ULTRA ELITE ENGINE ADDON
# Master Performance, Thermal, Network & CPU/GPU Subroutine Suite

apply_50_plus() {
    # 1. CPU & Scheduler Overdrive
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
        [ -f "$cpu/scaling_governor" ] && echo "performance" > "$cpu/scaling_governor" 2>/dev/null
        [ -f "$cpu/schedutil/down_rate_limit_us" ] && echo 1000 > "$cpu/schedutil/down_rate_limit_us" 2>/dev/null
        [ -f "$cpu/schedutil/up_rate_limit_us" ] && echo 500 > "$cpu/schedutil/up_rate_limit_us" 2>/dev/null
    done
    
    # 2. Kernel & Process Enhancements
    echo 0 > /proc/sys/kernel/randomize_va_space 2>/dev/null
    echo 10 > /proc/sys/vm/swappiness 2>/dev/null
    echo 100 > /proc/sys/vm/vfs_cache_pressure 2>/dev/null
    echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
    echo 512 > /proc/sys/fs/inotify/max_user_watches 2>/dev/null
    echo 1048576 > /proc/sys/fs/file-max 2>/dev/null
    echo 2048 > /proc/sys/kernel/sched_latency_ns 2>/dev/null
    echo 250 > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null
    echo 500 > /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null

    # 3. GPU & SurfaceFlinger Overdrive
    setprop debug.hwui.renderer opengl
    setprop debug.sf.latch_unsignaled 1
    setprop debug.sf.disable_backpressure 1
    setprop debug.sf.treat_hq_as_sdr 1
    setprop debug.sf.enable_hgl 1
    setprop debug.performance.tuning 1
    setprop video.accelerate.hw 1
    setprop persist.vendor.gpu.autotune 1
    setprop debug.egl.hw 1

    # 4. Touch & Input Latency Tweaks
    settings put system touch_blocking_period 30
    settings put secure tap_duration_threshold 0
    settings put secure long_press_timeout 150
    settings put system pointer_speed 7
    settings put global pointer_location 0
    cmd device_config put input velocity_tracker_strategy impulse
    cmd device_config put input block_untrusted_touches false

    # 5. Network & TCP Low Latency
    setprop net.tcp.buffersize.default 4096,87380,704000,4096,16384,110208
    setprop net.tcp.buffersize.wifi 524288,1048576,2097152,262144,524288,1048576
    setprop net.tcp.buffersize.lte 524288,1048576,2097152,262144,524288,1048576
    setprop net.tcp.low_latency 1
    settings put global wifi_suspend_optimizations_enabled 0
    settings put global wifi_watchdog_on 0
    settings put global ble_scan_always_available 0
    settings put global mobile_data_always_on 0

    # 6. Activity Manager & Phantom Killer Bypass
    device_config put activity_manager max_phantom_processes 2147483647
    device_config put activity_manager use_compaction true
    cmd device_config put activity_manager max_cached_processes 32

    # 7. Disable Vendor Throttling
    pm disable-user --user 0 com.samsung.android.game.gos 2>/dev/null
    pm disable-user --user 0 com.samsung.android.game.gametools 2>/dev/null
    pm disable-user --user 0 com.xiaomi.joyose 2>/dev/null
    pm disable-user --user 0 com.motorola.gamemode 2>/dev/null

    # 8. Storage & I/O
    for queue in /sys/block/*/queue; do
        [ -f "$queue/read_ahead_kb" ] && echo 2048 > "$queue/read_ahead_kb" 2>/dev/null
        [ -f "$queue/add_random" ] && echo 0 > "$queue/add_random" 2>/dev/null
        [ -f "$queue/scheduler" ] && echo "noop" > "$queue/scheduler" 2>/dev/null
    done
}

reset_50_plus() {
    setprop debug.hwui.renderer ""
    setprop debug.sf.latch_unsignaled ""
    setprop debug.sf.disable_backpressure ""
    pm enable com.samsung.android.game.gos 2>/dev/null
    pm enable com.xiaomi.joyose 2>/dev/null
    pm enable com.motorola.gamemode 2>/dev/null
}

case "$1" in
    apply|on|1) apply_50_plus ;;
    reset|off|0) reset_50_plus ;;
    *) apply_50_plus ;;
esac
