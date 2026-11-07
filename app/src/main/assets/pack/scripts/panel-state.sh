#!/system/bin/sh
# =============================================================================
#  panel-state.sh - Lê o estado REAL do aparelho para o painel.
#
#  Não altera nada: só lê. O painel usa isto para mostrar qual renderizador
#  está de fato em uso e quais os valores ATUAIS do toque — nada de número
#  fictício na tela. Se um valor não foi mexido (ou o acesso não lê), volta "".
#
#  Saída: uma linha JSON com pares chave/valor (valores são tokens simples).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh" 2>/dev/null

# lê um setting e devolve "" quando é "null"/vazio
_g() {
    v="$(sh_get "settings get $1 $2" 2>/dev/null)"
    case "$v" in ""|null|"null") echo "" ;; *) echo "$v" ;; esac
}
_p() {
    v="$(sh_get "getprop $1" 2>/dev/null)"
    case "$v" in ""|null|"null") echo "" ;; *) echo "$v" ;; esac
}
# remove aspas/quebras e limita ao que é seguro dentro do JSON
_clean() { printf '%s' "$1" | tr -d '"\\\n\r' | cut -c1-120; }

renderer="$(_clean "$(_p debug.hwui.renderer)")"
# Quando o prop está VAZIO, quem decide é o sistema. No Android 10+ o pipeline
# OpenGL foi removido (só existem SkiaGL e Skia Vulkan) e o padrão é skiavk se
# ro.hwui.use_vulkan=true, senão skiagl — nunca "opengl". Abaixo de API 29 o
# OpenGL ainda existia e era o padrão. (Fonte: AOSP libs/hwui/Properties.cpp.)
if [ -z "$renderer" ]; then
    _api="$(_p ro.build.version.sdk)"
    case "$_api" in
        ''|*[!0-9]*) renderer="skiagl" ;;
        *) if [ "$_api" -lt 29 ]; then renderer="opengl"; else
               [ "$(_p ro.hwui.use_vulkan)" = "true" ] && renderer="skiavk" || renderer="skiagl"
           fi ;;
    esac
fi

printf '{"renderer":"%s"' "$renderer"
printf ',"renderer_prop":"%s"' "$(_clean "$(_p debug.hwui.renderer)")"
printf ',"renderengine_backend":"%s"' "$(_clean "$(_p debug.renderengine.backend)")"
printf ',"force_gpu":"%s"' "$(_clean "$(_g global force_gpu_rendering)")"
printf ',"angle_pkgs":"%s"' "$(_clean "$(_g global angle_gl_driver_selection_pkgs)")"
printf ',"angle_vals":"%s"' "$(_clean "$(_g global angle_gl_driver_selection_values)")"
printf ',"angle_all":"%s"' "$(_clean "$(_g global angle_gl_driver_all_angle)")"
printf ',"game_driver_all":"%s"' "$(_clean "$(_g global game_driver_all_apps)")"
printf ',"updatable_driver":"%s"' "$(_clean "$(_g global updatable_driver_all_apps)")"
printf ',"touch_responsiveness":"%s"' "$(_clean "$(_g system touch_responsiveness)")"
printf ',"long_press_timeout":"%s"' "$(_clean "$(_g system long_press_timeout)")"
printf ',"pointer_speed":"%s"' "$(_clean "$(_g system pointer_speed)")"
printf ',"touch_slop":"%s"' "$(_clean "$(_g system touch_slop)")"
printf ',"multi_press_timeout":"%s"' "$(_clean "$(_g system multi_press_timeout)")"
printf ',"refresh_min":"%s"' "$(_clean "$(_g system min_refresh_rate)")"
# Taxa travada: só quando peak == min. O Android deixa o peak preenchido no modo
# adaptativo (min 60 / peak 120); sem esta regra o card dizia "travada em 120"
# num aparelho que estava só alternando. (Mesma regra do panel-stats.sh.)
_rmin="$(_g system min_refresh_rate)"; _rpeak="$(_g system peak_refresh_rate)"
[ -n "$_rpeak" ] && [ "$_rpeak" != "$_rmin" ] && _rpeak=""
printf ',"refresh_peak":"%s"' "$(_clean "$_rpeak")"
# taxa EM USO agora (modo ativo), para o card mostrar o valor real
printf ',"refresh_hz":"%s"' "$(_clean "$(otm_refresh_now 2>/dev/null)")"
# teto real do painel (maior modo que a tela suporta) — separado do travado
printf ',"refresh_max":"%s"' "$(_clean "$(otm_max_refresh 2>/dev/null)")"
# Menor largura (o mesmo "Menor largura" das Opções do desenvolvedor), em dp:
#   160 * menor_lado_em_px / densidade
# O painel mostra este número para o usuário reconhecer o que está no aparelho.
# `dpi_padrao_dp` é o valor de fábrica (densidade física) — o alvo do "padrão".
_wmd="$(sh_get 'wm density' 2>/dev/null)"
_dpi_ov="$(otm_echo "$_wmd" | sed -n 's/.*Override density: *\([0-9]*\).*/\1/p' | tail -1)"
_dpi_den="$(otm_num "$_dpi_ov")"
[ -z "$_dpi_den" ] && _dpi_den="$(otm_num "$(otm_echo "$_wmd" | sed -n 's/.*Physical density: *\([0-9]*\).*/\1/p' | tail -1)")"
_wmsz="$(sh_get 'wm size' 2>/dev/null)"
_phx="$(otm_echo "$_wmsz" | sed -n 's/.*Physical size: *\([0-9]*\)x\([0-9]*\).*/\1/p' | tail -1)"
_phy="$(otm_echo "$_wmsz" | sed -n 's/.*Physical size: *\([0-9]*\)x\([0-9]*\).*/\2/p' | tail -1)"
_ovx="$(otm_echo "$_wmsz" | sed -n 's/.*Override size: *\([0-9]*\)x\([0-9]*\).*/\1/p' | tail -1)"
_ovy="$(otm_echo "$_wmsz" | sed -n 's/.*Override size: *\([0-9]*\)x\([0-9]*\).*/\2/p' | tail -1)"
[ -n "$_ovx" ] && { _phx="$_ovx"; _phy="$_ovy"; }
_lado="$(otm_num "$_phx")"
if [ -n "$(otm_num "$_phy")" ] && [ "$(otm_num "$_phy")" -lt "$_lado" ] 2>/dev/null; then _lado="$(otm_num "$_phy")"; fi
_dpi_dp=""
if [ -n "$_lado" ] && [ -n "$_dpi_den" ]; then
    _dpi_dp="$(awk -v p="$_lado" -v d="$_dpi_den" 'BEGIN{ if (d>0) printf "%d", 160*p/d + 0.5 }')"
fi
printf ',"dpi_dp":"%s"' "$(_clean "$_dpi_dp")"
printf ',"dpi_padrao_dp":"%s"' "$(_clean "$(otm_dpi_padrao_dp 2>/dev/null)")"
printf ',"dpi_override":"%s"' "$(_clean "$_dpi_den")"
printf ',"dpi_profile":"%s"' "$(_clean "$(cat "$ST/dpi_profile" 2>/dev/null | head -1)")"
printf ',"device":"%s"' "$(_clean "$(_p ro.product.model)")"
printf ',"android":"%s"' "$(_clean "$(_p ro.build.version.sdk)")"
printf ',"gpu_driver":"%s"' "$(_clean "$(_p ro.gfx.driver.0)")"
printf ',"dns_host":"%s"' "$(_clean "$(_g global private_dns_specifier)")"
# modo desempenho fixo (turbo.sh perfmode): true/false -> on/off
_perf="$(sh_get 'dumpsys power 2>/dev/null' | grep -o 'mIsFixedPerformanceMode=[a-zA-Z]*' | head -1 | cut -d= -f2)"
case "$_perf" in true) _perf=on ;; false) _perf=off ;; *) _perf="" ;; esac
printf ',"fixed_perf":"%s"' "$(_clean "$_perf")"
# barras do sistema (modo imersivo, ícones escondidos, bateria em %). O painel
# usa isto para marcar a opção em uso de verdade, não a que foi pedida.
_pc="$(sh_get 'settings get global policy_control')"
case "$_pc" in
    ""|null)            _sb="on" ;;
    *immersive.full*)   _sb="off" ;;
    *immersive.status*) _sb="status" ;;
    *immersive.navigation*) _sb="nav" ;;
    *)                  _sb="other" ;;
esac
printf ',"sysbars":"%s"' "$(_clean "$_sb")"
printf ',"sysbars_icons":"%s"' "$(_clean "$(_g secure icon_blacklist)")"
# o card "Barra de cima: ícones" marca a opção em uso. O grupo canônico que o
# pack escreve é rotate,headset,volume,alarm_clock; qualquer outra lista (ou
# nenhuma) conta como "mostrar todos".
_sbi="$(sh_get 'settings get secure icon_blacklist' 2>/dev/null)"
case "$_sbi" in
    ""|null)                        _sbic="all" ;;
    rotate,headset,volume,alarm_clock) _sbic="clean" ;;
    *)                              _sbic="other" ;;
esac
printf ',"sysbars_icons_clean":"%s"' "$(_clean "$_sbic")"
printf ',"sysbars_battery":"%s"' "$(_clean "$(_g system status_bar_show_battery_percent)")"
# --- estado real das otimizações ESCONDIDAS do Android ------------------------
# O painel não pode inventar: cada chave abaixo é lida do aparelho. Ausente/
# "null" = padrão de fábrica (o módulo não foi ligado).
printf ',"pkg_verify":"%s"' "$(_clean "$(_g global package_verifier_enable)")"
printf ',"app_standby":"%s"' "$(_clean "$(_g global app_standby_enabled)")"
printf ',"auto_restrict":"%s"' "$(_clean "$(_g global app_auto_restriction_enabled)")"
printf ',"concurrent_gc":"%s"' "$(_clean "$(_g global force_concurrent_gc)")"
printf ',"cache_freezer":"%s"' "$(_clean "$(_g global cached_apps_freezer)")"
printf ',"game_driver_all":"%s"' "$(_clean "$(_g global game_driver_all_apps)")"
printf ',"netstats":"%s"' "$(_clean "$(_g global netstats_enabled)")"
printf ',"am_constants":"%s"' "$(_clean "$(_g global activity_manager_constants)")"
printf ',"aot_install":"%s"' "$(_clean "$(_p pm.dexopt.install)")"
printf ',"swappiness":"%s"' "$(_clean "$(sh_get 'cat /proc/sys/vm/swappiness' 2>/dev/null)")"
# chaves DERIVADAS: o interruptor acende só quando a marca da otimização está
# presente no aparelho. Se o sistema recusou o ajuste, a marca não existe e o
# switch fica apagado — nunca "mente" dizendo que aplicou.
_ac="$(sh_get 'settings get global activity_manager_constants' 2>/dev/null)"
case "$_ac" in *max_cached_processes=32*) _am="on" ;; *) _am="off" ;; esac
printf ',"am_tuned":"%s"' "$(_clean "$_am")"
case "$(sh_get 'getprop pm.dexopt.install' 2>/dev/null)" in speed) _aot="on" ;; *) _aot="off" ;; esac
printf ',"aot_tuned":"%s"' "$(_clean "$_aot")"
case "$(sh_get 'cat /proc/sys/vm/compaction_proactiveness' 2>/dev/null)" in 40) _ram="on" ;; *) _ram="off" ;; esac
printf ',"ram_tuned":"%s"' "$(_clean "$_ram")"
# limite de processos em segundo plano (Dev Options): valor REAL, não o que o
# pack escreveu. No Android 10+ mora em device_config, não no setting.
printf ',"proc_limit":"%s"' "$(_clean "$(proc_limit_get)")"
# efeitos visuais (desfoque/transparência). Ausente/"null" = padrão do sistema,
# que é o efeito LIGADO — o painel precisa saber disso para marcar "Em uso".
_bl="$(sh_get 'settings get global disable_window_blurs' 2>/dev/null)"
case "$_bl" in 1) _fx_blur=off ;; *) _fx_blur=on ;; esac
printf ',"blur":"%s"' "$(_clean "$_fx_blur")"
_tp="$(sh_get 'settings get global accessibility_reduce_transparency' 2>/dev/null)"
case "$_tp" in 1) _fx_tp=off ;; *) _fx_tp=on ;; esac
printf ',"reduce_transparency":"%s"' "$(_clean "$_fx_tp")"

# composicao enxuta: o interruptor so acende quando TODAS as flags que o toggle
# escreve estao no valor esperado. Se o sistema recusou alguma, fica apagado —
# o painel nunca marca "ligado" no que nao pegou.
_dd="$(sh_get 'settings get global debug.hwui.disable_draw_defer' 2>/dev/null)"
_ds="$(sh_get 'settings get global debug.hwui.disable_scissor_opt' 2>/dev/null)"
_ba="$(sh_get 'settings get global debug.hwui.use_buffer_age' 2>/dev/null)"
if [ "$_dd" = 1 ] && [ "$_ds" = 1 ] && [ "$_ba" = 1 ]; then _gcomp=on; else _gcomp=off; fi
printf ',"gfx_comp":"%s"' "$(_clean "$_gcomp")"

# resposta ao toque: acende quando as 4 janelas estao nos valores do toggle
_tr="$(sh_get 'settings get system touch_responsiveness' 2>/dev/null)"
_ts="$(sh_get 'settings get system touch_slop' 2>/dev/null)"
_mp="$(sh_get 'settings get system multi_press_timeout' 2>/dev/null)"
_lp="$(sh_get 'settings get system long_press_timeout' 2>/dev/null)"
if [ "$_tr" = 110 ] && [ "$_ts" = 4 ] && [ "$_mp" = 0 ] && [ "$_lp" = 300 ]; then
    _tresp=on
else
    _tresp=off
fi
printf ',"touch_resp":"%s"' "$(_clean "$_tresp")"

# trava termica (sem root): o interruptor mostra se a temperatura lida AGORA
# passou do teto padrao. Nao ha "ligado" persistente — e uma checagem pontual.
_tg="$(otm_temp 2>/dev/null)"
case "$_tg" in '' | *[!0-9-]*) _tguard="" ;; *)
    if [ "$_tg" -ge "${THERMAL_GUARD_C:-43}" ]; then _tguard=hot; else _tguard=ok; fi ;;
esac
printf ',"thermal_guard":"%s"' "$(_clean "$_tguard")"
printf ',"temp_now":"%s"' "$(_clean "$_tg")"

# vitalidade: um único 'tick' mede a bateria e roda o guardião. Roda antes de
# ler o estado para o painel nunca mostrar número velho.
_vout="$(sh "$DIR/vitality.sh" tick 2>/dev/null | grep '^#OTM-VITAL' | head -1)"
_vfield() {
    printf '%s' "$_vout" | tr ' ' '\n' | grep "^$1=" | head -1 | cut -d= -f2
}
for _k in health cycles level temp charging score care w80 whot alert; do
    _v="$(_vfield "$_k")"
    case "$_k" in
        charging) case "$_v" in 0|1|"") ;; *) _v="" ;; esac ;;
        score|health|level|temp) case "$_v" in ''|*[!0-9]*) _v="" ;; esac ;;
        cycles|w80|whot) case "$_v" in ''|*[!0-9]*) _v="" ;; esac ;;
        care) case "$_v" in on|off) ;; *) _v="off" ;; esac ;;
    esac
    # alert vem com '_' no lugar de espaço (é uma linha só); devolve legível
    [ "$_k" = alert ] && _v="$(printf '%s' "$_v" | tr '_' ' ')"
    printf ',"vital_%s":"%s"' "$_k" "$(_clean "$_v")"
done

# --- estado dos recursos "ativáveis" (interruptores do painel) ----------------
# Cada recurso que virou liga/desliga no painel precisa dizer se está LIGADO de
# verdade, senão o switch mente. Só leitura; campo que o aparelho não expõe = "".
printf ',"anim_scale":"%s"' "$(_clean "$(_g global window_animation_scale)")"
printf ',"low_power":"%s"' "$(_clean "$(_g global low_power)")"
printf ',"freezer":"%s"' "$(_clean "$(_g global cached_apps_freezer)")"
printf ',"wifi_scan":"%s"' "$(_clean "$(_g global wifi_scan_always_enabled)")"
printf ',"heads_up":"%s"' "$(_clean "$(_g global heads_up_notifications_enabled)")"
printf ',"data_saver":"%s"' "$(_clean "$(_g global data_saver_mode)")"
printf ',"ntp":"%s"' "$(_clean "$(_g global ntp_server)")"
printf ',"dnd":"%s"' "$(_clean "$(_g global zen_mode)")"
# doze afinado = device_idle_constants customizadas
_dc="$(sh_get 'settings get global device_idle_constants' 2>/dev/null)"
case "$_dc" in ""|null) _doze="off" ;; *) _doze="on" ;; esac
printf ',"doze_custom":"%s"' "$(_clean "$_doze")"
# logpersist desligado = telemetria contida
printf ',"logpersist":"%s"' "$(_clean "$(_p persist.logd.logpersistd)")"
# phantom killer desligado = monitor false
printf ',"phantom":"%s"' "$(_clean "$(_g global settings_enable_monitor_phantom_procs)")"
# refresh travado = min e peak iguais e preenchidos
_pk="$(_g system peak_refresh_rate)"; _mn="$(_g system min_refresh_rate)"
if [ -n "$_pk" ] && [ "$_pk" = "$_mn" ]; then _rfx="on"; else _rfx="off"; fi
printf ',"refresh_fixed":"%s"' "$(_clean "$_rfx")"


# fluidez: animações zeradas + taxa de tela travada
if [ "$(_g global window_animation_scale)" = "0" ] && [ -n "$(_g system min_refresh_rate)" ]; then
    _flu="on"
else
    _flu="off"
fi
printf ',"fluidez":"%s"' "$(_clean "$_flu")"
# não perturbe: lido do modo zen (secure). dnd() grava aqui também.
printf ',"dnd_zen":"%s"' "$(_clean "$(_g secure zen_mode)")"
# economia de bateria adaptativa (0 = sem economia agressiva)
printf ',"adaptive_batt":"%s"' "$(_clean "$(_g global adaptive_battery_management_enabled)")"
# isenções de 2º plano: o pacote está na whitelist do Doze?
_dw="$(sh_get 'cmd deviceidle whitelist' 2>/dev/null)"
case "$_dw" in *com.otm.pack*) _pp=1 ;; *) _pp=0 ;; esac
printf ',"perm_pack":"%s"' "$(_clean "$_pp")"
case "$_dw" in *com.dts.freefireth*|*com.dts.freefiremax*) _pf=1 ;; *) _pf=0 ;; esac
printf ',"perm_ff":"%s"' "$(_clean "$_pf")"

printf ',"mode":"%s"' "$(_clean "${RUN_MODE:-local}")"
printf '}\n'
exit 0
