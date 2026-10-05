#!/system/bin/sh
MODPATH="${0%/*}"
case "$1" in
    run|optimize) sh "$MODPATH/action.sh" run ;;
    heavy)        sh "$MODPATH/action.sh" heavy ;;
    report)       sh "$MODPATH/action.sh" report ;;
    all)          sh "$MODPATH/action.sh" all ;;
    status|info)  sh "$MODPATH/action.sh" status ;;
    *)
        echo "VOID BATTERY v9.1-fix"
        echo "Usage: {run|heavy|report|all|status}"
        ;;
esac
