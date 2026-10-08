#!/system/bin/sh
# =============================================================================
#  check-licenses.sh - Mostra o status de licença dos módulos de terceiros.
#
#  Sem licença explícita = "todos os direitos reservados": não redistribuir/vender.
#  Use junto com THIRD-PARTY-NOTICES.md.
#
#  Uso:
#     sh scripts/check-licenses.sh            # relatório
#     sh scripts/check-licenses.sh --strict   # sai com código 1 se houver pendência
#
#  Saída: <pasta>\t<licença detectada>
#  Códigos: 0 = tudo liberado | 1 = há módulo sem licença (bloqueia release estrita)
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
SRC="$ROOT/modules"

STRICT=0
[ "$1" = "--strict" ] && STRICT=1
[ "$STRICT_LICENSES" = "1" ] && STRICT=1

# licença liberada para redistribuição? (permissivas + copyleft com deveres)
is_ok() {
    case "$1" in
        Apache*|MIT*|BSD*|GPL*|LGPL*|GNU*|MPL*|Mozilla*|Unlicense|CC0*) return 0 ;;
        *) return 1 ;;
    esac
}

detect() {  # detect <dir> -> imprime o nome da licença, ou vazio
    d="$1"
    for f in "$d"/LICENSE "$d"/LICENSE.md "$d"/LICENSE.txt "$d"/COPYING; do
        [ -f "$f" ] || continue
        head -3 "$f" 2>/dev/null | grep -ioE 'Apache License|MIT License|GNU (GENERAL|LESSER) PUBLIC LICENSE|BSD|Mozilla Public License|The Unlicense|CC0' | head -1
        return 0
    done
    # alguns módulos trazem só um hash da licença (Kang, Celestial)
    [ -f "$d/LICENSE.sha256" ] && { echo "Apache-2.0 (hash)"; return 0; }
    [ -f "$d/LICENSE.sha1" ]   && { echo "Apache-2.0 (hash)"; return 0; }
}

pend=0; ok=0; total=0
printf '\n  Licenças dos módulos de terceiros\n'
printf '  ------------------------------------------------------------------\n'
for d in "$SRC"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    [ -f "$d/module.prop" ] || continue
    total=$((total+1))
    lic="$(detect "$d")"
    if [ -n "$lic" ] && is_ok "$lic"; then
        printf '  [ ok ] %-42s %s\n' "$name" "$lic"
        ok=$((ok+1))
    else
        printf '  [ !! ] %-42s SEM LICENÇA (todos os direitos reservados)\n' "$name"
        pend=$((pend+1))
    fi
done
printf '  ------------------------------------------------------------------\n'
printf '  %d módulos: %d liberados, %d pendentes\n\n' "$total" "$ok" "$pend"

if [ "$pend" -gt 0 ]; then
    printf '  ⚠️  %d módulo(s) sem licença NÃO podem ser redistribuídos/vendidos sem\n' "$pend"
    printf '      permissão escrita do autor. Veja THIRD-PARTY-NOTICES.md.\n\n'
fi

[ "$STRICT" = "1" ] && [ "$pend" -gt 0 ] && exit 1
exit 0
