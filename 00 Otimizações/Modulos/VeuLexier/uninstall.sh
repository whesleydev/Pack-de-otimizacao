#!/system/bin/sh

# Nama proses
TARGET="lex.sh"

# Cari PID yang exact
pid=$(pgrep -f "$TARGET")

# ==== Kill Process ====
if [ -n "$pid" ]; then
    kill -9 "$pid"
    sleep 0.3
fi

# ==== Cek Apakah Masih Hidup ====
pid_after=$(pgrep -f "$TARGET")

if [ -z "$pid_after" ]; then
    am start -a AxManager.TOAST -e text "Smart Cache Cleaner Deactivated"
else
    am start -a AxManager.TOAST -e text "Deactivated Smart Cache Cleaner Denied"
fi