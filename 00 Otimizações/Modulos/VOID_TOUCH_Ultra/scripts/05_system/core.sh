# ===========================================================
# Phase 5: SYSTEM LATENCY REDUCTION (f27-f32)
# Free CPU/RAM/GPU for touch event priority
# ===========================================================

f27_kill_cached_processes(){
    am kill-all >/dev/null 2>&1
    CHANGED=$((CHANGED+1))
    ok "f27 Processos em cache eliminados"
}

f28_trim_memory(){
    _count=0
    for _pkg in $(pm list packages -3 2>/dev/null | sed 's/package://' | head -40); do
        am send-trim-memory "$_pkg" COMPLETE >/dev/null 2>&1 && _count=$((_count+1))
    done
    CHANGED=$((CHANGED+1))
    ok "f28 TRIM_MEMORY enviado para $_count apps"
}

f29_disable_notification_pulse(){
    safe_disable system notification_light_pulse "f29 LED de notificacao"
}

f30_disable_notification_dots(){
    safe_disable secure notification_badging "f30 Pontos de notificacao"
}

f31_ensure_activities_persist(){
    _old="$(get global always_finish_activities)"
    if [ "$_old" = "1" ]; then
        safe_set global always_finish_activities 0 "f31 Manter atividades em memoria"
    else
        ok "f31 Atividades ja persistem em memoria"
    fi
}

f32_disable_dtmf_tones(){
    safe_disable system dtmf_tone "f32 Tons DTMF do discador"
}
