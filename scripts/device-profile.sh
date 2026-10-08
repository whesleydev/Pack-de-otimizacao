#!/system/bin/sh
# =============================================================================
#  device-profile.sh - Perfil do aparelho: o que o pack PODE e NÃO PODE fazer.
#
#  Caminhos de sysfs variam por SoC/kernel. Este script detecta a plataforma e
#  diz quais módulos do deep-tune tendem a funcionar, e quais evitar.
#
#  Uso:
#     sh device-profile.sh            # relatório do aparelho
#     sh device-profile.sh save       # salva o perfil em ~/.packotm/perfil.txt
#
#  Saída é informativa (baseada em família de SoC), NÃO uma garantia. Sempre
#  teste no seu modelo. Veja docs/COMPATIBILIDADE.md.
# =============================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/common.sh"

soc_family() {
    p="$(sh_get 'getprop ro.board.platform')"
    h="$(sh_get 'getprop ro.hardware')"
    c="$(sh_get 'cat /proc/cpuinfo' | grep -m1 -i 'Hardware' | cut -d: -f2- | tr -d ' ')"
    all="$p $h $c"
    case "$all" in
        *sm[0-9]*|*msm*|*sdm*|*qcom*|*kona*|*waipio*|*kalama*|*pineapple*) echo "snapdragon" ;;
        *mt[0-9]*|*dimensity*|*mediatek*|*mtk*) echo "dimensity" ;;
        *exynos*|*universal*|*s5e*) echo "exynos" ;;
        *tensor*|*gs[0-9]*|*zuma*|*husky*) echo "tensor" ;;
        *kirin*|*hi[0-9]*) echo "kirin" ;;
        *) echo "desconhecido" ;;
    esac
}

gpu_vendor() {
    g="$(sh_get 'getprop ro.hardware.egl')"
    case "$g" in
        *adreno*) echo "Adreno" ;;
        *mali*)   echo "Mali" ;;
        *powervr*|*pvrs*) echo "PowerVR" ;;
        *) [ -d /sys/class/kgsl/kgsl-3d0 ] && echo "Adreno (kgsl)" || echo "?" ;;
    esac
}

android_ver() {
    v="$(sh_get 'getprop ro.build.version.release')"
    api="$(sh_get 'getprop ro.build.version.sdk')"
    echo "${v:-?} (API ${api:-?})"
}

ram_gb() {
    k="$(sh_get 'cat /proc/meminfo' | awk '/MemTotal/{print $2}')"
    [ -n "$k" ] && awk "BEGIN{printf \"%.1f\", $k/1048576}"
}

# módulos que costumam funcionar por família
profile_modules() {
    case "$1" in
        snapdragon) echo "angle debloat net io mem latency freq thermal" ;;
        dimensity)  echo "angle debloat net io mem latency" ;;
        exynos)     echo "angle debloat net mem latency" ;;
        tensor)     echo "angle debloat net mem" ;;
        kirin)      echo "angle debloat net" ;;
        *)          echo "angle debloat net" ;;
    esac
}

report() {
    fam="$(soc_family)"
    say "Perfil do aparelho"
    printf '   modelo:    %s\n' "$(sh_get 'getprop ro.product.model')"
    printf '   fabricante:%s\n' "$(sh_get 'getprop ro.product.manufacturer')"
    printf '   Android:   %s\n' "$(android_ver)"
    printf '   SoC:       %s (%s)\n' "$fam" "$(sh_get 'getprop ro.board.platform')"
    printf '   GPU:       %s\n' "$(gpu_vendor)"
    printf '   kernel:    %s\n' "$(sh_get 'uname -r')"
    printf '   RAM:       %s GB\n' "$(ram_gb)"
    printf '   root:      %s\n' "$(sh_ok && echo sim || echo não)"
    printf '   modo:      %s\n' "$RUN_MODE"
    echo
    printf '   %sMódulos recomendados%s (tendem a funcionar):\n' "$C_A" "$C_R"
    printf '     %s\n' "$(profile_modules "$fam")"
    case "$fam" in
        dimensity)
            warn "MTK: caminhos de GPU (Mali) e térmico mudam muito. Teste 'freq'/'thermal' antes."
            ;;
        exynos)
            warn "Exynos: 'freq' e 'thermal' raramente funcionam sem kernel custom. Prefira angle/debloat/net."
            ;;
        tensor)
            warn "Tensor: térmico é agressivo de fábrica; evitar 'thermal' (esquenta e throttla)."
            ;;
        desconhecido)
            warn "SoC não reconhecido: rode 'deep-tune.sh detect' e confira os caminhos manualmente."
            ;;
    esac
    echo
    printf '   %sAviso:%s a detecção é por família de SoC, não por modelo. Sempre teste.\n' "$C_Y" "$C_R"
}

case "$1" in
    save)
        f="$ST/perfil.txt"
        mkdir -p "$ST" 2>/dev/null
        { report; echo; sh "$DIR/deep-tune.sh" detect; } > "$f" 2>&1
        say "perfil salvo em $f"
        ;;
    *) report ;;
esac
