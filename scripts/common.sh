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

# --- detecção -----------------------------------------------------------------
# _with_timeout <segundos> <cmd...>  -> roda o cmd com timeout, se houver `timeout`.
# Evita que `su`/`adb` pendurem esperando senha/servidor (script travado é pior que
# script sem privilégio). Sem `timeout` disponível, roda direto.
_with_timeout() {
    t="$1"; shift
    if command -v timeout >/dev/null 2>&1; then
        timeout "$t" "$@"
    else
        "$@"
    fi
}

_su_works() {
    command -v su >/dev/null 2>&1 || return 1
    [ "$(id -u 2>/dev/null)" = "0" ] && return 1        # já é root
    [ "$(_with_timeout 3 su -c 'id -u' 2>/dev/null)" = "0" ] || return 1
}

_adb_works() {
    command -v adb >/dev/null 2>&1 || return 1
    _with_timeout 3 adb devices 2>/dev/null \
        | awk 'NR>1 && $2=="device"{print $1}' | head -1 | grep -q .
}

if [ -n "$OTM_MODE" ]; then
    RUN_MODE="$OTM_MODE"
elif _adb_works; then
    RUN_MODE="adb"
elif command -v rish >/dev/null 2>&1; then
    RUN_MODE="rish"
elif _su_works; then
    RUN_MODE="su"
else
    RUN_MODE="local"
fi

# --- execução -----------------------------------------------------------------
sh_run() {  # sh_run "settings put global foo 1"
    case "$RUN_MODE" in
        adb)   _with_timeout 20 adb shell "$1" 2>/dev/null ;;
        rish)  _with_timeout 20 rish -c "$1" 2>/dev/null ;;
        su)    _with_timeout 20 su -c "$1" 2>/dev/null ;;
        *)     sh -c "$1" 2>/dev/null ;;
    esac
}

sh_get() {  # sh_get "settings get global foo" -> imprime valor
    case "$RUN_MODE" in
        adb)   _with_timeout 20 adb shell "$1" 2>/dev/null | tr -d '\r' ;;
        rish)  _with_timeout 20 rish -c "$1" 2>/dev/null | tr -d '\r' ;;
        su)    _with_timeout 20 su -c "$1" 2>/dev/null | tr -d '\r' ;;
        *)     sh -c "$1" 2>/dev/null | tr -d '\r' ;;
    esac
}

sh_ok() { [ "$(sh_get 'id -u')" = "0" ]; }
have()  { command -v "$1" >/dev/null 2>&1; }

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

# bkp_set <tipo> <chave> <novo_valor> -> aplica e guarda o valor antigo
bkp_set() {
    t="$1"; k="$2"; v="$3"
    old=$(sh_get "settings get $t $k")
    if [ -z "$old" ] || [ "$old" = "null" ]; then
        echo "settings delete $t $k" >> "$OFF_SH"
    else
        printf "settings put %s %s '%s'\n" "$t" "$k" "$old" >> "$OFF_SH"
    fi
    sh_run "settings put $t $k $v" >/dev/null
}

# bkp_raw "comando de reversão" -> só registra para o restore
bkp_raw() { echo "$1" >> "$OFF_SH"; }
