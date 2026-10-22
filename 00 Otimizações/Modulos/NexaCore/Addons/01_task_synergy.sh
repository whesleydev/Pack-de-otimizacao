#!/system/bin/sh

get_ram_mb() {
    RAM_KB=0
    while read -r line; do
        case "$line" in
            MemTotal:*)
                set -- $line
                RAM_KB=$2
                break
                ;;
        esac
    done < /proc/meminfo
    printf "%s\n" $((RAM_KB / 1024))
}

RAM_MB=$(get_ram_mb)

apply() {
    if [ "$RAM_MB" -lt 900 ]; then
        MAX_CACHED=4
        CONSTANTS="max_cached_processes=4,background_settle_time=15000,gc_min_interval=30000,process_start_async=true,power_check_max_cpu_1=5,power_check_max_cpu_2=3,power_check_max_cpu_3=1,power_check_max_cpu_4=1,max_phantom_processes=2,low_swap_threshold_percent=0.30,proactive_kills_enabled=true,max_previous_time=15000,service_restart_duration=10000,binder_heavy_hitter_watcher_enabled=false"
    elif [ "$RAM_MB" -lt 1500 ]; then
        MAX_CACHED=6
        CONSTANTS="max_cached_processes=6,background_settle_time=20000,gc_min_interval=45000,process_start_async=true,power_check_max_cpu_1=5,power_check_max_cpu_2=3,power_check_max_cpu_3=1,power_check_max_cpu_4=1,max_phantom_processes=4,low_swap_threshold_percent=0.25,proactive_kills_enabled=true,max_previous_time=20000,service_restart_duration=8000,binder_heavy_hitter_watcher_enabled=false"
    elif [ "$RAM_MB" -lt 2500 ]; then
        MAX_CACHED=8
        CONSTANTS="max_cached_processes=8,background_settle_time=30000,gc_min_interval=60000,process_start_async=true,power_check_max_cpu_1=10,power_check_max_cpu_2=5,power_check_max_cpu_3=2,power_check_max_cpu_4=1,max_phantom_processes=6,low_swap_threshold_percent=0.20,proactive_kills_enabled=true,max_previous_time=30000,service_restart_duration=5000,binder_heavy_hitter_watcher_enabled=false"
    elif [ "$RAM_MB" -lt 3500 ]; then
        MAX_CACHED=10
        CONSTANTS="max_cached_processes=10,background_settle_time=30000,gc_min_interval=60000,process_start_async=true,power_check_max_cpu_1=12,power_check_max_cpu_2=6,power_check_max_cpu_3=3,power_check_max_cpu_4=1,max_phantom_processes=8,low_swap_threshold_percent=0.18,proactive_kills_enabled=true,max_previous_time=45000,service_restart_duration=5000,binder_heavy_hitter_watcher_enabled=false"
    elif [ "$RAM_MB" -lt 4500 ]; then
        MAX_CACHED=12
        CONSTANTS="max_cached_processes=12,background_settle_time=45000,gc_min_interval=90000,process_start_async=true,power_check_max_cpu_1=15,power_check_max_cpu_2=8,power_check_max_cpu_3=4,power_check_max_cpu_4=2,max_phantom_processes=10,low_swap_threshold_percent=0.15,proactive_kills_enabled=true,max_previous_time=60000,service_restart_duration=3000,binder_heavy_hitter_watcher_enabled=false"
    elif [ "$RAM_MB" -lt 5500 ]; then
        MAX_CACHED=14
        CONSTANTS="max_cached_processes=14,background_settle_time=45000,gc_min_interval=90000,process_start_async=true,power_check_max_cpu_1=18,power_check_max_cpu_2=10,power_check_max_cpu_3=5,power_check_max_cpu_4=2,max_phantom_processes=12,low_swap_threshold_percent=0.12,proactive_kills_enabled=true,max_previous_time=60000,service_restart_duration=3000,binder_heavy_hitter_watcher_enabled=false"
    elif [ "$RAM_MB" -lt 6500 ]; then
        MAX_CACHED=16
        CONSTANTS="max_cached_processes=16,background_settle_time=60000,gc_min_interval=120000,process_start_async=true,power_check_max_cpu_1=20,power_check_max_cpu_2=10,power_check_max_cpu_3=5,power_check_max_cpu_4=2,max_phantom_processes=14,low_swap_threshold_percent=0.10,proactive_kills_enabled=true,max_previous_time=90000,service_restart_duration=2000,binder_heavy_hitter_watcher_enabled=false"
    else
        MAX_CACHED=18
        CONSTANTS="max_cached_processes=18,background_settle_time=60000,gc_min_interval=120000,process_start_async=true,power_check_max_cpu_1=25,power_check_max_cpu_2=12,power_check_max_cpu_3=6,power_check_max_cpu_4=3,max_phantom_processes=16,low_swap_threshold_percent=0.10,proactive_kills_enabled=true,max_previous_time=120000,service_restart_duration=2000,binder_heavy_hitter_watcher_enabled=false"
    fi

    cmd device_config put activity_manager max_cached_processes "$MAX_CACHED" >/dev/null 2>&1
    settings put global activity_manager_constants "$CONSTANTS" >/dev/null 2>&1
    cmd device_config put activity_manager use_compaction true >/dev/null 2>&1
}

reset() {
    cmd device_config delete activity_manager max_cached_processes >/dev/null 2>&1
    settings delete global activity_manager_constants >/dev/null 2>&1
    cmd device_config delete activity_manager use_compaction >/dev/null 2>&1
}

ACTION=$(echo "$1" | tr '[:upper:]' '[:lower:]')

case "$ACTION" in
    enable|on|apply|1)
        apply
        ;;
    reset|remove|off|disable|0)
        reset
        ;;
esac