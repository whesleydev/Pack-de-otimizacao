#!/system/bin/sh
# VOID BATTERY v9.1 — Maintenance Deferral
[ "$VB_PROFILE" = "PERFORMANCE" ] && return 0

if [ "$VB_CHARGING" = "0" ]; then
    case "$VB_PROFILE" in
        CRITICAL|POWERSAVE)
            vb_devconfig runtime dex2oat_threads 1
            vb_devconfig runtime_native bg_dex2oat_threads 1
            ;;
        ECO|IDLE)
            vb_devconfig runtime dex2oat_threads 1
            ;;
    esac
else
    vb_devconfig runtime dex2oat_threads 2
fi
