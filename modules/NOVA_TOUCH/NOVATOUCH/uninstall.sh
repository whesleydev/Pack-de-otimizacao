#!/system/bin/sh
echo "NOVA TOUCH v1.0"
echo "Uninstall helper: removing only NOVA TOUCH owned temporary marker."
rm -f /data/local/tmp/touch_tweak_install_date 2>/dev/null
echo "Done."
exit 0
