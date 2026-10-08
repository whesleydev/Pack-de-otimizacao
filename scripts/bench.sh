#!/system/bin/sh
# =============================================================================
#  bench.sh - Mede o ANTES e o DEPOIS do pack, para provar resultado (ou não).
#
#  Coleta métricas reais do aparelho e gera um relatório comparativo. A ideia é
#  medir de verdade em vez de prometer número — o pack só vale se o número subir.
#
#  Uso:
#     sh bench.sh save antes        # coleta a linha de base
#     # ... aplica o pack (menu.sh all / deep-tune.sh gaming on) ...
#     sh bench.sh run depois        # coleta o estado atual
#     sh bench.sh report antes depois
#     sh bench.sh app com.dts.freefireth   # mede o tempo de abertura do app (ms)
#
#  Métricas: RAM livre/cache, temperatura, bateria, carga, governador/freq de CPU,
#  refresh, zRAM, load average. Relatórios em ~/.packotm/bench/<nome>.txt e .md
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

BENCH_DIR="$ST/bench"
mkdir -p "$BENCH_DIR" 2>/dev/null

# --- coleta de métricas -------------------------------------------------------
# cada linha: chave=valor (valor vazio = não disponível neste aparelho)
collect() {
    # RAM
    mem_avail="$(sh_get 'cat /proc/meminfo' | awk '/MemAvailable/{print $2}')"
    mem_total="$(sh_get 'cat /proc/meminfo' | awk '/MemTotal/{print $2}')"
    mem_free="$(sh_get 'cat /proc/meminfo' | awk '/MemFree/{print $2}')"
    [ -n "$mem_avail" ] && ram_livre_mb=$((mem_avail/1024))
    [ -n "$mem_total" ] && ram_total_mb=$((mem_total/1024))

    # carga do sistema
    loadavg="$(sh_get 'cat /proc/loadavg' | awk '{print $1}')"

    # bateria (nível + temperatura em °C, dumpsys reporta décimos de °C)
    bat="$(sh_get 'dumpsys battery')"
    bat_level="$(printf '%s\n' "$bat" | awk -F': ' '/ level:/{print $2}')"
    bat_temp="$(printf '%s\n' "$bat" | awk -F': ' '/ temperature:/{print $2}')"
    [ -n "$bat_temp" ] && bat_temp_c=$(awk "BEGIN{printf \"%.1f\", $bat_temp/10}")

    # governador e frequência da CPU (melhor esforço)
    cpu_gov="$(sh_get 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor')"
    cpu_cur="$(sh_get 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq')"
    cpu_max="$(sh_get 'cat /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq')"
    [ -n "$cpu_cur" ] && cpu_cur_mhz=$((cpu_cur/1000))
    [ -n "$cpu_max" ] && cpu_max_mhz=$((cpu_max/1000))

    # refresh atual
    hz="$(sh_get 'dumpsys display' | grep -m1 -oE 'fps=[0-9.]+' | cut -d= -f2)"

    # zRAM
    zram="$(sh_get 'cat /proc/swaps' | awk 'NR>1 && /zram/{print $3}')"
    [ -n "$zram" ] && zram_kb=$zram

    # imprime só o que existe
    printf 'ram_livre_mb=%s\n'   "${ram_livre_mb:-}"
    printf 'ram_total_mb=%s\n'   "${ram_total_mb:-}"
    printf 'loadavg=%s\n'        "${loadavg:-}"
    printf 'bat_level=%s\n'      "${bat_level:-}"
    printf 'bat_temp_c=%s\n'     "${bat_temp_c:-}"
    printf 'cpu_gov=%s\n'        "${cpu_gov:-}"
    printf 'cpu_cur_mhz=%s\n'    "${cpu_cur_mhz:-}"
    printf 'cpu_max_mhz=%s\n'    "${cpu_max_mhz:-}"
    printf 'refresh_hz=%s\n'     "${hz:-}"
    printf 'zram_kb=%s\n'        "${zram_kb:-}"
    printf 'data=%s\n'           "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'modelo=%s\n'         "$(sh_get 'getprop ro.product.model')"
    printf 'android=%s\n'        "$(sh_get 'getprop ro.build.version.release')"
}

snapshot() {  # snapshot <nome>
    n="${1:-$(date +%H%M%S)}"
    f="$BENCH_DIR/$n.txt"
    collect > "$f"
    say "métricas salvas em $f"
    sed 's/^/     /' "$f"
}

# --- relatório ----------------------------------------------------------------
val() { grep -m1 "^$2=" "$1" 2>/dev/null | cut -d= -f2-; }

delta_txt() {  # delta_txt <antes> <depois> [invert]  (invert: menor é melhor)
    a="$1"; b="$2"; inv="$3"
    case "$a$b" in *[!0-9.]*|'') echo "n/d"; return ;; esac
    d=$(awk "BEGIN{printf \"%+.1f\", $b-$a}")
    if [ "$inv" = "1" ]; then
        awk "BEGIN{exit !($b<$a)}" && printf '%s ↓ (melhor)' "$d" || printf '%s' "$d"
    else
        awk "BEGIN{exit !($b>$a)}" && printf '%s ↑ (melhor)' "$d" || printf '%s' "$d"
    fi
}

report() {
    a="$BENCH_DIR/${1:-antes}.txt"; b="$BENCH_DIR/${2:-depois}.txt"
    [ -f "$a" ] || { err "não achei $a (rode: bench.sh save ${1:-antes})"; exit 1; }
    [ -f "$b" ] || { err "não achei $b (rode: bench.sh run ${2:-depois})"; exit 1; }

    md="$BENCH_DIR/relatorio-$(date +%Y%m%d-%H%M%S).md"
    {
        printf '# Relatório de benchmark\n\n'
        printf 'Antes: `%s` · Depois: `%s`\n\n' "$1" "$2"
        printf '| Métrica | Antes | Depois | Δ |\n|---|---|---|---|\n'
    } > "$md"

    row() {  # row <rótulo> <chave> <invert>
        av="$(val "$a" "$2")"; bv="$(val "$b" "$2")"
        [ -z "$av" ] && [ -z "$bv" ] && return
        d="$(delta_txt "$av" "$bv" "$3")"
        printf '| %s | %s | %s | %s |\n' "$1" "${av:-n/d}" "${bv:-n/d}" "$d" >> "$md"
    }
    row "RAM livre (MB)"      ram_livre_mb 0
    row "Load average"        loadavg      1
    row "Bateria (%)"         bat_level    0
    row "Temperatura (°C)"    bat_temp_c   1
    row "CPU atual (MHz)"     cpu_cur_mhz  0
    row "CPU máximo (MHz)"    cpu_max_mhz  0
    row "Refresh (Hz)"        refresh_hz   0
    row "zRAM (KB)"           zram_kb      0

    printf '\n  %b▸%b  Relatório: %s\n\n' "$C_G" "$C_R" "$md"
    sed 's/^/  /' "$md"
    say "governador de CPU: $(val "$a" cpu_gov) → $(val "$b" cpu_gov)"
    warn "medição instantânea varia; para provar ganho, meça 3× e compare médias."
}

# --- tempo de abertura de app -------------------------------------------------
app_launch() {  # app_launch <pkg> [repetições]
    pkg="$1"; reps="${2:-3}"
    [ -z "$pkg" ] && { err "informe o pacote: bench.sh app <pkg>"; exit 1; }
    act="$(sh_get "cmd package resolve-activity --brief $pkg" | tail -1)"
    [ -z "$act" ] && { err "não resolvi a activity de $pkg"; exit 1; }
    say "medindo abertura de $pkg ($act), $reps×"
    i=1
    while [ "$i" -le "$reps" ]; do
        t="$(sh_get "am start -W -n $act" | awk -F': ' '/TotalTime/{print $2}')"
        [ -n "$t" ] && printf '  %dª: %s ms\n' "$i" "$t"
        i=$((i+1))
        sleep 2
    done
}

case "$1" in
    save)   snapshot "$2" ;;
    run)    snapshot "$2" ;;
    report) report "$2" "$3" ;;
    app)    app_launch "$2" "$3" ;;
    *)      printf '  Uso: %s save <nome> | run <nome> | report <antes> <depois> | app <pkg> [reps]\n' "$0" ;;
esac
