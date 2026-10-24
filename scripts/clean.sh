#!/system/bin/sh
# =============================================================================
#  clean.sh - Limpeza e suavização ("Clean") do Pack de Otimização.
#
#  Motor único de limpeza: reúne num só lugar o que estava espalhado entre
#  `adb-tweaks.sh clean`, `turbo.sh trim/killbg`, `ram-boost.sh` e `game-clean.sh`.
#
#  Em vez de "matar tudo", trabalha em FASES com o que o aparelho aguenta:
#    fundo  - só libera RAM (encerra 2º plano + poda cache). Nada persistente.
#    suave  - fundo + suavização (animações, blur, doze leve, trim,
#             rede móvel e scan Wi-Fi). Reversível.
#
#  Nada de número inventado: cada ajuste é lido de volta e contado
#  (#OTM-RESULT applies/changed/failed). O que não pega aparece como falha.
#
#  Uso:
#     clean.sh scan                 # só lê o que dá para limpar (não mexe)
#     clean.sh now [fundo|suave]   # limpa/suaviza (padrão: suave)
#     clean.sh status               # o que está ativo agora
#     clean.sh off                  # desfaz a suavização (a limpeza é pontual)
#
#  Reversão de TUDO: pack.sh restore  (ou o snapshot).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
scope_begin clean          # reversão própria: `off` não mexe no que outras ações aplicaram
otm_v_reset

CL_ST="$ST/clean"
CL_APPLIED="$CL_ST/applied"   # qual fase foi aplicada por último
mkdir -p "$CL_ST" 2>/dev/null

# app do jogo: nunca encerrar no clean (e poupar quem está no anti-relog)
CL_KEEP="com.dts.freefireth com.dts.freefiremax"

# =============================================================================
#  LEITURA (scan / status) - não altera nada
# =============================================================================

cl_ram() {
    tot="$(otm_meminfo MemTotal)"; av="$(otm_meminfo MemAvailable)"
    if [ -n "$tot" ] && [ -n "$av" ]; then
        printf '%sMB livres de %sMB (%s%% em uso)' \
            "$((av / 1024))" "$((tot / 1024))" "$(((tot - av) * 100 / tot))"
    else
        printf 'indisponível'
    fi
}

cl_disk_free() {  # espaço livre em /data, em KB
    sh_get 'df /data' | awk 'NR==2{print $4}'
}

# processos em cache (2º plano que dá para encerrar) - só conta, não mata
cl_cached_procs() {
    n="$(sh_get 'ps -A -o NAME' | grep -c . )"
    [ -n "$n" ] && echo "$n" || echo ""
}

cl_scan() {
    printf '  %s◆%s  %sCLEAN · o que dá para liberar%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %sRAM:%s %s\n' "$C_A" "$C_R" "$(cl_ram)"
    df_k="$(cl_disk_free)"
    [ -n "$df_k" ] && printf '  %sespaço livre /data:%s %sMB\n' "$C_A" "$C_R" "$((df_k / 1024))"
    cp="$(cl_cached_procs)"
    [ -n "$cp" ] && printf '  %sprocessos:%s %s\n' "$C_A" "$C_R" "$cp"

    if [ -s "$CL_APPLIED" ]; then
        printf '  %súltima fase aplicada:%s %s\n' "$C_A" "$C_R" "$(cat "$CL_APPLIED")"
    else
        printf '  %súltima fase aplicada:%s nenhuma\n' "$C_A" "$C_R"
    fi
    printf '  %sReversível:%s pack.sh restore (a limpeza em si é pontual)\n' "$C_A" "$C_R"
}

# =============================================================================
#  FASE 1 (sempre): liberar RAM de verdade - pontual, sem reverter nada
# =============================================================================
cl_free_ram() {
    say "1/2  Liberando RAM (2º plano + cache)"
    before="$(otm_ram_livre_mb)"
    [ -n "$before" ] && say "RAM livre antes: ${before}MB"

    keep="$CL_KEEP"
    [ -s "$ST/keepalive/apps" ] && keep="$keep $(tr '\n' ' ' < "$ST/keepalive/apps")"
    n="$(otm_bg_kill $keep)"
    otm_v_inc apply
    if [ "${n:-0}" -gt 0 ] 2>/dev/null; then otm_v_inc changed; else otm_v_inc failed; fi
    say "$n app(s) de fundo encerrado(s)"

    f="$(otm_cache_trim)"
    if [ -n "$f" ]; then
        otm_v_inc apply; otm_v_inc changed
        say "cache podado: $((f / 1048576))MB liberados"
    fi

    sh_run "am kill-all" >/dev/null 2>&1
    sh_run "sync" >/dev/null 2>&1   # flush de buffer (não é liberação de RAM)

    after="$(otm_ram_livre_mb)"
    if [ -n "$before" ] && [ -n "$after" ]; then
        say "RAM livre: ${before}MB → ${after}MB (+$((after - before))MB)"
    fi
}

# =============================================================================
#  FASE 2 (suave): suavização - só `settings`/`cmd`, tudo reversível
# =============================================================================
cl_smooth_noroot() {
    say "2/2  Suavização (animações, blur, doze, rede)"
    bkp_begin
    bkp_set global window_animation_scale 0
    bkp_set global transition_animation_scale 0
    bkp_set global animator_duration_scale 0
    bkp_set global disable_window_blurs 1
    bkp_set global accessibility_reduce_transparency 1
    # doze afinado: dorme mais rápido quando a tela apaga (economiza e esfria)
    bkp_set global device_idle_constants \
        "light_after_inactive_to=60000,light_pre_idle_to=60000,inactive_to=120000,sensing_to=0,locating_to=0,idle_after_idle_to_ms=60000,idle_to=300000,min_time_to_alarm=60000"
    # rede: sem scan Wi-Fi em 2º plano (menos rádio, menos calor)
    bkp_set global wifi_scan_always_enabled 0
    bkp_set global wifi_wakeup_enabled 0
}

# =============================================================================
#  AÇÕES
# =============================================================================
cmd_now() {
    fase="${1:-suave}"
    case "$fase" in fundo|suave) ;; *) err "fase inválida: $fase (fundo|suave)"; return 1 ;; esac
    require_shell "limpar" || return 1

    printf '  %s◆%s  %sCLEAN%s  %s(%s)%s\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$fase" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"

    cl_free_ram
    [ "$fase" != "fundo" ] && cl_smooth_noroot

    printf '%s\n' "$fase" > "$CL_APPLIED"
    echo
    say "Clean pronto (fase: $fase). Reverta a suavização em: clean.sh off"
}

cmd_off() {
    say "Desfazendo a suavização do Clean (a limpeza de RAM é pontual)"
    # desfaz os módulos do deep-tune.sh que ainda existem (display/debloat)
    for m in display debloat; do
        sh "$DIR/deep-tune.sh" "$m" off >/dev/null 2>&1
    done
    # desfaz SÓ os settings que o Clean guardou (escopo próprio, não toca no
    # que Performance/Fluidez/DNS aplicaram por fora)
    otm_undo_run "$OFF_SH"
    rm -f "$OFF_SH" "$MARK"
    rm -f "$CL_APPLIED" 2>/dev/null
    say "pronto (aparelho de volta ao comportamento normal)"
}

cmd_status() {
    printf '  %s◆%s  %sCLEAN · estado%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %sRAM:%s %s\n' "$C_A" "$C_R" "$(cl_ram)"
    if [ -s "$CL_APPLIED" ]; then
        printf '  %sfase aplicada:%s %s\n' "$C_A" "$C_R" "$(cat "$CL_APPLIED")"
    else
        printf '  %sfase aplicada:%s nenhuma\n' "$C_A" "$C_R"
    fi
    an="$(sh_get 'settings get global window_animation_scale')"
    printf '  %sanimações:%s %s\n' "$C_A" "$C_R" "${an:-—}"
    bl="$(sh_get 'settings get global disable_window_blurs')"
    printf '  %sblur desligado:%s %s\n' "$C_A" "$C_R" "${bl:-—}"
    dz="$(sh_get 'settings get global device_idle_constants')"
    printf '  %sdoze:%s %s\n' "$C_A" "$C_R" "${dz:-padrão}"
}

case "${1:-}" in
    scan)   cl_scan ;;
    now)    shift; cmd_now "$@" ;;
    off)    cmd_off ;;
    status) cmd_status ;;
    *)      sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report clean
exit $rc
