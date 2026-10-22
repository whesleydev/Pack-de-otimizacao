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

# sys_write <path> <valor>  -> guarda o valor antigo, escreve e confirma
sys_write() {
    p="$1"; v="$2"
    otm_v_inc apply
    old=$(sh_get "cat $p" 2>/dev/null)
    [ -n "$old" ] && deep_add "echo '$old' > $p"
    sh_run "echo '$v' > $p" >/dev/null 2>&1
    now=$(sh_get "cat $p" 2>/dev/null)
    if [ "$now" = "$v" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s = %s\n' "$C_G" "$C_R" "$p" "$v"
    else
        otm_v_inc failed
        printf '   %bX%b %s nao mudou (lido: %s)\n' "$C_RD" "$C_R" "$p" "${now:-vazio}"
    fi
}

# sysctl_write <chave> <valor>
sysctl_write() {
    k="$1"; v="$2"
    otm_v_inc apply
    old=$(sh_get "sysctl -n $k" 2>/dev/null)
    [ -n "$old" ] && deep_add "sysctl -w $k=$old"
    sh_run "sysctl -w $k=$v" >/dev/null 2>&1
    now=$(sh_get "sysctl -n $k" 2>/dev/null)
    if [ "$now" = "$v" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s = %s\n' "$C_G" "$C_R" "$k" "$v"
    else
        otm_v_inc failed
        printf '   %bX%b %s nao mudou (lido: %s)\n' "$C_RD" "$C_R" "$k" "${now:-vazio}"
    fi
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

    # temperatura em °C (melhor zona disponível) — vazio se não der para ler
    thermal_temp() {
        for z in $(thermal_zones); do
            t=$(sh_get "cat $z/type" 2>/dev/null)
            case "$t" in soc|*skin*|cpu*|gpu*) ;; *) continue ;; esac
            v=$(sh_get "cat $z/temp" 2>/dev/null)
            case "$v" in ''|*[!0-9-]*) continue ;; esac
            [ "$v" -gt 1000 ] && v=$((v/1000))
            echo "$v"; return 0
        done
        # fallback: bateria
        v=$(sh_get 'dumpsys battery' | awk -F': ' '/ temperature:/{print $2}')
        [ -n "$v" ] && echo "$((v/10))"
    }

    thermal_charging() {
        [ "$(sh_get 'dumpsys battery' | awk -F': ' '/ powered:/{print $2}' | tr -d ' ')" = "true" ]
    }

    # Vigia em segundo plano: se passar do limite (ou carregar), reverte thermal.
    thermal_watch() {
        [ -f "$THERMAL_PID" ] && kill "$(cat "$THERMAL_PID")" 2>/dev/null
        (
            while :; do
                sleep 30
                t="$(thermal_temp)"
                if [ -n "$t" ] && [ "$t" -ge "$THERMAL_MAX_C" ]; then
                    say "TRAVA TÉRMICA: ${t}°C ≥ ${THERMAL_MAX_C}°C — revertendo térmico"
                    deep_restore thermal
                    break
                fi
                if [ "$THERMAL_STOP_CHARGING" = "1" ] && thermal_charging; then
                    say "TRAVA TÉRMICA: carregando — revertendo térmico"
                    deep_restore thermal
                    break
                fi
            done
            rm -f "$THERMAL_PID"
        ) >> "$DEEP_ST/thermal.log" 2>&1 &
        echo $! > "$THERMAL_PID"
    }

    thermal_watch_stop() {
        [ -f "$THERMAL_PID" ] && kill "$(cat "$THERMAL_PID")" 2>/dev/null
        rm -f "$THERMAL_PID"
    }

    thermal_on() {
        require_root || return 1
        # confirmação explícita: exige THERMAL_OK=1 ou "sim" em terminal
        if [ "$THERMAL_OK" != "1" ]; then
            if [ -t 0 ]; then
                printf '  %b!%b  Afrouxar o limite térmico esquenta mais o aparelho.\n' "$C_Y" "$C_R"
                printf '      Continuar? [s/N] '
                read -r r
                case "$r" in s|S|sim|SIM|y|Y) ;; *) warn "cancelado."; return 0 ;; esac
            else
                warn "Não interativo: use THERMAL_OK=1 para confirmar (segurança)."
                return 1
            fi
        fi
        DEEP_TAG=thermal; warn "Isso AFROUXA a proteção térmica: mais FPS sustentado, MAIS CALOR."
        warn "Use só jogando e com o celular ventilado. Trava automática em ${THERMAL_MAX_C}°C."
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
            thermal_watch
            say "térmico afrouxado (+5°C em $n pontos) — trava em ${THERMAL_MAX_C}°C; reverter: thermal off"
        fi
    }

    thermal_off() {
        thermal_watch_stop
        say "Restaurando limites térmicos"; deep_restore thermal
    }

    case "$acao" in
        on)   thermal_on ;;
        off)  thermal_off ;;
        temp) t="$(thermal_temp)"; [ -n "$t" ] && say "temperatura atual: ${t}°C" || warn "não consegui ler a temperatura" ;;
        *)    say "Uso: thermal on|off|temp (⚠️ esquenta mais)"; status_show ;;
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
#  MÓDULO: VM / KERNEL DE MEMÓRIA  (root, extremo)
#  Ajusta o gerenciador de memória virtual do kernel. Pouco conhecido e muito
#  eficaz contra engasgo de I/O e "reabrir app lento".
# =============================================================================
m_vm() {
    acao="${1:-status}"

    vm_on() {
        require_root || return 1
        DEEP_TAG=vm; deep_begin
        VM="${DEEP_VM_DIR:-/proc/sys/vm}"
        # cache de dentries/inodes menos agressivo -> apps reabrem rápido
        [ -w "$VM/vfs_cache_pressure" ] && sysctl_write vm.vfs_cache_pressure 50
        # escrita em blocos maiores = menos microtravadas
        [ -w "$VM/dirty_ratio" ] && sysctl_write vm.dirty_ratio 20
        [ -w "$VM/dirty_background_ratio" ] && sysctl_write vm.dirty_background_ratio 5
        [ -w "$VM/dirty_expire_centisecs" ] && sysctl_write vm.dirty_expire_centisecs 3000
        [ -w "$VM/dirty_writeback_centisecs" ] && sysctl_write vm.dirty_writeback_centisecs 3000
        # reserva de memória e resposta do reclaim
        [ -w "$VM/min_free_kbytes" ] && sysctl_write vm.min_free_kbytes 16384
        [ -w "$VM/watermark_scale_factor" ] && sysctl_write vm.watermark_scale_factor 200
        [ -w "$VM/watermark_boost_factor" ] && sysctl_write vm.watermark_boost_factor 0
        [ -w "$VM/compaction_proactiveness" ] && sysctl_write vm.compaction_proactiveness 0
        [ -w "$VM/page-cluster" ] && sysctl_write vm.page-cluster 0
        [ -w "$VM/stat_interval" ] && sysctl_write vm.stat_interval 1
        say "vm: cache_pressure 50, dirty suave, min_free 16MB, watermark 200"
    }

    vm_off() { say "Restaurando vm"; deep_restore vm; }

    case "$acao" in
        on)  vm_on ;;
        off) vm_off ;;
        *)   say "Uso: vm on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: ESCALONADOR DE CPU / EAS  (root, extremo)
#  Mexe em como o kernel distribui tarefas e acorda núcleos. Menos "pulos" de
#  clock e resposta mais imediata ao toque.
# =============================================================================
m_sched() {
    acao="${1:-status}"

    sched_on() {
        require_root || return 1
        DEEP_TAG=sched; deep_begin
        [ -w /proc/sys/kernel/sched_migration_cost_ns ] && sysctl_write kernel.sched_migration_cost_ns 5000000
        [ -w /proc/sys/kernel/sched_min_granularity_ns ] && sysctl_write kernel.sched_min_granularity_ns 10000000
        [ -w /proc/sys/kernel/sched_wakeup_granularity_ns ] && sysctl_write kernel.sched_wakeup_granularity_ns 15000000
        [ -w /proc/sys/kernel/sched_latency_ns ] && sysctl_write kernel.sched_latency_ns 20000000
        [ -w /proc/sys/kernel/sched_boost ] && sysctl_write kernel.sched_boost 1
        [ -w /proc/sys/kernel/sched_tunable_scaling ] && sysctl_write kernel.sched_tunable_scaling 1
        # schedtune (EAS): dá boost ao app em foco
        for d in /dev/stune/top-app /dev/cpuset/top-app /dev/stune/foreground; do
            [ -w "$d/schedtune.boost" ] && sys_write "$d/schedtune.boost" 10
            [ -w "$d/schedtune.prefer_idle" ] && sys_write "$d/schedtune.prefer_idle" 1
        done
        say "sched: migração/granularidade p/ fluidez + boost no app em foco"
    }

    sched_off() { say "Restaurando escalonador"; deep_restore sched; }

    case "$acao" in
        on)  sched_on ;;
        off) sched_off ;;
        *)   say "Uso: sched on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: GPU EXTREMO (Adreno/KGSL, Mali/devfreq)  (root)
#  Trava clock no topo e desliga economia de energia da GPU — o que mais pesa
#  em jogo e quase ninguém ajusta.
# =============================================================================
m_gpu() {
    acao="${1:-status}"

    gpu_on() {
        require_root || return 1
        g=$(gpu_path) || { warn "GPU não detectada"; return 1; }
        DEEP_TAG=gpu; deep_begin
        # Adreno (KGSL)
        for k in force_clk_on force_bus_on force_rail_on; do
            [ -w "$g/$k" ] && sys_write "$g/$k" 1
        done
        [ -w "$g/idle_timer" ] && sys_write "$g/idle_timer" 0
        [ -w "$g/throttling" ] && sys_write "$g/throttling" 0
        [ -w "$g/bus_split" ] && sys_write "$g/bus_split" 0
        for k in default_pwrlevel min_pwrlevel; do
            [ -w "$g/$k" ] && sys_write "$g/$k" 0     # 0 = nível de potência máximo
        done
        [ -w "$g/devfreq/governor" ] && sys_write "$g/devfreq/governor" performance
        # devfreq genérico (Mali, etc.)
        for d in /sys/class/devfreq/*gpu* /sys/class/devfreq/*mali*; do
            [ -d "$d" ] || continue
            [ -w "$d/governor" ] && sys_write "$d/governor" performance
            mx=$(sh_get "cat $d/max_freq" 2>/dev/null)
            [ -n "$mx" ] && [ -w "$d/min_freq" ] && sys_write "$d/min_freq" "$mx"
        done
        say "gpu: clock no topo, idle_timer off, throttling off"
    }

    gpu_off() { say "Restaurando GPU"; deep_restore gpu; }

    case "$acao" in
        on)  gpu_on ;;
        off) gpu_off ;;
        *)   say "Uso: gpu on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: NÚCLEOS (core_ctl / hotplug)  (root)
#  Mantém os núcleos ligados em vez de desligá-los. Reduz o atraso de "acordar"
#  núcleo no meio da ação. Gasta mais bateria.
# =============================================================================
m_cores() {
    acao="${1:-status}"; n="${2:-}"

    cores_on() {
        require_root || return 1
        DEEP_TAG=cores; deep_begin
        for d in /sys/devices/system/cpu/cpu[0-9]*/core_ctl; do
            [ -w "$d/max_cpus" ] && sys_write "$d/max_cpus" 0     # 0 = sem limite
            [ -w "$d/min_cpus" ] && sys_write "$d/min_cpus" 4
            [ -w "$d/enable" ] && sys_write "$d/enable" 0
        done
        for d in /sys/module/msm_performance/parameters; do
            [ -w "$d/max_cpus" ] && sys_write "$d/max_cpus" 8
            [ -w "$d/min_cpus" ] && sys_write "$d/min_cpus" 8
        done
        for c in /sys/devices/system/cpu/cpu[0-9]*/online; do
            [ -w "$c" ] && sys_write "$c" 1
        done
        say "cores: núcleos sempre ligados ${n:+($n)} — mais desempenho, mais bateria"
    }

    cores_off() { say "Restaurando hotplug"; deep_restore cores; }

    case "$acao" in
        on)  cores_on ;;
        off) cores_off ;;
        *)   say "Uso: cores on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MODULO: BOOST DE TOQUE (input boost)  (root)
#  Sobe a frequência da CPU na hora do toque. É o que dá a sensação de
#  "resposta instantânea". Knobs diferentes por fabricante.
# =============================================================================
m_input() {
    acao="${1:-status}"

    input_on() {
        require_root || return 1
        DEEP_TAG=input; deep_begin
        n=0
        for f in /sys/module/cpu_boost/parameters/input_boost_freq \
                 /sys/module/msm_performance/parameters/touchboost; do
            [ -w "$f" ] || continue
            mx=$(max_freq_of "$(cpufreq_dirs | head -1)")
            sys_write "$f" "${mx:-1401000}"; n=$((n+1))
        done
        for f in /sys/module/cpu_boost/parameters/input_boost_ms \
                 /sys/module/cpu_boost/parameters/input_boost_duration; do
            [ -w "$f" ] && { sys_write "$f" 880; n=$((n+1)); }
        done
        [ -w /sys/module/cpu_boost/parameters/sched_boost_on_input ] && sys_write /sys/module/cpu_boost/parameters/sched_boost_on_input Y
        if [ "$n" = 0 ]; then warn "este kernel não expõe input boost — nada aplicado"; else
            say "input boost: CPU sobe no toque ($n knobs)"; fi
    }

    input_off() { say "Restaurando input boost"; deep_restore input; }

    case "$acao" in
        on)  input_on ;;
        off) input_off ;;
        *)   say "Uso: input on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: ZRAM AVANÇADO  (root)
#  Troca o algoritmo de compressão da memória (lz4 -> zstd) e mexe no
#  swappiness. Mais RAM efetiva (troca CPU por memória).
# =============================================================================
m_zram() {
    acao="${1:-status}"

    zram_on() {
        require_root || return 1
        DEEP_TAG=zram; deep_begin
        n=0
        for z in /sys/block/zram0; do
            [ -d "$z" ] || continue
            algo=$(sh_get "cat $z/comp_algorithm" 2>/dev/null)
            case "$algo" in *zstd*) sys_write "$z/comp_algorithm" zstd; n=$((n+1)) ;; esac
            [ -w "$z/mem_limit" ] && { sys_write "$z/mem_limit" $((3 * 1024 * 1024 * 1024)); n=$((n+1)); }
        done
        [ -w /proc/sys/vm/swappiness ] && sysctl_write vm.swappiness 160
        [ -w /proc/sys/vm/page-cluster ] && sysctl_write vm.page-cluster 0
        say "zram: zstd + mem_limit 3G + swappiness 160 ($n knobs)"
    }

    zram_off() { say "Restaurando zram"; deep_restore zram; }

    case "$acao" in
        on)  zram_on ;;
        off) zram_off ;;
        status) say "zram:"; sh_get "cat /sys/block/zram0/comp_algorithm" 2>/dev/null ;;
        *)   say "Uso: zram on|off|status (root)" ;;
    esac
}

# =============================================================================
#  MÓDULO: KERNEL MISC  (root)
#  Desliga rastreamento/debug do kernel (overhead silencioso) e sobe limites do
#  sistema. Ganho pequeno e constante.
# =============================================================================
m_kernel() {
    acao="${1:-status}"

    kernel_on() {
        require_root || return 1
        DEEP_TAG=kernel; deep_begin
        [ -w /proc/sys/kernel/printk ] && sysctl_write kernel.printk "0 0 0 0"
        [ -w /sys/kernel/debug/tracing/tracing_on ] && sys_write /sys/kernel/debug/tracing/tracing_on 0
        [ -w /proc/sys/kernel/sched_schedstats ] && sysctl_write kernel.sched_schedstats 0
        [ -w /proc/sys/fs/file-max ] && sysctl_write fs.file-max 131072
        [ -w /proc/sys/fs/inotify/max_user_watches ] && sysctl_write fs.inotify.max_user_watches 524288
        [ -w /proc/sys/fs/inotify/max_user_instances ] && sysctl_write fs.inotify.max_user_instances 1024
        [ -w /proc/sys/net/core/netdev_max_backlog ] && sysctl_write net.core.netdev_max_backlog 5000
        [ -w /proc/sys/net/core/somaxconn ] && sysctl_write net.core.somaxconn 1024
        say "kernel: tracing/debug off, file-max e backlog acima"
    }

    kernel_off() { say "Restaurando kernel"; deep_restore kernel; }

    case "$acao" in
        on)  kernel_on ;;
        off) kernel_off ;;
        *)   say "Uso: kernel on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: CPU IDLE  (root)
#  Escolhe o governor de idle. `menu` responde mais rápido (latência), `teo`
#  economiza bateria. Útil para quem quer resposta e não se importa com consumo.
# =============================================================================
m_idle() {
    acao="${1:-status}"

    idle_on() {
        require_root || return 1
        DEEP_TAG=idle; deep_begin
        n=0
        for gov in /sys/devices/system/cpu/cpuidle/current_governor \
                   /sys/devices/system/cpu/cpu0/cpuidle/governor; do
            [ -w "$gov" ] && { sys_write "$gov" menu; n=$((n+1)); }
        done
        # limita o estado de idle mais profundo (menos atraso ao acordar)
        for d in /sys/devices/system/cpu/cpu*/cpuidle/state*/disable; do
            [ -w "$d" ] && sys_write "$d" 1        # desliga idle profundo; guardado p/ reverter
        done
        say "idle: governor menu + idle profundo desligado ($n govs) — resposta melhor, gasta mais"
    }

    idle_off() { say "Restaurando idle"; deep_restore idle; }

    case "$acao" in
        on)  idle_on ;;
        off) idle_off ;;
        *)   say "Uso: idle on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: REDE AVANÇADA 2  (root)
#  Além do BBR: desliga slow-start após ocioso, liga MTU probing, reaproveita
#  conexões e ajusta buffers finos. Menos lag em jogos online.
# =============================================================================
m_net2() {
    acao="${1:-status}"

    net2_on() {
        require_root || return 1
        DEEP_TAG=net2; deep_begin
        cc=$(sh_get "sysctl -n net.ipv4.tcp_available_congestion_control" 2>/dev/null)
        case "$cc" in *bbr2*) sysctl_write net.ipv4.tcp_congestion_control bbr2 ;;
                       *bbr*)  sysctl_write net.ipv4.tcp_congestion_control bbr ;;
                       *) warn "BBR/BBR2 indisponível" ;; esac
        [ -w /proc/sys/net/ipv4/tcp_slow_start_after_idle ] && sysctl_write net.ipv4.tcp_slow_start_after_idle 0
        [ -w /proc/sys/net/ipv4/tcp_mtu_probing ] && sysctl_write net.ipv4.tcp_mtu_probing 1
        [ -w /proc/sys/net/ipv4/tcp_notsent_lowat ] && sysctl_write net.ipv4.tcp_notsent_lowat 131072
        [ -w /proc/sys/net/ipv4/tcp_no_metrics_save ] && sysctl_write net.ipv4.tcp_no_metrics_save 1
        [ -w /proc/sys/net/ipv4/tcp_tw_reuse ] && sysctl_write net.ipv4.tcp_tw_reuse 1
        [ -w /proc/sys/net/ipv4/tcp_fin_timeout ] && sysctl_write net.ipv4.tcp_fin_timeout 15
        [ -w /proc/sys/net/ipv4/tcp_rmem ] && sysctl_write net.ipv4.tcp_rmem "4096 262144 6291456"
        [ -w /proc/sys/net/ipv4/tcp_wmem ] && sysctl_write net.ipv4.tcp_wmem "4096 262144 6291456"
        [ -w /proc/sys/net/core/rps_sock_flow_entries ] && sysctl_write net.core.rps_sock_flow_entries 32768
        say "rede2: BBR2/BBR + MTU probing + slow-start off + buffers finos"
    }

    net2_off() { say "Restaurando rede avançada"; deep_restore net2; }

    case "$acao" in
        on)  net2_on ;;
        off) net2_off ;;
        *)   say "Uso: net2 on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: DISPLAY / HWUI  (sem root — props debug.*)
#  Props obscuras do SurfaceFlinger e do HWUI que quase ninguém conhece e que
#  deixam a rolagem mais lisa. Não precisa de root para `debug.*`.
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
#  MÓDULO: DALVIK / ART  (root)
#  Ajusta os heaps da máquina virtual e o filtro de compilação. Ajuda apps
#  grandes (jogos) a não sofrerem GC no meio do uso.
# =============================================================================
m_dalvik() {
    acao="${1:-status}"

    dalvik_on() {
        require_root || return 1
        DEEP_TAG=dalvik; deep_begin
        for kv in \
            "dalvik.vm.heapstartsize 8m" \
            "dalvik.vm.heapgrowthlimit 192m" \
            "dalvik.vm.heapsize 512m" \
            "dalvik.vm.heapminfree 512k" \
            "dalvik.vm.heapmaxfree 8m" \
            "dalvik.vm.heaputilization 0.8" \
            "dalvik.vm.usejit true" \
            "dalvik.vm.dex2oat-filter speed" \
            "dalvik.vm.image-dex2oat-filter speed" \
            ; do
            p=${kv% *}; v=${kv#* }
            old=$(sh_get "getprop $p")
            [ -n "$old" ] && deep_add "setprop $p '$old'"
            sh_run "setprop $p $v" >/dev/null 2>&1
        done
        say "dalvik: heaps maiores + compilação em modo speed"
    }

    dalvik_off() { say "Restaurando dalvik"; deep_restore dalvik; }

    case "$acao" in
        on)  dalvik_on ;;
        off) dalvik_off ;;
        *)   say "Uso: dalvik on|off (root)"; status_show ;;
    esac
}

# =============================================================================
#  MÓDULO: DEXOPT / ART COMPILE  (sem root)
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

    # MODO EXTREMO: turbo + tudo que é pouco conhecido (a bomba total)
    extreme_on() {
        say "MODO EXTREMO — turbo + knobs avançados (VM, sched, GPU, cores, input, idle, rede2, zram, kernel, display, dalvik)"
        gaming_on
        m_vm on
        m_sched on
        m_gpu on
        m_cores on
        m_input on
        m_idle on
        m_net2 on
        m_zram on
        m_kernel on
        m_display on
        m_dalvik on
        echo
        warn "EXTREMO ativo: núcleos sempre ligados, idle profundo desligado, GPU travada."
        warn "Isso esquenta MUITO e consome bateria — use com o aparelho ventilado."
        say "reverter: sh scripts/deep-tune.sh extreme off"
    }

    gaming_off() {
        say "MODO JOGO TURBO — desligando"
        deep_restore
        say "tudo restaurado"
    }

    case "$acao" in
        on)      gaming_on ;;
        off)     gaming_off ;;
        extreme) extreme_on ;;
        *)       say "Uso: gaming on [pkg] | gaming off | gaming extreme"; status_show ;;
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
    printf '   %sthermal%s[on|off|temp]  limite térmico (root, ⚠️ esquenta; trava auto)\n' "$C_A" "$C_R"
    printf '   %sio%s     [on|off]  scheduler + fstrim (root)\n' "$C_A" "$C_R"
    printf '   %smem%s    [on|off]  MGLRU + zRAM + KSM (root)\n' "$C_A" "$C_R"
    printf '   %snet%s    [on|off]  TCP BBR + fq_codel (root)\n' "$C_A" "$C_R"
    printf '   %slatency%s[on|off]  SurfaceFlinger/vsync (root)\n' "$C_A" "$C_R"
    printf '   %sdebloat%s[on|off]  appops + buckets (sem root)\n' "$C_A" "$C_R"
    printf '   %s——+ avançados (pouco conhecidos) ——%s\n' "$C_D" "$C_R"
    printf '   %svm%s     [on|off]  VM/dirty/cache pressure (root)\n' "$C_A" "$C_R"
    printf '   %ssched%s  [on|off]  escalonador/EAS + schedtune (root)\n' "$C_A" "$C_R"
    printf '   %sgpu%s    [on|off]  GPU KGSL/Mali no topo (root)\n' "$C_A" "$C_R"
    printf '   %scores%s  [on|off]  core_ctl/hotplug (root)\n' "$C_A" "$C_R"
    printf '   %sinput%s  [on|off]  input/touch boost (root)\n' "$C_A" "$C_R"
    printf '   %sidle%s   [on|off]  cpuidle menu (root)\n' "$C_A" "$C_R"
    printf '   %snet2%s   [on|off]  BBR2 + MTU probing + slow-start off (root)\n' "$C_A" "$C_R"
    printf '   %szram%s   [on|off]  zstd + mem_limit (root)\n' "$C_A" "$C_R"
    printf '   %skernel%s [on|off]  tracing/debug off, file-max (root)\n' "$C_A" "$C_R"
    printf '   %sdisplay%s[on|off]  HWUI/SurfaceFlinger props (sem root)\n' "$C_A" "$C_R"
    printf '   %sdalvik%s [on|off]  heaps ART/dex2oat (root)\n' "$C_A" "$C_R"
    printf '   %sdexopt%s [run|status]  recompilar apps AOT (sem root)\n' "$C_A" "$C_R"
    printf '   %sgaming%s [on|off|extreme]  TURBO / TUDO (extremo)\n' "$C_A" "$C_R"
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
    vm)      m_vm "$@" ;;
    sched)   m_sched "$@" ;;
    gpu)     m_gpu "$@" ;;
    cores)   m_cores "$@" ;;
    input)   m_input "$@" ;;
    idle)    m_idle "$@" ;;
    net2)    m_net2 "$@" ;;
    zram)    m_zram "$@" ;;
    kernel)  m_kernel "$@" ;;
    display) m_display "$@" ;;
    dalvik)  m_dalvik "$@" ;;
    dexopt)  m_dexopt "$@" ;;
    gaming)  m_gaming "$@" ;;
    extreme) m_gaming extreme ;;
    detect)  detect ;;
    status)  status_show ;;
    restore) deep_restore ;;
    *)       err "módulo desconhecido: $mod"; exit 1 ;;
esac
rc=$?
otm_v_report "deep:$mod"
exit $rc
