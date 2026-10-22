#!/system/bin/sh

# Copyright (C) 2024-2025 Kanao
# Licensed under the Apache License, Version 2.0
# See http://www.apache.org/licenses/LICENSE-2.0

# WebUI X
if pm path com.dergoogler.mmrl.wx >/dev/null 2>&1; then
    echo "[*] Start Open WebUI X.."
    am start -n "com.dergoogler.mmrl.wx/.ui.activity.webui.WebUIActivity" -e id "stellar" > /dev/null 2>&1
    exit 0 
fi
    
# KSU WebUI
if pm path io.github.a13e300.ksuwebui >/dev/null 2>&1; then
    echo "[*] Start Open WebUI on KSU Webui Standanlone.."
    am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "stellar" > /dev/null 2>&1
    exit 0
fi  	
    
# MMRL 
if pm path com.dergoogler.mmrl >/dev/null 2>&1; then
    echo "[*] Starting WebUI through MMRL..."
    am start -n "com.dergoogler.mmrl/.ui.activity.webui.WebUIActivity" -e MOD_ID "stellar" > /dev/null 2>&1
    exit 0
fi

# Case didn't have, Download manually
echo "[!] WebUI App is required for access feature.."
echo "[!] Without WebUI you lost many feature of Stellar.."
sleep 0.5
echo "[*] Try Open Playstore.."
echo "[*] Opening download webuix..."
sleep 0.8
am start -a android.intent.action.VIEW -d "https://play.google.com/store/apps/details?id=com.dergoogler.mmrl.wx" > /dev/null 2>&1

exit 0