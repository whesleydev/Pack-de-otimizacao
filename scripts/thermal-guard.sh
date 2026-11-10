#!/system/bin/sh
# =============================================================================
#  thermal-guard.sh - laço térmico PREDITIVO (o "Thermal Headroom Manager").
#
#  O problema: quando o aparelho cruza o limite do kernel, ele já está quente e o
#  throttling vem de uma vez — o jogo engasga por alguns segundos. Reagir ao
#  limite é tarde. Este script LÊ a temperatura das zonas, calcula a INCLINAÇÃO
#  (quanto sobe por segundo) e PROJETA quando vai cruzar o limite. Se faltar
#  pouco, ele baixa o teto de frequência da CPU AGORA, antes do calor chegar.
#
#  Não é "IA": é um controlador. Mede, projeta por extrapolação linear, age com
#  antecedência e solta quando esfria (com histerese, para não ficar liga-desliga).
#  Mais simples que um modelo e mais previsível — o que um laço de controle deve ser.
#
#  Uso:
#     sh thermal-guard.sh once      # avalia uma vez (para teste/cron)
#     sh thermal-guard.sh watch     # fica em loop (serviço/daemon)
#     sh thermal-guard.sh status    # mostra zonas, limite, inclinação e projeção
#     sh thermal-guard.sh off       # solta o teto e desfaz
#
#  Tudo reversível: o teto original de cada núcleo é guardado antes de baixar.
# =============================================================================

# diretório próprio: NÃO usa DIR, que é do chamador quando este script é
# carregado como biblioteca (TG_LIB=1) para aproveitar só as funções.
TG_SELF="$(cd "$(dirname "$0")" && pwd)"
[ -n "$TG_LIB" ] || . "$TG_SELF/common.sh"

scope_begin thermal-guard

TG_DIR="$ST/thermal"
mkdir -p "$TG_DIR" 2>/dev/null
HIST="$TG_DIR/hist"          # histórico "epoch temp_mc" para a inclinação
ORIG="$TG_DIR/orig"          # teto original de cada núcleo (para soltar)
THROTTLED="$TG_DIR/throttled" # marcador: estamos com o teto baixado

# --- parâmetros (ajustáveis por ambiente, com padrão seguro) ------------------
# TG_LEAD: quantos segundos de antecedência para agir.
# TG_RELEASE: com quantos graus ABAIXO do limite soltar (histerese).
# TG_CAP_PCT: teto de frequência aplicado quando ameaça (70% do máximo).
# TG_MAX_C: limite de segurança, usado só quando o kernel não expõe trip point.
TG_LEAD="${TG_LEAD:-8}"
TG_RELEASE="${TG_RELEASE:-6}"
TG_CAP_PCT="${TG_CAP_PCT:-70}"
TG_MAX_C="${TG_MAX_C:-45}"
# Bases configuráveis: o padrão é o /sys real; os testes apontam para um /sys
# falso. Sem isso não dava para exercitar o laço sem um aparelho de verdade.
TG_SYS="${TG_SYS:-/sys/class/thermal}"
TG_CPU="${TG_CPU:-/sys/devices/system/cpu}"

# --- leitura das zonas térmicas ----------------------------------------------
# tg_max_mc -> maior temperatura entre todas as zonas, em mili-graus (mC), ou -1.
# Normaliza zonas que reportam em décimos de grau (valor < 1000).
tg_max_mc() {
    best=-1
    for z in "$TG_SYS"/thermal_zone*; do
        [ -d "$z" ] || continue
        t="$(sh_get "cat $z/temp" 2>/dev/null)"
        case "$t" in '' | *[!0-9-]*) continue ;; esac
        [ "$t" -le 0 ] 2>/dev/null && continue
        [ "$t" -lt 1000 ] && t=$((t * 100))
        [ "$t" -gt "$best" ] && best="$t"
    done
    printf '%s' "$best"
}

# tg_zones -> "tipo=°C" por zona (só as que o aparelho expõe)
tg_zones() {
    for z in "$TG_SYS"/thermal_zone*; do
        [ -d "$z" ] || continue
        t="$(sh_get "cat $z/temp" 2>/dev/null)"
        case "$t" in '' | *[!0-9-]*) continue ;; esac
        [ "$t" -le 0 ] 2>/dev/null && continue
        [ "$t" -lt 1000 ] && t=$((t * 100))
        ty="$(sh_get "cat $z/type" 2>/dev/null)"
        printf '%s=%s\n' "${ty:-zona}" "$((t / 1000))"
    done
}

# tg_trip_mc -> menor trip point (mC) que o KERNEL já usa como limite, ou vazio.
# É a linha de perigo real do aparelho — melhor que um número chutado.
tg_trip_mc() {
    best=""
    for t in "$TG_SYS"/thermal_zone*/trip_point_*_temp; do
        [ -r "$t" ] || continue
        v="$(sh_get "cat $t" 2>/dev/null)"
        case "$v" in '' | *[!0-9]*) continue ;; esac
        [ "$v" -le 0 ] && continue
        [ "$v" -gt 150000 ] && continue      # valor absurdo: ignora
        if [ -z "$best" ] || [ "$v" -lt "$best" ]; then best="$v"; fi
    done
    printf '%s' "$best"
}

# tg_limit_mc -> limite de trabalho: trip point do kernel, ou o padrão seguro.
tg_limit_mc() {
    lim="$(tg_trip_mc)"
    if [ -z "$lim" ]; then
        lim=$((TG_MAX_C * 1000))
    fi
    # não deixa o limite de trabalho passar do padrão quando o trip é muito alto:
    # agir antes do trip é o ponto; um trip de 100 °C não serve de aviso.
    padrao=$((TG_MAX_C * 1000))
    [ "$lim" -gt "$padrao" ] && lim="$padrao"
    printf '%s' "$lim"
}

# --- predição ----------------------------------------------------------------
# tg_slope -> inclinação em mC/s, pelas amostras do histórico (0 se não sobe).
tg_slope() {
    [ -s "$HIST" ] || { printf '0'; return; }
    tail -6 "$HIST" > "$TG_DIR/.h" 2>/dev/null
    awk '
        NR==1 { t0=$1; v0=$2; next }
        { t1=$1; v1=$2 }
        END {
            if (t1 > t0) printf "%d", (v1 - v0) / (t1 - t0);
            else printf "0";
        }' "$TG_DIR/.h" 2>/dev/null
    rm -f "$TG_DIR/.h" 2>/dev/null
}

# tg_eta <temp_mc> <slope_mc_s> <limite_mc> -> segundos até cruzar o limite.
#   -1 = não está subindo (ou dado inválido); 0 = já cruzou.
# É função pura: mesma entrada, mesma saída — por isso dá para testar a conta.
tg_eta() {
    t="$1"; s="$2"; lim="$3"
    case "$t" in '' | *[!0-9-]*) printf '%s' -1; return ;; esac
    case "$s" in '' | *[!0-9-]*) printf '%s' -1; return ;; esac
    case "$lim" in '' | *[!0-9-]*) printf '%s' -1; return ;; esac
    [ "$t" -ge "$lim" ] && { printf '%s' 0; return; }
    [ "$s" -le 0 ] && { printf '%s' -1; return; }
    printf '%s' $(((lim - t) / s))
}

# --- ação --------------------------------------------------------------------
# tg_apply_cap -> baixa o teto de frequência de cada núcleo para TG_CAP_PCT% do
# máximo, guardando o valor original (uma vez só, sem empilhar) para soltar.
tg_apply_cap() {
    pct="$1"
    : > "$ORIG" 2>/dev/null
    n=0
    for c in "$TG_CPU"/cpu*/cpufreq/scaling_max_freq; do
        [ -w "$c" ] || continue
        max="$(sh_get "cat ${c%scaling_max_freq}cpuinfo_max_freq" 2>/dev/null)"
        cur="$(sh_get "cat $c" 2>/dev/null)"
        case "$max" in '' | *[!0-9]*) continue ;; esac
        case "$cur" in '' | *[!0-9]*) continue ;; esac
        novo=$((max * pct / 100))
        [ "$novo" -ge "$cur" ] && continue          # já está abaixo do alvo
        printf '%s %s\n' "$c" "$cur" >> "$ORIG"
        sh_run "echo '$novo' > '$c' 2>/dev/null" >/dev/null
        n=$((n + 1))
    done
    if [ "$n" -gt 0 ]; then
        bkp_raw "# thermal-guard: teto baixado a ${pct}%"
        # a reversão geral também solta o teto (além do `off` deste script)
        while IFS=' ' read -r c v; do
            bkp_raw "echo '$v' > '$c' 2>/dev/null"
        done < "$ORIG"
        : > "$THROTTLED" 2>/dev/null
    fi
    printf '%s' "$n"
}

# tg_release -> devolve o teto original de cada núcleo e limpa o marcador.
tg_release() {
    [ -s "$ORIG" ] || { rm -f "$THROTTLED" 2>/dev/null; return 0; }
    while IFS=' ' read -r c v; do
        [ -n "$c" ] && sh_run "echo '$v' > '$c' 2>/dev/null" >/dev/null
    done < "$ORIG"
    rm -f "$ORIG" "$THROTTLED" 2>/dev/null
}

# --- avaliação (uma passada) --------------------------------------------------
# tg_once -> mede, registra no histórico e decide. Devolve nada; escreve o estado.
tg_once() {
    mc="$(tg_max_mc)"
    [ "$mc" -le 0 ] 2>/dev/null && { echo "sem leitura térmica neste aparelho"; return 0; }
    now="$(date +%s 2>/dev/null)"
    [ -n "$now" ] || now="$(sh_get 'date +%s')"
    case "$now" in '' | *[!0-9]*) now=0 ;; esac
    echo "$now $mc" >> "$HIST"
    # histórico curto: só as últimas 40 amostras
    tail -40 "$HIST" > "$TG_DIR/.h2" 2>/dev/null && mv "$TG_DIR/.h2" "$HIST" 2>/dev/null

    lim="$(tg_limit_mc)"
    sl="$(tg_slope)"
    eta="$(tg_eta "$mc" "$sl" "$lim")"

    acao="nada"
    if [ "$eta" -ge 0 ] 2>/dev/null && [ "$eta" -le "$TG_LEAD" ]; then
        # vai cruzar o limite dentro do tempo de antecedência: age agora
        if [ ! -f "$THROTTLED" ]; then
            n="$(tg_apply_cap "$TG_CAP_PCT")"
            if [ "$n" -gt 0 ] 2>/dev/null; then
                acao="teto da CPU a ${TG_CAP_PCT}% (faltavam ${eta}s para ${lim}mC)"
            else
                acao="ameaça detectada, mas nenhum núcleo aceitou o teto"
            fi
        else
            acao="já contido (${eta}s para o limite)"
        fi
    elif [ -f "$THROTTLED" ]; then
        # solta só quando esfriar de verdade (histerese)
        solta=$((lim - TG_RELEASE * 1000))
        if [ "$mc" -le "$solta" ] 2>/dev/null; then
            tg_release
            acao="esfriou: teto da CPU devolvido"
        else
            acao="contido (esperando esfriar até $((solta / 1000))°C)"
        fi
    fi

    printf '%s\n' "$acao"
}

# --- comandos ----------------------------------------------------------------
cmd_status() {
    printf '  %s▸%s  %sThermal Guard%s\n' "$C_G" "$C_R" "$C_A" "$C_R"
    mc="$(tg_max_mc)"
    if [ "$mc" -le 0 ] 2>/dev/null; then
        echo "  este aparelho não expõe zonas térmicas legíveis"
        return 0
    fi
    lim="$(tg_limit_mc)"
    sl="$(tg_slope)"
    eta="$(tg_eta "$mc" "$sl" "$lim")"
    printf '   %-14s %s °C\n' "agora" "$((mc / 1000))"
    printf '   %-14s %s °C\n' "limite" "$((lim / 1000))"
    printf '   %-14s %s mC/s\n' "inclinação" "$sl"
    if [ "$eta" -lt 0 ] 2>/dev/null; then
        printf '   %-14s estável/descendo\n' "projeção"
    else
        printf '   %-14s cruza em %ss\n' "projeção" "$eta"
    fi
    [ -f "$THROTTLED" ] && printf '   %-14s %sATIVO%s (teto a %s%%)\n' "estado" "$C_Y" "$C_R" "$TG_CAP_PCT" \
        || printf '   %-14s normal\n' "estado"
    echo
    echo "  zonas:"
    tg_zones | sort -t= -k2 -n -r | head -8 | while IFS='=' read -r z t; do
        printf '   %-18s %s °C\n' "$z" "$t"
    done
}

cmd_watch() {
    printf '  %s▸%s  thermal-guard em loop (a cada %ss)\n' "$C_G" "$C_R" "${TG_INTERVAL:-5}"
    while :; do
        [ -f "$TG_DIR/stop" ] && { echo "parado"; return 0; }
        saida="$(tg_once)"
        [ -n "$saida" ] && printf '  [%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$saida"
        sleep "${TG_INTERVAL:-5}" 2>/dev/null || sleep 5
    done
}

# --- comandos ----------------------------------------------------------------
# TG_LIB=1: carregado por outro script só para usar as funções (sem despachar).
if [ -z "$TG_LIB" ]; then
case "$1" in
    "" | status) cmd_status ;;
    once)        tg_once ;;
    watch)       cmd_watch ;;
    off)         tg_release; echo "thermal-guard desligado (teto devolvido)" ;;
    *)           echo "uso: thermal-guard.sh [status|once|watch|off]" ;;
esac
fi
