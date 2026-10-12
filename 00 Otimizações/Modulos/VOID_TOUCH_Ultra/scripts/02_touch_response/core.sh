# ===========================================================
# Phase 2: TOUCH RESPONSE OPTIMIZATION (f09-f16)
# Reduce input latency and remove debug overhead
# ===========================================================

f09_disable_show_touches(){
    safe_disable system show_touches "f09 Debug overlay de toque"
}

f10_disable_pointer_location(){
    safe_disable system pointer_location "f10 Debug overlay de coordenadas"
}

f11_optimize_long_press(){
    # Default 400-500ms -> 300ms for faster recognition
    # Try secure namespace first (AOSP), then system (some OEMs)
    _v1="$(get secure long_press_timeout)"
    _v2="$(get system long_press_timeout)"

    if nonempty "$_v1"; then
        case "$_v1" in *[!0-9]*) ;; *)
            if [ "$_v1" -gt 300 ] 2>/dev/null; then
                safe_set secure long_press_timeout 300 "f11 Long press timeout"
                return
            else
                ok "f11 Long press timeout (ja otimizado: ${_v1}ms)"
                return
            fi
        ;; esac
    fi

    if nonempty "$_v2"; then
        case "$_v2" in *[!0-9]*) ;; *)
            if [ "$_v2" -gt 300 ] 2>/dev/null; then
                safe_set system long_press_timeout 300 "f11 Long press timeout"
                return
            else
                ok "f11 Long press timeout (ja otimizado: ${_v2}ms)"
                return
            fi
        ;; esac
    fi

    # Neither exists — try writing to secure
    safe_set secure long_press_timeout 300 "f11 Long press timeout"
}

f12_optimize_multi_press(){
    # Default 300ms -> 250ms for faster double-tap
    # Try writing regardless of current value
    _old="$(get system multi_press_timeout)"
    if nonempty "$_old"; then
        case "$_old" in
            *[!0-9]*) safe_set system multi_press_timeout 250 "f12 Multi press timeout" ;;
            *)
                if [ "$_old" -gt 250 ] 2>/dev/null; then
                    safe_set system multi_press_timeout 250 "f12 Multi press timeout"
                else
                    ok "f12 Multi press timeout (ja otimizado: ${_old}ms)"
                fi ;;
        esac
    else
        # Try writing even if null
        safe_set system multi_press_timeout 250 "f12 Multi press timeout"
    fi
}

f13_optimize_pointer_speed(){
    _old="$(get system pointer_speed)"
    if nonempty "$_old"; then
        case "$_old" in
            *[!0-9-]*) ok "f13 Pointer speed (valor customizado: $_old)" ;;
            *)
                if [ "$_old" -lt 3 ] 2>/dev/null; then
                    safe_set system pointer_speed 3 "f13 Pointer speed (boost)"
                elif [ "$_old" -gt 7 ] 2>/dev/null; then
                    safe_set system pointer_speed 7 "f13 Pointer speed (cap)"
                else
                    ok "f13 Pointer speed (otimo: $_old)"
                fi ;;
        esac
    else
        safe_set system pointer_speed 4 "f13 Pointer speed"
    fi
}

f14_disable_touch_sounds(){
    safe_disable system sound_effects_enabled "f14 Sons de toque"
}

f15_disable_lockscreen_sounds(){
    safe_disable system lockscreen_sounds_enabled "f15 Sons de lockscreen"
}

f16_disable_charging_sounds(){
    safe_disable global charging_sounds_enabled "f16 Sons de carregamento"
}
