#!/system/bin/sh

type ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

[ -n "$MODPATH" ] && DIRECT="$MODPATH" || DIRECT="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"

if [[ "$DIRECT" == */ ]]; then
    DIRECT="${DIRECT%/}"
fi

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
        nohup sh "${addons_path}${script}" apply >/dev/null 2>&1 &
    fi
}

banner() {
    ui_print "$(cat << 'EOF'
╭━╮╱╭╮╱╱╱╱╱╱╱╱╭━━━╮
┃┃╰╮┃┃╱╱╱╱╱╱╱╱┃╭━╮┃
┃╭╮╰╯┣━━┳╮╭┳━━┫┃╱╰╋━━┳━┳━━╮
┃┃╰╮┃┃┃━╋╋╋┫╭╮┃┃╱╭┫╭╮┃╭┫┃━┫
┃┃╱┃┃┃┃━╋╋╋┫╭╮┃╰━╯┃╰╯┃┃┃┃━┫
╰╯╱╰━┻━━┻╯╰┻╯╰┻━━━┻━━┻╯╰━━╯
EOF
)"
}

print_info() {
    model=$(getprop ro.product.model)
    sdk=$(getprop ro.build.version.sdk)
    release=$(getprop ro.build.version.release)

    ui_print "$(cat << 'EOF'
——————————————————————————————————————————————————
 • Credits to: @EnriqueBrach
 • Created By: @EnriqueBrach
——————————————————————————————————————————————————
EOF
)"

    sleep 1

    ui_print "$(cat << EOF

[◦] Environment: $APP
[◦] Device Model: $model
[◦] Android SDK: $sdk
[◦] Android Ver: $release
EOF
)"
}

print_progress() {
    ui_print "$(cat << 'EOF'
——————————————————————————————————————————————————
 NexaCore Module Installing...
——————————————————————————————————————————————————
EOF
)"
    ui_print ""

    for bar in "[█▒▒▒▒▒▒▒▒▒] 10%" "[███▒▒▒▒▒▒▒] 30%" "[█████▒▒▒▒▒] 50%" "[███████▒▒▒] 75%" "[██████████] 100%"; do
        ui_print "$bar"
        case "$bar" in
            *10%)  run_addon "01_task_synergy.sh" ;;
            *30%)  run_addon "02_power_harmony.sh" ;;
            *50%)  run_addon "03_touch_drift.sh" ;;
            *75%)  run_addon "04_net_thread.sh" ;;
            *100%) run_addon "05_perf_stride.sh" ;;
        esac
        sleep 1
    done

    ui_print ""
}

main() {
    banner
    sleep 1
    print_info
    sleep 1
    print_progress
    sleep 1
    ui_print ">>> NexaCore Successfully Loaded. <<<"
    ui_print ""
}

main