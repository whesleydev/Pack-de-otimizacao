# ===========================================================
# Phase 4: DISPLAY & REFRESH RATE (f21-f26)
# Higher refresh = smoother touch tracking
# ===========================================================

f21_set_peak_refresh(){
    if [ -n "$MAX_HZ" ] && [ "$MAX_REFRESH" -gt 60 ] 2>/dev/null; then
        _fval="${MAX_REFRESH}.0"
        safe_set system peak_refresh_rate "$_fval" "f21 Peak refresh -> ${MAX_REFRESH}Hz"
    else
        ok "f21 Peak refresh (display ${MAX_REFRESH}Hz, ja no maximo)"
    fi
}

f22_set_min_refresh(){
    if [ -n "$MAX_HZ" ] && [ "$MAX_REFRESH" -gt 60 ] 2>/dev/null; then
        _fval="${MAX_REFRESH}.0"
        safe_set system min_refresh_rate "$_fval" "f22 Min refresh -> ${MAX_REFRESH}Hz"
    else
        ok "f22 Min refresh (display ${MAX_REFRESH}Hz)"
    fi
}

f23_set_user_refresh(){
    if [ -n "$MAX_HZ" ] && [ "$MAX_REFRESH" -gt 60 ] 2>/dev/null; then
        _fval="${MAX_REFRESH}.0"
        safe_set system user_refresh_rate "$_fval" "f23 User refresh -> ${MAX_REFRESH}Hz"
    else
        ok "f23 User refresh (display ${MAX_REFRESH}Hz)"
    fi
}

f24_disable_window_blurs(){
    # Android 12+ window blur effects — GPU overhead on every frame
    safe_enable global disable_window_blurs "f24 Desativar blur de janelas"
}

f25_disable_notification_bubbles(){
    # Try global first, then secure (varies by Android version)
    _v1="$(get global notification_bubbles)"
    _v2="$(get secure notification_bubbles)"
    if nonempty "$_v1"; then
        safe_disable global notification_bubbles "f25 Notification bubbles"
    elif nonempty "$_v2"; then
        safe_disable secure notification_bubbles "f25 Notification bubbles"
    else
        safe_disable global notification_bubbles "f25 Notification bubbles"
    fi
}

f26_disable_screensaver(){
    # Screen saver/Daydream adds display overhead
    safe_disable secure screensaver_enabled "f26 Screen saver/Daydream"
}
