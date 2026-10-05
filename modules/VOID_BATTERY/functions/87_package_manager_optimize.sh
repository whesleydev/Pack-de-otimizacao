#!/system/bin/sh
# VOID BATTERY v9.1 — Package Manager Optimize
case "$VB_PROFILE" in
    CRITICAL|POWERSAVE)
        vb_settings global verifier_verify_adb_installs 0
        vb_devconfig runtime_native dex2oat_threads 1
        ;;
    *)
        vb_settings global verifier_verify_adb_installs 1
        ;;
esac
