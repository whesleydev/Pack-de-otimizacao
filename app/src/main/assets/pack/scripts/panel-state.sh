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
# quando o prop está vazio, o Android usa o padrão (OpenGL)
[ -z "$renderer" ] && renderer="opengl"

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
printf ',"refresh_peak":"%s"' "$(_clean "$(_g system peak_refresh_rate)")"
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
printf ',"sysbars_battery":"%s"' "$(_clean "$(_g system status_bar_show_battery_percent)")"
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
printf ',"mode":"%s"' "$(_clean "${RUN_MODE:-local}")"
printf '}\n'
exit 0
