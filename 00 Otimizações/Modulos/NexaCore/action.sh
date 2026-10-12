#!/system/bin/sh
# Credits to @EnriqueBrach - NexaCore System Optimizer

MODDIR=${0%/*}

R='\e[1;31m'
W='\e[1;37m'
Y='\e[1;33m'
N='\e[0m'

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

echo ""
echo -e "${R}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${W}    NEXACORE ${R}│${Y} SYSTEM OPTIMIZATION${N}"
echo -e "${R}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""
echo -e "${R}◆${W} Status: ${Y}Optimizing system resources...${N}"
echo ""

echo -e "${R}◆${W} Closing background user applications...${N}"
KILLED_COUNT=0
for app in $(cmd package list packages -3 | cut -f 2 -d ":"); do
    case "$app" in
        frb.axeron.manager|com.sunprot.manager)
            continue
            ;;
        *)
            cmd activity force-stop "$app" >/dev/null 2>&1
            cmd activity kill "$app" >/dev/null 2>&1
            KILLED_COUNT=$((KILLED_COUNT + 1))
            ;;
    esac
done
echo -e "  ${Y}└─${W} Terminated ${Y}${KILLED_COUNT}${W} user applications${N}"
echo ""

echo -e "${R}◆${W} Purging system memory & app caches...${N}"
cmd activity trim-caches >/dev/null 2>&1
pm trim-caches 9999999999 >/dev/null 2>&1
dumpsys usagestats --reset >/dev/null 2>&1
echo -e "  ${Y}└─${W} Cache buffers & usage stats reset${N}"
echo ""

echo -e "${R}◆${W} Trimming filesystem storage (fstrim)...${N}"
sm fstrim >/dev/null 2>&1
echo -e "  ${Y}└─${W} NAND flash storage trimmed successfully${N}"
echo ""

echo -e "${R}◆${W} Clearing logcat logs & syncing storage...${N}"
logcat -c >/dev/null 2>&1
sync >/dev/null 2>&1
echo -e "  ${Y}└─${W} System logs cleared & buffers flushed${N}"
echo ""

RAM_AFTER=$(get_free_ram)
FREED=$((RAM_AFTER - RAM_BEFORE))
if [ "$FREED" -lt 0 ]; then FREED=0; fi

echo -e "${R}──────────────────────────────────────────────────${N}"
echo -e "  ${Y}✔${W} Optimization Completed Successfully!${N}"
if [ "$FREED" -gt 0 ]; then
    echo -e "  ${Y}★${W} Released approx. ${Y}+${FREED} MB${W} of RAM${N}"
fi
echo -e "${R}──────────────────────────────────────────────────${N}"
echo -e "${R}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo -e "${W} Powered by NexaCore ${R}│${W} Credits to @EnriqueBrach${N}"
echo -e "${R}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${N}"
echo ""