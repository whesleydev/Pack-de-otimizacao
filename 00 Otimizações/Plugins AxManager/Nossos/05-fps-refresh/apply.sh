#!/system/bin/sh
# =============================================================================
#  apply.sh - Aplica FPS/refresh uma vez.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
boot_wait
apply_fps
echo "FPS/refresh aplicado (painel: $(panel_max_hz)Hz)"
