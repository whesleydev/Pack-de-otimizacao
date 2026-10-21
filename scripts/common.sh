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
    # guarda só a 1ª vez: reaplicar não pode empilhar backups obsoletos
    if ! grep -qE "^settings (put|delete) $t $k( |$)" "$OFF_SH" 2>/dev/null; then
        if [ -z "$old" ] || [ "$old" = "null" ]; then
            echo "settings delete $t $k" >> "$OFF_SH"
        else
            printf "settings put %s %s %s\n" "$t" "$k" "$old" >> "$OFF_SH"
        fi
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

# --- persistência no boot -----------------------------------------------------
# Alguns `settings`/`setprop` se perdem no reboot. Com root dá para reaplicar no
# boot: os scripts registram a linha de aplicação em $BOOT_SH e instalamos um
# wrapper em /data/adb/service.d (Magisk) ou /system/etc/init.d.
BOOT_SH="$ST/boot.sh"

# boot_add "comando de aplicação"  -> guarda (sem duplicar) para reaplicar no boot
boot_add() {
    mkdir -p "$ST" 2>/dev/null
    touch "$BOOT_SH" 2>/dev/null
    grep -qxF "$1" "$BOOT_SH" 2>/dev/null || echo "$1" >> "$BOOT_SH"
}

# boot_install -> instala o wrapper de boot (só com root). Reaplica $BOOT_SH.
boot_install() {
    require_root "persistência no boot" || return 1
    [ -s "$BOOT_SH" ] || { warn "nada para persistir (aplique algo primeiro)"; return 1; }
    wrapper="#!/system/bin/sh
# gerado pelo Pack de Otimização — reaplica os ajustes no boot
sleep 20
[ -f '$BOOT_SH' ] && sh '$BOOT_SH' >/dev/null 2>&1"
    svc="${OTM_BOOT_DIR:-/data/adb/service.d}/otm-pack.sh"
    initd="${OTM_BOOT_INITD:-/system/etc/init.d}/99otm-pack"
    if [ -d "${OTM_BOOT_DIR:-/data/adb/service.d}" ]; then
        printf '%s\n' "$wrapper" > "$svc" 2>/dev/null && chmod 755 "$svc" 2>/dev/null
        say "persistência no boot instalada ($svc)"
    elif [ -d "${OTM_BOOT_INITD:-/system/etc/init.d}" ]; then
        printf '%s\n' "$wrapper" > "$initd" 2>/dev/null && chmod 755 "$initd" 2>/dev/null
        say "persistência no boot instalada ($initd)"
    else
        warn "sem /data/adb/service.d nem init.d — persistência indisponível nesta ROM"
        return 1
    fi
    say "no boot, ${BOOT_SH} é reaplicado. Remova em: turbo.sh boot off"
}

boot_uninstall() {
    rm -f "${OTM_BOOT_DIR:-/data/adb/service.d}/otm-pack.sh" "${OTM_BOOT_INITD:-/system/etc/init.d}/99otm-pack" 2>/dev/null
    say "persistência no boot removida"
}

boot_status() {
    if [ -f "${OTM_BOOT_DIR:-/data/adb/service.d}/otm-pack.sh" ] || [ -f "${OTM_BOOT_INITD:-/system/etc/init.d}/99otm-pack" ]; then
        printf '  %sboot:%s ATIVO\n' "$C_A" "$C_R"
    else
        printf '  %sboot:%s inativo\n' "$C_A" "$C_R"
    fi
    printf '  %slinhas no perfil de boot:%s %s\n' "$C_A" "$C_R" "$(grep -c . "$BOOT_SH" 2>/dev/null || echo 0)"
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

# otm_drop_caches -> manda o kernel soltar pagecache/dentries/inodes (root)
otm_drop_caches() {
    sh_ok || return 1
    if [ -w /proc/sys/vm/drop_caches ]; then
        sh_run 'echo 3 > /proc/sys/vm/drop_caches' >/dev/null 2>&1
        return 0
    fi
    sh_run 'sync' >/dev/null 2>&1
    return 1
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
