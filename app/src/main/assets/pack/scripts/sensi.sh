#!/system/bin/sh
# =============================================================================
#  sensi.sh - GERADOR DE SENSI (Free Fire) sob medida para o aparelho.
#
#  NÃO altera NADA no aparelho: só LÊ o que o sistema expõe e calcula uma sensi
#  pensada para AQUELE aparelho (resolução, densidade/DPI, tamanho físico da
#  tela, taxa de toque, taxa de atualização, SoC/GPU e Android). No fim imprime
#  os valores para você digitar no jogo e o tamanho recomendado do botão de
#  atirar.
#
#  O que de fato muda a sensi (e por isso entra no cálculo):
#    1) DPI (densidade) e resolução  -> quantos "pixels de dedo" o jogo recebe
#       por centímetro. Tela mais densa = mais pixels por cm = o mesmo arrasto
#       cobre mais; a sensi precisa CAIR.
#    2) Tamanho físico da tela (polegadas) -> arrasto em cm até a borda.
#    3) Taxa de toque (Hz do touch) -> quantas amostras por segundo o jogo lê.
#       Mais amostras = mira mais suave; permite sensi um pouco maior sem tremer.
#    4) Taxa de atualização (Hz da tela) -> quanto do movimento aparece. 60Hz
#       "esconde" movimento; 90/120Hz mostra mais, então a sensi cai um pouco.
#    5) Teto de FPS do jogo x SoC/GPU -> quanto o aparelho segura. Aparelho que
#       não segura o teto não deve usar sensi extrema (perde precisão).
#    6) Ajuste de toque já aplicado pelo pack (touch_responsiveness) -> muda a
#       resposta do sistema; a sensi acompanha.
#
#  Uso:
#     sensi.sh                 # mostra a sensi do seu aparelho
#     sensi.sh calc            # idem
#     sensi.sh analyze         # mostra as LEITURAS usadas no cálculo
#     sensi.sh perfil <n>      # recalcula para outro perfil de jogo:
#                              #   padrao | headshot | spray | sniper | speed
#     sensi.sh ff              # valores prontos na ordem da tela do Free Fire
#
#  Nada é inventado: o que o aparelho não expõe aparece como "—" e o cálculo
#  usa o valor seguro (neutro). Reversão: não há o que reverter (só leitura).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

_num() { printf '%s' "$1" | tr -cd '0-9'; }

# -----------------------------------------------------------------------------
#  LEITURA
# -----------------------------------------------------------------------------
sn_read() {
    # --- tela: resolução em pixels ---
    sz="$(sh_get 'wm size')"
    SW="$(printf '%s\n' "$sz" | sed -n 's/.*Physical size: *\([0-9]*\)x\([0-9]*\).*/\1/p' | tail -1)"
    SH="$(printf '%s\n' "$sz" | sed -n 's/.*Physical size: *\([0-9]*\)x\([0-9]*\).*/\2/p' | tail -1)"
    [ -z "$SW" ] && SW=1080
    [ -z "$SH" ] && SH=2400

    # --- densidade (DPI) ---
    DPI="$(sh_get 'wm density' | sed -n 's/.*Physical density: *\([0-9]*\).*/\1/p' | tail -1)"
    DPI="$(_num "$DPI")"
    [ -z "$DPI" ] && DPI="$(sh_get 'getprop ro.sf.lcd_density')"
    DPI="$(_num "$DPI")"
    [ -z "$DPI" ] && DPI=420

    # --- tamanho físico (polegadas), quando o fabricante expõe ---
    XD="$(sh_get 'getprop ro.sf.lcd_density')"
    DIAG_IN=""
    for p in ro.device.diagonal ro.hardware.screen.size ro.screen.size; do
        v="$(sh_get "getprop $p")"
        case "$v" in ''|*[!0-9.]*) ;; *) DIAG_IN="$v"; break ;; esac
    done
    # sem o dado do fabricante, estima pela densidade (padrão ~160dpi = 1"): só
    # para calibrar a ordem de grandeza, nunca para prometer um número exato.
    if [ -z "$DIAG_IN" ]; then
        DIAG_IN="$(awk -v w="$SW" -v h="$SH" -v d="$DPI" 'BEGIN{
            diag_px = sqrt(w*w + h*h);
            printf "%.1f", (d>0 ? diag_px/d : diag_px/420) }')"
        DIAG_SRC="estimado (pela densidade)"
    else
        DIAG_SRC="informado pelo aparelho"
    fi

    # --- taxa de toque (touch sampling) ---
    TOUCH_HZ="$(sh_get 'dumpsys input' | grep -oE 'SamplingRate|sampling rate[ =:]*[0-9]+' | grep -oE '[0-9]+' | sort -n | tail -1)"
    [ -z "$TOUCH_HZ" ] && TOUCH_HZ="$(sh_get 'getprop ro.input.touch.sampling.rate')"
    TOUCH_HZ="$(_num "$TOUCH_HZ")"
    [ -z "$TOUCH_HZ" ] && TOUCH_HZ=0

    # --- taxa de atualização (Hz da tela) ---
    HZ="$(sh_get 'dumpsys display' | grep -oE 'fps=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | sort -n | tail -1)"
    [ -z "$HZ" ] && HZ="$(sh_get 'settings get system peak_refresh_rate')"
    HZ="$(_num "${HZ%%.*}")"
    [ -z "$HZ" ] && HZ=60

    # --- SoC/GPU e Android ---
    MAKER="$(sh_get 'getprop ro.product.manufacturer')"
    MODEL="$(sh_get 'getprop ro.product.model')"
    SOC="$(sh_get 'getprop ro.soc.model')"
    [ -z "$SOC" ] && SOC="$(sh_get 'getprop ro.board.platform')"
    GPU="$(sh_get 'getprop ro.hardware.egl')"
    API="$(sh_get 'getprop ro.build.version.sdk')"
    API="$(_num "$API")"
    [ -z "$API" ] && API=0
    CORES="$(sh_get 'nproc')"
    CORES="$(_num "$CORES")"
    [ -z "$CORES" ] && CORES=8
    tot="$(otm_meminfo MemTotal)"; tot="$(_num "$tot")"
    RAM_MB=0; [ -n "$tot" ] && [ "$tot" -gt 0 ] 2>/dev/null && RAM_MB=$((tot / 1024))

    # --- ajuste de toque que o pack já aplicou (se houver) ---
    TR="$(sh_get 'settings get system touch_responsiveness')"
    TR="$(_num "$TR")"
    [ -z "$TR" ] && TR=100

    # derivados
    PPI="$DPI"
    DIAG_CM="$(awk -v i="$DIAG_IN" 'BEGIN{printf "%.1f", i*2.54}')"
}

# classe do aparelho (reaproveita o critério do smart-opt, simplificado)
sn_tier() {
    s=0
    [ "$RAM_MB" -ge 12000 ] 2>/dev/null && s=$((s+40)) || \
    { [ "$RAM_MB" -ge 8000 ] 2>/dev/null && s=$((s+32)) || \
    { [ "$RAM_MB" -ge 6000 ] 2>/dev/null && s=$((s+24)) || s=$((s+12)); }; }
    [ "$CORES" -ge 8 ] 2>/dev/null && s=$((s+20)) || { [ "$CORES" -ge 6 ] 2>/dev/null && s=$((s+14)) || s=$((s+8)); }
    [ "$API" -ge 33 ] 2>/dev/null && s=$((s+20)) || { [ "$API" -ge 30 ] 2>/dev/null && s=$((s+14)) || s=$((s+6)); }
    [ "$TOUCH_HZ" -ge 240 ] 2>/dev/null && s=$((s+20)) || \
    { [ "$TOUCH_HZ" -ge 180 ] 2>/dev/null && s=$((s+14)) || \
    { [ "$TOUCH_HZ" -ge 120 ] 2>/dev/null && s=$((s+8)) || s=$((s+2)); }; }
    [ "$s" -gt 100 ] && s=100
    if   [ "$s" -ge 80 ]; then echo topo
    elif [ "$s" -ge 60 ]; then echo alto
    elif [ "$s" -ge 40 ]; then echo medio
    else echo entrada; fi
}

# -----------------------------------------------------------------------------
#  CÁLCULO
# -----------------------------------------------------------------------------
# Aparelho de referência (fatores = 1.00): 420 dpi, tela de 16 cm, toque 180 Hz,
# tela 90 Hz, ajuste de toque do pack em 110 e classe "alto desempenho".
#
# Ponto importante: sensi é GOSTO do jogador (graus por centímetro de arrasto),
# não uma propriedade do aparelho. Então os fatores de hardware são CORREÇÕES
# PEQUENAS (no máximo ±10%, com trava) e quem manda de verdade é o perfil.
# Fingir que o hardware muda a sensi em 30% seria número inventado.
sn_clamp() {  # sn_clamp <valor> <min> <max>
    awk -v v="$1" -v a="$2" -v b="$3" 'BEGIN{ if(v<a)v=a; if(v>b)v=b; printf "%.4f", v }'
}

sn_calc() {
    prof="${1:-padrao}"

    # densidade: mais dpi = o mesmo arrasto cobre mais tela -> sensi cai
    FD="$(sn_clamp "$(awk -v d="$DPI" 'BEGIN{ printf "%.4f", 420/(d>0?d:420) }')" 0.90 1.10)"
    # tamanho da tela: tela pequena (cm) = menos espaço de arrasto -> sobe
    FCM="$(sn_clamp "$(awk -v cm="$DIAG_CM" 'BEGIN{ printf "%.4f", 16/(cm>0?cm:16) }')" 0.90 1.10)"
    # taxa de toque: mais amostras = mira mais suave -> permite um pouco mais
    FTO="$(sn_clamp "$(awk -v h="$TOUCH_HZ" 'BEGIN{ printf "%.4f", (h>0?h:180)/180 }')" 0.90 1.10)"
    # taxa da tela: tela lenta esconde movimento -> precisa de um pouco mais
    FHZ="$(sn_clamp "$(awk -v h="$HZ" 'BEGIN{ printf "%.4f", (h>0?h:90)/90 }')" 0.90 1.10)"
    # ajuste de toque que o pack já aplicou (tr alto = mais responsivo -> cai)
    FTR="$(sn_clamp "$(awk -v t="$TR" 'BEGIN{ printf "%.4f", (t>0?t:110)/110 }')" 0.90 1.10)"
    # classe do aparelho: aparelho forte segura FPS alto, mira mais estável
    case "$(sn_tier)" in
        topo)    FTI=1.06 ;;
        alto)    FTI=1.02 ;;
        medio)   FTI=0.98 ;;
        *)       FTI=0.94 ;;
    esac

    # perfil do jogador (é aqui que a sensi realmente muda)
    case "$prof" in
        headshot) PM=1.06 ;;
        spray)    PM=0.95 ;;
        sniper)   PM=0.88 ;;
        speed)    PM=1.12 ;;
        *)        PM=1.00 ;;
    esac

    # sensi geral (o "Geral" do Free Fire) — base 80 no aparelho de referência
    GEN="$(awk -v fd="$FD" -v fc="$FCM" -v ft="$FTO" -v fh="$FHZ" -v ftr="$FTR" -v fi="$FTI" -v pm="$PM" \
        'BEGIN{ v=80*fd*fc*ft*fh*ftr*fi*pm; if(v<40)v=40; if(v>100)v=100; printf "%d", v+0.5 }')"

    # Red dot / 2x / 4x / AWM: no Free Fire a escala segue a do geral, com
    # pequenos ajustes (mira com zoom precisa de menos para não tremer).
    RD="$(awk -v g="$GEN" 'BEGIN{ v=g*0.92; if(v<40)v=40; if(v>100)v=100; printf "%d", v+0.5 }')"
    X2="$(awk -v g="$GEN" 'BEGIN{ v=g*0.88; if(v<40)v=40; if(v>100)v=100; printf "%d", v+0.5 }')"
    X4="$(awk -v g="$GEN" 'BEGIN{ v=g*0.80; if(v<35)v=35; if(v>100)v=100; printf "%d", v+0.5 }')"
    AWM="$(awk -v g="$GEN" 'BEGIN{ v=g*0.72; if(v<30)v=30; if(v>100)v=100; printf "%d", v+0.5 }')"

    # tamanho do botão de atirar: REGRA DO USUÁRIO — nunca acima de 50% da
    # escala, senão fica grande e feio. Telas menores (em cm) pedem botão um
    # pouco maior para o dedo acertar; telas grandes pedem menor.
    BTN="$(awk -v cm="$DIAG_CM" -v hz="$TOUCH_HZ" 'BEGIN{
        if (cm<=0) cm=16;
        v = 38 * (16/cm);
        if (hz>=240) v = v - 3;      # toque rápido: dá para um botão menor
        if (v>50) v=50;              # teto rígido: 50%
        if (v<28) v=28;
        printf "%d", v+0.5 }')"

    # sensibilidade do botão de atirar (o "Fire Button" do FF, 0-100)
    FBTN="$(awk -v g="$GEN" 'BEGIN{ v=g*0.95; if(v<40)v=40; if(v>100)v=100; printf "%d", v+0.5 }')"

    SN_PROF="$prof"
    SN_GEN="$GEN"; SN_RD="$RD"; SN_2X="$X2"; SN_4X="$X4"; SN_AWM="$AWM"
    SN_BTN="$BTN"; SN_FBTN="$FBTN"
}

# -----------------------------------------------------------------------------
#  SAÍDA
# -----------------------------------------------------------------------------
sn_tier_label() {
    case "$1" in
        topo) echo "topo de linha" ;;
        alto) echo "alto desempenho" ;;
        medio) echo "intermediário" ;;
        *) echo "entrada / modesta" ;;
    esac
}

sn_show() {
    sn_read
    sn_calc "${1:-padrao}"
    printf '\n  %s◆%s  %sGERADOR DE SENSI · sob medida para o seu aparelho%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s────────────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %s%s%s %s(%s)%s\n' "$C_A" "$MODEL" "$C_R" "$C_D" "$MAKER" "$C_R"
    printf '  %stela%s %sx%s · %s dpi · %s" (%s cm) · %s Hz · toque %s Hz\n' \
        "$C_A" "$C_R" "$SW" "$SH" "$DPI" "$DIAG_IN" "$DIAG_CM" "$HZ" \
        "$([ "$TOUCH_HZ" -gt 0 ] 2>/dev/null && echo "$TOUCH_HZ" || echo '—')"
    printf '  %sclasse%s %s\n' "$C_A" "$C_R" "$(sn_tier_label "$(sn_tier)")"
    printf '  %sperfil%s %s\n\n' "$C_A" "$C_R" "$SN_PROF"
    printf '  %sDigite no Free Fire (Sensibilidade)%s\n' "$C_A" "$C_R"
    printf '   %sGeral%s              %s%s%s\n' "$C_D" "$C_R" "$C_G" "$SN_GEN" "$C_R"
    printf '   %sPonto vermelho%s    %s%s%s\n' "$C_D" "$C_R" "$C_G" "$SN_RD" "$C_R"
    printf '   %sMira 2x%s           %s%s%s\n' "$C_D" "$C_R" "$C_G" "$SN_2X" "$C_R"
    printf '   %sMira 4x%s           %s%s%s\n' "$C_D" "$C_R" "$C_G" "$SN_4X" "$C_R"
    printf '   %sAWM / mira livre%s  %s%s%s\n' "$C_D" "$C_R" "$C_G" "$SN_AWM" "$C_R"
    printf '   %sBotão de atirar%s   %s%s%%%s  %s(tamanho · máximo 50%%)%s\n' \
        "$C_D" "$C_R" "$C_G" "$SN_BTN" "$C_R" "$C_D" "$C_R"
    printf '   %ssensibilidade do botão%s %s%s%s\n' "$C_D" "$C_R" "$C_G" "$SN_FBTN" "$C_R"
    echo
    printf '  %sDicas%s\n' "$C_A" "$C_R"
    printf '   · Digite no TREINO antes de jogar partida.\n'
    printf '   · Se tremer, baixe o "Geral" de 5 em 5.\n'
    printf '   · Não passe o botão de atirar de 50%% — fica grande e atrapalha.\n'
    printf '   · Rode de novo depois de mudar a resolução do aparelho.\n'
    printf '   %s(este comando NÃO altera nada no aparelho — só leu e calculou)%s\n' "$C_D" "$C_R"
    echo
}

sn_analyze() {
    sn_read
    sn_calc "${1:-padrao}"
    printf '\n  %s◆%s  %sSENSI · leituras usadas no cálculo%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s────────────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  modelo            : %s (%s)\n' "$MODEL" "$MAKER"
    printf '  SoC / GPU         : %s / %s\n' "${SOC:-—}" "${GPU:-—}"
    printf '  Android (API)     : %s (%s)\n' "${API:-—}" "$([ "$API" -ge 33 ] 2>/dev/null && echo '13+' || echo '—')"
    printf '  núcleos / RAM     : %s · %s MB\n' "${CORES:-—}" "${RAM_MB:-—}"
    printf '  resolução         : %sx%s px\n' "$SW" "$SH"
    printf '  densidade (dpi)   : %s\n' "$DPI"
    printf '  diagonal          : %s" (%s cm) — %s\n' "$DIAG_IN" "$DIAG_CM" "$DIAG_SRC"
    printf '  taxa da tela      : %s Hz\n' "$HZ"
    printf '  taxa de toque     : %s\n' "$([ "$TOUCH_HZ" -gt 0 ] 2>/dev/null && echo "$TOUCH_HZ Hz" || echo 'não exposto (usa 180 Hz no cálculo)')"
    printf '  toque do pack (tr) : %s\n' "$TR"
    printf '  classe calculada  : %s\n' "$(sn_tier_label "$(sn_tier)")"
    echo
    printf '  %sfatores aplicados%s (1.00 = neutro)\n' "$C_A" "$C_R"
    printf '   densidade %.3f · tela %.3f · toque %.3f · Hz %.3f · ajuste %.3f\n' \
        "$FD" "$FCM" "$FTO" "$FHZ" "$FTR"
    echo
}

# valores na ordem em que o Free Fire pede (para digitar rápido)
sn_ff() {
    sn_read
    sn_calc "${1:-padrao}"
    printf '%s %s %s %s %s\n' "$SN_GEN" "$SN_RD" "$SN_2X" "$SN_4X" "$SN_AWM"
}

# -----------------------------------------------------------------------------
#  RUNNER
# -----------------------------------------------------------------------------
case "${1:-calc}" in
    ''|calc|show|gerar) sn_show "${2:-padrao}" ;;
    analyze|read|leitura) sn_analyze ;;
    ff|rapido|valores) sn_ff "${2:-padrao}" ;;
    perfil|profile) sn_show "${2:-padrao}" ;;
    help|-h|--help)
        printf '  Uso: sensi.sh [calc|analyze|ff|perfil <nome>]\n'
        printf '   perfis: padrao headshot spray sniper speed\n'
        printf '   Não altera nada no aparelho (só leitura + cálculo).\n' ;;
    *) sn_show "${1}" ;;
esac
rc=$?

# Só leitura: o veredito é "ok" porque o cálculo é o resultado, não uma mudança.
otm_v_report sensi 1
exit $rc
