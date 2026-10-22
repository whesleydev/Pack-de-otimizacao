#!/system/bin/sh
# ===========================================================
# VOID TOUCH Ultra v5.1.0 — RESTORE
# ===========================================================

BACKUP="/sdcard/VOID_TOUCH/v5/backup/settings_backup.txt"

C='\033[36m'; G='\033[32m'; R='\033[31m'; Y='\033[33m'; B='\033[1m'; N='\033[0m'

printf '%b\n' ""
printf '%b\n' "${B}${C}  VOID TOUCH Ultra v5.1.0 -- RESTORE${N}"
printf '%s\n' "  ======================================"
printf '%s\n' ""

if [ ! -f "$BACKUP" ]; then
    printf '%b\n' "  ${R}[ERRO]${N} Backup nao encontrado: $BACKUP"
    exit 1
fi

_count=0; _fail=0

while IFS=' ' read -r _ns _key _val; do
    [ -z "$_ns" ] && continue
    [ -z "$_key" ] && continue
    if [ "$_val" = "null" ] || [ -z "$_val" ]; then
        settings delete "$_ns" "$_key" >/dev/null 2>&1
        printf '%b\n' "  ${G}[OK]${N}    $_ns.$_key -> (removido)"
        _count=$((_count+1))
    else
        if settings put "$_ns" "$_key" "$_val" >/dev/null 2>&1; then
            printf '%b\n' "  ${G}[OK]${N}    $_ns.$_key -> $_val"
            _count=$((_count+1))
        else
            printf '%b\n' "  ${R}[FAIL]${N}  $_ns.$_key -> $_val"
            _fail=$((_fail+1))
        fi
    fi
done < "$BACKUP"

printf '%s\n' ""
printf '%s\n' "  ======================================"
printf '%b\n' "  ${G}Restaurados:${N} $_count | ${R}Falhas:${N} $_fail"
printf '%s\n' "  ======================================"
printf '%s\n' ""
exit 0
