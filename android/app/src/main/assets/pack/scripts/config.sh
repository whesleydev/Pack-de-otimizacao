#!/system/bin/sh
# =============================================================================
#  config.sh - Configuração de acesso do pack (painel > Configs).
#
#  Define COMO o pack conversa com o Android, sem precisar de root:
#    rish   Shizuku (rodando no celular)          <- recomendado no celular
#    adb    ADB pela rede/Wi-Fi (host:porta)      <- recomendado no PC/rede
#    su     root (Magisk/KernelSU/APatch)
#    local  shell sem privilégio (só leitura/informativo)
#
#  Uso:
#    sh scripts/config.sh show            # mostra a config atual + modo detectado
#    sh scripts/config.sh set rish [caminho-do-rish]
#    sh scripts/config.sh set adb 192.168.0.10:5555
#    sh scripts/config.sh set su
#    sh scripts/config.sh set auto
#    sh scripts/config.sh test            # testa a conexão de verdade
#    sh scripts/config.sh reset           # volta à detecção automática
#
#  Grava em ~/.packotm/config (nunca versionado). Tudo reversível.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

# --- leitura/escrita do arquivo de config ------------------------------------
cfg_get() {  # cfg_get <chave> -> valor salvo (do arquivo, não do ambiente)
    [ -f "$OTM_CFG" ] || return 0
    while IFS='=' read -r k v; do
        case "$k" in ''|\#*) continue ;; esac
        [ "$k" = "$1" ] && { printf '%s' "$v"; return 0; }
    done < "$OTM_CFG"
}

cfg_write() {  # cfg_write <modo> <serial> <rish>
    mkdir -p "$OTM_ST" 2>/dev/null
    {
        printf '# config do Pack de Otimização (gerado pelo painel)\n'
        printf 'OTM_MODE=%s\n' "$1"
        printf 'OTM_ADB_SERIAL=%s\n' "$2"
        printf 'OTM_RISH=%s\n' "$3"
    } > "$OTM_CFG"
}

cfg_clear() { rm -f "$OTM_CFG" 2>/dev/null; }

# --- ações --------------------------------------------------------------------
do_show() {
    say "Configuração de acesso"
    printf '   arquivo : %s\n' "$OTM_CFG"
    printf '   modo    : %s\n' "$(cfg_get OTM_MODE)"
    printf '   adb     : %s\n' "$(cfg_get OTM_ADB_SERIAL)"
    printf '   rish    : %s\n' "$(cfg_get OTM_RISH)"
    printf '   detectado agora : %s%s%s\n' "$C_A" "$RUN_MODE" "$C_R"
    printf '   privilégio      : %s\n' "$(sh_ok && echo 'root' || (have_shell && echo 'shell (Shizuku/ADB)' || echo 'nenhum (só local)'))"
    printf '   adb no PATH     : %s\n' "$(have adb && echo sim || echo não)"
    printf '   rish no PATH    : %s\n' "$(have rish && echo sim || echo não)"
    echo
    printf '   dica: %sShizuku%s no celular (rish) ou %sdepuração por Wi-Fi%s no PC (adb).\n' "$C_A" "$C_R" "$C_A" "$C_R"
}

do_set() {
    modo="$1"; arg2="$2"
    case "$modo" in
        rish)  cfg_write rish "" "${arg2:-}" ;;
        adb)   [ -z "$arg2" ] && { err "informe o endereço host:porta (ex.: 192.168.0.10:5555)"; return 1; }
               cfg_write adb "$arg2" "" ;;
        su)    cfg_write su "" "" ;;
        local) cfg_write local "" "" ;;
        auto|"") cfg_clear ;;
        *)     err "modo inválido: use rish|adb|su|local|auto"; return 1 ;;
    esac
    say "config salva: modo=${modo:-auto} ${arg2:+($arg2)}"
    do_show
}

# do_test: tenta conectar de verdade e diz o que funcionou.
do_test() {
    say "Testando acesso ao Android…"
    # ADB por Wi-Fi: tenta conectar se houver endereço salvo
    ser="$(cfg_get OTM_ADB_SERIAL)"
    if [ -n "$ser" ]; then
        case "$ser" in *:*) have adb && _with_timeout 8 adb connect "$ser" >/dev/null 2>&1 ;; esac
    fi
    # (re)detecta com a config carregada
    RUN_MODE=""
    if [ -n "$OTM_MODE" ]; then RUN_MODE="$OTM_MODE"
    elif _rish_works; then RUN_MODE=rish
    elif _adb_works; then RUN_MODE=adb
    elif _su_works; then RUN_MODE=su
    else RUN_MODE=local; fi

    ok=1
    printf '   modo detectado : %s%s%s\n' "$C_A" "$RUN_MODE" "$C_R"
    uid="$(sh_get 'id -u')"
    printf '   id -u          : %s\n' "${uid:-?}"
    model="$(sh_get 'getprop ro.product.model')"
    printf '   aparelho       : %s\n' "${model:-?}"
    sdk="$(sh_get 'getprop ro.build.version.sdk')"
    printf '   Android API    : %s\n' "${sdk:-?}"

    if have_shell; then
        # prova real: lê um setting e tenta escrever um setting de teste
        probe="$(sh_get 'settings get global window_animation_scale')"
        printf '   leitura settings : %s\n' "${probe:-?}"
        if sh_ok; then
            printf '   %s✓%s privilégio de shell (root) confirmado\n' "$C_G" "$C_R"
        else
            printf '   %s✓%s privilégio de shell (Shizuku/ADB) confirmado\n' "$C_G" "$C_R"
        fi
    else
        ok=0
        printf '   %s✗%s sem privilégio de shell: o pack vai rodar em modo local\n' "$C_RD" "$C_R"
        printf '     → no celular: instale/ative o %sShizuku%s e rode o rish\n' "$C_A" "$C_R"
        printf '     → no PC/rede: ative a %sdepuração por Wi-Fi%s e informe o IP:porta\n' "$C_A" "$C_R"
    fi
    echo
    otm_v_report config "$ok"
    [ "$ok" = 1 ] && return 0 || return 1
}

# --- runner -------------------------------------------------------------------
case "${1:-show}" in
    show|get|"") do_show ;;
    set)   shift; do_set "$@" ;;
    test)  do_test ;;
    reset) cfg_clear; say "config apagada (volta à detecção automática)"; do_show ;;
    *)     err "uso: config.sh show|set <modo> [arg]|test|reset"; exit 1 ;;
esac
