#!/system/bin/sh

# ── Phoenix v2.1 — Uninstall Script ──────────────────────────────────────────
# Restaura valores predeterminados del sistema al desinstalar el módulo.

alias STS="settings"
alias C="cmd"

# Cancelar notificación persistente del servicio si existe
C notification cancel 'PhoenixBoost' 2>/dev/null

# Restaurar refresh rate al valor mínimo (sin boost)
STS put system peak_refresh_rate 60 2>/dev/null
STS put system min_refresh_rate 60 2>/dev/null

# Restaurar escalas de animación a valores normales
STS put global animator_duration_scale 1.0 2>/dev/null
STS put global transition_animation_scale 1.0 2>/dev/null
STS put global window_animation_scale 1.0 2>/dev/null

# Eliminar configuración guardada en Settings globales
STS delete global phoenix3_PEAK_RATE 2>/dev/null
STS delete global phoenix3_MIN_RATE 2>/dev/null
STS delete global phoenix3_SLEEP_INTERVAL 2>/dev/null
STS delete global phoenix3_AUTO_BOOST 2>/dev/null
STS delete global phoenix3_DNS_SERVER 2>/dev/null
STS delete global phoenix3_THERMAL_MODE 2>/dev/null
STS delete global phoenix3_GAMELIST 2>/dev/null

# Restaurar thermal service a modo normal (0 = sin override)
C thermalservice override-status 0 2>/dev/null

# Limpiar archivos temporales
rm -f /data/local/tmp/.phoenix_dir 2>/dev/null
rm -f /data/local/tmp/.phoenix_state 2>/dev/null
rm -f /data/local/tmp/.phoenix_pid 2>/dev/null
rm -f /data/local/tmp/.phoenix_game 2>/dev/null
rm -f /data/local/tmp/.phoenix_gamelist 2>/dev/null

# ── Notificación de desinstalación (estilo GoodPing) ─────────────────────────
cmd notification post -S bigtext -t 'Phoenix 🔥' 'PhoenixBoost' " Module uninstalled 🛑"
