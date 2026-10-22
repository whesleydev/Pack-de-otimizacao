#!/system/bin/sh
# =============================================================================
#  service.sh - Aplica a config salva no boot. Se CFG_LOOP=1, reafirma em loop.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"

# espera boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
until [ -d "/sdcard/Android" ] || [ -d "/storage/emulated/0/Android" ]; do sleep 1; done

APPLY="/data/adb/packotm/apply.sh"
[ -f "$APPLY" ] || APPLY="$DIR/apply.sh"

sh "$APPLY" apply >/dev/null 2>&1

# loop opcional
STATE="/data/adb/packotm"
[ -d "$STATE" ] || STATE="$DIR/state"
. "$STATE/webui.conf" 2>/dev/null
if [ "$CFG_LOOP" = "1" ]; then
    while :; do
        sleep 120
        sh "$APPLY" apply >/dev/null 2>&1
    done
fi
