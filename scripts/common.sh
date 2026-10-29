#!/system/bin/sh
# =============================================================================
#  common.sh - Biblioteca compartilhada do Pack de Otimização
#  Detecta automaticamente como executar comandos privilegiados:
#    1) direct      (o processo JÁ é shell/root: é o caso do app via Shizuku)
#    2) adb shell   (PC -> celular, depuração USB ou sem fio)
#    3) rish        (Shizuku, rodando de fora do app)
#    4) su -c       (root / Magisk / KernelSU / APatch)
#    5) sh -c       (shell local, sem privilégio)
#  Todos os scripts fazem ". ./common.sh" e usam sh_run / sh_get.
#  Variável de override: OTM_MODE=adb|usb|rish|su|local
#  (usb = adb no 1º aparelho do cabo; adb = endereço fixo OTM_ADB_SERIAL)
# =============================================================================

# --- configuração (persistida pelo painel > Configs) --------------------------
# Carrega ~/.packotm/config, se existir. Chaves: OTM_MODE (adb|usb|rish|su|local),
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
elif [ "$(id -u 2>/dev/null)" = "0" ]; then
    # já somos root: nenhum wrapper é necessário, os comandos valem direto
    RUN_MODE="direct"
elif [ "$(id -u 2>/dev/null)" = "2000" ]; then
    # já somos o usuário `shell` (o app roda os scripts pelo Shizuku/ADB, que
    # abrem o processo JÁ privilegiado). Sem `rish`/`adb` no PATH o teste por
    # binário daria "local" e o pack se recusaria a trabalhar sem motivo.
    RUN_MODE="direct"
elif _rish_works; then
    RUN_MODE="rish"
elif _adb_works; then
    RUN_MODE="adb"
else
    RUN_MODE="local"
fi

# --- execução -----------------------------------------------------------------
# _otm_shell "<cmd>" -> executa no alvo conforme o modo. Base de sh_run/sh_get.
# `direct` = o próprio processo já tem o privilégio (Shizuku/ADB abriram o shell
# como uid 2000, ou já somos root): roda sem wrapper.
_otm_shell() {
    case "$RUN_MODE" in
        adb)    if [ -n "$OTM_ADB_SERIAL" ]; then _with_timeout 20 adb -s "$OTM_ADB_SERIAL" shell "$1"
                else _with_timeout 20 adb shell "$1"; fi ;;
        usb)    _with_timeout 20 adb shell "$1" ;;
        rish)   r="$(_otm_rish)"
                if [ -x "$r" ]; then _with_timeout 20 "$r" -c "$1"
                else _with_timeout 20 rish -c "$1"; fi ;;
        su)     _with_timeout 20 su -c "$1" ;;
        *)      sh -c "$1" ;;
    esac
}

sh_run() { _otm_shell "$1" 2>/dev/null; }
sh_get() { _otm_shell "$1" 2>/dev/null | tr -d '\r'; }

sh_ok() { [ "$(sh_get 'id -u')" = "0" ]; }
have()  { command -v "$1" >/dev/null 2>&1; }

# tem privilégio de shell (root OU Shizuku/ADB), não só shell local sem poder.
# `direct` cobre o caso em que o processo já nasceu privilegiado (Shizuku/ADB).
have_shell() {
    case "$RUN_MODE" in
        local) return 1 ;;
        direct) return 0 ;;
        *) return 0 ;;
    esac
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

# --- backup / restauração -----------------------------------------------------
ST="${HOME:-/data/data/com.termux/files/home}/.packotm"
UNDO_DIR="$ST/undo"
OFF_SH="$ST/off.sh"; MARK="$ST/on"     # escopo padrão (compartilhado)
OTM_SCOPE=""                            # vazio = escopo padrão
mkdir -p "$ST" "$UNDO_DIR" 2>/dev/null

# scope_begin <nome> -> isola a reversão deste script num arquivo próprio.
# Sem isso, um `off` de uma função desfaz e apaga a reversão das outras: o
# "Clean: desfazer" apagava o 0.5x do "Performance" e a reversão geral ficava
# pela metade. Cada escopo tem seu off.sh + marcador; `restore_all` percorre todos.
scope_begin() {
    OTM_SCOPE="$1"
    OFF_SH="$UNDO_DIR/$1.sh"
    MARK="$UNDO_DIR/$1.on"
}

# otm_undo_files -> lista os arquivos de reversão existentes (todos os escopos)
otm_undo_files() {
    [ -s "$ST/off.sh" ] && echo "$ST/off.sh"
    for f in "$UNDO_DIR"/*.sh; do
        [ -s "$f" ] && echo "$f"
    done
}

# otm_undo_run <arquivo> -> executa as linhas de reversão de um arquivo
otm_undo_run() {
    f="$1"; [ -s "$f" ] || return 0
    while IFS= read -r c; do
        [ -z "$c" ] && continue
        case "$c" in '#'*) continue ;; esac
        sh_run "$c" >/dev/null 2>&1
    done < "$f"
}

# otm_undo_clear -> apaga TODAS as reversões (restauração geral)
otm_undo_clear() {
    rm -f "$ST/off.sh" "$ST/on" 2>/dev/null
    rm -rf "$UNDO_DIR" 2>/dev/null
    rm -f "$ST/origins" 2>/dev/null
}

# --- valores originais do aparelho -------------------------------------------
# Guarda o valor que a chave tinha ANTES de qualquer ação mexer nela. Sem isso,
# aplicar A e depois B fazia o "desfazer B" restaurar o valor que A tinha
# deixado (o snapshot de B já nascia poluído por A).
ORIG_FILE="$ST/origins"

orig_get() {  # orig_get <tipo> <chave> -> valor original, ou __NONE__ se nunca visto
    [ -f "$ORIG_FILE" ] || { printf '__NONE__'; return; }
    awk -F'\t' -v t="$1" -v k="$2" '
        $1==t && $2==k { sub(/^[^\t]*\t[^\t]*\t?/, ""); print; found=1; exit }
        END { if (!found) printf "__NONE__" }' "$ORIG_FILE"
}

orig_set() {  # orig_set <tipo> <chave> <valor>   (vazio = não existia)
    mkdir -p "$ST" 2>/dev/null
    printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$ORIG_FILE"
}

bkp_begin() {
    [ -f "$MARK" ] && return 0
    mkdir -p "$(dirname "$OFF_SH")" 2>/dev/null
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


# otm_undo_retarget <tipo> <chave> <novo_guard> -> atualiza a CONDIÇÃO da
# reversão já registrada para esta chave, sem trocar o alvo (o valor original).
# A reversão é 1 por chave e o guard nasce com o 1º valor escrito. Se a MESMA
# ação escrever a chave de novo com outro valor (ex.: barras do sistema trocando
# de "imersivo" para "só a de baixo"), o guard antigo ficava preso no valor
# velho e o "Reverter TUDO" não devolvia nada (a barra ficava escondida).
otm_undo_retarget() {
    t="$1"; k="$2"; v="$3"
    [ -s "$OFF_SH" ] || return 0
    awk -v t="$t" -v k="$k" -v v="$v" '
        $0 ~ ("settings (put|delete) " t " " k "( |$)") {
            sub(/= "[^"]*"/, "= \"" v "\"")
        }
        { print }' "$OFF_SH" > "$OFF_SH.tmp" && mv "$OFF_SH.tmp" "$OFF_SH"
}

# bkp_set <tipo> <chave> <novo_valor> -> aplica e guarda o valor antigo
bkp_set() {
    t="$1"; k="$2"; v="$3"
    otm_v_inc apply
    old=$(sh_get "settings get $t $k")
    # registra o valor ORIGINAL do aparelho na 1ª vez que mexemos nesta chave
    orig="$(orig_get "$t" "$k")"
    if [ "$orig" = "__NONE__" ]; then
        [ -z "$old" ] || [ "$old" = "null" ] && orig="" || orig="$old"
        orig_set "$t" "$k" "$orig"
    fi
    # guarda só a 1ª vez por escopo: reaplicar não pode empilhar backups obsoletos.
    # A reversão é CONDICIONAL: só desfaz se o valor atual ainda for o que esta
    # ação escreveu. Sem isso, desfazer uma ação antiga apagaria o que uma ação
    # posterior aplicou na mesma chave (as otimizações "se atropelavam").
    if ! grep -qE "settings (put|delete) $t $k( |$)" "$OFF_SH" 2>/dev/null; then
        if [ -z "$orig" ]; then
            printf '[ "$(settings get %s %s)" = "%s" ] && settings delete %s %s\n' \
                "$t" "$k" "$v" "$t" "$k" >> "$OFF_SH"
        else
            printf '[ "$(settings get %s %s)" = "%s" ] && settings put %s %s %s\n' \
                "$t" "$k" "$v" "$t" "$k" "$orig" >> "$OFF_SH"
        fi
    else
        # já havia reversão para esta chave: só move o guard para o valor atual,
        # para o "desfazer" ainda reconhecer o que esta ação acabou de escrever
        otm_undo_retarget "$t" "$k" "$v"
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
    bkp_begin
    old=$(sh_get "getprop $p")
    # guarda a reversão só na 1ª vez por prop: reaplicar não pode empilhar backups
    # obsoletos (sem isso, "renderer opengl" depois de "skiagl" restaurava o skiagl).
    if ! grep -qE "setprop $p( |$)" "$OFF_SH" 2>/dev/null; then
        if [ -n "$old" ]; then bkp_raw "setprop $p $old"; else bkp_raw "setprop $p ''"; fi
    fi
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

# prop_clear <prop> -> apaga o prop (setprop ''), com reversão
prop_clear() {
    p="$1"
    otm_v_inc apply
    bkp_begin
    old=$(sh_get "getprop $p")
    if ! grep -qE "setprop $p( |$)" "$OFF_SH" 2>/dev/null; then
        if [ -n "$old" ]; then bkp_raw "setprop $p $old"; else bkp_raw "setprop $p ''"; fi
    fi
    sh_run "setprop $p ''" >/dev/null
    now=$(sh_get "getprop $p")
    if [ -z "$now" ]; then
        otm_v_inc changed
        printf '   %bOK%b prop %s = (vazio)\n' "$C_G" "$C_R" "$p"
    else
        otm_v_inc failed
        printf '   %bX%b prop %s nao limpou (lido: %s)\n' "$C_RD" "$C_R" "$p" "$now"
    fi
}

# bkp_raw "comando de reversão" -> só registra para o restore
bkp_raw() { echo "$1" >> "$OFF_SH"; }

# bkp_del <tipo> <chave> -> APAGA a chave (settings delete) com reversão.
# Diferente de bkp_set com valor vazio: `settings put <t> <k> ` não remove a
# chave e em muitos aparelhos dá erro; o delete devolve o padrão de fábrica.
bkp_del() {
    t="$1"; k="$2"
    otm_v_inc apply
    old=$(sh_get "settings get $t $k")
    orig="$(orig_get "$t" "$k")"
    if [ "$orig" = "__NONE__" ]; then
        [ -z "$old" ] || [ "$old" = "null" ] && orig="" || orig="$old"
        orig_set "$t" "$k" "$orig"
    fi
    if ! grep -qE "settings (put|delete) $t $k( |$)" "$OFF_SH" 2>/dev/null; then
        if [ -z "$orig" ]; then
            printf 'settings delete %s %s\n' "$t" "$k" >> "$OFF_SH"
        else
            printf '[ "$(settings get %s %s)" = "null" ] && settings put %s %s %s\n' \
                "$t" "$k" "$t" "$k" "$orig" >> "$OFF_SH"
        fi
    else
        # já havia reversão: depois do delete o valor é nulo, então o guard da
        # linha existente tem de casar com "null" (senão o restore não devolvia)
        otm_undo_retarget "$t" "$k" null
    fi
    sh_run "settings delete $t $k" >/dev/null
    now=$(sh_get "settings get $t $k")
    if [ -z "$now" ] || [ "$now" = "null" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s %s apagado (padrão)\n' "$C_G" "$C_R" "$t" "$k"
    else
        otm_v_inc failed
        printf '   %bX%b %s %s nao apagou (lido: %s)\n' "$C_RD" "$C_R" "$t" "$k" "$now"
    fi
}

# --- ActivityManager constants ------------------------------------------------
# am_constants_merge <k=v> [k=v...] -> string de activity_manager_constants com as
# chaves atualizadas, PRESERVANDO as que já estavam lá. O `settings put` nessa
# chave substitui a string inteira: gravar só "max_cached_processes=4" apagava o
# max_phantom_processes e qualquer outro ajuste já presente no aparelho.
am_constants_merge() {
    cur="$(sh_get 'settings get global activity_manager_constants')"
    case "$cur" in '' | null) cur="" ;; esac
    for kv in "$@"; do
        k="${kv%%=*}"
        rest="$(printf '%s' "$cur" | tr ',' '\n' | grep -v "^$k=" | tr '\n' ',' | sed 's/,$//')"
        cur="${rest:+$rest,}$kv"
    done
    printf '%s' "$cur"
}

# am_set <k=v> [k=v...] -> aplica as constantes mesclando com o que já existe
am_set() { bkp_set global activity_manager_constants "$(am_constants_merge "$@")"; }

# --- limite de processos em segundo plano -------------------------------------
# O "Limite de processos em segundo plano" das Opções do desenvolvedor NÃO lê o
# setting global activity_manager_constants. No Android 10+ a plataforma lê
# `device_config activity_manager max_cached_processes` (namespace
# activity_manager) e o Dev Options lê um override interno
# (IActivityManager.setProcessLimit). Era por isso que o pack gravava
# max_cached_processes no setting e o painel do Android continuava em "Padrão":
# a string era lida, mas a chave não era usada (MAX_CACHED_PROCESSES é um
# recurso do sistema, não um campo do parser). Aqui escrevemos nos DOIS lugares
# (o setting fica para Androids antigos e para não quebrar quem já lê de lá) e
# lemos de volta o valor REAL.
OTM_PROC_NS="activity_manager"
OTM_PROC_KEY="max_cached_processes"

# proc_limit_set <n>  -> n = 1..32 (0 ou "padrao" volta ao padrão de fábrica)
proc_limit_set() {
    n="$1"
    bkp_begin
    case "$n" in
        padrao|default|0)
            otm_v_inc apply
            bkp_raw "device_config delete $OTM_PROC_NS $OTM_PROC_KEY"
            sh_run "device_config delete $OTM_PROC_NS $OTM_PROC_KEY" >/dev/null 2>&1
            am_set max_cached_processes=0
            say "limite de processos: padrão do sistema"
            ;;
        *[!0-9]*|'')
            err "uso: proc_limit <1..32|padrao>"; return 1 ;;
        *)
            [ "$n" -lt 1 ] && n=1
            [ "$n" -gt 32 ] && n=32
            otm_v_inc apply
            bkp_raw "device_config delete $OTM_PROC_NS $OTM_PROC_KEY"
            sh_run "device_config put $OTM_PROC_NS $OTM_PROC_KEY $n" >/dev/null 2>&1
            # mantém o setting em sincronia (Androids antigos / quem lê de lá)
            am_set "max_cached_processes=$n"
            got="$(sh_get "device_config get $OTM_PROC_NS $OTM_PROC_KEY")"
            if [ "$got" = "$n" ]; then
                otm_v_inc changed
                printf '   %bOK%b limite de processos em segundo plano = %s\n' "$C_G" "$C_R" "$n"
            else
                otm_v_inc failed
                printf '   %bX%b limite não pegou (lido: %s)\n' "$C_RD" "$C_R" "${got:-vazio}"
            fi
            ;;
    esac
}

# proc_limit_get -> valor REAL do limite (número, ou "padrão" se não houver)
proc_limit_get() {
    v="$(sh_get "device_config get $OTM_PROC_NS $OTM_PROC_KEY")"
    case "$v" in
        ''|null)
            # cai para o setting (Androids antigos) e, por fim, para o dumpsys
            s="$(sh_get 'settings get global activity_manager_constants' \
                | tr ',' '\n' | grep "^$OTM_PROC_KEY=" | head -1 | cut -d= -f2)"
            case "$s" in ''|0|null) v="$(sh_get 'dumpsys activity settings' \
                | awk -F= '/^ *CUR_MAX_CACHED_PROCESSES=/{print $2; exit}' | tr -d ' ')";; *) v="$s" ;; esac
            ;;
    esac
    case "$v" in ''|null|0) printf 'padrão' ;; *) printf '%s' "$v" ;; esac
}

# --- sysctl com verificação e reversão ----------------------------------------
# otm_sysctl <chave> <valor> -> escreve, LÊ DE VOLTA e guarda o valor antigo.
# Nem todo kernel aceita toda chave (BBR, ECN, low latency): sem ler de volta, o
# script "aplicaria" no escuro. Espaços em valores de lista (tcp_rmem) contam
# como iguais mesmo com tabulação/espaço diferente.
otm_sysctl() {
    k="$1"; v="$2"
    otm_v_inc apply
    old="$(sh_get "sysctl -n $k")"
    [ -n "$old" ] && bkp_raw "sysctl -w $k='$old'"
    sh_run "sysctl -w $k='$v'" >/dev/null
    now="$(sh_get "sysctl -n $k")"
    n_now="$(printf '%s' "$now" | tr -s ' \t' ' ' | sed 's/^ *//;s/ *$//')"
    n_want="$(printf '%s' "$v" | tr -s ' \t' ' ' | sed 's/^ *//;s/ *$//')"
    if [ "$n_now" = "$n_want" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s = %s\n' "$C_G" "$C_R" "$k" "$v"
    else
        otm_v_inc failed
        printf '   %bX%b %s nao mudou (lido: %s)\n' "$C_RD" "$C_R" "$k" "${now:-vazio}"
    fi
}

# --- RAM: leitura e liberação real --------------------------------------------
# apps que nunca devem ser encerrados por engano (a UI do sistema, o próprio pack)
OTM_SYS_KEEP="android com.android.systemui com.android.launcher3 com.google.android.apps.nexuslauncher com.android.settings com.otm.pack com.termux"

# otm_meminfo <campo MemTotal|MemAvailable> -> kB
otm_meminfo() {
    sh_get 'cat /proc/meminfo' | awk -v k="$1" '$1==k":"{print $2; exit}'
}

# otm_ram_livre_mb -> RAM disponível em MB (vazio se não der para ler)
otm_ram_livre_mb() {
    v="$(otm_meminfo MemAvailable)"
    [ -n "$v" ] && echo $((v / 1024))
}

# otm_fg_pkg -> pacote do app em PRIMEIRO PLANO (o que está na tela agora).
# Vazio quando não dá para ler. Usado para nunca fechar o que o usuário está
# usando: o jogo aberto, o próprio painel, o app do pack.
otm_fg_pkg() {
    d="$(sh_get 'dumpsys activity activities' 2>/dev/null)"
    [ -n "$d" ] || d="$(sh_get 'dumpsys window windows' 2>/dev/null)"
    p="$(printf '%s\n' "$d" | sed -n 's/.*mResumedActivity.*[ {]\([A-Za-z0-9_.]*\)\/.*/\1/p' | head -1)"
    [ -z "$p" ] && p="$(printf '%s\n' "$d" | sed -n 's/.*topResumedActivity.*[ {]\([A-Za-z0-9_.]*\)\/.*/\1/p' | head -1)"
    [ -z "$p" ] && p="$(printf '%s\n' "$d" | sed -n 's/.*mFocusedApp.*[ {]\([A-Za-z0-9_.]*\)\/.*/\1/p' | head -1)"
    printf '%s' "$p"
}

# otm_keep_list -> tudo que a limpeza NUNCA deve encerrar, separado por espaço:
# o jogo escolhido (Modo Competitivo), os protegidos no anti-relog, o app do
# pack e o que está em primeiro plano agora. É a lista que o clean/ram-boost usa.
otm_keep_list() {
    k=""
    [ -s "$ST/game/pkg" ] && k="$k $(tr '\n' ' ' < "$ST/game/pkg")"
    [ -s "$ST/keepalive/apps" ] && k="$k $(tr '\n' ' ' < "$ST/keepalive/apps")"
    # exceções do gerenciador de processos ("X app não vai encerrar"): valem para
    # o encerrar-todos do flutuante E para o clean/ram-boost/game-clean.
    [ -s "$ST/procmgr/keep" ] && k="$k $(tr '\n' ' ' < "$ST/procmgr/keep")"
    fg="$(otm_fg_pkg)"
    [ -n "$fg" ] && k="$k $fg"
    # jogos de FPS conhecidos: nunca encerrar (o usuário pode estar no meio da partida)
    k="$k com.dts.freefireth com.dts.freefiremax com.activision.callofduty.shooter com.tencent.ig com.pubg.imobile com.garena.game.kgth com.miHoYo.GenshinImpact com.epicgames.fortnite com.riotgames.league.wildrift com.mobile.legends"
    printf '%s' "$k" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' '
}

# otm_bg_kill <poupados...> -> encerra apps de 3º plano, poupando os citados.
# Só mexe em apps instalados pelo usuário (pm list packages -3): não toca em
# serviços do sistema. Ecoa a quantidade de apps encerrados.
otm_bg_kill() {
    keep=" $OTM_SYS_KEEP $* "
    n=0
    for p in $(sh_get 'pm list packages -3' | sed 's/^package://'); do
        [ -n "$p" ] || continue
        case "$keep" in *" $p "*) continue ;; esac
        sh_run "am force-stop $p" >/dev/null 2>&1 && n=$((n + 1))
    done
    echo "$n"
}

# otm_cache_trim -> apaga o cache de todos os apps e devolve o espaço liberado (B)
otm_cache_trim() {
    out="$(sh_get 'pm trim-caches 999999999999')"
    printf '%s' "$out" | awk '/space free/{print $1; exit}'
}

# otm_temp -> temperatura em °C da melhor zona disponível (vazio se não der)
otm_temp() {
    for z in /sys/class/thermal/thermal_zone*; do
        [ -d "$z" ] || continue
        t="$(sh_get "cat $z/type" 2>/dev/null)"
        case "$t" in soc | *skin* | cpu* | gpu* | *battery* | tsens*) ;; *) continue ;; esac
        v="$(sh_get "cat $z/temp" 2>/dev/null)"
        case "$v" in '' | *[!0-9-]*) continue ;; esac
        [ "$v" -gt 1000 ] && v=$((v / 1000))
        echo "$v"
        return 0
    done
    v="$(sh_get 'dumpsys battery' | awk -F': ' '/ temperature:/{print $2}')"
    case "$v" in '' | *[!0-9]*) return 0 ;; esac
    echo "$((v / 10))"
}
