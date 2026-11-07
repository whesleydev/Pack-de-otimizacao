#!/system/bin/sh
# =============================================================================
#  game-per-app.sh - Tuning POR JOGO (resolução / FPS / engine)
#
#  Mexe SÓ no app do jogo via Game Mode do Android 12+ (interventions).
#  NÃO altera o telefone: nada global, nada de settings do sistema.
#  Reversível por jogo.
#
#  Uso:
#     ./game-per-app.sh list
#     ./game-per-app.sh show <pkg>
#     ./game-per-app.sh apply <pkg> <perfil>
#     ./game-per-app.sh custom <pkg> <downscale> [fps]
#     ./game-per-app.sh mode <pkg> [standard|performance|battery]
#     ./game-per-app.sh dpi <largura_dp|padrao>   (igual "Menor largura" do Android)
#     ./game-per-app.sh dpi-reset
#     ./game-per-app.sh reset <pkg>
#     ./game-per-app.sh reset-all
#
#  Perfis: fps (0.9) · balanced (0.75) · max (0.5)
#
#  Requer Android 12+ (Android 13+ para teto de FPS).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
scope_begin game-per-app
otm_v_reset


# jogos conhecidos (só para o comando "list")
JOGOS="com.dts.freefireth:Free Fire
com.dts.freefiremax:Free Fire MAX
com.activision.callofduty.shooter:Call of Duty Mobile
com.mobile.legends:Mobile Legends
com.tencent.ig:PUBG Mobile
com.dts.freefireth.br:Free Fire BR
com.dts.freefireth.id:Free Fire ID"

perfil_valor() {
    case "$1" in
        fps)      echo "0.9" ;;
        balanced) echo "0.75" ;;
        max)      echo "0.5" ;;
        *)        echo "" ;;
    esac
}

requer_android12() {
    api=$(sh_get "getprop ro.build.version.sdk" 2>/dev/null)
    case "$api" in
        ''|*[!0-9]*) return 0 ;;   # não deu pra ler: segue
        *) [ "$api" -ge 31 ] && return 0 ;;
    esac
    err "Game Mode interventions exigem Android 12+ (API 31). Seu API: $api"
    return 1
}

aplicar_overlay() {
    pkg="$1"; cfg="$2"
    sh_run "device_config put game_overlay $pkg $cfg" >/dev/null
}

cmd_game() {
    # cmd_game <pkg> <standard|performance|battery>
    pkg="$1"; m="$2"
    sh_run "cmd game set --mode $m $pkg" >/dev/null
}

listar() {
    printf '  Perfis:\n'
    printf '   %bfps%b        downscale 0.9  (mais FPS, nitidez quase igual)\n' "$C_A" "$C_R"
    printf '   %bbalanced%b   downscale 0.75 (equilíbrio)\n' "$C_A" "$C_R"
    printf '   %bmax%b        downscale 0.5  (FPS máximo, imagem serrilhada)\n' "$C_A" "$C_R"
    printf '\n  Jogos conhecidos:\n'
    echo "$JOGOS" | while IFS=: read -r p n; do
        [ -z "$p" ] && continue
        printf '   %-38s %s\n' "$p" "$n"
    done
    printf '\n  Menor largura (o "Menor largura" das Opções do desenvolvedor) — sistema inteiro:\n'
    printf '   padrão deste aparelho: %b%s dp%b\n' "$C_A" "$(dpi_padrao_dp)" "$C_R"
    printf '   dpi <largura_dp>   aplica a largura exata (o painel sugere a faixa sã)\n'
    printf '   dpi padrao         volta ao padrão do aparelho\n'
    printf '\n  Uso: %s apply <pkg> <perfil> | custom <pkg> <downscale> [fps] | dpi <largura_dp> | reset <pkg>\n' "$0"
}

# _resolver_pkg <pkg|auto> -> define RESOLVED_PKG. "auto" = o jogo escolhido no
# pack (Modo Competitivo); sem escolha, o app em primeiro plano; e, se nem isso
# der para ler (tela bloqueada, dumpsys sem a linha), o Free Fire — a MESMA
# decisão do `adb-tweaks.sh game_open`. Sem esse último degrau o flutuante
# devolvia erro no meio da partida só porque o usuário nunca escolheu um jogo.
# Devolve por variável (não por stdout) de propósito: capturar com $( ) engoliria
# a mensagem de erro junto com o valor.
_resolver_pkg() {
    if [ "$1" = "auto" ] || [ "$1" = "-" ]; then
        RESOLVED_PKG="$(sed -n '1p' "$ST/game/pkg" 2>/dev/null | tr -d '\n')"
        [ -n "$RESOLVED_PKG" ] || RESOLVED_PKG="$(otm_fg_pkg)"
        [ -n "$RESOLVED_PKG" ] || RESOLVED_PKG="$GAME_PKG_DEFAULT"
        [ -n "$RESOLVED_PKG" ] || { err "não sei qual é o jogo (escolha um no pack)"; return 1; }
    else
        RESOLVED_PKG="$1"
    fi
    return 0
}

mostrar() {
    _resolver_pkg "$1" || return 1
    pkg="$RESOLVED_PKG"
    [ -z "$pkg" ] && { err "faltou o pacote"; return 1; }
    say "Config atual do jogo: $pkg"
    atual=$(sh_get "device_config get game_overlay $pkg")
    if [ -z "$atual" ] || [ "$atual" = "null" ]; then
        printf '   %s(nenhuma intervention definida)%s\n' "$C_D" "$C_R"
    else
        printf '   %s\n' "$atual"
    fi
}

aplicar() {
    pkg="$1"; perfil="$2"
    [ -z "$pkg" ] || [ -z "$perfil" ] && { err "uso: apply <pkg|auto> <perfil>"; return 1; }
    _resolver_pkg "$pkg" || return 1
    pkg="$RESOLVED_PKG"
    requer_android12 || return 1
    d=$(perfil_valor "$perfil")
    [ -z "$d" ] && { err "perfil inválido: $perfil (use fps|balanced|max)"; return 1; }
    bkp_begin
    antigo=$(sh_get "device_config get game_overlay $pkg")
    if [ -z "$antigo" ] || [ "$antigo" = "null" ]; then
        bkp_raw "device_config delete game_overlay $pkg"
    else
        bkp_raw "device_config put game_overlay $pkg $antigo"
    fi
    say "Aplicando '$perfil' (downscale $d) em $pkg"
    aplicar_overlay "$pkg" "mode=2,downscaleFactor=$d:mode=3,downscaleFactor=$d"
    cmd_game "$pkg" performance
    say "pronto — REINICIE o jogo para valer"
    mostrar "$pkg"
}

aplicar_custom() {
    pkg="$1"; d="$2"; fps="$3"
    [ -z "$pkg" ] || [ -z "$d" ] && { err "uso: custom <pkg|auto> <downscale 0.3-1.0> [fps]"; return 1; }
    _resolver_pkg "$pkg" || return 1
    pkg="$RESOLVED_PKG"
    requer_android12 || return 1
    bkp_begin
    antigo=$(sh_get "device_config get game_overlay $pkg")
    if [ -z "$antigo" ] || [ "$antigo" = "null" ]; then
        bkp_raw "device_config delete game_overlay $pkg"
    else
        bkp_raw "device_config put game_overlay $pkg $antigo"
    fi
    if [ -n "$fps" ]; then
        cfg="mode=2,fps=$fps,downscaleFactor=$d:mode=3,fps=$fps,downscaleFactor=$d"
    else
        cfg="mode=2,downscaleFactor=$d:mode=3,downscaleFactor=$d"
    fi
    say "Aplicando custom (downscale $d${fps:+ fps $fps}) em $pkg"
    aplicar_overlay "$pkg" "$cfg"
    cmd_game "$pkg" performance
    say "pronto — REINICIE o jogo para valer"
}

modo() {
    pkg="$1"; m="${2:-performance}"
    [ -z "$pkg" ] && { err "uso: mode <pkg|auto> [standard|performance|battery]"; return 1; }
    _resolver_pkg "$pkg" || return 1
    pkg="$RESOLVED_PKG"
    say "Modo do jogo: $m ($pkg)"
    cmd_game "$pkg" "$m"
    say "pronto — REINICIE o jogo"
}

resetar() {
    _resolver_pkg "$1" || return 1
    pkg="$RESOLVED_PKG"
    [ -z "$pkg" ] && { err "faltou o pacote"; return 1; }
    say "Removendo intervention de $pkg"
    sh_run "device_config delete game_overlay $pkg" >/dev/null
    cmd_game "$pkg" standard
    say "restaurado"
}

resetar_tudo() {
    say "Removendo interventions de todos os jogos conhecidos"
    echo "$JOGOS" | while IFS=: read -r p n; do
        [ -z "$p" ] && continue
        sh_run "device_config delete game_overlay $p" >/dev/null
        cmd_game "$p" standard
        printf '   %s%s%s\n' "$C_D" "$p" "$C_R"
    done
    say "restaurado"
}
# --- DPI / "Menor largura" (densidade) do telefone ----------------------------
# O que o Android chama de "Menor largura" (Opções do desenvolvedor) é a largura
# da tela em dp:  menor_largura_dp = 160 * menor_lado_em_px / densidade.
#
# Antes este ajuste mexia só na DENSIDADE, com presets inventados ("pequeno",
# "grande"). Isso confundia: o número que o usuário vê no aparelho é a MENOR
# LARGURA (dp), não a densidade. Pior: escrever uma densidade fora da faixa
# segura (ex.: 969) deixava a interface minúscula e o painel flutuante
# inutilizável. Agora o alvo é a PRÓPRIA menor largura (dp), o mesmo número do
# Android, sempre lido de volta do aparelho.
#
# O padrão é o valor do aparelho: não escreve override nenhum, deixa o sistema
# decidir (é o que o "padrão" do Android faz). A faixa é relativa ao aparelho
# (metade até o dobro da largura padrão), nunca um número fixo que estoura.

_dpi_dims() {
    # imprime "fisico_x fisico_y override_x override_y densidade"
    _sz="$(sh_get 'wm size' 2>/dev/null)"
    _ph="$(otm_echo "$_sz" | sed -n 's/.*Physical size: *\([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)"
    _ov="$(otm_echo "$_sz" | sed -n 's/.*Override size: *\([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)"
    _den="$(sh_get 'wm density' 2>/dev/null | sed -n 's/.*Physical density: *\([0-9]*\).*/\1/p' | tail -1)"
    _den="$(otm_num "$_den")"; [ -z "$_den" ] && _den=420
    [ -z "$_ph" ] && _ph="$(sh_get 'getprop ro.sf.lcd_density' >/dev/null 2>&1; echo '1080 2400')"
    # se não leu nada, assume um valor plausível (nunca deixa vazio)
    _px="$(echo "$_ph" | cut -d' ' -f1)"; _py="$(echo "$_ph" | cut -d' ' -f2)"
    [ -z "$_px" ] && _px=1080; [ -z "$_py" ] && _py=2400
    _ox="$(echo "$_ov" | cut -d' ' -f1)"; _oy="$(echo "$_ov" | cut -d' ' -f2)"
    printf '%s %s %s %s %s' "$_px" "$_py" "${_ox:-0}" "${_oy:-0}" "$_den"
}

# menor lado em px do que está valendo AGORA (override de tamanho vence o físico)
_dpi_menor_lado() {
    _dims="$(_dpi_dims)"
    _px="$(echo "$_dims" | cut -d' ' -f1)"
    _py="$(echo "$_dims" | cut -d' ' -f2)"
    _ox="$(echo "$_dims" | cut -d' ' -f3)"
    _oy="$(echo "$_dims" | cut -d' ' -f4)"
    if [ -n "$_ox" ] && [ "$_ox" -gt 0 ] 2>/dev/null; then _px="$_ox"; _py="$_oy"; fi
    if [ "$_px" -le "$_py" ] 2>/dev/null; then printf '%s' "$_px"; else printf '%s' "$_py"; fi
}

# largura padrão do aparelho, em dp (densidade física)
dpi_padrao_dp() { otm_dpi_padrao_dp; }

# densidade que produz a largura <dp> pedida (mantém o tamanho da tela)
dpi_densidade_para_dp() {
    _alvo="$1"
    set -- $(_dpi_dims)
    _den="$5"
    _lado="$(_dpi_menor_lado)"
    awk -v p="$_lado" -v dp="$_alvo" 'BEGIN{ if (dp>0) printf "%d", 160*p/dp + 0.5 }'
}

# faixa sã: metade até o dobro da largura padrão (nunca um número fixo)
dpi_faixa() {
    _pad="$(dpi_padrao_dp)"
    awk -v b="$_pad" 'BEGIN{ lo=int(b/2+0.5); hi=int(b*2+0.5); printf "%d %d", lo, hi }'
}

# otm_dpi_clamp <dp> -> prende na faixa sã relativa ao aparelho
otm_dpi_clamp() {
    _v="$1"
    _faixa="$(dpi_faixa)"
    _lo="$(echo "$_faixa" | cut -d' ' -f1)"
    _hi="$(echo "$_faixa" | cut -d' ' -f2)"
    awk -v v="$_v" -v lo="$_lo" -v hi="$_hi" \
        'BEGIN{ v+=0; if (v<lo) v=lo; if (v>hi) v=hi; printf "%d", v }'
}

# aplica a largura <dp> (o mesmo "Menor largura" das Opções do desenvolvedor).
aplicar_dpi() {
    alvo="$1"
    [ -z "$alvo" ] && { err "uso: dpi <largura_dp|padrao>"; return 1; }
    # "padrão" não escreve nada: devolve a decisão ao sistema.
    if [ "$alvo" = "padrao" ] || [ "$alvo" = "normal" ] || [ "$alvo" = "default" ]; then
        resetar_dpi; return $?
    fi
    case "$alvo" in
        ''|*[!0-9]*) err "valor de largura inválido: $alvo"; return 1 ;;
    esac
    set -- $(dpi_faixa); _lo="$1"; _hi="$2"
    preso="$(otm_dpi_clamp "$alvo")"
    if [ "$preso" != "$alvo" ]; then
        warn "largura $alvo fora da faixa ${_lo}-${_hi} dp; usando ${preso}"
        alvo="$preso"
    fi
    _den="$(dpi_densidade_para_dp "$alvo")"
    [ -z "$_den" ] && { err "não consegui calcular a densidade"; return 1; }
    bkp_begin
    # guarda a reversão uma vez: o override é removido com `wm density reset`.
    if ! grep -q 'wm density reset' "$OFF_SH" 2>/dev/null; then
        bkp_raw "wm density reset"
    fi
    sh_run "wm density $_den" >/dev/null 2>&1
    # confere lendo o override de volta (não basta "mandei aplicar")
    agora="$(sh_get 'wm density' | sed -n 's/.*Override density: *\([0-9]*\).*/\1/p' | tail -1)"
    agora="$(otm_num "$agora")"
    if [ "$agora" = "$_den" ]; then
        otm_v_inc apply; otm_v_inc changed
        mkdir -p "$ST" 2>/dev/null
        printf '%s\n' "$alvo" > "$ST/dpi_profile" 2>/dev/null
        printf '   %bOK%b menor largura %s dp (densidade %s)\n' "$C_G" "$C_R" "$alvo" "$_den"
        say "pronto — a interface muda na hora"
    else
        otm_v_inc apply; otm_v_inc failed
        printf '   %bX%b DPI não mudou (lido: %s)\n' "$C_RD" "$C_R" "${agora:-vazio}"
        return 1
    fi
}

resetar_dpi() {
    say "Voltando a menor largura ao padrão do aparelho"
    sh_run "wm density reset" >/dev/null 2>&1
    rm -f "$ST/dpi_profile" 2>/dev/null
    say "menor largura padrão ($(dpi_padrao_dp) dp)"
}


# --- execução ----------------------------------------------------------------
[ $# -eq 0 ] && { listar; exit 0; }

acao="$1"; shift
case "$acao" in
    list)      listar ;;
    show)      mostrar "$1" ;;
    apply)     aplicar "$1" "$2" ;;
    custom)    aplicar_custom "$1" "$2" "$3" ;;
    mode)      modo "$1" "$2" ;;
    dpi)       aplicar_dpi "$1" ;;
    dpi-reset) resetar_dpi ;;
    reset)     resetar "$1"; resetar_dpi ;;
    reset-all) resetar_tudo; resetar_dpi ;;
    *)         err "ação desconhecida: $acao"; listar; exit 1 ;;
esac

rc=$?
otm_v_report game-per-app
exit $rc
