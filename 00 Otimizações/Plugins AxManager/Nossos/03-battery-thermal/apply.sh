#!/system/bin/sh
# =============================================================================
#  apply.sh - Aplica a economia uma vez.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
boot_wait
apply_battery
echo "Economia aplicada. Temp: $(read_temp_c)°C"
