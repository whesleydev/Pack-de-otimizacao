#!/system/bin/sh
# =============================================================================
#  build-modules.sh - Empacota cada módulo de modules/<nome> em releases/<nome>.zip
#  Uso: sh scripts/build-modules.sh
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
SRC="$ROOT/modules"
OUT="$ROOT/releases"
mkdir -p "$OUT"

have_zip=1
command -v zip >/dev/null 2>&1 || have_zip=0

printf '  Empacotando módulos de %s\n' "$SRC"
for d in "$SRC"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    [ "$name" = "README.md" ] && continue
    [ -f "$d/module.prop" ] || { printf '  · %s (sem module.prop) — ignorado\n' "$name"; continue; }

    if [ "$have_zip" = "1" ]; then
        ( cd "$d" && zip -rq "$OUT/$name.zip" . )
        printf '  ▸ releases/%s.zip\n' "$name"
    else
        # fallback sem o binário zip (usa python ou tar)
        if command -v python3 >/dev/null 2>&1; then
            python3 - "$d" "$OUT/$name.zip" <<'PY'
import sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, src))
PY
            printf '  ▸ releases/%s.zip\n' "$name"
        else
            printf '  ! %s — instale o zip ou python3\n' "$name"
        fi
    fi
done
printf '  pronto. zips em releases/\n'

# --- plugins do pack (níveis 3 e 4) -------------------------------------------
PLUG="$ROOT/plugins"
if [ -d "$PLUG" ]; then
    printf '  Empacotando plugins de %s\n' "$PLUG"
    for d in "$PLUG"/*/; do
        [ -d "$d" ] || continue
        name="$(basename "$d")"
        [ -f "$d/module.prop" ] || { printf '  · %s (sem module.prop) — ignorado\n' "$name"; continue; }
        if [ "$have_zip" = "1" ]; then
            ( cd "$d" && zip -rq "$OUT/$name.zip" . )
        elif command -v python3 >/dev/null 2>&1; then
            python3 - "$d" "$OUT/$name.zip" <<'PY'
import sys, os, zipfile
src, out = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(src):
        for f in files:
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, src))
PY
        fi
        printf '  ▸ releases/%s.zip\n' "$name"
    done
fi
printf '  pronto. zips em releases/\n'
