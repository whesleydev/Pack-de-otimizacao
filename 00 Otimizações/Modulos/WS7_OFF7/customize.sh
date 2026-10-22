#!/system/bin/sh
type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

[ -n "$MODPATH" ] && DIRECT="$MODPATH" || DIRECT="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ "${DIRECT%/}" != "$DIRECT" ] && DIRECT="${DIRECT%/}"

if [ "$AXERON" = "true" ]; then
    APP="AxManager"
elif [ "$SUNPROT" = "true" ]; then
    APP="SunProt"
elif [ "$KSU" = "true" ] || [ -n "$KSU_VER" ] || [ -n "$KSU_ENV" ]; then
    APP="KernelSU"
elif [ "$APATCH" = "true" ] || [ -n "$APATCH_VER" ]; then
    APP="APatch"
elif [ -n "$MAGISK_VER" ] || [ -n "$MAGISK_VER_CODE" ] || [ "$MAGISK" = "true" ] || type magisk >/dev/null 2>&1; then
    APP="Magisk"
else
    APP="Unknown"
fi

addons_path="${DIRECT}/Addons/"

run_addon() {
    local script="$1"
    if [ -f "${addons_path}${script}" ]; then
        chmod 777 "${addons_path}${script}"
        sh "${addons_path}${script}" apply >/dev/null 2>&1 &
    fi
}

ui_print "=================================================="
ui_print "  WS7_OFF7 · SUPREME CYBERNETIC ENGINE v6.0"
ui_print "  Environment: $APP"
ui_print "=================================================="

for s in 01_task_synergy.sh 02_power_harmony.sh 03_touch_drift.sh 04_net_thread.sh 05_perf_stride.sh; do
    ui_print " -> Applying addon: $s"
    run_addon "$s"
    sleep 0.3
done

ui_print "=================================================="
ui_print " [✔] WS7_OFF7 successfully installed & primed!"
ui_print "=================================================="
