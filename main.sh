#!/system/bin/sh
# =============================================================================
#  main.sh - Entrada ALTERNATIVA do Pack de Otimização.
#
#  Diferente do pack.sh (que aplica otimizações), este menu é para:
#    1) BAIXAR RECURSOS FULL  - baixa o pack completo (código + módulos + plugins)
#    2) SUBIR SERVIDOR WEB    - sobe o painel 00deUdia Otimizações (PHP)
#    3) ABRIR O PAINEL        - mostra a URL para abrir no navegador
#    4) MANUTENÇÃO            - status, parar servidor, atualizar o pack
#
#  Uso: sh main.sh                 (menu interativo)
#       sh main.sh web start       (sobe o servidor)
#       sh main.sh web stop|status|url
#       sh main.sh web key new     (cria uma chave de acesso)
#       sh main.sh baixar [destino]  (baixa os recursos full)
#
#  O painel web (web/) executa as ações do pack por uma API com lista branca.
#  O acesso é por chave (sem usuário e senha): veja `web key`.
#  Requer PHP (php -S). No Termux: pkg install php.
# =============================================================================

DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
[ -z "$DIR" ] && DIR="."
. "$DIR/scripts/common.sh" 2>/dev/null || {
    printf '  ✕ não achei scripts/common.sh (rode de dentro do pack)\n'; exit 1
}

WEB_DIR="$DIR/web"
STATE="$HOME/.packotm/web"
PORT="${OTM_WEB_PORT:-8099}"
REPO_SLUG="whesleydev/Trix"
REPO_BRANCH="main"
DEST_FULL="${OTM_FULL_DIR:-$HOME/Trix-full}"

mkdir -p "$STATE" 2>/dev/null

# --- servidor web -------------------------------------------------------------
web_pid() {
    [ -f "$STATE/pid" ] || return 1
    p="$(cat "$STATE/pid" 2>/dev/null)"
    [ -n "$p" ] && kill -0 "$p" 2>/dev/null && { echo "$p"; return 0; }
    return 1
}

web_url() {
    ip="$(ip route get 1 2>/dev/null | awk '{print $7; exit}')"
    [ -z "$ip" ] && ip="$(ifconfig 2>/dev/null | awk '/inet /{print $2; exit}')"
    [ -z "$ip" ] && ip="127.0.0.1"
    echo "http://$ip:$PORT/index.php"
}

web_start() {
    if ! have php; then
        err "PHP não encontrado. Instale (Termux: 'pkg install php' / Debian: 'apt install php-cli')."
        return 1
    fi
    if web_pid >/dev/null; then
        warn "servidor já está no ar (PID $(web_pid))"
        printf '  URL: %s\n' "$(web_url)"
        return 0
    fi
    say "subindo o painel web na porta $PORT"
    ( cd "$WEB_DIR" && php -S "0.0.0.0:$PORT" > "$STATE/server.log" 2>&1 & echo $! > "$STATE/pid" )
    sleep 1
    if web_pid >/dev/null; then
        printf '\n  %b✔ painel no ar%b\n' "$C_G" "$C_R"
        printf '     URL: %s\n' "$(web_url)"
        if [ "$(web_key_count)" -eq 0 ]; then
            printf '     %batenção:%b ainda não há chave — crie com "sh main.sh web key new"\n' "$C_A" "$C_R"
        fi
        printf '     (mesma rede Wi-Fi; no PC abra essa URL no navegador)\n\n'
    else
        err "não consegui subir — veja $STATE/server.log"
        tail -5 "$STATE/server.log" 2>/dev/null
        return 1
    fi
}

web_stop() {
    if p="$(web_pid)"; then
        kill "$p" 2>/dev/null
        rm -f "$STATE/pid"
        say "servidor parado (PID $p)"
    else
        warn "servidor não está rodando"
    fi
}

web_status() {
    if p="$(web_pid)"; then
        printf '  %b● no ar%b  PID %s · porta %s\n' "$C_G" "$C_R" "$p" "$PORT"
        printf '  URL: %s\n' "$(web_url)"
    else
        printf '  %b○ parado%b  porta %s\n' "$C_D" "$C_R" "$PORT"
    fi
}

web_abrir() {
    web_pid >/dev/null || web_start || return 1
    u="$(web_url)"
    printf '\n  Abra no navegador:\n    %s\n\n' "$u"
    if have termux-open-url; then termux-open-url "$u" 2>/dev/null && say "abrindo…"
    elif have xdg-open; then xdg-open "$u" >/dev/null 2>&1 && say "abrindo…"
    else warn "abra manualmente a URL acima"; fi
}

# --- baixar recursos full -----------------------------------------------------
baixar_full() {
    dest="${1:-$DEST_FULL}"
    tarball="$STATE/pack-full.tar.gz"
    url="https://codeload.github.com/$REPO_SLUG/tar.gz/refs/heads/$REPO_BRANCH"

    dl=""
    have curl && dl="curl -fL --retry 2 -o"
    [ -z "$dl" ] && have wget && dl="wget -O"
    if [ -z "$dl" ]; then
        err "preciso de 'curl' ou 'wget' (Termux: pkg install curl)."
        return 1
    fi

    say "baixando o pack completo (branch $REPO_BRANCH)"
    printf '     de: %s\n' "$url"
    if ! $dl "$tarball" "$url" 2>/dev/null; then
        err "download falhou (sem internet ou repo privado?)"
        return 1
    fi
    sz="$(wc -c < "$tarball" 2>/dev/null | tr -d ' ')"
    say "recebido ($sz bytes) — extraindo em $dest"
    mkdir -p "$dest" || { err "não consegui criar $dest"; return 1; }
    if have tar; then
        tar -xzf "$tarball" -C "$dest" --strip-components=1 2>/dev/null \
            && say "recursos full em: $dest" \
            || { err "falha ao extrair"; return 1; }
    else
        cp "$tarball" "$dest/pack-full.tar.gz"
        warn "sem 'tar' — deixei o .tar.gz em $dest para extrair manualmente"
    fi
    printf '\n  Dentro de %s você tem o pack inteiro (scripts, módulos, plugins).\n' "$dest"
    printf '  Para usar o painel: sh "%s/main.sh" web start\n\n' "$dest"
}

# --- manutenção ---------------------------------------------------------------
atualizar() {
    say "atualizando o pack (git pull)"
    if have git && [ -d "$DIR/.git" ]; then
        ( cd "$DIR" && git pull --ff-only ) && say "atualizado" || err "git pull falhou"
    else
        warn "sem git/.git aqui — use a opção 'Baixar recursos full'"
    fi
}

status_geral() {
    printf '\n  %bPACK%b   %s\n' "$C_A" "$C_R" "$DIR"
    printf '  %bPHP%b    %s\n' "$C_A" "$C_R" "$(have php && php -v 2>/dev/null | head -1 || echo 'ausente')"
    printf '  %bADB%b    %s\n' "$C_A" "$C_R" "$(have adb && echo presente || echo 'ausente')"
    printf '  %bMODO%b   %s\n' "$C_A" "$C_R" "$RUN_MODE"
    printf '  %bWEB%b    ' "$C_A" "$C_R"; web_status
}

# --- menu ---------------------------------------------------------------------
menu() {
    while :; do
        printf '\n  %b╔══════════════════════════════════════════════╗%b\n' "$C_A" "$C_R"
        printf '  %b║   PACK DE OTIMIZAÇÃO · menu principal        ║%b\n' "$C_A" "$C_R"
        printf '  %b╚══════════════════════════════════════════════╝%b\n' "$C_A" "$C_R"
        printf '  %bmodo %s · PHP %s%b\n' "$C_D" "$RUN_MODE" "$(have php && echo ok || echo ausente)" "$C_R"
        printf '\n  %bPAINEL 00deUdia OTIMIZAÇÕES%b\n' "$C_A" "$C_R"
        printf '    %b1%b  Subir servidor web\n' "$C_G" "$C_R"
        printf '    %b2%b  Abrir o painel no navegador\n' "$C_G" "$C_R"
        printf '    %b3%b  Ver URL\n' "$C_G" "$C_R"
        printf '    %b4%b  Parar servidor web\n' "$C_G" "$C_R"
        printf '\n  %bCHAVES DE ACESSO%b\n' "$C_A" "$C_R"
        printf '    %b9%b  Criar uma chave nova\n' "$C_G" "$C_R"
        printf '    %b10%b Listar chaves\n' "$C_G" "$C_R"
        printf '    %b11%b Revogar uma chave\n' "$C_G" "$C_R"
        printf '\n  %bRECURSOS%b\n' "$C_A" "$C_R"
        printf '    %b5%b  Baixar recursos FULL (pack completo)\n' "$C_G" "$C_R"
        printf '    %b6%b  Atualizar o pack (git pull)\n' "$C_G" "$C_R"
        printf '\n  %bSISTEMA%b\n' "$C_A" "$C_R"
        printf '    %b7%b  Status geral (PHP/ADB/modo/web)\n' "$C_G" "$C_R"
        printf '    %b8%b  Abrir o pack de otimizações (pack.sh)\n' "$C_G" "$C_R"
        printf '\n    %b0%b  Sair\n' "$C_D" "$C_R"
        printf '  %b›%b ' "$C_A" "$C_R"
        read -r op || { printf '\n'; break; }
        case "$op" in
            1) web_start ;;
            2) web_abrir ;;
            3) printf '\n  URL: %s\n' "$(web_url)" ;;
            4) web_stop ;;
            5) printf '  destino [%s]: ' "$DEST_FULL"; read -r d; baixar_full "${d:-$DEST_FULL}" ;;
            6) atualizar ;;
            7) status_geral ;;
            8) sh "$DIR/scripts/pack.sh" ;;
            9) printf '  nome da chave (opcional): '; read -r lb; web_key_new "$lb" ;;
            10) web_key_list ;;
            11) printf '  id da chave: '; read -r kid; web_key_revoke "$kid" ;;
            0|q|sair) printf '\n  %bvaleu!%b\n\n' "$C_A" "$C_R"; exit 0 ;;
            *) warn "opção inválida" ;;
        esac
        printf '\n  %benter para continuar%b' "$C_D" "$C_R"
        read -r _ || { printf '\n'; break; }
    done
}

# --- chaves de acesso ---------------------------------------------------------
# Tudo passa pelo PHP (web/keys.php), que guarda só o hash SHA-256 das chaves.
web_key_count() {
    if ! have php; then echo 0; return 0; fi
    c="$(php -r 'require $argv[1]."/web/keys.php"; echo otm_key_active_count();' "$DIR" 2>/dev/null </dev/null)"
    [ -n "$c" ] && echo "$c" || echo 0
}

web_key_new() {
    label="$1"
    if ! have php; then
        err "PHP não encontrado. Instale (Termux: 'pkg install php')."
        return 1
    fi
    out="$(php -r '
        require $argv[1]."/web/keys.php";
        $c = otm_key_create((string)($argv[2] ?? ""));
        echo $c["key"], "\t", $c["id"];
    ' "$DIR" "$label" 2>/dev/null </dev/null)"
    if [ -z "$out" ]; then
        err "não consegui criar a chave"
        return 1
    fi
    key="$(printf '%s' "$out" | cut -f1)"
    kid="$(printf '%s' "$out" | cut -f2)"
    printf '\n  %b✔ chave criada%b  (guarde agora — ela não é mostrada de novo)\n\n' "$C_G" "$C_R"
    printf '     %b%s%b\n\n' "$C_A" "$key" "$C_R"
    printf '     id: %s\n' "$kid"
    [ -n "$label" ] && printf '     nome: %s\n' "$label"
    printf '     acesso: %s\n' "$(web_url)"
    printf '     entre no painel e cole a chave, ou use o cabeçalho X-OTM-Key\n\n'
}

web_key_list() {
    if [ "$(web_key_count)" -eq 0 ]; then
        printf '  nenhuma chave ainda — crie com "sh main.sh web key new"\n'
        return 0
    fi
    php -r '
        require $argv[1]."/web/keys.php";
        foreach (otm_key_list() as $k) {
            printf("  %-10s %-22s %-10s %s\n",
                $k["id"],
                ($k["label"] !== "" ? $k["label"] : "(sem nome)"),
                ($k["revoked"] ? "revogada" : "ativa"),
                ($k["last_used"] ? "usada " . date("d/m/Y H:i", $k["last_used"]) : "nunca usada"));
        }
    ' "$DIR" 2>/dev/null </dev/null
}

web_key_revoke() {
    id="$1"
    if [ -z "$id" ]; then
        err "informe o id da chave (veja: sh main.sh web key list)"
        return 1
    fi
    r="$(php -r 'require $argv[1]."/web/keys.php"; echo otm_key_revoke($argv[2]) ? "OK":"NAO";' "$DIR" "$id" 2>/dev/null </dev/null)"
    if [ "$r" = "OK" ]; then
        printf '  %b✔ chave %s revogada%b\n' "$C_G" "$id" "$C_R"
    else
        err "não achei a chave $id"
        return 1
    fi
}

web_logout() {
    # Encerra a sessão atual do painel (apaga o cookie/estado local).
    rm -f "$STATE/sess" 2>/dev/null
    printf '  %b✔%b sessão encerrada (reabra a URL do painel)\n' "$C_G" "$C_R"
}

# --- entrada ------------------------------------------------------------------
case "$1" in
    ""|menu) menu ;;
    web)
        case "$2" in
            start)  web_start ;;
            stop)   web_stop ;;
            restart) web_stop; web_start ;;
            status) web_status ;;
            url)    web_url ;;
            key|keys)
                case "$3" in
                    new)      web_key_new "$4" ;;
                    list|ls)  web_key_list ;;
                    revoke|rm) web_key_revoke "$4" ;;
                    count)    web_key_count ;;
                    *) printf '  Uso: sh main.sh web key new [nome]|list|revoke <id>\n' ;;
                esac ;;
            logout) web_logout ;;
            *) printf '  Uso: sh main.sh web start|stop|restart|status|url|key|logout\n' ;;
        esac ;;
    baixar|full|recursos) baixar_full "$2" ;;
    status) status_geral ;;
    -h|--help|help)
        printf '  Uso: sh main.sh [acao]\n\n'
        printf '   sem argumento   abre o menu principal\n'
        printf '   web start       sobe o painel 00deUdia Otimizações (PHP)\n'
        printf '   web stop        para o servidor\n'
        printf '   web status      mostra se está no ar + URL\n'
        printf '   web url         só imprime a URL do painel\n'
        printf '   web key new     cria uma chave de acesso (sem usuário/senha)\n'
        printf '   web key list    lista as chaves (id, nome, status)\n'
        printf '   web key revoke  revoga uma chave pelo id\n'
        printf '   web logout      encerra a sessão local do painel\n'
        printf '   baixar [dir]    baixa os recursos full do pack\n'
        printf '   status          status geral (PHP/ADB/modo/web)\n' ;;
    *) err "ação desconhecida: $1"; printf '  veja: sh main.sh --help\n'; exit 1 ;;
esac
