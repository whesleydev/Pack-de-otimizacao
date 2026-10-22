#!/system/bin/sh
# =============================================================================
#  NÍVEL 2 · Entry point (sh + Shizuku)
#  Atalho curto para o MENU-MESTRE (../scripts/pack.sh), que gerencia tudo.
#  Você não precisa decorar caminho de nada — só rodar este arquivo.
#
#  Uso:
#     sh run.sh              # abre o menu-mestre
#     sh run.sh status       # estado do aparelho
#     sh run.sh apply        # aplica o pack recomendado
#     sh run.sh restore      # reverte tudo
#     sh run.sh headshot     # perfil de sensibilidade
#     sh run.sh debloat on medio
#     sh run.sh save         # snapshot do estado atual
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"

# localiza a pasta do motor (scripts/). O layout varia: no repositório o run.sh
# fica em "00 Otimizações/Scripts SH/", então scripts/ está dois níveis acima;
# se o pack for copiado para outro lugar, tenta um nível acima também.
SCRIPTS=""
for cand in "${OTM_SCRIPTS:-}" "$DIR/../../scripts" "$DIR/../scripts"; do
    [ -n "$cand" ] && [ -f "$cand/pack.sh" ] && { SCRIPTS="$cand"; break; }
done
[ -n "$SCRIPTS" ] || { echo "não achei scripts/pack.sh (defina OTM_SCRIPTS)" >&2; exit 1; }

exec sh "$SCRIPTS/pack.sh" "$@"
