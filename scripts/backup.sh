#!/system/bin/sh
# =============================================================================
#  backup.sh - Ponto de retorno COMPLETO, num arquivo só.
#
#  O snapshot.sh guarda o estado numa pasta interna (bom para uso rápido). Este
#  aqui empacota o mesmo estado num ÚNICO arquivo de texto, que o app grava
#  criptografado na pasta pública do aparelho. É o que o usuário pode guardar:
#  um arquivo .txt que devolve TODAS as configurações de uma vez.
#
#  Este script NÃO criptografa: ele só monta (collect) e aplica (restore) o
#  conteúdo em texto. Quem criptografa é o app (Android Keystore/AES-GCM) ou o
#  painel web (openssl/PHP) — assim a criptografia fica num lugar só de cada
#  lado e o miolo aqui continua testável como o resto do pack.
#
#  Uso:
#     sh backup.sh collect            # escreve o pacote em texto no stdout
#     sh backup.sh restore <arquivo>  # lê o pacote e devolve as configurações
#     sh backup.sh list               # lista os pacotes salvos no aparelho
#
#  O pacote tem três seções, no mesmo formato que o snapshot.sh usa:
#     ### meta      (id, data, modo, modelo, android)
#     ### settings  (global <chave> <valor> / system <chave> <valor>)
#     ### props     (setprop <prop> <valor>)
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

BKP_DIR="$ST/backups"
mkdir -p "$BKP_DIR" 2>/dev/null

# nome do snapshot temporário usado para intermediar com o snapshot.sh
TMP_ID="_backup_tmp"
SNAP_DIR="$ST/snapshots"

# --- collect ------------------------------------------------------------------
# Deixa o snapshot.sh fazer a leitura (é a mesma lista de chaves, já testada) e
# converte o resultado em UM texto só, com as seções marcadas.
collect() {
    rm -rf "$SNAP_DIR/$TMP_ID" 2>/dev/null
    if ! sh "$DIR/snapshot.sh" save "$TMP_ID" >/dev/null 2>&1; then
        err "não consegui ler o estado atual do aparelho"
        return 1
    fi
    d="$SNAP_DIR/$TMP_ID"
    if [ ! -f "$d/settings" ]; then
        err "a leitura do aparelho não devolveu configurações"
        return 1
    fi

    printf '#TRIX-BACKUP-V1\n'
    printf '### meta\n'
    [ -f "$d/meta" ] && cat "$d/meta"
    printf '### settings\n'
    cat "$d/settings"
    printf '### props\n'
    [ -f "$d/props" ] && cat "$d/props"
    printf '### fim\n'

    rm -rf "$d" 2>/dev/null
    return 0
}

# --- restore ------------------------------------------------------------------
# Aceita o pacote por arquivo. Recria um snapshot temporário com o conteúdo e
# delega a aplicação ao snapshot.sh (que já sabe escrever settings e props).
restore() {
    src="$1"
    [ -n "$src" ] || { err "uso: backup.sh restore <arquivo>"; return 1; }
    [ -f "$src" ] || { err "arquivo não encontrado: $src"; return 1; }

    # valida a assinatura antes de mexer em qualquer coisa
    if ! head -1 "$src" 2>/dev/null | grep -q '^#TRIX-BACKUP-V1'; then
        err "este arquivo não é um backup do Trix (assinatura não confere)"
        return 1
    fi

    d="$SNAP_DIR/$TMP_ID"
    rm -rf "$d" 2>/dev/null
    mkdir -p "$d" 2>/dev/null

    # separa as seções; o que não pertencer a nenhuma é ignorado de propósito
    awk -v dir="$d" '
        /^### meta$/     { sec="meta";     next }
        /^### settings$/ { sec="settings"; next }
        /^### props$/    { sec="props";    next }
        /^### fim$/      { sec="";         next }
        /^#TRIX-BACKUP-V1$/ { next }
        sec != "" { print > (dir "/" sec) }
    ' "$src"

    if [ ! -s "$d/settings" ]; then
        err "o backup não tem nenhuma configuração para restaurar"
        rm -rf "$d" 2>/dev/null
        return 1
    fi

    n="$(wc -l < "$d/settings" | tr -cd '0-9')"
    say "Restaurando $n configuração(ões) do arquivo"
    sh "$DIR/snapshot.sh" restore "$TMP_ID" || {
        err "não consegui aplicar o backup"
        rm -rf "$d" 2>/dev/null
        return 1
    }
    rm -rf "$d" 2>/dev/null
    say "configurações restauradas. Desligue e ligue a tela para aplicar."
    return 0
}

# --- list ---------------------------------------------------------------------
list() {
    if [ -z "$(ls -1 "$BKP_DIR" 2>/dev/null)" ]; then
        warn "nenhum arquivo de configuração salvo ainda."
        return 0
    fi
    printf '  Arquivos de configuração em %s:\n\n' "$BKP_DIR"
    for f in $(ls -1 "$BKP_DIR" | sort); do
        printf '   %b%s%b  %s\n' "$C_A" "$f" "$C_R" "$(wc -c < "$BKP_DIR/$f" | tr -cd '0-9') bytes"
    done
}

usage() {
    printf '  Uso: %s collect | restore <arquivo> | list\n' "$0"
}

case "$1" in
    collect) collect ;;
    restore) restore "$2" ;;
    list)    list ;;
    *)       usage ;;
esac
rc=$?
exit $rc
