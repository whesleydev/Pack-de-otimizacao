#!/system/bin/sh
# =============================================================================
#  pack.sh - MENU-MESTRE do Pack de Otimização.
#
#  É o ponto único de entrada: gerencia TODOS os outros scripts
#  (adb-tweaks, deep-tune, debloat, ff-touch, game-per-app, snapshot, bench,
#   device-profile e os builds). Você não precisa decorar caminho de nada.
#
#  Uso interativo:   sh scripts/pack.sh
#  Uso direto (scriptável): sh scripts/pack.sh <acao> [args...]
#
#  Ações: status | apply | restore | snapshot <...> | debloat <...> |
#         deep <modulo> <on|off> | touch <perfil> | game <...> | bench <...> |
#         dns <perfil|menu> | modules <run|list|info|menu> <nome> |
#         device | freeze | unfreeze | gameclean <on|off|status> |
#         keep <on|off|status|list|restore> | ram <boost|status> |
#         <grupo do adb-tweaks> | test | build
#
#  Tudo que aplica é reversível. Estado em ~/.packotm/ (nunca versionado).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
. "$DIR/common.sh"

ST="${HOME:-/data/data/com.termux/files/home}/.packotm"

# --- helpers de estado --------------------------------------------------------
# marca <arquivo> <texto-se-existe> <texto-se-nao-existe>
marca() { [ -f "$1" ] && printf '%s' "$2" || printf '%s' "$3"; }

snap_count() { ls -1 "$ST/snapshots" 2>/dev/null | wc -l | tr -d ' '; }

soc_nome() {
    s="$(sh_get 'getprop ro.soc.model')"
    [ -z "$s" ] && s="$(sh_get 'getprop ro.board.platform')"
    [ -z "$s" ] && s="desconhecido"
    printf '%s' "$s"
}

confirm() {
    printf '  %s [s/N]: ' "$1"
    read -r r
    case "$r" in s|S|y|Y|sim|SIM) return 0 ;; *) return 1 ;; esac
}

# --- status -------------------------------------------------------------------
show_status() {
    printf '\n  %s◆%s  %sSTATUS DO PACK%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '   modo de execução : %s%s%s\n' "$C_G" "$RUN_MODE" "$C_R"
    if have_shell; then
        printf '   privilégio       : %sshell OK%s\n' "$C_G" "$C_R"
    else
        printf '   privilégio       : %ssem shell (nível 1 ainda funciona)%s\n' "$C_Y" "$C_R"
    fi
    printf '   aparelho (SoC)   : %s\n' "$(soc_nome)"
    printf '   versão do pack   : %s\n' "$(cat "$ROOT/VERSION" 2>/dev/null || echo '?')"
    printf '   otimizações deep : %s\n' "$(marca "$ST/deep/on" "${C_G}aplicadas${C_R}" "nenhuma")"
    printf '   debloat          : %s\n' "$(marca "$ST/debloat/applied" "${C_G}aplicado${C_R}" "não aplicado")"
    printf '   snapshots salvos : %s\n' "$(snap_count)"
    tr="$(sh_get 'settings get system touch_responsiveness')"
    [ -z "$tr" ] || [ "$tr" = "null" ] && tr="padrão"
    printf '   toque (FF)       : %s\n' "$tr"
    printf '\n'
}

# --- ações --------------------------------------------------------------------
do_apply() {
    warn "aplica o conjunto recomendado (sem root). Salve um snapshot antes."
    confirm "aplicar agora?" || return 0
    sh "$DIR/adb-tweaks.sh" all
}

do_restore() {
    warn "desfaz TUDO que o pack aplicou (níveis 2, profundas e debloat)."
    confirm "reverter agora?" || return 0
    sh "$DIR/adb-tweaks.sh" restore_all
    sh "$DIR/deep-tune.sh" restore
    sh "$DIR/debloat.sh" off
    say "tudo revertido"
}

do_touch_custom() {
    printf '  touch_responsiveness long_press pointer_speed slop (ex: 110 350 0 4): '
    read -r a b c d
    sh "$DIR/ff-touch.sh" custom "$a" "$b" "$c" "$d"
}

# --- despacho (usado pelo menu E pela linha de comando) -----------------------
dispatch() {
    acao="$1"; [ $# -gt 0 ] && shift
    case "$acao" in
        # meta
        status)   show_status ;;
        apply)    do_apply ;;
        restore)  do_restore ;;

        # delegações diretas
        snapshot|snap) sh "$DIR/snapshot.sh" "$@" ;;
        save)     sh "$DIR/snapshot.sh" save ;;
        all)      sh "$DIR/adb-tweaks.sh" all ;;
        debloat)  sh "$DIR/debloat.sh" "$@" ;;
        deep)     sh "$DIR/deep-tune.sh" "$@" ;;
        touch)    sh "$DIR/ff-touch.sh" "$@" ;;
        headshot|spray|sniper|speed|balanced) sh "$DIR/ff-touch.sh" "$acao" ;;
        game)     sh "$DIR/game-per-app.sh" "$@" ;;
        gameclean|gclean) sh "$DIR/game-clean.sh" "$@" ;;
        keep)     sh "$DIR/keep-alive.sh" "$@" ;;
        ram|ramboost) sh "$DIR/ram-boost.sh" "$@" ;;
        bench)    sh "$DIR/bench.sh" "$@" ;;
        device)   sh "$DIR/device-profile.sh" "$@" ;;
        dns)      sh "$DIR/dns.sh" "$@" ;;
        modules)  sh "$DIR/modules.sh" "$@" ;;
        mods)     sh "$DIR/modules.sh" "$@" ;;
        freeze)   sh "$DIR/adb-tweaks.sh" freeze_apps ;;
        unfreeze) sh "$DIR/adb-tweaks.sh" unfreeze_apps ;;

        # manutenção
        test)     sh "$ROOT/tests/run.sh" ;;
        build)    sh "$DIR/build-pack.sh" ;;
        plugins)  sh "$DIR/build-plugins.sh" ;;
        build-modules) sh "$DIR/build-modules.sh" ;;

        # grupos do adb-tweaks (nível 2)
        perf|perf_max|gpu|net|net_reset|wifi|battery|battery_off|game|ff|ff_open|\
        clean|clean_scan|mem|dnd|dnd_off|screen|fluidez|game_tune|\
        obscure|mobile_net|notif|window_tweaks)
            sh "$DIR/adb-tweaks.sh" "$acao" "$@" ;;

        *) return 1 ;;
    esac
    return 0
}

# --- menu interativo ----------------------------------------------------------
menu() {
    while :; do
        printf '\n'
        printf '  %s◆%s  %sPACK DE OTIMIZAÇÃO%s  %s(menu-mestre)%s\n' \
            "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$C_R"
        printf '  %s──────────────────────────────────────────────%s\n' "$C_D" "$C_R"
        printf '  modo %s%s%s' "$C_G" "$RUN_MODE" "$C_R"
        printf ' · snapshots: %s\n' "$(snap_count)"

        printf '\n  %sRÁPIDO%s\n' "$C_A" "$C_R"
        printf '   %s1%s  Aplicar o pack recomendado (sem root)\n' "$C_A" "$C_R"
        printf '   %s2%s  Reverter tudo\n' "$C_A" "$C_R"
        printf '   %s3%s  Salvar snapshot agora\n' "$C_A" "$C_R"
        printf '   %s4%s  Status do aparelho\n' "$C_A" "$C_R"

        printf '\n  %sOTIMIZAÇÃO (nível 2)%s\n' "$C_A" "$C_R"
        printf '   %s10%s Performance (0.5x/GPU)   %s11%s Performance extrema\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s12%s GPU / renderização       %s13%s DNS / rede (perfis)\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s14%s Wi-Fi                    %s15%s Bateria / Doze\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s16%s Game Mode                %s17%s Free Fire (preparar+abrir)\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s18%s Limpeza (cache/dexopt)   %s19%s RAM (padrão/gaming)\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s20%s Tela / refresh           %s21%s Notificações / DND\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s22%s Congelar apps            %s23%s Descongelar apps\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s24%s %sGame Clean%s (jogo limpo)   %s25%s Anti-relog (manter vivo)\n' "$C_A" "$C_R" "$C_G" "$C_R" "$C_A" "$C_R"
        printf '   %s26%s %sLiberar RAM agora%s\n' "$C_A" "$C_R" "$C_G" "$C_R"

        printf '\n  %sDEBLOAT / PROFUNDAS%s\n' "$C_A" "$C_R"
        printf '   %s30%s Debloat (perfis)         %s31%s Debloat - reverter\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s36%s ANGLE/Vulkan por jogo    %s39%s Detectar hardware\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s38%s MODO JOGO                %s112%s Recompilar (dexopt)\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s110%s Display/HWUI\n' "$C_A" "$C_R"

        printf '\n  %sTOQUE / FREE FIRE%s\n' "$C_A" "$C_R"
        printf '   %s40%s balanced   %s41%s headshot   %s42%s spray\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s43%s sniper     %s44%s speed      %s45%s custom\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s46%s Restaurar toque          %s50%s Tuning por jogo (FPS)\n' "$C_A" "$C_R" "$C_A" "$C_R"

        printf '\n  %sAVANÇADO%s\n' "$C_A" "$C_R"
        printf '   %s121%s Ajustes obscuros  %s122%s Rede móvel  %s123%s Notificações\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s124%s Janelas/imersivo\n' "$C_A" "$C_R"


        printf '\n  %sMÓDULOS / PLUGINS (da pasta)%s\n' "$C_A" "$C_R"
        printf '   %s80%s Executar módulo/plugin (lista + roda)\n' "$C_A" "$C_R"
        printf '   %s81%s Listar módulos e plugins\n' "$C_A" "$C_R"

        printf '\n  %sSNAPSHOT / MANUTENÇÃO%s\n' "$C_A" "$C_R"
        printf '   %s60%s Salvar   %s61%s Listar   %s62%s Restaurar último\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s70%s Rodar testes   %s71%s Gerar Pack 00 (.zip)\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '   %s72%s Ver o zip gerado\n' "$C_A" "$C_R"

        printf '\n   %s0%s  Sair\n' "$C_D" "$C_R"
        printf '  %s›%s ' "$C_A" "$C_R"
        read -r op || { printf '\n'; break; }

        case "$op" in
            1)  do_apply ;;
            2)  do_restore ;;
            3)  sh "$DIR/snapshot.sh" save ;;
            4)  show_status ;;
            10) sh "$DIR/adb-tweaks.sh" perf ;;
            11) sh "$DIR/adb-tweaks.sh" perf_max ;;
            12) sh "$DIR/adb-tweaks.sh" gpu ;;
            13) sh "$DIR/dns.sh" menu ;;
            14) sh "$DIR/adb-tweaks.sh" wifi ;;
            15) sh "$DIR/adb-tweaks.sh" battery ;;
            16) sh "$DIR/adb-tweaks.sh" game ;;
            17) sh "$DIR/adb-tweaks.sh" ff; sh "$DIR/adb-tweaks.sh" ff_open ;;
            18) sh "$DIR/adb-tweaks.sh" clean ;;
            19) printf '  perfil de RAM (padrao/gaming) [padrao]: '; read -r mp
                sh "$DIR/adb-tweaks.sh" mem "${mp:-padrao}" ;;
            20) sh "$DIR/adb-tweaks.sh" screen ;;
            21) sh "$DIR/adb-tweaks.sh" dnd ;;
            22) printf '  modo (suspend/soft) [suspend]: '; read -r fm
                OTM_FREEZE_MODE="${fm:-suspend}" sh "$DIR/adb-tweaks.sh" freeze_apps ;;
            23) sh "$DIR/adb-tweaks.sh" unfreeze_apps ;;
            24) printf '  pacote do jogo [com.dts.freefireth]: '; read -r gp
                printf '  modo (normal/max) [normal]: '; read -r gm
                sh "$DIR/game-clean.sh" on "${gp:-com.dts.freefireth}" "${gm:-normal}" ;;
            25) printf '  pacote do app/jogo [com.dts.freefireth]: '; read -r kp
                sh "$DIR/keep-alive.sh" on "${kp:-com.dts.freefireth}" ;;
            26) printf '  modo (normal/max) [normal]: '; read -r rm
                sh "$DIR/ram-boost.sh" boost "${rm:-normal}" ;;
            30) printf '  perfil (leve/medio/pesado) [medio]: '; read -r dp
                sh "$DIR/debloat.sh" on "${dp:-medio}" ;;
            31) sh "$DIR/debloat.sh" off ;;
            36) printf '  ação (add/remove/list/reset): '; read -r a
                printf '  pacote do jogo (ex com.dts.freefireth): '; read -r gp
                sh "$DIR/deep-tune.sh" angle "$a" "$gp" ;;
            38) printf '  ligar (on) ou desligar (off)? [on]: '; read -r a
                printf '  pacote do jogo (opcional): '; read -r gp
                sh "$DIR/deep-tune.sh" gaming "${a:-on}" "$gp" ;;
            39) sh "$DIR/deep-tune.sh" detect; sh "$DIR/device-profile.sh" ;;
            40) sh "$DIR/ff-touch.sh" balanced ;;
            41) sh "$DIR/ff-touch.sh" headshot ;;
            42) sh "$DIR/ff-touch.sh" spray ;;
            43) sh "$DIR/ff-touch.sh" sniper ;;
            44) sh "$DIR/ff-touch.sh" speed ;;
            45) do_touch_custom ;;
            46) sh "$DIR/ff-touch.sh" restore ;;
            110) printf '  on/off [on]: '; read -r a
                sh "$DIR/deep-tune.sh" display "${a:-on}" ;;
            80) sh "$DIR/modules.sh" menu ;;
            81) sh "$DIR/modules.sh" list ;;
            112) printf '  run (recompilar) ou status [status]: '; read -r a
                sh "$DIR/deep-tune.sh" dexopt "${a:-status}" ;;
            121) sh "$DIR/adb-tweaks.sh" obscure ;;
            122) sh "$DIR/adb-tweaks.sh" mobile_net ;;
            123) sh "$DIR/adb-tweaks.sh" notif ;;
            124) sh "$DIR/adb-tweaks.sh" window_tweaks ;;
            50) printf '  pacote do jogo: '; read -r gp
                printf '  perfil (fps/balanced/max) ou downscale 0.3-1.0: '; read -r gv
                case "$gv" in
                    fps|balanced|max) sh "$DIR/game-per-app.sh" apply "$gp" "$gv" ;;
                    *) sh "$DIR/game-per-app.sh" custom "$gp" "$gv" ;;
                esac ;;
            60) sh "$DIR/snapshot.sh" save ;;
            61) sh "$DIR/snapshot.sh" list ;;
            62) sh "$DIR/snapshot.sh" restore latest ;;
            70) sh "$ROOT/tests/run.sh" ;;
            71) sh "$DIR/build-pack.sh" ;;
            72) ls -lh "$ROOT/releases"/*.zip 2>/dev/null || warn "nenhum zip em releases/ (rode a opção 71)" ;;
            0|q|sair) printf '\n  %svaleu!%s\n\n' "$C_A" "$C_R"; exit 0 ;;
            *) warn "opção inválida" ;;
        esac
        printf '\n  %senter para continuar%s' "$C_D" "$C_R"
        read -r _ || { printf '\n'; break; }
    done
}

# --- entrada ------------------------------------------------------------------
case "$1" in
    ""|menu)      menu ;;
    -h|--help|help)
        printf '  Uso: sh scripts/pack.sh [acao] [args]\n\n'
        printf '   sem argumento  abre o menu interativo\n'
        printf '   status         mostra o estado atual\n'
        printf '   apply|restore  aplica o recomendado / reverte tudo\n'
        printf '   snapshot ...   save|list|restore|show|diff|delete\n'
        printf '   debloat ...    on|off|status|list|disable|enable|uninstall|restore|restrict|unrestrict\n'
        printf '   deep ...       angle|freq|thermal|io|mem|net|latency|debloat|gaming|detect\n'
        printf '   touch ...      balanced|headshot|spray|sniper|speed|custom|restore\n'
        printf '   game ...       apply|custom|list|show|mode|reset\n'
        printf '   dns ...        menu|list|status|<perfil>|custom <host>|off\n'
        printf '   modules ...    list|info <nome>|run <nome>|actions <nome>|menu\n'
        printf '   perf|perf_max|gpu|net|wifi|battery|game|ff|clean|clean_scan|mem|dnd|screen|fluidez\n'
        printf '   freeze|unfreeze|device|bench|test|build\n' ;;
    *)
        if ! dispatch "$@"; then
            err "ação desconhecida: $1"
            printf '  veja: sh scripts/pack.sh --help\n'
            exit 1
        fi ;;
esac
