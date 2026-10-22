#!/system/bin/sh
# ===========================================================
# VOID TOUCH Ultra v5.1.0 — Ultimate ADB Touch Optimizer
# 50 functions | 40 real optimizations | No Root | No Daemon
# ===========================================================

MODDIR="${0%/*}"
BASE="/sdcard/VOID_TOUCH/v5"
SNAP="$BASE/snapshot"
BACKUP="$BASE/backup"
TMP="$BASE/tmp"
REPORT="$BASE/report.txt"
LOG="$BASE/void_touch.log"
INPUT="$TMP/input_dump.txt"

mkdir -p "$SNAP" "$BACKUP" "$TMP" 2>/dev/null
: > "$REPORT"
: > "$LOG"
: > "$BACKUP/settings_backup.txt"

# --- Source library ---
. "$MODDIR/scripts/lib/common.sh"

# --- Banner (printf %s for art, %b for colors only) ---
printf '%b' "${C}${B}"
printf '%s\n' ''
printf '%s\n' '  __     ______  ___ ____  '
printf '%s\n' '  \ \   / / __ \|_ _|  _ \ '
printf '%s\n' '   \ \ / / |  | || || | | |'
printf '%s\n' '    \ V /| |  | || || | | |'
printf '%s\n' '     \ / | |__| || || |_| |'
printf '%s\n' '      V   \____/|___|____/ '
printf '%b\n' "${N}"
printf '%b\n' ""
printf '%b\n' "${B}  VOID TOUCH Ultra v5.1.0${N}"
printf '%s\n' "  Touch Optimizer | ADB No Root | Safe & Reversible"
printf '%s\n' "  =================================================="
printf '%s\n' ""

# --- Source all phase scripts ---
for _script in "$MODDIR"/scripts/*/core.sh; do
    case "$_script" in */lib/*) continue;; esac
    [ -f "$_script" ] && . "$_script"
done

# --- Dump input data for analysis ---
dumpsys input > "$INPUT" 2>/dev/null
MAX_HZ=""
MAX_REFRESH=""

# ============================
# Phase 1: DETECTION
# ============================
printf '%b\n' "${B}${C}  [Phase 1/7] DEVICE & TOUCH DETECTION${N}"
printf '%s\n' "  ------------------------------------------"
f01_touchscreen_presence
f02_touch_vendor
f03_input_service
f04_multitouch_detect
f05_touch_resolution
f06_device_info
f07_settings_snapshot
f08_display_info
printf '%s\n' ""

# ============================
# Phase 2: TOUCH RESPONSE
# ============================
printf '%b\n' "${B}${C}  [Phase 2/7] TOUCH RESPONSE OPTIMIZATION${N}"
printf '%s\n' "  ------------------------------------------"
f09_disable_show_touches
f10_disable_pointer_location
f11_optimize_long_press
f12_optimize_multi_press
f13_optimize_pointer_speed
f14_disable_touch_sounds
f15_disable_lockscreen_sounds
f16_disable_charging_sounds
printf '%s\n' ""

# ============================
# Phase 3: ANIMATIONS
# ============================
printf '%b\n' "${B}${C}  [Phase 3/7] ANIMATION SPEED OPTIMIZATION${N}"
printf '%s\n' "  ------------------------------------------"
f17_window_animation
f18_transition_animation
f19_animator_duration
f20_disable_ime_animations
printf '%s\n' ""

# ============================
# Phase 4: DISPLAY & REFRESH
# ============================
printf '%b\n' "${B}${C}  [Phase 4/7] DISPLAY & REFRESH RATE${N}"
printf '%s\n' "  ------------------------------------------"
f21_set_peak_refresh
f22_set_min_refresh
f23_set_user_refresh
f24_disable_window_blurs
f25_disable_notification_bubbles
f26_disable_screensaver
printf '%s\n' ""

# ============================
# Phase 5: SYSTEM LATENCY
# ============================
printf '%b\n' "${B}${C}  [Phase 5/7] SYSTEM LATENCY REDUCTION${N}"
printf '%s\n' "  ------------------------------------------"
f27_kill_cached_processes
f28_trim_memory
f29_disable_notification_pulse
f30_disable_notification_dots
f31_ensure_activities_persist
f32_disable_dtmf_tones
printf '%s\n' ""

# ============================
# Phase 6: INPUT PIPELINE
# ============================
printf '%b\n' "${B}${C}  [Phase 6/7] INPUT PIPELINE OPTIMIZATION${N}"
printf '%s\n' "  ------------------------------------------"
f33_disable_text_classifier
f34_disable_smart_selection
f35_disable_predictive_back
f36_disable_magnification
f37_disable_autoclick
f38_disable_touch_exploration
printf '%s\n' ""

# ============================
# Phase 7: ADVANCED
# ============================
printf '%b\n' "${B}${C}  [Phase 7/7] ADVANCED OPTIMIZATIONS${N}"
printf '%s\n' "  ------------------------------------------"
f39_vendor_touch_optimizer
f40_disable_battery_saver
f41_clear_debug_app
f42_reset_gpu_pipeline
f43_trim_app_caches
f44_disable_spell_checker
f45_disable_wifi_scan_throttle
f46_disable_network_scoring
f47_disable_pkg_verifier
f48_connectivity_refresh
printf '%s\n' ""

# ============================
# SUMMARY
# ============================
printf '%s\n' "  =================================================="
printf '%b\n' "${B}${G}  VOID TOUCH v5.1.0 -- Concluido!${N}"
printf '%s\n' "  =================================================="
printf '%s\n' ""
printf '%b\n' "  ${G}Otimizacoes aplicadas:${N} $CHANGED"
printf '%b\n' "  ${C}Funcoes processadas:${N}   $((PASS + SKIP + WARN + FAIL_C))"
printf '%b\n' "  ${Y}Ignorados (skip):${N}     $SKIP"
if [ "$WARN" -gt 0 ]; then
    printf '%b\n' "  ${Y}Avisos:${N}               $WARN"
fi
if [ "$FAIL_C" -gt 0 ]; then
    printf '%b\n' "  ${R}Falhas:${N}               $FAIL_C"
fi
printf '%s\n' ""
printf '%s\n' "  Backup:    $BACKUP/settings_backup.txt"
printf '%s\n' "  Relatorio: $REPORT"
printf '%s\n' "  Log:       $LOG"
printf '%s\n' ""

# --- Final report ---
report ""
report "========================================"
report "VOID TOUCH Ultra v5.1.0 — Summary"
report "Changed: $CHANGED | Pass: $PASS | Skip: $SKIP | Warn: $WARN"
report "Date: $(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)"
report "========================================"

rm -rf "$TMP" 2>/dev/null
exit 0
