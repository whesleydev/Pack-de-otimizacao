#!/system/bin/sh
# Ruta donde AxManager suele montar o ejecutar los scripts del módulo
MODDIR=${0%/*}

# Ejecutar el script principal
sh "$MODDIR/run.sh"
