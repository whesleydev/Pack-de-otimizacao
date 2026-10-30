#!/system/bin/sh
# =============================================================================
#  profile-custom.sh - Perfil PERSONALIZADO: você escolhe o que aplicar.
#
#  Diferente dos modos prontos (batata/competitivo/fluido/eco), aqui cada
#  recurso é opcional e ligado por conta própria. O script guarda a escolha em
#  $ST/profile-custom/config e aplica SÓ o que estiver ligado.
#
#  Cada recurso tem um valor "nao" (ou o padrão equivalente) que significa
#  "não mexer". A lista completa e a ordem ficam em PC_ORDER, que é a MESMA
#  ordem dos parâmetros do painel (web/lib.php, profile.custom.apply) e da
#  const CPROF do HTML. Mexer na ordem de um lado exige mexer no outro.
#
#  Recursos:
#     anim=normal|half|off        animações do sistema (off=0x, half=0.5x)
#     ram=padrao|gaming|batata    limite de apps em 2º plano
#     hz=off|60|90|120|144        trava a tela numa taxa fixa
#     touch=none|balanced|headshot|spray|sniper|speed
#     telemetry=nao|off           off desliga logs/telemetria e scans
#     clean=off|fundo|suave|normal  limpeza de RAM/cache + suavização
#     hibernate=on|off            hiberna os apps de fundo
#     gpu=nao|on                  renderização por GPU + driver do jogo
#     renderer=nao|skiagl|skiavk  motor gráfico da interface
#     dns=nao|cloudflare|adguard|quad9|google
#     net=nao|on                  DNS + buffers TCP
#     latency=nao|on              BBR, low latency, ECN (ping)
#     wifi=nao|on                 Wi-Fi sem scan/economia em 2º plano
#     battery=nao|on              economia de bateria ligada
#     doze=nao|on                 sono profundo mais rápido
#     proc=nao|4|8|16             limite de processos em 2º plano
#     freezer=nao|on              congela apps em cache
#     efeitos=nao|ligados|leves   desfoque/transparência
#     barras=nao|visiveis|status|nav|full  barras do sistema (imersivo)
#     dnd=nao|on                  não perturbe
#     gamefocus=nao|on            foco de jogo (DND extremo)
#     notif=nao|on                menos notificações heads-up
#     res=nao|auto|720x1600|1080x1920|1080x2340  resolução lógica
#     perfmode=nao|on             modo desempenho fixo
#     vitality=nao|on             longevidade da bateria (carga 80%)
#     mobile=nao|on               rede móvel sem economia de dados
#     janelas=nao|on              transições 0.5x
#     touchlat=nao|leve|forte     latência de toque (responsividade/slop)
#     touchmulti=nao|120|200|300  janela do multitouch (ms)
#     barras_bat=nao|on|off       bateria em % na barra de cima
#     barras_relogio=nao|on|off   segundos no relógio da barra de cima
#     barras_icones=nao|limpa     esconde ícones secundários da barra
#     art=nao|speed-profile|speed recompila TODOS os apps (ART/AOT; demora)
#     trim=nao|on                 poda caches (sem apagar dados)
#     killbg=nao|on               encerra os apps em 2º plano agora
#     phantom=nao|on              desliga o Phantom Process Killer
#     debloat_bg=nao|on           restringe apps de fundo (appops + standby)
#     display=nao|on              HWUI/SurfaceFlinger afinados
#     dexopt=nao|on               recompila os apps em 2º plano (demora)
#     gaming=nao|on               modo jogo profundo (debloat + ANGLE)
#     obscure=nao|on              menos kills em 2º plano, jogo fora do Doze
#     tela=nao|on                 tela 10 min + 120 Hz fixos
#
#  Uso:
#     profile-custom.sh show                    # mostra a configuração salva
#     profile-custom.sh set <chave> <valor>     # muda uma opção (sem aplicar)
#     profile-custom.sh set k1=v1 k2=v2 ...     # muda várias de uma vez
#     profile-custom.sh apply                   # aplica o que está ligado
#     profile-custom.sh on                      # atalho: set + apply
#     profile-custom.sh off                     # desfaz tudo e volta ao padrão
#
#  Aplicar parte de um estado limpo (reverte o pack antes), para não empilhar
#  ajustes de uma aplicação anterior. Tudo é reversível: `profile-custom.sh off`
#  (ou pack.sh restore).
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
otm_v_reset

PC_ST="$ST/profile-custom"
mkdir -p "$PC_ST" 2>/dev/null
PC_CFG="$PC_ST/config"       # opções escolhidas (chave=valor)
PC_CUR="$PC_ST/current"      # marca que o perfil está ativo

PC_A=0; PC_C=0; PC_F=0

# Ordem canônica das chaves. Casa com o argv de profile.custom.apply e com a
# const CPROF do painel: os três têm de estar na MESMA ordem.
PC_ORDER="anim ram hz touch clean renderer \
dns proc efeitos barras res touchlat \
barras_bat barras_relogio barras_icones touchmulti art \
telemetry hibernate gpu net latency wifi \
battery doze freezer dnd gamefocus notif \
perfmode vitality mobile janelas \
trim killbg phantom debloat_bg \
display dexopt gaming obscure tela"

# --- valores aceitos por chave (o primeiro é o padrão "não mexer") ------------
pc_opts() {
    case "$1" in
        anim)      echo "normal half off" ;;
        ram)       echo "padrao gaming batata" ;;
        hz)        echo "off 60 90 120 144" ;;
        touch)     echo "none balanced headshot spray sniper speed" ;;
        telemetry) echo "nao off" ;;
        clean)     echo "off fundo suave normal" ;;
        hibernate) echo "off on" ;;
        gpu)       echo "nao on" ;;
        renderer)  echo "nao skiagl skiavk" ;;
        dns)       echo "nao cloudflare adguard quad9 google" ;;
        net)       echo "nao on" ;;
        latency)   echo "nao on" ;;
        wifi)      echo "nao on" ;;
        battery)   echo "nao on" ;;
        doze)      echo "nao on" ;;
        proc)      echo "nao 4 8 16" ;;
        freezer)   echo "nao on" ;;
        efeitos)   echo "nao ligados leves" ;;
        barras)    echo "nao visiveis status nav full" ;;
        dnd)       echo "nao on" ;;
        gamefocus) echo "nao on" ;;
        notif)     echo "nao on" ;;
        res)       echo "nao auto 720x1600 1080x1920 1080x2340" ;;
        perfmode)  echo "nao on" ;;
        vitality)  echo "nao on" ;;
        mobile)    echo "nao on" ;;
        janelas)   echo "nao on" ;;
        touchlat)  echo "nao leve forte" ;;
        barras_bat)     echo "nao on off" ;;
        barras_relogio) echo "nao on off" ;;
        barras_icones)  echo "nao limpa" ;;
        touchmulti)     echo "nao 120 200 300" ;;
        art)            echo "nao speed-profile speed" ;;
        trim)           echo "nao on" ;;
        killbg)         echo "nao on" ;;
        phantom)        echo "nao on" ;;
        debloat_bg)     echo "nao on" ;;
        display)        echo "nao on" ;;
        dexopt)         echo "nao on" ;;
        gaming)         echo "nao on" ;;
        obscure)        echo "nao on" ;;
        tela)           echo "nao on" ;;
        *)         echo "" ;;
    esac
}

# --- acesso por chave: a variável é PC_<CHAVE> em maiúsculas ------------------
pc_key_ok() { case " $PC_ORDER " in *" $1 "*) return 0 ;; esac; return 1; }
pc_var()    { printf '%s' "PC_$(printf '%s' "$1" | tr 'a-z' 'A-Z')"; }
pc_setvar() { eval "$(pc_var "$1")=\"\$2\""; }
pc_getvar() { eval "printf '%s' \"\${$(pc_var "$1"):-}\""; }

pc_default() {
    case "$1" in
        anim)      echo normal ;;
        ram)       echo padrao ;;
        hz)        echo off ;;
        touch)     echo none ;;
        telemetry) echo nao ;;
        clean)     echo off ;;
        hibernate) echo off ;;
        *)         echo nao ;;
    esac
}

pc_defaults() { for _k in $PC_ORDER; do pc_setvar "$_k" "$(pc_default "$_k")"; done; }

# --- lê a configuração salva por cima dos padrões ------------------------------
pc_load() {
    pc_defaults
    [ -f "$PC_CFG" ] || return 0
    while IFS= read -r _l; do
        case "$_l" in ''|'#'*) continue ;; esac
        _k="${_l%%=*}"; _v="${_l#*=}"
        pc_key_ok "$_k" && pc_setvar "$_k" "$_v"
    done < "$PC_CFG"
}

# --- valida uma chave=valor ----------------------------------------------------
pc_valid() {
    pc_key_ok "$1" || return 1
    case " $(pc_opts "$1") " in *" $2 "*) return 0 ;; esac
    return 1
}

# --- grava uma chave=valor (substitui a linha existente) -----------------------
pc_save() {
    _k="$1"; _v="$2"
    : > "$PC_CFG.new"
    _done=0
    if [ -f "$PC_CFG" ]; then
        while IFS= read -r _l; do
            case "$_l" in ''|'#'*) continue ;; esac
            if [ "${_l%%=*}" = "$_k" ]; then
                printf '%s=%s\n' "$_k" "$_v" >> "$PC_CFG.new"; _done=1
            else
                printf '%s\n' "$_l" >> "$PC_CFG.new"
            fi
        done < "$PC_CFG"
    fi
    [ "$_done" = "1" ] || printf '%s=%s\n' "$_k" "$_v" >> "$PC_CFG.new"
    mv "$PC_CFG.new" "$PC_CFG" 2>/dev/null
}

# --- roda um script do pack somando as contagens reais ------------------------
pc_run() {
    _s="$1"; shift
    _o="$(OTM_NO_COLOR=1 sh "$DIR/$_s" "$@" 2>&1)"
    _rc=$?
    printf '%s\n' "$_o" | grep -v '^#OTM-RESULT'
    _l="$(printf '%s\n' "$_o" | grep '^#OTM-RESULT' | tail -1)"
    [ -n "$_l" ] || return $_rc
    _k="$(printf '%s' "$_l" | sed 's/^#OTM-RESULT //')"
    for _t in $_k; do
        case "$_t" in
            applies=*) PC_A=$((PC_A + ${_t#applies=})) ;;
            changed=*) PC_C=$((PC_C + ${_t#changed=})) ;;
            failed=*)  PC_F=$((PC_F + ${_t#failed=})) ;;
        esac
    done
    return $_rc
}

# --- volta ao estado limpo antes de aplicar -----------------------------------
pc_reset() {
    say "Revertendo o pack para partir de um estado limpo"
    pc_run adb-tweaks.sh restore_all
    pc_run deep-tune.sh restore
    pc_run debloat.sh off
}

# --- salva várias opções "chave=valor" (valida cada uma) -----------------------
# Devolve 1 se alguma opção for inválida.
pc_set_all() {
    _bad=0
    for _p in "$@"; do
        case "$_p" in
            *=*) _k="${_p%%=*}"; _v="${_p#*=}" ;;
            *)   err "opção inválida: $_p"; _bad=1; continue ;;
        esac
        if pc_valid "$_k" "$_v"; then
            pc_save "$_k" "$_v"
        else
            err "opção inválida: $_p"; _bad=1
        fi
    done
    return $_bad
}

# --- salva as opções na ORDEM fixa usada pelo painel --------------------------
# O painel manda uma ação só, com os valores posicionais; aqui eles viram
# chave=valor. Omitir um argumento (vazio) mantém o que já estava salvo.
pc_set_pos() {
    _i=1
    for _k in $PC_ORDER; do
        eval "_v=\${$_i:-}"
        if [ -n "$_v" ]; then
            if pc_valid "$_k" "$_v"; then pc_save "$_k" "$_v"
            else err "opção inválida: $_k=$_v"; return 1; fi
        fi
        _i=$((_i+1))
    done
    return 0
}

# --- aplica só o que estiver ligado -------------------------------------------
# Cada bloco só age quando a chave saiu do valor "não mexer"; assim aplicar o
# perfil não empilha ajuste nenhum além do que o usuário marcou.
pc_apply() {
    pc_load
    _n=0
    say "Perfil PERSONALIZADO — aplicando só o que você ligou"

    # --- desempenho / memória ---
    case "$PC_TELEMETRY" in
        off) pc_run turbo.sh telemetry off; _n=$((_n+1)) ;;
    esac
    case "$PC_ANIM" in
        off)    pc_run adb-tweaks.sh perf_max; _n=$((_n+1)) ;;
        half)   pc_run adb-tweaks.sh perf;     _n=$((_n+1)) ;;
    esac
    case "$PC_RAM" in
        gaming|batata) pc_run adb-tweaks.sh mem "$PC_RAM"; _n=$((_n+1)) ;;
    esac
    case "$PC_PROC" in
        nao|'') ;;
        *) pc_run adb-tweaks.sh proc_limit "$PC_PROC"; _n=$((_n+1)) ;;
    esac
    case "$PC_HIBERNATE" in
        on) pc_run turbo.sh hibernate now; _n=$((_n+1)) ;;
    esac
    case "$PC_FREEZER" in
        on) pc_run adb-tweaks.sh freezer; _n=$((_n+1)) ;;
    esac
    case "$PC_PERFMODE" in
        on) pc_run turbo.sh perfmode on; _n=$((_n+1)) ;;
    esac
    case "$PC_PHANTOM" in
        on) pc_run turbo.sh phantom off; _n=$((_n+1)) ;;
    esac
    case "$PC_DEBLOAT_BG" in
        on) pc_run deep-tune.sh debloat on; _n=$((_n+1)) ;;
    esac
    case "$PC_OBSCURE" in
        on) pc_run adb-tweaks.sh obscure; _n=$((_n+1)) ;;
    esac
    case "$PC_ART" in
        nao|'') ;;
        *) pc_run turbo.sh art-all "$PC_ART"; _n=$((_n+1)) ;;
    esac
    case "$PC_DEXOPT" in
        # bg-dexopt-job só AGENDA a compilação: o Android a roda quando o
        # aparelho está parado. `dexopt run` compilaria tudo na hora e travaria
        # a aplicação do perfil por vários minutos.
        on) pc_run turbo.sh dexopt-bg; _n=$((_n+1)) ;;
    esac

    # --- gráficos / tela ---
    case "$PC_GPU" in
        on) pc_run adb-tweaks.sh gpu; _n=$((_n+1)) ;;
    esac
    case "$PC_DISPLAY" in
        on) pc_run deep-tune.sh display on; _n=$((_n+1)) ;;
    esac
    case "$PC_GAMING" in
        on) pc_run deep-tune.sh gaming on; _n=$((_n+1)) ;;
    esac
    case "$PC_RENDERER" in
        skiagl|skiavk) pc_run adb-tweaks.sh renderer "$PC_RENDERER"; _n=$((_n+1)) ;;
    esac
    case "$PC_HZ" in
        off|'') ;;
        *) pc_run turbo.sh refresh_fixed "$PC_HZ"; _n=$((_n+1)) ;;
    esac
    case "$PC_TELA" in
        on) pc_run adb-tweaks.sh screen; _n=$((_n+1)) ;;
    esac
    case "$PC_RES" in
        auto) pc_run resolution.sh auto; _n=$((_n+1)) ;;
        nao|'') ;;
        *) pc_run resolution.sh apply "$PC_RES"; _n=$((_n+1)) ;;
    esac
    case "$PC_EFEITOS" in
        ligados) pc_run adb-tweaks.sh effects on;  _n=$((_n+1)) ;;
        leves)   pc_run adb-tweaks.sh effects off; _n=$((_n+1)) ;;
    esac
    case "$PC_JANELAS" in
        on) pc_run adb-tweaks.sh window_tweaks; _n=$((_n+1)) ;;
    esac
    case "$PC_BARRAS" in
        visiveis|status|nav|full) pc_run adb-tweaks.sh sysbars "$PC_BARRAS"; _n=$((_n+1)) ;;
    esac

    # --- toque ---
    case "$PC_TOUCH" in
        none|'') ;;
        *) pc_run ff-touch.sh "$PC_TOUCH"; _n=$((_n+1)) ;;
    esac
    case "$PC_TOUCHLAT" in
        leve)  pc_run adb-tweaks.sh touch_latency 110 300 0 2; _n=$((_n+1)) ;;
        forte) pc_run adb-tweaks.sh touch_latency 100 200 0 0; _n=$((_n+1)) ;;
    esac
    case "$PC_TOUCHMULTI" in
        nao|'') ;;
        *) pc_run adb-tweaks.sh touch_multi "$PC_TOUCHMULTI"; _n=$((_n+1)) ;;
    esac

    # --- barra de status (ajuste fino) ---
    case "$PC_BARRAS_BAT" in
        on|off) pc_run adb-tweaks.sh sysbars battery "$PC_BARRAS_BAT"; _n=$((_n+1)) ;;
    esac
    case "$PC_BARRAS_RELOGIO" in
        on|off) pc_run adb-tweaks.sh sysbars clock "$PC_BARRAS_RELOGIO"; _n=$((_n+1)) ;;
    esac
    case "$PC_BARRAS_ICONES" in
        limpa) pc_run adb-tweaks.sh sysbars clean; _n=$((_n+1)) ;;
    esac

    # --- rede ---
    case "$PC_DNS" in
        cloudflare|adguard|quad9|google) pc_run dns.sh "$PC_DNS"; _n=$((_n+1)) ;;
    esac
    case "$PC_NET" in
        on) pc_run adb-tweaks.sh net; _n=$((_n+1)) ;;
    esac
    case "$PC_LATENCY" in
        on) pc_run adb-tweaks.sh latency; _n=$((_n+1)) ;;
    esac
    case "$PC_WIFI" in
        on) pc_run adb-tweaks.sh wifi; _n=$((_n+1)) ;;
    esac
    case "$PC_MOBILE" in
        on) pc_run adb-tweaks.sh mobile_net; _n=$((_n+1)) ;;
    esac

    # --- bateria / sono ---
    case "$PC_BATTERY" in
        on) pc_run adb-tweaks.sh battery; _n=$((_n+1)) ;;
    esac
    case "$PC_DOZE" in
        on) pc_run adb-tweaks.sh doze on; _n=$((_n+1)) ;;
    esac
    case "$PC_VITALITY" in
        on) pc_run vitality.sh care on; _n=$((_n+1)) ;;
    esac

    # --- notificações ---
    case "$PC_NOTIF" in
        on) pc_run adb-tweaks.sh notif; _n=$((_n+1)) ;;
    esac
    case "$PC_DND" in
        on) pc_run adb-tweaks.sh dnd; _n=$((_n+1)) ;;
    esac
    case "$PC_GAMEFOCUS" in
        on) pc_run adb-tweaks.sh game_focus; _n=$((_n+1)) ;;
    esac

    # --- limpeza (por último: libera o que sobrou) ---
    case "$PC_TRIM" in
        on) pc_run turbo.sh trim; _n=$((_n+1)) ;;
    esac
    case "$PC_KILLBG" in
        on) pc_run turbo.sh killbg; _n=$((_n+1)) ;;
    esac
    case "$PC_CLEAN" in
        off|'') ;;
        *) pc_run clean.sh now "$PC_CLEAN"; _n=$((_n+1)) ;;
    esac

    if [ "$_n" = "0" ]; then
        warn "nenhum recurso ligado — use 'profile-custom.sh set <chave> <valor>'"
        return 1
    fi
    printf '%s\n' "custom" > "$PC_CUR" 2>/dev/null
    say "$_n recurso(s) aplicado(s). Reverta em 'profile-custom.sh off'."
    return 0
}

# --- mostra a configuração -----------------------------------------------------
pc_show() {
    pc_load
    printf '\n  %s◆%s  %sPERFIL PERSONALIZADO%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    _on="$(cat "$PC_CUR" 2>/dev/null)"
    printf '  %sestado:%s %s\n\n' "$C_A" "$C_R" "${_on:+ativo (aplicado)}${_on:-não aplicado}"
    for _k in $PC_ORDER; do
        printf '   %-10s %s\n' "$_k" "$(pc_getvar "$_k")"
    done
    printf '\n  %sAplicar:%s profile-custom.sh apply\n' "$C_A" "$C_R"
    printf '  %sReverter:%s profile-custom.sh off\n\n' "$C_A" "$C_R"
}

# --- execução -----------------------------------------------------------------
acao="${1:-show}"; [ $# -gt 0 ] && shift

case "$acao" in
    show|status)
        pc_show ;;

    set)
        [ $# -gt 0 ] || { err "uso: profile-custom.sh set <chave> <valor> | set k=v ..."; exit 1; }
        # aceita "k=v" (um ou vários) ou "<chave> <valor>"
        case "$1" in
            *=*) pc_set_all "$@" || { pc_show; exit 1; } ;;
            *)   _k="$1"; _v="${2:-}"
                 if pc_valid "$_k" "$_v"; then pc_save "$_k" "$_v"
                 else err "opção inválida: $_k=$_v"; pc_show; exit 1; fi ;;
        esac
        say "Configuração salva"
        pc_show ;;

    apply|on)
        # O painel manda tudo numa chamada só: os valores na ordem de PC_ORDER.
        # Também aceita "apply k=v ..." e "apply" sem nada (usa o que já está salvo).
        if [ $# -gt 0 ]; then
            case "$1" in
                *=*) pc_set_all "$@" || { pc_show; exit 1; } ;;
                *)   pc_set_pos "$@" || { pc_show; exit 1; } ;;
            esac
        fi
        pc_reset; pc_apply ;;

    off)
        pc_reset; rm -f "$PC_CUR" 2>/dev/null
        say "Perfil personalizado desligado (aparelho de volta ao padrão)" ;;

    reset)
        rm -f "$PC_CFG" "$PC_CUR" 2>/dev/null
        say "Configuração apagada (tudo desligado)" ;;

    keys)
        printf '%s\n' $PC_ORDER ;;

    *) pc_show ;;
esac
rc=$?

OTM_V_APPLIES=$PC_A; OTM_V_CHANGED=$PC_C; OTM_V_FAILED=$PC_F
otm_v_report profile-custom
exit $rc
