#!/system/bin/sh
# =============================================================================
#  panel-stats.sh - Consumo REAL do aparelho para a home do painel.
#
#  Só lê, nunca altera. Devolve uma linha JSON com o que o aparelho realmente
#  reporta (RAM, CPU, bateria, temperatura, refresh, armazenamento). Qualquer
#  campo que o aparelho não exponha volta "" — o painel mostra "—" em vez de
#  inventar número.
#
#  Uso: sh panel-stats.sh
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh" 2>/dev/null

_clean() { printf '%s' "$1" | tr -d '"\\\n\r' | cut -c1-120; }
_num()   { printf '%s' "$1" | tr -cd '0-9'; }

# --- RAM (/proc/meminfo é universal) ------------------------------------------
mi="$(sh_get 'cat /proc/meminfo' 2>/dev/null)"
[ -z "$mi" ] && mi="$(cat /proc/meminfo 2>/dev/null)"
_mem() { printf '%s\n' "$mi" | awk -v k="$1" '$1==k":"{print $2; exit}'; }
mem_total_kb="$(_num "$(_mem MemTotal)")"
mem_avail_kb="$(_num "$(_mem MemAvailable)")"
mem_free_kb="$(_num "$(_mem MemFree)")"
# usa MemAvailable quando existe; senão cai em MemFree
[ -z "$mem_avail_kb" ] && mem_avail_kb="$mem_free_kb"
ram_total_mb=$([ -n "$mem_total_kb" ] && echo $((mem_total_kb / 1024)))
ram_livre_mb=$([ -n "$mem_avail_kb" ] && echo $((mem_avail_kb / 1024)))
ram_uso_pct=""
if [ -n "$mem_total_kb" ] && [ -n "$mem_avail_kb" ] && [ "$mem_total_kb" -gt 0 ]; then
    ram_uso_pct=$(( (mem_total_kb - mem_avail_kb) * 100 / mem_total_kb ))
fi

# --- CPU: uso real, carga média e frequência ----------------------------------
# O uso vem da variação de /proc/stat entre duas amostras (busy/total). A carga
# média (loadavg) NÃO é porcentagem: ela conta processos prontos/em espera e
# passa de 100% com facilidade — usá-la como "%" dava número absurdo (ex.: 345%).
read_stat() {
    sh_get 'cat /proc/stat' 2>/dev/null | awk '/^cpu /{for(i=2;i<=NF;i++)t+=$i; printf "%d %d", t-$5-$6, t; exit}'
}
[ -z "$(read_stat)" ] && read_stat() {
    awk '/^cpu /{for(i=2;i<=NF;i++)t+=$i; printf "%d %d", t-$5-$6, t; exit}' /proc/stat 2>/dev/null
}
s1="$(read_stat)"; sleep 1; s2="$(read_stat)"
cpu_busy="$(printf '%s' "$s2" | awk '{print $1}')"
cpu_all="$(printf '%s' "$s2" | awk '{print $2}')"
b1="$(printf '%s' "$s1" | awk '{print $1}')"
a1="$(printf '%s' "$s1" | awk '{print $2}')"
cpu_uso_pct=""
if [ -n "$cpu_busy" ] && [ -n "$b1" ] && [ -n "$a1" ] && [ "$cpu_all" -gt "$a1" ] 2>/dev/null; then
    cpu_uso_pct=$(( (cpu_busy - b1) * 100 / (cpu_all - a1) ))
fi
load1="$(sh_get 'cat /proc/loadavg' 2>/dev/null | awk '{print $1}')"
[ -z "$load1" ] && load1="$(awk '{print $1}' /proc/loadavg 2>/dev/null)"
ncores="$(sh_get 'nproc' 2>/dev/null)"
[ -z "$ncores" ] && ncores="$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)"
cpu_gov="$(sh_get 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor' 2>/dev/null)"
[ -z "$cpu_gov" ] && cpu_gov="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"
cpu_cur="$(sh_get 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq' 2>/dev/null)"
[ -z "$cpu_cur" ] && cpu_cur="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null)"
cpu_max="$(sh_get 'cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq' 2>/dev/null)"
[ -z "$cpu_max" ] && cpu_max="$(cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq 2>/dev/null)"
cpu_cur_khz="$(_num "$cpu_cur")"; [ -n "$cpu_cur_khz" ] && cpu_cur_mhz=$((cpu_cur_khz / 1000))
cpu_max_khz="$(_num "$cpu_max")"; [ -n "$cpu_max_khz" ] && cpu_max_mhz=$((cpu_max_khz / 1000))

# --- bateria / temperatura ----------------------------------------------------
bat="$(sh_get 'dumpsys battery' 2>/dev/null)"
bat_level="$(printf '%s\n' "$bat" | awk -F': ' '/ level:/{print $2; exit}')"
bat_temp="$(printf '%s\n' "$bat" | awk -F': ' '/ temperature:/{print $2; exit}')"
bat_status="$(printf '%s\n' "$bat" | awk -F': ' '/ status:/{print $2; exit}')"
bat_temp_c=""
[ -n "$bat_temp" ] && bat_temp_c="$(awk "BEGIN{printf \"%.1f\", $bat_temp/10}")"
# `dumpsys battery` devolve o status como código (1..5); o painel mostrava "3".
case "$bat_status" in
    1) bat_status="Desconhecido" ;;
    2) bat_status="Carregando" ;;
    3) bat_status="Descarregando" ;;
    4) bat_status="Não carrega" ;;
    5) bat_status="Cheio" ;;
esac

# --- refresh atual ------------------------------------------------------------
refresh_hz="$(sh_get 'dumpsys display' 2>/dev/null | grep -m1 -oE 'fps=[0-9.]+' | cut -d= -f2)"
[ -z "$refresh_hz" ] && refresh_hz="$(sh_get 'dumpsys SurfaceFlinger' 2>/dev/null | grep -m1 -oE '[0-9.]+ fps' | cut -d' ' -f1)"
# Taxa travada: só conta como "fixa" quando peak == min. O Android deixa o
# peak_refresh_rate preenchido no modo adaptativo (min 60 / peak 120), e usar
# isso como "travada" faria o painel mentir. O pack sempre grava os dois iguais.
refresh_min="$(sh_get 'settings get system min_refresh_rate' 2>/dev/null)"
case "$refresh_min" in ""|null) refresh_min="" ;; esac
refresh_peak="$(sh_get 'settings get system peak_refresh_rate' 2>/dev/null)"
case "$refresh_peak" in ""|null) refresh_peak="" ;; esac
[ -n "$refresh_peak" ] && [ "$refresh_peak" != "$refresh_min" ] && refresh_peak=""

# --- armazenamento (data) -----------------------------------------------------
df_line="$(sh_get 'df -k /data' 2>/dev/null | tail -1)"
# só calcula se o df realmente devolveu números (senão fica vazio, não zero)
stor_total_mb="$(printf '%s\n' "$df_line" | awk 'NF>=4 && $2 ~ /^[0-9]+$/ {print int($2/1024); exit}')"
stor_livre_mb="$(printf '%s\n' "$df_line" | awk 'NF>=4 && $4 ~ /^[0-9]+$/ {print int($4/1024); exit}')"

# --- uptime -------------------------------------------------------------------
uptime_s="$(sh_get 'cat /proc/uptime' 2>/dev/null | awk '{print int($1)}')"

printf '{"ram_total_mb":"%s"'      "$(_clean "$ram_total_mb")"
printf ',"ram_livre_mb":"%s"'      "$(_clean "$ram_livre_mb")"
printf ',"ram_uso_pct":"%s"'       "$(_clean "$ram_uso_pct")"
printf ',"cpu_uso_pct":"%s"'       "$(_clean "$cpu_uso_pct")"
printf ',"load1":"%s"'             "$(_clean "$load1")"
printf ',"ncores":"%s"'            "$(_clean "$ncores")"
printf ',"cpu_gov":"%s"'           "$(_clean "$cpu_gov")"
printf ',"cpu_cur_mhz":"%s"'       "$(_clean "$cpu_cur_mhz")"
printf ',"cpu_max_mhz":"%s"'       "$(_clean "$cpu_max_mhz")"
printf ',"bat_level":"%s"'         "$(_clean "$bat_level")"
printf ',"bat_temp_c":"%s"'        "$(_clean "$bat_temp_c")"
printf ',"bat_status":"%s"'        "$(_clean "$bat_status")"
printf ',"refresh_hz":"%s"'        "$(_clean "$refresh_hz")"
printf ',"refresh_peak":"%s"'      "$(_clean "$refresh_peak")"
printf ',"stor_total_mb":"%s"'     "$(_clean "$stor_total_mb")"
printf ',"stor_livre_mb":"%s"'     "$(_clean "$stor_livre_mb")"
printf ',"uptime_s":"%s"'          "$(_clean "$uptime_s")"
printf '}\n'
exit 0
