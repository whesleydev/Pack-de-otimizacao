#!/system/bin/sh
# =============================================================================
#  resolution.sh - Resolução de tela (a mesma de vários aparelhos) e custom.
#
#  O `wm size` muda a resolução LÓGICA: o Android renderiza menos pixels e
#  estica para a tela física. É o ajuste que mais rende FPS em jogo pesado —
#  a GPU desenha menos e o mesmo chip entrega mais quadros. A resolução de
#  fábrica do aparelho nunca é perdida: fica guardada e volta com "reset".
#
#  Uso:
#     resolution.sh list                  # perfis prontos (nome + WxH)
#     resolution.sh current               # o que está valendo agora
#     resolution.sh apply <perfil|WxH>    # aplica um perfil pronto ou "1080x2340"
#     resolution.sh reset                 # volta à resolução de fábrica
#     resolution.sh auto                  # perfil conforme o aparelho
#
#  Reversível: a resolução original é guardada no primeiro apply e o
#  "Reverter TUDO" do pack devolve o valor de fábrica.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

scope_begin resolution

# --- perfis prontos -----------------------------------------------------------
# Resoluções reais de aparelhos conhecidos, em ordem de PIXELS (menor = mais FPS).
# A ideia não é "igualar ao aparelho X", é dar degraus que já existem no mercado
# para o usuário escolher o quanto aceita perder de nitidez em troca de FPS.
perfis() {
    cat <<'EOF'
480x800|320p (mínimo, só p/ FPS)
540x960|540p (leve)
720x1280|720p (HD)
720x1600|720p alto (20:9)
1080x1920|1080p (Full HD)
1080x2340|1080p alto (19.5:9)
1080x2400|1080p+ (20:9)
1220x2712|1220p (iPhone 15 Pro)
1179x2556|1179p (iPhone 14 Pro)
1440x2560|1440p (QHD)
1440x3200|1440p alto (20:9)
EOF
}

# --- resolução atual ----------------------------------------------------------
# `wm size` devolve "Physical size: WxH" e, quando há override, uma 2ª linha
# "Override size: WxH". A física é a de fábrica; o override é o que está valendo.
fisico() {
    sh_get 'wm size' | sed -n 's/.*Physical size: *\([0-9]*x[0-9]*\).*/\1/p' | tail -1
}

override() {
    sh_get 'wm size' | sed -n 's/.*Override size: *\([0-9]*x[0-9]*\).*/\1/p' | tail -1
}

atual() {
    o="$(override)"
    [ -n "$o" ] && printf '%s' "$o" || fisico
}

cmd_current() {
    f="$(fisico)"; o="$(override)"
    printf '  %sresolução de fábrica%s  %s\n' "$C_A" "$C_R" "${f:-não deu para ler}"
    printf '  %sresolução em uso%s     %s\n' "$C_A" "$C_R" "$(atual)"
    if [ -n "$o" ]; then
        printf '  %s(com override ativo — "reset" volta para a de fábrica)%s\n' "$C_D" "$C_R"
    else
        printf '  %s(sem override: está na resolução de fábrica)%s\n' "$C_D" "$C_R"
    fi
    d="$(sh_get 'wm density' | sed -n 's/.*Physical density: *\([0-9]*\).*/\1/p' | tail -1)"
    do_="$(sh_get 'wm density' | sed -n 's/.*Override density: *\([0-9]*\).*/\1/p' | tail -1)"
    [ -n "$d" ] && printf '  %sdensidade%s             %s%s\n' "$C_A" "$C_R" "$d" \
        "$([ -n "$do_" ] && printf ' (override %s)' "$do_")"
}

cmd_list() {
    printf '  %s◆%s  %sRESOLUÇÕES DISPONÍVEIS%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    perfis | while IFS='|' read -r wh nome; do
        printf '   %s%-12s%s %s\n' "$C_A" "$wh" "$C_R" "$nome"
    done
    echo
    printf '  %smelhor p/ FPS: menos pixels (720p). melhor nitidez: a de fábrica.%s\n' "$C_D" "$C_R"
    printf '  %saplicar:%s resolution.sh apply 720x1600  (ou um nome da lista)\n' "$C_A" "$C_R"
    printf '  %svoltar:%s  resolution.sh reset\n' "$C_A" "$C_R"
}

# --- aplicação ----------------------------------------------------------------
# Guarda a resolução de FÁBRICA na 1ª vez (não o override anterior): assim o
# reset sempre devolve o valor original do aparelho, mesmo aplicando várias vezes.
guardar_original() {
    f="$(fisico)"
    [ -n "$f" ] || return 0
    mkdir -p "$ST/res" 2>/dev/null
    [ -s "$ST/res/orig" ] || printf '%s\n' "$f" > "$ST/res/orig" 2>/dev/null
}

cmd_apply() {
    alvo="$1"
    [ -z "$alvo" ] && { err "uso: resolution.sh apply <perfil|WxH>"; return 1; }

    # nome de perfil -> "WxH"; se já vier "WxH", aceita como está
    case "$alvo" in
        *x*|*X*) wh="$(printf '%s' "$alvo" | tr 'X' 'x')" ;;
        *)
            wh="$(perfis | awk -F'|' -v n="$alvo" '$2 ~ n || $1 == n {print $1; exit}')"
            [ -z "$wh" ] && { err "perfil desconhecido: $alvo"; cmd_list; return 1; }
            ;;
    esac

    # valida WxH: dois números, faixa sã (nada de 0x0 nem 99x99)
    w="${wh%x*}"; h="${wh#*x}"
    case "$w$h" in ''|*[!0-9]*) err "resolução inválida: $alvo (use WxH, ex.: 720x1600)"; return 1 ;; esac
    [ "$w" -lt 320 ] || [ "$h" -lt 320 ] && { err "resolução pequena demais: $wh"; return 1; }
    [ "$w" -gt 4320 ] || [ "$h" -gt 4320 ] && { err "resolução grande demais: $wh"; return 1; }

    require_shell "mudar a resolução" || return 1
    guardar_original

    otm_v_inc apply
    sh_run "wm size $wh" >/dev/null 2>&1
    got="$(atual)"
    if [ "$got" = "$wh" ]; then
        otm_v_inc changed
        say "resolução agora é $wh (era $(fisico) de fábrica)"
        printf '  %sreinicie o jogo para ele pegar a resolução nova%s\n' "$C_D" "$C_R"
    else
        otm_v_inc failed
        err "não pegou (lido: ${got:-vazio}) — este aparelho pode não aceitar wm size"
    fi
}

cmd_reset() {
    require_shell "voltar a resolução" || return 1
    f="$(fisico)"
    otm_v_inc apply
    # `wm size reset` devolve o valor de fábrica; é mais seguro que escrever o
    # número lido (o `wm size` físico pode vir vazio em alguns aparelhos).
    sh_run "wm size reset" >/dev/null 2>&1
    rm -f "$ST/res/orig" 2>/dev/null
    if [ -z "$(override)" ]; then
        otm_v_inc changed
        say "resolução de fábrica restaurada${f:+ ($f)}"
    else
        otm_v_inc failed
        err "não voltou (lido: $(atual))"
    fi
}

# auto: escolhe um degrau conforme o tamanho de fábrica. Aparelho com tela muito
# grande (QHD) desce para 1080p — ganho grande de FPS com perda pequena; tela
# pequena fica como está (já renderiza pouco).
cmd_auto() {
    f="$(fisico)"
    [ -n "$f" ] || { err "não deu para ler a resolução do aparelho"; return 1; }
    w="${f%x*}"
    if   [ "$w" -ge 1400 ] 2>/dev/null; then cmd_apply "1080x2340"
    elif [ "$w" -ge 1150 ] 2>/dev/null; then cmd_apply "1080x1920"
    else say "tela já é leve ($f): mantida como está"; fi
}

case "${1:-}" in
    list|perfis)  cmd_list ;;
    current|atual) cmd_current ;;
    apply)        shift; cmd_apply "$1" ;;
    reset|off)    cmd_reset ;;
    auto)         cmd_auto ;;
    *)            cmd_list ;;
esac
rc=$?
otm_v_report resolution
exit $rc
