#!/system/bin/sh
# =============================================================================
#  proc-mgr.sh - Gerenciador de processos (RAM e CPU)
#
#  Mostra o que cada processo REALMENTE consome e permite limitar/priorizar.
#  Nada de número inventado: o que o aparelho não expõe aparece como "—".
#
#  Uso:
#     proc-mgr.sh top [n]              # N processos que mais gastam (CPU/RAM)
#     proc-mgr.sh info <pkg>           # PID, RAM, nice, oom_score do app
#
#  Só leitura: limite de RAM, cpuset, nice e congelamento (SIGSTOP) exigem root,
#  então saíram deste pack.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

PM_ST="$ST/procmgr"
mkdir -p "$PM_ST" 2>/dev/null

# pids de um pacote (o app pode ter vários processos)
pids_of() {
    sh_get "pidof $1" 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+$'
}

# RAM (PSS, kB) de um processo, lida do /proc quando possível.
rss_of() {
    p="$1"
    v="$(sh_get "cat /proc/$p/statm 2>/dev/null" | awk '{print $2}')"
    [ -n "$v" ] && echo $((v * 4)) || echo ""
}

cmd_top() {
    n="${1:-12}"
    case "$n" in ''|*[!0-9]*) n=12 ;; esac
    say "Top $n processos (RAM/CPU reais)"
    # CPU: top em modo batch. RAM: coluna RES do mesmo top.
    out="$(sh_get "top -n 1 -b -o %CPU,RES,ARGS -s 9 2>/dev/null")"
    if [ -z "$out" ]; then
        out="$(sh_get "top -n 1 -b 2>/dev/null")"
    fi
    if [ -z "$out" ]; then
        warn "este aparelho não expõe 'top' para o shell — sem dados"
        return 1
    fi
    printf '%b%s%b\n' "$C_D" "   PID   %CPU   RES(kB)  NOME" "$C_R"
    printf '%s\n' "$out" | awk -v n="$n" '
        /PID/ {hdr=1; next}
        hdr && NF>=4 {print}
    ' | head -n "$n" | while read -r line; do
        [ -z "$line" ] && continue
        printf '  %s\n' "$line"
    done
    say "para congelar/limitar: proc-mgr.sh freeze|ram|renice <pkg>"
}

cmd_info() {
    pkg="$1"
    [ -z "$pkg" ] && { err "uso: info <pkg>"; return 1; }
    ps="$(pids_of "$pkg")"
    if [ -z "$ps" ]; then
        warn "$pkg não está rodando agora"
        return 1
    fi
    say "Processos de $pkg"
    for p in $ps; do
        r="$(rss_of "$p")"
        nice="$(sh_get "cat /proc/$p/stat 2>/dev/null" | awk '{print $19}')"
        oom="$(sh_get "cat /proc/$p/oom_score_adj 2>/dev/null")"
        printf '  %spid%b %-7s %sRAM%b %-9s %snice%b %-5s %soom%b %s\n' \
            "$C_A" "$C_R" "$p" "$C_A" "$C_R" "${r:+$((r/1024))MB}" "$C_A" "$C_R" "${nice:-—}" "$C_A" "$C_R" "${oom:-—}"
    done
}

case "$1" in
    top)      shift; cmd_top "$@" ;;
    info)     shift; cmd_info "$@" ;;
    *)        sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report proc-mgr
exit $rc
