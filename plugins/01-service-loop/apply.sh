#!/system/bin/sh
# =============================================================================
#  apply.sh - Aplica o pack UMA vez (chamado pelo customize.sh e action.sh).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
boot_wait
apply_core
apply_deep
kill_background_apps
clean_memory
apply_doze
log "apply: core aplicado (RAM livre: $(free_ram_mb) MB)"
echo "Pack aplicado. RAM livre: $(free_ram_mb) MB"
