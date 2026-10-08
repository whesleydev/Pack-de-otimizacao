#!/system/bin/sh
# =============================================================================
#  deep-tune.sh - Otimizações PROFUNDAS do Pack de Otimização
#
#  Vai além dos `settings`: mexe em sysfs (kernel), GPU, térmico, I/O e rede.
#  TUDO é reversível — cada valor antigo é guardado e o `restore` desfaz.
#
#  Módulos:
#     angle  [add|remove|list|reset]   ANGLE/Vulkan por jogo (SEM root)  ★
#     freq   [on|off]                  trava frequência de CPU/GPU      (root)
#     thermal[on|off]                  afrouxa o limite térmico         (root) ⚠️
#     io     [on|off]                  scheduler none + fstrim          (root)
#     mem    [on|off]                  MGLRU + zRAM + KSM + swappiness (root)
#     net    [on|off]                  TCP BBR + fq_codel               (root)
#     latency[on|off]                  SurfaceFlinger / vsync           (root)
#     debloat[on|off]                  appops + standby buckets         (sem root)
#     gaming [on|off|watch <pkg>]      MODO JOGO TURBO (liga tudo junto)
#     detect                           mostra o que o aparelho suporta
#     status                           mostra o que está ativo
#     restore                          desfaz TUDO que este script aplicou
#
#  Uso: sh scripts/deep-tune.sh <módulo> [ação] [args]
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

DEEP_ST="${HOME:-/data/data/com.termux/files/home}/.packotm/deep"
DEEP_OFF="$DEEP_ST/off.sh"
DEEP_MARK="$DEEP_ST/on"
mkdir -p "$DEEP_ST" 2>/dev/null

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

# sys_write <path> <valor>  -> guarda o valor antigo e escreve o novo
sys_write() {
    p="$1"; v="$2"
    old=$(sh_get "cat $p" 2>/dev/null)
    [ -n "$old" ] && deep_add "echo '$old' > $p"
    sh_run "echo '$v' > $p" >/dev/null 2>&1
}

# sysctl_write <chave> <valor>
sysctl_write() {
    k="$1"; v="$2"
    old=$(sh_get "sysctl -n $k" 2>/dev/null)
    [ -n "$old" ] && deep_add "sysctl -w $k=$old"
    sh_run "sysctl -w $k=$v" >/dev/null 2>&1
}

writable() { [ -w "$1" ] 2>/dev/null; }

# =============================================================================
#  DETECÇÃO DE HARDWARE
# =============================================================================
cpu_list()      { ls -d /sys/devices/system/cpu/cpu[0-9]* 2>/dev/null; }
cpufreq_dirs()  { ls -d /sys/devices/system/cpu/cpu[0-9]*/cpufreq 2>/dev/null; }
thermal_zones() { ls -d /sys/class/thermal/thermal_zone[0-9]* 2>/dev/null; }
block_devs()    { ls -d /sys/block/sd* /sys/block/mmcblk* /sys/block/ufs* /sys/block/nvme* 2>/dev/null; }

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

    case "$acao" in
        add)    angle_add "$2" ;;
        remove) angle_remove "$2" ;;
        reset)  angle_reset ;;
        *)      angle_list ;;
    esac
}

# =============================================================================
#  MÓDULO: FREQUÊNCIA DE CPU/GPU  (root)
# =============================================================================
m_freq() {
    acao="${1:-status}"

    freq_on() {
        require_root || return 1
        DEEP_TAG=freq; deep_begin
        n=0
        for d in $(cpufreq_dirs); do
            gov=$(sh_get "cat $d/scaling_governor" 2>/dev/null)
            [ -n "$gov" ] && sys_write "$d/scaling_governor" performance
            mx=$(max_freq_of "$d")
            [ -n "$mx" ] && sys_write "$d/scaling_min_freq" "$mx"
            n=$((n+1))
        done
        g=$(gpu_path)
        if [ -n "$g" ]; then
            # Adreno: min_pwrlevel 0 = clock máximo
            if [ -w "$g/min_pwrlevel" ]; then
                sys_write "$g/min_pwrlevel" 0
            fi
            # devfreq: governor performance
            if [ -d "$g/devfreq" ] && [ -w "$g/devfreq/governor" ]; then
                sys_write "$g/devfreq/governor" performance
            elif [ -w "$g/governor" ]; then
                sys_write "$g/governor" performance
            fi
        fi
        say "CPU/GPU no topo ($n clusters) — reverter: deep-tune.sh freq off"
    }

    freq_off() { say "Voltando frequência para o padrão"; deep_restore freq; }

    case "$acao" in
        on)  freq_on ;;
        off) freq_off ;;
        *)   say "Uso: freq on|off"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: TÉRMICO  (root)  ⚠️ aviso
# =============================================================================
m_thermal() {
    acao="${1:-status}"

    thermal_on() {
        require_root || return 1
        DEEP_TAG=thermal; warn "Isso AFROUXA a proteção térmica: mais FPS sustentado, MAIS CALOR."
        warn "Use só jogando e com o celular ventilado. Risco de aquecimento."
        deep_begin
        n=0
        for z in $(thermal_zones); do
            t=$(sh_get "cat $z/type" 2>/dev/null)
            case "$t" in
                cpu|gpu|soc|tsens*|big*|little*|*skin*) ;;
                *) continue ;;
            esac
            # eleva o trip point crítico se existir
            for tp in "$z"/trip_point_*_temp; do
                [ -f "$tp" ] || continue
                old=$(sh_get "cat $tp" 2>/dev/null)
                case "$old" in ''|*[!0-9]*) continue ;; esac
                [ "$old" -lt 60000 ] && continue   # só trip points "quentes"
                novo=$((old + 5000))               # +5 °C
                sys_write "$tp" "$novo"
                n=$((n+1))
            done
            # desativa o cooling device de throttling, se der
            [ -w "$z/mode" ] && sys_write "$z/mode" disabled
        done
        if [ "$n" = "0" ]; then
            warn "nenhum trip point ajustável neste kernel — nada aplicado"
        else
            say "térmico afrouxado (+5°C em $n pontos) — reverter: deep-tune.sh thermal off"
        fi
    }

    thermal_off() { say "Restaurando limites térmicos"; deep_restore thermal; }

    case "$acao" in
        on)  thermal_on ;;
        off) thermal_off ;;
        *)   say "Uso: thermal on|off (⚠️ esquenta mais)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: I/O  (root)
# =============================================================================
m_io() {
    acao="${1:-status}"

    io_on() {
        require_root || return 1
        DEEP_TAG=io; deep_begin
        for b in $(block_devs); do
            [ -w "$b/queue/scheduler" ] && sys_write "$b/queue/scheduler" none
            [ -w "$b/queue/read_ahead_kb" ] && sys_write "$b/queue/read_ahead_kb" 4096
            [ -w "$b/queue/iostats" ] && sys_write "$b/queue/iostats" 0
            [ -w "$b/queue/nr_requests" ] && sys_write "$b/queue/nr_requests" 128
        done
        sh_run "sm fstrim" >/dev/null 2>&1
        say "I/O: scheduler none, read_ahead 4096, fstrim feito"
    }

    io_off() { say "Restaurando I/O"; deep_restore io; }

    case "$acao" in
        on)  io_on ;;
        off) io_off ;;
        *)   say "Uso: io on|off"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: MEMÓRIA  (root)
# =============================================================================
m_mem() {
    acao="${1:-status}"

    mem_on() {
        require_root || return 1
        DEEP_TAG=mem; deep_begin
        # MGLRU (kernel 6.1+ / Android 13+)
        [ -w /sys/kernel/mm/lru_gen/enabled ] && sys_write /sys/kernel/mm/lru_gen/enabled 1
        # KSM (merge de páginas iguais)
        [ -w /sys/kernel/mm/ksm/run ] && sys_write /sys/kernel/mm/ksm/run 1
        # swappiness
        [ -w /proc/sys/vm/swappiness ] && sysctl_write vm.swappiness 100
        # dirty ratio (menos picos de escrita)
        [ -w /proc/sys/vm/dirty_ratio ] && sysctl_write vm.dirty_ratio 15
        [ -w /proc/sys/vm/dirty_background_ratio ] && sysctl_write vm.dirty_background_ratio 5
        # zRAM: aumenta se existir
        for z in /sys/block/zram*/disksize; do
            [ -w "$z" ] && sys_write "$z" $((3 * 1024 * 1024 * 1024))
        done
        say "memória: MGLRU + KSM + swappiness 100 + zRAM"
    }

    mem_off() { say "Restaurando memória"; deep_restore mem; }

    case "$acao" in
        on)  mem_on ;;
        off) mem_off ;;
        *)   say "Uso: mem on|off"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: REDE  (root)
# =============================================================================
m_net() {
    acao="${1:-status}"

    net_on() {
        require_root || return 1
        DEEP_TAG=net; deep_begin
        # TCP BBR
        if sh_get "sysctl -n net.ipv4.tcp_available_congestion_control" | grep -q bbr; then
            sysctl_write net.ipv4.tcp_congestion_control bbr
        else
            warn "BBR não disponível neste kernel"
        fi
        sysctl_write net.ipv4.tcp_fastopen 3
        sysctl_write net.ipv4.tcp_low_latency 1
        sysctl_write net.core.rmem_max 6291456
        sysctl_write net.core.wmem_max 6291456
        # qdisc fq_codel na interface ativa
        if have tc || sh_run "command -v tc" >/dev/null 2>&1; then
            ifc=$(sh_get "ip route get 1.1.1.1 2>/dev/null | awk '{print \$5; exit}'")
            [ -n "$ifc" ] && sh_run "tc qdisc replace dev $ifc root fq_codel" >/dev/null 2>&1
        fi
        say "rede: BBR + fastopen + buffers + fq_codel"
    }

    net_off() { say "Restaurando rede"; deep_restore net; }

    case "$acao" in
        on)  net_on ;;
        off) net_off ;;
        *)   say "Uso: net on|off"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: LATÊNCIA (SurfaceFlinger / vsync)  (root)
# =============================================================================
m_latency() {
    acao="${1:-status}"

    lat_on() {
        require_root || return 1
        DEEP_TAG=latency; deep_begin
        for p in debug.sf.latch_unsignaled debug.sf.enable_gl_backpressure; do
            old=$(sh_get "getprop $p")
            [ -n "$old" ] && deep_add "setprop $p '$old'"
            sh_run "setprop $p 1" >/dev/null
        done
        say "latência: latch_unsignaled + gl_backpressure"
    }

    lat_off() { say "Restaurando latência"; deep_restore latency; }

    case "$acao" in
        on)  lat_on ;;
        off) lat_off ;;
        *)   say "Uso: latency on|off"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: DEBLOAT REAL  (sem root)
# =============================================================================
BLOAT="com.facebook.katana com.facebook.orca com.instagram.android \
com.ss.android.ugc.trill com.ss.android.ugc.aweme com.twitter.android \
com.google.android.youtube com.android.chrome com.spotify.music com.discord"

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
#  MODO JOGO TURBO  (liga tudo junto, com reversão automática)
# =============================================================================
m_gaming() {
    acao="${1:-status}"
    pkg="$2"

    gaming_on() {
        say "MODO JOGO TURBO — ligando tudo"
        m_freq on
        m_io on
        m_mem on
        m_net on
        m_latency on
        m_debloat on
        [ -n "$pkg" ] && m_angle add "$pkg"
        m_thermal on
        echo
        warn "TURBO ativo: frequência no topo + térmico afrouxado (esquenta mais)."
        say "reverter: sh scripts/deep-tune.sh gaming off"
    }

    gaming_off() {
        say "MODO JOGO TURBO — desligando"
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
    printf '   root:   %s\n' "$(sh_ok && echo sim || echo não)"
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
    printf '  Módulos profundos:\n'
    printf '   %sangle%s [add|remove|list|reset]  ANGLE/Vulkan por jogo (sem root)\n' "$C_A" "$C_R"
    printf '   %sfreq%s   [on|off]  frequência CPU/GPU (root)\n' "$C_A" "$C_R"
    printf '   %sthermal%s[on|off]  limite térmico (root, ⚠️ esquenta)\n' "$C_A" "$C_R"
    printf '   %sio%s     [on|off]  scheduler + fstrim (root)\n' "$C_A" "$C_R"
    printf '   %smem%s    [on|off]  MGLRU + zRAM + KSM (root)\n' "$C_A" "$C_R"
    printf '   %snet%s    [on|off]  TCP BBR + fq_codel (root)\n' "$C_A" "$C_R"
    printf '   %slatency%s[on|off]  SurfaceFlinger/vsync (root)\n' "$C_A" "$C_R"
    printf '   %sdebloat%s[on|off]  appops + buckets (sem root)\n' "$C_A" "$C_R"
    printf '   %sgaming%s [on|off]  MODO JOGO TURBO (tudo junto)\n' "$C_A" "$C_R"
    printf '   %sdetect%s / %sstatus%s / %srestore%s\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
    exit 0
}

mod="$1"; shift
case "$mod" in
    angle)   m_angle "$@" ;;
    freq)    m_freq "$@" ;;
    thermal) m_thermal "$@" ;;
    io)      m_io "$@" ;;
    mem)     m_mem "$@" ;;
    net)     m_net "$@" ;;
    latency) m_latency "$@" ;;
    debloat) m_debloat "$@" ;;
    gaming)  m_gaming "$@" ;;
    detect)  detect ;;
    status)  status_show ;;
    restore) deep_restore ;;
    *)       err "módulo desconhecido: $mod"; exit 1 ;;
esac
