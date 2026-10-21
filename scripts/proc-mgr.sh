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
#     proc-mgr.sh ram <pkg> <mb>       # limite de RAM do app (root; 0 = sem limite)
#     proc-mgr.sh cpu <pkg> <grupo>    # cpuset: top-app | foreground | background
#     proc-mgr.sh renice <pkg> <nice>  # prioridade (-20..19; menor = mais forte)
#     proc-mgr.sh freeze <pkg>         # congela agora (SIGSTOP, sem matar)
#     proc-mgr.sh unfreeze <pkg>       # descongela (SIGCONT)
#     proc-mgr.sh status               # o que está aplicado agora
#     proc-mgr.sh restore              # remove limites/prioridades aplicados
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

# cgroup de memória do processo (para o limite)
cg_of() {
    p="$1"
    sh_get "cat /proc/$p/cgroup 2>/dev/null" | awk -F: '/memory/{print $3; exit}'
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

cmd_ram() {
    pkg="$1"; mb="$2"
    [ -z "$pkg" ] || [ -z "$mb" ] && { err "uso: ram <pkg> <mb> (0 = sem limite)"; return 1; }
    case "$mb" in ''|*[!0-9]*) err "mb inválido: $mb"; return 1 ;; esac
    require_root "limite de RAM por app" || return 1
    ok=0
    for p in $(pids_of "$pkg"); do
        cg="$(cg_of "$p")"
        [ -z "$cg" ] && continue
        f="/sys/fs/cgroup/memory$cg/memory.limit_in_bytes"
        [ -w "$f" ] || f="/sys/fs/cgroup$cg/memory.max"
        if [ -w "$f" ]; then
            if [ "$mb" = 0 ]; then
                sh_run "echo -1 > '$f'" >/dev/null 2>&1 || sh_run "echo max > '$f'" >/dev/null 2>&1
            else
                sh_run "echo $((mb * 1024 * 1024)) > '$f'" >/dev/null 2>&1
            fi
            echo "$pkg $mb" >> "$PM_ST/ram.txt"; ok=1
        fi
    done
    if [ "$ok" = 1 ]; then
        say "limite de RAM de $pkg = ${mb}MB"
    else
        warn "este kernel não expõe limite de RAM por app — nada aplicado"
        return 1
    fi
}

cmd_cpu() {
    pkg="$1"; grp="$2"
    case "$grp" in top-app|foreground|background) ;; *) err "uso: cpu <pkg> <top-app|foreground|background>"; return 1 ;; esac
    require_root "cpuset" || return 1
    n=0
    for p in $(pids_of "$pkg"); do
        for d in /dev/cpuset/$grp/tasks /dev/cpuset/$grp/cgroup.procs; do
            [ -w "$d" ] && { sh_run "echo $p > '$d'" >/dev/null 2>&1 && n=$((n+1)); }
        done
    done
    if [ "$n" -gt 0 ]; then
        echo "$pkg $grp" >> "$PM_ST/cpu.txt"
        say "$pkg agora no grupo de CPU '$grp'"
    else
        warn "cpuset não disponível — nada aplicado"
        return 1
    fi
}

cmd_renice() {
    pkg="$1"; n="$2"
    case "$n" in ''|*[!0-9-]*|-|--) err "uso: renice <pkg> <nice -20..19>"; return 1 ;; esac
    [ "$n" -lt -20 ] && n=-20; [ "$n" -gt 19 ] && n=19
    require_root "prioridade (nice)" || return 1
    c=0
    for p in $(pids_of "$pkg"); do
        sh_run "renice -n $n -p $p" >/dev/null 2>&1 && c=$((c+1))
    done
    [ "$c" -gt 0 ] && { echo "$pkg $n" >> "$PM_ST/nice.txt"; say "$pkg: nice $n ($c processo(s))"; } \
                   || { warn "não deu para mudar a prioridade"; return 1; }
}

cmd_freeze() {
    pkg="$1"
    [ -z "$pkg" ] && { err "uso: freeze <pkg>"; return 1; }
    require_root "congelar processo" || return 1
    c=0
    for p in $(pids_of "$pkg"); do
        sh_run "kill -STOP $p" >/dev/null 2>&1 && c=$((c+1))
    done
    [ "$c" -gt 0 ] && { echo "$pkg" >> "$PM_ST/frozen.txt"; say "$pkg congelado (SIGSTOP, $c processo(s))"; } \
                   || { warn "não deu para congelar (precisa de root)"; return 1; }
}

cmd_unfreeze() {
    pkg="$1"
    [ -z "$pkg" ] && { err "uso: unfreeze <pkg>"; return 1; }
    c=0
    for p in $(pids_of "$pkg"); do
        sh_run "kill -CONT $p" >/dev/null 2>&1 && c=$((c+1))
    done
    grep -vx "$pkg" "$PM_ST/frozen.txt" > "$PM_ST/frozen.txt.tmp" 2>/dev/null && mv "$PM_ST/frozen.txt.tmp" "$PM_ST/frozen.txt"
    say "$pkg descongelado ($c processo(s))"
}

cmd_status() {
    say "Limites e prioridades aplicados"
    for k in ram cpu nice frozen; do
        f="$PM_ST/$k.txt"
        if [ -s "$f" ]; then
            printf '  %s%s:%b\n' "$C_A" "$k" "$C_R"
            sed 's/^/     /' "$f"
        fi
    done
    [ -s "$PM_ST/ram.txt" ] || [ -s "$PM_ST/cpu.txt" ] || [ -s "$PM_ST/nice.txt" ] || [ -s "$PM_ST/frozen.txt" ] \
        || say "  (nada aplicado)"
}

cmd_restore() {
    require_root "restaurar limites" || return 1
    # descongela tudo o que foi congelado
    if [ -s "$PM_ST/frozen.txt" ]; then
        while read -r pkg; do
            [ -z "$pkg" ] && continue
            for p in $(pids_of "$pkg"); do sh_run "kill -CONT $p" >/dev/null 2>&1; done
        done < "$PM_ST/frozen.txt"
    fi
    # volta nice para 0
    if [ -s "$PM_ST/nice.txt" ]; then
        while read -r pkg _; do
            [ -z "$pkg" ] && continue
            for p in $(pids_of "$pkg"); do sh_run "renice -n 0 -p $p" >/dev/null 2>&1; done
        done < "$PM_ST/nice.txt"
    fi
    rm -f "$PM_ST"/*.txt "$PM_ST"/*.tmp 2>/dev/null
    say "limites, prioridades e congelamentos removidos"
}

case "$1" in
    top)      shift; cmd_top "$@" ;;
    info)     shift; cmd_info "$@" ;;
    ram)      shift; cmd_ram "$@" ;;
    cpu)      shift; cmd_cpu "$@" ;;
    renice)   shift; cmd_renice "$@" ;;
    freeze)   shift; cmd_freeze "$@" ;;
    unfreeze) shift; cmd_unfreeze "$@" ;;
    status)   cmd_status ;;
    restore)  cmd_restore ;;
    *)        sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report proc-mgr
exit $rc
