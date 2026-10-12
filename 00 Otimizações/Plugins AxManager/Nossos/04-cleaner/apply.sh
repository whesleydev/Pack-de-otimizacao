#!/system/bin/sh
# =============================================================================
#  apply.sh - Roda a limpeza uma vez.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
boot_wait
run_clean
echo "Limpeza feita. RAM livre: $(free_ram_mb) MB"
