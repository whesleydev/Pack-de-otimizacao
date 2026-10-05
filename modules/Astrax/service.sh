#!/system/bin/sh
while [ "$(getprop sys.boot_completed)" != "1" ]; do
  sleep 2
done
sleep 5

# ── Tunggu storage siap ──
until [ -d "/sdcard/Android" ] || [ -d "/storage/emulated/0/Android" ]; do
    sleep 1
done

MODDIR="$(dirname "$(readlink -f "$0")")"
TMP_BASE="/data/local/tmp/astrax"
ASTRAX_DIR="/storage/emulated/0/.astrax"
PKG_FILE="$ASTRAX_DIR/pkg"
CFG_FILE="$ASTRAX_DIR/gm_cfg"

mkdir -p "$TMP_BASE" "$ASTRAX_DIR" 2>/dev/null

cp -f "$MODDIR/hhtnn/"*.sh "$TMP_BASE/" 2>/dev/null
cp -f "$MODDIR/hhtnn/scripts/"*.sh "$TMP_BASE/" 2>/dev/null
cp -f "$MODDIR/hhtnn/scripts/"*.sh "$ASTRAX_DIR/" 2>/dev/null
chmod 755 "$TMP_BASE/"*.sh "$ASTRAX_DIR/"*.sh 2>/dev/null

# ── Buat file pkg jika belum ada ──
if [ ! -f "$PKG_FILE" ]; then
    touch "$PKG_FILE" 2>/dev/null
    chmod 644 "$PKG_FILE" 2>/dev/null
fi

# ── Bersihkan duplikat di file pkg ──
if [ -f "$PKG_FILE" ] && [ -s "$PKG_FILE" ]; then
    sort -u "$PKG_FILE" -o "$PKG_FILE" 2>/dev/null
fi

# ── Buat file gm_cfg jika belum ada ──
if [ ! -f "$CFG_FILE" ]; then
    touch "$CFG_FILE" 2>/dev/null
    chmod 644 "$CFG_FILE" 2>/dev/null
fi

# ── Jalankan sistem utama Astrax ──
"$MODDIR/hhtnn/content.sh" &

# ── Tunggu sebentar lalu restore Game Manager settings ──
# Delay agar sistem siap sebelum kita apply game mode, downscale, dll
sleep 8
sh "$ASTRAX_DIR/gm_restore.sh" &

# ── FIX bug "downscale kadang burem kadang enggak": device_config
#    game_overlay TIDAK bertahan lewat reboot — WAJIB di-reapply tiap
#    boot lewat gm_restore.sh di atas. Masalahnya: kalau user buru-buru
#    buka game persis di jendela waktu SEBELUM restore pertama ini
#    selesai (device baru saja boot), game itu sempat jalan TANPA
#    downscale sama sekali (makanya kadang "enggak burem" — bukan bug
#    di fitur downscale-nya sendiri, tapi soal timing race saat boot).
#    Jalankan sekali lagi sebagai jaring pengaman kedua setelah jeda
#    lebih lama — supaya kalau percobaan pertama kelewat cepat/gagal
#    diam-diam (mis. GameManagerService belum sepenuhnya siap), restart
#    game berikutnya oleh user tetap dapat downscale yang benar.
( sleep 30; sh "$ASTRAX_DIR/gm_restore.sh" ) &

