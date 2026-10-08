#!/system/bin/sh
# =============================================================================
#  apply.sh - Motor configurável do pack (WebUI Control).
#  Lê o arquivo de config (chave=valor) e aplica somente o que está ligado.
#
#  Uso:
#     sh apply.sh            # aplica a config atual
#     sh apply.sh apply      # idem
#     sh apply.sh restore    # restaura o snapshot do pack
#     sh apply.sh read KEY   # imprime o valor de uma chave
#     sh apply.sh set KEY V  # grava uma chave
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm"
mkdir -p "$STATE" 2>/dev/null || STATE="$DIR/state"
mkdir -p "$STATE" 2>/dev/null
CFG="$STATE/webui.conf"

# --- config padrão ------------------------------------------------------------
cfg_defaults() {
    CFG_PERF=1
    CFG_GFX=1
    CFG_NET=1
    CFG_GAME=1
    CFG_FREEZE=0
    CFG_DND=0
    CFG_TV=1
    CFG_TOUCH=1
    CFG_LOOP=0
    CFG_ANIM=0.5
    CFG_TR=110
    CFG_LP=350
    CFG_PS=0
    CFG_SLOP=4
    CFG_HZ=0
    CFG_GAMETUNE=0
    CFG_GT_PKG=com.dts.freefireth
    CFG_GT_DS=0.9
    CFG_GT_FPS=0
    # otimizações profundas
    CFG_ANGLE=0
    CFG_ANGLE_PKGS=com.dts.freefireth,com.dts.freefiremax
    CFG_DEBLOAT=0
    CFG_DEEP=0
    CFG_THERMAL=0
}

cfg_defaults
[ -f "$CFG" ] && . "$CFG" 2>/dev/null

save_cfg() {
    {
        for k in CFG_PERF CFG_GFX CFG_NET CFG_GAME CFG_FREEZE CFG_DND CFG_TV \
                 CFG_TOUCH CFG_LOOP CFG_ANIM CFG_TR CFG_LP CFG_PS CFG_SLOP CFG_HZ \
                 CFG_GAMETUNE CFG_GT_PKG CFG_GT_DS CFG_GT_FPS \
                 CFG_ANGLE CFG_ANGLE_PKGS CFG_DEBLOAT CFG_DEEP CFG_THERMAL; do
            eval "v=\$$k"
            printf '%s=%s\n' "$k" "$v"
        done
    } > "$CFG"
}

get_val() { eval "echo \$$1"; }

set_val() {
    eval "$1='$2'"
    save_cfg
}

# --- módulos ------------------------------------------------------------------
m_perf() {
    settings put global window_animation_scale "$CFG_ANIM"
    settings put global transition_animation_scale "$CFG_ANIM"
    settings put global animator_duration_scale "$CFG_ANIM"
    settings put global activity_manager_constants max_cached_processes=32
    setprop debug.hwui.renderer skiagl
}
m_gfx() {
    settings put global force_gpu_rendering 1
    settings put global disable_window_blurs 1
    settings put global accessibility_reduce_transparency 1
}
m_net() {
    settings put global private_dns_mode hostname
    settings put global private_dns_specifier dns.cloudflare.com
    settings put global wifi_scan_always_enabled 0
}
m_game() {
    settings put global game_driver_all_apps 1
    cmd game set --mode performance com.dts.freefireth  >/dev/null 2>&1
    cmd game set --mode performance com.dts.freefiremax >/dev/null 2>&1
}
m_freeze() {
    settings put global cached_apps_freezer enabled
}
m_dnd() {
    settings put global heads_up_notifications_enabled 0
    settings put global zen_mode 0
}
m_tv() {
    [ "$CFG_HZ" != "0" ] && {
        settings put system peak_refresh_rate "$CFG_HZ"
        settings put system min_refresh_rate "$CFG_HZ"
    }
}
m_touch() {
    settings put system touch_responsiveness "$CFG_TR"
    settings put system long_press_timeout "$CFG_LP"
    settings put system pointer_speed "$CFG_PS"
    settings put system touch_slop "$CFG_SLOP"
    setprop persist.sys.touch.sensitivity 1
}

m_gametune() {
    [ -z "$CFG_GT_PKG" ] && return 0
    if [ "$CFG_GT_FPS" != "0" ]; then
        cfg="mode=2,fps=$CFG_GT_FPS,downscaleFactor=$CFG_GT_DS:mode=3,fps=$CFG_GT_FPS,downscaleFactor=$CFG_GT_DS"
    else
        cfg="mode=2,downscaleFactor=$CFG_GT_DS:mode=3,downscaleFactor=$CFG_GT_DS"
    fi
    device_config put game_overlay "$CFG_GT_PKG" "$cfg" >/dev/null 2>&1
    cmd game set --mode performance "$CFG_GT_PKG" >/dev/null 2>&1
}

# --- otimizações profundas (sysfs/root), espelhando scripts/deep-tune.sh ------
DEEP_OFF="$STATE/deep_off.sh"
DEEP_MARK="$STATE/deep_mark"
DEEP_RECORD=0

_deep_record_once() {
    if [ ! -f "$DEEP_MARK" ]; then
        : > "$DEEP_OFF"
        DEEP_RECORD=1
    fi
}
_sys_write() {  # _sys_write <path> <novo>
    p="$1"; v="$2"
    [ -w "$p" ] || return 0
    if [ "$DEEP_RECORD" = "1" ]; then
        old=$(cat "$p" 2>/dev/null)
        [ -n "$old" ] && echo "echo '$old' > $p" >> "$DEEP_OFF"
    fi
    echo "$v" > "$p" 2>/dev/null
}
BLOAT_PKGS="com.instagram.android com.facebook.katana com.facebook.orca \
com.ss.android.ugc.trill com.ss.android.ugc.aweme com.twitter.android \
com.google.android.youtube com.android.chrome com.spotify.music com.discord"

m_angle() {
    [ -z "$CFG_ANGLE_PKGS" ] && return 0
    n=$(echo "$CFG_ANGLE_PKGS" | tr ',' '\n' | wc -l)
    vals=$(i=0; while [ "$i" -lt "$n" ]; do printf 'angle,'; i=$((i+1)); done | sed 's/,$//')
    settings put global angle_gl_driver_selection_pkgs "$CFG_ANGLE_PKGS" >/dev/null 2>&1
    settings put global angle_gl_driver_selection_values "$vals" >/dev/null 2>&1
}
m_debloat() {
    for a in $BLOAT_PKGS; do
        cmd appops set "$a" RUN_IN_BACKGROUND ignore >/dev/null 2>&1
        cmd appops set "$a" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
        am set-standby-bucket "$a" restricted >/dev/null 2>&1
    done
}
m_deep() {
    for d in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
        _sys_write "$d/scaling_governor" performance
        mx=$(cat "$d/cpuinfo_max_freq" 2>/dev/null)
        [ -n "$mx" ] && _sys_write "$d/scaling_min_freq" "$mx"
    done
    for b in /sys/block/sd* /sys/block/mmcblk* /sys/block/ufs*; do
        _sys_write "$b/queue/scheduler" none
        _sys_write "$b/queue/read_ahead_kb" 4096
    done
    _sys_write /sys/kernel/mm/lru_gen/enabled 1
    _sys_write /proc/sys/vm/swappiness 100
    if sysctl -n net.ipv4.tcp_available_congestion_control 2>/dev/null | grep -q bbr; then
        if [ "$DEEP_RECORD" = "1" ]; then
            old=$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)
            [ -n "$old" ] && echo "sysctl -w net.ipv4.tcp_congestion_control=$old" >> "$DEEP_OFF"
        fi
        sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    fi
    if [ "$DEEP_RECORD" = "1" ]; then
        echo "setprop debug.sf.latch_unsignaled '$(getprop debug.sf.latch_unsignaled)'" >> "$DEEP_OFF"
    fi
    setprop debug.sf.latch_unsignaled 1 >/dev/null 2>&1
}
m_thermal() {
    for z in /sys/class/thermal/thermal_zone*; do
        case "$(cat "$z/type" 2>/dev/null)" in
            cpu|gpu|soc|tsens*|big*|little*|*skin*) ;;
            *) continue ;;
        esac
        for tp in "$z"/trip_point_*_temp; do
            [ -f "$tp" ] || continue
            old=$(cat "$tp" 2>/dev/null)
            case "$old" in ''|*[!0-9]*) continue ;; esac
            [ "$old" -ge 60000 ] && _sys_write "$tp" $((old + 5000))
        done
    done
}
m_deepgroup() {
    _deep_record_once
    m_deep
    m_thermal
    [ "$DEEP_RECORD" = "1" ] && { command touch "$DEEP_MARK"; DEEP_RECORD=0; }
}
revert_deep() {
    if [ -s "$DEEP_OFF" ]; then
        while IFS= read -r c; do
            [ -z "$c" ] && continue
            sh -c "$c" >/dev/null 2>&1
        done < "$DEEP_OFF"
        rm -f "$DEEP_OFF"
    fi
    for a in $BLOAT_PKGS; do
        cmd appops set "$a" RUN_IN_BACKGROUND allow >/dev/null 2>&1
        cmd appops set "$a" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
        am set-standby-bucket "$a" active >/dev/null 2>&1
    done
    settings delete global angle_gl_driver_selection_pkgs >/dev/null 2>&1
    settings delete global angle_gl_driver_selection_values >/dev/null 2>&1
}

apply_all() {
    [ "$CFG_PERF"  = "1" ] && m_perf
    [ "$CFG_GFX"   = "1" ] && m_gfx
    [ "$CFG_NET"   = "1" ] && m_net
    [ "$CFG_GAME"  = "1" ] && m_game
    [ "$CFG_FREEZE" = "1" ] && m_freeze
    [ "$CFG_DND"   = "1" ] && m_dnd
    [ "$CFG_TV"    = "1" ] && m_tv
    [ "$CFG_TOUCH" = "1" ] && m_touch
    [ "$CFG_GAMETUNE" = "1" ] && m_gametune
    [ "$CFG_ANGLE" = "1" ] && m_angle
    [ "$CFG_DEBLOAT" = "1" ] && m_debloat
    [ "$CFG_DEEP" = "1" ] && m_deepgroup
    echo "ok"
}

restore_all() {
    settings delete global window_animation_scale 2>/dev/null
    settings delete global transition_animation_scale 2>/dev/null
    settings delete global animator_duration_scale 2>/dev/null
    settings put global force_gpu_rendering 0
    settings put global disable_window_blurs 0
    settings put global accessibility_reduce_transparency 0
    settings put global game_driver_all_apps 0
    settings put global private_dns_mode opportunistic
    settings delete global private_dns_specifier 2>/dev/null
    settings put global cached_apps_freezer disabled
    settings put global heads_up_notifications_enabled 1
    settings delete system touch_slop 2>/dev/null
    settings delete system touch_responsiveness 2>/dev/null
    settings delete system peak_refresh_rate 2>/dev/null
    settings delete system min_refresh_rate 2>/dev/null
    [ -n "$CFG_GT_PKG" ] && device_config delete game_overlay "$CFG_GT_PKG" >/dev/null 2>&1
    revert_deep
    rm -f "$DEEP_MARK"
    echo "restaurado"
}

case "$1" in
    ""|apply) apply_all ;;
    restore)  restore_all ;;
    read)     get_val "$2" ;;
    set)      set_val "$2" "$3" ;;
    save)     save_cfg; echo "salvo" ;;
    show)     [ -f "$CFG" ] || save_cfg; cat "$CFG" ;;
    *)        apply_all ;;
esac
