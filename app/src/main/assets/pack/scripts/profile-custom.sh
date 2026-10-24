#!/system/bin/sh
# =============================================================================
#  profile-custom.sh - Perfil PERSONALIZADO: você escolhe o que aplicar.
#
#  Diferente dos modos prontos (batata/competitivo/fluido/eco), aqui cada
#  recurso é opcional e ligado por conta própria. O script guarda a escolha em
#  $ST/profile-custom/config e aplica SÓ o que estiver ligado.
#
#  Recursos (chave=valor):
#     anim=off|half|normal     animações do sistema (off=0x, half=0.5x)
#     ram=padrao|gaming|batata limite de apps em 2º plano
#     hz=off|60|90|120|144     trava a tela numa taxa fixa
#     touch=none|balanced|headshot|spray|sniper|speed
#     telemetry=on|off         desliga logs/telemetria e scans
#     clean=off|fundo|suave|normal  limpeza de RAM/cache + suavização
#     hibernate=on|off         hiberna os apps de fundo
#
#  Uso:
#     profile-custom.sh show                    # mostra a configuração salva
#     profile-custom.sh set <chave> <valor>     # muda uma opção (sem aplicar)
#     profile-custom.sh set k1=v1 k2=v2 ...     # muda várias de uma vez
#     profile-custom.sh apply                   # aplica o que está ligado
#     profile-custom.sh on                      # atalho: set + apply
#     profile-custom.sh off                     # desfaz tudo e volta ao padrão
#
#  Aplicar parte de um estado limpo (reverte o pack antes), para não empilhar
#  ajustes de uma aplicação anterior. Tudo é reversível: `profile-custom.sh off`
#  (ou pack.sh restore).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

PC_ST="$ST/profile-custom"
mkdir -p "$PC_ST" 2>/dev/null
PC_CFG="$PC_ST/config"       # opções escolhidas (chave=valor)
PC_CUR="$PC_ST/current"      # marca que o perfil está ativo

PKG="${OTM_FF_PKG:-com.dts.freefireth}"
PC_A=0; PC_C=0; PC_F=0

# --- valores padrão (tudo desligado) ------------------------------------------
pc_defaults() {
    PC_ANIM=normal; PC_RAM=padrao; PC_HZ=off; PC_TOUCH=none
    PC_TELEMETRY=on; PC_CLEAN=off; PC_HIBERNATE=off
}

# --- lê a configuração salva por cima dos padrões ------------------------------
pc_load() {
    pc_defaults
    [ -f "$PC_CFG" ] || return 0
    while IFS= read -r _l; do
        case "$_l" in ''|'#'*) continue ;; esac
        _k="${_l%%=*}"; _v="${_l#*=}"
        case "$_k" in
            anim)      PC_ANIM="$_v" ;;
            ram)       PC_RAM="$_v" ;;
            hz)        PC_HZ="$_v" ;;
            touch)     PC_TOUCH="$_v" ;;
            telemetry) PC_TELEMETRY="$_v" ;;
            clean)     PC_CLEAN="$_v" ;;
            hibernate) PC_HIBERNATE="$_v" ;;
        esac
    done < "$PC_CFG"
}

# --- valida uma chave=valor ----------------------------------------------------
pc_valid() {
    case "$1" in
        anim)      case "$2" in off|half|normal) return 0 ;; esac ;;
        ram)       case "$2" in padrao|gaming|batata) return 0 ;; esac ;;
        hz)        case "$2" in off|60|90|120|144) return 0 ;; esac ;;
        touch)     case "$2" in none|balanced|headshot|spray|sniper|speed) return 0 ;; esac ;;
        telemetry) case "$2" in on|off) return 0 ;; esac ;;
        clean)     case "$2" in off|fundo|suave|normal) return 0 ;; esac ;;
        hibernate) case "$2" in on|off) return 0 ;; esac ;;
    esac
    return 1
}

# --- grava uma chave=valor (substitui a linha existente) -----------------------
pc_save() {
    _k="$1"; _v="$2"
    : > "$PC_CFG.new"
    _done=0
    if [ -f "$PC_CFG" ]; then
        while IFS= read -r _l; do
            case "$_l" in ''|'#'*) continue ;; esac
            if [ "${_l%%=*}" = "$_k" ]; then
                printf '%s=%s\n' "$_k" "$_v" >> "$PC_CFG.new"; _done=1
            else
                printf '%s\n' "$_l" >> "$PC_CFG.new"
            fi
        done < "$PC_CFG"
    fi
    [ "$_done" = "1" ] || printf '%s=%s\n' "$_k" "$_v" >> "$PC_CFG.new"
    mv "$PC_CFG.new" "$PC_CFG" 2>/dev/null
}

# --- roda um script do pack somando as contagens reais ------------------------
pc_run() {
    _s="$1"; shift
    _o="$(OTM_NO_COLOR=1 sh "$DIR/$_s" "$@" 2>&1)"
    _rc=$?
    printf '%s\n' "$_o" | grep -v '^#OTM-RESULT'
    _l="$(printf '%s\n' "$_o" | grep '^#OTM-RESULT' | tail -1)"
    [ -n "$_l" ] || return $_rc
    _k="$(printf '%s' "$_l" | sed 's/^#OTM-RESULT //')"
    for _t in $_k; do
        case "$_t" in
            applies=*) PC_A=$((PC_A + ${_t#applies=})) ;;
            changed=*) PC_C=$((PC_C + ${_t#changed=})) ;;
            failed=*)  PC_F=$((PC_F + ${_t#failed=})) ;;
        esac
    done
    return $_rc
}

# --- volta ao estado limpo antes de aplicar -----------------------------------
pc_reset() {
    say "Revertendo o pack para partir de um estado limpo"
    pc_run adb-tweaks.sh restore_all
    pc_run deep-tune.sh restore
    pc_run debloat.sh off
}

# --- salva várias opções "chave=valor" (valida cada uma) -----------------------
# Devolve 1 se alguma opção for inválida.
pc_set_all() {
    _bad=0
    for _p in "$@"; do
        case "$_p" in
            *=*) _k="${_p%%=*}"; _v="${_p#*=}" ;;
            *)   err "opção inválida: $_p"; _bad=1; continue ;;
        esac
        if pc_valid "$_k" "$_v"; then
            pc_save "$_k" "$_v"
        else
            err "opção inválida: $_p"; _bad=1
        fi
    done
    return $_bad
}

# --- salva as opções na ORDEM fixa usada pelo painel --------------------------
# O painel manda uma ação só, com os valores posicionais; aqui eles viram
# chave=valor. Omitir um argumento mantém o que já estava salvo.
pc_set_pos() {
    _i=1
    for _k in anim ram hz touch telemetry clean hibernate; do
        eval "_v=\${$_i:-}"
        if [ -n "$_v" ]; then
            if pc_valid "$_k" "$_v"; then pc_save "$_k" "$_v"
            else err "opção inválida: $_k=$_v"; return 1; fi
        fi
        _i=$((_i+1))
    done
    return 0
}

# --- aplica só o que estiver ligado -------------------------------------------
pc_apply() {
    pc_load
    _n=0
    say "Perfil PERSONALIZADO — aplicando só o que você ligou"

    # animações
    case "$PC_ANIM" in
        off)    pc_run adb-tweaks.sh perf_max; _n=$((_n+1)) ;;
        half)   pc_run adb-tweaks.sh perf;     _n=$((_n+1)) ;;
        normal) ;;
    esac

    # RAM / apps em 2º plano
    case "$PC_RAM" in
        gaming|batata) pc_run adb-tweaks.sh mem "$PC_RAM"; _n=$((_n+1)) ;;
        padrao) ;;
    esac

    # taxa de atualização da tela
    case "$PC_HZ" in
        off) ;;
        *) pc_run turbo.sh refresh_fixed "$PC_HZ"; _n=$((_n+1)) ;;
    esac

    # perfil de toque
    case "$PC_TOUCH" in
        none) ;;
        *) pc_run ff-touch.sh "$PC_TOUCH"; _n=$((_n+1)) ;;
    esac

    # telemetria
    case "$PC_TELEMETRY" in
        off) pc_run turbo.sh telemetry off; _n=$((_n+1)) ;;
        on)  ;;
    esac

    # limpeza + suavização
    case "$PC_CLEAN" in
        off) ;;
        *) pc_run clean.sh now "$PC_CLEAN"; _n=$((_n+1)) ;;
    esac

    # hibernar apps de fundo
    case "$PC_HIBERNATE" in
        on) pc_run turbo.sh hibernate now; _n=$((_n+1)) ;;
        off) ;;
    esac

    if [ "$_n" = "0" ]; then
        warn "nenhum recurso ligado — use 'profile-custom.sh set <chave> <valor>'"
        return 1
    fi
    printf '%s\n' "custom" > "$PC_CUR" 2>/dev/null
    say "$_n recurso(s) aplicado(s). Reverta em 'profile-custom.sh off'."
    return 0
}

# --- mostra a configuração -----------------------------------------------------
pc_show() {
    pc_load
    printf '\n  %s◆%s  %sPERFIL PERSONALIZADO%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    _on="$(cat "$PC_CUR" 2>/dev/null)"
    printf '  %sestado:%s %s\n\n' "$C_A" "$C_R" "${_on:+ativo (aplicado)}${_on:-não aplicado}"
    printf '   %-10s %s\n' "anim"      "$PC_ANIM"
    printf '   %-10s %s\n' "ram"       "$PC_RAM"
    printf '   %-10s %s\n' "hz"        "$PC_HZ"
    printf '   %-10s %s\n' "touch"     "$PC_TOUCH"
    printf '   %-10s %s\n' "telemetry" "$PC_TELEMETRY"
    printf '   %-10s %s\n' "clean"     "$PC_CLEAN"
    printf '   %-10s %s\n' "hibernate" "$PC_HIBERNATE"
    printf '\n  %sAplicar:%s profile-custom.sh apply\n' "$C_A" "$C_R"
    printf '  %sReverter:%s profile-custom.sh off\n\n' "$C_A" "$C_R"
}

# --- execução -----------------------------------------------------------------
acao="${1:-show}"; [ $# -gt 0 ] && shift

case "$acao" in
    show|status)
        pc_show ;;

    set)
        [ $# -gt 0 ] || { err "uso: profile-custom.sh set <chave> <valor> | set k=v ..."; exit 1; }
        # aceita "k=v" (um ou vários) ou "<chave> <valor>"
        case "$1" in
            *=*) pc_set_all "$@" || { pc_show; exit 1; } ;;
            *)   _k="$1"; _v="${2:-}"
                 if pc_valid "$_k" "$_v"; then pc_save "$_k" "$_v"
                 else err "opção inválida: $_k=$_v"; pc_show; exit 1; fi ;;
        esac
        say "Configuração salva"
        pc_show ;;

    apply|on)
        # O painel manda tudo numa chamada só: os 8 valores na ordem fixa
        # (anim ram hz touch telemetry clean hibernate). Também aceita
        # "apply k=v ..." e "apply" sem nada (usa o que já está salvo).
        if [ $# -gt 0 ]; then
            case "$1" in
                *=*) pc_set_all "$@" || { pc_show; exit 1; } ;;
                *)   pc_set_pos "$@" || { pc_show; exit 1; } ;;
            esac
        fi
        pc_reset; pc_apply ;;

    off)
        pc_reset; rm -f "$PC_CUR" 2>/dev/null
        say "Perfil personalizado desligado (aparelho de volta ao padrão)" ;;

    reset)
        rm -f "$PC_CFG" "$PC_CUR" 2>/dev/null
        say "Configuração apagada (tudo desligado)" ;;

    *) pc_show ;;
esac
rc=$?

OTM_V_APPLIES=$PC_A; OTM_V_CHANGED=$PC_C; OTM_V_FAILED=$PC_F
otm_v_report profile-custom
exit $rc
