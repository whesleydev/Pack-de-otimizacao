#!/system/bin/sh
# =============================================================================
#  proc-mgr.sh - Gerenciador de processos (RAM e CPU)
#
#  Mostra o que cada processo REALMENTE consome e permite limitar/priorizar.
#  Nada de número inventado: o que o aparelho não expõe aparece como "—".
#
#  Uso:
#     proc-mgr.sh top [n]              # N processos que mais gastam (CPU/RAM)
#     proc-mgr.sh list [n]             # apps de usuário RODANDO agora (RAM, exceção)
#     proc-mgr.sh apps                 # TODOS os apps instalados (proteger/liberar)
#     proc-mgr.sh info <pkg>           # PID, RAM, nice, oom_score do app
#     proc-mgr.sh kill                 # encerra o 2º plano (poupa exceções/1º plano/jogo)
#     proc-mgr.sh keep <pkg>           # exceção: este app NUNCA é encerrado
#     proc-mgr.sh unkeep <pkg>         # remove a exceção
#     proc-mgr.sh keep-fg              # cria exceção para o app em 1º plano agora
#     proc-mgr.sh keep-list            # lista as exceções
#     proc-mgr.sh keep-clear           # apaga todas as exceções
#
#  "list" imprime uma linha legível por máquina por app rodando:
#     #OTM-PROC pkg=<pacote> ram=<MB> protected=<0|1>
#  O painel flutuante usa essas linhas para montar a lista com nome e RAM.
#
#  Só leitura (fora o kill/keep): limite de RAM, cpuset, nice e congelamento
#  (SIGSTOP) exigem root, então saíram deste pack.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
scope_begin proc-mgr
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

# --- exceções ("X app não vai encerrar") --------------------------------------
# Guardadas ao lado do anti-relog, que já é a lista do que a limpeza respeita:
# assim o "encerrar todos" e o clean/ram-boost poupam os mesmos apps.
PM_KEEP="$ST/procmgr/keep"

_pm_valid() {
    case "$1" in ''|*[!A-Za-z0-9._]*) return 1 ;; *.*) return 0 ;; *) return 1 ;; esac
}
_pm_keep_has() { [ -f "$PM_KEEP" ] && grep -qxF "$1" "$PM_KEEP" 2>/dev/null; }
_pm_keep_add() { _pm_keep_has "$1" || { mkdir -p "$PM_ST" 2>/dev/null; echo "$1" >> "$PM_KEEP"; }; }
_pm_keep_del() {
    [ -f "$PM_KEEP" ] || return 0
    grep -vxF "$1" "$PM_KEEP" > "$PM_KEEP.tmp" 2>/dev/null
    mv "$PM_KEEP.tmp" "$PM_KEEP" 2>/dev/null
}

# RAM (PSS) somada de todos os processos do app, em MB (vazio se não der).
pm_ram_mb() {
    total=0; achou=""
    for p in $(pids_of "$1"); do
        r="$(rss_of "$p")"
        [ -n "$r" ] || continue
        total=$((total + r)); achou=1
    done
    [ -n "$achou" ] && echo $((total / 1024))
}

# cmd_list [n] -> apps de usuário RODANDO agora, com RAM e se estão protegidos.
cmd_list() {
    n="${1:-40}"
    case "$n" in ''|*[!0-9]*) n=40 ;; esac
    fg="$(otm_fg_pkg)"
    i=0
    for p in $(sh_get 'pm list packages -3' | sed 's/^package://'); do
        [ -n "$p" ] || continue
        pids="$(pids_of "$p")"
        [ -n "$pids" ] || continue
        i=$((i + 1))
        [ "$i" -gt "$n" ] && break
        prot=0
        _pm_keep_has "$p" && prot=1
        case " $fg " in *" $p "*) prot=1 ;; esac
        printf '#OTM-PROC pkg=%s ram=%s protected=%s\n' "$p" "$(pm_ram_mb "$p")" "$prot"
    done
    if [ "$i" -eq 0 ]; then
        say "nenhum app de usuário rodando agora (fora o próprio pack)"
    else
        say "$i app(s) rodando — protegidos ficam de fora do encerrar"
    fi
}

cmd_keep() {
    pkg="$1"
    _pm_valid "$pkg" || { err "uso: keep <pkg>"; return 1; }
    _pm_keep_add "$pkg"
    otm_v_inc apply; otm_v_inc changed
    say "exceção criada: $pkg nunca será encerrado"
}

cmd_unkeep() {
    pkg="$1"
    _pm_valid "$pkg" || { err "uso: unkeep <pkg>"; return 1; }
    _pm_keep_del "$pkg"
    otm_v_inc apply; otm_v_inc changed
    say "exceção removida: $pkg"
}

cmd_keep_fg() {
    pkg="$(otm_fg_pkg)"
    # se o dumpsys não diz quem está na tela (tela bloqueada, formato novo do
    # Android), cai no jogo escolhido em vez de dar erro: no meio da partida o
    # botão "exceção (1º plano)" falhava e não protegia nada.
    [ -n "$pkg" ] || pkg="$(game_pkg_saved)"
    [ -n "$pkg" ] || { warn "não consegui identificar o app em primeiro plano"; return 1; }
    _pm_valid "$pkg" || { err "pacote inválido em 1º plano: '$pkg'"; return 1; }
    _pm_keep_add "$pkg"
    otm_v_inc apply; otm_v_inc changed
    say "exceção criada para o app em 1º plano: $pkg"
}

cmd_keep_list() {
    if [ -s "$PM_KEEP" ]; then
        say "Exceções (nunca encerrar):"
        sed 's/^/    /' "$PM_KEEP"
    else
        say "nenhuma exceção ainda"
    fi
    say "crie com: proc-mgr.sh keep <pkg>"
}

cmd_keep_clear() {
    n=0
    [ -s "$PM_KEEP" ] && n="$(grep -c . "$PM_KEEP")"
    : > "$PM_KEEP" 2>/dev/null
    otm_v_inc apply
    [ "$n" -gt 0 ] && otm_v_inc changed
    say "exceções apagadas ($n)"
}

# cmd_kill -> encerra o 2º plano de uma vez, poupando exceções, o app em 1º
# plano, o jogo e o essencial do sistema. É o "encerrar todos" do flutuante.
cmd_kill() {
    require_shell "encerrar apps de fundo" || return 1
    keep="$(otm_keep_list) $(cat "$PM_KEEP" 2>/dev/null | tr '\n' ' ')"
    say "Encerrando apps de fundo (exceções e 1º plano ficam)"
    n="$(otm_bg_kill $keep)"
    otm_v_inc apply
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then otm_v_inc changed; else otm_v_inc failed; fi
    say "$n app(s) encerrado(s)"
    r="$(otm_ram_livre_mb)"
    [ -n "$r" ] && say "RAM livre agora: ${r}MB"
}

# cmd_apps -> TODOS os apps de usuário instalados, com ou sem exceção. É o que
# permite proteger um app que NÃO está rodando agora (ex.: o app do banco, que
# precisa continuar vivo quando a limpeza de RAM rodar mais tarde).
cmd_apps() {
    i=0
    for p in $(sh_get 'pm list packages -3' | sed 's/^package://' | sort); do
        [ -n "$p" ] || continue
        i=$((i + 1))
        prot=0
        _pm_keep_has "$p" && prot=1
        printf '#OTM-APP pkg=%s protected=%s\n' "$p" "$prot"
    done
    if [ "$i" -eq 0 ]; then
        say "nenhum app de usuário instalado"
    else
        say "$i app(s) instalado(s) — toque para proteger/liberar"
    fi
}

case "$1" in
    top)        shift; cmd_top "$@" ;;
    list)       shift; cmd_list "$@" ;;
    apps)       shift; cmd_apps "$@" ;;
    info)       shift; cmd_info "$@" ;;
    kill)       shift; cmd_kill "$@" ;;
    keep)       shift; cmd_keep "$@" ;;
    unkeep)     shift; cmd_unkeep "$@" ;;
    keep-fg)    shift; cmd_keep_fg "$@" ;;
    keep-list)  shift; cmd_keep_list "$@" ;;
    keep-clear) shift; cmd_keep_clear "$@" ;;
    *)          sed -n '3,26p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report proc-mgr
exit $rc
