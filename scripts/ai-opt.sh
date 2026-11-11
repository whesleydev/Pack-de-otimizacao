#!/system/bin/sh
# =============================================================================
#  ai-opt.sh - otimizador que APRENDE no aparelho (bandit contextual local).
#
#  O que este script é, sem enfeite: um bandit contextual (multi-armed bandit)
#  rodando 100% no aparelho. Ele não é uma rede neural e não precisa ser — para
#  escolher ENTRE POUCAS ações com feedback que se mede, um bandit aprende mais
#  rápido, com menos bateria e sem baixar modelo nenhum.
#
#  O ciclo é fechado e medido de verdade:
#     1) MEDE o estado atual (bench.sh collect) e reduz a um CONTEXTO grosso
#        (bateria baixa/média/alta, frio/ok/quente, carga baixa/média/alta);
#     2) ESCOLHE uma ação (competitivo | fluido | economico | nada) com
#        exploração UCB — testa o que ainda não conhece, explora o que vence;
#     3) APLICA a ação (profiles.sh apply <modo>);
#     4) MEDE de novo depois de assentar;
#     5) ATUALIZA o modelo com a RECOMPENSA = ganho da função-objetivo.
#
#  Função-objetivo (o que é "melhor"): RAM livre e refresh CONTAM A FAVOR;
#  temperatura e load average CONTAM CONTRA. É isso que evita o clássico "o
#  aparelho ficou rápido e fervendo" — o calor entra na conta como custo.
#
#  Tudo local: o modelo fica em ~/.packotm/ai/model. Nada sai do aparelho.
#
#  Uso:
#     sh ai-opt.sh apply [perfil]   # um ciclo: mede, decide, aplica, mede, aprende
#     sh ai-opt.sh train [n]        # roda n ciclos (padrão 3)
#     sh ai-opt.sh predict          # só mostra a ação escolhida agora (não aplica)
#     sh ai-opt.sh status           # modelo aprendido (melhor ação por contexto)
#     sh ai-opt.sh reset            # esquece tudo
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
[ -n "$AI_LIB" ] || . "$DIR/common.sh"
scope_begin ai-opt

AI_ST="$ST/ai"
mkdir -p "$AI_ST" 2>/dev/null
AI_MODEL="$AI_ST/model"      # <contexto> <acao> <n> <soma_recompensa>
AI_LOG="$AI_ST/log"          # histórico legível das decisões
AI_SETTLE="${AI_SETTLE:-15}" # segundos de assentamento antes da 2ª medição
AI_EXPLORE="${AI_EXPLORE:-50}" # constante de exploração do UCB (quanto ousar)

# ações possíveis: os modos reais do pack + "nada" (linha de base honesta).
AI_ACTIONS="${AI_ACTIONS:-competitivo fluido economico nada}"

# --- leitura de métricas (formato do bench.sh: chave=valor) -------------------
ai_val() {  # ai_val <arquivo> <chave>
    [ -f "$1" ] || return 0
    sed -n "s/^$2=//p" "$1" 2>/dev/null | tail -1
}

# ai_band <valor> <corte_baixo> <corte_alto> -> low|mid|high ("" vira mid)
ai_band() {
    v="$1"
    case "$v" in '' | *[!0-9.]*) printf 'mid'; return ;; esac
    awk -v v="$v" -v lo="$2" -v hi="$3" 'BEGIN{
        if (v < lo) print "low"; else if (v >= hi) print "high"; else print "mid";
    }'
}

# ai_ctx <arquivo> -> contexto grosso "b..|t..|l.."
# Contexto grosso DE PROPÓSITO: fino demais nunca repete e o aprendizado não
# acontece. Três eixos de três faixas = 27 estados, cabe em poucos ciclos.
ai_ctx() {
    lvl="$(ai_val "$1" bat_level)"
    tmp="$(ai_val "$1" bat_temp_c)"
    load="$(ai_val "$1" loadavg)"
    printf 'b%s|t%s|l%s' \
        "$(ai_band "$lvl" 25 70)" \
        "$(ai_band "$tmp" 36 42)" \
        "$(ai_band "$load" 1.5 4)"
}

# ai_score <arquivo> -> função-objetivo (inteiro). Maior = melhor.
# RAM e refresh ajudam; temperatura e load custam. É a mesma régua para todas as
# ações, então comparar recompensas entre elas faz sentido.
ai_score() {
    ram="$(ai_val "$1" ram_livre_mb)"
    hz="$(ai_val "$1" refresh_hz)"
    tmp="$(ai_val "$1" bat_temp_c)"
    ld="$(ai_val "$1" loadavg)"
    # `load` é builtin do gawk: usar como nome de variável aborta o programa no
    # awk do Ubuntu/CI (no mawk do aparelho passa). Por isso a variável é `ld`.
    awk -v ram="${ram:-0}" -v hz="${hz:-0}" -v tmp="${tmp:-0}" -v ld="${ld:-0}" 'BEGIN{
        printf "%d", ram + hz * 10 - tmp * 10 - ld * 100;
    }'
}

# ai_reward <antes> <depois> -> ganho da função-objetivo (inteiro)
ai_reward() {
    printf '%s' "$(( $(ai_score "$2") - $(ai_score "$1") ))"
}

# --- modelo ------------------------------------------------------------------
# ai_stats <ctx> <acao> -> "n soma" (0 0 quando nunca foi tentada)
ai_stats() {
    if [ -f "$AI_MODEL" ]; then
        awk -v c="$1" -v a="$2" '$1==c && $2==a { n+=$3; s+=$4 } END { print n+0, s+0 }' "$AI_MODEL"
    else
        echo "0 0"
    fi
}

# ai_total <ctx> -> total de tentativas naquele contexto
ai_total() {
    if [ -f "$AI_MODEL" ]; then
        awk -v c="$1" '$1==c { n+=$3 } END { print n+0 }' "$AI_MODEL"
    else
        echo 0
    fi
}

# ai_update <ctx> <acao> <recompensa>
ai_update() {
    n="$(ai_stats "$1" "$2" | cut -d' ' -f1)"
    s="$(ai_stats "$1" "$2" | cut -d' ' -f2)"
    tmp="$AI_MODEL.tmp"
    if [ -f "$AI_MODEL" ]; then
        grep -v "^$1 $2 " "$AI_MODEL" > "$tmp" 2>/dev/null || : > "$tmp"
    else
        : > "$tmp"
    fi
    printf '%s %s %s %s\n' "$1" "$2" "$((n + 1))" "$((s + $3))" >> "$tmp"
    mv "$tmp" "$AI_MODEL" 2>/dev/null
}

# ai_pick <ctx> -> ação escolhida. Média observada + bônus de exploração (UCB):
# uma ação nunca tentada ganha bônus alto (é explorada uma vez); depois vale a
# média real, com bônus decrescente conforme as tentativas aumentam.
ai_pick() {
    ctx="$1"
    [ -f "$AI_MODEL" ] || : > "$AI_MODEL"
    awk -v MODEL="$AI_MODEL" -v ctx="$ctx" -v acts="$AI_ACTIONS" -v C="$AI_EXPLORE" '
        BEGIN {
            # lê o modelo UMA vez (o arquivo não rebobina entre as ações)
            while ((getline line < MODEL) > 0) {
                split(line, f, " ")
                if (f[1] != ctx) continue
                n[f[2]] += f[3]; s[f[2]] += f[4]; N += f[3]
            }
            close(MODEL)
            split(acts, A, " ")
            best = ""; bestv = -1e18
            for (i = 1; i <= length(A); i++) {
                a = A[i]
                if (n[a] == 0) {
                    v = 1e9            # nunca tentada: explora primeiro
                } else {
                    v = s[a] / n[a] + C * sqrt(log(N + 1) / n[a])
                }
                if (v > bestv) { bestv = v; best = a }
            }
            print best
        }'
}

# --- ciclo -------------------------------------------------------------------
# ai_measure <nome> -> coleta as métricas para ~/.packotm/bench/<nome>.txt e
# imprime o caminho. Reusa o bench.sh (não duplica a coleta).
ai_measure() {
    OTM_NO_COLOR=1 sh "$DIR/bench.sh" save "$1" >/dev/null 2>&1
    printf '%s' "$ST/bench/$1.txt"
}

# ai_apply_action <acao> -> aplica de verdade; "nada" é a linha de base.
ai_apply_action() {
    case "$1" in
        nada) return 0 ;;
        *)
            OTM_NO_COLOR=1 sh "$DIR/profiles.sh" apply "$1" >/dev/null 2>&1
            return $?
            ;;
    esac
}

# ai_cycle [acao_forcada] -> um ciclo completo. Imprime o que decidiu e aprendeu.
ai_cycle() {
    forcada="$1"
    antes="$(ai_measure ai-antes)"
    ctx="$(ai_ctx "$antes")"
    acao="$forcada"
    [ -n "$acao" ] || acao="$(ai_pick "$ctx")"
    [ -n "$acao" ] || acao="nada"

    s0="$(ai_score "$antes")"
    say "contexto $ctx · ação: $acao"
    ai_apply_action "$acao"
    sleep "$AI_SETTLE" 2>/dev/null || sleep 0

    depois="$(ai_measure ai-depois)"
    s1="$(ai_score "$depois")"
    r="$(ai_reward "$antes" "$depois")"
    ai_update "$ctx" "$acao" "$r"

    if [ "$r" -gt 0 ] 2>/dev/null; then
        printf '   %bganho%b  %s → %s  (%+d)\n' "$C_G" "$C_R" "$s0" "$s1" "$r"
    elif [ "$r" -lt 0 ] 2>/dev/null; then
        printf '   %bcusto%b  %s → %s  (%+d)\n' "$C_Y" "$C_R" "$s0" "$s1" "$r"
    else
        printf '   neutro  %s → %s  (%+d)\n' "$s0" "$s1" "$r"
    fi
    printf '%s %s %s %s\n' "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" "$ctx" "$acao" "$r" >> "$AI_LOG" 2>/dev/null
}

# --- comandos ----------------------------------------------------------------
cmd_predict() {
    antes="$(ai_measure ai-predict)"
    ctx="$(ai_ctx "$antes")"
    acao="$(ai_pick "$ctx")"
    say "contexto agora: $ctx"
    printf '   ação escolhida: %s%s%s\n' "$C_A" "$acao" "$C_R"
    n="$(ai_total "$ctx")"
    printf '   este contexto já foi visto %s vez(es)\n' "$n"
}

cmd_status() {
    printf '  %s▸%s  %sIA local (bandit contextual)%s\n' "$C_G" "$C_R" "$C_A" "$C_R"
    if [ ! -s "$AI_MODEL" ]; then
        echo "  ainda não aprendeu nada — rode: ai-opt.sh apply"
        return 0
    fi
    ciclos="$(awk '{n+=$3} END{print n+0}' "$AI_MODEL" 2>/dev/null)"
    printf '   %-20s %s\n' "ciclos aprendidos" "$ciclos"
    printf '   %-20s %s\n' "contextos distintos" "$(awk '{print $1}' "$AI_MODEL" | sort -u | wc -l | tr -d ' ')"
    printf '   %-20s %s\n' "ações" "$AI_ACTIONS"
    echo
    echo "  melhor ação por contexto (média de recompensa):"
    awk '
        { n[$1" "$2] += $3; s[$1" "$2] += $4; ctx[$1] = 1 }
        END {
            for (c in ctx) {
                best = ""; bestv = -1e18
                for (k in n) {
                    split(k, p, " ")
                    if (p[1] != c) continue
                    avg = s[k] / n[k]
                    if (avg > bestv) { bestv = avg; best = p[2] }
                }
                printf "   %-14s %s  (%+.0f em %d tentativas)\n", c, best, bestv, n[c" "best]
            }
        }' "$AI_MODEL" | sort
}

cmd_reset() {
    rm -f "$AI_MODEL" "$AI_LOG" 2>/dev/null
    say "modelo local apagado (o aparelho vai reaprender do zero)"
}

# AI_LIB=1: carregado por outro script/teste só para usar as funções (sem despachar).
if [ -z "$AI_LIB" ]; then
case "$1" in
    "" | apply) ai_cycle "$2" ;;
    train)
        n="${2:-3}"
        case "$n" in '' | *[!0-9]*) n=3 ;; esac
        say "treinando com $n ciclo(s)"
        i=1
        while [ "$i" -le "$n" ]; do
            printf '  %b·%b ciclo %s/%s\n' "$C_D" "$C_R" "$i" "$n"
            ai_cycle
            i=$((i + 1))
        done
        cmd_status
        ;;
    predict) cmd_predict ;;
    status)  cmd_status ;;
    reset)   cmd_reset ;;
    *)       echo "uso: ai-opt.sh [apply|train [n]|predict|status|reset]" ;;
esac
fi
