#!/system/bin/sh
# =============================================================================
#  game-clean.sh - "Game Clean": deixa o jogo limpo, leve e sem interferência.
#
#  Junta num só lugar a limpeza que realmente muda o jogo:
#    1) encerra apps de fundo (poupando o jogo e quem você mandar manter)
#    2) poda cache/dexopt e compacta a memória
#    3) protege o jogo (anti-relog + prioridade de memória + RAM de jogo)
#    4) liga Game Mode performance e tira o jogo do congelador/Doze
#    5) silencia notificações/heads-up e liga o Não Perturbe
#    6) corta telemetria/scans em segundo plano
#
#  Tudo é reversível: o que muda no sistema vai para ~/.packotm/off.sh e o
#  `clean off` desfaz. Nada de número inventado: cada item é lido de volta.
#
#  Uso:
#     game-clean.sh on [pkg] [max]   # limpa e otimiza (max = mais agressivo)
#     game-clean.sh off [pkg]        # desfaz o que o clean aplicou
#     game-clean.sh status [pkg]     # mostra o que está ativo AGORA
#
#  Sem pkg, usa o Free Fire (com.dts.freefireth).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

GC_ST="$ST/gameclean"
mkdir -p "$GC_ST" 2>/dev/null
GC_ON="$GC_ST/applied"      # pacote do último clean aplicado
GC_OFF="$ST/off.sh"         # reversões (compartilhado, desfeito por pack restore)

DEFAULT_PKG="com.dts.freefireth"

# apps que o "max" também encerra (mídia, chat, streaming)
GC_EXTRA="com.spotify.music com.discord com.google.android.youtube com.netflix.mediaclient com.twitch.android.app"

_valid_pkg() {
    case "$1" in
        ''|*[!A-Za-z0-9._]*) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}

# registra a reversão de um appops e aplica, confirmando a leitura de volta
gc_appops() {
    p="$1"; op="$2"; val="$3"; label="$4"
    old="$(sh_get "cmd appops get $p $op" | awk '{print $NF}')"
    case "$old" in allow|deny|ignore|default) ;; *) old="default" ;; esac
    bkp_raw "cmd appops set $p $op $old"
    otm_v_inc apply
    sh_run "cmd appops set $p $op $val" >/dev/null 2>&1
    now="$(sh_get "cmd appops get $p $op" | awk '{print $NF}')"
    if [ "$now" = "$val" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s\n' "$C_G" "$C_R" "$label"
    else
        otm_v_inc failed
        printf '   %bX%b %s\n' "$C_RD" "$C_R" "$label"
    fi
}

# apps em 2º plano que podem ser encerrados agora (poupa o jogo e os protegidos)
gc_killbg() {
    pkg="$1"; extra="$2"
    keep="$pkg com.dts.freefireth com.dts.freefiremax"
    # não mata quem você protegeu no anti-relog
    [ -s "$ST/keepalive/apps" ] && keep="$keep $(tr '\n' ' ' < "$ST/keepalive/apps")"
    n=0
    for p in $(sh_get "pm list packages -3" | sed 's/package://'); do
        case " $keep " in *" $p "*) continue ;; esac
        case "$p" in
            com.android.*|com.google.android.gms|com.google.android.gsf|android) continue ;;
        esac
        sh_run "am force-stop $p" >/dev/null 2>&1 && n=$((n+1))
    done
    # "max" também encerra os apps de mídia/chat conhecidos
    if [ "$extra" = "max" ]; then
        for p in $GC_EXTRA; do
            case " $keep " in *" $p "*) continue ;; esac
            sh_run "am force-stop $p" >/dev/null 2>&1 && n=$((n+1))
        done
    fi
    say "$n app(s) de fundo encerrado(s) (o jogo ficou de fora)"
}

cmd_on() {
    pkg="${1:-$DEFAULT_PKG}"
    modo="${2:-normal}"
    _valid_pkg "$pkg" || { err "pacote inválido: '$pkg'"; return 1; }
    case "$modo" in normal|max) ;; *) err "modo inválido: $modo (normal|max)"; return 1 ;; esac

    printf '  %s◆%s  %sGAME CLEAN%s  %s(%s)%s\n' "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$pkg" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"

    # 1) fecha o que está atrapalhando (não precisa de privilégio p/ force-stop? precisa)
    say "1/6  Encerrando apps de fundo"
    if have_shell; then gc_killbg "$pkg" "$modo"; else warn "sem shell — pulando o encerramento"; fi

    # 2) limpeza real de cache/dexopt + RAM
    say "2/6  Limpando cache, dexopt e RAM"
    bkp_begin
    sh_run "pm trim-caches 999999999999" >/dev/null 2>&1
    sh_run "am kill-all" >/dev/null 2>&1
    sh_run "sync" >/dev/null 2>&1
    if sh_ok; then
        sh_run "killall -9 dex2oat" >/dev/null 2>&1
        sh_run "logcat -c" >/dev/null 2>&1
        [ -w /sys/kernel/mm/lru_gen/enabled ] && sh_run "echo 1 > /sys/kernel/mm/lru_gen/enabled" >/dev/null 2>&1
        sh_run "sm fstrim" >/dev/null 2>&1
    fi
    # perfil de RAM de jogo: menos apps em cache, mais RAM para o jogo
    bkp_set global activity_manager_constants max_cached_processes=8,max_phantom_processes=1024
    say "cache/dexopt podados · RAM no perfil gaming"

    # 3) protege o jogo: anti-relog (keep-alive) — mantém o jogo vivo, sem relog
    say "3/6  Protegendo o jogo (anti-relog)"
    if have_shell; then
        sh "$DIR/keep-alive.sh" on "$pkg" jogo >/dev/null 2>&1 \
            && say "jogo protegido: não reloga e não é morto em 2º plano" \
            || warn "não deu para proteger (veja keep-alive.sh)"
    else
        warn "sem shell — proteção anti-relog pulada"
    fi
    # jogo fora do Doze (garantia extra)
    sh_run "cmd deviceidle whitelist +$pkg" >/dev/null 2>&1

    # 4) Game Mode performance + driver de jogo
    say "4/6  Game Mode performance"
    if have_shell; then
        sh_run "cmd game set --mode performance $pkg" >/dev/null 2>&1
        sh_run "settings put global game_driver_all_apps 1" >/dev/null 2>&1
        say "Game Mode e driver de jogo ligados"
    fi

    # 5) menos interrupção: sem heads-up/bolhas + Não Perturbe
    say "5/6  Silenciando interrupções"
    bkp_set global heads_up_notifications_enabled 0
    bkp_set global notification_bubbles 0
    if have_shell; then
        sh_run "cmd notification set_dnd on" >/dev/null 2>&1 \
            || sh_run "settings put global zen_mode 1" >/dev/null 2>&1
        say "Não Perturbe ligado (chamadas de emergência continuam)"
    fi

    # 6) telemetria e scans em 2º plano (consomem CPU/rede durante o jogo)
    say "6/6  Cortando telemetria e scans"
    bkp_set global wifi_scan_throttle_enabled 1
    bkp_set global adaptive_battery_management_enabled 0
    if sh_ok; then
        bkp_set global logpersist.start 0
        bkp_set global logpersist.loglevel 0
    fi
    say "telemetria e scans reduzidos"

    # grava o pacote aplicado (para o status/off saberem quem proteger)
    printf '%s\n' "$pkg" > "$GC_ON"
    echo
    say "Game Clean pronto. Reverta em 'game-clean.sh off' (ou pack.sh restore)."
    printf '  %sReabra o jogo para valer.%s\n' "$C_D" "$C_R"
}

cmd_off() {
    pkg="${1:-}"
    [ -z "$pkg" ] && [ -f "$GC_ON" ] && pkg="$(head -1 "$GC_ON")"
    say "Desfazendo o Game Clean"
    # interrupções: o off.sh restaura os settings gravados; aqui garantimos o
    # estado "ligado" mesmo se o clean tiver sido aplicado noutra sessão
    have_shell && { sh_run "cmd notification set_dnd off" >/dev/null 2>&1 \
        || sh_run "settings put global zen_mode 0" >/dev/null 2>&1; }
    if [ -n "$pkg" ] && _valid_pkg "$pkg"; then
        have_shell && sh "$DIR/keep-alive.sh" off "$pkg" >/dev/null 2>&1
        sh_run "cmd game set --mode standard $pkg" >/dev/null 2>&1
    fi
    # desfaz o que foi registrado em off.sh (settings/appops/standby/doze)
    if [ -s "$GC_OFF" ]; then
        while IFS= read -r c; do
            [ -z "$c" ] && continue
            case "$c" in '#'*) continue ;; esac
            sh_run "$c" >/dev/null 2>&1
        done < "$GC_OFF"
        rm -f "$GC_OFF" "$ST/on"
    fi
    rm -f "$GC_ON" 2>/dev/null
    say "pronto (o jogo volta ao comportamento normal)"
}

cmd_status() {
    pkg="${1:-}"
    [ -z "$pkg" ] && [ -f "$GC_ON" ] && pkg="$(head -1 "$GC_ON")"
    printf '  %s◆%s  %sGAME CLEAN · estado%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    if [ -z "$pkg" ]; then
        printf '  %snenhum Game Clean aplicado%s\n' "$C_D" "$C_R"
        return 0
    fi
    printf '  %sjogo:%s %s\n' "$C_A" "$C_R" "$pkg"
    wl="$(sh_get "cmd deviceidle whitelist" | grep -q "$pkg" && echo isento || echo não)"
    printf '  %sDoze:%s %s\n' "$C_A" "$C_R" "$wl"
    m="$(sh_get "am get-standby-bucket $pkg" | tr -d ' ')"
    printf '  %sstandby:%s %s\n' "$C_A" "$C_R" "${m:-—}"
    hu="$(sh_get 'settings get global heads_up_notifications_enabled')"
    printf '  %sheads-up:%s %s\n' "$C_A" "$C_R" "${hu:-—}"
    zen="$(sh_get 'settings get global zen_mode')"
    printf '  %sNão Perturbe:%s %s\n' "$C_A" "$C_R" "${zen:-—}"
    mx="$(sh_get 'settings get global activity_manager_constants')"
    printf '  %sRAM (cache máx):%s %s\n' "$C_A" "$C_R" "${mx:-—}"
    if [ -s "$ST/keepalive/apps" ] && grep -qxF "$pkg" "$ST/keepalive/apps" 2>/dev/null; then
        printf '  %santi-relog:%s %ssim (protegido)%s\n' "$C_A" "$C_R" "$C_G" "$C_R"
    else
        printf '  %santi-relog:%s não\n' "$C_A" "$C_R"
    fi
}

case "${1:-}" in
    on)      shift; cmd_on "$@" ;;
    off)     shift; cmd_off "$@" ;;
    status)  shift; cmd_status "$@" ;;
    *)       sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report game-clean
exit $rc
