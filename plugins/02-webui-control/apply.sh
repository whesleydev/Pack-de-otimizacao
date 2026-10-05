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
}

cfg_defaults
[ -f "$CFG" ] && . "$CFG" 2>/dev/null

save_cfg() {
    {
        for k in CFG_PERF CFG_GFX CFG_NET CFG_GAME CFG_FREEZE CFG_DND CFG_TV \
                 CFG_TOUCH CFG_LOOP CFG_ANIM CFG_TR CFG_LP CFG_PS CFG_SLOP CFG_HZ; do
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

apply_all() {
    [ "$CFG_PERF"  = "1" ] && m_perf
    [ "$CFG_GFX"   = "1" ] && m_gfx
    [ "$CFG_NET"   = "1" ] && m_net
    [ "$CFG_GAME"  = "1" ] && m_game
    [ "$CFG_FREEZE" = "1" ] && m_freeze
    [ "$CFG_DND"   = "1" ] && m_dnd
    [ "$CFG_TV"    = "1" ] && m_tv
    [ "$CFG_TOUCH" = "1" ] && m_touch
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
