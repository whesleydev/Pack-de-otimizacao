#!/system/bin/sh
# =============================================================================
#  pack.sh (raiz) - atalho para o MENU-MESTRE do Pack de Otimização.
#  Roda de qualquer lugar:  sh pack.sh            (menu interativo)
#                           sh pack.sh status      (estado do aparelho)
#                           sh pack.sh apply       (aplica o recomendado)
#                           sh pack.sh restore     (reverte tudo)
#  O motor fica em scripts/pack.sh.
# =============================================================================
DIR="$(cd "$(dirname "$0")" && pwd)"
exec sh "$DIR/scripts/pack.sh" "$@"
