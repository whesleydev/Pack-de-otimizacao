# ===========================================================
# Phase 1: DEVICE & TOUCH DETECTION (f01-f08)
# Read-only diagnostics — zero changes
# ===========================================================

f01_touchscreen_presence(){
    if grep -Eqi "touchscreen|touch screen|TOUCHSCREEN" "$INPUT" 2>/dev/null; then
        ok "f01 Touchscreen detectado"
    else
        warn "f01 Touchscreen nao identificado no dumpsys"
    fi
}

f02_touch_vendor(){
    _vendors="goodix|focaltech|synaptics|elan|himax|novatek|atmel|melfas|cypress|ili|chipone|raydium|mstar|zinitix"
    _found="$(grep -Eio "$_vendors" "$INPUT" 2>/dev/null | sort -u | tr '\n' ', ')"
    if nonempty "$_found"; then
        report "f02 Touch vendor: $_found"
        ok "f02 Touch vendor: $_found"
    else
        ok "f02 Touch vendor generico"
    fi
}

f03_input_service(){
    if dumpsys input >/dev/null 2>&1; then
        ok "f03 Servico de input acessivel"
    else
        warn "f03 Servico de input nao acessivel"
    fi
}

f04_multitouch_detect(){
    if grep -Eqi "ABS_MT|TOUCH_MAJOR|MT_SLOT" "$INPUT" 2>/dev/null; then
        ok "f04 Multitouch suportado"
    else
        ok "f04 Multitouch nao exposto (single-touch)"
    fi
}

f05_touch_resolution(){
    grep -Ei "ABS_X|ABS_MT_POSITION" "$INPUT" 2>/dev/null | head -6 >> "$REPORT"
    ok "f05 Resolucao touch analisada"
}

f06_device_info(){
    SDK="$(prop ro.build.version.sdk)"
    REL="$(prop ro.build.version.release)"
    MAN="$(prop ro.product.manufacturer)"
    MDL="$(prop ro.product.model)"
    detect_brand
    report "f06 Device: $MAN $MDL | Android $REL (SDK $SDK) | Brand: $BRAND"
    ok "f06 $MAN $MDL | Android $REL | $BRAND"
}

f07_settings_snapshot(){
    for _k in pointer_speed long_press_timeout multi_press_timeout \
              haptic_feedback_enabled show_touches pointer_location \
              sound_effects_enabled peak_refresh_rate min_refresh_rate; do
        printf '%s=%s\n' "$_k" "$(get system "$_k")" >> "$REPORT"
    done
    for _k in long_press_timeout touch_exploration_enabled accessibility_enabled \
              notification_badging screensaver_enabled spell_checker_enabled; do
        printf '%s=%s\n' "$_k" "$(get secure "$_k")" >> "$REPORT"
    done
    for _k in window_animation_scale transition_animation_scale \
              animator_duration_scale always_finish_activities low_power; do
        printf '%s=%s\n' "$_k" "$(get global "$_k")" >> "$REPORT"
    done
    ok "f07 Snapshot de configuracoes salvo"
}

f08_display_info(){
    _size="$(wm size 2>/dev/null | tail -1)"
    _dens="$(wm density 2>/dev/null | tail -1)"

    # --- FIXED: Multiple regex patterns for refresh rate detection ---
    # Pattern 1: "NNHz" or "NN.NHz" format (Samsung, some AOSP)
    # Pattern 2: "fps=NN.N" or "fps: NN.N" format (Xiaomi, AOSP)
    # Pattern 3: "refreshRate=NN.N" format (various)
    # Pattern 4: "NN.N fps" format (SurfaceFlinger)

    _display_dump="$(dumpsys display 2>/dev/null)"
    _sf_dump="$(dumpsys SurfaceFlinger 2>/dev/null | head -200)"

    _maxhz=""

    # Try fps= pattern first (most common on Xiaomi/AOSP)
    _try="$(printf '%s\n%s' "$_display_dump" "$_sf_dump" | grep -Eio 'fps[= :]+[0-9]+\.?[0-9]*' | grep -Eo '[0-9]+\.?[0-9]*' | awk '$1+0>=30 && $1+0<=360' | sort -t. -k1,1n | tail -1)"
    [ -n "$_try" ] && _maxhz="$_try"

    # Try Hz pattern
    if [ -z "$_maxhz" ]; then
        _try="$(printf '%s\n%s' "$_display_dump" "$_sf_dump" | grep -Eio '[0-9]+\.?[0-9]*[ ]*[Hh][Zz]' | grep -Eo '[0-9]+\.?[0-9]*' | awk '$1+0>=30 && $1+0<=360' | sort -t. -k1,1n | tail -1)"
        [ -n "$_try" ] && _maxhz="$_try"
    fi

    # Try refreshRate= pattern
    if [ -z "$_maxhz" ]; then
        _try="$(printf '%s\n%s' "$_display_dump" "$_sf_dump" | grep -Eio 'refreshRate[= :]+[0-9]+\.?[0-9]*' | grep -Eo '[0-9]+\.?[0-9]*' | awk '$1+0>=30 && $1+0<=360' | sort -t. -k1,1n | tail -1)"
        [ -n "$_try" ] && _maxhz="$_try"
    fi

    # Fallback: check settings values
    if [ -z "$_maxhz" ]; then
        for _sk in peak_refresh_rate user_refresh_rate; do
            _sv="$(get system "$_sk")"
            if nonempty "$_sv"; then
                _svi="$(printf '%s' "$_sv" | sed 's/\..*//')"
                if [ "$_svi" -ge 30 ] 2>/dev/null && [ "$_svi" -le 360 ] 2>/dev/null; then
                    _maxhz="$_sv"
                    break
                fi
            fi
        done
    fi

    if [ -n "$_maxhz" ]; then
        MAX_HZ="$_maxhz"
        MAX_REFRESH="$(printf '%s' "$_maxhz" | sed 's/\..*//')"
    else
        MAX_HZ=""
        MAX_REFRESH="60"
    fi

    report "f08 Display: $_size | $_dens | Max: ${MAX_REFRESH}Hz"
    ok "f08 Display: $_size | Max: ${MAX_REFRESH}Hz"
}
