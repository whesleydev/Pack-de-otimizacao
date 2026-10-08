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
#     ./game-per-app.sh reset <pkg>
#     ./game-per-app.sh reset-all
#
#  Perfis: fps (0.9) · balanced (0.75) · max (0.5)
#
#  Requer Android 12+ (Android 13+ para teto de FPS).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

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
    printf '\n  Uso: %s apply <pkg> <perfil> | custom <pkg> <downscale> [fps] | reset <pkg>\n' "$0"
}

mostrar() {
    pkg="$1"
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
    [ -z "$pkg" ] || [ -z "$perfil" ] && { err "uso: apply <pkg> <perfil>"; return 1; }
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
    [ -z "$pkg" ] || [ -z "$d" ] && { err "uso: custom <pkg> <downscale 0.3-1.0> [fps]"; return 1; }
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
    [ -z "$pkg" ] && { err "uso: mode <pkg> [standard|performance|battery]"; return 1; }
    say "Modo do jogo: $m ($pkg)"
    cmd_game "$pkg" "$m"
    say "pronto — REINICIE o jogo"
}

resetar() {
    pkg="$1"
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

# --- execução ----------------------------------------------------------------
[ $# -eq 0 ] && { listar; exit 0; }

acao="$1"; shift
case "$acao" in
    list)      listar ;;
    show)      mostrar "$1" ;;
    apply)     aplicar "$1" "$2" ;;
    custom)    aplicar_custom "$1" "$2" "$3" ;;
    mode)      modo "$1" "$2" ;;
    reset)     resetar "$1" ;;
    reset-all) resetar_tudo ;;
    *)         err "ação desconhecida: $acao"; listar; exit 1 ;;
esac
