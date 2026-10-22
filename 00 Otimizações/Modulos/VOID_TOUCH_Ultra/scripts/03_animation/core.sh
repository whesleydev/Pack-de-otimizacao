# ===========================================================
# Phase 3: ANIMATION SPEED OPTIMIZATION (f17-f20)
# 0.5x = fast but still visible feedback
# ===========================================================

f17_window_animation(){
    _old="$(get global window_animation_scale)"
    case "$_old" in
        0|0.0|0.5) ok "f17 Window animation (ja otimizado: $_old)" ;;
        *)         safe_set global window_animation_scale 0.5 "f17 Window animation" ;;
    esac
}

f18_transition_animation(){
    _old="$(get global transition_animation_scale)"
    case "$_old" in
        0|0.0|0.5) ok "f18 Transition animation (ja otimizado: $_old)" ;;
        *)         safe_set global transition_animation_scale 0.5 "f18 Transition animation" ;;
    esac
}

f19_animator_duration(){
    _old="$(get global animator_duration_scale)"
    case "$_old" in
        0|0.0|0.5) ok "f19 Animator duration (ja otimizado: $_old)" ;;
        *)         safe_set global animator_duration_scale 0.5 "f19 Animator duration" ;;
    esac
}

f20_disable_ime_animations(){
    safe_disable global fancy_ime_animations "f20 Animacoes do teclado"
}
