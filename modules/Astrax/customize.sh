#!/system/bin/sh
chip=$(getprop ro.soc.model)
dev=$(getprop ro.product.model)
[ -z "$chip" ] && CHIPSET=$(getprop ro.board.platform)
sed -i "s|∆|$chip|g" $MODPATH/module.prop
[ -z "$dev" ] && DEVICE=$(getprop ro.product.device)
sed -i "s|§|$dev|g" $MODPATH/module.prop
