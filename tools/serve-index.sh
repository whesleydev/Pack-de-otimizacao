#!/bin/sh
# Gera serve/index.html a partir dos APKs que existem em serve/.
#
# A pagina era estatica e ficou desatualizada: continuava anunciando uma versao
# velha como RECOMENDADO enquanto os APKs nem estavam mais na pasta. Agora ela e
# gerada da lista real, entao nunca aponta para arquivo que nao existe.
#
# Uso: sh scripts/serve-index.sh

set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SERVE="$ROOT/serve"
OUT="$SERVE/index.html"

cd "$SERVE" || { echo "sem a pasta serve/" >&2; exit 1; }

# Ordena por versao (2.49.0 > 2.44.1) de forma decrescente.
LISTA=$(ls -1 *.apk 2>/dev/null | while read -r f; do
    v=$(printf '%s' "$f" | sed -n 's/.*-v\([0-9][0-9.]*\)[^0-9].*/\1/p')
    [ -z "$v" ] && v=$(printf '%s' "$f" | sed -n 's/.*-v\([0-9][0-9.]*\)\.apk/\1/p')
    printf '%s %s\n' "${v:-0.0.0}" "$f"
done | sort -rV)

[ -z "$LISTA" ] && { echo "nenhum .apk em serve/" >&2; exit 1; }

escreve_cartao() {
    apk="$1"; destaque="$2"
    bytes=$(wc -c < "$apk" | tr -d ' ')
    sha=$(sha256sum "$apk" | cut -d' ' -f1)
    if [ "$destaque" = "1" ]; then
        cls="card best"; tag='<span class="tag">RECOMENDADO</span>'
    else
        cls="card old"; tag='<span class="tag warn">versao anterior</span>'
    fi
    cat <<EOF
<div class="$cls">
  <strong>$apk</strong>$tag
  <div class="muted">$bytes bytes</div>
  <div><a class="btn$([ "$destaque" = 1 ] || echo ' alt')" href="$apk">Baixar</a></div>
EOF
    if [ "$destaque" = "1" ]; then
        cat <<'EOF'
  <div class="cred">
    A venda oficial e <b>so</b> no servidor do dono. Comprou em outro lugar? Voce tomou um golpe.<br>
    <a href="https://discord.gg/w9hFBeVKw8" target="_blank" rel="noopener">Servidor do dono</a>
  </div>
EOF
    fi
    echo "  <div class=\"muted\">SHA-256: <code>$sha</code></div>"
    echo "</div>"
}

{
cat <<'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Trix - downloads</title>
<style>
  :root { color-scheme: dark; }
  * { box-sizing: border-box; }
  body { margin:0; padding:28px 18px 48px; font:15px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif; background:#0e1116; color:#e6e9ef; }
  h1 { margin:0 0 4px; font-size:22px; }
  .sub { margin:0 0 22px; color:#9aa4b2; }
  .card { max-width:660px; margin:0 0 16px; padding:16px 18px; background:#161b22; border:1px solid #262c36; border-radius:12px; }
  .card.best { border-color:#c7ccd6; }
  .card.old { opacity:.75; }
  strong { display:block; margin-bottom:6px; font-size:15px; word-break:break-all; }
  .tag { display:inline-block; margin-bottom:8px; padding:2px 8px; font-size:11px; font-weight:700; letter-spacing:.04em; border-radius:999px; background:#c7ccd6; color:#12151a; }
  .tag.warn { background:#6b7280; color:#f5f7fa; }
  .muted { color:#9aa4b2; font-size:13px; }
  .muted + .muted { margin-top:3px; }
  code { font:12px/1.4 ui-monospace,SFMono-Regular,Menlo,monospace; color:#d7dde7; word-break:break-all; }
  .btn { display:inline-block; margin-top:12px; padding:10px 16px; font-weight:700; text-decoration:none; border-radius:9px; background:#c7ccd6; color:#12151a; }
  .btn.alt { background:#2b323d; color:#e6e9ef; }
  .cred { margin-top:12px; padding:10px 12px; border-radius:9px; background:#0e1116; border:1px dashed #3a424f; font-size:13px; }
</style>
</head>
<body>
<h1>Trix - downloads</h1>
<p class="sub">Baixe pelo botao. A instalacao acontece por cima (mesma assinatura), sem desinstalar.</p>
EOF

primeiro=1
printf '%s\n' "$LISTA" | while read -r _ver apk; do
    [ -z "$apk" ] && continue
    escreve_cartao "$apk" "$primeiro"
    primeiro=0
done

cat <<'EOF'
</body>
</html>
EOF
} > "$OUT"

echo "gerado: $OUT"
grep -c '<div class="card' "$OUT" | sed 's/^/cartoes: /'
