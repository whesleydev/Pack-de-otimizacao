#!/system/bin/sh
# =============================================================================
#  menu.sh - Menu unificado do Pack de Otimização
#  Reúne comandos ADB (Brevent/Termux/Shizuku/root) e perfis de sensibilidade FF.
#  Uso: ./menu.sh   (ou: sh menu.sh)
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

echo
printf '  %s◆%s  %sPACK DE OTIMIZAÇÃO%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
printf '  %s──────────────────────────────────────%s\n' "$C_D" "$C_R"
printf '  modo de execução: %s%s%s\n' "$C_G" "$RUN_MODE" "$C_R"
if sh_ok; then printf '  privilégio: %sroot/shell OK%s\n' "$C_G" "$C_R"; else printf '  privilégio: %ssem shell%s\n' "$C_Y" "$C_R"; fi

while :; do
    echo
    printf '  %s1%s  Performance (animações 0.5x / GPU)' "$C_A" "$C_R"; echo
    printf '  %s2%s  Performance EXTREMA (animações 0)'    "$C_A" "$C_R"; echo
    printf '  %s3%s  GPU / renderização'                    "$C_A" "$C_R"; echo
    printf '  %s4%s  Rede / DNS (TCP + Cloudflare)'         "$C_A" "$C_R"; echo
    printf '  %s5%s  Wi-Fi tweaks'                          "$C_A" "$C_R"; echo
    printf '  %s6%s  Bateria / Doze'                        "$C_A" "$C_R"; echo
    printf '  %s7%s  Game Mode'                             "$C_A" "$C_R"; echo
    printf '  %s8%s  Free Fire - preparar'                  "$C_A" "$C_R"; echo
    printf '  %s9%s  Free Fire - abrir'                     "$C_A" "$C_R"; echo
    printf '  %s10%s Sensibilidade / toque (perfis)'        "$C_A" "$C_R"; echo
    printf '  %s11%s Congelar apps (com whitelist)'         "$C_A" "$C_R"; echo
    printf '  %s12%s Descongelar apps'                      "$C_A" "$C_R"; echo
    printf '  %s30%s Whitelist do congelador (add/listar)'  "$C_A" "$C_R"; echo
    printf '  %s31%s RAM (perfil padrão / gaming)'           "$C_A" "$C_R"; echo
    printf '  %s32%s Debloat (leve / medio / pesado)'       "$C_A" "$C_R"; echo
    printf '  %s33%s Debloat - reverter tudo'                "$C_A" "$C_R"; echo
    printf '  %s13%s Notificações / DND'                    "$C_A" "$C_R"; echo
    printf '  %s14%s Tela / refresh'                        "$C_A" "$C_R"; echo
    printf '  %s15%s Limpeza (caches/dexopt)'               "$C_A" "$C_R"; echo
    printf '  %s16%s AOT nos jogos (root)'                  "$C_A" "$C_R"; echo
    printf '  %s17%s Salvar snapshot do estado atual'        "$C_A" "$C_R"; echo
    printf '  %s18%s Listar snapshots'                       "$C_A" "$C_R"; echo
    printf '  %s19%s Restaurar último snapshot'              "$C_A" "$C_R"; echo
    printf '  %s20%s Fluidez (animações 0, toque 0 delay, Hz max)' "$C_A" "$C_R"; echo
    printf '  %s21%s Tuning por jogo (resolução/FPS/engine)'      "$C_A" "$C_R"; echo
    printf '  %s── otimizações profundas ─────────────%s\n' "$C_D" "$C_R"
    printf '  %s22%s ANGLE/Vulkan por jogo (sem root)'       "$C_A" "$C_R"; echo
    printf '  %s23%s MODO JOGO TURBO (tudo junto, root)'     "$C_A" "$C_R"; echo
    printf '  %s24%s Frequência CPU/GPU (root)'              "$C_A" "$C_R"; echo
    printf '  %s25%s I/O + memória (MGLRU/zRAM, root)'       "$C_A" "$C_R"; echo
    printf '  %s26%s Rede BBR (root)'                        "$C_A" "$C_R"; echo
    printf '  %s27%s Debloat real (appops/buckets)'          "$C_A" "$C_R"; echo
    printf '  %s28%s Detectar hardware / perfil do aparelho' "$C_A" "$C_R"; echo
    printf '  %s29%s Limite térmico (root, ⚠️ trava em 45°C)' "$C_A" "$C_R"; echo
    printf '  %s── extremos / pouco conhecidos (root) ──%s\n' "$C_D" "$C_R"
    printf '  %s40%s VM / kernel de memória (root)'          "$C_A" "$C_R"; echo
    printf '  %s41%s Escalonador / EAS + schedtune (root)'   "$C_A" "$C_R"; echo
    printf '  %s42%s GPU extrema KGSL/Mali (root)'           "$C_A" "$C_R"; echo
    printf '  %s43%s Núcleos sempre ligados (root)'          "$C_A" "$C_R"; echo
    printf '  %s44%s Input / touch boost (root)'             "$C_A" "$C_R"; echo
    printf '  %s45%s CPU idle menu (root)'                   "$C_A" "$C_R"; echo
    printf '  %s46%s Rede avançada 2 / BBR2 (root)'          "$C_A" "$C_R"; echo
    printf '  %s47%s zRAM avançada zstd (root)'              "$C_A" "$C_R"; echo
    printf '  %s48%s Kernel: tirar overhead (root)'          "$C_A" "$C_R"; echo
    printf '  %s49%s Display / HWUI props (sem root)'        "$C_A" "$C_R"; echo
    printf '  %s50%s Dalvik / ART heaps (root)'              "$C_A" "$C_R"; echo
    printf '  %s51%s Recompilar apps (dexopt/AOT)'           "$C_A" "$C_R"; echo
    printf '  %s52%s ⚡ MODO EXTREMO (TUDO de uma vez)'      "$C_RD" "$C_R"; echo
    printf '  %s── avançado sem root ─────────────────%s\n' "$C_D" "$C_R"
    printf '  %s55%s Ajustes obscuros (standby/Doze)'        "$C_A" "$C_R"; echo
    printf '  %s56%s Rede móvel / economia de dados'         "$C_A" "$C_R"; echo
    printf '  %s57%s Menos notificações (heads-up)'          "$C_A" "$C_R"; echo
    printf '  %s58%s Janelas / modo imersivo'                "$C_A" "$C_R"; echo
    printf '  %s90%s Aplicar TUDO (all)'                    "$C_G" "$C_R"; echo
    printf '  %s91%s RESTAURAR tudo'                        "$C_Y" "$C_R"; echo
    printf '  %s0%s  Sair'                                  "$C_D" "$C_R"; echo
    printf '  %s›%s ' "$C_A" "$C_R"
    read -r op

    case "$op" in
        1)  "$DIR/adb-tweaks.sh" perf ;;
        2)  "$DIR/adb-tweaks.sh" perf_max ;;
        3)  "$DIR/adb-tweaks.sh" gpu ;;
        4)  "$DIR/adb-tweaks.sh" net ;;
        5)  "$DIR/adb-tweaks.sh" wifi ;;
        6)  "$DIR/adb-tweaks.sh" battery ;;
        7)  "$DIR/adb-tweaks.sh" game ;;
        8)  "$DIR/adb-tweaks.sh" ff ;;
        9)  "$DIR/adb-tweaks.sh" ff_open ;;
        10) printf '  perfil (balanced/headshot/spray/sniper/speed/custom): '
            read -r p
            if [ "$p" = "custom" ]; then
                printf '  tr lp ps slop: '; read -r a b c d
                "$DIR/ff-touch.sh" custom "$a" "$b" "$c" "$d"
            else
                "$DIR/ff-touch.sh" "$p"
            fi ;;
        11) printf '  modo (suspend/soft) [suspend]: '; read -r fm
            OTM_FREEZE_MODE="${fm:-suspend}" "$DIR/adb-tweaks.sh" freeze_apps ;;
        12) "$DIR/adb-tweaks.sh" unfreeze_apps ;;
        30) printf '  (a)dd pacote / (l)istar whitelist: '; read -r wl
            case "$wl" in
                l|list|listar) "$DIR/adb-tweaks.sh" freeze_whitelist_list ;;
                *) printf '  pacote: '; read -r wp
                   "$DIR/adb-tweaks.sh" freeze_whitelist_add "$wp" ;;
            esac ;;
        31) printf '  perfil de RAM (padrao/gaming) [padrao]: '; read -r mp
            "$DIR/adb-tweaks.sh" mem "${mp:-padrao}" ;;
        32) printf '  perfil (leve/medio/pesado) [medio]: '; read -r dp
            "$DIR/debloat.sh" on "${dp:-medio}" ;;
        33) "$DIR/debloat.sh" off ;;
        13) "$DIR/adb-tweaks.sh" dnd ;;
        14) "$DIR/adb-tweaks.sh" screen ;;
        15) "$DIR/adb-tweaks.sh" clean ;;
        16) "$DIR/adb-tweaks.sh" aot ;;
        17) "$DIR/snapshot.sh" save ;;
        18) "$DIR/snapshot.sh" list ;;
        19) "$DIR/snapshot.sh" restore latest ;;
        20) printf '  long_press (100-250) e Hz (ex 120.0): '
            read -r lp hz
            "$DIR/adb-tweaks.sh" fluidez "$lp" "$hz" ;;
        21) printf '  pacote do jogo (ex com.dts.freefireth): '
            read -r gp
            printf '  perfil (fps/balanced/max) ou downscale 0.3-1.0: '
            read -r gv
            case "$gv" in
                fps|balanced|max) "$DIR/game-per-app.sh" apply "$gp" "$gv" ;;
                *) "$DIR/game-per-app.sh" custom "$gp" "$gv" ;;
            esac ;;
        22) printf '  ação (add/remove/list/reset) e pacote: '
            read -r a gp
            "$DIR/deep-tune.sh" angle "$a" "$gp" ;;
        23) printf '  ligar (on) ou desligar (off)? [on] e pacote opcional: '
            read -r a gp
            "$DIR/deep-tune.sh" gaming "${a:-on}" "$gp" ;;
        24) printf '  on/off [on]: '; read -r a
            "$DIR/deep-tune.sh" freq "${a:-on}" ;;
        25) printf '  io/mem on/off [on]: '; read -r a b
            case "$a" in io|mem) "$DIR/deep-tune.sh" "$a" "${b:-on}" ;;
                         *) warn "use: io on | mem on" ;; esac ;;
        26) printf '  on/off [on]: '; read -r a
            "$DIR/deep-tune.sh" net "${a:-on}" ;;
        27) printf '  on/off [on]: '; read -r a
            "$DIR/deep-tune.sh" debloat "${a:-on}" ;;
        28) "$DIR/deep-tune.sh" detect
            "$DIR/device-profile.sh" ;;
        29) printf '  on/off/temp [temp]: '; read -r a
            "$DIR/deep-tune.sh" thermal "${a:-temp}" ;;
        40|41|42|43|44|45|46|47|48|50)  # módulos extremos (root) -> número -> nome
            case "$op" in
                40) m=vm ;; 41) m=sched ;; 42) m=gpu ;; 43) m=cores ;;
                44) m=input ;; 45) m=idle ;; 46) m=net2 ;; 47) m=zram ;;
                48) m=kernel ;; 50) m=dalvik ;;
            esac
            printf '  on/off [on]: '; read -r a
            "$DIR/deep-tune.sh" "$m" "${a:-on}" ;;
        49) printf '  on/off [on]: '; read -r a
            "$DIR/deep-tune.sh" display "${a:-on}" ;;
        51) printf '  run (recompilar) ou status [status]: '; read -r a
            "$DIR/deep-tune.sh" dexopt "${a:-status}" ;;
        52) printf '  %sIsso liga TUDO e esquenta muito. Continuar? [s/N]: %s' "$C_Y" "$C_R"; read -r r
            case "$r" in s|S|sim|SIM|y|Y) THERMAL_OK=1 "$DIR/deep-tune.sh" extreme ;;
                          *) warn "cancelado" ;; esac ;;
        55) "$DIR/adb-tweaks.sh" obscure ;;
        56) "$DIR/adb-tweaks.sh" mobile_net ;;
        57) "$DIR/adb-tweaks.sh" notif ;;
        58) "$DIR/adb-tweaks.sh" window_tweaks ;;
        90) "$DIR/adb-tweaks.sh" all ;;
        91) "$DIR/adb-tweaks.sh" restore_all
            "$DIR/deep-tune.sh" restore ;;
        0|q|sair) printf '\n  %svaleu!%s\n\n' "$C_A" "$C_R"; exit 0 ;;
        *)  warn "opção inválida" ;;
    esac
    printf '\n  %senter para continuar%s' "$C_D" "$C_R"
    read -r _
done
