#!/system/bin/sh
# =============================================================================
#  debloat.sh - Remove/restringe bloatware sem root (nível ADB/Shizuku).
#  Uso: sh scripts/debloat.sh <on|off|status|list|disable|enable|uninstall|restore>
#
#  O que faz:
#    on [perfil]   aplica um perfil (leve|medio|pesado): desativa apps de
#                  fabricante e restringe o resto (appops + standby bucket)
#    off           reverte TUDO que este módulo aplicou (enable + appops allow)
#    status        mostra o que está aplicado agora
#    list          lista apps de usuário (-3) e de sistema (-s)
#    disable <pkg>   desativa um app (pm disable-user --user 0)
#    enable  <pkg>   reativa um app
#    uninstall <pkg> remove o app do usuário atual (reversível com restore)
#    restore <pkg>   traz de volta um app removido (install-existing)
#    restrict <pkg>  corta o plano de fundo (appops ignore + standby restricted)
#    unrestrict <pkg> devolve o plano de fundo (appops allow + standby active)
#
#  Nada é apagado de verdade: disable-user e uninstall --user 0 são reversíveis.
#  Estado em ~/.packotm/debloat/ (nunca versionado).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

ST2="${HOME:-/data/data/com.termux/files/home}/.packotm/debloat"
mkdir -p "$ST2" 2>/dev/null
D_OFF="$ST2/off.sh"      # comandos de reversão do que este script aplicou
D_ON="$ST2/applied"      # marcador

# --- perfis -------------------------------------------------------------------
# "fabricante" = gerenciadores de jogo/telemetria que costumam atrapalhar.
# Desativar de fábrica sem saber quebra sistema; por isso só os do fabricante
# entram no disable e o resto vai para appops/standby (reversível e seguro).
FW_SAMSUNG="com.samsung.android.game.gos com.samsung.android.kgclient"
FW_XIAOMI="com.xiaomi.joyose com.miui.analytics com.miui.msa.global"
FW_MOTO="com.motorola.gamemode com.motorola.genie"
FW_GENERIC="com.google.android.apps.turbo com.google.android.gms.location.history"

SOCIAL="com.facebook.katana com.facebook.orca com.instagram.android \
com.ss.android.ugc.trill com.ss.android.ugc.aweme com.twitter.android \
com.snapchat.android com.linkedin.android"
STREAM="com.netflix.mediaclient com.spotify.music com.amazon.avod.thirdpartyclient \
com.disney.disneyplus com.hbo.hbonow"
EXTRAS="com.aliexpress.buyer com.shopee.br com.mercadolibre com.ubercab com.ifood"

profile_pkgs() {  # profile_pkgs <leve|medio|pesado> -> imprime os pacotes de usuário
    case "$1" in
        leve)   echo "$SOCIAL" ;;
        medio)  echo "$SOCIAL $STREAM" ;;
        pesado) echo "$SOCIAL $STREAM $EXTRAS" ;;
        *)      return 1 ;;
    esac
}

fw_pkgs() { echo "$FW_SAMSUNG $FW_XIAOMI $FW_MOTO $FW_GENERIC"; }

# --- classificação de risco ---------------------------------------------------
# SAFE: apps de usuário/loja — desativar não quebra o sistema.
# CAUTION: gerenciadores de fabricante — costumam ser seguros, mas variam por marca.
# DANGEROUS: apps de sistema essenciais — o pack NUNCA toca neles.
risk_of() {  # risk_of <pkg> -> SAFE|CAUTION|DANGEROUS
    case "$1" in
        com.android.*|com.google.android.gms|com.google.android.gsf|android|com.qualcomm.*|com.mediatek.*)
            echo DANGEROUS ;;
        com.samsung.*|com.xiaomi.*|com.miui.*|com.motorola.*|com.oneplus.*|com.oppo.*|com.vivo.*|com.realme.*|com.huawei.*|com.transsion.*)
            echo CAUTION ;;
        *) echo SAFE ;;
    esac
}

risk_label() {
    case "$1" in
        SAFE)      printf '%bSAFE%b' "$C_G" "$C_R" ;;
        CAUTION)   printf '%bCAUTION%b' "$C_Y" "$C_R" ;;
        DANGEROUS) printf '%bDANGER%b' "$C_RD" "$C_R" ;;
        *)         printf '%s' "$1" ;;
    esac
}

# preview <perfil>: mostra o que o perfil faria, com o risco de cada app. Nada muda.
debloat_preview() {
    prof="${1:-medio}"
    case "$prof" in leve|medio|pesado) ;; *) err "perfil inválido: $prof (leve|medio|pesado)"; return 1 ;; esac
    printf '  %sPrévia do debloat — perfil %s%s (nada foi alterado)\n\n' "$C_A" "$prof" "$C_R"
    printf '  %sDesativar (disable-user) — reversível%s\n' "$C_A" "$C_R"
    for p in $(fw_pkgs); do
        printf '   %s  %-42s %s\n' "$(risk_label "$(risk_of "$p")")" "$p" ""
    done
    printf '\n  %sRestringir em 2º plano (appops + standby)%s\n' "$C_A" "$C_R"
    for p in $(profile_pkgs "$prof"); do
        printf '   %s  %s\n' "$(risk_label "$(risk_of "$p")")" "$p"
    done
    printf '\n  %sLegenda:%s SAFE pode desativar · CAUTION pode quebrar algo · DANGER não mexa\n' "$C_A" "$C_R"
    printf '  %sReverter sempre:%s sh scripts/debloat.sh off\n' "$C_A" "$C_R"
}

# --- estado -------------------------------------------------------------------
d_record() { printf '%s\n' "$1" >> "$D_OFF"; }

d_applied() { [ -f "$D_ON" ]; }

# --- ações por app ------------------------------------------------------------
disable_app() {
    p="$1"; [ -n "$p" ] || { err "uso: disable <pacote>"; return 1; }
    sh_run "pm disable-user --user 0 $p" >/dev/null
    d_record "pm enable --user 0 $p"
    say "desativado: $p"
}

enable_app() {
    p="$1"; [ -n "$p" ] || { err "uso: enable <pacote>"; return 1; }
    sh_run "pm enable --user 0 $p" >/dev/null
    say "reativado: $p"
}

uninstall_app() {
    p="$1"; [ -n "$p" ] || { err "uso: uninstall <pacote>"; return 1; }
    sh_run "pm uninstall -k --user 0 $p" >/dev/null
    d_record "cmd package install-existing $p"
    say "removido do usuário atual: $p"
}

restore_app() {
    p="$1"; [ -n "$p" ] || { err "uso: restore <pacote>"; return 1; }
    sh_run "cmd package install-existing $p" >/dev/null
    say "trazido de volta: $p"
}

restrict_app() {
    p="$1"; [ -n "$p" ] || { err "uso: restrict <pacote>"; return 1; }
    sh_run "cmd appops set $p RUN_IN_BACKGROUND ignore" >/dev/null
    sh_run "cmd appops set $p RUN_ANY_IN_BACKGROUND ignore" >/dev/null
    sh_run "am set-standby-bucket $p restricted" >/dev/null
    d_record "cmd appops set $p RUN_IN_BACKGROUND allow"
    d_record "cmd appops set $p RUN_ANY_IN_BACKGROUND allow"
    d_record "am set-standby-bucket $p active"
    say "restringido: $p"
}

unrestrict_app() {
    p="$1"; [ -n "$p" ] || { err "uso: unrestrict <pacote>"; return 1; }
    sh_run "cmd appops set $p RUN_IN_BACKGROUND allow" >/dev/null
    sh_run "cmd appops set $p RUN_ANY_IN_BACKGROUND allow" >/dev/null
    sh_run "am set-standby-bucket $p active" >/dev/null
    say "liberado: $p"
}

# --- perfis -------------------------------------------------------------------
debloat_on() {
    prof="${1:-medio}"
    case "$prof" in leve|medio|pesado) ;; *) err "perfil inválido: $prof (leve|medio|pesado)"; return 1 ;; esac
    d_applied && warn "já havia debloat aplicado; reaplicando por cima."
    say "aplicando debloat ($prof)"
    # 1) desativa gerenciadores de fabricante (reversível)
    for p in $(fw_pkgs); do
        sh_run "pm disable-user --user 0 $p" >/dev/null 2>&1
        d_record "pm enable --user 0 $p"
    done
    say "gerenciadores de fabricante desativados"
    # 2) restringe o resto (appops + standby): não roda sozinho, mas não some
    for p in $(profile_pkgs "$prof"); do
        sh_run "cmd appops set $p RUN_IN_BACKGROUND ignore" >/dev/null 2>&1
        sh_run "cmd appops set $p RUN_ANY_IN_BACKGROUND ignore" >/dev/null 2>&1
        sh_run "am set-standby-bucket $p restricted" >/dev/null 2>&1
        d_record "cmd appops set $p RUN_IN_BACKGROUND allow"
        d_record "cmd appops set $p RUN_ANY_IN_BACKGROUND allow"
        d_record "am set-standby-bucket $p active"
        printf '   %s%s%s\n' "$C_D" "$p" "$C_R"
    done
    command touch "$D_ON"
    say "para reverter: sh scripts/debloat.sh off"
}

debloat_off() {
    if [ ! -f "$D_OFF" ]; then
        warn "nada para reverter (nenhum debloat aplicado por este script)."
        return 0
    fi
    say "revertendo debloat"
    # roda as reversões na ordem inversa
    if command -v tac >/dev/null 2>&1; then
        tac "$D_OFF" | while IFS= read -r cmd; do [ -n "$cmd" ] && sh_run "$cmd" >/dev/null 2>&1; done
    else
        sed '1!G;h;$!d' "$D_OFF" | while IFS= read -r cmd; do [ -n "$cmd" ] && sh_run "$cmd" >/dev/null 2>&1; done
    fi
    rm -f "$D_OFF" "$D_ON"
    say "restaurado"
}

debloat_status() {
    if d_applied; then
        say "debloat aplicado. reversões guardadas em $D_OFF"
        printf '  %sreverter:%s sh scripts/debloat.sh off\n' "$C_A" "$C_R"
    else
        say "nenhum debloat aplicado"
    fi
}

# --- main ---------------------------------------------------------------------
case "${1:-status}" in
    on)        debloat_on "${2:-medio}" ;;
    off)       debloat_off ;;
    status)    debloat_status ;;
    preview)   debloat_preview "${2:-medio}" ;;
    list)      printf '  %sapps de usuário (-3):%s\n' "$C_A" "$C_R"; sh_get "pm list packages -3"
               printf '\n  %sapps de sistema (-s):%s\n' "$C_A" "$C_R"; sh_get "pm list packages -s" ;;
    disable)   disable_app "$2" ;;
    enable)    enable_app "$2" ;;
    uninstall) uninstall_app "$2" ;;
    restore)   restore_app "$2" ;;
    restrict)  restrict_app "$2" ;;
    unrestrict) unrestrict_app "$2" ;;
    *) printf '  uso: debloat.sh on [leve|medio|pesado] | off | status | list\n'
       printf '       debloat.sh disable|enable|uninstall|restore|restrict|unrestrict <pacote>\n' ;;
esac

rc=$?
otm_v_report debloat
exit $rc
