#!/system/bin/sh

ASTRAX_DIR="/storage/emulated/0/.astrax"
CFG_FILE="$ASTRAX_DIR/gm_cfg"
LOG_FILE="$ASTRAX_DIR/gm_restore.log"

ANDROID_VER=$(getprop ro.build.version.release 2>/dev/null | cut -d. -f1)
ANDROID_VER=${ANDROID_VER:-0}

FPS=$(settings get system peak_refresh_rate 2>/dev/null | cut -d. -f1)
FPS=${FPS:-60}
[ "$FPS" = "null" ] && FPS=60

echo "[$(date)] Astrax GM Restore start — Android $ANDROID_VER, FPS $FPS" > "$LOG_FILE"

if [ ! -f "$CFG_FILE" ] || [ ! -s "$CFG_FILE" ]; then
    echo "[$(date)] No gm_cfg found. Nothing to restore." >> "$LOG_FILE"
    exit 0
fi

for KEY in updatable_driver_production_opt_in_apps \
           updatable_driver_production_opt_out_apps \
           updatable_driver_prerelease_opt_in_apps \
           game_driver_opt_in_apps \
           game_driver_opt_out_apps; do
    settings delete global "$KEY" 2>/dev/null
done

APPLIED=0
SKIPPED=0

while IFS='|' read -r PKG ACTIVE MODE DSVAL GPUDRIVER; do
    [ -z "$PKG" ] && continue
    echo "$PKG" | grep -q '^#' && continue
    echo "$PKG" | grep -qE '^[a-zA-Z][a-zA-Z0-9._]+$' || continue

    echo "[$(date)] Processing: $PKG | active=$ACTIVE mode=$MODE ds=$DSVAL gpu=$GPUDRIVER" >> "$LOG_FILE"

    if [ "$ACTIVE" != "1" ]; then
        echo "  → Skipped (inactive)" >> "$LOG_FILE"
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    apply_game_mode() {
        local pkg="$1"
        local mode="$2"
        local m=1
        [ "$mode" = "performance" ] && m=2

        if [ "$ANDROID_VER" -gt 0 ] && [ "$ANDROID_VER" -lt 12 ]; then
            device_config put game_overlay "$pkg" "mode=$m" 2>/dev/null
            return
        fi

        device_config set_sync_disabled_for_tests persistent 2>/dev/null
        if [ "$mode" = "performance" ]; then
            device_config put game_overlay "$pkg" "mode=2,fps=$FPS,loadingBoost=2147483647" 2>/dev/null
        else
            device_config put game_overlay "$pkg" "mode=1,fps=$FPS" 2>/dev/null
        fi
        device_config clear_override game_overlay "$pkg" 2>/dev/null

        if [ "$ANDROID_VER" -eq 12 ]; then
            cmd game set --mode "$m" --fps "$FPS" "$pkg" 2>/dev/null
        elif [ "$ANDROID_VER" -le 14 ]; then
            cmd game reset --mode "$m" --user 0 "$pkg" 2>/dev/null
            cmd game set --mode "$m" --fps "$FPS" --user 0 "$pkg" 2>/dev/null
        elif [ "$ANDROID_VER" -eq 15 ]; then
            cmd game reset --mode "$m" --user 0 "$pkg" 2>/dev/null
            cmd game set --mode "$m" --fps "$FPS" --user 0 "$pkg" 2>/dev/null
            cmd game mode "$mode" "$pkg" 2>/dev/null
        elif [ "$ANDROID_VER" -ge 16 ]; then
            cmd game reset --mode "$m" --user 0 "$pkg" 2>/dev/null
            cmd game set --mode "$m" --fps "$FPS" --user 0 "$pkg" 2>/dev/null
            cmd game mode "$mode" "$pkg" 2>/dev/null
            game_mode set "$m" "$pkg" 2>/dev/null
        fi
    }

    apply_downscale() {
        local pkg="$1"
        local dsval="$2"

        [ "$ANDROID_VER" -lt 13 ] && return
        [ "$dsval" = "disable" ] || [ "$dsval" = "1.0" ] || [ -z "$dsval" ] && return

        local attempt=1
        while [ "$attempt" -le 3 ]; do
            device_config set_sync_disabled_for_tests persistent 2>/dev/null
            device_config delete game_overlay "$pkg" 2>/dev/null
            device_config put game_overlay "$pkg" "mode=2,fps=$FPS,loadingBoost=2147483647,downscaleFactor=$dsval" 2>/dev/null
            device_config clear_override game_overlay "$pkg" 2>/dev/null
            cmd game set --mode 2 --downscale "$dsval" --user 0 "$pkg" 2>/dev/null
            [ "$ANDROID_VER" -ge 15 ] && cmd game mode performance "$pkg" 2>/dev/null

            CHECK=$(device_config get game_overlay "$pkg" 2>/dev/null)
            case "$CHECK" in
                *"downscaleFactor=$dsval"*)
                    echo "  → downscale verified OK (attempt $attempt)" >> "$LOG_FILE"
                    return
                    ;;
            esac
            echo "  → downscale verify FAILED (attempt $attempt), retrying..." >> "$LOG_FILE"
            attempt=$((attempt + 1))
            sleep 2
        done
        echo "  → downscale gave up after 3 attempts for $pkg" >> "$LOG_FILE"
    }

    apply_gpu_driver() {
        local pkg="$1"
        local driver="$2"
        [ "$driver" = "default" ] || [ -z "$driver" ] && return

        local OPT_IN="updatable_driver_production_opt_in_apps"
        local OPT_OUT="updatable_driver_production_opt_out_apps"
        local DEV_KEY="updatable_driver_prerelease_opt_in_apps"
        local GOPT_IN="game_driver_opt_in_apps"

        for KEY in "$OPT_IN" "$OPT_OUT" "$DEV_KEY" "$GOPT_IN"; do
            CUR=$(settings get global "$KEY" 2>/dev/null)
            [ "$CUR" = "null" ] || [ -z "$CUR" ] && continue
            NEW=$(echo "$CUR" | tr ',' '\n' | grep -vxF "$pkg" | tr '\n' ',' | sed 's/,$//')
            if [ -n "$NEW" ]; then
                settings put global "$KEY" "$NEW" 2>/dev/null
            else
                settings delete global "$KEY" 2>/dev/null
            fi
        done

        case "$driver" in
            game)
                CUR=$(settings get global "$OPT_IN" 2>/dev/null)
                [ "$CUR" = "null" ] || [ -z "$CUR" ] && CUR=""
                [ -n "$CUR" ] && NEW="$CUR,$pkg" || NEW="$pkg"
                settings put global "$OPT_IN" "$NEW" 2>/dev/null

                CUR2=$(settings get global "$GOPT_IN" 2>/dev/null)
                [ "$CUR2" = "null" ] || [ -z "$CUR2" ] && CUR2=""
                [ -n "$CUR2" ] && NEW2="$CUR2,$pkg" || NEW2="$pkg"
                settings put global "$GOPT_IN" "$NEW2" 2>/dev/null
                ;;
            system)
                CUR=$(settings get global "$OPT_OUT" 2>/dev/null)
                [ "$CUR" = "null" ] || [ -z "$CUR" ] && CUR=""
                [ -n "$CUR" ] && NEW="$CUR,$pkg" || NEW="$pkg"
                settings put global "$OPT_OUT" "$NEW" 2>/dev/null
                ;;
            dev)
                CUR=$(settings get global "$DEV_KEY" 2>/dev/null)
                [ "$CUR" = "null" ] || [ -z "$CUR" ] && CUR=""
                [ -n "$CUR" ] && NEW="$CUR,$pkg" || NEW="$pkg"
                settings put global "$DEV_KEY" "$NEW" 2>/dev/null
                ;;
        esac
    }

    apply_game_mode "$PKG" "${MODE:-standard}"
    apply_downscale "$PKG" "${DSVAL:-disable}"
    apply_gpu_driver "$PKG" "${GPUDRIVER:-default}"

    echo "  → Applied OK" >> "$LOG_FILE"
    APPLIED=$((APPLIED + 1))

done < "$CFG_FILE"

echo "[$(date)] Done. Applied=$APPLIED Skipped=$SKIPPED" >> "$LOG_FILE"

if [ "$APPLIED" -gt 0 ]; then
    cmd notification post -S bigtext -t "ᯓAstrax" "★" \
        "Game Manager: $APPLIED game/app dikonfigurasi ulang setelah reboot." 2>/dev/null
fi

cleanup_orphan_overlays() {
    local cfg="$1"
    local overlays
    overlays=$(device_config list game_overlay 2>/dev/null | grep -oE '^[a-zA-Z][a-zA-Z0-9._]+' | sort -u)
    [ -z "$overlays" ] && return

    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if ! grep -qF "${pkg}|" "$cfg" 2>/dev/null; then
            device_config delete game_overlay "$pkg" 2>/dev/null
            echo "[cleanup] Removed orphan overlay: $pkg" >> "$LOG_FILE"
        fi
    done <<EOF
$overlays
EOF
}

cleanup_orphan_overlays "$CFG_FILE"
echo "[$(date)] Cleanup done." >> "$LOG_FILE"
