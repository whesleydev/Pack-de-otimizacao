#!/system/bin/sh
# =============================================================================
#  check-secrets.sh - Procura credenciais em arquivos VERSIONADOS do repositório.
#  Roda local e no CI (portão antes de publicar). Não imprime o valor do segredo.
#
#  Uso:
#     sh scripts/check-secrets.sh          # varre arquivos rastreados pelo git
#     sh scripts/check-secrets.sh --all    # varre também não rastreados (lento)
#
#  Saída: lista "arquivo: linha" com o padrão encontrado (valor mascarado).
#  Código: 0 = limpo | 1 = encontrou algo
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"
cd "$ROOT" || exit 1

# padrões de credencial (só o formato, nunca o valor)
PATTERNS='ghp_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{60,}|gho_[A-Za-z0-9]{36}|ghs_[A-Za-z0-9]{36}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|xox[baprs]-[A-Za-z0-9-]{10,}|sk-[A-Za-z0-9]{20,}'

if [ "$1" = "--all" ]; then
    files="$(find . -type f -not -path './.git/*' 2>/dev/null)"
else
    files="$(git ls-files 2>/dev/null)"
fi

found=0
for f in $files; do
    [ -f "$f" ] || continue
    # ignora binários e o próprio scanner
    case "$f" in
        *check-secrets.sh|*.png|*.jpg|*.jpeg|*.gif|*.webp|*.zip|*.apk|*.so|*.jar|*.ttf|*.woff*) continue ;;
    esac
    hits="$(grep -InE "$PATTERNS" "$f" 2>/dev/null | head -3)"
    if [ -n "$hits" ]; then
        found=$((found+1))
        printf '  [ !! ] %s\n' "$f"
        printf '%s\n' "$hits" | sed -E 's/(ghp_|github_pat_|gho_|ghs_|AKIA|xox[baprs]-|sk-)[A-Za-z0-9_-]+/\1<REDACTED>/g; s/^/         /'
    fi
done

if [ "$found" -gt 0 ]; then
    printf '\n  ⚠️  %d arquivo(s) com possível credencial. Remova, revogue o token e\n' "$found"
    printf '      purgue o histórico (veja docs/SEGURANCA.md).\n\n'
    exit 1
fi
printf '  [ ok ] nenhuma credencial encontrada nos arquivos verificados.\n'
exit 0
