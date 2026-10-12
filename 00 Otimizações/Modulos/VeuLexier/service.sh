#!/system/bin/sh

SCRIPT_PATH="${0%/*}/system/lex.sh"

# ==== CEK FILE SCRIPT ADA ====
if [ ! -f "$SCRIPT_PATH" ]; then
    am start -a AxManager.TOAST -e text "Error: lex.sh tidak ditemukan"
    exit 1
fi

# ==== CEK LOKASI LOG AMAN ====
LOG_PATH="/dev/null"

# Kalau /system read-only → pindah ke /data/local/tmp
if ! touch "$LOG_PATH" 2>/dev/null; then
    LOG_PATH="/data/local/tmp/lex.log"
fi

# ==== CEK SUDAH BERJALAN BELUM ====
PID_EXIST=$(pgrep -f "$SCRIPT_PATH")
if [ -n "$PID_EXIST" ]; then
    am start -a AxManager.TOAST -e text "Smart Cache Cleaner sudah aktif"
    exit 0
fi

# ==== START BACKGROUND PROCESS ====

# Jalankan script
nohup "$SCRIPT_PATH" > "$LOG_PATH" 2>&1 &

sleep 0.5

# ==== CEK BERHASIL JALAN ====
NEW_PID=$(pgrep -f "$SCRIPT_PATH")

if [ -n "$NEW_PID" ]; then
    am start -a AxManager.TOAST -e text "Smart Cache Cleaner Activated"
else
    am start -a AxManager.TOAST -e text "Gagal Mengaktifkan Smart Cache Cleaner"
fi

# ============= CLEAN UP SYSTEM JUNK =================
# Credit By @HoyoSlave For CMD TWEAK
for a in $(cmd package list packages --user 0 -s|grep -Eiv 'youtube|theme'|cut -f2 -d:);do
  rm -rf "/storage/emulated/0/Android/data/$a"
  rm -rf "/storage/emulated/0/Android/media/.sosp/$a"
  rm -rf "/storage/emulated/0/Android/Android/obb/$a"
done
for b in $(cmd package list packages --user 0|cut -f2 -d:);do
  cmd activity clear-ignore-delivery-group-policy "$b"
  cmd usagestats clear-last-used-timestamps "$b"
  cmd usagestats delete-package-data "$b"
done
cmd activity clear-debug-app
cmd activity clear-exit-info
cmd activity clear-watch-heap all
cmd blob_store clear-all-blobs
cmd blob_store clear-all-sessions
cmd companiondevice remove-inactive-associations
cmd device_policy clear-freeze-period-record
cmd display clear-user-preferred-display-mode 0
cmd font clear
cmd greezer clearmonitor
cmd location_time_zone_manager clear_recorded_provider_states
cmd lock_settings clear
cmd lock_settings remove-cache
cmd media.camera clear-stream-use-case-override
cmd media.camera watch clear
cmd miui.downscale clear-debug-apps
cmd miui_embedding_window clear-fixedOri
cmd miui_embedding_window_projection clear-fixedOri
cmd safety_center clear-data
cmd stats clear-puller-cache
cmd stats config remove 0
cmd telecom cleanup-orphan-phone-accounts
cmd telecom cleanup-stuck-calls
cmd time_detector clear_network_time
cmd time_detector clear_system_clock_network_time
cmd wifi remove-all-suggestions
dumpsys media.metrics --clear
dumpsys procstats --clear