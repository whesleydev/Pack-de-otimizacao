#!/system/bin/sh
get_ram_mb() {
    RAM_KB=0
    while read -r line; do
        case "$line" in
            MemTotal:*) set -- $line; RAM_KB=$2; break ;;
        esac
    done < /proc/meminfo
    echo $((RAM_KB / 1024))
}
RAM_MB=$(get_ram_mb)

apply() {
    if [ "$RAM_MB" -lt 2500 ]; then
        MAX_CACHED=8
        CONSTANTS="max_cached_processes=8,background_settle_time=20000,gc_min_interval=45000,process_start_async=true,max_phantom_processes=6,low_swap_threshold_percent=0.20"
    elif [ "$RAM_MB" -lt 4500 ]; then
        MAX_CACHED=12
        CONSTANTS="max_cached_processes=12,background_settle_time=30000,gc_min_interval=60000,process_start_async=true,max_phantom_processes=10,low_swap_threshold_percent=0.15"
    else
        MAX_CACHED=18
        CONSTANTS="max_cached_processes=18,background_settle_time=45000,gc_min_interval=90000,process_start_async=true,max_phantom_processes=2147483647,low_swap_threshold_percent=0.10"
    fi
    cmd device_config put activity_manager max_cached_processes "$MAX_CACHED" >/dev/null 2>&1
    settings put global activity_manager_constants "$CONSTANTS" >/dev/null 2>&1
    cmd device_config put activity_manager use_compaction true >/dev/null 2>&1
    device_config put activity_manager max_phantom_processes 2147483647 >/dev/null 2>&1
}

reset() {
    cmd device_config delete activity_manager max_cached_processes >/dev/null 2>&1
    settings delete global activity_manager_constants >/dev/null 2>&1
    cmd device_config delete activity_manager use_compaction >/dev/null 2>&1
}

[ "$1" = "apply" ] || [ "$1" = "on" ] && apply || reset
