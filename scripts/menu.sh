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
    printf '  %s11%s Congelar apps (freezer)'               "$C_A" "$C_R"; echo
    printf '  %s12%s Descongelar apps'                      "$C_A" "$C_R"; echo
    printf '  %s13%s Notificações / DND'                    "$C_A" "$C_R"; echo
    printf '  %s14%s Tela / refresh'                        "$C_A" "$C_R"; echo
    printf '  %s15%s Limpeza (caches/dexopt)'               "$C_A" "$C_R"; echo
    printf '  %s16%s AOT nos jogos (root)'                  "$C_A" "$C_R"; echo
    printf '  %s17%s Salvar snapshot do estado atual'        "$C_A" "$C_R"; echo
    printf '  %s18%s Listar snapshots'                       "$C_A" "$C_R"; echo
    printf '  %s19%s Restaurar último snapshot'              "$C_A" "$C_R"; echo
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
        11) "$DIR/adb-tweaks.sh" freezer ;;
        12) "$DIR/adb-tweaks.sh" unfreeze_apps ;;
        13) "$DIR/adb-tweaks.sh" dnd ;;
        14) "$DIR/adb-tweaks.sh" screen ;;
        15) "$DIR/adb-tweaks.sh" clean ;;
        16) "$DIR/adb-tweaks.sh" aot ;;
        17) "$DIR/snapshot.sh" save ;;
        18) "$DIR/snapshot.sh" list ;;
        19) "$DIR/snapshot.sh" restore latest ;;
        90) "$DIR/adb-tweaks.sh" all ;;
        91) "$DIR/adb-tweaks.sh" restore_all ;;
        0|q|sair) printf '\n  %svaleu!%s\n\n' "$C_A" "$C_R"; exit 0 ;;
        *)  warn "opção inválida" ;;
    esac
    printf '\n  %senter para continuar%s' "$C_D" "$C_R"
    read -r _
done
