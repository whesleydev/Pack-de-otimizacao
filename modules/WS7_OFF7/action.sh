#!/system/bin/sh
# WS7_OFF7 Quick Action Script

get_free_ram() {
    local avail_kb=0
    while read -r line; do
        case "$line" in
            MemAvailable:*)
                set -- $line
                avail_kb=$2
                break
                ;;
        esac
    done < /proc/meminfo
    echo $((avail_kb / 1024))
}

RAM_BEFORE=$(get_free_ram)

echo "=================================================="
echo "  WS7_OFF7 · SUPREME SYSTEM PURGE & OVERDRIVE"
echo "=================================================="

KILLED=0
for app in $(cmd package list packages -3 | cut -f 2 -d ":"); do
    case "$app" in
        frb.axeron.manager|com.sunprot.manager|com.termux) continue ;;
        *)
            cmd activity force-stop "$app" >/dev/null 2>&1
            cmd activity kill "$app" >/dev/null 2>&1
            KILLED=$((KILLED + 1))
            ;;
    esac
done
echo " [✔] Terminated $KILLED idle user apps."

cmd activity trim-caches >/dev/null 2>&1
pm trim-caches 9999999999 >/dev/null 2>&1
sm fstrim >/dev/null 2>&1
logcat -c >/dev/null 2>&1
sync >/dev/null 2>&1

RAM_AFTER=$(get_free_ram)
FREED=$((RAM_AFTER - RAM_BEFORE))
[ "$FREED" -lt 0 ] && FREED=0

echo " [✔] RAM purged! Released approx +${FREED} MB."
echo "=================================================="
