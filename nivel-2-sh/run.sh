#!/system/bin/sh
# =============================================================================
#  NÍVEL 2 · Entry point (sh + Shizuku)
#  Atalho que roda o menu do pack usando Shizuku (rish) ou root, sem precisar
#  decorar caminhos. O motor fica em ../scripts/.
#
#  Uso:
#     sh run.sh            # abre o menu
#     sh run.sh all        # aplica tudo
#     sh run.sh headshot   # perfil de sensibilidade
#     sh run.sh save       # snapshot do estado atual
#     sh run.sh restore    # volta o último snapshot
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
SCRIPTS="$DIR/../scripts"

# prefere Shizuku; cai para root se não houver rish
if command -v rish >/dev/null 2>&1; then
    OTM_MODE=rish
elif command -v su >/dev/null 2>&1 && [ "$(id -u 2>/dev/null)" != "0" ]; then
    OTM_MODE=su
else
    OTM_MODE=local
fi
export OTM_MODE

case "$1" in
    ""|menu)  exec sh "$SCRIPTS/menu.sh" ;;
    all)      exec sh "$SCRIPTS/adb-tweaks.sh" all ;;
    restore)  exec sh "$SCRIPTS/snapshot.sh" restore latest ;;
    save)     exec sh "$SCRIPTS/snapshot.sh" save ;;
    fluidez)  exec sh "$SCRIPTS/adb-tweaks.sh" fluidez ;;
    game)     exec sh "$SCRIPTS/game-per-app.sh" "${2:-list}" "${3:-}" "${4:-}" ;;
    status)   exec sh "$SCRIPTS/adb-tweaks.sh" raw "dumpsys battery | grep -E 'level|temperature'" ;;
    headshot|spray|sniper|speed|balanced)
              exec sh "$SCRIPTS/ff-touch.sh" "$1" ;;
    *)        exec sh "$SCRIPTS/adb-tweaks.sh" "$@" ;;
esac
