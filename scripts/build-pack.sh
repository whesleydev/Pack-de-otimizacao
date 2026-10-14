#!/system/bin/sh
# =============================================================================
#  build-pack.sh - Gera o "Pack 00" completo em um único .zip, pronto para baixar
#  e usar (níveis 1 a 4).  Uso: sh scripts/build-pack.sh
#
#  O zip sai em releases/ com a estrutura:
#    Pack de Otimização 00/
#      00 Otimizações/   (níveis 1 a 4: .txt, scripts, plugins, módulos)
#      scripts/          (motor dos scripts — o run.sh aponta para cá)
#      releases/         (zips dos plugins/módulos já empacotados)
#      Apps/  COMECE-AQUI.md  README.md  VERSION  LICENSE
#
#  Inclui scripts/ de propósito: o "00 Otimizações/Scripts SH/run.sh" usa
#  "../scripts", então o pacote precisa das duas pastas lado a lado para rodar
#  sem instalar nada.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
OUT="$ROOT/releases"
VER="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0)"
NAME="Pack-de-Otimizacao-00-v$VER"
STAGE="$OUT/.stage/$NAME"

mkdir -p "$OUT"
rm -rf "$OUT/.stage"
mkdir -p "$STAGE"

# 1) empacota plugins e módulos primeiro, para irem junto
sh "$DIR/build-plugins.sh" >/dev/null 2>&1 || true
sh "$DIR/build-modules.sh" >/dev/null 2>&1 || true

# 2) copia o conteúdo do pack (sem lixo de git/build)
copy() {  # copy <origem> <destino-relativo>
    src="$1"; dst="$STAGE/$2"
    [ -e "$src" ] || return 0
    mkdir -p "$(dirname "$dst")"
    cp -r "$src" "$dst"
}
copy "$ROOT/00 Otimizações" "00 Otimizações"
copy "$ROOT/scripts" "scripts"
copy "$ROOT/Apps" "Apps"
copy "$ROOT/pack.sh" "pack.sh"
copy "$ROOT/main.sh" "main.sh"
copy "$ROOT/web" "web"
copy "$ROOT/README.md" "README.md"
copy "$ROOT/COMECE-AQUI.md" "COMECE-AQUI.md"
copy "$ROOT/LICENSE" "LICENSE"
copy "$ROOT/VERSION" "VERSION"
mkdir -p "$STAGE/releases"
cp "$OUT"/*.zip "$STAGE/releases/" 2>/dev/null || true

# limpa estados/lixo que não devem ir no zip
find "$STAGE" -name '.git' -type d -prune -exec rm -rf {} + 2>/dev/null
find "$STAGE" -name 'state' -type d -prune -exec rm -rf {} + 2>/dev/null
find "$STAGE" -name '*.log' -delete 2>/dev/null
rm -f "$STAGE/web/.token" 2>/dev/null   # token é segredo local, nunca vai no zip

# 3) zipa
ZIP="$OUT/$NAME.zip"
rm -f "$ZIP"
if command -v zip >/dev/null 2>&1; then
    ( cd "$OUT/.stage" && zip -rq "$ZIP" "$NAME" )
elif command -v python3 >/dev/null 2>&1; then
    python3 - "$OUT/.stage" "$NAME" "$ZIP" <<'PY'
import sys, os, zipfile
base, name, out = sys.argv[1], sys.argv[2], sys.argv[3]
root = os.path.join(base, name)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for r, _, files in os.walk(root):
        for f in files:
            p = os.path.join(r, f)
            z.write(p, os.path.join(name, os.path.relpath(p, root)))
PY
else
    printf '  ! instale o zip ou python3\n'; exit 1
fi
rm -rf "$OUT/.stage"

# 4) checksum
if command -v sha256sum >/dev/null 2>&1; then
    ( cd "$OUT" && sha256sum "$NAME.zip" > "$NAME.zip.sha256" )
fi
printf '  ▸ releases/%s.zip\n' "$NAME"
ls -lh "$ZIP" 2>/dev/null | awk '{print "    tamanho:", $5}'
