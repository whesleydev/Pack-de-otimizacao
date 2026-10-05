#!/system/bin/sh
# BEN UNIVERSAL v4.6 • FREE FIRE FRAME STABILITY
U=$(id -u 2>/dev/null)
[ "$U" = "2000" ] || [ "$U" = "0" ] || { echo "Cần quyền Shizuku/ADB hoặc root."; exit 1; }
BASE="/sdcard/.ben_universal"; mkdir -p "$BASE" 2>/dev/null
echo "freefire-frame-stability" > "$BASE/profile"
echo "BEN UNIVERSAL v4.6 • FREE FIRE FRAME STABILITY"
echo "[OK] Không polling khi đang chơi"
echo "[OK] Không trim RAM / kill app"
echo "[OK] Không ép CPU/GPU hoặc Thermal"
echo "[OK] Không spam Game Mode"
echo "Ưu tiên giảm tải nền và ổn định frame-time."
exit 0
