#!/system/bin/sh
# =============================================================================
#  snapshot.sh - Salva o estado ATUAL do aparelho e permite voltar a qualquer
#  momento. Ideal antes de aplicar qualquer tweak do pack.
#
#  Uso:
#     sh snapshot.sh save              # cria um snapshot com data/hora
#     sh snapshot.sh save meu-nome     # snapshot com nome fixo
#     sh snapshot.sh list              # lista os snapshots
#     sh snapshot.sh show latest       # mostra o que foi salvo
#     sh snapshot.sh diff latest       # compara o estado atual com o snapshot
#     sh snapshot.sh restore latest    # restaura o snapshot
#     sh snapshot.sh restore 2026-10-05_1430
#     sh snapshot.sh delete latest
#
#  Funciona com ADB, Shizuku (rish), root ou shell local (via common.sh).
#  Snapshots ficam em: ~/.packotm/snapshots/<id>/
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

SNAP_DIR="$ST/snapshots"
mkdir -p "$SNAP_DIR" 2>/dev/null

# --- chaves que o pack altera (tipo chave) ------------------------------------
KEYS_GLOBAL="window_animation_scale transition_animation_scale animator_duration_scale \
force_gpu_rendering disable_window_blurs accessibility_reduce_transparency \
private_dns_mode private_dns_specifier wifi_scan_always_enabled \
low_power adaptive_battery_management_enabled cached_apps_freezer \
heads_up_notifications_enabled zen_mode game_driver_all_apps activity_manager_constants"

KEYS_SYSTEM="touch_responsiveness long_press_timeout pointer_speed touch_slop \
screen_off_timeout screen_brightness peak_refresh_rate min_refresh_rate"

# propriedades capturadas em modo best-effort (podem não persistir após reboot)
PROPS="debug.hwui.renderer net.tcp.buffersize.default net.tcp.buffersize.wifi \
net.tcp.buffersize.lte net.tcp.buffersize.hspa persist.sys.touch.sensitivity \
persist.sys.input.touch.boost"

# -----------------------------------------------------------------------------
snap_id() {
    if [ -n "$1" ]; then echo "$1"; else date +%Y-%m-%d_%H%M%S; fi
}

save() {
    id="$(snap_id "$2")"
    d="$SNAP_DIR/$id"
    mkdir -p "$d"
    say "Salvando snapshot: $id"

    # meta
    {
        echo "id=$id"
        echo "data=$(date '+%Y-%m-%d %H:%M:%S')"
        echo "modo=$RUN_MODE"
        echo "modelo=$(sh_get 'getprop ro.product.model')"
        echo "android=$(sh_get 'getprop ro.build.version.release')"
    } > "$d/meta"

    # settings
    : > "$d/settings"
    for k in $KEYS_GLOBAL; do
        v="$(sh_get "settings get global $k")"
        printf 'global %s %s\n' "$k" "${v:-null}" >> "$d/settings"
    done
    for k in $KEYS_SYSTEM; do
        v="$(sh_get "settings get system $k")"
        printf 'system %s %s\n' "$k" "${v:-null}" >> "$d/settings"
    done

    # props (best effort)
    : > "$d/props"
    for p in $PROPS; do
        v="$(sh_get "getprop $p")"
        [ -n "$v" ] && printf 'setprop %s %s\n' "$p" "$v" >> "$d/props"
    done

    n=$(wc -l < "$d/settings")
    say "OK — $n chaves salvas em $d"
    return 0
}

latest_id() {
    ls -1 "$SNAP_DIR" 2>/dev/null | sort | tail -1
}

resolve() {
    if [ "$1" = "latest" ] || [ -z "$1" ]; then latest_id; else echo "$1"; fi
}

list() {
    if [ -z "$(ls -1 "$SNAP_DIR" 2>/dev/null)" ]; then
        warn "nenhum snapshot ainda. rode: sh snapshot.sh save"
        return 0
    fi
    printf '  Snapshots em %s:\n\n' "$SNAP_DIR"
    for d in $(ls -1 "$SNAP_DIR" | sort); do
        m="$SNAP_DIR/$d/meta"
        info=""
        [ -f "$m" ] && info="$(grep -m1 '^modelo=' "$m" | cut -d= -f2-) | $(grep -m1 '^data=' "$m" | cut -d= -f2-)"
        printf '   %b%s%b  %s\n' "$C_A" "$d" "$C_R" "$info"
    done
}

show() {
    id="$(resolve "$1")"
    d="$SNAP_DIR/$id"
    [ -d "$d" ] || { err "snapshot não encontrado: $id"; exit 1; }
    printf '  Snapshot %s%s%s\n\n' "$C_A" "$id" "$C_R"
    [ -f "$d/meta" ] && sed 's/^/   /' "$d/meta"
    printf '\n   --- settings ---\n'
    sed 's/^/   /' "$d/settings"
    [ -s "$d/props" ] && { printf '\n   --- props ---\n'; sed 's/^/   /' "$d/props"; }
}

cur() { # cur <tipo> <chave>
    sh_get "settings get $1 $2"
}

diff() {
    id="$(resolve "$1")"
    d="$SNAP_DIR/$id/settings"
    [ -f "$d" ] || { err "snapshot não encontrado: $id"; exit 1; }
    printf '  Diferenças (atual vs %s%s%s):\n\n' "$C_A" "$id" "$C_R"
    changed=0
    while read -r t k v; do
        [ -z "$k" ] && continue
        c="$(cur "$t" "$k")"
        [ -z "$c" ] && c="null"
        if [ "$c" != "$v" ]; then
            printf '   %b%s %s%b\n' "$C_Y" "$t" "$k" "$C_R"
            printf '      salvo:   %s\n' "$v"
            printf '      atual:   %s\n' "$c"
            changed=$((changed+1))
        fi
    done < "$d"
    [ "$changed" = "0" ] && say "nenhuma diferença — está igual ao snapshot."
}

restore() {
    id="$(resolve "$1")"
    d="$SNAP_DIR/$id"
    [ -f "$d/settings" ] || { err "snapshot não encontrado: $id"; exit 1; }
    warn "Restaurando o estado de: $id"
    n=0
    while read -r t k v; do
        [ -z "$k" ] && continue
        if [ -z "$v" ] || [ "$v" = "null" ]; then
            sh_run "settings delete $t $k" >/dev/null
        else
            sh_run "settings put $t $k '$v'" >/dev/null
        fi
        n=$((n+1))
    done < "$d/settings"
    if [ -s "$d/props" ]; then
        while read -r _ p v; do
            [ -z "$p" ] && continue
            sh_run "setprop $p $v" >/dev/null
        done < "$d/props"
    fi
    # estados que não são settings
    sh_run "dumpsys deviceidle unforce" >/dev/null
    say "$n chaves restauradas. Relogue/desligue a tela para aplicar."
}

delete() {
    id="$(resolve "$1")"
    d="$SNAP_DIR/$id"
    [ -d "$d" ] || { err "snapshot não encontrado: $id"; exit 1; }
    rm -rf "$d"
    say "snapshot removido: $id"
}

usage() {
    printf '  Uso: %s save [nome] | list | show [id|latest] | diff [id|latest]\n' "$0"
    printf '        restore [id|latest] | delete [id|latest]\n'
}

case "$1" in
    save)    save "$@" ;;
    list)    list ;;
    show)    show "$2" ;;
    diff)    diff "$2" ;;
    restore) restore "$2" ;;
    delete)  delete "$2" ;;
    *)       usage ;;
esac
