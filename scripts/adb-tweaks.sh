#!/system/bin/sh
# =============================================================================
#  adb-tweaks.sh - Biblioteca de comandos ADB para otimização
#
#  Funciona em: ADB (PC), Brevent, Termux, Shizuku (rish), root.
#  Uso:
#     ./adb-tweaks.sh list                 # lista os grupos
#     ./adb-tweaks.sh perf                 # aplica um grupo
#     ./adb-tweaks.sh perf gpu net         # vários grupos
#     ./adb-tweaks.sh all                  # aplica tudo
#     ./adb-tweaks.sh touch 110 400 400    # grupo com parâmetros
#     ./adb-tweaks.sh raw "settings get global window_animation_scale"
#
#  Cada grupo é uma função abaixo. Para adicionar um comando novo, crie uma
#  função com o nome do grupo e registre em GRUPOS no final do arquivo.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

# -----------------------------------------------------------------------------
#  GRUPOS DE COMANDOS
# -----------------------------------------------------------------------------

# --- performance / animações --------------------------------------------------
perf() {
    bkp_begin
    say "Performance e animações"
    bkp_set global window_animation_scale 0.5
    bkp_set global transition_animation_scale 0.5
    bkp_set global animator_duration_scale 0.5
    bkp_set global force_gpu_rendering 1
    bkp_set global disable_window_blurs 1
    bkp_set global accessibility_reduce_transparency 1
    bkp_set global activity_manager_constants max_cached_processes=32
    sh_run "setprop debug.hwui.renderer skiagl" >/dev/null
    say "animações 0.5x, GPU forçada, blur off"
}

perf_max() {
    bkp_begin
    say "Performance EXTREMA (animações 0)"
    bkp_set global window_animation_scale 0
    bkp_set global transition_animation_scale 0
    bkp_set global animator_duration_scale 0
    bkp_set global force_gpu_rendering 1
    bkp_set global disable_window_blurs 1
    bkp_set global accessibility_reduce_transparency 1
    sh_run "setprop debug.hwui.renderer skiagl" >/dev/null
    say "pronto"
}

# --- GPU / renderização -------------------------------------------------------
gpu() {
    bkp_begin
    say "GPU / renderização"
    bkp_set global force_gpu_rendering 1
    bkp_set global disable_window_blurs 1
    bkp_set global accessibility_reduce_transparency 1
    bkp_set global game_driver_all_apps 1
    # debug.hwui.renderer é uma *prop* (não um setting): guarda o valor antigo e aplica
    old=$(sh_get "getprop debug.hwui.renderer")
    if [ -n "$old" ]; then
        bkp_raw "setprop debug.hwui.renderer '$old'"
    else
        bkp_raw "setprop debug.hwui.renderer ''"
    fi
    sh_run "setprop debug.hwui.renderer skiagl" >/dev/null
    say "renderização otimizada"
}

# --- rede / TCP ---------------------------------------------------------------
net() {
    bkp_begin
    say "Rede / TCP"
    bkp_set global private_dns_mode hostname
    bkp_set global private_dns_specifier dns.cloudflare.com
    bkp_set global wifi_scan_always_enabled 0
    if [ "$RUN_MODE" = "adb" ] || [ "$RUN_MODE" = "su" ] || [ "$RUN_MODE" = "rish" ]; then
        sh_run "setprop net.tcp.buffersize.default 4096,87380,524288,4096,16384,110208" >/dev/null
        sh_run "setprop net.tcp.buffersize.wifi 524288,1048576,2097152,262144,524288,1048576" >/dev/null
        sh_run "setprop net.tcp.buffersize.lte 524288,1048576,2097152,262144,524288,1048576" >/dev/null
        sh_run "setprop net.tcp.buffersize.hspa 4094,87380,524288,4096,16384,262144" >/dev/null
    fi
    say "DNS Cloudflare, buffers TCP ajustados"
}

net_reset() {
    bkp_begin
    say "Rede - reset para automático"
    bkp_set global private_dns_mode opportunistic
    sh_run "settings delete global private_dns_specifier" >/dev/null
    say "pronto"
}

wifi() {
    bkp_begin
    say "Wi-Fi tweaks"
    bkp_set global wifi_scan_always_enabled 0
    bkp_set global wifi_wakeup_enabled 0
    bkp_set global wifi_power_save 1
    say "scan em background off"
}

# --- bateria / doze -----------------------------------------------------------
battery() {
    bkp_begin
    say "Bateria / Doze"
    bkp_set global low_power 1
    bkp_set global adaptive_battery_management_enabled 0
    sh_run "dumpsys deviceidle enable" >/dev/null
    sh_run "dumpsys deviceidle force-idle" >/dev/null
    say "economia de bateria ativada"
}

battery_off() {
    bkp_begin
    say "Bateria - modo normal"
    bkp_set global low_power 0
    bkp_set global adaptive_battery_management_enabled 1
    sh_run "dumpsys deviceidle unforce" >/dev/null
    say "pronto"
}

# --- jogos / Game Mode --------------------------------------------------------
game() {
    bkp_begin
    say "Game Mode / game driver"
    bkp_set global game_driver_all_apps 1
    sh_run "cmd game set --mode performance com.dts.freefireth" >/dev/null
    sh_run "cmd game set --mode performance com.dts.freefiremax" >/dev/null
    sh_run "cmd game set --downscale-factor 1 com.dts.freefireth" >/dev/null
    say "game mode performance aplicado"
}

# --- Free Fire ----------------------------------------------------------------
ff() {
    bkp_begin
    say "Free Fire - preparação"
    # fecha apps de fundo conhecidos
    for a in com.instagram.android com.facebook.katana com.facebook.orca \
             com.ss.android.ugc.trill com.ss.android.ugc.aweme \
             com.twitter.android com.google.android.youtube \
             com.android.chrome com.spotify.music com.discord; do
        sh_run "am force-stop $a" >/dev/null
    done
    sh_run "cmd game set --mode performance com.dts.freefireth" >/dev/null
    sh_run "cmd game set --mode performance com.dts.freefiremax" >/dev/null
    sh_run "settings put global game_driver_all_apps 1" >/dev/null
    say "apps fechados, game mode ligado"
}

ff_open() {
    say "Abrindo Free Fire"
    sh_run "am start -n com.dts.freefireth/com.dts.freefireth.FFMainActivity" >/dev/null \
        || sh_run "am start -n com.dts.freefiremax/com.dts.freefireth.FFMainActivity" >/dev/null
    say "launch enviado"
}

# --- freezer de apps (funciona no Brevent!) -----------------------------------
freezer() {
    say "Congelamento de apps em cache (cached_apps_freezer)"
    bkp_begin
    sh_run "settings put global cached_apps_freezer enabled" >/dev/null
    bkp_raw "settings put global cached_apps_freezer disabled"
    say "cached_apps_freezer = enabled"
}

freezer_off() {
    say "Desligando cached_apps_freezer"
    sh_run "settings put global cached_apps_freezer disabled" >/dev/null
    say "pronto"
}

# congela apps de terceiros (respeitando whitelist + proteção do sistema)
# A whitelist fica em $ST/whitelist (um pacote por linha). Apps essenciais e do
# sistema NUNCA entram, mesmo que estejam na lista de congelar.
FREEZE_WL="$ST/whitelist"
FREEZE_BL="$ST/blacklist"
SYSTEM_GUARD="android com.android.systemui com.android.settings com.android.phone \
com.android.server.telecom com.google.android.gms com.google.android.gsf \
com.android.vending com.android.inputmethod.latin com.android.providers.telephony \
com.android.shell com.termux com.topjohnwu.magisk me.weishu.kernelsu frb.axeron.manager"

# apps de fundo que costumam drenar RAM (blacklist padrão)
DEFAULT_BL="com.instagram.android com.facebook.katana com.facebook.orca \
com.ss.android.ugc.trill com.ss.android.ugc.aweme com.twitter.android \
com.google.android.youtube com.android.chrome com.spotify.music com.discord \
com.netflix.mediaclient com.snapchat.android com.reddit.frontpage"

_freeze_lists() {
    [ -f "$FREEZE_WL" ] || : > "$FREEZE_WL"
    if [ ! -f "$FREEZE_BL" ]; then
        for p in $DEFAULT_BL; do echo "$p"; done > "$FREEZE_BL"
    fi
}

_is_protected() {
    a="$1"
    case " $SYSTEM_GUARD " in *" $a "*) return 0 ;; esac
    [ -f "$FREEZE_WL" ] && grep -qxF "$a" "$FREEZE_WL" && return 0
    return 1
}

freeze_apps() {
    _freeze_lists
    mode="${OTM_FREEZE_MODE:-suspend}"
    trap '' INT TERM 2>/dev/null
    say "Congelando blacklist (menos whitelist) · modo=$mode"
    n=0
    for a in $(cat "$FREEZE_BL"); do
        _is_protected "$a" && continue
        sh_run "pm list packages $a" | grep -q "package:$a" || continue
        if [ "$mode" = "soft" ]; then
            sh_run "pm disable-user --user 0 $a" >/dev/null
        else
            sh_run "pm suspend --user 0 $a" >/dev/null
        fi && { echo "$a" >> "$ST/frozen"; n=$((n+1)); }
        sh_run "am force-stop $a" >/dev/null
    done
    sh_run "settings put global cached_apps_freezer enabled" >/dev/null
    say "congelados: $n app(s) (whitelist em $FREEZE_WL)"
}

freeze_whitelist_add() {
    [ -z "$1" ] && { err "uso: freeze_wl_add <pacote>"; return 1; }
    _freeze_lists
    grep -qxF "$1" "$FREEZE_WL" || echo "$1" >> "$FREEZE_WL"
    grep -vxF "$1" "$FREEZE_BL" > "$FREEZE_BL.tmp" 2>/dev/null && mv "$FREEZE_BL.tmp" "$FREEZE_BL"
    sh_run "pm unsuspend --user 0 $1" >/dev/null
    sh_run "pm enable --user 0 $1" >/dev/null
    say "whitelist += $1"
}

freeze_whitelist_list() {
    _freeze_lists
    say "Whitelist (nunca congelar):"
    sed 's/^/    /' "$FREEZE_WL"
}

unfreeze_apps() {
    say "Descongelando todos"
    if sh_ok; then
        lista=$(sh_get "pm list packages -u -3" | sed 's/^package://')
        for a in $lista; do
            sh_run "pm unsuspend --user 0 $a" >/dev/null
            sh_run "pm enable --user 0 $a" >/dev/null
        done
        sh_run "settings put global cached_apps_freezer disabled" >/dev/null
    else
        warn "sem root/shell, use o Brevent para descongelar"
    fi
    : > "$ST/frozen"
    say "pronto"
}

# --- DND / notificações -------------------------------------------------------
dnd() {
    bkp_begin
    say "Não perturbe (DND)"
    bkp_set global zen_mode 0
    sh_run "cmd notification set_dnd off" >/dev/null
    bkp_set global heads_up_notifications_enabled 0
    say "notificações silenciadas"
}

dnd_off() {
    bkp_begin
    say "DND desligado / heads-up on"
    bkp_set global heads_up_notifications_enabled 1
    sh_run "cmd notification set_dnd off" >/dev/null
    say "pronto"
}

# --- tela / brilho ------------------------------------------------------------
screen() {
    bkp_begin
    say "Tela / brilho"
    bkp_set system screen_off_timeout 600000
    bkp_set system peak_refresh_rate 120.0
    bkp_set system min_refresh_rate 120.0
    sh_run "settings put system screen_brightness 200" >/dev/null
    say "timeout 10min, refresh 120Hz"
}

# --- touch / sensibilidade (Free Fire) ----------------------------------------
touch() {
    # touch [touch_responsiveness] [long_press_timeout] [pointer_speed]
    tbp="${1:-110}"; lpt="${2:-400}"; psp="${3:-0}"
    bkp_begin
    say "Sensibilidade / toque (tbp=$tbp lpt=$lpt speed=$psp)"
    # responsividade e janelas de toque (device-dependente)
    sh_run "settings put system touch_responsiveness $tbp" >/dev/null
    bkp_set system long_press_timeout "$lpt"
    bkp_set system pointer_speed "$psp"
    # desativa suavização de toque onde existir
    sh_run "settings put system touch_slop 0" >/dev/null
    sh_run "setprop persist.sys.touch.sensitivity 1" >/dev/null
    say "aplicado (requer reiniciar o jogo)"
}

# --- fluidez (animações 0, long/multi press, Hz máximo) -----------------------
fluidez() {
    # fluidez [long_press_timeout] [hz]
    lpt="${1:-150}"; hz="${2:-120.0}"
    bkp_begin
    say "Fluidez (animações 0, long_press=$lpt, multi_press=0, ${hz}Hz)"
    bkp_set global window_animation_scale 0
    bkp_set global transition_animation_scale 0
    bkp_set global animator_duration_scale 0
    bkp_set system long_press_timeout "$lpt"
    bkp_set system multi_press_timeout 0
    bkp_set system peak_refresh_rate "$hz"
    bkp_set system min_refresh_rate "$hz"
    sh_run "settings put system touch_responsiveness 110" >/dev/null
    sh_run "settings put system touch_slop 4" >/dev/null
    sh_run "settings put global disable_window_blurs 1" >/dev/null
    sh_run "settings put global accessibility_reduce_transparency 1" >/dev/null
    say "pronto (efeito instantâneo, toque sem atraso, Hz máximo)"
}

# --- tuning por jogo (resolução/FPS, só no app) -------------------------------
game_tune() {
    # game_tune [pkg] [downscale 0.3-1.0] [fps]
    pkg="${1:-com.dts.freefireth}"; d="${2:-0.9}"; fps="${3:-}"
    say "Tuning por jogo: $pkg (downscale $d${fps:+ · fps $fps})"
    if [ -n "$fps" ]; then
        sh "$DIR/game-per-app.sh" custom "$pkg" "$d" "$fps"
    else
        sh "$DIR/game-per-app.sh" custom "$pkg" "$d"
    fi
}

# --- memória / RAM ------------------------------------------------------------
# mem [padrao|gaming] -> ajusta quantos apps ficam em cache e libera RAM
mem() {
    perfil="${1:-padrao}"
    bkp_begin
    case "$perfil" in
        gaming)
            say "RAM - perfil GAMING (mais RAM livre)"
            bkp_set global activity_manager_constants max_cached_processes=8,max_phantom_processes=1024
            ;;
        *)
            say "RAM - perfil PADRÃO (multitarefa)"
            bkp_set global activity_manager_constants max_cached_processes=32,max_phantom_processes=2147483647
            ;;
    esac
    sh_run "am kill-all" >/dev/null
    sh_run "pm trim-caches 999999999999" >/dev/null
    sh_run "sync" >/dev/null
    # zram/MGLRU/KSM só com root e se o kernel aceitar
    if sh_ok; then
        [ -w /sys/kernel/mm/lru_gen/enabled ] && sh_run "echo 1 > /sys/kernel/mm/lru_gen/enabled" >/dev/null
        [ -w /sys/kernel/mm/ksm/run ] && sh_run "echo 1 > /sys/kernel/mm/ksm/run" >/dev/null
        sh_run "sysctl -w vm.swappiness=100" >/dev/null 2>&1
    fi
    say "RAM ajustada (perfil $perfil)"
}

# --- dexopt / limpeza ---------------------------------------------------------
clean() {
    say "Limpeza (dexopt / logs)"
    if sh_ok; then
        sh_run "pm trim-caches 999999999999" >/dev/null
        sh_run "killall -9 dex2oat" >/dev/null
        sh_run "logcat -c" >/dev/null
        sh_run "sm fstrim" >/dev/null 2>&1
        sh_run "sync" >/dev/null
    fi
    say "caches trimados"
}

aot() {
    require_root || return 1
    say "Compilando apps em AOT (speed)"
    for a in com.dts.freefireth com.dts.freefiremax; do
        sh_run "cmd package compile -m speed -f $a" >/dev/null && say "AOT: $a"
    done
}

# --- ajustes obscuros (sem root) ----------------------------------------------
# Junta knobs que quase ninguém conhece: animações do launcher, aviso de
# "pouca memória", jobs em segundo plano, morte de apps, etc.
obscure() {
    bkp_begin
    say "Ajustes obscuros (sem root)"
    # app em segundo plano: força parar depois de N minutos
    bkp_set global app_standby_enabled 1
    bkp_set global adaptive_battery_management_enabled 0
    # desliga o "aviso de memória baixa" e o kill agressivo
    bkp_set global low_memory_kill 0
    # transições mais curtas no launcher
    bkp_set secure skip_first_use_hints 1
    bkp_set global development_settings_enabled 1
    # economiza processamento de localização/rotação em background
    bkp_set global wifi_scan_throttle_enabled 1
    sh_run "cmd deviceidle whitelist +com.dts.freefireth" >/dev/null 2>&1
    sh_run "cmd deviceidle whitelist +com.dts.freefiremax" >/dev/null 2>&1
    say "aplicado (menos kills em 2º plano, jogo fora do Doze)"
}

# --- DNS de emergência / rede mobile (sem root) -------------------------------
# Bloqueia o "random MAC" (endereço aleatório) para redes confiáveis e desliga
# o modo de economia de dados que estrangula a velocidade em jogo.
mobile_net() {
    bkp_begin
    say "Rede móvel / economia de dados"
    bkp_set global data_saver_mode 0
    bkp_set global mobile_data_always_on 1
    bkp_set global network_avoid_bad_wifi 1
    sh_run "svc wifi disable" >/dev/null 2>&1
    sh_run "svc wifi enable" >/dev/null 2>&1
    say "economia de dados off, rede estável"
}

# --- notificações / heads-up (sem root) ---------------------------------------
# Reduz o trabalho do SystemUI com heads-up, o que dá mais fluidez em jogo.
notif() {
    bkp_begin
    say "Notificações (menos heads-up)"
    bkp_set global heads_up_notifications_enabled 0
    bkp_set global notification_bubbles 0
    say "heads-up e bolhas desligados"
}

# --- janela / transições (sem root) -------------------------------------------
# Além das animações: desliga "rotação lenta" e transições de tema escuro.
window_tweaks() {
    bkp_begin
    say "Janelas / transições"
    bkp_set global window_animation_scale 0.5
    bkp_set global transition_animation_scale 0.5
    bkp_set global animator_duration_scale 0.5
    bkp_set system screen_off_timeout 600000
    sh_run "settings put global policy_control immersive.full=*" >/dev/null 2>&1
    say "transições 0.5x + modo imersivo"
}

# --- restaurar tudo -----------------------------------------------------------
restore_all() {
    say "Restaurando configurações originais"
    if [ -s "$OFF_SH" ]; then
        # executa os comandos de reversão guardados
        while IFS= read -r c; do
            [ -z "$c" ] && continue
            case "$c" in '#'*) continue ;; esac
            sh_run "$c" >/dev/null
        done < "$OFF_SH"
    fi
    sh_run "settings put global cached_apps_freezer disabled" >/dev/null
    sh_run "dumpsys deviceidle unforce" >/dev/null
    rm -f "$MARK" "$OFF_SH"
    say "restaurado"
}

# -----------------------------------------------------------------------------
#  RUNNER
# -----------------------------------------------------------------------------
GRUPOS="perf perf_max gpu net net_reset wifi battery battery_off game ff ff_open freezer freezer_off freeze_apps freeze_whitelist_add freeze_whitelist_list unfreeze_apps mem dnd dnd_off screen touch fluidez game_tune clean aot obscure mobile_net notif window_tweaks restore_all"

list() {
    printf '  Grupos disponíveis:\n\n'
    for g in $GRUPOS; do printf '   %b%s%b\n' "$C_A" "$g" "$C_R"; done
    printf '\n  Uso: %s <grupo> [grupo...] | all | raw "<cmd>" | list\n' "$0"
}

all() {
    for g in perf mem gpu net wifi game freezer dnd screen fluidez game_tune clean; do
        eval "$g"
        echo
    done
    # otimizações profundas que não exigem root
    sh "$DIR/deep-tune.sh" debloat on
    echo
}

# execução
[ $# -eq 0 ] && { list; exit 0; }

acao="$1"; shift
case "$acao" in
    list) list ;;
    all)  all ;;
    raw)  [ -z "$1" ] && { err "faltou o comando"; exit 1; }; sh_run "$1" ;;
    *)
        if echo " $GRUPOS " | grep -q " $acao "; then
            "$acao" "$@"
        else
            err "grupo desconhecido: $acao"
            list
            exit 1
        fi ;;
esac

rc=$?
otm_v_report adb-tweaks
exit $rc
