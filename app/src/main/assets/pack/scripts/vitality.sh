#!/system/bin/sh
# =============================================================================
#  vitality.sh - Vitalidade: cuida para o aparelho durar (sem root).
#
#  O resto do pack "tira o freio" (mais FPS, mais desempenho). Este script faz o
#  contrário e é o único do pack que olha para o LONGO PRAZO: mede a saúde real
#  da bateria, aplica hábitos que reduzem desgaste e avisa quando o uso está
#  agredindo o aparelho. Nada aqui força o celular; tudo reduz agressão.
#
#  Uso: sh scripts/vitality.sh <ação> [args]
#     diag                 saúde real da bateria (só lê, não muda nada)
#     score                nota de vitalidade 0..100
#     care <on|off|status> modo longevidade (doze + 60Hz + menos scan)
#     guard                guardião de carga: avisa hábitos que desgastam
#     tick                 um ciclo do guardião (o painel chama no poll)
#     status               resumo legível
#
#  Tudo reversível: os valores antigos vão para ~/.packotm/undo/vitality.sh e o
#  "Reverter TUDO" do pack restaura. Nada é destrutivo.
#
#  Testes: aceita OTM_VIT_LEVEL / OTM_VIT_TEMP / OTM_VIT_STATUS / OTM_VIT_HEALTH
#  / OTM_VIT_CYCLES para verificar as decisões sem aparelho.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
scope_begin vitality
otm_v_reset

VIT_ST="$ST/vitality"
mkdir -p "$VIT_ST" 2>/dev/null

# Limites do guardião (reduzem desgaste; o usuário pode ajustar depois)
VIT_LEVEL_MAX=80      # acima disso carregando, avisa (carga alta acelera desgaste)
VIT_TEMP_WARN=40      # carregando e quente: avisa
VIT_TEMP_HOT=43       # carregando e muito quente: avisa forte
VIT_CYCLES_OK=400     # até aqui a contagem de ciclos é considerada normal
VIT_CYCLES_HIGH=800

_num() { printf '%s' "$1" | tr -cd '0-9'; }

# -----------------------------------------------------------------------------
#  Leitura da bateria - em camadas, porque cada aparelho expõe de um jeito.
#  Se não der para ler, devolve "" (nunca um número inventado).
# -----------------------------------------------------------------------------

# _sysfs <nome-do-arquivo> -> primeiro valor encontrado nos caminhos conhecidos
_sysfs() {
    sh_get "for d in /sys/class/power_supply/battery /sys/class/power_supply/bms \
                   /sys/class/power_supply/Battery /sys/class/power_supply/main; do
              [ -f \"\$d/$1\" ] || continue
              v=\$(cat \"\$d/$1\" 2>/dev/null)
              case \"\$v\" in ''|*[!0-9]*) continue;; esac
              printf '%s' \"\$v\"; exit 0
            done" 2>/dev/null
}

read_battery() {
    # capacidade atual e de fábrica (µAh). A razão entre elas é a saúde real.
    if [ -n "$OTM_VIT_HEALTH" ]; then
        HEALTH="$(_num "$OTM_VIT_HEALTH")"
    else
        cf="$(_sysfs charge_full)"; cfd="$(_sysfs charge_full_design)"
        [ -z "$cfd" ] && cfd="$(_sysfs charge_full_design_aw)"
        if [ -n "$cf" ] && [ -n "$cfd" ] && [ "$cfd" -gt 0 ] 2>/dev/null; then
            HEALTH=$((cf * 100 / cfd))
        else
            HEALTH=""
        fi
    fi
    # sanidade: fora de 1..100 não é saúde, é leitura ruim
    case "$HEALTH" in ''|*[!0-9]*) HEALTH="" ;; esac
    [ -n "$HEALTH" ] && { [ "$HEALTH" -lt 1 ] || [ "$HEALTH" -gt 100 ]; } && HEALTH=""

    if [ -n "$OTM_VIT_CYCLES" ]; then CYCLES="$(_num "$OTM_VIT_CYCLES")"
    else CYCLES="$(_sysfs cycle_count)"; fi
    case "$CYCLES" in ''|*[!0-9]*) CYCLES="" ;; esac

    if [ -n "$OTM_VIT_LEVEL" ] || [ -n "$OTM_VIT_TEMP" ] || [ -n "$OTM_VIT_STATUS" ]; then
        LEVEL="$(_num "$OTM_VIT_LEVEL")"; TEMP="$(_num "$OTM_VIT_TEMP")"; STATUS="$OTM_VIT_STATUS"
    else
        b="$(sh_get 'dumpsys battery' 2>/dev/null)"
        LEVEL="$(printf '%s\n' "$b" | awk -F': ' '/ level:/{print $2; exit}')"
        t="$(printf '%s\n' "$b" | awk -F': ' '/ temperature:/{print $2; exit}')"
        TEMP=""
        case "$t" in ''|*[!0-9]*) ;; *) TEMP=$((t / 10)) ;; esac
        s="$(printf '%s\n' "$b" | awk -F': ' '/ status:/{print $2; exit}')"
        case "$s" in 2|5) STATUS="charging" ;; 3|4) STATUS="discharging" ;; *) STATUS="" ;; esac
    fi
    case "$LEVEL" in ''|*[!0-9]*) LEVEL="" ;; esac
    [ -n "$LEVEL" ] && { [ "$LEVEL" -gt 100 ]; } && LEVEL=""
    case "$TEMP" in ''|*[!0-9]*) TEMP="" ;; esac
    [ -n "$TEMP" ] && { [ "$TEMP" -lt 5 ] || [ "$TEMP" -gt 90 ]; } && TEMP=""
    case "$STATUS" in charging|discharging) ;; *) STATUS="" ;; esac
}

# charging -> 1/0/"" (vazio quando não deu para saber)
is_charging() {
    case "$STATUS" in charging) echo 1 ;; discharging) echo 0 ;; *) echo "" ;; esac
}

# -----------------------------------------------------------------------------
#  Nota de vitalidade 0..100. Só dá nota se houver dado real de bateria; sem
#  leitura devolve "" (melhor não ter nota do que ter uma falsa).
# -----------------------------------------------------------------------------
vital_score() {
    [ -n "$HEALTH" ] || { echo ""; return 0; }
    s="$HEALTH"
    # ciclos: penaliza o desgaste acumulado de forma suave
    if [ -n "$CYCLES" ]; then
        if [ "$CYCLES" -gt "$VIT_CYCLES_HIGH" ]; then s=$((s - 12))
        elif [ "$CYCLES" -gt "$VIT_CYCLES_OK" ]; then s=$((s - 6)); fi
    fi
    # calor: uso quente constante é o que mais encurta a vida da célula
    if [ -n "$TEMP" ]; then
        if [ "$TEMP" -ge 43 ]; then s=$((s - 10))
        elif [ "$TEMP" -ge 40 ]; then s=$((s - 5)); fi
    fi
    [ "$s" -lt 0 ] && s=0
    [ "$s" -gt 100 ] && s=100
    echo "$s"
}

# rótulo humano da nota
score_label() {
    n="$1"
    case "$n" in
        '') printf 'sem leitura' ;;
        *) if   [ "$n" -ge 90 ]; then printf 'excelente'
           elif [ "$n" -ge 75 ]; then printf 'saudável'
           elif [ "$n" -ge 60 ]; then printf 'atenção'
           elif [ "$n" -ge 40 ]; then printf 'desgastada'
           else printf 'troque a bateria' ; fi ;;
    esac
}

# -----------------------------------------------------------------------------
#  diag - saúde real. SÓ LÊ. É o que o pack nunca mostrou.
# -----------------------------------------------------------------------------
cmd_diag() {
    read_battery
    sc="$(vital_score)"

    printf '  %s◆%s  %sVITALIDADE DA BATERIA%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    if [ -n "$HEALTH" ]; then
        printf '  %ssaúde real:%s %s%% (%s)\n' "$C_A" "$C_R" "$HEALTH" "$(score_label "$HEALTH")"
        printf '  %sleitura:%s capacidade atual / de fábrica\n' "$C_D" "$C_R"
    else
        printf '  %ssaúde real:%s não foi possível ler neste aparelho\n' "$C_A" "$C_R"
        printf '  %s·%s alguns modelos só expõem isso com root\n' "$C_D" "$C_R"
    fi
    [ -n "$CYCLES" ] && printf '  %sciclos de carga:%s %s\n' "$C_A" "$C_R" "$CYCLES"
    [ -n "$LEVEL" ]  && printf '  %snível:%s %s%%\n' "$C_A" "$C_R" "$LEVEL"
    [ -n "$TEMP" ]   && printf '  %stemperatura:%s %s°C\n' "$C_A" "$C_R" "$TEMP"
    [ -n "$STATUS" ] && printf '  %sestado:%s %s\n' "$C_A" "$C_R" \
        "$([ "$STATUS" = charging ] && echo 'na tomada' || echo 'na bateria')"
    [ -n "$sc" ] && printf '  %snota de vitalidade:%s %s/100\n' "$C_A" "$C_R" "$sc"
    print_machine
}

# -----------------------------------------------------------------------------
#  care - modo longevidade. Reduz agressão em vez de forçar desempenho.
#  Reaproveita exatamente os ajustes que o pack já usa, mas na direção de durar.
# -----------------------------------------------------------------------------
# _care_apply <on|off>: aplica de verdade, SEM imprimir. Quem chama decide a saida.
# O botao unico "Otimizar saude do telefone" reaproveita exatamente o mesmo ajuste,
# sem duplicar codigo e sem risco de divergir do care.
_care_apply() {
    case "$1" in
        on)
            bkp_begin
            say "modo longevidade: reduzindo agressao"
            # 1) sono profundo afinado (o mesmo ajuste do pack, aqui a favor da bateria)
            bkp_set global device_idle_constants \
                "light_after_inactive_to=60000,light_pre_idle_to=60000,inactive_to=120000,sensing_to=0,locating_to=0,idle_after_idle_to_ms=60000,idle_to=300000,min_time_to_alarm=60000"
            sh_run "dumpsys deviceidle enable light" >/dev/null 2>&1
            sh_run "dumpsys deviceidle enable deep" >/dev/null 2>&1
            # 2) tela em 60Hz: taxa alta e um dos maiores consumos continuos
            bkp_set system peak_refresh_rate 60.0
            bkp_set system min_refresh_rate 60.0
            # 3) menos varredura de radio em segundo plano
            bkp_set global wifi_scan_always_enabled 0
            bkp_set global ble_scan_always_enabled 0
            # 4) a economia de energia do sistema VOLTA a funcionar (o pack a desligava)
            bkp_set global low_power 0
            bkp_set global adaptive_battery_management_enabled 1
            say "doze ativo, tela 60Hz, scans off, economia do sistema ligada"
            say "o aparelho dura mais; para voltar: vitality.sh care off"
            printf '%s' "on" > "$VIT_ST/care" 2>/dev/null
            ;;
        off)
            say "modo longevidade desligado"
            sh_run "settings delete global device_idle_constants" >/dev/null 2>&1
            bkp_set global wifi_scan_always_enabled 1
            bkp_set global ble_scan_always_enabled 1
            bkp_set global adaptive_battery_management_enabled 1
            printf '%s' "off" > "$VIT_ST/care" 2>/dev/null
            say "sono profundo e varreduras de volta ao padrao"
            ;;
    esac
}

cmd_care() {
    case "${1:-status}" in
        on|off) _care_apply "$1" ;;
        *)
            st="$(cat "$VIT_ST/care" 2>/dev/null)"
            case "$st" in on|off) ;; *) st="off" ;; esac
            printf '  %smodo longevidade:%s %s\n' "$C_A" "$C_R" "$st"
            ;;
    esac
    print_machine
}

# -----------------------------------------------------------------------------
#  guard - guardião de carga. Não muda nada: avisa hábitos que desgastam.
#  Uma contagem por ciclo de carga (não fica contando a cada leitura).
# -----------------------------------------------------------------------------
_guard_count() {  # _guard_count <nome> <sinal-para-contar>
    n="$(cat "$VIT_ST/g_$1" 2>/dev/null)"
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    if [ "$2" = "1" ]; then
        n=$((n + 1))
        printf '%s' "$n" > "$VIT_ST/g_$1" 2>/dev/null
    fi
    echo "$n"
}

# _guard_flag <nome> <ativo> -> 1 na primeira vez que ativa, 0 depois (até limpar)
_guard_flag() {
    f="$VIT_ST/f_$1"
    if [ "$2" = "1" ]; then
        if [ -f "$f" ]; then echo 0
        else printf 'x' > "$f" 2>/dev/null; echo 1; fi
    else
        rm -f "$f" 2>/dev/null; echo 0
    fi
}

guard_run() {
    read_battery
    chg="$(is_charging)"
    ALERT=""

    if [ "$chg" = "1" ] && [ -n "$LEVEL" ]; then
        if [ "$LEVEL" -ge "$VIT_LEVEL_MAX" ]; then
            if [ "$(_guard_flag high80 1)" = 1 ]; then
                _guard_count high80 1 >/dev/null
                ALERT="carga alta (${LEVEL}%): acima de ${VIT_LEVEL_MAX}% o desgaste acelera"
            fi
        elif [ "$LEVEL" -le 75 ]; then
            _guard_flag high80 0 >/dev/null
        fi
    fi

    if [ "$chg" = "1" ] && [ -n "$TEMP" ]; then
        if [ "$TEMP" -ge "$VIT_TEMP_HOT" ]; then
            if [ "$(_guard_flag hotcharge 1)" = 1 ]; then
                _guard_count hotcharge 1 >/dev/null
                ALERT="calor na tomada (${TEMP}°C): calor + carga é o que mais encurta a vida"
            fi
        elif [ "$TEMP" -le 38 ]; then
            _guard_flag hotcharge 0 >/dev/null
        fi
    fi

    [ -z "$ALERT" ] && [ -n "$TEMP" ] && [ "$TEMP" -ge "$VIT_TEMP_WARN" ] \
        && ALERT="aparelho quente (${TEMP}°C): evite jogar carregando"
}

cmd_guard() {
    read_battery
    guard_run
    n80="$(_guard_count high80 0)"; nhot="$(_guard_count hotcharge 0)"
    printf '  %s◆%s  %sGUARDIÃO DE CARGA%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %scargas acima de %s%%:%s %s vez(es)\n' "$C_A" "$VIT_LEVEL_MAX" "$C_R" "$n80"
    printf '  %scargas com calor:%s %s vez(es)\n' "$C_A" "$C_R" "$nhot"
    if [ -n "$ALERT" ]; then
        printf '  %s!%s  %s\n' "$C_Y" "$C_R" "$ALERT"
    else
        printf '  %s·%s  hábitos de carga em ordem agora\n' "$C_D" "$C_R"
    fi
    print_machine
}

# tick - chamado pelo poll do painel: mantém o guardião de olho sem processo
# residente. Barato: sai cedo quando não há nada a observar.
tick() {
    read_battery
    guard_run
    print_machine
}

print_machine() {
    chg="$(is_charging)"
    [ -z "$chg" ] && chg=""
    sc="$(vital_score)"
    st="$(cat "$VIT_ST/care" 2>/dev/null)"
    case "$st" in on|off) ;; *) st="off" ;; esac
    n80="$(_guard_count high80 0)"; nhot="$(_guard_count hotcharge 0)"
    printf '#OTM-VITAL health=%s cycles=%s level=%s temp=%s charging=%s score=%s care=%s w80=%s whot=%s alert=%s\n' \
        "${HEALTH:-}" "${CYCLES:-}" "${LEVEL:-}" "${TEMP:-}" "$chg" "${sc:-}" "$st" \
        "$n80" "$nhot" "$(printf '%s' "$ALERT" | tr ' ' '_')"
}

cmd_status() {
    read_battery
    guard_run
    sc="$(vital_score)"
    printf '  %s◆%s  %sVITALIDADE%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    if [ -n "$sc" ]; then
        printf '  %snota:%s %s/100 (%s)\n' "$C_A" "$C_R" "$sc" "$(score_label "$sc")"
    else
        printf '  %snota:%s sem leitura de bateria neste aparelho\n' "$C_A" "$C_R"
    fi
    [ -n "$HEALTH" ] && printf '  %ssaúde:%s %s%%\n' "$C_A" "$C_R" "$HEALTH"
    [ -n "$CYCLES" ] && printf '  %sciclos:%s %s\n' "$C_A" "$C_R" "$CYCLES"
    [ -n "$TEMP" ]   && printf '  %stemperatura:%s %s°C\n' "$C_A" "$C_R" "$TEMP"
    st="$(cat "$VIT_ST/care" 2>/dev/null)"
    case "$st" in on|off) ;; *) st="off" ;; esac
    printf '  %smodo longevidade:%s %s\n' "$C_A" "$C_R" "$st"
    [ -n "$ALERT" ] && printf '  %s!%s  %s\n' "$C_Y" "$C_R" "$ALERT"
    print_machine
}

# -----------------------------------------------------------------------------
#  optimize - o botao unico "Otimizar saude do telefone".
#  Liga o modo longevidade e mostra o diagnostico na mesma tela: um toque so para
#  cuidar do aparelho. Nada e forcado; so reduz agressao e revela a saude real.
# -----------------------------------------------------------------------------
cmd_optimize() {
    read_battery
    say "otimizando a saude do telefone"
    _care_apply on
    printf '\n'
    cmd_diag
}

case "${1:-status}" in
    optimize) cmd_optimize ;;
    diag)   cmd_diag ;;
    score)  read_battery; vital_score; printf '\n' ;;
    care)   cmd_care "$2" ;;
    guard)  cmd_guard ;;
    tick)   tick ;;
    status) cmd_status ;;
    *)
        printf '  uso: vitality.sh diag|score|care <on|off|status>|guard|tick|status\n' ;;
esac

rc=$?
otm_v_report vitality
exit $rc
