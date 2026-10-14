#!/system/bin/sh
# =============================================================================
#  common.sh - Biblioteca compartilhada do Pack de Otimização
#  Detecta automaticamente como executar comandos privilegiados:
#    1) adb shell   (PC -> celular, depuração sem fio/USB)
#    2) rish        (Shizuku, roda direto no celular)
#    3) su -c       (root / Magisk / KernelSU / APatch)
#    4) sh -c       (shell local, sem privilégio)
#  Todos os scripts fazem ". ./common.sh" e usam sh_run / sh_get.
#  Variável de override: OTM_MODE=adb|rish|su|local
# =============================================================================

# --- configuração (persistida pelo painel > Configs) --------------------------
# Carrega ~/.packotm/config, se existir. Chaves: OTM_MODE (adb|rish|su|local),
# OTM_ADB_SERIAL (serial ou host:porta), OTM_RISH (caminho do rish do Shizuku).
OTM_ST="${HOME:-/data/data/com.termux/files/home}/.packotm"
OTM_CFG="$OTM_ST/config"
[ -f "$OTM_CFG" ] && . "$OTM_CFG" 2>/dev/null

# --- detecção -----------------------------------------------------------------
# _with_timeout <segundos> <cmd...>  -> roda o cmd com timeout, se houver `timeout`.
# Evita que `su`/`adb` pendurem esperando senha/servidor (script travado é pior que
# script sem privilégio). Sem `timeout` disponível, roda direto.
_with_timeout() {
    _otm_to="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$_otm_to" "$@"
    else
        "$@"
    fi
}

_otm_rish() { [ -n "$OTM_RISH" ] && printf '%s' "$OTM_RISH" || printf 'rish'; }

_su_works() {
    command -v su >/dev/null 2>&1 || return 1
    [ "$(id -u 2>/dev/null)" = "0" ] && return 1        # já é root
    [ "$(_with_timeout 3 su -c 'id -u' 2>/dev/null)" = "0" ] || return 1
}

_rish_works() {
    r="$(_otm_rish)"
    if [ -x "$r" ]; then
        [ -n "$(_with_timeout 5 "$r" -c 'id -u' 2>/dev/null)" ] || return 1
        return 0
    fi
    command -v rish >/dev/null 2>&1 || return 1
    [ -n "$(_with_timeout 5 rish -c 'id -u' 2>/dev/null)" ] || return 1
}

# ADB: com serial fixo (Wi-Fi) ou o primeiro dispositivo conectado.
_otm_adb() {
    if [ -n "$OTM_ADB_SERIAL" ]; then
        _with_timeout 10 adb -s "$OTM_ADB_SERIAL" "$@"
    else
        _with_timeout 10 adb "$@"
    fi
}

_adb_works() {
    command -v adb >/dev/null 2>&1 || return 1
    if [ -n "$OTM_ADB_SERIAL" ]; then
        [ "$(_with_timeout 6 adb -s "$OTM_ADB_SERIAL" get-state 2>/dev/null)" = "device" ] && return 0
        # tenta conectar uma vez (depuração por Wi-Fi)
        case "$OTM_ADB_SERIAL" in *:*) _with_timeout 6 adb connect "$OTM_ADB_SERIAL" >/dev/null 2>&1 ;; esac
        [ "$(_with_timeout 6 adb -s "$OTM_ADB_SERIAL" get-state 2>/dev/null)" = "device" ] && return 0
        return 1
    fi
    _with_timeout 5 adb devices 2>/dev/null \
        | awk 'NR>1 && $2=="device"{print $1}' | head -1 | grep -q .
}

if [ -n "$OTM_MODE" ]; then
    RUN_MODE="$OTM_MODE"
elif _rish_works; then
    RUN_MODE="rish"
elif _adb_works; then
    RUN_MODE="adb"
elif _su_works; then
    RUN_MODE="su"
else
    RUN_MODE="local"
fi

# --- execução -----------------------------------------------------------------
# _otm_shell "<cmd>" -> executa no alvo conforme o modo. Base de sh_run/sh_get.
_otm_shell() {
    case "$RUN_MODE" in
        adb)   if [ -n "$OTM_ADB_SERIAL" ]; then _with_timeout 20 adb -s "$OTM_ADB_SERIAL" shell "$1"
               else _with_timeout 20 adb shell "$1"; fi ;;
        rish)  r="$(_otm_rish)"
               if [ -x "$r" ]; then _with_timeout 20 "$r" -c "$1"
               else _with_timeout 20 rish -c "$1"; fi ;;
        su)    _with_timeout 20 su -c "$1" ;;
        *)     sh -c "$1" ;;
    esac
}

sh_run() { _otm_shell "$1" 2>/dev/null; }
sh_get() { _otm_shell "$1" 2>/dev/null | tr -d '\r'; }

sh_ok() { [ "$(sh_get 'id -u')" = "0" ]; }
have()  { command -v "$1" >/dev/null 2>&1; }

# tem privilégio de shell (root OU Shizuku/ADB), não só shell local sem poder
have_shell() {
    [ "$RUN_MODE" != "local" ] && return 0
    sh_ok
}

# Exige privilégio de shell. Sem ele, avisa como habilitar (painel > Configs).
require_shell() {
    have_shell && return 0
    warn "sem permissão de shell (Shizuku/ADB). Abra o painel > Configs e conecte."
    return 1
}

# --- saída colorida -----------------------------------------------------------
if [ -t 1 ] && [ -z "$OTM_NO_COLOR" ]; then
    C_R=$(printf '\033[0m')
    C_G=$(printf '\033[38;5;150m')
    C_Y=$(printf '\033[38;5;221m')
    C_RD=$(printf '\033[38;5;203m')
    C_A=$(printf '\033[38;5;116m')
    C_D=$(printf '\033[38;5;243m')
else
    C_R=''; C_G=''; C_Y=''; C_RD=''; C_A=''; C_D=''
fi

say()  { printf '  %b▸%b  %s\n' "$C_G" "$C_R" "$1"; }
warn() { printf '  %b!%b  %s\n' "$C_Y" "$C_R" "$1"; }
err()  { printf '  %b✕%b  %s\n' "$C_RD" "$C_R" "$1"; }
skip() { printf '  %b·%b  %s (off)\n' "$C_D" "$C_R" "$1"; }

require_root() {
    if sh_ok; then return 0; fi
    warn "precisa de root ($RUN_MODE). pulando."
    return 1
}

# --- backup / restauração -----------------------------------------------------
ST="${HOME:-/data/data/com.termux/files/home}/.packotm"
OFF_SH="$ST/off.sh"; MARK="$ST/on"
mkdir -p "$ST" 2>/dev/null

bkp_begin() {
    [ -f "$MARK" ] && return 0
    : > "$OFF_SH"
    printf '#!/system/bin/sh\n' >> "$OFF_SH"
    command touch "$MARK"
}

# --- verificacao REAL: aplicou? mudou? ----------------------------------------
# Contadores por processo. Os runners zeram no inicio e imprimem #OTM-RESULT no
# fim; o painel le essa linha para decidir se houve mudanca de verdade no sistema.
OTM_V_APPLIES=0
OTM_V_CHANGED=0
OTM_V_FAILED=0

otm_v_reset() { OTM_V_APPLIES=0; OTM_V_CHANGED=0; OTM_V_FAILED=0; }
otm_v_inc()   { case "$1" in
    apply)   OTM_V_APPLIES=$((OTM_V_APPLIES+1)) ;;
    changed) OTM_V_CHANGED=$((OTM_V_CHANGED+1)) ;;
    failed)  OTM_V_FAILED=$((OTM_V_FAILED+1)) ;;
esac; }

# otm_v_report <tag> [ok] -> linha legivel por maquina para o painel.
# ok default = 1 se mudou algo de verdade, senao 0. Passe ok explicitamente para
# acoes que nao mudam o sistema mas sao um teste (ex.: config test).
otm_v_report() {
    tag="${1:-geral}"
    if [ -n "$2" ]; then ok="$2"
    elif [ "$OTM_V_CHANGED" -gt 0 ]; then ok=1
    else ok=0; fi
    printf '#OTM-RESULT tag=%s applies=%d changed=%d failed=%d ok=%d\n' \
        "$tag" "$OTM_V_APPLIES" "$OTM_V_CHANGED" "$OTM_V_FAILED" "$ok"
}


# bkp_set <tipo> <chave> <novo_valor> -> aplica e guarda o valor antigo
bkp_set() {
    t="$1"; k="$2"; v="$3"
    otm_v_inc apply
    old=$(sh_get "settings get $t $k")
    if [ -z "$old" ] || [ "$old" = "null" ]; then
        echo "settings delete $t $k" >> "$OFF_SH"
    else
        printf "settings put %s %s %s\n" "$t" "$k" "$old" >> "$OFF_SH"
    fi
    sh_run "settings put $t $k $v" >/dev/null
    now=$(sh_get "settings get $t $k")
    if [ "$now" = "$v" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s %s = %s\n' "$C_G" "$C_R" "$t" "$k" "$v"
    else
        otm_v_inc failed
        printf '   %bX%b %s %s nao mudou (lido: %s)\n' "$C_RD" "$C_R" "$t" "$k" "${now:-vazio}"
    fi
}

prop_set() {
    p="$1"; v="$2"
    otm_v_inc apply
    old=$(sh_get "getprop $p")
    if [ -n "$old" ]; then bkp_raw "setprop $p $old"; else bkp_raw "setprop $p ''"; fi
    sh_run "setprop $p $v" >/dev/null
    now=$(sh_get "getprop $p")
    if [ "$now" = "$v" ]; then
        otm_v_inc changed
        printf '   %bOK%b prop %s = %s\n' "$C_G" "$C_R" "$p" "$v"
    else
        otm_v_inc failed
        printf '   %bX%b prop %s nao mudou (lido: %s)\n' "$C_RD" "$C_R" "$p" "${now:-vazio}"
    fi
}

# bkp_raw "comando de reversão" -> só registra para o restore
bkp_raw() { echo "$1" >> "$OFF_SH"; }
