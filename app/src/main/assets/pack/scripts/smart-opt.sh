#!/system/bin/sh
# =============================================================================
#  smart-opt.sh - Otimizador Inteligente (v2: mede, escolhe e COMPROVA).
#
#  Em vez de aplicar o mesmo pacote para todo mundo, ele:
#     1) LÊ o aparelho de ponta a ponta (SoC, GPU, CPU/clusters, RAM, tela,
#        térmico, bateria, armazenamento, Android, kernel, zram, MGLRU, rede,
#        governador, pressão de memória) — só leitura, nada é alterado;
#     2) CLASSIFICA o aparelho (topo/alto/médio/entrada) com uma NOTA e diz onde
#        ele está FORA do ideal (os "pontos fracos" que puxam a nota para baixo);
#     3) DECIDE item por item, com rigor: cada escolha mostra o motivo e o risco,
#        e o que não tem dado suficiente cai no valor conservador (nunca chuta);
#     4) TESTA: mede o desempenho ANTES, aplica, mede DEPOIS e compara os dois —
#        se o resultado piorar, ele diz e oferece voltar;
#     5) COMPARA COMBINAÇÕES: quando dois caminhos são plausíveis (ex.: Vulkan ×
#        GL, Hz no topo × 90Hz), ele testa os dois e fica com o melhor.
#
#  Debloat NAO faz parte daqui de proposito: remover apps de fabrica e uma decisao
#  do usuario, com previa e reversao proprias. Fica na categoria "Debloat".
#
#  Nada é inventado: cada número vem de uma leitura real. O que o aparelho não
#  expõe aparece como "—" e a decisão cai no valor seguro.
#
#  Uso:
#     smart-opt.sh auto               # FAZ TUDO: lê, decide, aplica e COMPROVA
#     smart-opt.sh analyze            # relatório completo (não altera nada)
#     smart-opt.sh plan [perfil]      # o que seria aplicado e por quê
#     smart-opt.sh apply [perfil]     # aplica
#     smart-opt.sh bench [perfil]     # mede ANTES x DEPOIS e diz se melhorou
#     smart-opt.sh compare [perfil]   # testa combinações e escolhe a melhor
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
SO_BENCH="$SO_ST/bench"    # última medição (antes x depois)
SO_MEM="$SO_ST/memory"     # o que já APRENDEU neste aparelho (combinação vencedora)

# --- memória do aparelho ------------------------------------------------------
# O otimizador testa combinações no SEU aparelho e guarda qual venceu. Na próxima
# execução ele já começa pela vencedora em vez de repetir a regra técnica — é
# assim que ele fica melhor a cada uso, sem o usuário ver nada disso.
# A chave é a assinatura do hardware: outro aparelho (mesmo modelo, outra RAM ou
# outra tela) não herda o que este aprendeu.
so_mem_key() {
    printf '%s|%s|%s|%s|%s' "${SOC:-?}" "${GPU:-?}" "${RAM_MB:-0}" "${HZ_MAX:-0}" "${API:-0}" \
        | tr -c 'A-Za-z0-9|' '_'
}

so_mem_get() {   # so_mem_get <chave>
    [ -f "$SO_MEM" ] || return 0
    key="$(so_mem_key)"
    sed -n "s/^\($key\) \($1\)=\(.*\)$/\3/p" "$SO_MEM" 2>/dev/null | tail -1
}

so_mem_set() {   # so_mem_set <chave> <valor>
    key="$(so_mem_key)"
    tmp="$SO_MEM.tmp"
    if [ -f "$SO_MEM" ]; then
        grep -v "^\($key\) $1=" "$SO_MEM" > "$tmp" 2>/dev/null || : > "$tmp"
    else
        : > "$tmp"
    fi
    printf '%s %s=%s\n' "$key" "$1" "$2" >> "$tmp"
    mv "$tmp" "$SO_MEM" 2>/dev/null
    # não deixa a memória crescer sem fim num aparelho usado por anos
    n=$(wc -l < "$SO_MEM" 2>/dev/null || echo 0)
    [ "$n" -gt 200 ] 2>/dev/null && tail -100 "$SO_MEM" > "$tmp" 2>/dev/null && mv "$tmp" "$SO_MEM"
    return 0
}

# quantas vezes o otimizador já rodou por aqui (ele melhora com o uso)
so_mem_runs() { so_mem_get runs; }

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

    # --- leituras profundas (v2) ---------------------------------------------
    # Big.Little: frequências por cluster. Um aparelho com o cluster forte fraco
    # segura o jogo mesmo com muitos núcleos — antes isso passava batido.
    CL_FREQS=""
    for c in /sys/devices/system/cpu/cpufreq/policy*/cpuinfo_max_freq \
             /sys/devices/system/cpu/cpu[0-9]*/cpufreq/cpuinfo_max_freq; do
        [ -f "$c" ] || continue
        f="$(sh_get "cat $c" 2>/dev/null | tr -cd '0-9')"
        [ -z "$f" ] && continue
        f=$((f / 1000))
        case " $CL_FREQS " in *" $f "*) ;; *) CL_FREQS="$CL_FREQS $f" ;; esac
    done
    CL_FREQS="$(printf '%s' "$CL_FREQS" | sed 's/^ *//')"
    N_CLUSTERS="$(printf '%s' "$CL_FREQS" | wc -w | tr -d ' ')"

    # AVX/ISA e arquitetura da CPU: dizem a geração (um Cortex-A53 não entrega
    # o mesmo que um X4, mesmo com a mesma frequência).
    CPU_ISA="$(sh_get 'cat /proc/cpuinfo' | sed -n 's/^Features *: *//p' | head -1)"
    CPU_HW="$(sh_get 'cat /proc/cpuinfo' | sed -n 's/^Hardware *: *//p' | head -1)"
    case "$CPU_ISA" in *asimd*|*neon*) SIMD=1 ;; *) SIMD=0 ;; esac

    # Pressão de memória REAL do kernel (0-100): melhor sinal que "RAM livre"
    # sozinho, porque já leva em conta cache, swap e reclaim.
    PSI_MEM="$(sh_get 'cat /proc/pressure/memory' \
        | sed -n 's/.*avg10=\([0-9.]*\).*/\1/p' | head -1)"
    PSI_CPU="$(sh_get 'cat /proc/pressure/cpu' \
        | sed -n 's/.*avg10=\([0-9.]*\).*/\1/p' | head -1)"

    # Entropia: baixa entropia atrasa TLS e abertura de app em aparelho recém-ligado
    ENTROPY="$(sh_get 'cat /proc/sys/kernel/random/entropy_avail')"; ENTROPY="$(_num "$ENTROPY")"

    # Memória do sistema: swap/zram em uso e o quanto o kernel está comprimindo
    SWAP_USO="$(sh_get 'cat /proc/swaps' | awk 'NR>1{s+=$4} END{print s+0}')"
    SWAP_USO="$(_num "$SWAP_USO")"
    VM_DIRTY="$(sh_get 'sysctl -n vm.dirty_ratio')"; VM_DIRTY="$(_num "$VM_DIRTY")"
    VM_SWAPPY="$(sh_get 'sysctl -n vm.swappiness')"; VM_SWAPPY="$(_num "$VM_SWAPPY")"

    # I/O: se o armazenamento está saturado, mexer em CPU/GPU não adianta.
    IO_SCHED="$(sh_get 'cat /sys/block/sda/queue/scheduler' 2>/dev/null)"
    [ -z "$IO_SCHED" ] && IO_SCHED="$(sh_get 'cat /sys/block/mmcblk0/queue/scheduler' 2>/dev/null)"

    # Tela: densidade e tamanho (dp) — decide se a resolução alta compensa
    DENSITY="$(sh_get 'wm density' | sed -n 's/.*Physical density: *\([0-9]*\).*/\1/p' | tail -1)"
    DENSITY="$(_num "$DENSITY")"
    RES_ATUAL="$(sh_get 'wm size' | sed -n 's/.*Override size: *\([0-9]*x[0-9]*\).*/\1/p' | tail -1)"
    [ -z "$RES_ATUAL" ] && RES_ATUAL="$(sh_get 'wm size' \
        | sed -n 's/.*Physical size: *\([0-9]*x[0-9]*\).*/\1/p' | tail -1)"
    RES_W="${RES_ATUAL%x*}"; RES_H="${RES_ATUAL#*x}"
    RES_W="$(_num "$RES_W")"; RES_H="$(_num "$RES_H")"
    # densidade lógica (dp de largura): tela "grande em dp" = painel apertado
    if [ -n "$DENSITY" ] && [ "$DENSITY" -gt 0 ] 2>/dev/null && [ -n "$RES_W" ] && [ "$RES_W" -gt 0 ] 2>/dev/null; then
        DP_W=$((RES_W * 160 / DENSITY))
    else
        DP_W=0
    fi

    # Renderizador que está valendo agora (para saber se o apply mudou de fato)
    RENDERER_ATUAL="$(sh_get 'getprop debug.hwui.renderer')"

    # Número de apps instalados (3ª parte) e quantos estão rodando AGORA: mais
    # apps rodando = mais pressão de RAM no meio da partida.
    APPS_RODANDO="$(sh_get 'pm list packages -3' >/dev/null 2>&1; \
        sh_get 'ps -A -o NAME' 2>/dev/null | grep -c '^[a-z]' )"
    APPS_RODANDO="$(_num "$APPS_RODANDO")"

    # Nível de "lixo" no sistema: apps do usuário que nunca foram abertos,
    # caches grandes. É o que a limpeza profunda ataca.
    CACHE_MB="$(sh_get 'du -sm /data/data 2>/dev/null' | awk '{print $1}')"
    CACHE_MB="$(_num "$CACHE_MB")"

    classify
}

# NOTA (0..100), CLASSE (topo/alto/medio/entrada) e PONTOS FRACOS.
# A nota não é vaidade: cada bloco abaixo vale pontos e, quando o aparelho fica
# abaixo do ideal NAQUELE bloco, o motivo é anotado em SO_WEAK — é o que o
# relatório usa para dizer "o que está segurando este aparelho".
classify() {
    s=0
    SO_WEAK=""

    # --- RAM (0..30) ---------------------------------------------------------
    if   [ "$RAM_MB" -ge 16000 ] 2>/dev/null; then s=$((s+30))
    elif [ "$RAM_MB" -ge 12000 ] 2>/dev/null; then s=$((s+27))
    elif [ "$RAM_MB" -ge 8000 ]  2>/dev/null; then s=$((s+23))
    elif [ "$RAM_MB" -ge 6000 ]  2>/dev/null; then s=$((s+18))
    elif [ "$RAM_MB" -ge 4000 ]  2>/dev/null; then s=$((s+12))
    elif [ "$RAM_MB" -ge 3000 ]  2>/dev/null; then s=$((s+7))
    else s=$((s+3)); fi
    [ "$RAM_MB" -gt 0 ] && [ "$RAM_MB" -lt 4000 ] 2>/dev/null \
        && SO_WEAK="$SO_WEAK|pouca RAM (${RAM_MB}MB): limite o 2º plano"

    # --- CPU: núcleos (0..12) + frequência do cluster forte (0..18) ----------
    if   [ "$CORES" -ge 8 ] 2>/dev/null; then s=$((s+12))
    elif [ "$CORES" -ge 6 ] 2>/dev/null; then s=$((s+10))
    elif [ "$CORES" -ge 4 ] 2>/dev/null; then s=$((s+6))
    else s=$((s+3)); fi
    [ "$CORES" -gt 0 ] && [ "$CORES" -lt 8 ] 2>/dev/null \
        && SO_WEAK="$SO_WEAK|$CORES núcleos: evite tarefas pesadas em paralelo"

    if   [ "$MAXFREQ" -ge 3000 ] 2>/dev/null; then s=$((s+18))
    elif [ "$MAXFREQ" -ge 2400 ] 2>/dev/null; then s=$((s+14))
    elif [ "$MAXFREQ" -ge 2000 ] 2>/dev/null; then s=$((s+10))
    elif [ "$MAXFREQ" -ge 1600 ] 2>/dev/null; then s=$((s+6))
    else s=$((s+3)); fi
    [ "$MAXFREQ" -gt 0 ] && [ "$MAXFREQ" -lt 2000 ] 2>/dev/null \
        && SO_WEAK="$SO_WEAK|cluster forte fraco (${MAXFREQ}MHz)"

    # --- Android (0..12) -----------------------------------------------------
    if   [ "$API" -ge 33 ] 2>/dev/null; then s=$((s+12))
    elif [ "$API" -ge 30 ] 2>/dev/null; then s=$((s+10))
    elif [ "$API" -ge 29 ] 2>/dev/null; then s=$((s+7))
    elif [ "$API" -ge 26 ] 2>/dev/null; then s=$((s+4))
    else s=$((s+2)); fi
    [ "$API" -gt 0 ] && [ "$API" -lt 29 ] 2>/dev/null \
        && SO_WEAK="$SO_WEAK|Android antigo (API $API): menos recursos de desempenho"

    # --- SoC conhecido (0..8) ------------------------------------------------
    case "$SOC" in desconhecido) s=$((s+3)) ;; *) s=$((s+8)) ;; esac

    # --- térmico: quantas zonas e se já está throttlando (0..10) ------------
    if   [ "$ZONES" -ge 20 ] 2>/dev/null; then s=$((s+6))
    elif [ "$ZONES" -ge 10 ] 2>/dev/null; then s=$((s+4))
    elif [ "$ZONES" -ge 4 ]  2>/dev/null; then s=$((s+2)); fi
    case "$THERM" in
        '') ;; 0|1) s=$((s+4)) ;;
        *) s=$((s+1)); SO_WEAK="$SO_WEAK|térmico já segurando o clock agora" ;;
    esac

    # --- SIMD/NEON (0..4): sem isso, emulação e jogos pesados sofrem ---------
    [ "$SIMD" = "1" ] && s=$((s+4)) || SO_WEAK="$SO_WEAK|CPU sem NEON: desempenho limitado"

    # --- armazenamento livre (0..6): cheio demais, o sistema engasga ---------
    if   [ "$STORAGE_MB" -ge 8000 ] 2>/dev/null; then s=$((s+6))
    elif [ "$STORAGE_MB" -ge 4000 ] 2>/dev/null; then s=$((s+4))
    elif [ "$STORAGE_MB" -ge 1500 ] 2>/dev/null; then s=$((s+2))
    else s=$((s+0)); fi
    [ "$STORAGE_MB" -gt 0 ] && [ "$STORAGE_MB" -lt 2000 ] 2>/dev/null \
        && SO_WEAK="$SO_WEAK|armazenamento quase cheio (${STORAGE_MB}MB): limpe"

    # --- penalidades de estado real ------------------------------------------
    [ "$LOW_RAM" = "1" ] && { s=$((s-8)); SO_WEAK="$SO_WEAK|Android Go (low_ram)"; }
    # pressão de memória alta agora: o aparelho está sofrendo neste instante
    case "$PSI_MEM" in
        ''|0|0.0) ;;
        *) case "$PSI_MEM" in
               1*|2*|3*|4*|5*|6*|7*|8*|9*) s=$((s-6)); SO_WEAK="$SO_WEAK|memória sob pressão agora (${PSI_MEM}%)" ;;
           esac ;;
    esac

    [ "$s" -lt 0 ] && s=0
    [ "$s" -gt 100 ] && s=100
    SCORE="$s"

    if   [ "$SCORE" -ge 80 ]; then TIER=topo
    elif [ "$SCORE" -ge 60 ]; then TIER=alto
    elif [ "$SCORE" -ge 40 ]; then TIER=medio
    else TIER=entrada; fi
    [ "$LOW_RAM" = "1" ] && TIER=entrada
    SO_WEAK="$(printf '%s' "$SO_WEAK" | sed 's/^|//')"
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
    printf '  %sclusters CPU%s  %s%s\n' "$C_A" "$C_R" "${N_CLUSTERS:-—}" \
        "$([ -n "$CL_FREQS" ] && printf ' (%s MHz)' "$CL_FREQS")"
    printf '  %sNEON/SIMD%s      %s\n' "$C_A" "$C_R" \
        "$([ "$SIMD" = 1 ] && echo 'sim (CPU moderna)' || echo 'não detectado')"
    printf '  %sI/O%s            %s\n' "$C_A" "$C_R" "${IO_SCHED:-não exposto}"
    printf '  %spressão de RAM%s %s%s\n' "$C_A" "$C_R" \
        "$([ -n "$PSI_MEM" ] && printf '%s%% agora' "$PSI_MEM" || echo 'não exposta')" \
        "$([ -n "$PSI_CPU" ] && printf ' · CPU %s%%' "$PSI_CPU")"
    printf '  %szram em uso%s    %s kB\n' "$C_A" "$C_R" "${SWAP_USO:-—}"
    printf '  %sswappiness%s     %s\n' "$C_A" "$C_R" "${VM_SWAPPY:-—}"
    printf '  %sentropia%s       %s\n' "$C_A" "$C_R" "${ENTROPY:-—}"
    printf '  %stela lógica%s    %sx%s%s\n' "$C_A" "$C_R" "${RES_W:-—}" "${RES_H:-—}" \
        "$([ "${DP_W:-0}" -gt 0 ] 2>/dev/null && printf ' · %s dp de largura' "$DP_W")"
    printf '  %srenderizador%s   %s\n' "$C_A" "$C_R" \
        "${RENDERER_ATUAL:-automático (o sistema escolhe)}"
    [ "$LOW_RAM" = "1" ] && printf '  %sAndroid Go / pouca memória detectado%s\n' "$C_Y" "$C_R"
    echo
    printf '  %sclasse%s        %s\n' "$C_A" "$C_R" "$(tier_label "$TIER")"
    printf '  %snota%s          %s/100\n' "$C_A" "$C_R" "$SCORE"
    if [ -n "$SO_WEAK" ]; then
        printf '  %so que segura a nota:%s\n' "$C_A" "$C_R"
        printf '%s' "$SO_WEAK" | tr '|' '\n' | while IFS= read -r w; do
            [ -n "$w" ] && printf '     %s·%s %s\n' "$C_D" "$C_R" "$w"
        done
    fi
    printf '  %sperfil sugerido%s %s\n' "$C_A" "$C_R" "$(auto_profile)"
    printf '  %sperfil aplicado%s %s\n' "$C_A" "$C_R" "$(cat "$SO_LAST" 2>/dev/null || echo 'nenhum')"
    if [ -s "$SO_BENCH" ]; then
        printf '  %súltimo teste%s    %s\n' "$C_A" "$C_R" \
            "$(sed -n 's/^resumo=//p' "$SO_BENCH" 2>/dev/null)"
    fi
    [ -n "$SO_SILENT_NEXT" ] || {
        echo
        printf '  %spróximo passo:%s smart-opt.sh plan  (ver as decisões)\n' "$C_A" "$C_R"
    }
}

# =============================================================================
#  3b) AUTO - o comando único: lê, decide, aplica e COMPROVA
# =============================================================================
# mostra o que o otimizador já aprendeu neste aparelho (transparência)
cmd_mem() {
    collect >/dev/null 2>&1
    printf '  %s◆%s  %sO QUE ELE APRENDEU NESTE APARELHO%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %saparelho:%s %s · %s MB RAM · %s/100\n' "$C_A" "$C_R" "${MODEL:-?}" "${RAM_MB:-0}" "${SCORE:-?}"
    r="$(so_mem_get renderer)"; h="$(so_mem_get hz)"; n="$(so_mem_get nota)"; k="$(so_mem_runs)"
    if [ -z "$r" ] && [ -z "$h" ]; then
        warn "ainda não testei nada aqui — rode o otimizador uma vez."
        return 0
    fi
    [ -n "$r" ] && printf '  %smelhor renderizador:%s %s\n' "$C_A" "$C_R" "$r"
    [ -n "$h" ] && printf '  %smelhor taxa de tela:%s %sHz\n' "$C_A" "$C_R" "$h"
    [ -n "$n" ] && printf '  %smelhor nota medida:%s %s/100\n' "$C_A" "$C_R" "$n"
    [ -n "$k" ] && printf '  %svezes que rodou aqui:%s %s\n' "$C_A" "$C_R" "$k"
    printf '  %so arquivo fica em %s%s\n' "$C_D" "$SO_MEM" "$C_R"
}

cmd_auto() {
    local prof="${1:-auto}"
    SO_SILENT_NEXT=1
    # snapshot de segurança antes de qualquer coisa: se algo der errado, o
    # usuário tem um ponto de retorno (não precisa lembrar de salvar antes).
    sh "$DIR/snapshot.sh" save "antes-do-otimizador" >/dev/null 2>&1
    cmd_analyze
    echo
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    # aplica e, na mesma tacada, mede antes x depois (é o que prova o resultado)
    cmd_bench "$prof" || return 1
    # e ainda testa as combinações: é aqui que ele descobre o melhor PARA ESTE
    # aparelho e guarda na memória para as próximas vezes.
    runs="$(so_mem_runs)"; case "$runs" in ''|*[!0-9]*) runs=0 ;; esac
    if [ "$runs" -ge 1 ] 2>/dev/null; then
        printf '\n  %smemória:%s este aparelho já foi testado %s vez(es); começando pela combinação que venceu\n' \
            "$C_A" "$C_R" "$runs"
    fi
    echo
    cmd_compare "$prof" || return 1
    so_mem_set runs "$((runs + 1))"
    # resumo final: UM resultado, sem o usuário precisar ler nada do meio
    echo
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %s◆%s  %sRESULTADO FINAL%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    v_render="$(so_mem_get renderer)"; v_hz="$(so_mem_get hz)"; v_nota="$(so_mem_get nota)"
    printf '  %saparelho:%s %s · %s MB RAM · %s/100\n' "$C_A" "$C_R" \
        "$MODEL" "$RAM_MB" "$SCORE"
    printf '  %sconfig aplicada:%s %s%s\n' "$C_A" "$C_R" \
        "${v_render:-$D_RENDERER}" \
        "$([ -n "$v_hz" ] && printf ' + %sHz' "$v_hz" || printf ' + taxa padrão')"
    [ -n "$v_nota" ] && printf '  %snota medida:%s %s/100\n' "$C_A" "$C_R" "$v_nota"
    printf '  %so que ficou no seu aparelho é o melhor que deu para medir aqui.\n' "$C_D" "$C_R"
    printf '  %srodando de novo, ele parte desta combinação e tenta melhorar.\n' "$C_D" "$C_R"
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

    # memória: se já testamos aqui e um caminho venceu, começamos por ele. Isto
    # vem DEPOIS da regra técnica, então a memória só substitui quando há algo
    # medido neste aparelho (nunca um palpite).
    D_MEM_RENDER="$(so_mem_get renderer)"
    case "$D_MEM_RENDER" in
        skiavk|skiagl) D_RENDERER="$D_MEM_RENDER" ;;
    esac

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
    # memória: taxa de tela que venceu neste aparelho (menos no perfil bateria,
    # que por definição trava em 60Hz).
    if [ "$prof" != "bateria" ]; then
        D_MEM_HZ="$(so_mem_get hz)"
        case "$D_MEM_HZ" in
            60|90|120|144) D_HZ="$D_MEM_HZ" ;;
        esac
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

# =============================================================================
#  MEDIÇÃO DE DESEMPENHO (para provar que a otimização serviu)
# =============================================================================
# so_measure -> imprime "pontos" (quanto MAIOR, melhor) numa linha só.
#
# O que é medido, e por quê:
#   · RAM livre            → mais espaço para o jogo (peso 30)
#   · pressão de memória   → o quanto o kernel está sofrendo (peso 30, invertido)
#   · load average         → fila de trabalho na CPU (peso 20, invertido)
#   · frequência da CPU    → o clock que está valendo (peso 20)
#   · temperatura          → esquentando, throttla e cai o FPS (peso 10, invertido)
#
# Não é benchmark sintético: são os números que o aparelho já expõe. Se o
# aparelho não informa um deles, ele sai do cálculo (nunca conta como zero).
so_measure() {
    ram="$(otm_ram_livre_mb)"; ram="$(_num "$ram")"
    psi="$(sh_get 'cat /proc/pressure/memory' | sed -n 's/.*avg10=\([0-9.]*\).*/\1/p' | head -1)"
    load="$(sh_get 'cat /proc/loadavg' | awk '{print $1}')"
    cur="$(sh_get 'cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq')"; cur="$(_num "$cur")"
    [ -n "$cur" ] && cur=$((cur / 1000))
    tmp="$(otm_temp)"; tmp="$(_num "$tmp")"
    hz="$(sh_get 'settings get system peak_refresh_rate')"
    case "$hz" in ''|null) hz="$(sh_get 'dumpsys display' | grep -m1 -oE 'fps=[0-9.]+' | cut -d= -f2)" ;; esac

    pts=0; n=0
    # RAM livre: 30 pontos quando há 2 GB+ livres; cai linearmente até 0 em 200 MB
    if [ -n "$ram" ] && [ "$ram" -gt 0 ] 2>/dev/null; then
        [ "$ram" -ge 2048 ] && p=30 || p=$((ram * 30 / 2048))
        pts=$((pts + p)); n=$((n + 1))
    fi
    # pressão de memória: 0% = 30 pontos; 30%+ = 0
    case "$psi" in
        ''|null) ;;
        *) p="$(awk "BEGIN{v=30-$psi; if(v<0)v=0; printf \"%d\", v}")"
           pts=$((pts + p)); n=$((n + 1)) ;;
    esac
    # load average: 0 = 20 pontos; 4+ = 0
    case "$load" in
        ''|null) ;;
        *) p="$(awk "BEGIN{v=20-($load*5); if(v<0)v=0; printf \"%d\", v}")"
           pts=$((pts + p)); n=$((n + 1)) ;;
    esac
    # frequência: metade do pico vale 10, o pico vale 20 (usa o pico já lido)
    if [ -n "$cur" ] && [ "${MAXFREQ:-0}" -gt 0 ] 2>/dev/null; then
        p=$((cur * 20 / MAXFREQ)); [ "$p" -gt 20 ] && p=20
        pts=$((pts + p)); n=$((n + 1))
    fi
    # temperatura: 35 °C ou menos = 10 pontos; 55 °C+ = 0
    if [ -n "$tmp" ] && [ "$tmp" -gt 0 ] 2>/dev/null; then
        p=$(( (55 - tmp) * 10 / 20 )); [ "$p" -lt 0 ] && p=0; [ "$p" -gt 10 ] && p=10
        pts=$((pts + p)); n=$((n + 1))
    fi

    # normaliza para 0..100 conforme quantas métricas existiram
    tot=0
    [ -n "$ram" ] && tot=$((tot + 30))
    case "$psi" in ''|null) ;; *) tot=$((tot + 30)) ;; esac
    case "$load" in ''|null) ;; *) tot=$((tot + 20)) ;; esac
    [ -n "$cur" ] && [ "${MAXFREQ:-0}" -gt 0 ] 2>/dev/null && tot=$((tot + 20))
    [ -n "$tmp" ] && [ "$tmp" -gt 0 ] 2>/dev/null && tot=$((tot + 10))

    if [ "$tot" -gt 0 ] 2>/dev/null; then
        nota=$((pts * 100 / tot))
    else
        nota=""
    fi
    printf 'nota=%s ram=%s psi=%s load=%s cpu=%s temp=%s hz=%s n=%s\n' \
        "${nota:-—}" "${ram:-—}" "${psi:-—}" "${load:-—}" "${cur:-—}" "${tmp:-—}" "${hz:-—}" "$n"
}

# mede 3× e devolve a MÉDIA (uma leitura só oscila demais para comparar)
so_measure_avg() {
    i=1; soma=0; cnt=0; detalhe=""
    while [ "$i" -le 3 ]; do
        linha="$(so_measure)"
        detalhe="$linha"
        v="$(printf '%s' "$linha" | sed -n 's/^nota=\([0-9]*\).*/\1/p')"
        if [ -n "$v" ]; then soma=$((soma + v)); cnt=$((cnt + 1)); fi
        i=$((i + 1))
        [ "$i" -le 3 ] && sleep 1
    done
    [ "$cnt" -gt 0 ] && media=$((soma / cnt)) || media=""
    printf '%s\n' "media=${media:-—} $detalhe"
}

# --- benchmark antes x depois --------------------------------------------------
# cmd_bench [perfil]: mede, aplica, mede de novo e COMPARA. Se piorar, avisa e
# sugere voltar. É o que transforma "confie em mim" em "olha o número".
cmd_bench() {
    collect
    decide "$1" || return 1
    printf '  %s◆%s  %sTESTE DE DESEMPENHO%s  %s(perfil %s)%s\n' \
        "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$D_PROF" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"

    so_step "1/3  Medindo ANTES (3 amostras)"
    antes="$(so_measure_avg)"
    printf '     %s\n' "$antes"

    so_step "2/3  Aplicando o perfil $D_PROF"
    so_apply_steps
    printf '     aplicado\n'

    so_step "3/3  Medindo DEPOIS (3 amostras)"
    sleep 2
    depois="$(so_measure_avg)"
    printf '     %s\n' "$depois"

    a="$(printf '%s' "$antes" | sed -n 's/^media=\([0-9]*\).*/\1/p')"
    b="$(printf '%s' "$depois" | sed -n 's/^media=\([0-9]*\).*/\1/p')"
    printf '%s\n' "$antes" > "$SO_BENCH" 2>/dev/null

    echo
    if [ -n "$a" ] && [ -n "$b" ]; then
        d=$((b - a))
        printf '  %santes%s  %s/100\n' "$C_A" "$C_R" "$a"
        printf '  %sdepois%s %s/100\n' "$C_A" "$C_R" "$b"
        if   [ "$d" -gt 3 ];  then
            printf '  %sresultado: MELHOROU (%+d)%s\n' "$C_G" "$d" "$C_R"
            resumo="melhorou ${d} pontos ($a→$b)"
        elif [ "$d" -lt -3 ]; then
            printf '  %sresultado: PIOROU (%+d) — recomendado voltar%s\n' "$C_RD" "$d" "$C_R"
            printf '  %svoltar:%s smart-opt.sh restore\n' "$C_A" "$C_R"
            resumo="piorou ${d} pontos ($a→$b)"
        else
            printf '  %sresultado: estável (%+d)%s\n' "$C_Y" "$d" "$C_R"
            resumo="estável ($a→$b)"
        fi
        printf 'resumo=%s\n' "$resumo" >> "$SO_BENCH" 2>/dev/null
    else
        warn "não deu para medir este aparelho (faltam leituras) — os ajustes foram aplicados mesmo assim"
        resumo="sem medição"
        printf 'resumo=%s\n' "$resumo" >> "$SO_BENCH" 2>/dev/null
    fi
    printf '%s\n' "$D_PROF" > "$SO_LAST" 2>/dev/null
}

# --- comparação de combinações -------------------------------------------------
# cmd_compare [perfil]: testa os caminhos plausíveis (renderizador e taxa de tela)
# e FICA com o que der a melhor nota de desempenho. Cada candidato é aplicado,
# medido, e o vencedor é o que permanece no fim.
cmd_compare() {
    collect
    decide "$1" || return 1
    printf '  %s◆%s  %sCOMPARANDO COMBINAÇÕES%s\n' "$C_A" "$C_R" "$C_A" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %smede cada combinação e fica com a de melhor nota%s\n' "$C_D" "$C_R"

    melhor_nota=-1; melhor_render=""; melhor_hz=""

    # candidatos de renderizador: o decidido + a alternativa da mesma família
    case "$D_RENDERER" in
        skiavk) CAND_RENDER="skiavk skiagl" ;;
        skiagl) CAND_RENDER="skiagl skiavk" ;;
        *)      CAND_RENDER="$D_RENDERER" ;;
    esac
    # candidatos de Hz: o decidido + 90Hz (mais estável, esquenta menos). Sem
    # leitura de taxa, o candidato é "-" = não mexer na taxa (nunca chutar).
    CAND_HZ="${D_HZ:--}"
    case "$D_HZ" in
        120|144) CAND_HZ="$D_HZ 90" ;;
    esac

    for r in $CAND_RENDER; do
        for h in $CAND_HZ; do
            [ "$h" = "-" ] && rotulo="taxa padrão" || rotulo="${h}Hz"
            printf '\n  %s▸%s testando %s + %s\n' "$C_G" "$C_R" "$r" "$rotulo"
            sh "$DIR/adb-tweaks.sh" renderer "$r" >/dev/null 2>&1
            [ "$h" = "-" ] || sh "$DIR/turbo.sh" refresh_fixed "$h" >/dev/null 2>&1
            sleep 2
            m="$(so_measure_avg)"
            n="$(printf '%s' "$m" | sed -n 's/^media=\([0-9]*\).*/\1/p')"
            printf '     nota %s/100\n' "${n:-—}"
            if [ -n "$n" ] && [ "$n" -gt "$melhor_nota" ] 2>/dev/null; then
                melhor_nota="$n"; melhor_render="$r"; melhor_hz="$h"
            fi
        done
    done

    echo
    if [ -n "$melhor_render" ]; then
        # deixa o vencedor aplicado
        sh "$DIR/adb-tweaks.sh" renderer "$melhor_render" >/dev/null 2>&1
        [ "$melhor_hz" = "-" ] || sh "$DIR/turbo.sh" refresh_fixed "$melhor_hz" >/dev/null 2>&1
        [ "$melhor_hz" = "-" ] && melhor_rot="taxa padrão" || melhor_rot="${melhor_hz}Hz"
        printf '  %svencedor:%s %s + %s (nota %s/100)\n' \
            "$C_A" "$C_R" "$melhor_render" "$melhor_rot" "$melhor_nota"
        printf '%s\n' "$melhor_render" > "$SO_ST/winner_renderer" 2>/dev/null
        printf '%s\n' "$melhor_hz" > "$SO_ST/winner_hz" 2>/dev/null
        # grava na memória do aparelho: da próxima vez decide() já começa por aqui
        so_mem_set renderer "$melhor_render"
        [ "$melhor_hz" = "-" ] || so_mem_set hz "$melhor_hz"
        so_mem_set nota "$melhor_nota"
        printf '  %seste é o ajuste que ficou no aparelho%s\n' "$C_D" "$C_R"
    else
        warn "não deu para comparar neste aparelho (sem leitura suficiente)"
    fi
    printf '%s\n' "$D_PROF" > "$SO_LAST" 2>/dev/null
}

# --- passos de aplicação (compartilhado entre apply e bench) ------------------
# Cada passo delega a um módulo já testado do pack; nada é reimplementado aqui.
so_apply_steps() {
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
    so_step "5/7  Limpeza ($D_CLEAN)"
    sh "$DIR/clean.sh" now "$D_CLEAN" >/dev/null 2>&1
    if [ "$D_DOZE" = on ]; then
        sh "$DIR/adb-tweaks.sh" doze on >/dev/null 2>&1
    fi

    # 6) memória do kernel: só quando o kernel aceita (o otm_sysctl lê de volta)
    so_step "6/7  Memória do kernel (zram/swappiness)"
    case "$VM_SWAPPY" in
        ''|null) say "kernel não expôs vm.swappiness — pulado" ;;
        *)
            if [ "${RAM_MB:-0}" -ge 8000 ] 2>/dev/null; then
                otm_sysctl vm.swappiness 100   # RAM de sobra: comprime em vez de matar
            else
                otm_sysctl vm.swappiness 60    # pouca RAM: evita thrashing
            fi ;;
    esac

    # 7) jogo: anti-relog + foco (só no perfil jogo, com jogo escolhido)
    so_step "7/7  Jogo e proteção"
    if [ -n "$D_GAME" ]; then
        sh "$DIR/adb-tweaks.sh" game_keepalive "$D_GAME" >/dev/null 2>&1
        sh "$DIR/adb-tweaks.sh" game_focus >/dev/null 2>&1
        say "anti-relog e foco de jogo em $D_GAME"
    else
        say "nenhum jogo escolhido — pulei o anti-relog (use o Modo Competitivo na Home)"
    fi
}

cmd_apply() {
    collect
    decide "$1" || return 1

    printf '  %s◆%s  %sOTIMIZADOR INTELIGENTE%s  %s(perfil %s)%s\n' \
        "$C_A" "$C_R" "$C_A" "$C_R" "$C_D" "$D_PROF" "$C_R"
    printf '  %s──────────────────────────────────────────%s\n' "$C_D" "$C_R"
    printf '  %s · %s MB RAM · nota %s/100\n' "$(tier_label "$TIER")" "$RAM_MB" "$SCORE"

    so_apply_steps

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
        "$(sh_get 'getprop debug.hwui.renderer' | grep . || echo 'automático (o sistema escolhe)')"
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
    auto)    shift; cmd_auto "$1" ;;
    analyze) cmd_analyze ;;
    plan)    shift; cmd_plan "$1" ;;
    apply)   shift; cmd_apply "$1" ;;
    bench)   shift; cmd_bench "$1" ;;
    compare) shift; cmd_compare "$1" ;;
    status)  cmd_status ;;
    mem)     cmd_mem ;;
    restore) cmd_restore ;;
    *)
        sed -n '3,32p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
rc=$?
otm_v_report smart-opt
exit $rc
