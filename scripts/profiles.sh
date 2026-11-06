#!/system/bin/sh
# =============================================================================
#  profiles.sh - Modos prontos, REAIS e com desligar por modo.
#
#  Cada modo é um conjunto de ajustes que o pack JÁ sabe aplicar. Este script
#  não reimplementa nada: ele chama os mesmos comandos das abas (adb-tweaks.sh,
#  turbo.sh, deep-tune.sh...) e faz os três trabalhos que faltavam:
#
#    1) aplica o conjunto INTEIRO que o cartão promete (antes o botão do painel
#       rodava só uma linha: "Modo Batata" era um clean, "Econômico" era só
#       trocar o Hz, "Ultra Fluido" era só a taxa de tela);
#    2) registra tudo num ESCOPO PRÓPRIO do modo (via OTM_SCOPE_OVERRIDE), para
#       poder desfazer só aquele modo;
#    3) `off` devolve SÓ o que aquele modo mexeu — sem tocar no resto. Antes só
#       existia o "Reverter TUDO", que apagava todos os modos de uma vez.
#
#  O escopo do modo fica em $UNDO_DIR/profile-<modo>.sh, o mesmo diretório dos
#  outros escopos: por isso o "Reverter TUDO" (pack.sh restore) também alcança
#  o modo, sem precisar de caso especial.
#
#  Uso:
#     profiles.sh list                 # modos e o que está ativo
#     profiles.sh status               # modo aplicado por último
#     profiles.sh apply <modo> [pkg]   # aplica um modo (e desfaz o anterior)
#     profiles.sh off <modo>           # desfaz SÓ aquele modo
#     profiles.sh off                  # desfaz o modo ativo
#     profiles.sh restore              # desfaz todos os modos
#
#  Modos: batata | competitivo | fluido | economico
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

PR_ST="$ST/profiles"
mkdir -p "$PR_ST" 2>/dev/null
PR_LAST="$PR_ST/last"     # modo aplicado por último (para `off` sem argumento)

PR_A=0; PR_C=0; PR_F=0

pr_mode_scope() { printf 'profile-%s' "$1"; }

pr_mode_name() {
    case "$1" in
        batata)      echo "Modo Batata (2-4GB RAM)" ;;
        competitivo) echo "Modo Competitivo (jogo)" ;;
        fluido)      echo "Modo 90/120Hz Ultra Fluido" ;;
        economico)   echo "Modo Economico (bateria)" ;;
        *)           echo "" ;;
    esac
}

# roda um script do pack somando as contagens reais (#OTM-RESULT).
pr_run() {
    _s="$1"; shift
    _o="$(OTM_NO_COLOR=1 sh "$DIR/$_s" "$@" 2>&1)"
    _rc=$?
    printf '%s\n' "$_o" | grep -v '^#OTM-RESULT'
    _l="$(printf '%s\n' "$_o" | grep '^#OTM-RESULT' | tail -1)"
    [ -n "$_l" ] || return $_rc
    for _t in $(printf '%s' "$_l" | sed 's/^#OTM-RESULT //'); do
        case "$_t" in
            applies=*) PR_A=$((PR_A + ${_t#applies=})) ;;
            changed=*) PR_C=$((PR_C + ${_t#changed=})) ;;
            failed=*)  PR_F=$((PR_F + ${_t#failed=})) ;;
        esac
    done
    return $_rc
}

# fixa o escopo do modo para TODOS os scripts chamados daqui para baixo, para a
# reversão inteira cair num arquivo só. O export atravessa os `sh script.sh`.
pr_scope_on()  { OTM_SCOPE_OVERRIDE="$(pr_mode_scope "$1")"; export OTM_SCOPE_OVERRIDE; }
pr_scope_off() { unset OTM_SCOPE_OVERRIDE; }

# desfaz o escopo de um modo (roda as reversões e limpa o arquivo/marcador).
# Nomes de variável com "_" para NÃO colidir com o `m` do pr_apply: em sh não
# existe `local`, então reusar `m` aqui sobrescrevia o modo que o chamador estava
# aplicando (a troca de modo caía no escopo errado).
pr_undo_scope() {
    _m="$1"; _sc="$(pr_mode_scope "$_m")"
    _f="$UNDO_DIR/$_sc.sh"
    if [ -s "$_f" ]; then
        otm_undo_run "$_f"
    else
        warn "nada para desfazer no modo '$_m'"
    fi
    rm -f "$_f" "$UNDO_DIR/$_sc.on" 2>/dev/null
}

# --- definição dos modos -------------------------------------------------------
# Cada bloco só chama o que o cartão promete. A ordem segue a dos outros scripts
# (rede depois de animações, limpeza por último, jogo por último para o
# anti-relog não ser desfeito pelo congelador).

pr_apply_batata() {
    say "Modo Batata: animacoes 0, 1-2 apps em 2o plano"
    pr_run adb-tweaks.sh perf_max          # animações 0 + GPU + blur off
    pr_run adb-tweaks.sh mem batata        # poucos apps em cache + libera RAM
    pr_run adb-tweaks.sh proc_limit 2      # no máximo 2 apps em 2º plano
    pr_run adb-tweaks.sh obscure           # menos kills, jogo fora do Doze
    pr_run turbo.sh dexopt-bg              # agenda a recompilação (dexopt)
    pr_run clean.sh now suave              # libera o que sobrou
}

pr_apply_competitivo() {
    pkg="$1"
    say "Modo Competitivo: driver de jogo, anti-relog, 4 apps, DND, sensi${pkg:+ ($pkg)}"
    pr_run adb-tweaks.sh gpu                 # driver de jogo para todos os apps
    pr_run adb-tweaks.sh dnd                 # não perturbe (sem alarmes)
    pr_run adb-tweaks.sh game_focus          # foco de jogo (DND extremo)
    pr_run adb-tweaks.sh touch_latency 100 200 0 0   # latência de toque forte
    pr_run ff-touch.sh speed                 # perfil de toque "speed"
    # game_open já aplica o anti-relog (bateria sem restrição, 4 apps em 2º
    # plano, balde ativo) e abre o jogo. Sem pacote, usa o último salvo.
    pr_run adb-tweaks.sh game_open "$pkg"
}

pr_apply_fluido() {
    say "Modo Ultra Fluido: Hz no pico, speed-profile, buffer de log mínimo, térmico"
    pr_run turbo.sh refresh max            # taxa de atualização no pico
    pr_run adb-tweaks.sh fluidez           # animações 0 + Hz + toque
    pr_run adb-tweaks.sh gpu               # GPU na interface + driver do jogo
    pr_run turbo.sh telemetry off          # menos log/telemetria em 2º plano
    pr_run adb-tweaks.sh thermal_guard on  # trava térmica preventiva
    pr_run adb-tweaks.sh mem gaming        # mais RAM livre
    pr_run turbo.sh art-all speed-profile  # compila os apps (abre mais rápido)
}

pr_apply_economico() {
    say "Modo Econômico: 60Hz, economia de energia, Doze rápido, menos 2º plano"
    pr_run turbo.sh refresh_fixed 60       # 60Hz estável
    pr_run adb-tweaks.sh battery           # economia de energia ligada
    pr_run adb-tweaks.sh doze on           # sono profundo rápido
    pr_run adb-tweaks.sh wifi              # Wi-Fi sem economia/scan
    pr_run adb-tweaks.sh proc_limit 8      # menos apps em 2º plano
    pr_run turbo.sh telemetry off          # corta log/telemetria
}

pr_apply() {
    m="$1"; pkg="$2"
    case "$m" in
        batata|competitivo|fluido|economico) ;;
        *) err "modo inválido: '$m' (use: batata|competitivo|fluido|economico)"; return 1 ;;
    esac

    # desfaz o modo anterior antes de aplicar (um modo por vez)
    prev="$(cat "$PR_LAST" 2>/dev/null)"
    if [ -n "$prev" ] && [ "$prev" != "$m" ]; then
        say "Desfazendo o modo anterior ($prev)"
        pr_undo_scope "$prev"
    fi

    pr_scope_on "$m"
    printf '#!/system/bin/sh\n' > "$UNDO_DIR/$(pr_mode_scope "$m").sh" 2>/dev/null
    case "$m" in
        batata)      pr_apply_batata ;;
        competitivo) pr_apply_competitivo "$pkg" ;;
        fluido)      pr_apply_fluido ;;
        economico)   pr_apply_economico ;;
    esac
    pr_scope_off

    printf '%s\n' "$m" > "$PR_LAST" 2>/dev/null
    say "Modo aplicado: $(pr_mode_name "$m")"
    say "Desative quando quiser: profiles.sh off $m"
    return 0
}

pr_off() {
    m="$1"
    [ -n "$m" ] || m="$(cat "$PR_LAST" 2>/dev/null)"
    if [ -z "$m" ]; then
        warn "nenhum modo ativo para desfazer"
        return 0
    fi
    say "Desfazendo: $(pr_mode_name "$m")"
    pr_undo_scope "$m"
    cur="$(cat "$PR_LAST" 2>/dev/null)"
    [ "$cur" = "$m" ] && rm -f "$PR_LAST" 2>/dev/null
    say "aparelho de volta ao estado anterior a este modo"
    return 0
}

pr_restore() {
    say "Desfazendo todos os modos"
    for m in batata competitivo fluido economico; do
        [ -s "$UNDO_DIR/$(pr_mode_scope "$m").sh" ] && pr_undo_scope "$m"
    done
    rm -f "$PR_LAST" 2>/dev/null
    say "todos os modos desfeitos"
    return 0
}

pr_status() {
    cur="$(cat "$PR_LAST" 2>/dev/null)"
    say "Modos prontos"
    printf '   %smodo ativo:%s %s\n' "$C_A" "$C_R" "${cur:-nenhum}"
    for m in batata competitivo fluido economico; do
        mk="  "; [ -s "$UNDO_DIR/$(pr_mode_scope "$m").sh" ] && mk="* "
        printf '   %s%s%-12s%s %s\n' "$C_A" "$mk" "$m" "$C_R" "$(pr_mode_name "$m")"
    done
    printf '\n   %saplicar:%s profiles.sh apply <modo> [pkg]\n' "$C_A" "$C_R"
    printf '   %sdesfazer:%s profiles.sh off [modo]\n' "$C_A" "$C_R"
}

pr_list() { pr_status; }

# =============================================================================
#  RUNNER
# =============================================================================
acao="${1:-status}"; [ $# -gt 0 ] && shift

case "$acao" in
    apply|on)  pr_apply "$@" ;;
    off|desligar) pr_off "$1" ;;
    restore|off-all) pr_restore ;;
    status|list|'') pr_status ;;
    *) err "uso: profiles.sh <list|status|apply <modo> [pkg]|off [modo]|restore>"; exit 1 ;;
esac
rc=$?

OTM_V_APPLIES=$PR_A; OTM_V_CHANGED=$PR_C; OTM_V_FAILED=$PR_F
otm_v_report "profiles:$acao"
exit $rc
