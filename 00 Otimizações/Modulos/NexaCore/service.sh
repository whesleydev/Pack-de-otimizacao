#!/system/bin/sh
#Credits to @EnriqueBrach

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

if [[ "$DIRECT" == */ ]]; then
    DIRECT="${DIRECT%/}"
fi

ADDONS_DIR="${DIRECT}/Addons"
[ ! -d "$ADDONS_DIR" ] && ADDONS_DIR="$DIRECT"

settings put global nexacore_enable true
settings put system javafx.animation.scale 50000
setprop debug.sys.devices.system.cpu.cpu0.cpufreq.scaling.governor Performance

for addon in 01_task_synergy.sh 02_power_harmony.sh 03_touch_drift.sh 04_net_thread.sh 05_perf_stride.sh; do
    if [ -f "${ADDONS_DIR}/${addon}" ]; then
        chmod 777 "${ADDONS_DIR}/${addon}"
        nohup sh "${ADDONS_DIR}/${addon}" apply >/dev/null 2>&1 &
    fi
done

cmd notification post -t "NexaCore" "nexacore_status" "Status: Active • Installed || By @EnriqueBrach" >/dev/null 2>&1

if [ -f "/data/local/tmp/NexaCore/backup.sh" ]; then
    sh /data/local/tmp/NexaCore/backup.sh >/dev/null 2>&1
fi