#!/system/bin/sh
# =============================================================================
#  service.sh - Loop infinito em segundo plano.
#  O gerenciador (AxManager/KernelSU/APatch/Magisk) chama este script no boot
#  e ele fica rodando, reafirmando os tweaks e fazendo manutenção.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"

save_default_config
boot_wait
log "service: iniciado (loop=${LOOP_INTERVAL}s clean=${CLEAN_INTERVAL}s)"

# aplica uma vez no boot
apply_core
kill_background_apps
clean_memory
log "service: boot aplicado (RAM livre: $(free_ram_mb) MB)"

# desativa gerenciadores de jogos de fabricante que atrapalham
pm disable-user --user 0 com.samsung.android.game.gos  >/dev/null 2>&1
pm disable-user --user 0 com.xiaomi.joyose               >/dev/null 2>&1
pm disable-user --user 0 com.motorola.gamemode           >/dev/null 2>&1

last_clean=0
while :; do
    sleep "$LOOP_INTERVAL"
    [ -f "$STATE/stop" ] && { log "service: stop pedido"; break; }

    apply_core
    apply_doze
    log "service: core reafirmado (RAM livre: $(free_ram_mb) MB)"

    now=$(date +%s)
    if [ $((now - last_clean)) -ge "$CLEAN_INTERVAL" ]; then
        kill_background_apps
        clean_memory
        last_clean=$now
        log "service: manutenção (RAM livre: $(free_ram_mb) MB)"
    fi
done
