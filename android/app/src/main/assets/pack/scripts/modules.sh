#!/system/bin/sh
# =============================================================================
#  modules.sh - Lista e EXECUTA os módulos e plugins que já vêm na pasta.
#
#  Uso: sh scripts/modules.sh <list|status|run|actions|action|info|menu> [...]
#
#  Módulos (00 Otimizações/Modulos/): Magisk/KernelSU/APatch/AxManager.
#  Plugins (00 Otimizações/Plugins AxManager/): AxManager (Nossos + OSS).
#
#  O que dá para fazer aqui (sem instalar nada pelo gerenciador):
#    list              lista módulos e plugins encontrados
#    info <nome>       mostra os scripts (action/service/uninstall/apply…)
#    run <nome> [alvo] executa a ação principal do módulo
#                      (action.sh, ou apply.sh nos plugins)
#    actions <nome>    lista os scripts executáveis do módulo
#    action <nome> <script>   executa um script específico do módulo
#
#  Observação honesta: `run` executa o script avulso no shell atual. O fluxo
#  completo (rodar em segundo plano, boot, WebUI) exige INSTALAR o módulo no
#  gerenciador (Magisk/KernelSU/APatch/AxManager) — veja a seção Módulos do site.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
. "$DIR/common.sh"

MODDIR="$ROOT/00 Otimizações/Modulos"
PLUGDIR="$ROOT/00 Otimizações/Plugins AxManager"

# --- descoberta ---------------------------------------------------------------
# cada módulo/plugin tem module.prop; plugins têm apply.sh
mod_list() {
    for base in "$MODDIR" "$PLUGDIR"; do
        [ -d "$base" ] || continue
        find "$base" -name module.prop 2>/dev/null | sort | while read -r prop; do
            d="$(dirname "$prop")"
            n="$(basename "$d")"
            grupo="$(basename "$(dirname "$d")")"
            printf '%s\t%s\t%s\n' "$n" "$grupo" "$d"
        done
    done
}

mod_dir() {  # mod_dir <nome> -> caminho (match exato do basename)
    mod_list | while IFS="$(printf '\t')" read -r n g d; do
        [ "$n" = "$1" ] && { printf '%s' "$d"; break; }
    done
}

# imprime: script<TAB>descrição
mod_scripts() {  # mod_scripts <dir>
    d="$1"
    for s in action.sh apply.sh customize.sh service.sh uninstall.sh restore.sh; do
        [ -f "$d/$s" ] && printf '%s\t%s\n' "$s" "$(case "$s" in
            action.sh)    echo "ação principal (botão de ação)" ;;
            apply.sh)     echo "aplicar o módulo agora" ;;
            customize.sh) echo "instalação (roda no gerenciador)" ;;
            service.sh)   echo "serviço em segundo plano (boot)" ;;
            uninstall.sh) echo "remover / reverter" ;;
            restore.sh)   echo "restaurar valores" ;;
        esac)"
    done
    return 0
}

# --- execução -----------------------------------------------------------------
mod_run() {  # mod_run <nome>
    d="$(mod_dir "$1")"
    [ -z "$d" ] && { err "não achei o módulo '$1' (veja: modules.sh list)"; return 1; }
    if [ -f "$d/apply.sh" ]; then
        say "executando $1/apply.sh"
        ( cd "$d" && sh ./apply.sh )
    elif [ -f "$d/action.sh" ]; then
        say "executando $1/action.sh"
        ( cd "$d" && sh ./action.sh )
    elif [ -f "$d/service.sh" ]; then
        warn "$1 só tem service.sh (feito p/ rodar no boot). Rodando uma vez…"
        ( cd "$d" && sh ./service.sh )
    else
        err "$1 não tem script executável (só instala pelo gerenciador)"
        return 1
    fi
}

mod_action() {  # mod_action <nome> <script>
    d="$(mod_dir "$1")"
    [ -z "$d" ] && { err "não achei o módulo '$1'"; return 1; }
    s="$2"
    case "$s" in */*|.*) err "nome de script inválido"; return 1 ;; esac
    [ -f "$d/$s" ] || { err "'$1' não tem $s (veja: modules.sh actions $1)"; return 1; }
    say "executando $1/$s"
    ( cd "$d" && sh "./$s" )
}

# --- relatórios ---------------------------------------------------------------
mod_info() {
    d="$(mod_dir "$1")"
    [ -z "$d" ] && { err "não achei o módulo '$1'"; return 1; }
    printf '  %s%s%s  %s(%s)%s\n' "$C_A" "$1" "$C_R" "$C_D" "$(basename "$(dirname "$d")")" "$C_R"
    [ -f "$d/module.prop" ] && sed -n 's/^\(version\|author\|description\)=/\1: /p' "$d/module.prop" | sed 's/^/    /'
    printf '    %spasta:%s %s\n' "$C_D" "$C_R" "${d#$ROOT/}"
    printf '    %sscripts:%s\n' "$C_A" "$C_R"
    mod_scripts "$d" | while IFS="$(printf '\t')" read -r s desc; do
        printf '      %-14s %s\n' "$s" "$desc"
    done
    printf '\n    %sexecutar:%s sh scripts/modules.sh run %s\n' "$C_A" "$C_R" "$1"
}

mod_list_show() {
    printf '  %s◆%s  %sMÓDULOS E PLUGINS NA PASTA%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    for base in "$MODDIR" "$PLUGDIR"; do
        [ -d "$base" ] || continue
        find "$base" -name module.prop 2>/dev/null | sort | while read -r prop; do
            d="$(dirname "$prop")"; n="$(basename "$d")"
            printf '   %s%-24s%s %s\n' "$C_G" "$n" "$C_R" "$(basename "$(dirname "$d")")"
        done
    done
    printf '\n  %sexecutar:%s sh scripts/modules.sh run <nome>\n' "$C_A" "$C_R"
    printf '  %satalho:%s sh pack.sh modules run <nome>\n' "$C_A" "$C_R"
}

# --- submenu interativo -------------------------------------------------------
mod_menu() {
    while :; do
        printf '\n  %s◆%s  %sMÓDULOS / PLUGINS%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
        i=0
        mod_list | while IFS="$(printf '\t')" read -r n g d; do
            i=$((i + 1))
            printf '   %s%2d%s  %-24s %s\n' "$C_A" "$i" "$C_R" "$n" "$g"
        done
        printf '\n   %svoltar%s sai · %slist%s só lista\n' "$C_D" "$C_R" "$C_A" "$C_R"
        printf '  %s›%s (número para executar) ' "$C_A" "$C_R"
        read -r op || { printf '\n'; return 0; }
        case "$op" in
            voltar|q|"") return 0 ;;
            list) mod_list_show ;;
            ''|*[!0-9]*) warn "opção inválida" ;;
            *)
                nome="$(mod_list | sed -n "${op}p" | cut -f1)"
                if [ -n "$nome" ]; then
                    mod_info "$nome"
                    printf '  %senter para executar%s' "$C_D" "$C_R"; read -r _
                    mod_run "$nome"
                else warn "opção inválida"; fi ;;
        esac
    done
}

# --- main ---------------------------------------------------------------------
case "${1:-list}" in
    menu)     mod_menu ;;
    list)     mod_list_show ;;
    info)     mod_info "$2" ;;
    actions)  d="$(mod_dir "$2")"; [ -n "$d" ] && mod_scripts "$d" || err "não achei '$2'" ;;
    run)      [ -n "$2" ] && mod_run "$2" || { err "faltou o nome"; exit 1; } ;;
    action)   [ -n "$2" ] && [ -n "$3" ] && mod_action "$2" "$3" || { err "uso: modules.sh action <nome> <script>"; exit 1; } ;;
    *) printf '  uso: modules.sh list | info <nome> | actions <nome> | run <nome> | action <nome> <script> | menu\n' ;;
esac
