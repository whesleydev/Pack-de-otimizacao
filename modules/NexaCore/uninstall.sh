#!/system/bin/sh
#Credits to @EnriqueBrach

DIRECT="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

if [[ "$DIRECT" == */ ]]; then
    DIRECT="${DIRECT%/}"
fi

ADDONS_DIR="${DIRECT}/Addons"
[ ! -d "$ADDONS_DIR" ] && ADDONS_DIR="$DIRECT"

for addon in 01_task_synergy.sh 02_power_harmony.sh 03_touch_drift.sh 04_net_thread.sh 05_perf_stride.sh; do
    if [ -f "${ADDONS_DIR}/${addon}" ]; then
        chmod 777 "${ADDONS_DIR}/${addon}"
        sh "${ADDONS_DIR}/${addon}" reset >/dev/null 2>&1
    fi
done

settings delete global nexacore_enable >/dev/null 2>&1
settings delete system javafx.animation.scale >/dev/null 2>&1
setprop debug.sys.devices.system.cpu.cpu0.cpufreq.scaling.governor "" >/dev/null 2>&1

cmd notification post -t "NexaCore" "nexacore_status" "Status: Uninstalled || By @EnriqueBrach" >/dev/null 2>&1

if [ -f "/data/local/tmp/NexaCore/restore.sh" ]; then
    sh "/data/local/tmp/NexaCore/restore.sh" >/dev/null 2>&1
fi

rm -rf /data/local/tmp/NexaCore >/dev/null 2>&1