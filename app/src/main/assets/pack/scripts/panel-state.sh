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
printf ',"mode":"%s"' "$(_clean "${RUN_MODE:-local}")"
printf '}\n'
exit 0
