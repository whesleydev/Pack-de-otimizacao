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
#     ./game-per-app.sh dpi <compacto|padrao|grande|80-600>
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
    printf '\n  DPI (densidade do telefone) — vale para o sistema inteiro:\n'
    printf '   %bpequeno%b   ~15%% menor que o físico (cabe mais, HUD menor)\n' "$C_A" "$C_R"
    printf '   %bpadrao%b    densidade de fábrica\n' "$C_A" "$C_R"
    printf '   %bgrande%b    ~15%% maior (tela pequena / vista cansada)\n' "$C_A" "$C_R"
    printf '   ou um número (%s a %s). Volte com: dpi-reset\n' "$DPI_MIN" "$DPI_MAX"
    printf '\n  Uso: %s apply <pkg> <perfil> | custom <pkg> <downscale> [fps] | dpi <perfil> | reset <pkg>\n' "$0"
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

# --- DPI (densidade) do telefone ----------------------------------------------
# Muda a densidade LÓGICA da tela (o mesmo "Menor largura" das Opções do
# desenvolvedor). É um ajuste GLOBAL do telefone: vale para o sistema inteiro,
# não só para um app. Menos DPI = interface menor (cabe mais coisa, HUD/botões
# menores, mais campo de visão e menos pixels para compor); mais DPI = tudo
# maior. Muda na hora.
#
# Faixa: 300 (mínimo) a 600 (máximo). Abaixo de 300 a interface fica pequena
# demais para usar; acima de 600 fica gigante na tela. O padrão é a densidade
# de fábrica (`dpi padrao` / `dpi-reset` remove o override).
DPI_MIN=300
DPI_MAX=600

DPI_FISICA() {
    d="$(sh_get 'wm density' | sed -n 's/.*Physical density: *\([0-9]*\).*/\1/p' | tail -1)"
    d="$(otm_num "$d")"
    [ -z "$d" ] && d="$(sh_get 'getprop ro.sf.lcd_density')"
    d="$(otm_num "$d")"
    [ -z "$d" ] && d=420
    printf '%s' "$d"
}

# otm_dpi_clamp <valor> -> prende o valor na faixa segura
otm_dpi_clamp() {
    awk -v v="$1" -v lo="$DPI_MIN" -v hi="$DPI_MAX" \
        'BEGIN{ v+=0; if (v<lo) v=lo; if (v>hi) v=hi; printf "%d", v }'
}

dpi_valor() {
    base="$(DPI_FISICA)"
    case "$1" in
        pequeno|compacto|menor) awk -v b="$base" 'BEGIN{printf "%d", b*0.85+0.5}' ;;
        padrao|normal|medio)    printf '%s' "$base" ;;
        grande|maior)           awk -v b="$base" 'BEGIN{printf "%d", b*1.15+0.5}' ;;
        ''|*[!0-9]*)            printf '' ;;
        *)                      printf '%s' "$1" ;;
    esac
}

aplicar_dpi() {
    alvo="$1"
    [ -z "$alvo" ] && { err "uso: dpi <valor ${DPI_MIN}-${DPI_MAX}|pequeno|padrao|grande>"; return 1; }
    # "padrão" não escreve densidade: remove o override (volta à física).
    if [ "$alvo" = "padrao" ] || [ "$alvo" = "normal" ]; then
        resetar_dpi; return $?
    fi
    valor="$(dpi_valor "$alvo")"
    [ -z "$valor" ] && { err "valor de DPI inválido: $alvo"; return 1; }
    # prende na faixa segura (300-600): fora disso a tela fica inutilizável
    preso="$(otm_dpi_clamp "$valor")"
    if [ "$preso" != "$valor" ]; then
        warn "DPI $valor fora da faixa ${DPI_MIN}-${DPI_MAX}; usando ${preso}"
        valor="$preso"
    fi
    bkp_begin
    base="$(DPI_FISICA)"
    # guarda a reversão: o override é removido com `wm density reset` (volta à
    # densidade física), que é o estado padrão do aparelho.
    if ! grep -q 'wm density reset' "$OFF_SH" 2>/dev/null; then
        bkp_raw "wm density reset"
    fi
    sh_run "wm density $valor" >/dev/null 2>&1
    agora="$(sh_get 'wm density' | sed -n 's/.*Override density: *\([0-9]*\).*/\1/p' | tail -1)"
    agora="$(otm_num "$agora")"
    if [ "$agora" = "$valor" ]; then
        otm_v_inc apply; otm_v_inc changed
        # guarda o PERFIL escolhido (não o número) para o painel marcar qual
        # opção está em uso — o número muda de aparelho para aparelho.
        mkdir -p "$ST" 2>/dev/null
        printf '%s\n' "$alvo" > "$ST/dpi_profile" 2>/dev/null
        printf '   %bOK%b DPI %s (físico %s)\n' "$C_G" "$C_R" "$valor" "$base"
        say "pronto — a interface muda na hora"
    else
        otm_v_inc apply; otm_v_inc failed
        printf '   %bX%b DPI não mudou (lido: %s)\n' "$C_RD" "$C_R" "${agora:-vazio}"
        return 1
    fi
}

resetar_dpi() {
    say "Voltando a densidade ao padrão do aparelho"
    sh_run "wm density reset" >/dev/null 2>&1
    rm -f "$ST/dpi_profile" 2>/dev/null
    base="$(DPI_FISICA)"
    say "DPI restaurado (${base})"
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
