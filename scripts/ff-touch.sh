#!/system/bin/sh
# =============================================================================
#  ff-touch.sh - Otimização de sensibilidade / toque para Free Fire
#
#  Perfis prontos: balanced | headshot | spray | sniper | custom
#  Uso:
#     ./ff-touch.sh <perfil>        # ex: ./ff-touch.sh headshot
#     ./ff-touch.sh custom 110 400 400 0
#                                   #  touch_responsiveness long_press pointer_speed slop
#     ./ff-touch.sh list
#     ./ff-touch.sh restore
#
#  IMPORTANTE: ajustes de toque variam por aparelho/ROM. Teste no treino do FF
#  antes de jogar partida. Se ficar "trepidando", reduza o touch_responsiveness.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

# aplica um conjunto de parâmetros de toque
_apply() {
    tr="$1"; lp="$2"; ps="$3"; slop="$4"; label="$5"
    bkp_begin
    say "Perfil: $label (tr=$tr lp=$lp ps=$ps slop=$slop)"

    # --- responsividade / janela de toque (globais) ---
    sh_run "settings put system touch_responsiveness $tr" >/dev/null
    bkp_set system long_press_timeout "$lp"
    bkp_set system pointer_speed "$ps"
    sh_run "settings put system touch_slop $slop" >/dev/null
    bkp_raw "settings delete system touch_slop"

    # --- propriedades de input (device-dependentes) ---
    sh_run "setprop persist.sys.touch.sensitivity 1" >/dev/null
    sh_run "setprop persist.sys.input.touch.boost 1" >/dev/null
    sh_run "setprop ro.input.resampling.enable 1" >/dev/null

    # --- reduzir latência de input no jogo ---
    sh_run "cmd game set --mode performance com.dts.freefireth" >/dev/null
    sh_run "cmd game set --mode performance com.dts.freefiremax" >/dev/null

    say "aplicado. reinicie o Free Fire para valer."
}

_perfis() {
    case "$1" in
        balanced)  _apply 100 400 0   8  "balanced" ;;
        headshot)  _apply 110 350 0   4  "headshot (mira rápida)" ;;
        spray)     _apply 105 300 0   6  "spray (controle de recuo)" ;;
        sniper)    _apply  95 500 -1  10 "sniper (mira precisa)" ;;
        speed)     _apply 120 300 1   2  "speed (ultra reativo)" ;;
        *)
            err "perfil desconhecido: $1"
            printf '  perfis: balanced headshot spray sniper speed custom\n'
            return 1 ;;
    esac
}

list() {
    printf '  Perfis de sensibilidade:\n\n'
    printf '   %bbalanced%b   equilíbrio geral\n' "$C_A" "$C_R"
    printf '   %bheadshot%b   mira rápida, ideal p/ headshot\n' "$C_A" "$C_R"
    printf '   %bspray%b      controle de recuo no spray\n' "$C_A" "$C_R"
    printf '   %bsniper%b     mira precisa, movimento suave\n' "$C_A" "$C_R"
    printf '   %bspeed%b      máxima reatividade\n' "$C_A" "$C_R"
    printf '   %bcustom%b     define manualmente os 4 parâmetros\n\n' "$C_A" "$C_R"
    printf '  Uso: %s <perfil> | custom <tr> <lp> <ps> <slop>\n' "$0"
}

restore() {
    say "Restaurando toque original"
    sh_run "settings delete system touch_slop" >/dev/null
    sh_run "settings delete system touch_responsiveness" >/dev/null
    sh_run "setprop persist.sys.touch.sensitivity 0" >/dev/null
    sh_run "setprop persist.sys.input.touch.boost 0" >/dev/null
    say "pronto (reinicie o jogo)"
}

[ $# -eq 0 ] && { list; exit 0; }

case "$1" in
    list) list ;;
    restore) restore ;;
    custom)
        shift
        [ $# -lt 3 ] && { err "use: custom <tr> <lp> <ps> [slop]"; exit 1; }
        _apply "$1" "$2" "$3" "${4:-8}" "custom" ;;
    *) _perfis "$1" ;;
esac
