#!/system/bin/sh
notif_run="running"
current_time=10m
# =========================================
#   AETERNUM AI ENGINE — ULTRA MODE (SAFE)
# =========================================

engine() {
  pkg="com.android.systemui"
  
  # ================= HEAVY APPS =================
  
  # ===================================================
  #              SYSTEMUI RAM SCANNER
  # ===================================================
  get_mem_sysui() {
      info=$(dumpsys meminfo $pkg | sed -n '/App Summary/,/Objects/p' | sed 's/://')
  
      get() { echo "$info" | grep -m1 "$1" | awk '{print $3}'; }
  
      java=$(get "Java Heap")
      native=$(get "Native Heap")
      code=$(get "Code")
      stack=$(get "Stack")
      graphics=$(get "Graphics")
      private=$(get "Private Other")
      system=$(get "System")
  
      for v in java native code stack graphics private system; do
          eval "[ -z \${$v} ] && $v=0"
      done
  
      total=$((java + native + code + stack + graphics + private + system))
      echo "$total"
  }
  
  toMB() { echo $(( $1 / 1024 )); }
  
  
  # ===================================================
  #              USER APP RAM SCANNER
  # ===================================================
  get_app_ram() {
      pkgname="$1"
      mem=$(dumpsys meminfo "$pkgname" 2>/dev/null | grep "TOTAL PSS" | awk '{print $3}')
      echo ${mem:-0}
  }
  
  USER_PKGS=$(pm list packages --user 0 | sed 's/package://')
  
  
  # ===================================================
  #                GMS RAM SCANNER
  # ===================================================
  get_gms_ram() {
      val=$(dumpsys meminfo com.google.android.gms 2>/dev/null | grep "TOTAL PSS" | awk '{print $3}')
      echo ${val:-0}
  }
  
  
  # ===================================================
  #                NOTIFICATION ON START
  # ===================================================
  if [[ $notif_run == "running" ]]; then
      cmd notification post -S bigtext -t 'VeuLexier Engine' \
      "noxg_engine_mode" \
      "VeuLexier Engine —  Smart Cache Cleaner Running..." >/dev/null 2>&1
      am start -a AxManager.TOAST -e text "Smart Cache Cleaner Running🚀"  >/dev/null 2>&1
      notif_run="stopped"
  fi
  
  
  # ===================================================
  #           RAM SCAN — BEFORE CLEANING
  # ===================================================
  echo ""
  echo "🔍 Mengambil RAM SystemUI (SEBELUM)..."
  before_sysui=$(get_mem_sysui)
  echo "SystemUI Sebelum : $(toMB $before_sysui) MB"
  
  echo ""
  echo "🔍 Menghitung RAM seluruh aplikasi user (SEBELUM)..."
  total_before_apps=0
  for p in $USER_PKGS; do
      val=$(get_app_ram "$p")
      total_before_apps=$((total_before_apps + val))
  done
  before_apps_MB=$((total_before_apps / 1024))
  echo "RAM User Apps Sebelum : ${before_apps_MB} MB"
  
  echo ""
  echo "🔍 Mengambil RAM GMS (SEBELUM)..."
  before_gms=$(get_gms_ram)
  before_gms_MB=$((before_gms / 1024))
  echo "RAM GMS Sebelum : ${before_gms_MB} MB"
  
  
  # ===================================================
  #               OPTIMIZATION STEPS
  # ===================================================
  echo ""
  echo "⚠ Killing cached apps..."
  cmd activity kill-all
  sleep 1
  
  # ======= DISABLE DROPBOX ========
  for a in $(cmd settings list secure | grep dropbox | cut -f1 -d=); do
      cmd settings delete secure "$a"
  done
  cmd dropbox restore-defaults
  cmd dropbox set-rate-limit "$(echo 2^62 | bc)"
  cmd settings put global dropbox_max_files 0
  
  # ======= DISABLE LOGGING ========
  for a in $(cmd package list packages --user 0 | grep -v ia.mo | cut -f2 -d:); do
      cmd package log-visibility --disable "$a"
  done
  
  for b in $(cmd settings list global | cut -f1 -d= | grep logging); do
      cmd settings put global "$b" 0
  done
  
  for c in $(cmd settings list secure | cut -f1 -d= | grep logging); do
      cmd settings put secure "$c" 0
  done
  
  for d in $(cmd settings list system | cut -f1 -d= | grep logging); do
      cmd settings put system "$d" 0
  done
  
  # ======= DISABLE TRACING ========
  atrace --async_stop >/dev/null
  cmd activity trace-ipc stop
  cmd window tracing stop
  echo 0 > /sys/kernel/tracing/tracing_on 2>/dev/null
  
  
  # ===================================================
  #            CLEAR CACHE (ALL)
  # ===================================================
  echo ""
  echo "🧹 Membersihkan cache semua aplikasi user..."
  
  for p in $USER_PKGS; do
      rm -rf /data/data/$p/cache/* 2>/dev/null
      rm -rf /data/data/$p/code_cache/* 2>/dev/null
  done
  
  # user_de dirs
  find /data/user_de/*/*/cache/* -delete 2>/dev/null
  find /data/user_de/*/*/code_cache/* -delete 2>/dev/null
  
  # sdcard dirs
  find /sdcard/Android/data/*/cache/* -delete 2>/dev/null
  
  # extra wipe
  rm -rf /sdcard/DCIM/.thumbnails/* 2>/dev/null
  rm -f /data/misc/logd/* 2>/dev/null
  
  # ================= GMS CACHE CLEANER ==================
  echo "🧹 Membersihkan cache Google Mobile Services..."
  rm -rf /data/data/com.google.android.gms/cache/* 2>/dev/null
  rm -rf /data/data/com.google.android.gms/code_cache/* 2>/dev/null
  rm -rf /data/user_de/0/com.google.android.gms/cache/* 2>/dev/null
  rm -rf /data/user_de/0/com.google.android.gms/code_cache/* 2>/dev/null
  
  pm trim-caches 1024G 2>/dev/null >&1
  sleep 1
  
  
  # ===================================================
  #           RAM SCAN — AFTER CLEANING
  # ===================================================
  echo ""
  echo "🔍 Mengambil RAM SystemUI (SESUDAH)..."
  after_sysui=$(get_mem_sysui)
  echo "SystemUI Sesudah : $(toMB $after_sysui) MB"
  
  echo ""
  echo "🔍 Menghitung RAM seluruh aplikasi user (SESUDAH)..."
  total_after_apps=0
  for p in $USER_PKGS; do
      val=$(get_app_ram "$p")
      total_after_apps=$((total_after_apps + val))
  done
  after_apps_MB=$((total_after_apps / 1024))
  echo "RAM User Apps Sesudah : ${after_apps_MB} MB"
  
  echo ""
  echo "🔍 Mengambil RAM GMS (SESUDAH)..."
  after_gms=$(get_gms_ram)
  after_gms_MB=$((after_gms / 1024))
  echo "RAM GMS Sesudah : ${after_gms_MB} MB"
  
  
  # ===================================================
  #                    FINAL REPORT
  # ===================================================
  echo ""
  cmd_log=$(echo "┌[-] SystemUI Sebelum : $(toMB $before_sysui) MB\n\
├[-] SystemUI Sesudah : $(toMB $after_sysui) MB\n\
├[-] Pengurangan Cache UI   : $(( (before_sysui/1024) - (after_sysui/1024) )) MB\n\
│\n\
├[-] User Apps Sebelum : ${before_apps_MB} MB\n\
├[-] User Apps Sesudah : ${after_apps_MB} MB\n\
├[-] Pengurangan Cache Apps   : $((before_apps_MB - after_apps_MB)) MB\n\
│\n\
├[-] GMS Sebelum : ${before_gms_MB} MB\n\
├[-] GMS Sesudah : ${after_gms_MB} MB\n\
└[-] Pengurangan Cache GMS   : $((before_gms_MB - after_gms_MB)) MB\n\
")
      
      cmd notification post -S bigtext \
          -t "VeuLexier System Cleaner🧹" \
          "cache_cleaner" \
          "$cmd_log"
}

while true; do
  top_pkg=$(dumpsys activity processes | grep top-activity | cut -d ':' -f4 | cut -d '/' -f1 | head -n 1)
  list_game=$(cat "${0%/*}/game.txt"; out="$(cmd game ext game_list | sed '1d' | awk '{print $2}')"; echo "$out" | grep -v 'list(RUS)' | grep -v 'GameClassifierImpl')

  #==== DETEKSI GAME =====
  if echo "$list_game" | grep -qw "$top_pkg"; then
    HEAVY_PKGS="
    com.google.android.googlequicksearchbox
    com.facebook.katana
    com.instagram.android
    com.tiktok.android
    com.snapchat.android
    com.netflix.mediaclient
    com.android.vending
    com.google.android.youtube
    com.android.chrome
    com.whatsapp.w4b
    com.whatsapp
    com.brave.browser
    com.lemon.lvoverseas
    org.telegram.messenger
    com.twitter.android
    "
    # Recompiler Game
    cmd package compile -m speed --secondary-dex -f $top_pkg
    cmd package compile -m everything-profile -f $top_pkg
    cmd package compile -m quicken -f $top_pkg
    
    # Add Driver Grafis
    cmd settings put global angle_gl_driver_selection_pkgs "$top_pkg"
    cmd settings put global angle_gl_driver_selection_values native
    cmd settings put global game_driver_opt_in_apps "$top_pkg"
    cmd settings put global updatable_driver_production_opt_in_apps "$top_pkg"
    
    for app in $HEAVY_PKGS; do
      am force-stop "$app" >/dev/null 2>&1
      cmd dropbox add-low-priority $app >/dev/null 2>&1
      am send-trim-memory $app RUNNING_LOW
      am send-trim-memory $app MODERATE
      am send-trim-memory $app COMPLETE
    done
    
    if [ "$notif_run" = "stopped" ]; then
       notif_run="running"
       cmd notification post -S bigtext -t 'VeuLexier Engine' \
       "noxg_engine_mode" \
       "VeuLexier Engine — Smart Cache Cleaner Stopped... 
Playing Game Detected" >/dev/null 2>&1
    fi

    sleep 5
  else
    engine
    lock_screen=$(dumpsys window displays 2>/dev/null | grep -q "mScreenOnFully=true" && echo "on" || echo "off")
    custom_time=$(settings get global custom_time_veu)
    if [ $lock_screen == "off" ]; then
      current_time=10s
    else 
      if [ -n $custom_time ]; then
         current_time=$custom_time
      else
         current_time=10m
      fi
    fi
    sleep "$current_time"
  fi  

data_dex_compiler=$(settings get global dex_veulexier_enable)
if [ -n data_dex_compiler ]; then
      if [ "$(date +%H)" = 03 ];then
        for a in $(cmd package list packages --user 0 -3|cut -f2 -d:);do
          cmd package compile -m space -f "$a" --secondary-dex --include-dependencies
          cmd package compile -m space-profile -f "$a" --secondary-dex --include-dependencies
          cmd package compile -m speed -f "$a" --primary-dex --include-dependencies
          cmd package compile -m speed-profile -f "$a" --primary-dex --include-dependencies
        done
        for b in $(cmd package list packages --user 0 -s|cut -f2 -d:);do
          cmd package compile -m space -f "$b" --full
          cmd package compile -m space-profile -f "$b" --full
        done
        cmd package bg-dexopt-job --enable
        cmd package bg-dexopt-job
      fi
      # recompile dex2oat in every 3am
fi

done