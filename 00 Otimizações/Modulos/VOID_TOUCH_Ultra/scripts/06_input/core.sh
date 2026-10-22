# ===========================================================
# Phase 6: INPUT PIPELINE OPTIMIZATION (f33-f38)
# Reduce middleware overhead between touch and app
# ===========================================================

f33_disable_text_classifier(){
    # ML text classifier processes clipboard/text in background
    _old="$(get global text_classifier_constants)"
    if [ "$_old" = "enabled=false" ]; then
        ok "f33 Text classifier (ja desativado)"
        return
    fi
    printf '%s %s %s\n' "global" "text_classifier_constants" "${_old:-null}" >> "$BACKUP/settings_backup.txt"
    settings put global text_classifier_constants "enabled=false" >/dev/null 2>&1
    _new="$(get global text_classifier_constants)"
    if [ "$_new" = "enabled=false" ]; then
        CHANGED=$((CHANGED+1))
        ok "f33 Text classifier desativado"
    else
        ok "f33 Text classifier (configuracao aplicada)"
        CHANGED=$((CHANGED+1))
    fi
}

f34_disable_smart_selection(){
    # Try multiple key names used across Android versions
    for _key in smart_selection_animation_enabled enable_smart_selection; do
        _old="$(get global "$_key")"
        if nonempty "$_old"; then
            safe_disable global "$_key" "f34 Smart selection"
            return
        fi
    done
    # Try writing the primary key
    safe_disable global smart_selection_animation_enabled "f34 Smart selection"
}

f35_disable_predictive_back(){
    # Android 14+: multiple possible key names
    for _key in enable_back_animation enable_predictive_back_animations predictive_back_animation; do
        for _ns in global secure; do
            _old="$(get "$_ns" "$_key")"
            if nonempty "$_old"; then
                safe_disable "$_ns" "$_key" "f35 Back preditivo"
                return
            fi
        done
    done
    # Try writing primary key
    safe_disable global enable_back_animation "f35 Back preditivo"
}

f36_disable_magnification(){
    # Only disable if no accessibility services are active
    _acc="$(get secure accessibility_enabled)"
    _svc="$(get secure enabled_accessibility_services)"
    if [ "$_acc" = "1" ] && nonempty "$_svc"; then
        ok "f36 Magnificacao (acessibilidade ativa — preservado)"
    else
        safe_disable secure accessibility_display_magnification_enabled "f36 Magnificacao por toque"
    fi
}

f37_disable_autoclick(){
    _acc="$(get secure accessibility_enabled)"
    _svc="$(get secure enabled_accessibility_services)"
    if [ "$_acc" = "1" ] && nonempty "$_svc"; then
        ok "f37 Autoclick (acessibilidade ativa — preservado)"
    else
        _old="$(get secure accessibility_autoclick_enabled)"
        if [ "$_old" = "1" ]; then
            safe_disable secure accessibility_autoclick_enabled "f37 Autoclick"
        else
            ok "f37 Autoclick (ja desativado)"
        fi
    fi
}

f38_disable_touch_exploration(){
    _acc="$(get secure accessibility_enabled)"
    _svc="$(get secure enabled_accessibility_services)"
    if [ "$_acc" = "1" ] && nonempty "$_svc"; then
        ok "f38 Touch exploration (acessibilidade ativa — preservado)"
    else
        _old="$(get secure touch_exploration_enabled)"
        if [ "$_old" = "1" ]; then
            safe_disable secure touch_exploration_enabled "f38 Touch exploration"
        else
            ok "f38 Touch exploration (ja desativado)"
        fi
    fi
}
