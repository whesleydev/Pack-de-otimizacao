#!/system/bin/sh
# =============================================================================
#  fps.sh - FPS REAL do jogo (lido do SurfaceFlinger, sem root)
#
#  O FPS sai do contador de frames do próprio compositor do Android: cada frame
#  apresentado é carimbado com o horário real de apresentação. O FPS é
#  (frames-1) / (último - primeiro) — nada de estimativa, nada de "Hz da tela
#  fingindo ser FPS".
#
#  Por que isso funciona sem root: o `dumpsys SurfaceFlinger --latency` é
#  liberado para o uid 2000 (o mesmo do Shizuku/ADB). A checagem de permissão
#  do AOSP é `uid != AID_SHELL && !checkPermission(DUMP)` — ou seja, shell passa.
#
#  A leitura NÃO mexe em nada: é só leitura. Se o aparelho não expõe a camada
#  (ou o jogo não está na tela), o FPS volta vazio — o painel mostra "—" em vez
#  de inventar um número.
#
#  Uso:
#     fps.sh now [pkg]      # FPS real agora (o pkg é opcional; sem ele usa o
#                           #   app em primeiro plano)
#     fps.sh layer [pkg]    # qual camada do SurfaceFlinger foi escolhida
#     fps.sh list           # camadas disponíveis (diagnóstico)
#
#  Saída legível por máquina:
#     #OTM-FPS fps=<n> layer=<camada> frames=<n> window=<s>
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
scope_begin fps
otm_v_reset

case "${1:-now}" in
    now)
        pkg="${2:-}"
        layer="$(otm_fps_layer "$pkg")"
        if [ -z "$layer" ]; then
            err "não achei a camada do app${pkg:+ ($pkg)} na tela"
            say "abra o jogo e tente de novo (ou use: fps.sh layer <pacote>)"
            otm_v_report fps 0
            exit 1
        fi
        read_out="$(otm_fps_measure "$layer" "${FPS_WINDOW:-2}")"
        fps="$(printf '%s' "$read_out" | cut -f1)"
        frames="$(printf '%s' "$read_out" | cut -f2)"
        win="$(printf '%s' "$read_out" | cut -f3)"
        if [ -z "$fps" ]; then
            err "a camada \"$layer\" não tem frames novos"
            say "o jogo pode estar parado (menu) ou a camada trocou ao abrir"
            otm_v_report fps 0
            exit 1
        fi
        otm_v_inc apply
        say "FPS real: ${fps}  (${frames} frames em ${win}s)"
        printf '   camada: %s\n' "$layer"
        printf '#OTM-FPS fps=%s layer=%s frames=%s window=%s\n' "$fps" "$layer" "$frames" "$win"
        otm_v_report fps 1
        ;;
    layer)
        pkg="${2:-}"
        layer="$(otm_fps_layer "$pkg")"
        if [ -z "$layer" ]; then
            err "não achei a camada${pkg:+ do pacote $pkg}"
            otm_v_report fps 0
            exit 1
        fi
        say "camada: $layer"
        printf '#OTM-FPS layer=%s\n' "$layer"
        otm_v_report fps 1
        ;;
    list)
        sh_get 'dumpsys SurfaceFlinger --list' 2>/dev/null | grep -v '^$' | head -60
        otm_v_report fps 1
        ;;
    *)
        printf '  uso: fps.sh now [pkg] | fps.sh layer [pkg] | fps.sh list\n'
        otm_v_report fps 0
        ;;
esac
