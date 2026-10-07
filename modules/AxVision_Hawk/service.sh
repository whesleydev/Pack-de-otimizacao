#!/system/bin/sh

MODDIR=${0%/*}
TMPDIR="/data/local/tmp"
GAME_TXT="$TMPDIR/game.txt"

VERSION="$(getprop ro.build.version.release 2>/dev/null)"
VERSION_INT="${VERSION%%.*}"

GAME_LIST="$(dumpsys game 2>/dev/null | grep -oE 'Name:[^ ]+|package [^ ]+' | sed 's/Name://;s/package //')"

wait_until_boot_completed() {
  # Wait sys.boot_completed
  while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 2
  done

  # Wait for storage to mount
  until [ -d "/sdcard/Android" ] || [ -d "/storage/emulated/0/Android" ]; do
    sleep 1
  done
}

sync;wait_until_boot_completed

if [ -z "$VERSION_INT" ]; then
    echo "[ERROR] Tidak bisa membaca versi Android" >&2
    exit 1
fi

if [ "$VERSION_INT" -ge 12 ] 2>/dev/null; then
    if [ -n "$GAME_LIST" ]; then
        printf "%s\n" "$GAME_LIST" > "$GAME_TXT"
    else
        echo "[WARN] GAME_LIST kosong, melewati penulisan file" >&2
    fi
else
    package_list="$(cmd package list packages 2>/dev/null | cut -d':' -f2)"
    filtered=""
    if [ ! -f "$MODDIR/game.txt" ]; then
        echo "[ERROR] File $MODDIR/game.txt tidak ditemukan" >&2
        exit 1
    fi
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if printf "%s\n" "$package_list" | grep -qx "$pkg"; then
            filtered="${filtered}${pkg}"$'\n'
        fi
    done < "$MODDIR/game.txt"
    printf "%s" "$filtered" > "$GAME_TXT"
fi

# Hapus cache dengan validasi
CACHE_DIR="$TMPDIR/.vmtouch_cache"
if [ -d "$CACHE_DIR" ]; then
    rm -rf "$CACHE_DIR" || echo "[WARN] Gagal menghapus cache" >&2
fi

if [ ! -f /data/local/tmp/visionai.pid ]; then
   vision --exec
else
  vision --stop
  sleep 2
  vision --exec
fi

# Cek package sebelum am start
if cmd package list packages | grep -q "frb.axeron.manager"; then
    am start -n frb.axeron.manager/.ui.webui.WebUIActivity \
      --es "id" "axvision-release-version"
else
    echo "[ERROR] Package frb.axeron.manager tidak ditemukan" >&2
    exit 1
fi