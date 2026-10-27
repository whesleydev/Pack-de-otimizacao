#!/system/bin/sh
# =============================================================================
#  smart-opt.sh - Otimizador Inteligente.
#
#  Em vez de aplicar o mesmo pacote para todo mundo, ele:
#     1) LÊ o aparelho de ponta a ponta (SoC, GPU, CPU, RAM, tela, térmico,
#        bateria, armazenamento, Android, kernel) — só leitura, nada é alterado;
#     2) CLASSIFICA o aparelho (topo/alto/médio/entrada) e calcula uma NOTA;
#     3) DECIDE item por item o que aplicar, mostrando o motivo de cada escolha;
#     4) APLICA delegando aos módulos já testados do pack (perf, mem, renderer,
#        refresh, clean, anti-relog) — tudo reversível.
#
#  Debloat NAO faz parte daqui de proposito: remover apps de fabrica e uma decisao
#  do usuario, com previa e reversao proprias. Fica na categoria "Debloat".
#
#  Nada é inventado: cada número vem de uma leitura real. O que o aparelho não
#  expõe aparece como "—" e a decisão cai no valor seguro.
#
#  Uso:
#     smart-opt.sh auto               # FAZ TUDO: lê, decide e otimiza sob medida
#     smart-opt.sh analyze            # relatório completo (não altera nada)
#     smart-opt.sh plan [perfil]      # o que seria aplicado e por quê
#     smart-opt.sh apply [perfil]     # aplica
#     smart-opt.sh status             # o que está ativo agora
#     smart-opt.sh restore            # desfaz TUDO o que o pack aplicou
#
#  Perfis: auto | equilibrado | desempenho | jogo | bateria
#     auto         escolhe sozinho pelo tipo de aparelho (padrão)
#     equilibrado  bom para o dia a dia em qualquer aparelho
#     desempenho   máxima resposta (animações 0, RAM de jogo, Hz no topo)
#     jogo         desempenho + anti-relog e foco de jogo no seu jogo
#     bateria      economiza (60Hz, doze rápido, menos apps em cache)
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"
scope_begin smart-opt
otm_v_reset

SO_ST="$ST/smart"
mkdir -p "$SO_ST" 2>/dev/null
SO_LAST="$SO_ST/last"      # perfil aplicado por último

_num() { printf '%s' "$1" | tr -cd '0-9'; }

# =============================================================================
#  1) LEITURA DO APARELHO
# =============================================================================
soc_family() {
    p="$(sh_get 'getprop ro.board.platform')"
    h="$(sh_get 'getprop ro.hardware')"
    s="$(sh_get 'getprop ro.soc.model')"
    b="$(sh_get 'getprop ro.product.board')"
    all="$(printf '%s %s %s %s' "$p" "$h" "$s" "$b" | tr 'A-Z' 'a-z')"
    case "$all" in
        *sm[0-9]*|*msm*|*sdm*|*qcom*|*kona*|*waipio*|*kalama*|*pineapple*|*snapdragon*) echo snapdragon ;;
        *mt[0-9]*|*dimensity*|*mediatek*|*mtk*) echo dimensity ;;
        *exynos*|*universal*|*s5e*) echo exynos ;;
        *tensor*|*gs[0-9]*|*zuma*|*husky*) echo tensor ;;
        *kirin*|*hi[0-9]*) echo kirin ;;
        *) echo desconhecido ;;
    esac
}

gpu_vendor() {
    g="$(sh_get 'getprop ro.hardware.egl')"
    case "$g" in
        *adreno*) echo Adreno ;;
        *mali*) echo Mali ;;
        *powervr*|*pvrs*) echo PowerVR ;;
        *) [ -d /sys/class/kgsl/kgsl-3d0 ] && echo "Adreno (kgsl)" || echo '?' ;;
    esac
}

cpu_max_freq() {   # MHz (0 se não der para ler)
    mx=0
    for d in /sys/devices/system/cpu/cpu[0-9]*/cpufreq; do
        [ -d "$d" ] || continue
        f="$(sh_get "cat $d/cpuinfo_max_freq")"
        [ -z "$f" ] && f="$(sh_get "cat $d/scaling_max_freq")"
        f="$(_num "$f")"
        if [ -n "$f" ] && [ "$f" -gt "$mx" ] 2>/dev/null; then mx="$f"; fi
    done
    if [ "$mx" -eq 0 ]; then
        f="$(sh_get 'cat /proc/cpuinfo' | awk -F: '/cpu MHz/{gsub(/ /,"",$2); if ($2+0>m) m=$2+0} END{printf "%d", m}')"
        mx="$(_num "$f")"
    fi
    [ -n "$mx" ] && [ "$mx" -gt 0 ] 2>/dev/null && echo "$((mx / 1000))" || echo 0
}

cpu_cores() {
    n="$(sh_get 'nproc')"
    [ -z "$n" ] && n="$(sh_get 'cat /proc/cpuinfo' | grep -c '^processor')"
    n="$(_num "$n")"
    [ -n "$n" ] && [ "$n" -gt 0 ] 2>/dev/null && echo "$n" || echo 0
}

display_max_hz() {   # maior taxa suportada (0 se não der para ler)
    out="$(sh_get 'dumpsys display')"
    hz=""
    if [ -n "$out" ]; then
        hz="$(printf '%s\n' "$out" | grep -oE 'fps=[0-9]+(\.[0-9]+)?' | cut -d= -f2 | sort -n | tail -1)"
        [ -z "$hz" ] && hz="$(printf '%s\n' "$out" | grep -oE '[0-9]+(\.[0-9]+)?fps' | tr -d 'fps' | sort -n | tail -1)"
    fi
    case "$hz" in ''|*[!0-9.]*) echo 0; return ;; esac
    printf '%s' "$hz" | awk '{printf "%d", $1}'
}

storage_free_mb() {
    f="$(sh_get 'df /data' | awk 'NR==2{print $4}')"
    [ -z "$f" ] && f="$(sh_get 'df /' | awk 'NR==2{print $4}')"
    f="$(_num "$f")"
    [ -n "$f" ] && [ "$f" -gt 0 ] 2>/dev/null && echo "$((f / 1024))" || echo 0
}

battery_level() {
    v="$(sh_get 'dumpsys battery' | awk -F': ' '/ level:/{print $2}')"
    v="$(_num "$v")"
    [ -n "$v" ] && [ "$v" -gt 0 ] 2>/dev/null && echo "$v" || echo ""
}

# collect -> preenche as variáveis da análise (uma leitura só)
collect() {
    API="$(sh_get 'getprop ro.build.version.sdk')"; API="$(_num "$API")"
    [ -z "$API" ] && API=0
    ANDROID="$(sh_get 'getprop ro.build.version.release')"
    [ -z "$ANDROID" ] && ANDROID="?"
    KERNEL="$(sh_get 'uname -r')"
    [ -z "$KERNEL" ] && KERNEL="?"
    MODEL="$(sh_get 'getprop ro.product.model')"
    [ -z "$MODEL" ] && MODEL="?"
    MAKER="$(sh_get 'getprop ro.product.manufacturer')"
    [ -z "$MAKER" ] && MAKER="?"
    ABI="$(sh_get 'getprop ro.product.cpu.abi')"
    [ -z "$ABI" ] && ABI="?"

    SOC="$(soc_family)"
    GPU="$(gpu_vendor)"

    tot="$(otm_meminfo MemTotal)"; tot="$(_num "$tot")"
    RAM_MB=0
    [ -n "$tot" ] && [ "$tot" -gt 0 ] 2>/dev/null && RAM_MB=$((tot / 1024))
    CORES="$(cpu_cores)"
    MAXFREQ="$(cpu_max_freq)"
    HZ_MAX="$(display_max_hz)"
    STORAGE_MB="$(storage_free_mb)"
    TEMP="$(otm_temp)"
    BATT="$(battery_level)"
    LOW_RAM="$(sh_get 'getprop ro.config.low_ram')"
    case "$LOW_RAM" in true|1) LOW_RAM=1 ;; *) LOW_RAM=0 ;; esac
    ZRAM="$(sh_get 'cat /proc/swaps' | awk '/zram/{n++} END{print n+0}')"
    ZONES="$(ls -d /sys/class/thermal/thermal_zone[0-9]* 2>/dev/null | wc -l | tr -d ' ')"
    CLUSTERS="$(ls -d /sys/devices/system/cpu/cpu[0-9]*/cpufreq 2>/dev/null | wc -l | tr -d ' ')"
    GOV="$(sh_get 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor')"
    MGLRU="$(sh_get 'cat /sys/kernel/mm/lru_gen/enabled')"
    TCPCC="$(sh_get 'sysctl -n net.ipv4.tcp_available_congestion_control')"
    case "$TCPCC" in *bbr*) BBR=1 ;; *) BBR=0 ;; esac
    APPS3="$(sh_get 'pm list packages -3' | grep -c . )"
    APPS3="$(_num "$APPS3")"

    # RAM realmente disponível agora (diz se o aparelho está apertado neste momento)
    RAM_LIVRE="$(otm_ram_livre_mb)"
    RAM_LIVRE="$(_num "$RAM_LIVRE")"
    [ -z "$RAM_LIVRE" ] && RAM_LIVRE=0

    # Throttling térmico: 0=none 1=light 2=moderate 3=severe 4=critical 5=emergency
    THERM="$(sh_get 'dumpsys thermalservice' | awk -F': ' '/Thermal Status/{print $2; exit}' | tr -cd '0-9')"
    [ -z "$THERM" ] && THERM=""

    # Economia de energia ligada? (muda o que faz sentido aplicar agora)
    PSAVER="$(sh_get 'settings get global low_power')"
    case "$PSAVER" in 1) PSAVER=1 ;; *) PSAVER=0 ;; esac

    classify
}

# NOTA (0..100) e CLASSE (topo/alto/medio/entrada) a partir do que foi lido
classify() {
    s=0
    if   [ "$RAM_MB" -ge 16000 ] 2>/dev/null; then s=$((s+40))
    elif [ "$RAM_MB" -ge 12000 ] 2>/dev/null; then s=$((s+36))
    elif [ "$RAM_MB" -ge 8000 ]  2>/dev/null; then s=$((s+30))
    elif [ "$RAM_MB" -ge 6000 ]  2>/dev/null; then s=$((s+24))
    elif [ "$RAM_MB" -ge 4000 ]  2>/dev/null; then s=$((s+16))
    elif [ "$RAM_MB" -ge 3000 ]  2>/dev/null; then s=$((s+10))
    else s=$((s+4)); fi

    if   [ "$CORES" -ge 8 ] 2>/dev/null; then s=$((s+15))
    elif [ "$CORES" -ge 6 ] 2>/dev/null; then s=$((s+12))
    elif [ "$CORES" -ge 4 ] 2>/dev/null; then s=$((s+8))
    else s=$((s+4)); fi

    if   [ "$MAXFREQ" -ge 3000 ] 2>/dev/null; then s=$((s+15))
    elif [ "$MAXFREQ" -ge 2400 ] 2>/dev/null; then s=$((s+12))
    elif [ "$MAXFREQ" -ge 2000 ] 2>/dev/null; then s=$((s+8))
    elif [ "$MAXFREQ" -ge 1600 ] 2>/dev/null; then s=$((s+5))
    else s=$((s+2)); fi

    if   [ "$API" -ge 33 ] 2>/dev/null; then s=$((s+15))
    elif [ "$API" -ge 30 ] 2>/dev/null; then s=$((s+12))
    elif [ "$API" -ge 29 ] 2>/dev/null; then s=$((s+10))
    elif [ "$API" -ge 26 ] 2>/dev/null; then s=$((s+6))
    else s=$((s+2)); fi

    case "$SOC" in desconhecido) s=$((s+4)) ;; *) s=$((s+10)) ;; esac
    [ "$LOW_RAM" = "1" ] && s=$((s-10))
    [ "$s" -lt 0 ] && s=0
    [ "$s" -gt 100 ] && s=100
    SCORE="$s"

    if   [ "$SCORE" -ge 80 ]; then TIER=topo
    elif [ "$SCORE" -ge 60 ]; then TIER=alto
    elif [ "$SCORE" -ge 40 ]; then TIER=medio
    else TIER=entrada; fi
    [ "$LOW_RAM" = "1" ] && TIER=entrada
}

# =============================================================================
#  2) RELATÓRIO (analyze) - não altera nada
# =============================================================================
cmd_analyze() {
    collect
    printf '  %s◆%s  %sOTIMIZADOR INTELIGENTE · análise%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %smodelo%s        %s (%s)\n' "$C_A" "$C_R" "$MODEL" "$MAKER"
    printf '  %sAndroid%s       %s (API %s) · kernel %s\n' "$C_A" "$C_R" "$ANDROID" "$API" "$KERNEL"
    printf '  %sSoC%s           %s\n' "$C_A" "$C_R" "$SOC"
    printf '  %sGPU%s           %s\n' "$C_A" "$C_R" "$GPU"
    printf '  %sABI%s           %s\n' "$C_A" "$C_R" "$ABI"
    printf '  %sCPU%s           %s núcleos · %s MHz de pico · %s cluster(s)\n' \
        "$C_A" "$C_R" "${CORES:-—}" "${MAXFREQ:-—}" "${CLUSTERS:-—}"
    printf '  %sRAM%s           %s MB\n' "$C_A" "$C_R" "${RAM_MB:-—}"
    printf '  %sRAM livre%s    %s\n' "$C_A" "$C_R" \
        "$([ "${RAM_LIVRE:-0}" -gt 0 ] 2>/dev/null && printf '%s MB%s' "$RAM_LIVRE" \
            "$([ "$D_APERTADO" = "1" ] && printf ' %s(aparelho apertado agora)%s' "$C_Y" "$C_R")" || echo '—')"
    printf '  %stela%s          %s Hz suportado\n' "$C_A" "$C_R" "$([ "${HZ_MAX:-0}" -gt 0 ] 2>/dev/null && echo "$HZ_MAX" || echo '—')"
    printf '  %sarmazenamento%s %s MB livres\n' "$C_A" "$C_R" "${STORAGE_MB:-—}"
    printf '  %stérmico%s       %s zona(s)%s\n' "$C_A" "$C_R" "${ZONES:-—}" \
        "$([ -n "$TEMP" ] && printf ' · %s °C agora' "$TEMP")"
    printf '  %sbateria%s       %s\n' "$C_A" "$C_R" "$([ -n "$BATT" ] && printf '%s%%' "$BATT" || echo '—')"
    printf '  %szram%s          %s dispositivo(s)\n' "$C_A" "$C_R" "${ZRAM:-0}"
    printf '  %sgovernor%s      %s\n' "$C_A" "$C_R" "${GOV:-—}"
    printf '  %sMGLRU%s         %s\n' "$C_A" "$C_R" "${MGLRU:-não exposto}"
    printf '  %sTCP%s           %s%s\n' "$C_A" "$C_R" \
        "$([ "$BBR" = 1 ] && echo 'BBR disponível' || echo 'BBR não disponível')" \
        "$([ -n "$TCPCC" ] && printf ' (%s)' "$TCPCC")"
    printf '  %sapps de usuário%s %s\n' "$C_A" "$C_R" "${APPS3:-—}"
    [ "$LOW_RAM" = "1" ] && printf '  %sAndroid Go / pouca memória detectado%s\n' "$C_Y" "$C_R"
    echo
    printf '  %sclasse%s        %s\n' "$C_A" "$C_R" "$(tier_label "$TIER")"
    printf '  %snota%s          %s/100\n' "$C_A" "$C_R" "$SCORE"
    printf '  %sperfil sugerido%s %s\n' "$C_A" "$C_R" "$(auto_profile)"
    printf '  %sperfil aplicado%s %s\n' "$C_A" "$C_R" "$(cat "$SO_LAST" 2>/dev/null || echo 'nenhum')"
    [ -n "$SO_SILENT_NEXT" ] || {
        echo
        printf '  %spróximo passo:%s smart-opt.sh plan  (ver as decisões)\n' "$C_A" "$C_R"
    }
}

# =============================================================================
#  3b) AUTO - o comando único: lê, decide e aplica tudo de uma vez
# =============================================================================
cmd_auto() {
    SO_SILENT_NEXT=1
    cmd_analyze
    echo
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    cmd_apply auto || return 1
}

tier_label() {
    case "$1" in
        topo) echo "topo de linha" ;;
        alto) echo "alto desempenho" ;;
        medio) echo "intermediário" ;;
        *) echo "entrada / modesta" ;;
    esac
}

# =============================================================================
#  3) DECISÕES (plan / apply)
# =============================================================================
# decide <perfil> -> preenche D_* com o que aplicar. Nada é executado aqui.
decide() {
    prof="$1"
    [ -z "$prof" ] && prof="auto"
    [ "$prof" = "auto" ] && prof="$(auto_profile)"

    case "$prof" in
        equilibrado|desempenho|jogo|bateria) ;;
        *) err "perfil inválido: $prof"; return 1 ;;
    esac
    D_PROF="$prof"

    # animações: 0 no desempenho/jogo, 0.5x no resto
    case "$prof" in
        desempenho|jogo) D_ANIM="zero" ;;
        *) D_ANIM="meio" ;;
    esac

    # quantos apps ficam em cache (quanto menor, mais RAM para o que importa)
    case "$prof" in
        jogo)       D_RAM=4 ;;
        desempenho) D_RAM=8 ;;
        bateria)    D_RAM=8 ;;
        *)
            case "$TIER" in
                topo) D_RAM=32 ;;
                alto) D_RAM=24 ;;
                medio) D_RAM=16 ;;
                *) D_RAM=8 ;;
            esac ;;
    esac
    # aparelho apertado AGORA (pouca RAM livre em relação ao total): segura mais
    # o segundo plano, senão o app em uso é que sofre.
    D_APERTADO=0
    if [ "$RAM_MB" -gt 0 ] 2>/dev/null && [ "$RAM_LIVRE" -gt 0 ] 2>/dev/null; then
        limite=$((RAM_MB * 12 / 100))
        [ "$RAM_LIVRE" -lt "$limite" ] 2>/dev/null && D_APERTADO=1
    fi

    # Phantom Process Killer: em aparelho com RAM de sobra pode ficar off (não
    # mata processos "fantasma"); em aparelho modesto, ligado (protege a RAM).
    if [ "$RAM_MB" -ge 6000 ] 2>/dev/null; then D_PHANTOM=off; else D_PHANTOM=on; fi

    # renderizador: Vulkan costuma render mais em GPU recente; GL é o seguro
    if [ "$API" -ge 30 ] 2>/dev/null; then
        case "$GPU" in
            Adreno*) D_RENDERER=skiavk ;;
            Mali*)   D_RENDERER=skiavk ;;
            *)       D_RENDERER=skiagl ;;
        esac
    else
        D_RENDERER=skiagl
    fi

    # taxa de tela: a maior que o aparelho suporta; bateria trava em 60Hz.
    # Se o aparelho não informa a taxa, NÃO chutamos: deixamos no automático.
    hz="${HZ_MAX:-0}"
    if [ "$prof" = "bateria" ]; then
        D_HZ=60
    elif [ "$hz" -gt 0 ] 2>/dev/null; then
        D_HZ="$(snap_hz "$hz")"
    else
        D_HZ=""
    fi

    # limpeza: jogo/desempenho só liberam RAM; o resto suaviza também.
    # Com o aparelho já apertado, a limpeza vai mais fundo (normal) para liberar de verdade.
    case "$prof" in
        desempenho|jogo) D_CLEAN=fundo ;;
        *)               D_CLEAN=suave ;;
    esac
    [ "$D_APERTADO" = "1" ] && D_CLEAN=normal
    # aparelho apertado AGORA: segura o segundo plano, senão o app em uso sofre
    if [ "$D_APERTADO" = "1" ]; then
        case "$prof" in
            bateria) : ;;
            jogo)    D_RAM=4 ;;
            *)       D_RAM=8 ;;
        esac
    fi

    # doze rápido: economia no equilíbrio/bateria; no jogo atrapalharia.
    # Se o usuário já está com a economia de energia ligada, respeitamos (não forçamos).
    case "$prof" in
        equilibrado|bateria) D_DOZE=on ;;
        *)                   D_DOZE=off ;;
    esac
    [ "$PSAVER" = "1" ] && [ "$prof" != "jogo" ] && D_DOZE=off

    # anti-relog no jogo escolhido (só no perfil jogo)
    D_GAME="$(game_pkg)"
    [ "$prof" = "jogo" ] || D_GAME=""

    # cautela térmica: SoC que esquenta cedo OU aparelho já throttlando agora.
    # Nesse caso o otimizador evita forçar o kernel (não piora o aquecimento).
    case "$SOC" in
        tensor|exynos) D_THERMAL=cautela ;;
        *)             D_THERMAL=normal ;;
    esac
    case "$THERM" in
        2|3|4|5) D_THERMAL=cautela ;;
    esac
    # com a tela no topo de Hz e o aparelho quente, segurar a taxa evita throttling
    if [ "$D_THERMAL" = cautela ] && [ "$prof" != "bateria" ] && [ -n "$D_HZ" ]; then
        D_HZ="$(snap_hz "$((D_HZ > 90 ? 90 : D_HZ))")"
    fi
    return 0
}

snap_hz() {   # arredonda para 60/90/120/144 (o que o turbo aceita)
    h="$1"
    case "$h" in
        60|90|120|144) echo "$h" ;;
        *) if   [ "$h" -ge 144 ] 2>/dev/null; then echo 144
           elif [ "$h" -ge 120 ] 2>/dev/null; then echo 120
           elif [ "$h" -ge 90 ]  2>/dev/null; then echo 90
           else echo 60; fi ;;
    esac
}

game_pkg() {
    f="$ST/game/pkg"
    [ -f "$f" ] && head -1 "$f" 2>/dev/null
}

auto_profile() {
    # com jogo escolhido, o que faz diferença é o perfil de jogo
    [ -n "$(game_pkg)" ] && { echo jogo; return; }
    case "$TIER" in
        topo|alto) echo desempenho ;;
        *)         echo equilibrado ;;
    esac
}

cmd_plan() {
    collect
    decide "$1" || return 1
    printf '  %s◆%s  %sPLANO DO OTIMIZADOR%s  %s(perfil %s)%s\n' \
        "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$D_PROF" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %saparelho%s  %s · %s MB RAM · %s núcleos · %s MHz · %s/100\n' \
        "$C_A" "$C_R" "$(tier_label "$TIER")" "$RAM_MB" "${CORES:-—}" "${MAXFREQ:-—}" "$SCORE"
    echo
    printf '   %sanimação%s    %s   %s\n' "$C_A" "$C_R" \
        "$([ "$D_ANIM" = zero ] && echo '0 (instantâneo)' || echo '0.5x (rápido)')" \
        "$([ "$D_ANIM" = zero ] && echo 'menos espera entre telas' || echo 'resposta mais rápida sem parecer seco')"
    printf '   %sRAM em cache%s %s apps   %s\n' "$C_A" "$C_R" "$D_RAM" \
        "$([ "$D_APERTADO" = 1 ] && echo 'RAM apertada agora: mais apps saem do segundo plano' || echo 'sobra mais RAM para o app/jogo em uso')"
    printf '   %srenderizador%s %s   %s\n' "$C_A" "$C_R" "$D_RENDERER" \
        "$([ "$D_RENDERER" = skiavk ] && echo 'Vulkan: mais fluidez na GPU' || echo 'GL: máxima compatibilidade')"
    printf '   %staxa de tela%s %s   %s\n' "$C_A" "$C_R" \
        "$([ -n "$D_HZ" ] && echo "${D_HZ} Hz" || echo 'automática')" \
        "$([ -n "$D_HZ" ] && echo 'a maior taxa que o aparelho suporta' || echo 'não deu para ler a taxa; fica no padrão')"
    printf '   %slimpeza%s     %s   %s\n' "$C_A" "$C_R" "$D_CLEAN" \
        "$([ "$D_CLEAN" = suave ] && echo 'libera RAM e suaviza' || echo 'só libera RAM (não mexe em ajustes)')"
    printf '   %sphantom%s     %s   %s\n' "$C_A" "$C_R" "$D_PHANTOM" \
        "$([ "$D_PHANTOM" = off ] && echo 'RAM de sobra: não mata processos fantasma' || echo 'pouca RAM: protege a memória')"
    printf '   %sdoze%s        %s   %s\n' "$C_A" "$C_R" "$D_DOZE" \
        "$([ "$D_DOZE" = on ] && echo 'dorme rápido com a tela apagada' || echo 'deixado como está (perfil de jogo)')"
    [ -n "$D_GAME" ] && printf '   %santi-relog%s  %s   %s\n' "$C_A" "$C_R" "$D_GAME" \
        "não fecha nem volta ao login"
    [ "$D_THERMAL" = cautela ] && \
        printf '   %stérmico%s     cautela   %s\n' "$C_Y" "$C_R" \
        "$SOC esquenta cedo: evitado forçar o kernel"
    echo
    printf '  %saplicar:%s smart-opt.sh apply %s\n' "$C_A" "$C_R" "$D_PROF"
}

# =============================================================================
#  4) APLICAÇÃO (apply)
# =============================================================================
# Cada passo é delegado a um módulo já testado do pack; a reversão fica no
# escopo daquele módulo e o `restore` geral percorre todos.
so_step() { printf '\n  %s▸%s  %s\n' "$C_G" "$C_R" "$1"; }

# so_verify <descrição> <comando-de-leitura> <esperado>
# O apply delega aos outros módulos; para o painel não achar que "nada mudou",
# aqui cada ajuste é LIDO DE VOLTA e contado de verdade (#OTM-RESULT).
so_verify() {
    desc="$1"; cmd="$2"; want="$3"
    otm_v_inc apply
    got="$(sh_get "$cmd")"
    if [ "$got" = "$want" ]; then
        otm_v_inc changed
        printf '   %bOK%b %s = %s\n' "$C_G" "$C_R" "$desc" "$want"
    else
        otm_v_inc failed
        printf '   %bX%b %s nao pegou (lido: %s)\n' "$C_RD" "$C_R" "$desc" "${got:-vazio}"
    fi
}

cmd_apply() {
    collect
    decide "$1" || return 1

    printf '  %s◆%s  %sOTIMIZADOR INTELIGENTE%s  %s(perfil %s)%s\n' \
        "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$D_PROF" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %s · %s MB RAM · nota %s/100\n' "$(tier_label "$TIER")" "$RAM_MB" "$SCORE"

    # 1) base: animações, GPU na interface, blur off
    so_step "1/7  Base de performance"
    if [ "$D_ANIM" = zero ]; then
        sh "$DIR/adb-tweaks.sh" perf_max >/dev/null 2>&1
        say "animações desligadas · GPU na interface · blur off"
    else
        sh "$DIR/adb-tweaks.sh" perf >/dev/null 2>&1
        say "animações 0.5x · GPU na interface · blur off"
    fi

    # 2) RAM sob medida para o aparelho
    so_step "2/7  RAM ajustada ao aparelho ($D_RAM apps em cache)"
    proc_limit_set "$D_RAM"
    if [ "$D_PHANTOM" = off ]; then
        am_set max_phantom_processes=2147483647
    else
        am_set max_phantom_processes=1024
    fi

    # 3) renderizador escolhido pela GPU/versão do Android
    so_step "3/7  Renderizador: $D_RENDERER"
    sh "$DIR/adb-tweaks.sh" renderer "$D_RENDERER" >/dev/null 2>&1

    # 4) taxa de tela no melhor valor estável (pulado se não deu para ler)
    if [ -n "$D_HZ" ]; then
        so_step "4/7  Taxa de tela: ${D_HZ}Hz"
        sh "$DIR/turbo.sh" refresh_fixed "$D_HZ" >/dev/null 2>&1
    else
        so_step "4/7  Taxa de tela: mantida no padrão (não deu para ler)"
    fi

    # 5) limpeza e suavização / doze
    so_step "5/6  Limpeza ($D_CLEAN)"
    sh "$DIR/clean.sh" now "$D_CLEAN" >/dev/null 2>&1
    if [ "$D_DOZE" = on ]; then
        sh "$DIR/adb-tweaks.sh" doze on >/dev/null 2>&1
    fi

    # 6) jogo: anti-relog + foco (só no perfil jogo, com jogo escolhido)
    so_step "6/6  Jogo e proteção"
    if [ -n "$D_GAME" ]; then
        sh "$DIR/adb-tweaks.sh" game_keepalive "$D_GAME" >/dev/null 2>&1
        sh "$DIR/adb-tweaks.sh" game_focus >/dev/null 2>&1
        say "anti-relog e foco de jogo em $D_GAME"
    else
        say "nenhum jogo escolhido — pulei o anti-relog (use o Modo Competitivo na Home)"
    fi

    # leitura de volta: confirma que os ajustes pegaram neste aparelho
    echo
    so_verify "animações de janela" "settings get global window_animation_scale" \
        "$([ "$D_ANIM" = zero ] && echo 0 || echo 0.5)"
    so_verify "GPU na interface" "settings get global force_gpu_rendering" 1
    so_verify "renderizador" "getprop debug.hwui.renderer" "$D_RENDERER"
    [ -n "$D_HZ" ] && so_verify "taxa de tela" "settings get system peak_refresh_rate" "${D_HZ}.0"

    printf '%s\n' "$D_PROF" > "$SO_LAST" 2>/dev/null
    echo
    say "otimização aplicada (perfil $D_PROF). Reverta em \"Reverter TUDO\"."
}

# =============================================================================
#  5) STATUS / RESTORE
# =============================================================================
cmd_status() {
    collect
    printf '  %s◆%s  %sOTIMIZADOR INTELIGENTE · estado%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %saparelho:%s %s · %s MB RAM · %s/100 (%s)\n' "$C_A" "$C_R" \
        "$MODEL" "$RAM_MB" "$SCORE" "$(tier_label "$TIER")"
    printf '  %sperfil aplicado:%s %s\n' "$C_A" "$C_R" "$(cat "$SO_LAST" 2>/dev/null || echo 'nenhum')"
    printf '  %sRAM em cache:%s %s\n' "$C_A" "$C_R" \
        "$(sh_get 'settings get global activity_manager_constants')"
    printf '  %srenderizador:%s %s\n' "$C_A" "$C_R" \
        "$(sh_get 'getprop debug.hwui.renderer')"
    printf '  %staxa de tela:%s %s / %s Hz (min/peak)\n' "$C_A" "$C_R" \
        "$(sh_get 'settings get system min_refresh_rate')" \
        "$(sh_get 'settings get system peak_refresh_rate')"
    printf '  %sRAM livre:%s %s MB\n' "$C_A" "$C_R" "${RAM_MB:-—}"
    if [ -s "$ST/keepalive/apps" ]; then
        printf '  %santi-relog:%s %s\n' "$C_A" "$C_R" "$(tr '\n' ' ' < "$ST/keepalive/apps")"
    fi
}

cmd_restore() {
    say "Desfazendo tudo o que o pack aplicou"
    sh "$DIR/adb-tweaks.sh" restore_all >/dev/null 2>&1
    sh "$DIR/deep-tune.sh" restore >/dev/null 2>&1
    sh "$DIR/clean.sh" off >/dev/null 2>&1
    rm -f "$SO_LAST" 2>/dev/null
    say "aparelho de volta ao comportamento original"
}

# =============================================================================
#  RUNNER
# =============================================================================
case "${1:-}" in
    auto)    cmd_auto ;;
    analyze) cmd_analyze ;;
    plan)    shift; cmd_plan "$1" ;;
    apply)   shift; cmd_apply "$1" ;;
    status)  cmd_status ;;
    restore) cmd_restore ;;
    *)
        sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report smart-opt
exit $rc
