#!/system/bin/sh
# =============================================================================
#  apply.sh - CLI do Congelar Apps. É o que a WebUI e o action.sh chamam.
#
#  Uso:
#     sh apply.sh freeze                 # congela a blacklist (menos whitelist)
#     sh apply.sh unfreeze               # descongela tudo
#     sh apply.sh list                   # mostra whitelist/blacklist e o que será congelado
#     sh apply.sh wl-add <pacote>        # nunca congelar este app
#     sh apply.sh wl-del <pacote>        # remove da whitelist
#     sh apply.sh bl-add <pacote>        # adiciona à lista de congelar
#     sh apply.sh bl-del <pacote>        # remove da lista de congelar
#     sh apply.sh freeze-app <pacote>    # congela 1 app agora
#     sh apply.sh unfreeze-app <pacote>  # descongela 1 app agora
#     sh apply.sh status                 # resumo
#     sh apply.sh get <CHAVE>            # lê uma config
#     sh apply.sh set <CHAVE> <valor>    # grava uma config
#     sh apply.sh restore                # = unfreeze + desliga o serviço
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

case "$1" in
    ""|status)
        _ensure_lists
        echo "=================================================="
        echo "  Pack OTM · Congelar Apps"
        echo "=================================================="
        echo "  Serviço:      $( [ -f "$STATE/stop" ] && echo PARADO || echo ATIVO )"
        echo "  Modo:         $FREEZE_MODE (suspend=Brevent-like / soft=force-stop)"
        echo "  Cache freezer:$( [ "$CACHE_FREEZER" = "1" ] && echo ligado || echo desligado )"
        echo "  Na blacklist: $(wc -l < "$BL_FILE" 2>/dev/null | tr -d ' ') apps"
        echo "  Na whitelist: $(wc -l < "$WL_FILE" 2>/dev/null | tr -d ' ') apps"
        echo "  Config:       $CFG"
        echo "--------------------------------------------------"
        echo "  Serão congelados agora:"
        for p in $(freeze_list); do
            is_installed "$p" && echo "    • $p"
        done
        echo "=================================================="
        ;;

    freeze)   n=$(freeze_all); echo "Congelados: $n app(s)." ;;
    unfreeze) unfreeze_all; echo "Todos descongelados." ;;

    list)
        _ensure_lists
        echo "== WHITELIST (nunca congelar) =="
        cat "$WL_FILE"
        echo
        echo "== BLACKLIST (congelar) =="
        cat "$BL_FILE"
        echo
        echo "== EFETIVO (blacklist - whitelist - sistema) =="
        freeze_list
        ;;

    wl-add)
        [ -z "$2" ] && { echo "uso: wl-add <pacote>"; exit 1; }
        grep -qxF "$2" "$WL_FILE" 2>/dev/null || echo "$2" >> "$WL_FILE"
        # se estava na blacklist, tira
        grep -vxF "$2" "$BL_FILE" > "$BL_FILE.tmp" 2>/dev/null && mv "$BL_FILE.tmp" "$BL_FILE"
        unfreeze_one "$2"
        echo "Whitelist += $2 (descongelado)"
        ;;

    wl-del)
        [ -z "$2" ] && { echo "uso: wl-del <pacote>"; exit 1; }
        grep -vxF "$2" "$WL_FILE" > "$WL_FILE.tmp" 2>/dev/null && mv "$WL_FILE.tmp" "$WL_FILE"
        echo "Whitelist -= $2"
        ;;

    bl-add)
        [ -z "$2" ] && { echo "uso: bl-add <pacote>"; exit 1; }
        grep -qxF "$2" "$BL_FILE" 2>/dev/null || echo "$2" >> "$BL_FILE"
        grep -vxF "$2" "$WL_FILE" > "$WL_FILE.tmp" 2>/dev/null && mv "$WL_FILE.tmp" "$WL_FILE"
        echo "Blacklist += $2"
        ;;

    bl-del)
        [ -z "$2" ] && { echo "uso: bl-del <pacote>"; exit 1; }
        grep -vxF "$2" "$BL_FILE" > "$BL_FILE.tmp" 2>/dev/null && mv "$BL_FILE.tmp" "$BL_FILE"
        echo "Blacklist -= $2"
        ;;

    freeze-app)
        [ -z "$2" ] && { echo "uso: freeze-app <pacote>"; exit 1; }
        freeze_one "$2" && echo "Congelado: $2" || echo "Não congelado (protegido?): $2"
        ;;

    unfreeze-app)
        [ -z "$2" ] && { echo "uso: unfreeze-app <pacote>"; exit 1; }
        unfreeze_one "$2"; echo "Descongelado: $2"
        ;;

    get)  eval "echo \$$2" ;;
    set)
        [ -z "$2" ] || [ -z "$3" ] && { echo "uso: set <CHAVE> <valor>"; exit 1; }
        eval "$2='$3'"; save_config; echo "$2=$3" ;;

    save) save_config; echo "salvo" ;;

    restore)
        revert
        touch "$STATE/stop" 2>/dev/null
        echo "Congelar Apps restaurado (tudo descongelado, serviço parado)."
        ;;

    *) echo "comando desconhecido: $1"; exit 1 ;;
esac
