#!/system/bin/sh
# =============================================================================
#  dns.sh - Perfis de DNS privado (DNS-over-TLS) e ajuste de latência/conexão.
#
#  Uso: sh scripts/dns.sh <perfil|status|list|off|custom <host>|menu>
#
#  Perfis prontos (só trocam o DNS privado do sistema, sem root):
#    cloudflare         privacidade + velocidade
#    quad9              privacidade + bloqueio de malware
#    adguard            bloqueio de anúncios e rastreadores
#    adguard-family     anúncios + conteúdo adulto
#    cloudflare-family  família (conteúdo adulto)
#    mullvad            privacidade (sem registro)
#    dnsforge           bloqueio de anúncios (sem log)
#    google             compatibilidade máxima
#    gaming             baixa latência p/ jogos (+ buffers TCP + scan off)
#    custom <host>      use qualquer hostname DoT
#    off / auto         volta o DNS automático (padrão)
#
#  Tudo reversível: os valores antigos vão para ~/.packotm/off.sh.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

# --- catálogo de perfis -------------------------------------------------------
# imprime: nome<TAB>host<TAB>descrição
dns_profiles() {
    printf '%s\t%s\t%s\n' \
        cloudflare        "1dot1dot1dot1.cloudflare-dns.com" "Privacidade + velocidade (sem registro)" \
        quad9             "dns.quad9.net"                    "Privacidade + bloqueio de malware" \
        adguard           "dns.adguard-dns.com"              "Bloqueio de anúncios e rastreadores" \
        adguard-family    "family.adguard-dns.com"           "Anúncios + conteúdo adulto" \
        cloudflare-family "family.cloudflare-dns.com"        "Família (bloqueia conteúdo adulto)" \
        mullvad           "dns.mullvad.net"                  "Privacidade (sem registro)" \
        dnsforge          "dnsforge.de"                      "Bloqueio de anúncios (sem log)" \
        google            "dns.google"                       "Compatibilidade máxima" \
        nextdns           "dns.nextdns.io"                    "Filtragem e privacidade (NextDNS)" \
        gaming            "1dot1dot1dot1.cloudflare-dns.com" "Baixa latência p/ jogos (+ TCP + scan off)"
}

dns_host() {  # dns_host <perfil> -> hostname DoT (ou nada)
    dns_profiles | while IFS="$(printf '\t')" read -r n h d; do
        [ "$n" = "$1" ] && { printf '%s' "$h"; break; }
    done
}

dns_desc() {
    dns_profiles | while IFS="$(printf '\t')" read -r n h d; do
        [ "$n" = "$1" ] && { printf '%s' "$d"; break; }
    done
}

# --- aplicação -----------------------------------------------------------------
dns_apply() {  # dns_apply <perfil|hostname>
    prof="$1"
    host="$(dns_host "$prof")"
    [ -z "$host" ] && host="$prof"     # se não for perfil, trata como hostname

    bkp_begin
    bkp_set global private_dns_mode hostname
    bkp_set global private_dns_specifier "$host"

    case "$prof" in
        gaming)
            # latência/conexão: buffers TCP maiores + varredura de Wi-Fi off
            bkp_set global wifi_scan_always_enabled 0
            if [ "$RUN_MODE" = "adb" ] || [ "$RUN_MODE" = "su" ] || [ "$RUN_MODE" = "rish" ]; then
                sh_run "setprop net.tcp.buffersize.default 4096,87380,524288,4096,16384,110208" >/dev/null
                sh_run "setprop net.tcp.buffersize.wifi 524288,1048576,2097152,262144,524288,1048576" >/dev/null
                sh_run "setprop net.tcp.buffersize.lte 524288,1048576,2097152,262144,524288,1048576" >/dev/null
            fi
            say "DNS gaming ($host) + buffers TCP + Wi-Fi scan off" ;;
        *)
            say "DNS privado: $host"
            [ -n "$(dns_desc "$prof")" ] && printf '  %s%s%s\n' "$C_D" "$(dns_desc "$prof")" "$C_R" ;;
    esac
    printf '  %sreverter:%s sh scripts/dns.sh off\n' "$C_A" "$C_R"
}

dns_off() {
    bkp_begin
    bkp_set global private_dns_mode opportunistic
    sh_run "settings delete global private_dns_specifier" >/dev/null
    say "DNS automático (padrão) restaurado"
}

dns_status() {
    mode="$(sh_get 'settings get global private_dns_mode')"
    host="$(sh_get 'settings get global private_dns_specifier')"
    [ -z "$mode" ] || [ "$mode" = "null" ] && mode="(padrão: opportunistic)"
    [ -z "$host" ] || [ "$host" = "null" ] && host="(nenhum)"
    printf '  %smodo:%s %s\n' "$C_A" "$C_R" "$mode"
    printf '  %shost:%s %s\n' "$C_A" "$C_R" "$host"
    for p in $(dns_profiles | cut -f1); do
        [ "$host" = "$(dns_host "$p")" ] && { printf '  %sperfil:%s %s (%s)\n' "$C_G" "$C_R" "$p" "$(dns_desc "$p")"; return 0; }
    done
    return 0
}

dns_list() {
    printf '  %sPerfis de DNS (privado / DoT)%s\n\n' "$C_A" "$C_R"
    dns_profiles | while IFS="$(printf '\t')" read -r n h d; do
        printf '   %s%-18s%s %s\n' "$C_G" "$n" "$C_R" "$d"
        printf '   %s%-18s%s %s\n' "$C_D" "" "$C_R" "$h"
    done
    printf '\n  %soff/auto%s volta o DNS automático · %scustom <host>%s usa o seu\n' "$C_A" "$C_R" "$C_A" "$C_R"
}

# --- benchmark de latência ----------------------------------------------------
# Testa a latência de cada perfil (não altera nada). Usa ping/curl se existirem.
dns_bench() {
    printf '  %sBenchmark de DNS (latência, menor = melhor)%s\n\n' "$C_A" "$C_R"
    have_ping=0; have_curl=0
    command -v ping >/dev/null 2>&1 && have_ping=1
    command -v curl >/dev/null 2>&1 && have_curl=1
    [ "$have_ping" = 0 ] && [ "$have_curl" = 0 ] && {
        warn "sem ping nem curl disponíveis para medir"; return 0; }
    dns_profiles | while IFS="$(printf '\t')" read -r n h d; do
        ms=""
        if [ "$have_ping" = 1 ]; then
            r="$(sh_get "ping -c 2 -W 2 $h" 2>/dev/null | sed -n 's#.*= [0-9.]*/\([0-9.]*\)/.*#\1#p')"
            [ -n "$r" ] && ms="$r ms"
        fi
        if [ -z "$ms" ] && [ "$have_curl" = 1 ]; then
            t="$(sh_get "curl -o /dev/null -s -w '%{time_total}' --connect-timeout 3 https://$h" 2>/dev/null)"
            [ -n "$t" ] && ms="${t}s (https)"
        fi
        printf '   %s%-18s%s %-34s %s\n' "$C_G" "$n" "$C_R" "$h" "${ms:-(sem resposta)}"
    done
    printf '\n  %sDica:%s o mais rápido costuma ser o melhor; teste no Wi-Fi E nos dados.\n' "$C_A" "$C_R"
}

# --- submenu interativo -------------------------------------------------------
dns_menu() {
    while :; do
        printf '\n  %s◆%s  %sDNS / REDE%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
        printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
        i=0
        dns_profiles | while IFS="$(printf '\t')" read -r n h d; do
            i=$((i + 1))
            printf '   %s%2d%s  %-18s %s\n' "$C_A" "$i" "$C_R" "$n" "$d"
        done
        printf '   %s%2d%s  %-18s %s\n' "$C_A" "10" "$C_R" "custom" "usar um hostname DoT seu"
        printf '   %s%2d%s  %-18s %s\n' "$C_A" "0" "$C_R" "off/auto" "voltar ao DNS automático"
        printf '\n   %sstatus%s ver o DNS atual   %svoltar%s sai do submenu\n' "$C_A" "$C_R" "$C_D" "$C_R"
        printf '  %s›%s ' "$C_A" "$C_R"
        read -r op || { printf '\n'; return 0; }
        case "$op" in
            0|off|auto) dns_off ;;
            10|custom)  printf '  hostname DoT (ex: dns.exemplo.com): '; read -r h
                        [ -n "$h" ] && dns_apply "$h" || warn "vazio, nada feito" ;;
            status)     dns_status ;;
            voltar|voltar*|q) return 0 ;;
            ''|*[!0-9]*) warn "opção inválida" ;;
            *)
                nome="$(dns_profiles | sed -n "${op}p" | cut -f1)"
                [ -n "$nome" ] && dns_apply "$nome" || warn "opção inválida" ;;
        esac
    done
}

# --- main ---------------------------------------------------------------------
case "${1:-status}" in
    menu)              dns_menu ;;
    list|perfis)       dns_list ;;
    bench|latencia)    dns_bench ;;
    status)            dns_status ;;
    off|auto|reset)    dns_off ;;
    custom)            [ -n "$2" ] && dns_apply "$2" || { err "faltou o hostname"; exit 1; } ;;
    "")                dns_status ;;
    *)
        if [ -n "$(dns_host "$1")" ]; then dns_apply "$1"
        else err "perfil desconhecido: $1"; printf '  veja: sh scripts/dns.sh list\n'; exit 1; fi ;;
esac

rc=$?
otm_v_report dns
exit $rc
