#!/system/bin/sh
# =============================================================================
#  ram-boost.sh - Libera RAM de verdade, agora.
#
#  Diferente de "RAM: perfil gaming" (que só muda quantos apps o sistema deixa
#  em cache), aqui a memória é liberada na hora:
#    1) encerra os apps de 3º plano (poupa o jogo e quem você protegeu no anti-relog)
#    2) poda o cache de todos os apps
#    3) mostra quanto de RAM foi liberado (lido de /proc/meminfo)
#
#  Uso:
#     ram-boost.sh boost [normal|max]   # libera agora (max = mais agressivo)
#     ram-boost.sh status               # RAM livre e quem está protegido
#
#  "max" também encerra apps de mídia/chat conhecidos (Spotify, Discord, etc.).
#  É uma ação pontual: nada fica gravado para reverter.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

RB_EXTRA="com.spotify.music com.discord com.google.android.youtube com.netflix.mediaclient com.twitch.android.app"

# quem não pode ser encerrado: o jogo, os protegidos no anti-relog e o que
# está em primeiro plano agora (nunca fechar o que o usuário está usando)
rb_keep() {
    printf 'com.dts.freefireth com.dts.freefiremax %s' "$(otm_keep_list)"
}

cmd_boost() {
    modo="${1:-normal}"
    case "$modo" in normal|max) ;; *) err "modo inválido: $modo (normal|max)"; return 1 ;; esac
    require_shell "liberar RAM" || return 1

    printf '  %s◆%s  %sLIBERAR RAM%s  %s(%s)%s\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$modo" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"

    before="$(otm_ram_livre_mb)"
    [ -n "$before" ] && say "RAM livre antes: ${before}MB"

    keep="$(rb_keep)"
    say "Encerrando apps de fundo"
    n="$(otm_bg_kill $keep)"
    say "$n app(s) de fundo encerrado(s)"
    if [ "$modo" = "max" ]; then
        m=0
        for p in $RB_EXTRA; do
            case " $keep " in *" $p "*) continue ;; esac
            sh_run "am force-stop $p" >/dev/null 2>&1 && m=$((m + 1))
        done
        say "$m app(s) de mídia/chat encerrado(s)"
    fi

    say "Podando cache dos apps"
    f="$(otm_cache_trim)"
    [ -n "$f" ] && say "cache podado: $((f / 1048576))MB liberados"

    sh_run "am kill-all" >/dev/null 2>&1
    sh_run "sync" >/dev/null 2>&1

    after="$(otm_ram_livre_mb)"
    if [ -n "$before" ] && [ -n "$after" ]; then
        say "RAM livre depois: ${after}MB (+$((after - before))MB)"
    elif [ -n "$after" ]; then
        say "RAM livre agora: ${after}MB"
    else
        warn "não consegui ler /proc/meminfo neste aparelho"
    fi
    say "pronto (o jogo e os protegidos ficaram de fora)"
}

cmd_status() {
    printf '  %s◆%s  %sRAM · estado%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    tot="$(otm_meminfo MemTotal)"; av="$(otm_meminfo MemAvailable)"
    if [ -n "$tot" ] && [ -n "$av" ]; then
        printf '  %sRAM livre:%s %sMB de %sMB (%s%% em uso)\n' "$C_A" "$C_R" \
            "$((av / 1024))" "$((tot / 1024))" "$(((tot - av) * 100 / tot))"
    else
        printf '  %sRAM:%s indisponível neste aparelho\n' "$C_A" "$C_R"
    fi
    mx="$(sh_get 'settings get global activity_manager_constants')"
    printf '  %sperfil de RAM:%s %s\n' "$C_A" "$C_R" "${mx:-—}"
    if [ -s "$ST/keepalive/apps" ]; then
        printf '  %sprotegidos (anti-relog):%s %s\n' "$C_A" "$C_R" "$(tr '\n' ' ' < "$ST/keepalive/apps")"
    else
        printf '  %sprotegidos (anti-relog):%s nenhum\n' "$C_A" "$C_R"
    fi
}

case "${1:-}" in
    boost)  shift; cmd_boost "$@" ;;
    status) cmd_status ;;
    *)      sed -n '3,18p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report ram-boost
exit $rc
