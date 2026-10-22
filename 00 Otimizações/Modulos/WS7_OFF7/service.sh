#!/system/bin/sh
# WS7_OFF7 Brutalist Engine Service Script

boot_completed() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 2
    done
    until [ -d "/sdcard/Android" ] || [ -d "/storage/emulated/0/Android" ]; do
        sleep 1
    done
}

boot_completed

DIRECT="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ "${DIRECT%/}" != "$DIRECT" ] && DIRECT="${DIRECT%/}"
ADDONS_DIR="${DIRECT}/Addons"
[ ! -d "$ADDONS_DIR" ] && ADDONS_DIR="$DIRECT"

settings put global ws7_off7_enable true
setprop debug.performance.tuning 1
setprop persist.traced.enable 0
device_config put activity_manager max_phantom_processes 2147483647 >/dev/null 2>&1

# Apply vendor bypasses safely
pm disable-user --user 0 com.samsung.android.game.gos >/dev/null 2>&1
pm disable-user --user 0 com.xiaomi.joyose >/dev/null 2>&1
pm disable-user --user 0 com.motorola.gamemode >/dev/null 2>&1

# Apply addons
for addon in 01_task_synergy.sh 02_power_harmony.sh 03_touch_drift.sh 04_net_thread.sh 05_perf_stride.sh; do
    if [ -f "${ADDONS_DIR}/${addon}" ]; then
        chmod 777 "${ADDONS_DIR}/${addon}"
        sh "${ADDONS_DIR}/${addon}" apply >/dev/null 2>&1 &
    fi
done

cmd notification post -t "WS7_OFF7" "ws7_status" "Status: Active • Brutalist Engine Online" >/dev/null 2>&1
