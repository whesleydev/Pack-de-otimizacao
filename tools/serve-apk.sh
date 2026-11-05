#!/bin/sh
# Sobe o servidor de download do APK (pasta serve/) nas duas portas do ambiente.
# Uso: sh tools/serve-apk.sh
# O servidor morre quando o ambiente reinicia; rode de novo para religar.
DIR="$(cd "$(dirname "$0")/.." && pwd)/serve"
for p in 12000 12001; do
    if curl -sf -o /dev/null "http://localhost:$p/" 2>/dev/null; then
        echo "porta $p: já no ar"
        continue
    fi
    nohup python3 -m http.server "$p" --bind 0.0.0.0 --directory "$DIR" > "/tmp/serve-$p.log" 2>&1 &
    echo "porta $p: subiu (pid $!)"
done
sleep 1
for p in 12000 12001; do
    printf 'porta %s: ' "$p"
    curl -s -o /dev/null -w 'HTTP %{http_code}\n' "http://localhost:$p/" || echo "fora"
done
