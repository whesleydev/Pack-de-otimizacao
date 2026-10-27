#!/system/bin/sh
# =============================================================================
#  keep-alive.sh - Impede o app/jogo de "relogar" ao fechar e reabrir.
#
#  O que causa o relog: quando você sai do app, o Android o trata como
#  descartável e o mata. Ao voltar, ele abre do zero (a tela de login, o
#  carregamento, às vezes até sai da partida). Este módulo diz ao sistema
#  "esse app pode ficar": isenta do Doze, libera segundo plano e wake lock,
#  coloca no balde ativo de standby, tira do congelador/phantom killer e,
#  com root, baixa o oom_score_adj para o sistema não matá-lo.
#
#  Nada é inventado: cada ajuste é aplicado e lido de volta. O que o aparelho
#  não expõe aparece como "—".
#
#  Uso:
#     keep-alive.sh on <pkg>        # protege o app (anti-relog)
#     keep-alive.sh off <pkg>       # devolve o app ao comportamento normal
#     keep-alive.sh on <pkg> [jogo] # igual, mas também libera o Game Mode
#     keep-alive.sh status <pkg>    # mostra o que está aplicado AGORA
#     keep-alive.sh list            # apps protegidos (guardados pelo pack)
#     keep-alive.sh restore         # devolve TODOS ao normal
#
#  Requer privilégio de shell (Shizuku, ADB ou root). Sem ele, avisa e não
#  aplica nada.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
scope_begin keep-alive
otm_v_reset


KA_ST="$ST/keepalive"
mkdir -p "$KA_ST" 2>/dev/null
KA_FILE="$KA_ST/apps"

# --- utilidades ---------------------------------------------------------------
_valid_pkg() {
    case "$1" in
        ''|*[!A-Za-z0-9._]*) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}

# o app já está na lista de protegidos?
_ka_has() { [ -f "$KA_FILE" ] && grep -qxF "$1" "$KA_FILE" 2>/dev/null; }
_ka_add() { _ka_has "$1" || echo "$1" >> "$KA_FILE"; }
_ka_del() {
    [ -f "$KA_FILE" ] || return 0
    grep -vxF "$1" "$KA_FILE" > "$KA_FILE.tmp" 2>/dev/null
    mv "$KA_FILE.tmp" "$KA_FILE" 2>/dev/null
}

# appops/whitelist precisam de privilégio; sem ele, avisa uma vez.
_need_shell() {
    require_shell "manter o app vivo (anti-relog)" || return 1
    return 0
}

# --- aplicação ----------------------------------------------------------------
# Cada item: <descrição> <comando de reversão> <comando de aplicação>
ka_run() {
    otm_v_inc apply
    bkp_raw "$2"
    if sh_run "$3" >/dev/null 2>&1; then
        otm_v_inc changed
        printf '   %bOK%b %s\n' "$C_G" "$C_R" "$1"
    else
        otm_v_inc failed
        printf '   %bX%b %s\n' "$C_RD" "$C_R" "$1"
    fi
}

# Sobe a prioridade de memória dos processos do app/jogo: -1000 é "não mate por
# memória" (adj negativo). Lê o valor antigo de cada PID e guarda a reversão.
ka_oom_prio() {
    pkg="$1"
    n=0
    for p in $(sh_get "pidof $pkg" | tr ' ' '\n'); do
        case "$p" in '' | *[!0-9]*) continue ;; esac
        old="$(sh_get "cat /proc/$p/oom_score_adj 2>/dev/null")"
        case "$old" in '' | *[!0-9-]*) continue ;; esac
        bkp_raw "echo $old > /proc/$p/oom_score_adj 2>/dev/null"
        sh_run "echo -900 > /proc/$p/oom_score_adj" >/dev/null 2>&1
        now="$(sh_get "cat /proc/$p/oom_score_adj 2>/dev/null")"
        [ "$now" = "-900" ] && n=$((n + 1))
    done
    if [ "$n" -gt 0 ]; then
        otm_v_inc apply; otm_v_inc changed
        printf '   %bOK%b prioridade de memória (oom) · %s processo(s)\n' "$C_G" "$C_R" "$n"
    else
        printf '   %b·%b prioridade de memória (oom): %s não está rodando\n' "$C_D" "$C_R" "$pkg"
    fi
}

cmd_on() {
    pkg="$1"; modo="$2"
    _valid_pkg "$pkg" || { err "pacote inválido: '$pkg'"; return 1; }
    _need_shell || return 1

    say "Mantendo $pkg vivo (anti-relog)"
    bkp_begin

    # 1) fora do Doze (não é colocado em modo de espera)
    ka_run "isento do Doze · $pkg" \
        "cmd deviceidle whitelist -$pkg" "cmd deviceidle whitelist +$pkg"

    # 2) pode rodar e iniciar em segundo plano
    ka_run "rodar em 2º plano · $pkg" \
        "cmd appops set $pkg RUN_IN_BACKGROUND default" "cmd appops set $pkg RUN_IN_BACKGROUND allow"
    ka_run "rodar sempre em 2º plano · $pkg" \
        "cmd appops set $pkg RUN_ANY_IN_BACKGROUND default" "cmd appops set $pkg RUN_ANY_IN_BACKGROUND allow"
    ka_run "iniciar em 2º plano · $pkg" \
        "cmd appops set $pkg START_FOREGROUND default" "cmd appops set $pkg START_FOREGROUND allow"

    # 3) wake lock (segura a tela/CPU quando precisa, sem o sistema cortar)
    ka_run "wake lock · $pkg" \
        "cmd appops set $pkg WAKE_LOCK default" "cmd appops set $pkg WAKE_LOCK allow"

    # 4) balde de standby ativo (o Android não o rebaixa sozinho)
    old_bucket="$(sh_get "am get-standby-bucket $pkg" | tr -d ' ')"
    ka_run "standby ativo · $pkg (antes: ${old_bucket:-—})" \
        "am set-standby-bucket $pkg ${old_bucket:-active}" "am set-standby-bucket $pkg active"

    # 5) fora do congelador (cache freezer do sistema e plugin do pack)
    ka_run "fora do cache freezer · $pkg" \
        "settings put global cached_apps_freezer enabled" "settings put global cached_apps_freezer disabled"
    if [ -f "$ST/blacklist" ]; then
        grep -vxF "$pkg" "$ST/blacklist" > "$ST/blacklist.tmp" 2>/dev/null
        mv "$ST/blacklist.tmp" "$ST/blacklist" 2>/dev/null
        grep -qxF "$pkg" "$ST/whitelist" 2>/dev/null || echo "$pkg" >> "$ST/whitelist"
        printf '   %bOK%b whitelist do congelador · %s\n' "$C_G" "$C_R" "$pkg"
    fi
    sh_run "pm unsuspend --user 0 $pkg" >/dev/null 2>&1
    sh_run "pm enable --user 0 $pkg" >/dev/null 2>&1

    # 6b) o sistema não mata por engano: sobe a prioridade de memória dos
    # processos do app/jogo (oom_score_adj). Sem isso o LMK pode escolher o
    # jogo quando falta RAM — é uma das causas do relog em partida.
    # Só com root: /proc/<pid>/oom_score_adj não é gravável por shell comum.
    if sh_ok; then
        ka_oom_prio "$pkg"
    else
        printf '   %b·%b prioridade de memória (oom) precisa de root (pulado)\n' "$C_D" "$C_R"
    fi

    # 7) jogo: libera o Game Mode (opcional)
    if [ "$modo" = "jogo" ] || [ "$modo" = "game" ]; then
        sh_run "cmd game set --mode performance $pkg" >/dev/null 2>&1
        printf '   %bOK%b Game Mode performance · %s\n' "$C_G" "$C_R" "$pkg"
    fi

    _ka_add "$pkg"
    say "$pkg protegido. Para desfazer: keep-alive.sh off $pkg"
}

cmd_off() {
    pkg="$1"
    _valid_pkg "$pkg" || { err "pacote inválido: '$pkg'"; return 1; }
    _need_shell || return 1
    say "Devolvendo $pkg ao normal"
    sh_run "cmd deviceidle whitelist -$pkg" >/dev/null 2>&1
    sh_run "cmd appops set $pkg RUN_IN_BACKGROUND default" >/dev/null 2>&1
    sh_run "cmd appops set $pkg RUN_ANY_IN_BACKGROUND default" >/dev/null 2>&1
    sh_run "cmd appops set $pkg START_FOREGROUND default" >/dev/null 2>&1
    sh_run "cmd appops set $pkg WAKE_LOCK default" >/dev/null 2>&1
    sh_run "am set-standby-bucket $pkg active" >/dev/null 2>&1
    _ka_del "$pkg"
    say "pronto (o app volta a ser tratado como os outros)"
}

cmd_status() {
    pkg="$1"
    _valid_pkg "$pkg" || { err "uso: status <pkg>"; return 1; }
    printf '  %s◆%s  %sANTI-RELOG · %s%s\n' "$C_A" "$C_R" "$C_A" "$pkg" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    wl="$(sh_get "cmd deviceidle whitelist" | grep -q "$pkg" && echo isento || echo não)"
    printf '  %sDoze:%s %s\n' "$C_A" "$C_R" "$wl"
    for op in RUN_IN_BACKGROUND RUN_ANY_IN_BACKGROUND START_FOREGROUND WAKE_LOCK; do
        v="$(sh_get "cmd appops get $pkg $op" | awk '{print $NF}')"
        printf '  %s%s:%s %s\n' "$C_A" "$op" "$C_R" "${v:-—}"
    done
    b="$(sh_get "am get-standby-bucket $pkg" | tr -d ' ')"
    printf '  %sstandby:%s %s\n' "$C_A" "$C_R" "${b:-—}"
    pids="$(sh_get "pidof $pkg" | tr ' ' ',')"
    printf '  %sPIDs:%s %s\n' "$C_A" "$C_R" "${pids:-— (não está rodando)}"
    if _ka_has "$pkg"; then
        printf '  %sguardado pelo pack:%s sim\n' "$C_A" "$C_R"
    else
        printf '  %sguardado pelo pack:%s não\n' "$C_A" "$C_R"
    fi
}

cmd_list() {
    if [ -s "$KA_FILE" ]; then
        say "Apps protegidos (anti-relog)"
        sed 's/^/    /' "$KA_FILE"
    else
        say "nenhum app protegido ainda"
    fi
    say "proteja com: keep-alive.sh on <pkg>"
}

cmd_restore() {
    _need_shell || return 1
    if [ -s "$KA_FILE" ]; then
        while read -r p; do
            [ -z "$p" ] && continue
            sh_run "cmd deviceidle whitelist -$p" >/dev/null 2>&1
            sh_run "cmd appops set $p RUN_IN_BACKGROUND default" >/dev/null 2>&1
            sh_run "cmd appops set $p RUN_ANY_IN_BACKGROUND default" >/dev/null 2>&1
            sh_run "cmd appops set $p START_FOREGROUND default" >/dev/null 2>&1
            sh_run "cmd appops set $p WAKE_LOCK default" >/dev/null 2>&1
            sh_run "am set-standby-bucket $p active" >/dev/null 2>&1
            printf '   %s%s%s\n' "$C_D" "$p" "$C_R"
        done < "$KA_FILE"
    fi
    : > "$KA_FILE" 2>/dev/null
    say "todos os apps voltaram ao comportamento normal"
}

# --- main ---------------------------------------------------------------------
case "$1" in
    on)      shift; cmd_on "$1" "$2" ;;
    off)     shift; cmd_off "$1" ;;
    status)  shift; cmd_status "$1" ;;
    list)    cmd_list ;;
    restore) cmd_restore ;;
    *)       sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report keep-alive
exit $rc
