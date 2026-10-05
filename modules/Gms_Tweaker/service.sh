while true;do eval "$(dumpsys package com.google.android.gms|grep filter|cut -f10 -d\ |sed 's/^/sleep 1\;cmd activity force-stop /g')";done>/dev/null 2>&1&


 am start -a AxManager.TOAST -e text "GMS TWEAKER [ Installed ]"
