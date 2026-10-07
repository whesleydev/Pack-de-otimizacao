#!/system/bin/sh
echo "--- [✓] Iniciando optimización universal ---"

# Limpieza segura de caché compatible con cualquier Android
sync
if [ -w /proc/sys/vm/drop_caches ]; then
    echo 3 > /proc/sys/vm/drop_caches
    echo "[✓] Caché liberada"
fi

# Aplicar modo rendimiento a los núcleos de CPU disponibles
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    if [ -w "$gov" ]; then
        echo performance > "$gov" 2>/dev/null
    fi
done
echo "[✓] CPU ajustada"

# Búsqueda dinámica y universal de GPU (compatible con Adreno, Mali u otros con devfreq)
for gpu_gov in /sys/class/kgsl/kgsl-3d0/devfreq/governor /sys/class/devfreq/*gpu*/governor /sys/class/devfreq/*mali*/governor; do
    if [ -w "$gpu_gov" ]; then
        echo performance > "$gpu_gov" 2>/dev/null
        echo "[✓] GPU optimizada"
        break
    fi
done

echo "--- [✓] Proceso finalizado ---"
