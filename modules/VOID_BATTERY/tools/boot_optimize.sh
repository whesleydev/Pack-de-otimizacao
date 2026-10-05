#!/system/bin/sh
MODPATH="${1:-${0%/*}/..}"
echo "[BOOT] VOID BATTERY v9.1 — Boot optimization"

pm trim-caches 500M 2>/dev/null
echo "[BOOT] Cache trimmed"

settings put global window_animation_scale 0.7 2>/dev/null
settings put global transition_animation_scale 0.7 2>/dev/null
settings put global animator_duration_scale 0.7 2>/dev/null
echo "[BOOT] Animations set to 0.7x"

# Do not force App Standby or ActivityManager policy at boot. Android/OEM
# power managers retain ownership of these global settings.
settings put global adaptive_battery_management_enabled 1 2>/dev/null
echo "[BOOT] Adaptive battery requested; standby policy left to Android/OEM"

echo "[BOOT] Boot optimization done"
