#!/system/bin/sh
# =============================================================================
#  lib.sh - Congelar Apps. Estado em $STATE.
#
#  Regras de segurança:
#    - whitelist = nunca congela (o usuário adiciona o que NÃO pode congelar).
#    - blacklist = a lista de apps a congelar (padrão: bloat comum).
#    - apps do sistema/essenciais NUNCA entram (proteção embutida).
#    - congelar por padrão é "soft" (só am force-stop + cache freezer),
#      o modo "suspend" (pm suspend, estilo Brevent) é opt-in.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
STATE="/data/adb/packotm_freezer"
mkdir -p "$STATE" 2>/dev/null || STATE="$DIR/state"
mkdir -p "$STATE" 2>/dev/null
CFG="$STATE/config"
WL_FILE="$STATE/whitelist"
BL_FILE="$STATE/blacklist"
LOG="$STATE/freezer.log"

# --- config padrão ------------------------------------------------------------
ENABLE_FREEZER=1
FREEZE_MODE=suspend      # suspend (pm suspend, estilo Brevent) | soft (force-stop)
FREEZE_ON_BOOT=1
FREEZE_INTERVAL=180      # segundos entre varreduras
CACHE_FREEZER=1          # liga o cached_apps_freezer do sistema
KILL_ON_FREEZE=1         # força parar o app ao congelar
AUTO_BLACKLIST=1         # usa a blacklist padrão abaixo
[ -f "$CFG" ] && . "$CFG" 2>/dev/null

# blacklist padrão (apps de fundo que costumam drenar RAM/bateria)
DEFAULT_BLACKLIST="com.instagram.android com.facebook.katana com.facebook.orca \
com.ss.android.ugc.trill com.ss.android.ugc.aweme com.twitter.android \
com.google.android.youtube com.android.chrome com.spotify.music com.discord \
com.netflix.mediaclient com.snapchat.android com.reddit.frontpage"

# apps que NUNCA podem ser congelados (proteção embutida)
SYSTEM_GUARD="android com.android.systemui com.android.settings com.android.phone \
com.android.server.telecom com.google.android.gms com.google.android.gsf \
com.android.vending com.google.android.inputmethod.latin com.android.inputmethod.latin \
com.android.providers.telephony com.android.providers.contacts com.android.providers.media \
com.android.shell com.android.externalstorage com.android.documentsui com.android.bluetooth \
com.android.nfc com.android.launcher3 com.google.android.apps.nexuslauncher \
com.termux com.topjohnwu.magisk com.sukisu.ultra me.weishu.kernelsu \
frb.axeron.manager ia.mo.kernelmanager com.android.dialer com.android.mms \
com.android.emergency com.android.certinstaller com.android.packageinstaller"

log() { echo "[$(date '+%m-%d %H:%M:%S')] $1" >> "$LOG"; }

save_default_config() {
    [ -f "$CFG" ] && return 0
    {
        echo "ENABLE_FREEZER=$ENABLE_FREEZER"
        echo "FREEZE_MODE=$FREEZE_MODE"
        echo "FREEZE_ON_BOOT=$FREEZE_ON_BOOT"
        echo "FREEZE_INTERVAL=$FREEZE_INTERVAL"
        echo "CACHE_FREEZER=$CACHE_FREEZER"
        echo "KILL_ON_FREEZE=$KILL_ON_FREEZE"
        echo "AUTO_BLACKLIST=$AUTO_BLACKLIST"
    } > "$CFG"
}

save_config() {
    {
        for k in ENABLE_FREEZER FREEZE_MODE FREEZE_ON_BOOT FREEZE_INTERVAL \
                 CACHE_FREEZER KILL_ON_FREEZE AUTO_BLACKLIST; do
            eval "v=\$$k"
            printf '%s=%s\n' "$k" "$v"
        done
    } > "$CFG"
}

boot_wait() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done
    # espera o /sdcard montar (alguns apps só aparecem depois)
    i=0
    while [ ! -d /sdcard/Android ] && [ "$i" -lt 30 ]; do sleep 1; i=$((i+1)); done
}

# --- whitelist / blacklist ----------------------------------------------------
_ensure_lists() {
    [ -f "$WL_FILE" ] || : > "$WL_FILE"
    if [ ! -f "$BL_FILE" ]; then
        if [ "$AUTO_BLACKLIST" = "1" ]; then
            for p in $DEFAULT_BLACKLIST; do echo "$p"; done > "$BL_FILE"
        else
            : > "$BL_FILE"
        fi
    fi
}

# retorna 0 se o pacote está protegido (whitelist ou guarda do sistema)
is_protected() {
    p="$1"
    case " $SYSTEM_GUARD " in *" $p "*) return 0 ;; esac
    grep -qxF "$p" "$WL_FILE" 2>/dev/null && return 0
    return 1
}

# imprime a lista efetiva de pacotes a congelar (blacklist - whitelist - guarda)
freeze_list() {
    _ensure_lists
    for p in $(cat "$BL_FILE" 2>/dev/null); do
        is_protected "$p" && continue
        echo "$p"
    done
}

# --- detecção de pacotes instalados ------------------------------------------
installed_pkgs() {  # só apps de usuário (terceiros)
    pm list packages -3 2>/dev/null | sed 's/^package://' | tr -d '\r'
}
installed_pkgs_all() {  # inclui desabilitados
    pm list packages -u -3 2>/dev/null | sed 's/^package://' | tr -d '\r'
}

is_installed() {
    pm list packages "$1" 2>/dev/null | grep -q "package:$1"
}

# --- congelar / descongelar ---------------------------------------------------
freeze_one() {
    p="$1"
    is_protected "$p" && { log "freezer: $p protegido (whitelist) — ignorado"; return 1; }
    case "$FREEZE_MODE" in
        suspend)
            pm suspend --user 0 "$p" >/dev/null 2>&1
            ;;
        soft)
            pm disable-user --user 0 "$p" >/dev/null 2>&1
            ;;
    esac
    [ "$KILL_ON_FREEZE" = "1" ] && am force-stop "$p" >/dev/null 2>&1
    log "freezer: congelado $p ($FREEZE_MODE)"
}

unfreeze_one() {
    p="$1"
    pm unsuspend --user 0 "$p" >/dev/null 2>&1
    pm enable --user 0 "$p" >/dev/null 2>&1
    log "freezer: descongelado $p"
}

freeze_all() {
    _ensure_lists
    n=0
    for p in $(freeze_list); do
        is_installed "$p" || continue
        freeze_one "$p" && n=$((n+1))
    done
    [ "$CACHE_FREEZER" = "1" ] && settings put global cached_apps_freezer enabled >/dev/null 2>&1
    log "freezer: lote concluído ($n apps)"
    echo "$n"
}

unfreeze_all() {
    for p in $(installed_pkgs_all); do
        unfreeze_one "$p"
    done
    settings put global cached_apps_freezer disabled >/dev/null 2>&1
    log "freezer: descongelou todos"
}

revert() {
    unfreeze_all
    log "freezer: revertido"
}
