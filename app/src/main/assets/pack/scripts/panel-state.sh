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

# piloto térmico: um único 'tick' decide e devolve tudo. Roda antes de ler o
# estado para o painel nunca mostrar um estado que o motor já mudou (e o prazo
# vencido com o app fechado solta o teto aqui, na abertura do painel).
_pout="$(sh "$DIR/thermal-pilot.sh" tick 2>/dev/null | grep '^#OTM-PILOT' | head -1)"
_pfield() {
    printf '%s' "$_pout" | tr ' ' '\n' | grep "^$1=" | head -1 | cut -d= -f2
}
_pst="$(_pfield state)"
case "$_pst" in on|cooling) ;; *) _pst=off ;; esac
printf ',"pilot_state":"%s"' "$(_clean "$_pst")"
_pa="$(_pfield armed)"; case "$_pa" in 0|1) ;; *) _pa=0 ;; esac
printf ',"pilot_armed":"%s"' "$_pa"
_pleft="$(_pfield left)"
case "$_pleft" in ''|*[!0-9]*) printf ',"pilot_left":""' ;; *)
    printf ',"pilot_left":"%s"' "$((_pleft / 60))" ;;
esac
_phot="$(_pfield hot)"; case "$_phot" in ''|*[!0-9]*) _phot=43 ;; esac
_pcool="$(_pfield cool)"; case "$_pcool" in ''|*[!0-9]*) _pcool=38 ;; esac
printf ',"pilot_hot":"%s"' "$(_clean "$_phot")"
printf ',"pilot_cool":"%s"' "$(_clean "$_pcool")"
_prel="$(_pfield releases)"; case "$_prel" in ''|*[!0-9]*) _prel=0 ;; esac
printf ',"pilot_releases":"%s"' "$(_clean "$_prel")"
_ppeak="$(_pfield peak)"; case "$_ppeak" in ''|*[!0-9]*) _ppeak="" ;; esac
printf ',"pilot_peak":"%s"' "$(_clean "$_ppeak")"
_ptmp="$(_pfield temp)"; case "$_ptmp" in ''|*[!0-9]*) _ptmp="" ;; esac
printf ',"pilot_temp":"%s"' "$(_clean "$_ptmp")"
printf ',"mode":"%s"' "$(_clean "${RUN_MODE:-local}")"
printf '}\n'
exit 0
