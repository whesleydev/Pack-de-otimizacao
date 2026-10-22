# ===========================================================
# Phase 7: ADVANCED OPTIMIZATIONS (f39-f48)
# 1 consolidated vendor function + 9 universal functions
# ===========================================================

f39_vendor_touch_optimizer(){
    # --- Consolidated vendor function ---
    # Tries ALL brand-specific settings for detected brand
    _applied=0

    case "$BRAND" in
        samsung)
            # Edge panels steal edge touch area
            _v="$(get system edge_enable)"
            if [ "$_v" = "1" ]; then
                safe_set system edge_enable 0 "f39 Samsung Edge Panel" && _applied=$((_applied+1))
            fi
            # High touch sensitivity (glove mode)
            for _k in high_touch_sensitivity glove_mode; do
                _v="$(get system "$_k")"
                if nonempty "$_v" && [ "$_v" != "1" ]; then
                    safe_set system "$_k" 1 "f39 Samsung $_k" && _applied=$((_applied+1))
                    break
                fi
            done
            # Game mode touch boost
            _v="$(get global game_home_enable)"
            if nonempty "$_v" && [ "$_v" != "1" ]; then
                safe_set global game_home_enable 1 "f39 Samsung Game Touch" && _applied=$((_applied+1))
            fi
            ;;

        xiaomi)
            # Mistouch prevention adds delay
            for _k in mistouch_prohibition_enabled pocket_mode_enabled; do
                for _ns in system secure; do
                    _v="$(get "$_ns" "$_k")"
                    if nonempty "$_v" && [ "$_v" != "0" ]; then
                        safe_set "$_ns" "$_k" 0 "f39 Xiaomi $_k" && _applied=$((_applied+1))
                    fi
                done
            done
            # 3-finger screenshot gesture adds delay (fixed typo from v5.0)
            for _k in three_gesture_screenshot three_gestrue_screenshot capture_three_finger; do
                _v="$(get system "$_k")"
                if nonempty "$_v" && [ "$_v" != "0" ]; then
                    safe_set system "$_k" 0 "f39 Xiaomi 3-finger" && _applied=$((_applied+1))
                    break
                fi
            done
            # Slip protection
            _v="$(get system slip_protect)"
            if nonempty "$_v" && [ "$_v" != "0" ]; then
                safe_set system slip_protect 0 "f39 Xiaomi slip protect" && _applied=$((_applied+1))
            fi
            ;;

        oneplus)
            for _k in high_touch_sensitivity oplus_high_touch_mode; do
                _v="$(get system "$_k")"
                if nonempty "$_v" && [ "$_v" != "1" ]; then
                    safe_set system "$_k" 1 "f39 OnePlus touch high" && _applied=$((_applied+1))
                    break
                fi
            done
            ;;

        oppo)
            for _k in high_touch_sensitivity coloros_touch_boost; do
                _v="$(get system "$_k")"
                if nonempty "$_v" && [ "$_v" != "1" ]; then
                    safe_set system "$_k" 1 "f39 OPPO touch boost" && _applied=$((_applied+1))
                    break
                fi
            done
            ;;

        huawei)
            _v="$(get system smart_cover_mode)"
            if nonempty "$_v" && [ "$_v" != "0" ]; then
                safe_set system smart_cover_mode 0 "f39 Huawei smart cover" && _applied=$((_applied+1))
            fi
            for _k in glove_mode high_touch_sensitivity; do
                _v="$(get system "$_k")"
                if nonempty "$_v" && [ "$_v" != "1" ]; then
                    safe_set system "$_k" 1 "f39 Huawei $_k" && _applied=$((_applied+1))
                    break
                fi
            done
            ;;

        vivo)
            for _k in touch_boost_enable high_touch_sensitivity; do
                _v="$(get system "$_k")"
                if nonempty "$_v" && [ "$_v" != "1" ]; then
                    safe_set system "$_k" 1 "f39 Vivo $_k" && _applied=$((_applied+1))
                    break
                fi
            done
            ;;
    esac

    # Try universal sensitivity keys on all devices
    for _k in touch_sensitivity enhanced_touch glove_mode high_touch_sensitivity_enable; do
        _v="$(get system "$_k")"
        if nonempty "$_v" && [ "$_v" = "0" ]; then
            safe_set system "$_k" 1 "f39 Universal $_k" && _applied=$((_applied+1))
            break
        fi
    done

    if [ "$_applied" -gt 0 ]; then
        ok "f39 Vendor touch: $_applied ajustes ($BRAND)"
    else
        ok "f39 Vendor touch: sem ajuste especifico ($BRAND)"
    fi
}

f40_disable_battery_saver(){
    # Battery saver throttles CPU/GPU -> increases touch latency
    _old="$(get global low_power)"
    if [ "$_old" = "1" ]; then
        safe_set global low_power 0 "f40 Desativar economia de bateria"
    else
        ok "f40 Economia de bateria (ja desativada)"
    fi
}

f41_clear_debug_app(){
    # Debug app adds monitoring overhead to touch events
    _old="$(get global debug_app)"
    if nonempty "$_old"; then
        printf '%s %s %s\n' "global" "debug_app" "$_old" >> "$BACKUP/settings_backup.txt"
        settings delete global debug_app >/dev/null 2>&1
        CHANGED=$((CHANGED+1))
        ok "f41 Debug app removido ($_old)"
    else
        ok "f41 Debug app (nenhum configurado)"
    fi
    # Also ensure wait_for_debugger is off
    safe_disable global wait_for_debugger "f41 Wait for debugger"
}

f42_reset_gpu_pipeline(){
    # Clear accumulated GPU rendering stats — cleaner render pipeline
    dumpsys gfxinfo --reset >/dev/null 2>&1
    CHANGED=$((CHANGED+1))
    ok "f42 GPU pipeline resetado"
}

f43_trim_app_caches(){
    # Free storage I/O from bloated caches — reduces swap pressure
    pm trim-caches 999999999999 >/dev/null 2>&1
    CHANGED=$((CHANGED+1))
    ok "f43 Cache de apps limpo"
}

f44_disable_spell_checker(){
    # Spell checker runs ML model in background on each keystroke
    safe_disable secure spell_checker_enabled "f44 Verificacao ortografica"
}

f45_disable_wifi_scan_throttle(){
    # WiFi scan throttle causes background CPU spikes
    safe_disable global wifi_scan_throttle_enabled "f45 WiFi scan throttle"
}

f46_disable_network_scoring(){
    # Network scoring runs evaluation algorithms in background
    safe_disable global network_scoring_ui_enabled "f46 Network scoring UI"
}

f47_disable_pkg_verifier(){
    # Package verification adds I/O overhead in background
    safe_disable global verifier_verify_adb_installs "f47 Verificacao de pacotes ADB"
}

f48_connectivity_refresh(){
    # Refresh network connectivity — clears stale connections
    am broadcast -a android.intent.action.CONNECTIVITY_CHANGE >/dev/null 2>&1
    # Force DNS cache clear
    ndc resolver flushdefaultif >/dev/null 2>&1
    CHANGED=$((CHANGED+1))
    ok "f48 Conectividade atualizada"
}
