#!/system/bin/sh
# =============================================================================
#  thermal-pilot.sh - Piloto térmico adaptativo (sem root).
#
#  O problema que ele resolve:
#    Forçar o desempenho máximo e "esquecer" ligado esquenta o aparelho. O SoC
#    bate no limite térmico, o sistema derruba a frequência e o FPS cai ABAIXO
#    do que ficaria se nada tivesse sido forçado. O ganho vira perda.
#
#  O que ele faz:
#    Um laço fechado. Segura o teto de desempenho, acompanha a temperatura e
#    SOLTA antes do aparelho afogar; quando esfria, volta a segurar. Quem manda
#    é a temperatura medida, não o relógio.
#
#  Uso: sh scripts/thermal-pilot.sh <ação> [args]
#     status                 estado atual (para ler)
#     tick                   um ciclo de decisão (o painel chama no poll)
#     arm [minutos]          liga o piloto (padrão 20 min)
#     disarm                 solta o teto e para
#     limits [quente] [frio] mostra ou define os limites em °C
#     recover                rede de segurança: solta se o prazo venceu
#     watch <minutos>        laço limitado (para quando o prazo vence)
#
#  Segurança (as quatro travas que impedem o aparelho de ficar preso):
#    1. Prazo ABSOLUTO gravado em disco: se o processo morrer, o próximo
#       `tick`/`recover`/abertura do painel solta o teto ao ver o prazo vencido.
#    2. Histerese: solta em `hot` e só volta em `cool` (5 °C abaixo). Sem isso o
#       aparelho ficaria ligando/desligando a cada leitura.
#    3. Falha segura = DESLIGADO: não deu para ler a temperatura? solta.
#    4. "Reverter TUDO" sempre solta: o `arm` registra a reversão no escopo.
#
#  Testes: aceita OTM_PILOT_TEMP (temperatura) e OTM_PILOT_NOW (relógio) para
#  poder verificar as decisões sem aparelho e sem esperar de verdade.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
scope_begin pilot
otm_v_reset

PILOT_ST="$ST/pilot"
PILOT_STATE="$PILOT_ST/state"      # off | on | cooling
PILOT_DEADLINE="$PILOT_ST/deadline"
PILOT_LIMITS="$PILOT_ST/limits"    # "hot cool"
PILOT_LOG="$PILOT_ST/log"
PILOT_PEAK="$PILOT_ST/peak"
PILOT_REL="$PILOT_ST/releases"
mkdir -p "$PILOT_ST" 2>/dev/null

DEFAULT_HOT=43
DEFAULT_COOL=38
DEFAULT_MIN=20
LOG_MAX=40

now_epoch() {
    if [ -n "$OTM_PILOT_NOW" ]; then printf '%s' "$OTM_PILOT_NOW"
    else date +%s 2>/dev/null || printf '0'; fi
}

_load_limits() {
    hot="$DEFAULT_HOT"; cool="$DEFAULT_COOL"
    if [ -f "$PILOT_LIMITS" ]; then
        read -r h c < "$PILOT_LIMITS" 2>/dev/null
        case "$h" in ''|*[!0-9]*) ;; *) hot="$h" ;; esac
        case "$c" in ''|*[!0-9]*) ;; *) cool="$c" ;; esac
    fi
    # o frio tem de ficar abaixo do quente, senão a histerese não existe
    [ "$cool" -ge "$hot" ] && cool=$((hot - 5))
    [ "$cool" -lt 20 ] && cool=20
}

# Uma ida só ao shell: lê a temperatura e o estado do teto de desempenho.
# O poll do painel roda a cada 4 s; várias idas ao shell por ciclo pesariam.
_read_temp() {
    sh_get 'z=""; for d in /sys/class/thermal/thermal_zone*; do
[ -d "$d" ] || continue;
t=$(cat "$d/type" 2>/dev/null);
case "$t" in soc|*skin*|cpu*|gpu*|*battery*|tsens*) ;; *) continue;; esac;
x=$(cat "$d/temp" 2>/dev/null);
case "$x" in ""|*[!0-9-]*) continue;; esac;
[ "$x" -gt 1000 ] && x=$((x/1000));
z="$x"; break; done;
if [ -z "$z" ]; then z=$(dumpsys battery 2>/dev/null | awk -F": " "/ temperature:/{print int(\$2/10); exit}"); fi;
printf "%s" "$z"'
}

read_temp() {
    if [ -n "$OTM_PILOT_TEMP" ]; then TEMP="$OTM_PILOT_TEMP"
    else TEMP="$(_read_temp)"; fi
    # qualquer coisa que não seja número vira "sem leitura" (e o tick solta o teto)
    case "$TEMP" in ''|*[!0-9]*) TEMP="" ;; esac
    # sanidade: 0 ou 200 °C não é leitura, é sensor quebrado
    if [ -n "$TEMP" ] && { [ "$TEMP" -lt 5 ] || [ "$TEMP" -gt 120 ]; }; then TEMP=""; fi
}

perf_state() {
    if [ -n "$OTM_PILOT_PERF" ]; then PERF="$OTM_PILOT_PERF"; return 0; fi
    v="$(sh_get 'dumpsys power 2>/dev/null' | grep -o 'mIsFixedPerformanceMode=[a-zA-Z]*' | head -1 | cut -d= -f2)"
    case "$v" in true) PERF=on ;; false) PERF=off ;; *) PERF="" ;; esac
}

state_get() { cat "$PILOT_STATE" 2>/dev/null || printf 'off'; }
state_set() { printf '%s' "$1" > "$PILOT_STATE" 2>/dev/null; }

# hold -> segura o teto de desempenho (e registra a reversão no escopo pilot)
hold() {
    sh_run "cmd power set-fixed-performance-mode-enabled true" >/dev/null 2>&1
    if ! grep -q 'set-fixed-performance-mode-enabled false' "$OFF_SH" 2>/dev/null; then
        bkp_raw "cmd power set-fixed-performance-mode-enabled false"
    fi
}

# release -> solta o teto. É a operação segura: sempre pode ser chamada.
release() {
    sh_run "cmd power set-fixed-performance-mode-enabled false" >/dev/null 2>&1
    printf '%s' "${1:-manual}" > "$PILOT_ST/last_reason" 2>/dev/null
}

log_add() {  # log_add <estado> <temp> <nota>
    printf '%s\t%s\t%s\t%s\n' "$(now_epoch)" "$1" "${2:--}" "$3" >> "$PILOT_LOG" 2>/dev/null
    if [ -f "$PILOT_LOG" ]; then
        n="$(wc -l < "$PILOT_LOG" 2>/dev/null)"
        case "$n" in ''|*[!0-9]*) n=0 ;; esac
        if [ "$n" -gt "$LOG_MAX" ]; then
            tail -n "$LOG_MAX" "$PILOT_LOG" > "$PILOT_LOG.tmp" 2>/dev/null \
                && mv "$PILOT_LOG.tmp" "$PILOT_LOG" 2>/dev/null
        fi
    fi
}

peak_up() {  # guarda a temperatura máxima da sessão
    [ -n "$1" ] || return 0
    p="$(cat "$PILOT_PEAK" 2>/dev/null)"
    case "$p" in ''|*[!0-9]*) p=0 ;; esac
    [ "$1" -gt "$p" ] && printf '%s' "$1" > "$PILOT_PEAK" 2>/dev/null
}

rel_inc() {
    r="$(cat "$PILOT_REL" 2>/dev/null)"
    case "$r" in ''|*[!0-9]*) r=0 ;; esac
    printf '%s' "$((r + 1))" > "$PILOT_REL" 2>/dev/null
}

armed() { [ -f "$PILOT_DEADLINE" ]; }

# _drop -> tira o piloto de ação por completo (solta e limpa o estado)
_drop() {
    release "$1"
    rm -f "$PILOT_DEADLINE" "$PILOT_STATE" 2>/dev/null
    state_set off
}

# recover -> rede de segurança barata (não lê sensores). Chamada ao abrir o
# painel e antes de qualquer ação: se o prazo venceu, solta o teto na hora.
recover() {
    armed || return 0
    dl="$(cat "$PILOT_DEADLINE" 2>/dev/null)"
    n="$(now_epoch)"
    case "$dl" in ''|*[!0-9]*) _drop "prazo"; return 0 ;; esac
    if [ "$n" -ge "$dl" ]; then
        log_add off - "prazo vencido: teto solto"
        _drop "prazo"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
#  tick - um ciclo de decisão. Idempotente: pode rodar quantas vezes quiser.
# -----------------------------------------------------------------------------
tick() {
    _load_limits
    st="$(state_get)"

    if ! armed; then
        # sem piloto ativo: garante que nada ficou preso de uma sessão anterior
        [ "$st" != off ] && _drop "orfao"
        print_machine
        return 0
    fi

    # 1) prazo absoluto manda em tudo
    recover || { print_machine; return 0; }

    read_temp
    [ -n "$TEMP" ] && peak_up "$TEMP"

    if [ -z "$TEMP" ]; then
        # falha segura: sem leitura confiável, não segura o teto
        if [ "$st" != cooling ]; then
            release "sem-leitura"; state_set cooling; log_add cooling - "sem leitura de temperatura"
        fi
        print_machine
        return 0
    fi

    if [ "$st" = on ]; then
        if [ "$TEMP" -ge "$hot" ]; then
            release "quente"; state_set cooling; rel_inc
            log_add cooling "$TEMP" "esquentou (>= ${hot}°C): teto solto"
        fi
    elif [ "$st" = cooling ]; then
        if [ "$TEMP" -le "$cool" ]; then
            hold; state_set on
            log_add on "$TEMP" "esfriou (<= ${cool}°C): teto de volta"
        fi
    else
        # estado desconhecido com piloto armado: recomeça segurando
        hold; state_set on; log_add on "$TEMP" "piloto retomado"
    fi

    print_machine
}

print_machine() {
    _load_limits
    st="$(state_get)"
    a=0; armed && a=1
    left=""
    if armed; then
        dl="$(cat "$PILOT_DEADLINE" 2>/dev/null)"
        n="$(now_epoch)"
        case "$dl" in ''|*[!0-9]*) left="" ;; *) left=$((dl - n)); [ "$left" -lt 0 ] && left=0 ;; esac
    fi
    rel="$(cat "$PILOT_REL" 2>/dev/null)"; case "$rel" in ''|*[!0-9]*) rel=0 ;; esac
    pk="$(cat "$PILOT_PEAK" 2>/dev/null)"; case "$pk" in ''|*[!0-9]*) pk="" ;; esac
    printf '#OTM-PILOT state=%s armed=%d temp=%s hot=%s cool=%s left=%s releases=%s peak=%s\n' \
        "$st" "$a" "${TEMP:-}" "$hot" "$cool" "${left:-}" "$rel" "${pk:-}"
}

# -----------------------------------------------------------------------------
#  Ações
# -----------------------------------------------------------------------------
cmd_arm() {
    mins="${1:-$DEFAULT_MIN}"
    case "$mins" in ''|*[!0-9]*) mins="$DEFAULT_MIN" ;; esac
    [ "$mins" -lt 1 ] && mins=1
    [ "$mins" -gt 240 ] && mins=240

    if ! have_shell; then
        err "sem permissão de shell (Shizuku/ADB). Abra o painel > Configs e conecte."
        return 1
    fi

    _load_limits
    n="$(now_epoch)"
    printf '%s' "$((n + mins * 60))" > "$PILOT_DEADLINE" 2>/dev/null
    printf '0' > "$PILOT_REL" 2>/dev/null
    rm -f "$PILOT_PEAK" "$PILOT_LOG" 2>/dev/null

    read_temp
    [ -n "$TEMP" ] && peak_up "$TEMP"
    hold
    state_set on
    log_add on "${TEMP:--}" "piloto ligado por ${mins} min"

    say "Piloto térmico LIGADO por ${mins} min"
    printf '   %bsolta em %s°C e volta em %s°C — o prazo máximo é a trava final%b\n' \
        "$C_D" "$hot" "$cool" "$C_R"
    print_machine
}

cmd_disarm() {
    log_add off - "desligado pelo usuário"
    _drop "manual"
    say "Piloto térmico DESLIGADO (teto solto)"
    print_machine
}

cmd_limits() {
    if [ -n "$1" ]; then
        h="$1"; c="$2"
        case "$h" in ''|*[!0-9]*) err "limite quente inválido: '$h'"; return 1 ;; esac
        [ "$h" -lt 35 ] || [ "$h" -gt 60 ] && { err "limite quente fora de 35..60°C"; return 1; }
        if [ -z "$c" ]; then c=$((h - 5)); fi
        case "$c" in ''|*[!0-9]*) err "limite frio inválido: '$c'"; return 1 ;; esac
        [ "$c" -ge "$h" ] && { err "o frio ($c) precisa ser menor que o quente ($h)"; return 1; }
        printf '%s %s\n' "$h" "$c" > "$PILOT_LIMITS" 2>/dev/null
        say "limites: solta em ${h}°C, volta em ${c}°C"
    fi
    _load_limits
    printf '   solta em %s°C   |   volta em %s°C\n' "$hot" "$cool"
    printf '#OTM-PILOT state=%s armed=%d hot=%s cool=%s\n' \
        "$(state_get)" "$(armed && echo 1 || echo 0)" "$hot" "$cool"
}

cmd_status() {
    recover
    _load_limits
    st="$(state_get)"
    read_temp
    perf_state
    case "$st" in
        on)      lbl="segurando o teto" ;;
        cooling) lbl="esfriando (teto solto)" ;;
        *)       lbl="desligado" ;;
    esac
    printf '  %s◆%s  %sPILOTO TÉRMICO%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %sestado:%s %s\n' "$C_A" "$C_R" "$lbl"
    printf '  %stemperatura:%s %s\n' "$C_A" "$C_R" "${TEMP:-—}°C"
    printf '  %steto de desempenho:%s %s\n' "$C_A" "$C_R" "${PERF:-—}"
    printf '  %slimites:%s solta em %s°C, volta em %s°C\n' "$C_A" "$C_R" "$hot" "$cool"
    if armed; then
        dl="$(cat "$PILOT_DEADLINE" 2>/dev/null)"; n="$(now_epoch)"
        left=$((dl - n)); [ "$left" -lt 0 ] && left=0
        printf '  %stempo restante:%s %d min\n' "$C_A" "$C_R" "$((left / 60))"
    fi
    rel="$(cat "$PILOT_REL" 2>/dev/null)"; case "$rel" in ''|*[!0-9]*) rel=0 ;; esac
    printf '  %svezes que soltou:%s %s\n' "$C_A" "$C_R" "$rel"
    if [ -s "$PILOT_LOG" ]; then
        printf '  %súltimos ciclos:%s\n' "$C_A" "$C_R"
        tail -n 6 "$PILOT_LOG" | while IFS='	' read -r t s tp nota; do
            printf '    %s%s  %s°C  %s%s\n' "$C_D" "$s" "$tp" "$nota" "$C_R"
        done
    fi
    print_machine
}

# watch - laço limitado. NÃO fica residente: termina no prazo ou no disarm.
# O app pode usar isto numa sessão; se o processo morrer, o prazo absoluto
# gravado em disco garante que o teto será solto no próximo contato.
cmd_watch() {
    mins="${1:-$DEFAULT_MIN}"
    case "$mins" in ''|*[!0-9]*) mins="$DEFAULT_MIN" ;; esac
    armed || { err "o piloto não está ligado"; return 1; }
    say "acompanhando por até ${mins} min (Ctrl+C para parar)"
    i=0
    while [ "$i" -lt "$((mins * 15))" ]; do
        tick >/dev/null 2>&1 || break
        armed || break
        sleep 4
        i=$((i + 1))
    done
    recover
    say "acompanhamento encerrado"
}

case "${1:-status}" in
    status)  cmd_status ;;
    tick)    tick ;;
    arm)     cmd_arm "$2" ;;
    disarm)  cmd_disarm ;;
    limits)  cmd_limits "$2" "$3" ;;
    recover) recover && say "nada a fazer (dentro do prazo)" ;;
    watch)   cmd_watch "$2" ;;
    *)
        printf '  uso: thermal-pilot.sh status|tick|arm [min]|disarm|limits [quente] [frio]|recover|watch <min>\n' ;;
esac

rc=$?
otm_v_report pilot
exit $rc
