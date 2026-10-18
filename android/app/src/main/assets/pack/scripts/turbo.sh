#!/system/bin/sh
# =============================================================================
#  turbo.sh - Recursos "turbo" (sem root, via ADB/Shizuku) que faltavam no pack.
#
#  Uso: sh scripts/turbo.sh <ação> [args]
#
#    status                 mostra o estado de tudo abaixo
#    art <pkg> [modo]       recompila UM app (speed-profile|speed|everything)
#    art-all [modo]         recompila TODOS os apps (speed-profile por padrão)
#    dexopt-bg              dispara o bg-dexopt-job (compilação ociosa do sistema)
#    standby <pkg> <bucket> app standby bucket: active|working|frequent|rare|restricted
#    hibernate <pkg|now>    hiberna (estilo Hail): force-stop + set-inactive
#    killbg                 mata apps em 2º plano de forma seletiva (poupa o jogo)
#    phantom <on|off|status> liga/desliga o Phantom Process Killer
#    trim                   poda caches de verdade (cmd package trim-caches)
#    refresh <max|min|auto> [hz]  trava a taxa de atualização
#    refresh_fixed <hz>           trava a tela numa taxa fixa (60/90/120/144)
#    audio <on|off|status>        baixa latência de áudio para jogos
#    mem_compact <on|off|status>  compactação de memória (não mata apps)
#    perfmode <on|off|status>     modo desempenho fixo (Android 11+)
#    telemetry <on|off>           desliga logs/telemetria e scans "sempre disponível"
#
#  Tudo reversível: os valores antigos vão para ~/.packotm/off.sh.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

# --- ART / dexopt por app -----------------------------------------------------
# art <pkg> [speed-profile|speed|everything] -> recompila só aquele app.
art_one() {
    p="$1"; m="${2:-speed-profile}"
    [ -n "$p" ] || { err "uso: art <pacote> [speed-profile|speed|everything]"; return 1; }
    case "$m" in speed-profile|speed|everything|verify|quicken) ;; *) err "modo inválido: $m"; return 1 ;; esac
    say "compilando $p em modo $m (pode demorar)…"
    out="$(sh_get "cmd package compile -m $m -f $p")"
    printf '   %s%s%s\n' "$C_D" "${out:-sem saída}" "$C_R"
    printf '   %sreverter:%s cmd package compile -m verify -f %s\n' "$C_A" "$C_R" "$p"
}

# art-all [modo] -> recompila todos os apps (speed-profile é o equilíbrio certo).
art_all() {
    m="${1:-speed-profile}"
    say "compilando TODOS os apps em modo $m (demora vários minutos)…"
    sh_run "cmd package compile -m $m -a" >/dev/null 2>&1
    sh_run "cmd package trim-caches 1000G" >/dev/null 2>&1
    say "art-all: apps recompilados ($m) + cache podado"
}

dexopt_bg() {
    say "disparando bg-dexopt-job (compilação em ocioso)…"
    sh_run "cmd package bg-dexopt-job" >/dev/null 2>&1
    say "bg-dexopt-job enviado (roda sozinho quando o aparelho estiver parado)"
}

# --- App Standby Buckets ------------------------------------------------------
standby() {
    p="$1"; b="$2"
    [ -n "$p" ] || { err "uso: standby <pacote> <active|working|frequent|rare|restricted>"; return 1; }
    case "$b" in active|working_set|working|frequent|rare|restricted|never) ;; *) err "bucket inválido: $b"; return 1 ;; esac
    [ "$b" = "working" ] && b="working_set"
    old="$(sh_get "am get-standby-bucket $p")"
    bkp_raw "am set-standby-bucket $p ${old:-active}"
    otm_v_inc apply
    sh_run "am set-standby-bucket $p $b" >/dev/null
    now="$(sh_get "am get-standby-bucket $p")"
    if [ "$now" = "$b" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s → bucket %s\n' "$C_G" "$C_R" "$p" "$b"
    else
        otm_v_inc failed
        printf '   %bX%b %s bucket não mudou (lido: %s)\n' "$C_RD" "$C_R" "$p" "${now:-vazio}"
    fi
}

# --- hibernação (estilo Hail) -------------------------------------------------
hibernate_one() {
    p="$1"
    [ -n "$p" ] || { err "uso: hibernate <pacote|now>"; return 1; }
    say "hibernando $p (force-stop + inativo + restricted)"
    sh_run "am force-stop $p" >/dev/null
    sh_run "cmd activity set-inactive $p true" >/dev/null 2>&1
    sh_run "am set-standby-bucket $p restricted" >/dev/null 2>&1
    sh_run "cmd appops set $p RUN_IN_BACKGROUND ignore" >/dev/null 2>&1
    bkp_raw "cmd activity set-inactive $p false"
    bkp_raw "am set-standby-bucket $p active"
    bkp_raw "cmd appops set $p RUN_IN_BACKGROUND allow"
    say "hibernado: $p (abrir o app acorda ele normalmente)"
}

hibernate_all() {
    say "hibernando TODOS os apps de usuário (menos o jogo e a allowlist)"
    keep="com.dts.freefireth com.dts.freefiremax com.termux"
    for p in $(sh_get "pm list packages -3" | sed 's/package://'); do
        case " $keep " in *" $p "*) skip "$p (na allowlist)"; continue ;; esac
        hibernate_one "$p" >/dev/null 2>&1
        printf '   %s%s%s\n' "$C_D" "$p" "$C_R"
    done
    say "hibernação em massa concluída"
}

# --- matar 2º plano seletivo --------------------------------------------------
killbg() {
    say "matando apps em 2º plano (poupando o jogo)"
    keep="com.dts.freefireth com.dts.freefiremax"
    for p in $(sh_get "pm list packages -3" | sed 's/package://'); do
        case " $keep " in *" $p "*) continue ;; esac
        sh_run "am force-stop $p" >/dev/null 2>&1
    done
    sh_run "am kill-all" >/dev/null 2>&1
    say "2º plano encerrado (sem tocar no jogo)"
}

# --- Phantom Process Killer ---------------------------------------------------
phantom() {
    a="${1:-status}"
    case "$a" in
        off)
            bkp_begin
            bkp_set global settings_enable_monitor_phantom_procs false
            sh_run "device_config put activity_manager max_phantom_processes 2147483647" >/dev/null 2>&1
            say "Phantom Process Killer DESLIGADO (bom p/ Termux, emuladores, serviços)" ;;
        on)
            bkp_begin
            bkp_set global settings_enable_monitor_phantom_procs true
            say "Phantom Process Killer LIGADO (padrão do Android)" ;;
        status|*)
            v="$(sh_get 'settings get global settings_enable_monitor_phantom_procs')"
            [ -z "$v" ] || [ "$v" = "null" ] && v="(padrão: ligado)"
            printf '  %sphantom procs monitor:%s %s\n' "$C_A" "$C_R" "$v"
            printf '  %smax_phantom_processes:%s %s\n' "$C_A" "$C_R" "$(sh_get 'device_config get activity_manager max_phantom_processes')" ;;
    esac
}

# --- trim de caches real ------------------------------------------------------
trim() {
    say "podando caches (sem apagar dados)"
    before="$(sh_get 'df /data' | awk 'NR==2{print $4}')"
    sh_run "cmd package trim-caches 1000G" >/dev/null 2>&1
    sh_run "pm trim-caches 999999999999" >/dev/null 2>&1
    after="$(sh_get 'df /data' | awk 'NR==2{print $4}')"
    printf '  %santes:%s %s KB   %sdepois:%s %s KB\n' "$C_A" "$C_R" "${before:-?}" "$C_A" "$C_R" "${after:-?}"
    say "caches podados (dados dos apps intactos)"
}

# --- refresh rate -------------------------------------------------------------
refresh() {
    a="${1:-max}"; hz="${2:-}"
    bkp_begin
    case "$a" in
        max)
            hz="${hz:-$(sh_get 'dumpsys display' | sed -n 's/.*mSupportedModes.*//p')}"
            hz="${hz:-120.0}"
            bkp_set system peak_refresh_rate "$hz"
            bkp_set system min_refresh_rate "$hz"
            say "refresh travado no máximo (${hz}Hz)" ;;
        min)
            bkp_set system peak_refresh_rate 60.0
            bkp_set system min_refresh_rate 60.0
            say "refresh travado em 60Hz (economia)" ;;
        auto|off)
            sh_run "settings delete system peak_refresh_rate" >/dev/null
            sh_run "settings delete system min_refresh_rate" >/dev/null
            say "refresh no automático" ;;
        *) bkp_set system peak_refresh_rate "$a"; bkp_set system min_refresh_rate "$a"; say "refresh travado em ${a}Hz" ;;
    esac
}

# --- refresh fixo (consistência de frametime) ---------------------------------
# Trava min = peak = hz. Evita a tela oscilar (60<->120Hz) no meio da partida,
# o que causa micro-travadas (jitter) mesmo com FPS alto.
refresh_fixed() {
    hz="${1:-}"
    case "$hz" in
        60|90|120|144) ;;
        *) err "uso: refresh_fixed <60|90|120|144>"; return 1 ;;
    esac
    bkp_begin
    bkp_set system peak_refresh_rate "$hz.0"
    bkp_set system min_refresh_rate "$hz.0"
    boot_add "settings put system peak_refresh_rate ${hz}.0; settings put system min_refresh_rate ${hz}.0"
    say "tela travada em ${hz}Hz (frametime estável)"
    say "para voltar ao dia a dia: turbo.sh refresh auto"
}

# --- áudio de baixa latência (jogos) ------------------------------------------
# Reduz o buffer de áudio e liga o modo de baixa latência. Ajuda a ouvir passos
# e tiros alguns ms mais cedo. Requer root (prop de áudio global).
audio() {
    a="${1:-status}"
    case "$a" in
        on)
            bkp_begin
            require_root "áudio de baixa latência" || return 1
            prop_set audio.deep_buffer.media 0
            prop_set audio.safemedia.force 0
            prop_set vendor.audio.deep_buffer.media 0
            sh_run "setprop audio_hal.period_size 192" >/dev/null 2>&1
            boot_add "setprop audio.deep_buffer.media 0; setprop audio.safemedia.force 0"
            say "áudio de baixa latência LIGADO (reinicie o jogo)" ;;
        off)
            prop_set audio.deep_buffer.media 1
            prop_set audio.safemedia.force 1
            prop_set vendor.audio.deep_buffer.media 1
            say "áudio de volta ao padrão" ;;
        status|*)
            printf '  %sáudio deep_buffer:%s %s\n' "$C_A" "$C_R" "$(sh_get 'getprop audio.deep_buffer.media')"
            printf '  %ssafemedia.force:%s %s\n' "$C_A" "$C_R" "$(sh_get 'getprop audio.safemedia.force')" ;;
    esac
}

# --- compactação de memória (em vez de matar apps) ----------------------------
# Em vez de "matar" apps (o Android reabre e gasta mais CPU), força a compactação
# de páginas ociosas e o kernel a recuperar memória sem encerrar processos.
mem_compact() {
    a="${1:-status}"
    case "$a" in
        on)
            bkp_begin
            require_root "compactação de memória" || return 1
            sh_run "echo 1 > /proc/sys/vm/compact_memory" >/dev/null 2>&1
            [ -w /proc/sys/vm/compact_unevictable_allowed ] && sh_run "echo 1 > /proc/sys/vm/compact_unevictable_allowed" >/dev/null 2>&1
            [ -w /proc/sys/vm/compaction_proactiveness ] && sh_run "echo 20 > /proc/sys/vm/compaction_proactiveness" >/dev/null 2>&1
            [ -w /proc/sys/vm/watermark_boost_factor ] && sh_run "echo 15000 > /proc/sys/vm/watermark_boost_factor" >/dev/null 2>&1
            bkp_raw "echo 0 > /proc/sys/vm/compaction_proactiveness"
            bkp_raw "echo 0 > /proc/sys/vm/watermark_boost_factor"
            say "compactação de memória LIGADA (recupera RAM sem matar apps)" ;;
        off)
            sh_run "echo 0 > /proc/sys/vm/compaction_proactiveness" >/dev/null 2>&1
            sh_run "echo 0 > /proc/sys/vm/watermark_boost_factor" >/dev/null 2>&1
            say "compactação de volta ao padrão" ;;
        status|*)
            printf '  %scompactação proativa:%s %s\n' "$C_A" "$C_R" "$(sh_get 'cat /proc/sys/vm/compaction_proactiveness')"
            printf '  %swatermark boost:%s %s\n' "$C_A" "$C_R" "$(sh_get 'cat /proc/sys/vm/watermark_boost_factor')" ;;
    esac
}

# --- modo desempenho fixo -----------------------------------------------------
perfmode() {
    a="${1:-status}"
    case "$a" in
        on)
            sh_run "cmd power set-fixed-performance-mode-enabled true" >/dev/null 2>&1
            bkp_raw "cmd power set-fixed-performance-mode-enabled false"
            say "modo desempenho fixo LIGADO (mais FPS, mais calor)" ;;
        off)
            sh_run "cmd power set-fixed-performance-mode-enabled false" >/dev/null 2>&1
            say "modo desempenho fixo DESLIGADO" ;;
        status|*)
            v="$(sh_get 'dumpsys power' | grep -i 'mIsFixedPerformanceMode' | head -1)"
            printf '  %smodo desempenho fixo:%s %s\n' "$C_A" "$C_R" "${v:-desconhecido}" ;;
    esac
}

# --- telemetria / logs / scans ------------------------------------------------
telemetry() {
    a="${1:-off}"
    bkp_begin
    case "$a" in
        off)
            say "desligando logs e scans em 2º plano"
            sh_run "setprop persist.logd.logpersistd off" >/dev/null 2>&1
            sh_run "logpersist off" >/dev/null 2>&1
            bkp_set global wifi_scan_always_enabled 0
            bkp_set global ble_scan_always_enabled 0
            bkp_set global wifi_scan_throttle_enabled 1
            sh_run "setprop persist.bluetooth.btsnooplogmode disabled" >/dev/null 2>&1
            say "logs/telemetria off, scans 'sempre disponível' off" ;;
        on)
            say "religando logs e scans"
            bkp_set global wifi_scan_always_enabled 1
            bkp_set global ble_scan_always_enabled 1
            sh_run "setprop persist.logd.logpersistd on" >/dev/null 2>&1
            say "padrões restaurados" ;;
    esac
}

# --- status -------------------------------------------------------------------
turbo_status() {
    printf '  %s◆%s  %sTURBO — estado%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %sphantom procs:%s %s\n' "$C_A" "$C_R" "$(sh_get 'settings get global settings_enable_monitor_phantom_procs')"
    printf '  %speak refresh:%s %s / %s\n' "$C_A" "$C_R" "$(sh_get 'settings get system min_refresh_rate')" "$(sh_get 'settings get system peak_refresh_rate')"
    printf '  %slogpersist:%s %s\n' "$C_A" "$C_R" "$(sh_get 'getprop persist.logd.logpersistd')"
    printf '  %swifi scan always:%s %s\n' "$C_A" "$C_R" "$(sh_get 'settings get global wifi_scan_always_enabled')"
    printf '  %sbluetooth scan always:%s %s\n' "$C_A" "$C_R" "$(sh_get 'settings get global ble_scan_always_enabled')"
    printf '  %smemória (activity_manager):%s %s\n' "$C_A" "$C_R" "$(sh_get 'settings get global activity_manager_constants')"
}

# --- main ---------------------------------------------------------------------
case "${1:-status}" in
    status)     turbo_status ;;
    art)        art_one "$2" "$3" ;;
    art-all)    art_all "$2" ;;
    dexopt-bg)  dexopt_bg ;;
    standby)    standby "$2" "$3" ;;
    hibernate)  [ "$2" = "now" ] && hibernate_all || hibernate_one "$2" ;;
    killbg)     killbg ;;
    phantom)    phantom "$2" ;;
    trim)       trim ;;
    refresh)    refresh "$2" "$3" ;;
    refresh_fixed) refresh_fixed "$2" ;;
    audio)      audio "$2" ;;
    mem_compact) mem_compact "$2" ;;
    boot)       case "${2:-status}" in on) boot_install ;; off) boot_uninstall ;; *) boot_status ;; esac ;;
    perfmode)   perfmode "$2" ;;
    telemetry)  telemetry "$2" ;;
    *)
        printf '  uso: turbo.sh status|art <pkg> [modo]|art-all [modo]|dexopt-bg|standby <pkg> <bucket>\n'
        printf '       turbo.sh hibernate <pkg|now>|killbg|phantom on|off|status|trim\n'
        printf '       turbo.sh refresh max|min|auto|<hz>|refresh_fixed <60|90|120|144>\n'
        printf '       turbo.sh audio on|off|status|mem_compact on|off|status\n'
        printf '       turbo.sh boot on|off|status|perfmode on|off|status|telemetry on|off\n' ;;
esac

rc=$?
otm_v_report turbo
exit $rc
