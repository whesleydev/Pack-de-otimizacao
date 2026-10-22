#!/system/bin/sh
# =============================================================================
#  cool-down.sh - Modo resfriamento: baixa a temperatura do aparelho.
#
#  Use quando o celular estiver quente. O modo reduz o que esquenta:
#    1) limita a CPU (governor powersave + clock mínimo)
#    2) limita a GPU (clock mínimo)
#    3) no modo "max", desliga os núcleos extras
#    4) baixa o brilho da tela e encerra os apps de fundo
#    5) vigia a temperatura e DESLIGA SOZINHO quando esfriar (ou após o tempo)
#
#  Nada de valor inventado: cada escrita é lida de volta e tudo é reversível.
#  Desliga automático ao atingir a temperatura alvo (padrão 38°C) ou após o
#  tempo máximo (padrão 30 min). Ajuste com CO_TARGET / CO_MAXMIN.
#
#  Uso:
#     cool-down.sh on [normal|max]   # liga o resfriamento
#     cool-down.sh off               # desliga agora (volta tudo ao normal)
#     cool-down.sh status            # temperatura e estado
#
#  Requer root.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

CO_ST="$ST/cooldown"
mkdir -p "$CO_ST" 2>/dev/null
CO_OFF="$CO_ST/off.sh"
CO_MARK="$CO_ST/on"
CO_PID="$CO_ST/watch.pid"
CO_LOG="$CO_ST/watch.log"

CO_TARGET="${CO_TARGET:-38}"     # desliga ao chegar nesta temperatura (°C)
CO_MAXMIN="${CO_MAXMIN:-30}"     # tempo máximo ligado (minutos)

# --- backup próprio do resfriamento (reversão independente) -------------------
co_begin() {
    [ -f "$CO_MARK" ] && return 0
    : > "$CO_OFF"
    command touch "$CO_MARK"
}

co_add() { printf '%s\n' "$1" >> "$CO_OFF"; }

# co_write <caminho sysfs> <valor> -> guarda o antigo, escreve e confirma
co_write() {
    p="$1"; v="$2"
    otm_v_inc apply
    old=$(sh_get "cat $p" 2>/dev/null)
    if [ -n "$old" ]; then
        grep -qF "echo '$old' > $p" "$CO_OFF" 2>/dev/null || co_add "echo '$old' > $p"
    fi
    sh_run "echo '$v' > $p" >/dev/null 2>&1
    now=$(sh_get "cat $p" 2>/dev/null)
    if [ "$now" = "$v" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s = %s\n' "$C_G" "$C_R" "$p" "$v"
    else
        otm_v_inc failed
        printf '   %bX%b %s não mudou (lido: %s)\n' "$C_RD" "$C_R" "$p" "${now:-vazio}"
    fi
}

# co_set <tipo> <chave> <valor> -> settings reversível (guarda só o 1º valor)
co_set() {
    t="$1"; k="$2"; v="$3"
    otm_v_inc apply
    old=$(sh_get "settings get $t $k")
    if ! grep -qE "^settings (put|delete) $t $k( |$)" "$CO_OFF" 2>/dev/null; then
        if [ -z "$old" ] || [ "$old" = "null" ]; then co_add "settings delete $t $k"
        else printf "settings put %s %s %s\n" "$t" "$k" "$old" >> "$CO_OFF"; fi
    fi
    sh_run "settings put $t $k $v" >/dev/null 2>&1
    now=$(sh_get "settings get $t $k")
    if [ "$now" = "$v" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s %s = %s\n' "$C_G" "$C_R" "$t" "$k" "$v"
    else
        otm_v_inc failed
        printf '   %bX%b %s %s não mudou (lido: %s)\n' "$C_RD" "$C_R" "$t" "$k" "${now:-vazio}"
    fi
}

co_cpufreq_dirs() { ls -d /sys/devices/system/cpu/cpu[0-9]*/cpufreq 2>/dev/null; }

co_gpu_path() {
    for g in /sys/class/kgsl/kgsl-3d0 /sys/class/devfreq/*kgsl* \
             /sys/class/misc/mali0 /sys/class/devfreq/*mali*; do
        [ -d "$g" ] && { echo "$g"; return 0; }
    done
    return 1
}

# limita a CPU ao clock mais baixo disponível
co_cpu_cool() {
    n=0
    for d in $(co_cpufreq_dirs); do
        low="$(sh_get "cat $d/scaling_available_frequencies" 2>/dev/null | awk '{print $1}')"
        [ -z "$low" ] && low="$(sh_get "cat $d/scaling_min_freq" 2>/dev/null)"
        [ -z "$low" ] && continue
        govs="$(sh_get "cat $d/scaling_available_governors" 2>/dev/null)"
        case " $govs " in *" powersave "*) co_write "$d/scaling_governor" powersave ;; esac
        co_write "$d/scaling_min_freq" "$low"
        co_write "$d/scaling_max_freq" "$low"
        n=$((n + 1))
    done
    [ "$n" -gt 0 ] && say "CPU limitada ao clock mínimo ($n clusters)" \
                   || warn "este kernel não expõe cpufreq — CPU não ajustada"
}

# limita a GPU ao clock mais baixo
co_gpu_cool() {
    g="$(co_gpu_path)" || { warn "GPU não detectada — nada aplicado"; return 0; }
    if [ -w "$g/min_pwrlevel" ] && [ -r "$g/max_pwrlevel" ]; then
        mx="$(sh_get "cat $g/max_pwrlevel" 2>/dev/null)"
        [ -n "$mx" ] && co_write "$g/min_pwrlevel" "$mx"
    fi
    for dev in "$g" "$g"/devfreq/*; do
        [ -w "$dev/max_freq" ] || continue
        low="$(sh_get "cat $dev/available_frequencies" 2>/dev/null | awk '{print $1}')"
        [ -z "$low" ] && low="$(sh_get "cat $dev/min_freq" 2>/dev/null)"
        [ -z "$low" ] && continue
        co_write "$dev/max_freq" "$low"
    done
    say "GPU limitada ao clock mínimo"
}

# desliga os núcleos extras (modo max)
co_cores_off() {
    n=0
    for on in /sys/devices/system/cpu/cpu[1-9]*/online; do
        [ -w "$on" ] || continue
        co_write "$on" 0 && n=$((n + 1))
    done
    [ "$n" -gt 0 ] && say "$n núcleo(s) desligado(s)" || warn "não deu para desligar núcleos"
}

co_temp() { otm_temp; }

# vigia a temperatura; desliga sozinho ao esfriar ou no tempo máximo
co_watch() {
    [ -f "$CO_PID" ] && kill "$(cat "$CO_PID")" 2>/dev/null
    ticks=$((CO_MAXMIN * 2))
    (
        i=0
        while :; do
            sleep 30
            i=$((i + 1))
            t="$(otm_temp)"
            if [ -n "$t" ] && [ "$t" -le "$CO_TARGET" ]; then
                co_revert "esfriou: ${t}°C ≤ ${CO_TARGET}°C"
                break
            fi
            if [ "$i" -ge "$ticks" ]; then
                co_revert "tempo máximo (${CO_MAXMIN} min) atingido"
                break
            fi
        done
        rm -f "$CO_PID"
    ) >> "$CO_LOG" 2>&1 &
    echo $! > "$CO_PID"
}

# co_revert [mensagem] -> desfaz tudo (usado pelo off e pelo vigia)
co_revert() {
    [ -n "$1" ] && say "$1"
    if [ -s "$CO_OFF" ]; then
        while IFS= read -r c; do
            [ -z "$c" ] && continue
            case "$c" in '#'*) continue ;; esac
            sh_run "$c" >/dev/null 2>&1
        done < "$CO_OFF"
    fi
    rm -f "$CO_OFF" "$CO_MARK" 2>/dev/null
    say "modo resfriamento desligado (tudo de volta ao normal)"
}

cmd_on() {
    modo="${1:-normal}"
    case "$modo" in normal|max) ;; *) err "modo inválido: $modo (normal|max)"; return 1 ;; esac
    require_root "modo resfriamento" || return 1

    printf '  %s◆%s  %sMODO RESFRIAMENTO%s  %s(%s)%s\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$modo" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"

    t0="$(co_temp)"
    [ -n "$t0" ] && say "temperatura agora: ${t0}°C"
    chg="$(sh_get 'dumpsys battery' | awk -F': ' '/ powered:/{print $2}' | tr -d ' ')"
    [ "$chg" = "true" ] && warn "carregando: o aparelho esquenta enquanto carrega. Se puder, tire do carregador."

    co_begin
    say "1/4  Limitando CPU e GPU"
    co_cpu_cool
    co_gpu_cool
    if [ "$modo" = "max" ]; then
        say "2/4  Desligando núcleos extras"
        co_cores_off
    else
        printf '  %s·%s  núcleos extras (use o modo max para desligar)\n' "$C_D" "$C_R"
    fi

    say "3/4  Baixando o brilho da tela"
    co_set system screen_brightness_mode 0
    co_set system screen_brightness 40

    say "4/4  Aliviando o fundo"
    if have_shell; then
        k="$(otm_bg_kill com.dts.freefireth com.dts.freefiremax)"
        say "$k app(s) de fundo encerrado(s)"
        otm_drop_caches
    fi

    if [ -n "$t0" ] && [ -z "$OTM_COOL_NOWATCH" ]; then
        co_watch
        say "vigia ativo: desliga ao chegar em ${CO_TARGET}°C (ou em ${CO_MAXMIN} min)"
    else
        warn "sem leitura de temperatura — desligue na mão com 'cool-down.sh off'"
    fi
    say "resfriamento ligado. Para parar antes: cool-down.sh off"
}

cmd_off() {
    [ -f "$CO_PID" ] && kill "$(cat "$CO_PID")" 2>/dev/null
    rm -f "$CO_PID" 2>/dev/null
    say "Desligando o modo resfriamento"
    co_revert
}

cmd_status() {
    printf '  %s◆%s  %sRESFRIAMENTO · estado%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    t="$(co_temp)"
    printf '  %stemperatura:%s %s\n' "$C_A" "$C_R" "${t:+${t}°C}${t:-indisponível}"
    if [ -f "$CO_MARK" ]; then
        printf '  %smodo:%s %sLIGADO%s (alvo %s°C)\n' "$C_A" "$C_R" "$C_G" "$C_R" "$CO_TARGET"
    else
        printf '  %smodo:%s desligado\n' "$C_A" "$C_R"
    fi
    for d in $(co_cpufreq_dirs); do
        printf '  %s%s:%s max %s\n' "$C_A" "$(basename "$(dirname "$d")")" "$C_R" \
            "$(sh_get "cat $d/scaling_max_freq" 2>/dev/null)"
    done
}

case "${1:-}" in
    on)     shift; cmd_on "$@" ;;
    off)    cmd_off ;;
    status) cmd_status ;;
    *)      sed -n '3,24p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report cool-down
exit $rc
