cmd appops set com.google.android.gms RUN_IN_BACKGROUND ignore
cmd appops set com.google.android.gms RUN_ANY_IN_BACKGROUND ignore
cmd appops set com.google.android.gms WAKE_LOCK ignore

for a in $(cmd package list packages gms|cut -f2 -d:);do for b in FOREGROUND_SERVICE_SPECIAL_USE INSTANT_APP_START_FOREGROUND RUN_ANY_IN_BACKGROUND RUN_IN_BACKGROUND START_FOREGROUND;do cmd appops set "$a" "$b" ignore;done;for c in $(cmd package list packages -U "$a"|cut -f3 -d:);do cmd netpolicy remove restrict-background-whitelist "$c";cmd netpolicy add restrict-background-blacklist "$c";cmd netpolicy remove app-idle-whitelist "$c";done;cmd activity service-restart-backoff disable "$a";cmd activity set-bg-restriction-level --user 0 "$a" hibernation;cmd activity set-foreground-service-delegate --user 0 "$a" stop;cmd activity set-inactive "$a" true;cmd activity set-standby-bucket "$a" 50;cmd app_hibernation set-state "$a" true;cmd deviceidle except-idle-whitelist "-$a";cmd deviceidle sys-whitelist "-$a";cmd deviceidle whitelist "-$a";cmd dropbox add-low-priority "$a";cmd package art clear-app-profiles "$a";cmd package log-visibility --disable "$a";cmd shortcut clear-shortcuts "$a";cmd tare set-vip 0 "$a" false;cmd usagestats clear-last-used-timestamps "$a";done&

for a in $(pm list packages | grep gms | cut -d: -f2); do 
  dumpsys deviceidle sys-whitelist -$a;
  dumpsys deviceidle whitelist -$a;
done