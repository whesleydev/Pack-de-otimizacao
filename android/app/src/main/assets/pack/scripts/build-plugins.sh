#!/system/bin/sh
# =============================================================================
#  build-plugins.sh - Empacota os plugins do pack (níveis 3 e 4) em releases/.
#  Uso: sh scripts/build-plugins.sh
#
#  Varre "00 Otimizações/Plugins AxManager" por pastas com module.prop e empacota
#  cada uma em releases/<nome>.zip. Inclui os nossos (Nossos/) e os de terceiros
#  de licença permissiva (Terceiros-open-source/).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
OUT="$ROOT/releases"
SRC="$ROOT/00 Otimizações/Plugins AxManager"
mkdir -p "$OUT"

have_zip=1
command -v zip >/dev/null 2>&1 || have_zip=0

pack() {  # pack <dir> <nome>
    d="$1"; name="$2"
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
    else
        printf '  ! %s — instale o zip ou python3\n' "$name"
        return 1
    fi
    printf '  ▸ releases/%s.zip\n' "$name"
}

printf '  Empacotando plugins de %s\n' "$SRC"
found=0
while IFS= read -r prop; do
    [ -n "$prop" ] || continue
    d="$(dirname "$prop")"
    name="$(basename "$d")"
    found=$((found + 1))
    pack "$d" "$name"
done <<EOF
$(find "$SRC" -name module.prop -not -path '*/.git/*' 2>/dev/null | sort)
EOF

[ "$found" = "0" ] && printf '  · nenhum plugin encontrado\n'
printf '  pronto. zips em releases/\n'
