#!/system/bin/sh
# VOID BATTERY v9.1 — [NEW] ART Runtime Optimization
# Optimize ART runtime settings for battery efficiency

case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_devconfig runtime_native dex2oat_threads 1
        vb_devconfig runtime_native bg_dex2oat_threads 1
        vb_devconfig runtime_native dex2oat_priority background
        vb_devconfig runtime_native use_jit_profiles true
        ;;
    ECO|IDLE)
        vb_devconfig runtime_native dex2oat_threads 2
        vb_devconfig runtime_native bg_dex2oat_threads 1
        ;;
    BALANCED)
        vb_devconfig runtime_native dex2oat_threads 2
        vb_devconfig runtime_native bg_dex2oat_threads 2
        ;;
    PERFORMANCE)
        vb_devconfig runtime_native dex2oat_threads 4
        vb_devconfig runtime_native bg_dex2oat_threads 2
        ;;
esac
vb_log "RUNTIME" "ART runtime optimized"
