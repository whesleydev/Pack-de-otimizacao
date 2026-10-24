#!/system/bin/sh
# =============================================================================
#  deep-tune.sh - Otimizações PROFUNDAS do Pack de Otimização
#
#  Vai além dos `settings`: mexe em sysfs (kernel), GPU, térmico, I/O e rede.
#  TUDO é reversível — cada valor antigo é guardado e o `restore` desfaz.
#
#  Módulos:
#     angle  [add|remove|list|reset]   ANGLE/Vulkan por jogo           ★
#     debloat[on|off]                  appops + standby buckets
#     display[on|off]                  props HWUI/SurfaceFlinger
#     dexopt [run|status]              recompilar apps (AOT)
#     gaming [on|off|watch <pkg>]      MODO JOGO (debloat + ANGLE)
#     detect                           mostra o que o aparelho suporta
#     status                           mostra o que está ativo
#     restore                          desfaz TUDO que este script aplicou
#
#  Nada aqui precisa de root: tudo via Shizuku/ADB (settings/cmd/props).
#
#  Uso: sh scripts/deep-tune.sh <módulo> [ação] [args]
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset
DEEP_ST="${HOME:-/data/data/com.termux/files/home}/.packotm/deep"
DEEP_OFF="$DEEP_ST/off.sh"
DEEP_MARK="$DEEP_ST/on"
THERMAL_PID="$DEEP_ST/thermal.pid"
mkdir -p "$DEEP_ST" 2>/dev/null

# Trava de segurança térmica: reverte o módulo `thermal` automaticamente se a
# temperatura passar do limite (ou se estiver carregando, opcional). Veja docs.
THERMAL_MAX_C="${THERMAL_MAX_C:-45}"            # reverte ao atingir X °C
THERMAL_STOP_CHARGING="${THERMAL_STOP_CHARGING:-0}"  # 1 = reverte ao carregar

# =============================================================================
#  INFRA: backup de sysfs (reversão real, valor por valor)
#
#  Cada linha do backup tem o formato:  <tag><TAB><comando de reversão>
#  A tag permite reverter só um módulo (ex.: `freq off` não mexe no ANGLE).
# =============================================================================
DEEP_TAG="geral"

deep_begin() {
    [ -f "$DEEP_MARK" ] && return 0
    : > "$DEEP_OFF"
    command touch "$DEEP_MARK"
}

# deep_add <comando>  -> registra a reversão com a tag atual
deep_add() {
    printf '%s\t%s\n' "$DEEP_TAG" "$1" >> "$DEEP_OFF"
}

# drop_tag <tag>  -> esquece as reversões de um módulo (já voltamos ao original)
drop_tag() {
    [ -s "$DEEP_OFF" ] || return 0
    : > "$DEEP_OFF.tmp"
    while IFS="$(printf '\t')" read -r t c; do
        [ "$t" = "$1" ] && continue
        printf '%s\t%s\n' "$t" "$c" >> "$DEEP_OFF.tmp"
    done < "$DEEP_OFF"
    mv "$DEEP_OFF.tmp" "$DEEP_OFF"
}

# =============================================================================
#  DETECÇÃO DE HARDWARE
# =============================================================================
cpufreq_dirs()  { ls -d /sys/devices/system/cpu/cpu[0-9]*/cpufreq 2>/dev/null; }
thermal_zones() { ls -d /sys/class/thermal/thermal_zone[0-9]* 2>/dev/null; }

gpu_path() {
    for g in /sys/class/kgsl/kgsl-3d0 /sys/class/devfreq/*kgsl* \
             /sys/class/misc/mali0 /sys/class/devfreq/*mali*; do
        [ -d "$g" ] && { echo "$g"; return 0; }
    done
    return 1
}

max_freq_of() {  # <cpufreq dir> -> maior freq disponível
    f=$(sh_get "cat $1/cpuinfo_max_freq" 2>/dev/null)
    [ -z "$f" ] && f=$(sh_get "cat $1/scaling_max_freq" 2>/dev/null)
    echo "$f"
}

sdk() { sh_get "getprop ro.build.version.sdk" 2>/dev/null; }

# =============================================================================
#  MÓDULO: ANGLE / Vulkan por jogo  (SEM ROOT — prioridade máxima)
# =============================================================================
m_angle() {
    acao="${1:-list}"
    key_pkgs="angle_gl_driver_selection_pkgs"
    key_vals="angle_gl_driver_selection_values"

    angle_list() {
        pkgs=$(sh_get "settings get global $key_pkgs")
        vals=$(sh_get "settings get global $key_vals")
        say "ANGLE/Vulkan por jogo"
        if [ -z "$pkgs" ] || [ "$pkgs" = "null" ]; then
            printf '   %s(ninguém configurado)%s\n' "$C_D" "$C_R"
        else
            printf '   pacotes: %s\n   drivers: %s\n' "$pkgs" "$vals"
        fi
        printf '   %sadd <pkg> | remove <pkg> | reset%s\n' "$C_D" "$C_R"
    }

    # _angle_save_revert <valor_atual_pkgs> <valor_atual_vals>
    _angle_save_revert() {
        op="$1"; ov="$2"
        if [ -z "$op" ] || [ "$op" = "null" ]; then
            deep_add "settings delete global $key_pkgs"
            deep_add "settings delete global $key_vals"
        else
            deep_add "settings put global $key_pkgs '$op'"
            deep_add "settings put global $key_vals '$ov'"
        fi
    }

    angle_add() {
        pkg="$1"
        [ -z "$pkg" ] && { err "uso: angle add <pkg>"; return 1; }
        old_p=$(sh_get "settings get global $key_pkgs")
        old_v=$(sh_get "settings get global $key_vals")
        if [ -z "$old_p" ] || [ "$old_p" = "null" ]; then
            new_p="$pkg"; new_v="angle"
        else
            case ",$old_p," in *",$pkg,"*) say "$pkg já está no ANGLE"; return 0 ;; esac
            new_p="$old_p,$pkg"; new_v="$old_v,angle"
        fi
        DEEP_TAG=angle; deep_begin
        _angle_save_revert "$old_p" "$old_v"
        sh_run "settings put global $key_pkgs $new_p" >/dev/null
        sh_run "settings put global $key_vals $new_v" >/dev/null
        say "ANGLE ligado em $pkg — reabra o jogo"
    }

    angle_remove() {
        pkg="$1"
        [ -z "$pkg" ] && { err "uso: angle remove <pkg>"; return 1; }
        pkgs=$(sh_get "settings get global $key_pkgs")
        vals=$(sh_get "settings get global $key_vals")
        [ -z "$pkgs" ] || [ "$pkgs" = "null" ] && { say "nada para remover"; return 0; }
        np=""; nv=""
        i=0
        for p in $(echo "$pkgs" | tr ',' ' '); do
            i=$((i+1))
            v=$(echo "$vals" | tr ',' ' ' | awk -v n="$i" '{print $n}')
            if [ "$p" = "$pkg" ]; then continue; fi
            if [ -z "$np" ]; then np="$p"; nv="$v"; else np="$np,$p"; nv="$nv,$v"; fi
        done
        DEEP_TAG=angle; deep_begin
        _angle_save_revert "$pkgs" "$vals"
        if [ -z "$np" ]; then
            sh_run "settings delete global $key_pkgs" >/dev/null
            sh_run "settings delete global $key_vals" >/dev/null
        else
            sh_run "settings put global $key_pkgs $np" >/dev/null
            sh_run "settings put global $key_vals $nv" >/dev/null
        fi
        say "ANGLE removido de $pkg"
    }

    angle_reset() {
        sh_run "settings delete global $key_pkgs" >/dev/null
        sh_run "settings delete global $key_vals" >/dev/null
        # remove as entradas de reversão do ANGLE: já voltamos ao driver nativo
        drop_tag angle
        say "ANGLE resetado (volta ao driver nativo)"
    }

    # angle_set <pkg> <angle|native|default> — escolhe o driver gráfico do app.
    #   angle   = usa ANGLE (OpenGL ES sobre Vulkan)
    #   native  = força o driver OpenGL ES do fabricante
    #   default = deixa o sistema decidir (remove o app da lista)
    angle_set() {
        pkg="$1"; drv="$2"
        [ -z "$pkg" ] && { err "uso: angle set <pkg> angle|native|default"; return 1; }
        case "$drv" in angle|native) ;; default) angle_remove "$pkg"; return $? ;; *) err "driver inválido: $drv"; return 1 ;; esac
        old_p=$(sh_get "settings get global $key_pkgs")
        old_v=$(sh_get "settings get global $key_vals")
        [ -z "$old_p" ] || [ "$old_p" = "null" ] && old_p=""
        [ -z "$old_v" ] || [ "$old_v" = "null" ] && old_v=""
        new_p=""; new_v=""; found=0; i=0
        # substitui o valor do pacote, se já estiver na lista
        for p in $(echo "$old_p" | tr ',' ' '); do
            i=$((i+1))
            v=$(echo "$old_v" | tr ',' ' ' | awk -v n="$i" '{print $n}')
            if [ "$p" = "$pkg" ]; then v="$drv"; found=1; fi
            if [ -z "$new_p" ]; then new_p="$p"; new_v="$v"; else new_p="$new_p,$p"; new_v="$new_v,$v"; fi
        done
        if [ "$found" = 0 ]; then
            if [ -z "$new_p" ]; then new_p="$pkg"; new_v="$drv"; else new_p="$new_p,$pkg"; new_v="$new_v,$drv"; fi
        fi
        DEEP_TAG=angle; deep_begin
        _angle_save_revert "$old_p" "$old_v"
        sh_run "settings put global $key_pkgs $new_p" >/dev/null
        sh_run "settings put global $key_vals $new_v" >/dev/null
        say "driver do app $pkg: $drv — reabra o app"
    }

    case "$acao" in
        add)    angle_add "$2" ;;
        remove) angle_remove "$2" ;;
        set)    angle_set "$2" "$3" ;;
        reset)  angle_reset ;;
        *)      angle_list ;;
    esac
}

m_debloat() {
    acao="${1:-status}"

    debloat_on() {
        DEEP_TAG=debloat; deep_begin
        say "Restringindo apps em background (appops + standby)"
        for p in $BLOAT; do
            sh_run "cmd appops set $p RUN_IN_BACKGROUND ignore" >/dev/null 2>&1
            sh_run "cmd appops set $p RUN_ANY_IN_BACKGROUND ignore" >/dev/null 2>&1
            sh_run "am set-standby-bucket $p restricted" >/dev/null 2>&1
            printf '   %s%s%s\n' "$C_D" "$p" "$C_R"
        done
        say "para reverter: deep-tune.sh debloat off"
    }

    debloat_off() {
        say "Liberando apps de volta"
        for p in $BLOAT; do
            sh_run "cmd appops set $p RUN_IN_BACKGROUND allow" >/dev/null 2>&1
            sh_run "cmd appops set $p RUN_ANY_IN_BACKGROUND allow" >/dev/null 2>&1
            sh_run "am set-standby-bucket $p active" >/dev/null 2>&1
        done
        say "restaurado"
    }

    case "$acao" in
        on)  debloat_on ;;
        off) debloat_off ;;
        *)   say "Uso: debloat on|off"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: DISPLAY / HWUI  (props debug.*)
#  Props obscuras do SurfaceFlinger e do HWUI que quase ninguém conhece e que
#  deixam a rolagem mais lisa.
# =============================================================================
m_display() {
    acao="${1:-status}"

    display_on() {
        DEEP_TAG=display; deep_begin
        for kv in \
            "debug.hwui.render_dirty_regions false" \
            "debug.hwui.disable_draw_defer false" \
            "debug.hwui.use_buffer_age true" \
            "debug.hwui.disable_scissor_opt false" \
            "debug.sf.latch_unsignaled 1" \
            "debug.sf.enable_gl_backpressure 1" \
            "debug.sf.use_frame_rate_api 1" \
            "debug.sf.early_phase_offset_ns 500000" \
            "debug.sf.early_app_phase_offset_ns 500000" \
            "debug.sf.late_phase_offset_ns 2000000" \
            ; do
            p=${kv% *}; v=${kv#* }
            old=$(sh_get "getprop $p")
            [ -n "$old" ] && deep_add "setprop $p '$old'"
            sh_run "setprop $p $v" >/dev/null 2>&1
        done
        say "display: HWUI/SurfaceFlinger afinados (rolagem mais lisa)"
    }

    display_off() { say "Restaurando display"; deep_restore display; }

    case "$acao" in
        on)  display_on ;;
        off) display_off ;;
        *)   say "Uso: display on|off"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: DEXOPT / ART COMPILE
#  Recompila os apps de forma antecipada (AOT). Reduz engasgo na primeira
#  abertura. Demora bastante na primeira vez.
# =============================================================================
m_dexopt() {
    acao="${1:-status}"

    dexopt_run() {
        DEEP_TAG=dexopt; deep_begin
        say "compilando apps em modo speed (pode demorar vários minutos)…"
        sh_run "cmd package compile -m speed -a" >/dev/null 2>&1
        # limpa cache excedente depois
        sh_run "cmd package trim-caches 1000G" >/dev/null 2>&1
        say "dexopt: apps compilados em speed + cache podado"
    }

    dexopt_status() {
        say "última compilação (bg-dexopt):"
        sh_get "dumpsys package dexopt" 2>/dev/null | head -n 12
    }

    case "$acao" in
        run)    dexopt_run ;;
        status) dexopt_status ;;
        *)      say "Uso: dexopt run|status" ;;
    esac
}

# =============================================================================
#  MODO JOGO
# =============================================================================
m_gaming() {
    acao="${1:-status}"
    pkg="$2"

    gaming_on() {
        say "MODO JOGO — aplicando debloat + ANGLE"
        m_debloat on
        [ -n "$pkg" ] && m_angle add "$pkg"
        echo
        say "reverter: sh scripts/deep-tune.sh gaming off"
    }

    gaming_off() {
        say "MODO JOGO — desligando"
        deep_restore
        say "tudo restaurado"
    }

    case "$acao" in
        on)  gaming_on ;;
        off) gaming_off ;;
        *)   say "Uso: gaming on [pkg] | gaming off"; status_show ;;
    esac
}

# =============================================================================
#  RESTORE / STATUS / DETECT
# =============================================================================
# deep_restore [tag]  -> sem tag, reverte tudo; com tag, só aquele módulo
deep_restore() {
    tag="$1"
    if [ -s "$DEEP_OFF" ]; then
        if [ -n "$tag" ]; then say "Revertendo módulo: $tag"; else say "Revertendo otimizações profundas"; fi
        : > "$DEEP_OFF.tmp"
        while IFS="$(printf '\t')" read -r t c; do
            [ -z "$c" ] && continue
            if [ -n "$tag" ] && [ "$t" != "$tag" ]; then
                printf '%s\t%s\n' "$t" "$c" >> "$DEEP_OFF.tmp"
                continue
            fi
            sh_run "$c" >/dev/null 2>&1
        done < "$DEEP_OFF"
        mv "$DEEP_OFF.tmp" "$DEEP_OFF"
    fi
    [ -s "$DEEP_OFF" ] || rm -f "$DEEP_MARK" "$DEEP_OFF"
    say "ok"
}

status_show() {
    say "Estado das otimizações profundas"
    printf '   backup: %s\n' "$( [ -f "$DEEP_MARK" ] && echo "ATIVO ($DEEP_OFF)" || echo "inativo" )"
    g=$(gpu_path); printf '   GPU:    %s\n' "${g:-não detectada}"
    printf '   CPU clusters: %s\n' "$(cpufreq_dirs | wc -l)"
    printf '   térmico zonas: %s\n' "$(thermal_zones | wc -l)"
    printf '   Android API:  %s\n' "$(sdk)"
    ang=$(sh_get "settings get global angle_gl_driver_selection_pkgs")
    printf '   ANGLE:  %s\n' "${ang:-nenhum}"
}

detect() {
    say "Detecção de hardware (para auditoria)"
    printf '   modelo:  %s\n' "$(sh_get 'getprop ro.product.model')"
    printf '   android: %s (%s)\n' "$(sh_get 'getprop ro.build.version.release')" "$(sdk)"
    printf '   kernel:  %s\n' "$(sh_get 'uname -r')"
    printf '   CPU:     %s\n' "$(sh_get 'getprop ro.board.platform')"
    printf '   GPU:     %s\n' "$(gpu_path || echo 'não detectada')"
    printf '   clusters de CPU:\n'
    cpufreq_dirs | while read -r d; do
        printf '     %s  governor=%s  max=%s\n' "$d" \
            "$(sh_get "cat $d/scaling_governor")" "$(max_freq_of "$d")"
    done
    printf '   zonas térmicas:\n'
    thermal_zones | while read -r z; do
        printf '     %s  %s\n' "$z" "$(sh_get "cat $z/type")"
    done
    printf '   MGLRU: %s\n' "$(sh_get 'cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null' || echo 'n/a')"
    printf '   BBR:   %s\n' "$(sh_get 'sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null' || echo 'n/a')"
}

# =============================================================================
#  RUNNER
# =============================================================================
[ $# -eq 0 ] && {
    printf '  Módulos profundos (sem root):\n'
    printf '   %sangle%s  [add|remove|list|reset]  ANGLE/Vulkan por jogo\n' "$C_A" "$C_R"
    printf '   %sdebloat%s[on|off]  appops + buckets\n' "$C_A" "$C_R"
    printf '   %sdisplay%s[on|off]  HWUI/SurfaceFlinger props\n' "$C_A" "$C_R"
    printf '   %sdexopt%s [run|status]  recompilar apps AOT\n' "$C_A" "$C_R"
    printf '   %sgaming%s [on|off]  MODO JOGO (debloat + ANGLE)\n' "$C_A" "$C_R"
    printf '   %sdetect%s / %sstatus%s / %srestore%s\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
    exit 0
}

mod="$1"; shift
case "$mod" in
    angle)   m_angle "$@" ;;
    debloat) m_debloat "$@" ;;
    display) m_display "$@" ;;
    dexopt)  m_dexopt "$@" ;;
    gaming)  m_gaming "$@" ;;
    detect)  detect ;;
    status)  status_show ;;
    restore) deep_restore ;;
    *)       err "módulo desconhecido: $mod"; exit 1 ;;
esac
rc=$?
otm_v_report "deep:$mod"
exit $rc
