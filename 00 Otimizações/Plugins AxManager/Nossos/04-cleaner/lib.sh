#!/system/bin/sh
# =============================================================================
#  lib.sh - Limpeza & Memória. Só limpa; não muda configuração (nada a reverter).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm_cleaner"
mkdir -p "$STATE" 2>/dev/null || STATE="$DIR/state"
mkdir -p "$STATE" 2>/dev/null
CFG="$STATE/config"

CLEAN_INTERVAL=900   # 15 min
TRIM_CACHES=1
CLEAR_LOG=1
FSTRIM=1
KILL_BG=0
BG_APPS="com.instagram.android com.facebook.katana com.facebook.orca com.twitter.android"

[ -f "$CFG" ] && . "$CFG" 2>/dev/null

log() { echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$STATE/loop.log"; }

save_default_config() {
    [ -f "$CFG" ] && return 0
    {
        echo "CLEAN_INTERVAL=$CLEAN_INTERVAL"
        echo "TRIM_CACHES=$TRIM_CACHES"
        echo "CLEAR_LOG=$CLEAR_LOG"
        echo "FSTRIM=$FSTRIM"
        echo "KILL_BG=$KILL_BG"
        echo "BG_APPS=\"$BG_APPS\""
    } > "$CFG"
}

boot_wait() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
}

free_ram_mb() {
    while read -r line; do
        case "$line" in
            MemAvailable:*) set -- $line; echo $(( $2 / 1024 )); return ;;
        esac
    done < /proc/meminfo
    echo 0
}

run_clean() {
    before=$(free_ram_mb)
    [ "$TRIM_CACHES" = "1" ] && {
        cmd activity trim-caches >/dev/null 2>&1
        pm trim-caches 999999999 >/dev/null 2>&1
    }
    [ "$CLEAR_LOG" = "1" ] && logcat -c >/dev/null 2>&1
    [ "$FSTRIM" = "1" ] && {
        for m in /data /cache; do
            fstrim -v "$m" >/dev/null 2>&1
        done
    }
    if [ "$KILL_BG" = "1" ]; then
        for a in $BG_APPS; do am force-stop "$a" >/dev/null 2>&1; done
    fi
    sync >/dev/null 2>&1
    after=$(free_ram_mb)
    log "clean: RAM $before -> $after MB (liberou $((after - before)) MB)"
}
