#!/system/bin/sh
DIRECT="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ "${DIRECT%/}" != "$DIRECT" ] && DIRECT="${DIRECT%/}"
ADDONS_DIR="${DIRECT}/Addons"
[ ! -d "$ADDONS_DIR" ] && ADDONS_DIR="$DIRECT"

for addon in 01_task_synergy.sh 02_power_harmony.sh 03_touch_drift.sh 04_net_thread.sh 05_perf_stride.sh; do
    if [ -f "${ADDONS_DIR}/${addon}" ]; then
        sh "${ADDONS_DIR}/${addon}" reset >/dev/null 2>&1
    fi
done

pm enable com.samsung.android.game.gos >/dev/null 2>&1
pm enable com.xiaomi.joyose >/dev/null 2>&1
pm enable com.motorola.gamemode >/dev/null 2>&1
setprop persist.traced.enable 1 >/dev/null 2>&1

settings delete global ws7_off7_enable >/dev/null 2>&1
cmd notification post -t "WS7_OFF7" "ws7_status" "Status: Uninstalled • Engine Removed" >/dev/null 2>&1
