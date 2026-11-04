#!/system/bin/sh
# =============================================================================
#  hidden-tune.sh - Otimizações que o Android ESCONDE (sem root).
#
#  São chaves de desempenho que existem no sistema mas não aparecem em menu
#  nenhum: constantes do ActivityManager, verificador de pacotes (a checagem de
#  assinatura a cada instalação), App Standby, compilação AOT dos apps,
#  compactação de memória (zRAM), coleta de lixo, TRIM, congelamento de apps em
#  cache e coleta de estatísticas de rede.
#
#  REGRA DESTE SCRIPT: cada chave é LIDA DE VOLTA. Se o aparelho não aceitar, o
#  bkp_set acusa "não mudou" em vez de dizer que aplicou. Nada de número
#  inventado.
#
#  Cada módulo tem par liga/desliga e registra a própria reversão (bkp_*), então
#  "Reverter TUDO" (pack.sh restore) devolve o valor original do aparelho.
#
#  Uso: hidden-tune.sh <modulo> on|off|status  |  all on|off  |  list
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

scope_begin hidden-tune   # reversão própria: `restore_all` percorre todos os escopos

MODULOS="proc verify bg aot ram gc trim freezer gpu netstats"

list() {
    printf '  %s◆%s  %sOTIMIZAÇÕES ESCONDIDAS DO ANDROID%s\n\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '   %sproc%s      constantes do ActivityManager (memória, jobs, serviços)\n' "$C_A" "$C_R"
    printf '   %sverify%s    desliga a checagem de assinatura a cada instalação\n' "$C_A" "$C_R"
    printf '   %sbg%s        App Standby: restringe o que fica em 2º plano\n' "$C_A" "$C_R"
    printf '   %saot%s       compila os apps em código nativo (abrem mais rápido)\n' "$C_A" "$C_R"
    printf '   %sram%s       compactação de memória (zRAM) e pressão de cache\n' "$C_A" "$C_R"
    printf '   %sgc%s        coleta de lixo concorrente (menos pausa no jogo)\n' "$C_A" "$C_R"
    printf '   %strim%s      TRIM sob demanda (limpa os blocos livres do armazenamento)\n' "$C_A" "$C_R"
    printf '   %sfreezer%s   congela apps em cache (volta instantâneo, sem matar)\n' "$C_A" "$C_R"
    printf '   %sgpu%s       libera o driver gráfico para o jogo\n' "$C_A" "$C_R"
    printf '   %snetstats%s  para a coleta de estatísticas de rede (menos I/O)\n' "$C_A" "$C_R"
    printf '\n   Uso: %s <modulo> on|off|status  |  all on|off  |  list\n' "$0"
}

# ---------------------------------------------------------------------------
# proc - constantes do ActivityManager (AOSP ActivityManagerConstants). É o
# módulo de MAIOR impacto: mexe no cache de processos, nos limites de memória,
# nos tempos de serviço em segundo plano e na verificação periódica de CPU.
# O `am_constants_merge` (common.sh) preserva o que já existe na chave, porque
# o `settings put` nessa chave substitui a string inteira.
# ---------------------------------------------------------------------------
m_proc() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "Constantes do ActivityManager (memória e 2º plano)"
            am_set \
                max_cached_processes=32 \
                max_phantom_processes=2147483647 \
                background_settle_time=200 \
                fgservice_min_shown_time=2000 \
                fgservice_min_report_time=3000 \
                fgservice_screen_on_before_time=1000 \
                fgservice_screen_on_after_time=5000 \
                content_provider_retain_time=20000 \
                gc_timeout=5000 \
                gc_min_interval=1000 \
                full_pss_min_interval=120000 \
                full_pss_lowered_interval=60000 \
                power_check_interval=90000 \
                power_check_max_cpu_1=10 \
                power_check_max_cpu_2=18 \
                power_check_max_cpu_3=18 \
                power_check_max_cpu_4=28 \
                service_restart_duration=1000 \
                service_restart_duration_factor=1 \
                service_min_restart_time_between=2000 \
                service_background_timeout=60000 \
                service_timeout=120000 \
                service_crash_restart_duration=1000 \
                use_compaction=true \
                process_start_async=true
            say "constantes ajustadas"
            ;;
        off)
            bkp_begin
            say "Constantes do ActivityManager - devolver ao padrão"
            bkp_del global activity_manager_constants
            say "volta ao padrão de fábrica"
            ;;
        status|'')
            say "Constantes do ActivityManager"
            printf '   %s\n' "$(sh_get 'settings get global activity_manager_constants' | cut -c1-120)"
            ;;
        *) err "uso: proc on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# verify - o verificador de pacotes confere a assinatura dos apps a cada
# instalação/atualização e em eventos de boot. Em aparelho com muitos apps isso
# custa tempo e I/O. A Play Store tem o próprio controle, então isto só tira o
# trabalho extra do sistema.
# ---------------------------------------------------------------------------
m_verify() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "Verificador de pacotes: menos checagens"
            bkp_set global package_verifier_enable 0
            bkp_set global verifier_verify_adb_installs 0
            bkp_set global package_verifier_user_consent -1
            say "checagem de assinatura a cada instalação cortada"
            ;;
        off)
            bkp_begin
            say "Verificador de pacotes: padrão"
            bkp_set global package_verifier_enable 1
            bkp_set global verifier_verify_adb_installs 1
            say "verificação de volta ao padrão"
            ;;
        status|'')
            say "Verificador de pacotes"
            printf '   verificação:    %s\n' "$(sh_get 'settings get global package_verifier_enable')"
            printf '   apps por adb:   %s\n' "$(sh_get 'settings get global verifier_verify_adb_installs')"
            ;;
        *) err "uso: verify on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# bg - App Standby + restrição automática de apps em segundo plano. O Android
# põe apps ociosos em standby e restringe o que eles podem fazer; ligar isso
# reduz o "acorda a CPU à toa" sem impedir o app em primeiro plano.
# ---------------------------------------------------------------------------
m_bg() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "App Standby: restringindo o 2º plano"
            bkp_set global app_standby_enabled 1
            bkp_set global app_auto_restriction_enabled 1
            say "apps ociosos passam a ser restringidos"
            ;;
        off)
            bkp_begin
            say "App Standby: padrão"
            bkp_set global app_standby_enabled 0
            bkp_set global app_auto_restriction_enabled 0
            say "restrição automática devolvida ao padrão"
            ;;
        status|'')
            say "App Standby"
            printf '   standby:   %s\n' "$(sh_get 'settings get global app_standby_enabled')"
            printf '   restrição: %s\n' "$(sh_get 'settings get global app_auto_restriction_enabled')"
            ;;
        *) err "uso: bg on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# aot - compilação AOT. Sem compilação, o app é interpretado na primeira
# execução (lento) e compila enquanto você usa (engasgo). Aqui o sistema compila
# tudo em código nativo com o perfil de velocidade e o app do jogo recebe
# compilação máxima. É o que mais muda o "abre rápido e não engasga".
# `pm.dexopt.*` são propriedades lidas pelo PackageManager na hora de compilar.
# ---------------------------------------------------------------------------
m_aot() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "Compilação AOT (pode demorar alguns minutos)"
            prop_set pm.dexopt.first-boot speed
            prop_set pm.dexopt.boot-after-ota speed
            prop_set pm.dexopt.install speed
            prop_set pm.dexopt.bg-dexopt speed
            prop_set pm.dexopt.shared speed
            say "compilando todos os apps (aguarde)"
            sh_run "cmd package compile -m speed -f -a" >/dev/null 2>&1
            _g="$(game_pkg_saved)"; [ -n "$_g" ] || _g="$GAME_PKG_DEFAULT"
            if sh_run "pm list packages $_g" 2>/dev/null | grep -q "$_g"; then
                sh_run "cmd package compile -m speed -f $_g" >/dev/null 2>&1
                say "jogo ($_g) compilado em velocidade máxima"
            fi
            otm_v_inc apply; otm_v_inc changed
            say "pronto (o ganho aparece nas próximas aberturas)"
            ;;
        off)
            bkp_begin
            say "Compilação AOT - voltar ao modo por perfil"
            prop_set pm.dexopt.first-boot speed-profile
            prop_set pm.dexopt.boot-after-ota speed-profile
            prop_set pm.dexopt.install speed-profile
            prop_set pm.dexopt.bg-dexopt speed-profile
            prop_set pm.dexopt.shared speed-profile
            say "modo de compilação devolvido ao padrão"
            ;;
        status|'')
            say "Compilação AOT"
            printf '   first-boot: %s\n' "$(sh_get 'getprop pm.dexopt.first-boot')"
            printf '   install:    %s\n' "$(sh_get 'getprop pm.dexopt.install')"
            ;;
        *) err "uso: aot on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# ram - compactação de memória. O zRAM compacta a RAM em vez de matar o app;
# mais compactação = mais RAM efetiva, com um pouco mais de CPU. Os knobs do
# kernel (sysctl) reduzem a "pressão" de cache e evitam engasgo de alocação.
# ---------------------------------------------------------------------------
m_ram() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "Compactação de memória (zRAM) e pressão de cache"
            otm_sysctl vm.swappiness 100
            otm_sysctl vm.compaction_proactiveness 40
            otm_sysctl vm.watermark_boost_factor 15000
            otm_sysctl vm.watermark_scale_factor 150
            otm_sysctl vm.vfs_cache_pressure 100
            say "compactação ajustada"
            ;;
        off)
            bkp_begin
            say "Compactação de memória - padrão"
            otm_sysctl vm.compaction_proactiveness 20
            otm_sysctl vm.watermark_scale_factor 10
            say "compactação devolvida ao padrão"
            ;;
        status|'')
            say "Compactação de memória"
            printf '   swappiness:  %s\n' "$(sh_get 'cat /proc/sys/vm/swappiness')"
            printf '   compaction:  %s\n' "$(sh_get 'cat /proc/sys/vm/compaction_proactiveness')"
            printf '   RAM livre:   %s MB\n' "$(otm_ram_livre_mb)"
            ;;
        *) err "uso: ram on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# gc - coleta de lixo concorrente. Sem isso o Android pode parar o app para
# coletar lixo (a "engasgada" de meio segundo). Ligado, a coleta acontece em
# paralelo e o jogo não trava.
# ---------------------------------------------------------------------------
m_gc() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "Coleta de lixo concorrente"
            bkp_set global force_concurrent_gc 1
            say "o jogo não para mais para coletar lixo"
            ;;
        off)
            bkp_begin
            say "Coleta de lixo - padrão"
            bkp_del global force_concurrent_gc
            say "GC devolvido ao padrão"
            ;;
        status|'')
            say "Coleta de lixo"
            printf '   concorrente: %s (1 = ligado)\n' "$(sh_get 'settings get global force_concurrent_gc')"
            ;;
        *) err "uso: gc on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# trim - TRIM sob demanda. Sem TRIM o armazenamento vai ficando "sujo" e a
# leitura do jogo piora com o tempo. É uma limpeza pontual (não tem o que
# desfazer) e é segura.
# ---------------------------------------------------------------------------
m_trim() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "TRIM sob demanda (blocos livres do armazenamento)"
            sh_run "sm idle-maint run" >/dev/null 2>&1
            sh_run "cmd package trim-caches 1073741824" >/dev/null 2>&1
            otm_v_inc apply; otm_v_inc changed
            say "armazenamento tratado (melhora a leitura do jogo)"
            ;;
        off)
            say "TRIM é uma limpeza pontual — não há o que desfazer"
            ;;
        status|'')
            say "Armazenamento"
            printf '   livre em /data: %s\n' "$(sh_get 'df -h /data' | awk 'NR==2{print $4}')"
            ;;
        *) err "uso: trim on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# freezer - congela os apps em CACHE em vez de matá-los. Eles não consomem CPU
# enquanto congelados, mas voltam instantâneo quando você abre de novo (é o que
# o Hail/Greenify fazem, aqui pelo mecanismo do próprio Android).
# ---------------------------------------------------------------------------
m_freezer() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "Congelar apps em cache"
            bkp_set global cached_apps_freezer enabled
            say "apps em cache ficam congelados (RAM livre, sem perder o estado)"
            ;;
        off)
            bkp_begin
            say "Congelador - padrão"
            bkp_set global cached_apps_freezer default
            say "congelador devolvido ao padrão"
            ;;
        status|'')
            say "Congelador de apps em cache"
            printf '   modo: %s\n' "$(sh_get 'settings get global cached_apps_freezer')"
            ;;
        *) err "uso: freezer on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# gpu - libera o driver gráfico para TODOS os apps (não só o jogo). O driver de
# jogo é mais direto com a GPU; deixá-lo disponível para o app do jogo tira a
# camada de tradução no meio do caminho.
# ---------------------------------------------------------------------------
m_gpu() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "Driver gráfico liberado para os apps"
            bkp_set global game_driver_all_apps 1
            say "driver do jogo disponível para todos"
            ;;
        off)
            bkp_begin
            say "Driver gráfico - padrão"
            bkp_set global game_driver_all_apps 0
            say "devolvido ao padrão"
            ;;
        status|'')
            say "Driver gráfico"
            printf '   driver p/ todos: %s\n' "$(sh_get 'settings get global game_driver_all_apps')"
            ;;
        *) err "uso: gpu on|off|status"; return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# netstats - o sistema coleta estatística de rede de cada app o tempo todo
# (grava em disco periodicamente). Parar isso reduz I/O e um pouco de CPU; só
# deixa de existir o gráfico de "uso de dados por app".
# ---------------------------------------------------------------------------
m_netstats() {
    acao="${1:-status}"
    case "$acao" in
        on)
            bkp_begin
            say "Estatísticas de rede: paradas"
            bkp_set global netstats_enabled 0
            say "o sistema para de gravar o uso de dados por app"
            ;;
        off)
            bkp_begin
            say "Estatísticas de rede: padrão"
            bkp_set global netstats_enabled 1
            say "coleta devolvida ao padrão"
            ;;
        status|'')
            say "Estatísticas de rede"
            printf '   ativo: %s (0 = parado)\n' "$(sh_get 'settings get global netstats_enabled')"
            ;;
        *) err "uso: netstats on|off|status"; return 1 ;;
    esac
}

# --- despacho -----------------------------------------------------------------
[ $# -eq 0 ] && { list; exit 0; }

modulo="$1"; shift
case "$modulo" in
    list) list; exit 0 ;;
    all)
        acao="${1:-on}"
        for m in $MODULOS; do "m_$m" "$acao"; echo; done
        ;;
    *)
        if echo " $MODULOS " | grep -q " $modulo "; then
            "m_$modulo" "$@"
        else
            err "módulo desconhecido: $modulo"
            list
            exit 1
        fi ;;
esac

rc=$?
otm_v_report hidden-tune
exit $rc
