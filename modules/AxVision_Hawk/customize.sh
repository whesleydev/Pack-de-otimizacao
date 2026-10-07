#!/system/bin/sh

bin_32_c="AxVisionC_arm32"
bin_32_d="AxVisionD_arm32"

bin_64_c="AxVisionC_arm64"
bin_64_d="AxVisionD_arm64"

ABI=$(getprop ro.product.cpu.abi)
if [[ $ABI == "arm64-v8a" ]]; then
  rm -f "$MODPATH/system/bin/$bin_32_c"
  rm -f "$MODPATH/system/bin/$bin_32_d"
  mv -f "$MODPATH/system/bin/$bin_64_d" "$MODPATH/system/bin/visionD"
  mv -f "$MODPATH/system/bin/$bin_64_c" "$MODPATH/system/bin/vision"
  chmod 777 "$MODPATH/system/bin/visionD"
  chmod 777 "$MODPATH/system/bin/vision"
elif [[ $ABI == "armeabi-v7a" ]]; then
  rm -f "$MODPATH/system/bin/$bin_64_c"
  rm -f "$MODPATH/system/bin/$bin_64_d"
  mv -f "$MODPATH/system/bin/$bin_32_d" "$MODPATH/system/bin/visionD"
  mv -f "$MODPATH/system/bin/$bin_32_c" "$MODPATH/system/bin/vision"
  chmod 777 "$MODPATH/system/bin/visionD"
  chmod 777 "$MODPATH/system/bin/vision"
fi


echo "[-]  AxVision v1052-180926-S"
echo "----------------------------------------"
echo "  - Author     : Reiieja"
echo "  - Build Date : 2026-08-18"
echo "  - Version    : v1052-180926-S"
echo "  - Engine     : Stable Builder"
echo "  - Credits    : @reljawa | @dcx400 | @HoyoSlave | @Kzuyoo"
echo "----------------------------------------"
echo "[-] Enjoy__"
sleep 1