#!/system/bin/sh
# =============================================================================
#  run.sh - Testes automatizados do pack (rodam em PC/container, sem celular).
#
#  Exercita os scripts DE VERDADE com stubs de `settings`, `cmd`, `am`, `getprop`
#  e `setprop` no PATH — sem mocks de código. Valida apply->restore, a reversão
#  por módulo (tag) e o marcador que impede o loop de duplicar o backup.
#
#  Uso: sh tests/run.sh
#  Código: 0 = tudo passou | 1 = houve falha
# =============================================================================

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
PASS=0; FAIL=0

# --- stubs -------------------------------------------------------------------
setup_stubs() {
    mkdir -p "$TMP/bin" "$TMP/store"
    cat > "$TMP/bin/settings" <<'EOF'
#!/bin/sh
case "$1" in
  get)    cat "$TMP_STORE/$2.$3" 2>/dev/null ;;
  put)    t="$2"; k="$3"; shift 3; printf '%s' "$*" > "$TMP_STORE/$t.$k" ;;
  delete) rm -f "$TMP_STORE/$2.$3" ;;
esac
exit 0
EOF
    # cmd: registra chamadas (appops etc.)
    cat > "$TMP/bin/cmd" <<'EOF'
#!/bin/sh
[ -n "$TMP_CMD_LOG" ] && echo "$*" >> "$TMP_CMD_LOG"
exit 0
EOF
    # am: registra chamadas (force-stop etc.)
    cat > "$TMP/bin/am" <<'EOF'
#!/bin/sh
[ -n "$TMP_AM_LOG" ] && echo "$*" >> "$TMP_AM_LOG"
exit 0
EOF
    # monkey: usado para abrir um app sem saber a Activity (registra igual ao am)
    cat > "$TMP/bin/monkey" <<'EOF'
#!/bin/sh
[ -n "$TMP_AM_LOG" ] && echo "$*" >> "$TMP_AM_LOG"
exit 0
EOF
    # pm: registra chamadas e simula `pm list packages`
    cat > "$TMP/bin/pm" <<'EOF'
#!/bin/sh
[ -n "$TMP_PM_LOG" ] && echo "$*" >> "$TMP_PM_LOG"
if [ "$1" = "list" ]; then
    shift
    [ "$1" = "packages" ] && shift
    has=0
    for a in "$@"; do
        case "$a" in -*) continue ;; *) has=1; echo "package:$a" ;; esac
    done
    if [ "$has" = 0 ]; then
        echo package:com.example
        echo package:com.instagram.android
        echo package:com.whatsapp
        echo package:com.android.systemui
    fi
fi
exit 0
EOF
    # getprop/setprop com armazenamento (verificação real lê de volta)
    cat > "$TMP/bin/getprop" <<'EOF'
#!/bin/sh
case "$1" in
  ro.product.model) echo "TestPhone"; exit 0 ;;
  ro.build.version.sdk) if [ -f "$TMP_STORE/prop.ro.build.version.sdk" ]; then
                            cat "$TMP_STORE/prop.ro.build.version.sdk"; else echo "34"; fi
                        exit 0 ;;
  "") exit 0 ;;
esac
cat "$TMP_STORE/prop.$1" 2>/dev/null
exit 0
EOF
    cat > "$TMP/bin/setprop" <<'EOF'
#!/bin/sh
printf '%s' "$2" > "$TMP_STORE/prop.$1"
exit 0
EOF
    # sysctl com armazenamento (sysctl_write lê de volta). SYSCTL_ROOT mapeia as
    # chaves 'vm.*' para arquivos, permitindo testar a verificação de verdade.
    cat > "$TMP/bin/sysctl" <<'EOF'
#!/bin/sh
root="${SYSCTL_ROOT:-$TMP_STORE}"
key="${2#vm.}"
case "$1" in
  -n) if [ -f "$root/$key" ]; then cat "$root/$key"
      elif [ -f "$TMP_STORE/sys.$2" ]; then cat "$TMP_STORE/sys.$2"
      elif [ "$2" = "net.ipv4.tcp_available_congestion_control" ]; then echo "cubic reno bbr"
      else echo cubic; fi ;;
  -w) k="${2%%=*}"; v="${2#*=}"
      if [ -f "$root/${k#vm.}" ]; then printf '%s' "$v" > "$root/${k#vm.}"
      else printf '%s' "$v" > "$TMP_STORE/sys.$k"; fi ;;
esac
exit 0
EOF
    # device_config: usado pelo limite de processos (Android 10+). Guarda por
    # namespace+chave e imprime "null" quando não existe, como no Android.
    cat > "$TMP/bin/device_config" <<'EOF'
#!/bin/sh
case "$1" in
  put)    printf '%s' "$4" > "$TMP_STORE/dc.$2.$3" ;;
  get)    if [ -f "$TMP_STORE/dc.$2.$3" ]; then cat "$TMP_STORE/dc.$2.$3"; else echo null; fi ;;
  delete) rm -f "$TMP_STORE/dc.$2.$3" ;;
esac
exit 0
EOF
    # dumpsys: só o suficiente para o fallback do limite de processos e para
    # descobrir o app em PRIMEIRO PLANO (a limpeza nunca pode fechar o que está
    # na tela). O pacote em foco vem de $TMP_STORE/fg, senão usa um padrão.
    cat > "$TMP/bin/dumpsys" <<'EOF'
#!/bin/sh
if [ "$1" = "activity" ] && [ "$2" = "settings" ]; then
    if [ -f "$TMP_STORE/dc.activity_manager.max_cached_processes" ]; then
        echo "  CUR_MAX_CACHED_PROCESSES=$(cat "$TMP_STORE/dc.activity_manager.max_cached_processes")"
    else
        echo "  CUR_MAX_CACHED_PROCESSES=32"
    fi
fi
if [ "$1" = "activity" ] && [ "$2" = "activities" ]; then
    fg="$(cat "$TMP_STORE/fg" 2>/dev/null)"
    [ -n "$fg" ] && echo "    mResumedActivity: ActivityRecord{1a2b3c u0 $fg/.MainActivity t42}"
fi
# SurfaceFlinger: as camadas e o carimbo de frames vêm de arquivos do store, para
# o teste do FPS real controlar exatamente o que o compositor "respondeu".
if [ "$1" = "SurfaceFlinger" ] && [ "$2" = "--list" ]; then
    cat "$TMP_STORE/sf_list" 2>/dev/null
fi
if [ "$1" = "SurfaceFlinger" ] && [ "$2" = "--latency" ]; then
    cat "$TMP_STORE/sf_latency" 2>/dev/null
fi
exit 0
EOF
    # wm: simula `wm size` / `wm density` com override persistido, como no
    # Android (Physical size + Override size quando há override aplicado).
    cat > "$TMP/bin/wm" <<'EOF'
#!/bin/sh
[ -n "$TMP_CMD_LOG" ] && echo "wm $*" >> "$TMP_CMD_LOG"
case "$1" in
  size)
     case "$2" in
       reset) rm -f "$TMP_STORE/wm.size" ;;
       '')    echo "Physical size: ${WM_PHYS:-1080x2400}"
              [ -f "$TMP_STORE/wm.size" ] && echo "Override size: $(cat "$TMP_STORE/wm.size")" ;;
       *)     printf '%s' "$2" > "$TMP_STORE/wm.size" ;;
     esac ;;
  density)
     echo "Physical density: ${WM_DENSITY:-400}"
     [ -f "$TMP_STORE/wm.density" ] && echo "Override density: $(cat "$TMP_STORE/wm.density")" ;;
esac
exit 0
EOF
    # su falso: finge ser root e executa o comando como shell local
    cat > "$TMP/bin/su" <<'EOF'
#!/bin/sh
[ "$1" = "-c" ] && shift
case "$*" in
  "id -u") echo 0; exit 0 ;;
esac
exec sh -c "$*"
EOF
    chmod +x "$TMP/bin/"*
    export TMP_STORE="$TMP/store"
    export PATH="$TMP/bin:$PATH"
    export HOME="$TMP/home"
    mkdir -p "$HOME"
}

# --- asserções ---------------------------------------------------------------
ok()  { PASS=$((PASS+1)); printf '  [ ok ] %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  [FAIL] %s\n' "$1"; }

assert_contains()     { grep -q -- "$2" "$1" 2>/dev/null && ok "$3" || bad "$3 (não achei '$2' em $1)"; }
assert_not_contains() { grep -q -- "$2" "$1" 2>/dev/null && bad "$3 (achei '$2' em $1)" || ok "$3"; }
assert_eq()           { [ "$1" = "$2" ] && ok "$3" || bad "$3 (esperado '$1', obtido '$2')"; }

deep_off() { echo "$HOME/.packotm/deep/off.sh"; }

# --- testes ------------------------------------------------------------------
t_syntax() {
    printf '\n  # sintaxe (sh -n) de todos os scripts\n'
    n=0; e=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        n=$((n+1))
        sh -n "$f" 2>/dev/null || { e=$((e+1)); bad "sintaxe: $f"; }
    done <<EOF
$(find "$ROOT/scripts" "$ROOT/00 Otimizações" "$ROOT/tests" -name '*.sh' -not -path '*/.git/*' 2>/dev/null | sort)
EOF
    [ "$e" = "0" ] && ok "sintaxe OK em $n scripts"
}

t_angle_tag() {
    printf '\n  # deep-tune: angle add cria tag angle; reset remove\n'
    rm -rf "$HOME/.packotm/deep"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle add com.dts.freefireth >/dev/null 2>&1
    assert_contains "$(deep_off)" '^angle' "angle add registra reversão com tag 'angle'"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle reset >/dev/null 2>&1
    assert_not_contains "$(deep_off)" '^angle' "angle reset limpa as linhas do módulo angle"
}

t_renderer_app() {
    printf '\n  # renderizador do sistema + driver gráfico por app\n'
    rm -rf "$HOME/.packotm"
    rm -f "$TMP_STORE/prop.debug.hwui.renderer" "$TMP_STORE/prop.debug.renderengine.backend"
    # renderizador base grava o prop; o backend do COMPOSITOR fica no padrão
    # (nos modos não-multithread não mexemos no SurfaceFlinger — ver AOSP)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" renderer skiagl >/dev/null 2>&1
    assert_eq "skiagl" "$(cat "$TMP_STORE/prop.debug.hwui.renderer" 2>/dev/null)" "renderer skiagl grava o prop"
    [ -z "$(cat "$TMP_STORE/prop.debug.renderengine.backend" 2>/dev/null)" ] \
        && ok "renderer skiagl não prende o compositor (backend no padrão)" \
        || bad "renderer skiagl não devia setar o backend do compositor"
    # multithread usa o backend do compositor (é o único caso que desempata)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" renderer skiavk-threaded >/dev/null 2>&1
    assert_eq "skiavk" "$(cat "$TMP_STORE/prop.debug.hwui.renderer" 2>/dev/null)" "renderer multithread usa skiavk"
    assert_eq "skiavkthreaded" "$(cat "$TMP_STORE/prop.debug.renderengine.backend" 2>/dev/null)" "renderer multithread grava o backend"
    # "opengl" é recusado em Android 10+ (o pipeline não existe mais) — nada fictício
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" renderer opengl > "$TMP/gl_bad" 2>&1
    assert_contains "$TMP/gl_bad" "não existe" "renderer opengl é recusado no Android novo"
    # "auto" apaga o prop e devolve a decisão ao sistema
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" renderer auto >/dev/null 2>&1
    [ -z "$(cat "$TMP_STORE/prop.debug.hwui.renderer" 2>/dev/null)" ] \
        && ok "renderer auto limpa o prop (sistema decide)" || bad "renderer auto não limpou o prop"
    grep -q 'debug.renderengine.backend' "$HOME/.packotm/undo/adb-tweaks.sh" && ok "renderer é reversível" || bad "renderer sem reversão"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" restore_all >/dev/null 2>&1
    [ -z "$(cat "$TMP_STORE/prop.debug.hwui.renderer" 2>/dev/null)" ] && ok "renderer volta ao original no restore" || bad "restore não limpou o renderer"
    # driver gráfico por app (ANGLE/nativo/padrão) — sem root
    rm -rf "$HOME/.packotm/deep"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle set com.dts.freefireth angle >/dev/null 2>&1
    assert_eq "com.dts.freefireth" "$(cat "$TMP_STORE/global.angle_gl_driver_selection_pkgs" 2>/dev/null)" "angle set adiciona o app"
    assert_eq "angle" "$(cat "$TMP_STORE/global.angle_gl_driver_selection_values" 2>/dev/null)" "angle set grava o driver"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle set com.dts.freefireth native >/dev/null 2>&1
    assert_eq "native" "$(cat "$TMP_STORE/global.angle_gl_driver_selection_values" 2>/dev/null)" "angle set troca o driver do app"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle set com.dts.freefireth default >/dev/null 2>&1
    [ -z "$(cat "$TMP_STORE/global.angle_gl_driver_selection_pkgs" 2>/dev/null)" ] && ok "angle set default remove o app" || bad "default não removeu o app"
    # painel: renderizador por app e escolha de DNS registrados
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             echo isset($a["app.render"]) && $a["app.render"]["choice"]==="renderapp" ? "app " : "";
             echo isset($a["gpu.skiavk_threaded"]["state_backend_value"]) ? "mt " : "";
             echo isset($a["dns.cloudflare"]["choice"]) && $a["dns.cloudflare"]["state_value"]==="one.one.one.one" ? "dns" : "";' \
        > "$TMP/ra_reg" 2>&1
    assert_contains "$TMP/ra_reg" "app mt dns" "registro: app.render, multithread e DNS por escolha"
    # estado real do aparelho expõe o backend do renderizador e o host DNS
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/ra_state"
    grep -q '"renderengine_backend"' "$TMP/ra_state" && ok "state: expõe o backend do renderizador" || bad "state: sem backend"
    grep -q '"dns_host"' "$TMP/ra_state" && ok "state: expõe o host DNS em uso" || bad "state: sem dns_host"
    # DNS recomendado (gaming/net) não usa o host quebrado que deixa sem internet
    ! grep -q '1dot1dot1dot1' "$ROOT/scripts/dns.sh" && ok "DNS: host quebrado removido" || bad "DNS: host quebrado ainda presente"
    grep -q 'private_dns_specifier one.one.one.one' "$ROOT/scripts/adb-tweaks.sh" \
        && ok "rede (pack) usa o host DoT válido" || bad "rede ainda usa host quebrado"
    rm -rf "$HOME/.packotm"
}


t_per_module() {
    printf '\n  # deep-tune: reverter um módulo não afeta os outros\n'
    rm -rf "$HOME/.packotm/deep"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle add com.dts.freefireth >/dev/null 2>&1
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" debloat off >/dev/null 2>&1
    assert_contains "$(deep_off)" '^angle' "debloat off preserva as linhas do angle"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" restore >/dev/null 2>&1
}

t_extreme() {
    printf '\n  # deep-tune: módulos avançados rodam e a reversão respeita a tag\n'
    rm -rf "$HOME/.packotm/deep"
    # módulos que sobraram executam sem erro
    for m in debloat display dexopt; do
        OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" "$m" on >/dev/null 2>&1
        assert_eq "0" "$?" "módulo $m on roda sem erro"
    done
    # com props existentes, display/dalvik registram reversão (tag correta)
    rm -rf "$HOME/.packotm/deep"
    mkdir -p "$TMP/bin_prop"
    printf '#!/bin/sh\necho valor_antigo\n' > "$TMP/bin_prop/getprop"
    chmod +x "$TMP/bin_prop/getprop"
    PATH="$TMP/bin_prop:$PATH" OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" display on >/dev/null 2>&1
    assert_contains "$(deep_off)" '^display' "display registra reversão (com prop antiga)"
    # reverter só o display não mexe nas outras tags
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle add com.dts.freefireth >/dev/null 2>&1
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" display off >/dev/null 2>&1
    assert_not_contains "$(deep_off)" '^display' "display off remove só a tag display"
    assert_contains "$(deep_off)" '^angle' "display off preserva a tag angle"
    # o help lista os módulos que sobraram e NÃO lista os que saíram
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" > "$TMP/deep_help" 2>&1
    assert_contains "$TMP/deep_help" "debloat" "help do deep-tune lista debloat"
    assert_not_contains "$TMP/deep_help" "extreme" "help do deep-tune não lista mais extreme"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" restore >/dev/null 2>&1
}

t_adv_noroot() {
    printf '\n  # adb-tweaks: grupos avançados sem root aplicam e revertem\n'
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    for g in obscure mobile_net notif window_tweaks; do
        OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" "$g" >/dev/null 2>&1
    done
    assert_contains "$HOME/.packotm/undo/adb-tweaks.sh" "low_memory_kill" "obscure guarda reversão"
    assert_contains "$HOME/.packotm/undo/adb-tweaks.sh" "data_saver_mode" "mobile_net guarda reversão"
    assert_contains "$HOME/.packotm/undo/adb-tweaks.sh" "heads_up_notifications_enabled" "notif guarda reversão"
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" list > "$TMP/adb_list" 2>&1
    assert_contains "$TMP/adb_list" "obscure" "list mostra o grupo obscure"
    assert_contains "$TMP/adb_list" "window_tweaks" "list mostra o grupo window_tweaks"
    assert_contains "$TMP/adb_list" "sysbars" "list mostra o grupo sysbars (barras)"
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" restore_all >/dev/null 2>&1
    rm -rf "$HOME/.packotm"
}

t_sysbars() {
    printf '\n  # barras do sistema: esconder/mostrar com reversão (sem root)\n'
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    # esconder as duas: escreve o policy_control imersivo
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" sysbars off >/dev/null 2>&1
    assert_eq "immersive.full=*" "$(cat "$TMP_STORE/global.policy_control" 2>/dev/null)" \
        "sysbars off esconde as duas barras"
    assert_contains "$HOME/.packotm/undo/adb-tweaks.sh" "policy_control" \
        "sysbars guarda a reversão das barras"
    # voltar ao padrão: apaga a chave
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" sysbars on >/dev/null 2>&1
    [ ! -f "$TMP_STORE/global.policy_control" ] \
        && ok "sysbars on devolve as barras (padrão)" || bad "sysbars on não limpou o policy_control"
    # só a barra de baixo (a dos gestos: quadrado, bolinha, voltar)
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" sysbars so_nav >/dev/null 2>&1
    assert_eq "immersive.navigation=*" "$(cat "$TMP_STORE/global.policy_control" 2>/dev/null)" \
        "sysbars so_nav esconde só a barra de baixo"
    # estado lido de volta pelo panel-state (marcação de "Em uso" no painel)
    out=$(OTM_NO_COLOR=1 OTM_MODE=local sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/sb_out"
    grep -q '"sysbars":"nav"' "$TMP/sb_out" && ok "state: lê a barra escondida (nav)" \
        || bad "state: sysbars não leu 'nav'"
    # o card "Barra de cima: ícones" marca a opção em uso pelo valor canônico
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" sysbars clean >/dev/null 2>&1
    out=$(OTM_NO_COLOR=1 OTM_MODE=local sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/sb_ic"
    grep -q '"sysbars_icons_clean":"clean"' "$TMP/sb_ic" \
        && ok "state: card de ícones marca 'Só o essencial' quando escondido" \
        || bad "state: sysbars_icons_clean não leu 'clean'"
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" sysbars icons none >/dev/null 2>&1
    out=$(OTM_NO_COLOR=1 OTM_MODE=local sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/sb_ic2"
    grep -q '"sysbars_icons_clean":"all"' "$TMP/sb_ic2" \
        && ok "state: card de ícones marca 'Mostrar todos' quando limpo" \
        || bad "state: sysbars_icons_clean não leu 'all'"
    # bateria em %: card lê o valor real (1 = número, 0 = só ícone)
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" sysbars battery on >/dev/null 2>&1
    out=$(OTM_NO_COLOR=1 OTM_MODE=local sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/sb_bat"
    grep -q '"sysbars_battery":"1"' "$TMP/sb_bat" \
        && ok "state: card de bateria lê '1' (número)" || bad "state: sysbars_battery não leu '1'"
    # restaurar tudo volta as barras ao padrão
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" restore_all >/dev/null 2>&1
    [ ! -f "$TMP_STORE/global.policy_control" ] \
        && ok "restore_all devolve as barras (padrão)" || bad "restore_all não devolveu as barras"
    rm -rf "$HOME/.packotm"
}

t_gfxdriver() {
    printf '\n  # driver gráfico do sistema: aplica, verifica de verdade e reverte\n'
    rm -rf "$HOME/.packotm"
    out=$(OTM_MODE=local OTM_NO_COLOR=1 sh "$ROOT/scripts/deep-tune.sh" gfxdriver status 2>&1)
    printf '%s\n' "$out" > "$TMP/gd_status"
    assert_contains "$TMP/gd_status" '#OTM-RESULT tag=deep:gfxdriver' "gfxdriver status emite o resultado"
    # ANGLE em todos os apps: aplica e confirma na leitura
    out=$(OTM_MODE=local OTM_NO_COLOR=1 sh "$ROOT/scripts/deep-tune.sh" gfxdriver angle_all on 2>&1)
    printf '%s\n' "$out" > "$TMP/gd_aa"
    assert_eq "1" "$(cat "$TMP_STORE/global.angle_gl_driver_all_angle" 2>/dev/null)" \
        "angle_all on aplica de verdade"
    assert_contains "$TMP/gd_aa" "changed=1" "gfxdriver confirma a mudança real (changed=1)"
    # reaplicar NÃO pode empilhar reversão (senão o restore devolvia o valor errado)
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" gfxdriver angle_all off >/dev/null 2>&1
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" gfxdriver angle_all on >/dev/null 2>&1
    n=$(grep -c 'angle_gl_driver_all_angle' "$HOME/.packotm/deep/off.sh" 2>/dev/null)
    assert_eq "1" "$n" "reaplicar não empilha reversão (1 linha)"
    # restore devolve ao padrão (nada estava setado antes)
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" restore >/dev/null 2>&1
    [ ! -f "$TMP_STORE/global.angle_gl_driver_all_angle" ] \
        && ok "gfxdriver restore devolve ao padrão" || bad "gfxdriver restore não devolveu"
    # sem acesso real, não pode dizer que deu certo
    mkdir -p "$TMP/bin_gd"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin_gd/settings"
    chmod +x "$TMP/bin_gd/settings"
    out=$(TMP_STORE="$TMP/store_gd" PATH="$TMP/bin_gd:$PATH" OTM_MODE=local OTM_NO_COLOR=1 \
        sh "$ROOT/scripts/deep-tune.sh" gfxdriver gamedriver on 2>&1)
    printf '%s\n' "$out" > "$TMP/gd_bad"
    assert_contains "$TMP/gd_bad" "failed=1" "gfxdriver detecta falha real (failed=1)"
    assert_contains "$TMP/gd_bad" "ok=0" "gfxdriver não mascara sucesso sem acesso"
    rm -rf "$TMP/bin_gd" "$TMP/store_gd" "$HOME/.packotm"
}

# deep_off já definido acima (lê o arquivo de reversão do deep-tune)

t_realverify() {
    printf '\n  # verificação REAL: settings confirma, e falha vira X (não ok)\n'
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    # caso 1: o settings do stub funciona -> muda de verdade e reporta changed>=1
    out=$(OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" perf 2>&1)
    printf '%s\n' "$out" > "$TMP/vout"
    assert_contains "$TMP/vout" '#OTM-RESULT' "adb-tweaks emite #OTM-RESULT"
    res=$(printf '%s\n' "$out" | grep '#OTM-RESULT')
    ch=$(printf '%s' "$res" | sed -n 's/.*changed=\([0-9]*\).*/\1/p')
    [ "${ch:-0}" -ge 1 ] && ok "perf confirmou mudança real (changed=$ch)" \
        || bad "perf não confirmou mudança (changed=$ch)"
    assert_contains "$TMP/vout" "OK" "saída mostra OK para valores aplicados"
    # caso 2: settings quebrado (não grava) -> verificação marca X e failed>=1.
    # Store limpo + stub que engole settings E setprop: "sem acesso real" não
    # pode mascarar nada. (Só o settings quebrado não bastava: a prop do
    # renderizador ainda gravava de verdade e virava um "changed" solitário.)
    mkdir -p "$TMP/bin_bad" "$TMP/store_bad"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin_bad/settings"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin_bad/setprop"
    chmod +x "$TMP/bin_bad/settings" "$TMP/bin_bad/setprop"
    out2=$(TMP_STORE="$TMP/store_bad" PATH="$TMP/bin_bad:$PATH" OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" perf 2>&1)
    printf '%s\n' "$out2" > "$TMP/vout2"
    res2=$(printf '%s\n' "$out2" | grep '#OTM-RESULT')
    fl=$(printf '%s' "$res2" | sed -n 's/.*failed=\([0-9]*\).*/\1/p')
    okf=$(printf '%s' "$res2" | sed -n 's/.*ok=\([0-9]*\).*/\1/p')
    [ "${fl:-0}" -ge 1 ] && ok "settings quebrado vira failed=$fl" || bad "não detectou falha (failed=$fl)"
    assert_eq "0" "${okf:-x}" "veredito ok=0 quando nada mudou de verdade"
    assert_contains "$TMP/vout2" "nao mudou" "saída avisa 'nao mudou' quando a leitura não bate"
    rm -rf "$TMP/bin_bad" "$HOME/.packotm"
}

t_realverify_deep() {
    printf '\n  # verificação REAL: deep-tune display aplica e restaura props\n'
    rm -rf "$HOME/.packotm"
    mkdir -p "$TMP/bin_prop"
    printf '#!/bin/sh\necho valor_antigo\n' > "$TMP/bin_prop/getprop"
    chmod +x "$TMP/bin_prop/getprop"
    out=$(PATH="$TMP/bin_prop:$PATH" OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" display on 2>&1)
    printf '%s\n' "$out" > "$TMP/dv_out"
    assert_contains "$TMP/dv_out" '#OTM-RESULT tag=deep:display' "display emite o resultado com a tag"
    assert_eq "true" "$(cat "$TMP_STORE/prop.debug.hwui.use_buffer_age" 2>/dev/null)" \
        "display aplica a prop de HWUI"
    assert_contains "$(deep_off)" '^display' "display registra reversão das props antigas"
    # reverter devolve o valor original
    PATH="$TMP/bin_prop:$PATH" OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" display off >/dev/null 2>&1
    assert_eq "valor_antigo" "$(cat "$TMP_STORE/prop.debug.hwui.use_buffer_age" 2>/dev/null)" \
        "display off restaura a prop original"
    assert_not_contains "$(deep_off)" '^display' "display off limpa a reversão"
    rm -rf "$HOME/.packotm"
}

t_config() {
    printf '\n  # config.sh: mostra, salva e testa a conexão (sem root)\n'
    rm -rf "$HOME/.packotm"
    out=$(OTM_NO_COLOR=1 sh "$ROOT/scripts/config.sh" show 2>&1)
    printf '%s\n' "$out" > "$TMP/cfgout"
    assert_contains "$TMP/cfgout" 'Configuração de acesso' "config show explica a conexão"
    assert_contains "$TMP/cfgout" 'modo' "config show mostra o modo"
    sh "$ROOT/scripts/config.sh" set adb 192.168.0.10:5555 >/dev/null 2>&1
    assert_contains "$HOME/.packotm/config" 'OTM_ADB_SERIAL=192.168.0.10:5555' "config salva o endereço ADB Wi-Fi"
    sh "$ROOT/scripts/config.sh" set rish /data/local/tmp/rish >/dev/null 2>&1
    assert_contains "$HOME/.packotm/config" 'OTM_MODE=rish' "config salva o modo rish"
    # depuração USB (só autorizar, sem parear): modo 'usb' e roteamento pelo adb
    sh "$ROOT/scripts/config.sh" set usb >/dev/null 2>&1
    assert_contains "$HOME/.packotm/config" 'OTM_MODE=usb' "config salva o modo usb (depuração USB)"
    cat > "$TMP/bin/adb" <<'EOF'
#!/bin/sh
# stub: finge o adb do PC e marca a chamada de shell
[ "$1" = "shell" ] && { shift; echo "usb:$*"; exit 0; }
exit 0
EOF
    chmod +x "$TMP/bin/adb"
    usbout=$(OTM_MODE=usb sh -c '. "'"$ROOT"'/scripts/common.sh"; sh_get "echo oi"' 2>&1)
    assert_eq "usb:echo oi" "$usbout" "modo usb manda o comando pelo adb shell"
    sh "$ROOT/scripts/config.sh" set rish /data/local/tmp/rish >/dev/null 2>&1
    # test roda e reporta (mesmo sem conexão) — não pode travar
    tout=$(OTM_NO_COLOR=1 timeout 20 sh "$ROOT/scripts/config.sh" test 2>&1)
    printf '%s\n' "$tout" > "$TMP/cfgtest"
    assert_contains "$TMP/cfgtest" '#OTM-RESULT' "config test reporta resultado"
    sh "$ROOT/scripts/config.sh" reset >/dev/null 2>&1
    [ ! -f "$HOME/.packotm/config" ] && ok "config reset apaga o arquivo" || bad "reset não apagou"
    rm -rf "$HOME/.packotm"
}

t_auth() {
    printf '\n  # login do painel (00deUdia)\n'
    if command -v php >/dev/null 2>&1; then
        rm -f "$HOME/.packotm/web/auth.json"
        OTM_TEST_PASS="${OTM_TEST_PASS:-159951}"; export OTM_TEST_PASS
        php -r 'require "'"$ROOT"'/web/auth.php";
                 echo otm_auth_login("00deUdia",getenv("OTM_TEST_PASS")) ? "OK":"NAO";' \
                 > "$TMP/auth1" 2>&1
        assert_contains "$TMP/auth1" "OK" "credencial inicial do painel funciona"
        php -r 'require "'"$ROOT"'/web/auth.php";
                 echo otm_auth_login("00deUdia","errada") ? "ACEITOU":"RECUSOU";' > "$TMP/auth2" 2>&1
        assert_contains "$TMP/auth2" "RECUSOU" "senha errada e recusada"
        php -r 'require "'"$ROOT"'/web/auth.php"; otm_auth_set("chefe","segredo123");
                 echo otm_auth_login("chefe","segredo123") ? "OK":"NAO";' > "$TMP/auth3" 2>&1
        assert_contains "$TMP/auth3" "OK" "troca de usuario/senha funciona"
        if grep -q "segredo123" "$HOME/.packotm/web/auth.json" 2>/dev/null; then
            bad "senha gravada em texto puro"
        else
            ok "senha guardada com hash (nao em texto puro)"
        fi
        php -r 'require "'"$ROOT"'/web/auth.php"; otm_auth_set("00deUdia",getenv("OTM_TEST_PASS"));' >/dev/null 2>&1
    else
        printf '  [skip] php ausente: pulei testes de login\n'
    fi
}

t_noroot_only() {
    printf '\n  # tudo funciona sem root: ações do painel não exigem root\n'
    php -r 'require "'"$ROOT"'/web/lib.php";
             $r=otm_run("config.set",["mode"=>"rish"],false);
             echo ($r["ok"]||isset($r["need_confirm"]))?"DISPONIVEL":"BLOQUEADO";' \
        > "$TMP/noroot" 2>&1
    assert_contains "$TMP/noroot" "DISPONIVEL" "ação de config existe no painel"
    php -r 'require "'"$ROOT"'/web/lib.php"; otm_run("config.reset",[],false);' >/dev/null 2>&1
    # o pack é sem root: nenhuma ação do painel pode exigir root
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions(); $root=0;$tot=0;
             foreach ($a as $x){ $tot++; if (($x["risk"]??"")==="root") $root++; }
             echo "root=$root total=$tot\n";' > "$TMP/rootcnt" 2>&1
    assert_contains "$TMP/rootcnt" "root=0 " "nenhuma ação do painel exige root"
    assert_contains "$TMP/rootcnt" "total=" "registro de ações contável"
    rm -rf "$HOME/.packotm"
}


# --- espelho dos scripts: assets/pack/scripts == scripts ----------------------
# O Gradle sincroniza (task syncPackAssets), mas o espelho é versionado: sem este
# teste ele volta a divergir (foi assim que cool-down.sh ficou preso no asset e
# profile-custom.sh nunca chegou lá).
t_pack_scripts_mirror() {
    printf '\n  # espelho dos scripts: assets/pack/scripts == scripts\n'
    local src="$ROOT/scripts" dst="$ROOT/app/src/main/assets/pack/scripts"
    if ! diff -r "$src" "$dst" > "$TMP/mirror_diff" 2>&1; then
        bad "assets/pack/scripts divergiu de scripts ($(head -1 "$TMP/mirror_diff"))"
    else
        ok "assets/pack/scripts é igual a scripts (sem sobras nem faltas)"
    fi
    # todo script que uma ação do painel chama (argv[0]) tem de existir no espelho
    php -r 'require "'"$ROOT"'/web/lib.php";
             $d = "'"$ROOT"'/app/src/main/assets/pack/scripts";
             $miss = [];
             foreach (otm_actions() as $id => $a) {
                 $s = $a["argv"][0] ?? "";
                 if (substr($s, -3) === ".sh" && !is_file("$d/$s")) $miss[] = "$id->$s";
             }
             echo $miss ? "FALTAM: " . implode(", ", $miss) . "\n" : "OK\n";' > "$TMP/mirror_argv" 2>&1
    assert_contains "$TMP/mirror_argv" "OK" "toda ação aponta para um script existente no espelho"
}

# --- painel novo (Turso/SQLite): chaves validadas no banco --------------------
t_panel_db() {
    printf '\n  # painel: administradores no banco\n'
    if ! command -v php >/dev/null 2>&1; then
        printf '  [skip] php ausente: pulei os testes do painel\n'
        return 0
    fi
    if ! php -m 2>/dev/null | grep -qi 'pdo_sqlite'; then
        printf '  [skip] pdo_sqlite ausente: pulei os testes do painel\n'
        return 0
    fi

    local dbf="$TMP/painel.sqlite"
    rm -f "$dbf"*
    # banco local (sem rede): o mesmo código que roda no Turso
    local nmig
    nmig="$(ls "$ROOT"/panel/database/migrations/*.sql 2>/dev/null | wc -l | tr -d ' ')"
    if OTM_LOCAL_DB="$dbf" php "$ROOT/panel/bin/migrate.php" > "$TMP/mig" 2>&1; then
        if grep -q "pronto — ${nmig} migration" "$TMP/mig"; then
            ok "migrações aplicam no banco ($nmig)"
        else
            bad "migrações incompletas (esperava $nmig): $(head -1 "$TMP/mig")"
        fi
    else
        bad "migrações falharam: $(head -1 "$TMP/mig")"
        return 0
    fi

    # nenhuma tabela do sistema de chaves deve existir
    local tbl
    tbl="$(OTM_LOCAL_DB="$dbf" php -r '
             require $argv[1]."/src/bootstrap.php";
             $q = "select name from sqlite_master where type = " . chr(39) . "table" . chr(39);
             foreach (otm_db()->all($q) as $r)
                 if (str_contains((string)$r["name"], "key")) echo $r["name"]." ";' \
             "$ROOT/panel" 2>/dev/null)"
    if [ -z "$tbl" ]; then ok "nenhuma tabela de chaves no banco"; else bad "sobrou tabela de chave: $tbl"; fi

    # admin do painel (usuário e senha)
    if OTM_LOCAL_DB="$dbf" OTM_PASSWORD=segredo123 php "$ROOT/panel/bin/admin.php" add whesley --role owner >/dev/null 2>&1; then
        ok "admin do painel criado"
    else
        bad "não criei o admin do painel"
    fi

    # o admin entra com a senha certa e a senha errada é recusada
    OTM_LOCAL_DB="$dbf" php -r '
        require $argv[1]."/src/bootstrap.php";
        $h = (string)otm_db()->scalar("select password_hash from otm_admins where username = ?", ["whesley"]);
        echo (password_verify("segredo123", $h) ? "ENTRA " : "NAO_ENTRA ");
        echo (!password_verify("errada", $h) ? "RECUSA" : "ACEITOU_ERRADA");
    ' "$ROOT/panel" > "$TMP/auth" 2>&1
    assert_contains "$TMP/auth" "ENTRA"  "admin entra com usuário e senha"
    assert_contains "$TMP/auth" "RECUSA" "senha errada é recusada"

    # a senha não fica em texto puro no banco
    OTM_LOCAL_DB="$dbf" php -r '
        require $argv[1]."/src/bootstrap.php";
        $r = otm_db()->all("select username, password_hash from otm_admins");
        echo (str_contains(json_encode($r), "segredo123") ? "ACHOU" : "SEGURO");
    ' "$ROOT/panel" > "$TMP/plain" 2>&1
    assert_contains "$TMP/plain" "SEGURO" "senha não é gravada em texto puro"

    # não sobrou nenhuma referência ao sistema de chaves no painel
    if grep -rqs 'otm_keys\|KeyService\|KeyVault\|key_prefix' "$ROOT/panel/src" "$ROOT/panel/public"; then
        bad "painel ainda referencia o sistema de chaves"
    else
        ok "painel sem referências ao sistema de chaves"
    fi
}


# --- login do app Android (painel estático) ----------------------------------
t_app_login() {
    printf '\n  # login do app (usuário e senha)\n'
    local p="$ROOT/app/src/main/assets/panel"
    [ -f "$p/index.html" ] && ok "painel do app existe" || bad "index.html do app ausente"
    [ -f "$p/login.html" ] && ok "tela de login do app existe" || bad "login.html do app ausente"
    grep -q 'otm_session' "$p/index.html" && ok "painel do app tem guarda de sessão" \
        || bad "painel do app sem guarda de sessão"
    grep -q 'sha256' "$p/login.html" && ok "login valida usuário e senha (sha256)" \
        || bad "login sem validação de usuário/senha"
    grep -q 'panel/login.html' "$ROOT/app/src/main/java/com/otm/pack/PanelActivity.kt" \
        && ok "PanelActivity abre a tela de login" || bad "PanelActivity não abre login"
    # o app não deve mais ter o sistema de chaves
    [ ! -f "$ROOT/app/src/main/java/com/otm/pack/KeyGate.kt" ] \
        && ok "KeyGate removido do app" || bad "KeyGate ainda existe no app"
    [ ! -f "$ROOT/app/src/main/java/com/otm/pack/License.kt" ] \
        && ok "License removido do app" || bad "License ainda existe no app"
    # todo link do menu tem de ter a seção correspondente: o painel é gerado por
    # script (sync_app_panel) e uma categoria nova pode entrar no nav sem a seção,
    # deixando um link que não abre nada.
    python3 - "$p/index.html" <<'PY' > "$TMP/navsec" 2>&1
import re, sys, html as H, urllib.parse
doc = open(sys.argv[1], encoding='utf-8').read()
nav = re.search(r'<nav class="nav" id="nav">[\s\S]*?</nav>', doc).group(0)
# cada link do menu aponta para a seção "g-<data-g>"; os ids vêm com o nome
# URL-encoded e o data-g com entidade HTML (&amp;), então normalizo os dois.
links = [H.unescape(m) for m in re.findall(r'data-g="([^"]+)"', nav)]
secs = {urllib.parse.unquote(m) for m in re.findall(r'<section id="([^"]+)"', doc)}
faltam = [g for g in links if 'g-' + g not in secs]
print('OK' if not faltam else 'FALTAM:' + ','.join(faltam))
PY
    assert_contains "$TMP/navsec" "OK" "app: todo link do menu tem a sua seção"

    # o painel do app é montado por script (sync_app_panel); um card que ficou
    # entre o fim de uma seção e o começo da próxima não pertence a grupo nenhum
    # e aparece SEMPRE, empilhado no rodapé, fora das abas. Também denuncia
    # <section> desbalanceada. Já aconteceu com os cards de permissão (v2.41.2).
    python3 - "$p/index.html" <<'PY' > "$TMP/panstruct" 2>&1
import re, sys
from collections import Counter
doc = open(sys.argv[1], encoding='utf-8').read()
# só os cards de verdade (o texto do JS também cita data-id="apply")
cards = re.findall(r'<article class="card"[^>]*?data-id="([^"]+)"', doc)
dup = sorted(k for k, v in Counter(cards).items() if v > 1)
orf = [m.group(1).strip()[:60] for m in
       re.finditer(r'</section>([\s\S]*?)(?=<section\b|</main>)', doc)
       if '<article class="card"' in m.group(1)]
abre, fecha = len(re.findall(r'<section\b', doc)), doc.count('</section>')
prob = []
if dup: prob.append('cards duplicados: ' + ','.join(dup))
if orf: prob.append('cards fora de seção: ' + ' | '.join(orf))
if abre != fecha: prob.append('seções desbalanceadas: %d abre x %d fecha' % (abre, fecha))
print('OK' if not prob else ' | '.join(prob))
PY
    assert_contains "$TMP/panstruct" "OK" "app: nenhum card duplicado nem fora de seção"
}

# --- scripts rodam em /data/local/tmp (visível ao shell) ----------------------
t_app_exec() {
    printf '\n  # scripts rodam em /data/local/tmp (shell lê)\n'
    local src="$ROOT/app/src/main/java/com/otm/pack"
    grep -q '/data/local/tmp/otm-pack' "$src/PackAssets.kt" \
        && ok "scripts vão para /data/local/tmp/otm-pack" || bad "scripts não vão p/ /data/local/tmp"
    grep -q 'ensureShellCopy' "$src/PackAssets.kt" \
        && ok "PackAssets copia p/ o shell" || bad "sem ensureShellCopy"
    # o bridge monta o comando a partir da pasta visível ao shell
    grep -q 'OtmExec.scriptCommand' "$src/PackBridge.kt" \
        && ok "PackBridge usa a pasta de execução" || bad "PackBridge ainda usa filesDir"
    # o comando de execução não pode apontar para o filesDir do app (0700)
    awk '/fun scriptCommand/,/^    }/' "$src/OtmExec.kt" > "$TMP/scmd"
    if grep -q 'packDir()' "$TMP/scmd"; then
        bad "comando ainda usa o filesDir do app"
    else
        ok "comando usa a pasta visível ao shell"
    fi
    grep -q 'ensureShellCopy' "$src/OtmExec.kt" \
        && ok "executor compartilhado usa a pasta do shell" || bad "OtmExec sem ensureShellCopy"
}

# --- menu lateral do painel: fica fixo ao rolar ------------------------------
t_side_fixed() {
    printf '\n  # menu lateral fica fixo (não escorrega)\n'
    grep -q 'position:fixed' "$ROOT/web/index.php" && ok "index.php tem elemento fixo" \
        || bad "index.php sem position:fixed"
    # o CSS do menu pode ter quebra de linha; junta tudo numa linha p/ conferir
    tr '\n' ' ' < "$ROOT/web/index.php" > "$TMP/css1"
    grep -qE '\.side \.panel\{ *position:fixed' "$TMP/css1" \
        && ok "painel do menu é position:fixed" || bad "menu não está fixo no desktop"
    grep -qE '\.side \.panel\{ *position:static' "$TMP/css1" \
        && ok "gaveta mobile volta a position:static" || bad "gaveta mobile quebrada"
}

# descobre onde o plugin guardou o estado (STATE pode cair no fallback $DIR/state)
plugin_state() {
    if [ -f /data/adb/packotm/deep_mark ] || [ -d /data/adb/packotm ]; then
        echo /data/adb/packotm
    else
        echo "$1/state"
    fi
}

# --- correções pedidas no aparelho (arrasto, topo, papel de parede, engrenagem, som)
t_app_fixes() {
    printf '\n  # correções do painel (arrasto, topo, papel de parede, engrenagem, som)\n'
    local app="$ROOT/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"
    local src="$ROOT/app/src/main/java/com/otm/pack"
    tr '\n' ' ' < "$app" > "$TMP/fx1"
    tr '\n' ' ' < "$web" > "$TMP/fx2"
    # 1) não arrasta para o lado: transbordo clipado e topo sem largura fixa
    grep -q 'overflow-x:clip' "$app" && ok "app: overflow-x clipado (sem arrasto lateral)" || bad "app: overflow-x não clipado"
    grep -q 'overflow-x:clip' "$web" && ok "web: overflow-x clipado" || bad "web: overflow-x não clipado"
    grep -qE '\.top\{ *position:sticky; top:0; z-index:40; min-height:var\(--top\)' "$TMP/fx1" \
        && ok "app: topo usa min-height (não estoura a largura)" || bad "app: topo com altura fixa"
    # 2) topo organizado: quebra de linha e botões que não encolhem
    grep -q 'flex-wrap:wrap' "$TMP/fx1" && ok "app: topo organizado (flex-wrap)" || bad "app: topo sem flex-wrap"
    grep -q 'flex:none' "$TMP/fx1" && ok "app: botões do topo não encolhem" || bad "app: botões encolhem"
    # 3) papel de parede inteiro (contain) com fundo que preenche (cover)
    grep -q "wallpaper.jpeg') center/contain" "$TMP/fx1" && ok "app: papel de parede inteiro (contain)" || bad "app: papel de parede cortado"
    grep -q "wallpaper.jpeg') center/cover" "$TMP/fx1" && ok "app: fundo preenche a tela (cover)" || bad "app: fundo sem cover"
    grep -q "wallpaper.jpeg') center/contain" "$TMP/fx2" && ok "web: papel de parede inteiro (contain)" || bad "web: papel de parede cortado"
    # 4) engrenagem + modal de configurações (tema, cor, som)
    grep -q 'id="btnGear"' "$app" && ok "app: botão de engrenagem existe" || bad "app: sem engrenagem"
    grep -q 'id="gearMask"' "$app" && ok "app: modal de configurações existe" || bad "app: sem modal de config"
    grep -q 'id="btnGear"' "$web" && ok "web: botão de engrenagem existe" || bad "web: sem engrenagem"
    grep -q 'id="setAccent"\|id="setSound"' "$app" && ok "app: config tem cor/som" || bad "app: config incompleta"
    # o app é SÓ modo escuro: nada de alternância claro/escuro nem de data-theme
    if grep -q 'id="setTheme"\|data-theme\|otm-theme\|btnTheme' "$app"; then
        bad "app: ainda tem alternância de tema claro/escuro"
    else
        ok "app: sem alternância de tema (só escuro)"
    fi
    if grep -q 'id="setTheme"\|data-theme\|otm-theme\|btnTheme' "$web"; then
        bad "web: ainda tem alternância de tema claro/escuro"
    else
        ok "web: sem alternância de tema (só escuro)"
    fi
    grep -q 'name="color-scheme" content="dark"' "$app" \
        && ok "app: color-scheme fixo em escuro" || bad "app: color-scheme não é só escuro"
    grep -q 'id="setAccentCustom"\|id="setAccentHex"\|id="setAccentApply"' "$app" \
        && grep -q 'id="setAccentCustom"\|id="setAccentHex"\|id="setAccentApply"' "$web" \
        && ok "cor personalizada no app e no web" || bad "cor personalizada ausente"
    grep -q 'accentFromHex' "$app" && grep -q 'accentFromHex' "$web" \
        && ok "cor personalizada: hex vira accent/tinta/anel" || bad "cor personalizada sem conversão"
    grep -q 'ui_prefs' "$src/PackBridge.kt" \
        && ok "painel flutuante: recebe a cor/fonte do painel" || bad "overlay sem ui_prefs"
    grep -q "ui' => 'appearance'" "$ROOT/web/lib.php" && ok "registro tem a ação de aparência" || bad "sem ação de aparência"
    grep -q '"appearance"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem a ação de aparência" || bad "app: actions.json sem aparência"
    grep -q 'a.id === "appearance"' "$app" && ok "app: card de aparência abre a engrenagem" || bad "app: card não abre a engrenagem"
    # 5) som: ligar/desligar e sem corte pelo timer do som anterior
    grep -q 'onSoundSet' "$src/PanelActivity.kt" && ok "som: painel liga/desliga (onSoundSet)" || bad "som: painel sem onSoundSet"
    grep -q 'removeCallbacks(autoStop)' "$src/SoundPlayer.kt" \
        && ok "som: timer antigo é cancelado (não corta o próximo)" || bad "som: timer não cancelado"
    grep -q 'handler.removeCallbacks(autoStop)' "$src/SoundPlayer.kt" && ok "som: stop cancela o timer" || bad "som: stop não cancela"
    # 6) "login feito com sucesso" só toca quando o login dá certo
    local login="$ROOT/app/src/main/assets/panel/login.html"
    grep -q 'OTM.call("login"' "$login" && ok "login: avisa o app só no acerto" || bad "login: sem aviso de sucesso"
    grep -q 'onLogin = { sound.play("login_feito_com_sucesso.mp3") }' "$src/PanelActivity.kt" \
        && ok "som: sucesso ligado ao onLogin" || bad "som: sucesso não está no onLogin"
    if grep -n 'login_feito_com_sucesso' "$src/PanelActivity.kt" | grep -qv 'onLogin'; then
        bad "som: sucesso ainda toca fora do login"
    else
        ok "som: sucesso não toca ao conectar/ligar som"
    fi
    grep -q 'if (on) sound.play("ativando.mp3")' "$src/PanelActivity.kt" \
        && ok "som: ligar som usa 'ativando'" || bad "som: ligar som com áudio errado"
    # o app não pode mais ter o sistema de chaves
    [ ! -f "$src/KeyGate.kt" ] && ok "chave: KeyGate removido do app" || bad "chave: KeyGate ainda existe"
    [ ! -f "$src/License.kt" ] && ok "chave: License removido do app" || bad "chave: License ainda existe"
    # 7) áudio de pareamento (conectar) continua valendo
    test -f "$ROOT/app/src/main/assets/audio/pareamento_feito_com_sucesso.mp3" \
        && ok "áudio: pareamento presente" || bad "áudio: falta pareamento"
    grep -q 'sound.play("pareamento_feito_com_sucesso.mp3")' "$src/PanelActivity.kt" \
        && ok "som: conectar usa o áudio de pareamento" || bad "som: conectar sem áudio de pareamento"
    # 7b) fecho de cada ação: sucesso ou erro (no app e no site)
    test -f "$ROOT/app/src/main/assets/audio/perfil-aplicado-com-sucesso.mp3" \
        && ok "áudio: 'perfil aplicado com sucesso' presente" || bad "áudio: falta 'perfil aplicado'"
    test -f "$ROOT/app/src/main/assets/audio/erro.mp3" \
        && ok "áudio: 'erro' presente" || bad "áudio: falta 'erro'"
    test -f "$ROOT/app/src/main/assets/audio/login_feito_com_sucesso.mp3" \
        && ok "áudio: 'login feito com sucesso' presente" || bad "áudio: falta 'login feito'"
    grep -q 'PackCatalog.SND_OK' "$src/PackBridge.kt" && grep -q 'PackCatalog.SND_ERR' "$src/PackBridge.kt" \
        && ok "som: ação toca sucesso/erro no fim" || bad "som: sem fecho de sucesso/erro"
    grep -q 'login_feito_com_sucesso.mp3' "$ROOT/server.js" \
        && ok "web: ponte do site toca o áudio de login" || bad "web: ponte do site sem áudio de login"
    # 8) ícones no lugar de emojis (menos a engrenagem, que fica como está)
    if grep -qP '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}]' "$app"; then
        bad "ícones: ainda há emoji no painel do app"
    else
        ok "ícones: painel do app sem emojis"
    fi
    grep -q 'id="btnGear"' "$app" && ok "ícones: engrenagem preservada" || bad "ícones: engrenagem sumiu"
    grep -q 'class="stroke"' "$app" && ok "ícones: SVGs profissionais presentes" || bad "ícones: sem SVGs"
    # 9) atualizar sem desinstalar: keystore fixa e assinatura de release
    test -f "$ROOT/keystore/otm-release.jks" \
        && ok "update: keystore versionada presente" || bad "update: sem keystore versionada"
    grep -q 'signingConfig = signingConfigs.getByName("release")' "$ROOT/app/build.gradle.kts" \
        && ok "update: release assina com a keystore fixa" || bad "update: release sem assinatura fixa"
    grep -q 'if (a.argv.isEmpty())' "$src/PackBridge.kt" \
        && ok "bridge: ação sem comando não tenta executar" || bad "bridge: tenta executar ação de UI"
    # 9b) conexão por depuração USB (só autorizar, sem parear)
    grep -q 'Depuração USB (só autorizar)' "$src/PanelActivity.kt" \
        && ok "conexão: opção de depuração USB no diálogo" || bad "conexão: sem opção de depuração USB"
    grep -q 'fun useAdbLocal()' "$src/PanelActivity.kt" \
        && ok "conexão: useAdbLocal liga o ADB local" || bad "conexão: sem useAdbLocal"
    grep -q 'fun connectLocal()' "$src/AdbRunner.kt" \
        && ok "conexão: AdbRunner.connectLocal (loopback + mDNS)" || bad "conexão: sem connectLocal"
    grep -q 'autoConnect(context' "$src/AdbRunner.kt" \
        && ok "conexão: descobre o adbd pela rede (mDNS)" || bad "conexão: sem descoberta mDNS"
    grep -q 'set usb' "$ROOT/scripts/config.sh" && grep -q 'usb)   cfg_write usb' "$ROOT/scripts/config.sh" \
        && ok "conexão: config.sh aceita o modo usb" || bad "conexão: config.sh sem modo usb"
    # 9c) ADB por Wi-Fi simplificado: só o código de 6 números (mDNS acha as portas)
    grep -q 'fun pairWithCode(' "$src/AdbRunner.kt" \
        && ok "wifi: pareia só com o código (pairWithCode)" || bad "wifi: sem pareamento por código"
    grep -q 'SERVICE_TYPE_TLS_PAIRING' "$src/AdbRunner.kt" \
        && ok "wifi: descobre o serviço de pareamento (mDNS)" || bad "wifi: sem descoberta do pareamento"
    grep -q 'SERVICE_TYPE_TLS_CONNECT' "$src/AdbRunner.kt" && grep -q 'fun connectWireless(' "$src/AdbRunner.kt" \
        && ok "wifi: conecta sem digitar porta (connectWireless)" || bad "wifi: conexão sem porta ausente"
    grep -q 'Código de 6 números' "$src/WifiDialog.kt" \
        && ok "wifi: diálogo pede só o código" || bad "wifi: diálogo não simplificado"
    # o diálogo tem UM campo só (o código) e nada de IP/porta na mão: quem acha o
    # pareamento é o mDNS. Campos manuais eram a razão de o usuário não conseguir
    # conectar — ele não tem como saber a porta.
    if grep -qE 'Porta de (conexão|pareamento)|Avançado|Endereço \(ex\.' "$src/WifiDialog.kt"; then
        bad "wifi: diálogo ainda pede IP/porta na mão"
    else
        ok "wifi: diálogo não pede IP/porta (só o código)"
    fi
    grep -q 'adb.pairWithCode(' "$src/WifiDialog.kt" \
        && ok "wifi: o diálogo pareia pelo código (mDNS)" || bad "wifi: diálogo não pareia por código"
    grep -q 'ADB por Wi-Fi (só o código)' "$src/PanelActivity.kt" \
        && ok "wifi: opção do menu de conexão simplificada" || bad "wifi: opção do menu não atualizada"
    # 9d) pareamento por Wi-Fi: as três causas da falha ficam cobertas
    #     (a) TLS 1.3 do pareamento usa API oculta do Conscrypt -> precisa do bypass
    grep -q 'HiddenApiBypass.addHiddenApiExemptions' "$src/OtmApp.kt" \
        && ok "wifi: libera as APIs ocultas (Conscrypt/TLS 1.3)" || bad "wifi: sem bypass das APIs ocultas"
    grep -q 'android:name=".OtmApp"' "$ROOT/app/src/main/AndroidManifest.xml" \
        && ok "wifi: OtmApp registrado no manifesto" || bad "wifi: OtmApp fora do manifesto"
    grep -q 'hiddenapibypass' "$ROOT/app/build.gradle.kts" \
        && ok "wifi: dependência do bypass declarada" || bad "wifi: dependência do bypass ausente"
    #     (b) descoberta mDNS exige permissão (13+: Dispositivos próximos; <=12: localização)
    grep -q 'NEARBY_WIFI_DEVICES' "$ROOT/app/src/main/AndroidManifest.xml" \
        && grep -q 'ACCESS_FINE_LOCATION' "$ROOT/app/src/main/AndroidManifest.xml" \
        && ok "wifi: permissões da descoberta no manifesto" || bad "wifi: manifesto sem permissão de descoberta"
    grep -q 'CHANGE_WIFI_MULTICAST_STATE' "$ROOT/app/src/main/AndroidManifest.xml" \
        && ok "wifi: permissão do multicast declarada" || bad "wifi: sem permissão de multicast"
    grep -q 'fun askMdns(' "$src/Permissions.kt" && grep -q 'Permissions.askMdnsThen(this)' "$src/PanelActivity.kt" \
        && ok "wifi: pede a permissão antes de parear" || bad "wifi: não pede a permissão de descoberta"
    # 9e) o diálogo de pareamento só abre DEPOIS de o usuário responder a
    #     permissão. Pedir e abrir na mesma hora fazia o código ser digitado
    #     antes de a permissão existir: o mDNS falhava em silêncio e a conexão
    #     nunca completava. O retorno precisa chegar ao callback.
    grep -q 'fun askMdnsThen(' "$src/Permissions.kt" \
        && ok "wifi: pedido de permissão com callback" || bad "wifi: sem askMdnsThen"
    grep -q 'fun onRequestPermissionsResult(' "$src/PanelActivity.kt" \
        && grep -q 'Permissions.REQ_MDNS' "$src/PanelActivity.kt" \
        && grep -q 'Permissions.onMdnsResult(' "$src/PanelActivity.kt" \
        && ok "wifi: o resultado da permissão é tratado (REQ_MDNS)" || bad "wifi: REQ_MDNS não tratado"
    # a conexão é TESTADA de verdade: connect() devolver true só diz que o socket
    # abriu; sem o teste o painel dizia "conectado" e as ações falhavam depois.
    grep -q 'suspend fun verify(' "$src/AdbRunner.kt" \
        && ok "wifi: a conexão é verificada (não só o socket)" || bad "wifi: conexão não é verificada"
    grep -q 'adb.connectAndVerify()' "$src/WifiDialog.kt" \
        && ok "wifi: o diálogo conecta e confere" || bad "wifi: diálogo não confere a conexão"
    grep -q 'adb.verify()' "$src/PanelActivity.kt" \
        && ok "wifi: a depuração USB também é verificada" || bad "wifi: USB não verifica a conexão"
    #     (c) a chave e o certificado do ADB têm de ser SEMPRE do mesmo par
    if grep -q 'fun loadOrCreateCert' "$src/AdbRunner.kt"; then
        bad "wifi: certificado ainda pode sair de um par diferente da chave"
    else
        ok "wifi: certificado não é mais gerado de um par novo"
    fi
    grep -q 'fun publicFrom(' "$src/AdbRunner.kt" \
        && ok "wifi: pública derivada da mesma privada lida do disco" || bad "wifi: pública não derivada da privada"
    grep -q 'cert.publicKey == adbKeyPair.public' "$src/AdbRunner.kt" \
        && ok "wifi: certificado antigo é descartado se não casar com a chave" \
        || bad "wifi: certificado antigo aceito mesmo sem casar com a chave"
    #     (d) o NsdManager entrega eventos no Looper: a descoberta não pode rodar em IO
    grep -q 'withContext(Dispatchers.Main)' "$src/AdbRunner.kt" \
        && ok "wifi: descoberta roda na thread principal (Looper do NsdManager)" \
        || bad "wifi: descoberta fora da thread principal (NsdManager fica mudo)"
    grep -q 'MulticastLock' "$src/AdbRunner.kt" \
        && ok "wifi: multicast segurado durante a descoberta" || bad "wifi: multicast não é segurado"
    grep -q 'fun parseMdnsAnswer(' "$src/AdbRunner.kt" \
        && ok "wifi: plano B de mDNS próprio (não depende só do NsdManager)" || bad "wifi: sem plano B de mDNS"
    grep -qi 'achei o serviço de' "$src/AdbRunner.kt" \
        && ok "wifi: erro de descoberta é explicado (não falha em silêncio)" \
        || bad "wifi: erro de descoberta continua silencioso"
    # 10) áudio audível: stream de mídia (não sonificação) e erro no logcat
    grep -q 'USAGE_MEDIA' "$src/SoundPlayer.kt" \
        && ok "som: usa stream de mídia (audível)" || bad "som: ainda usa stream de sonificação"
    if grep -q 'USAGE_ASSISTANCE_SONIFICATION' "$src/SoundPlayer.kt"; then
        bad "som: ainda usa USAGE_ASSISTANCE_SONIFICATION"
    else
        ok "som: sem stream de sonificação"
    fi
    grep -q 'Log.w("SoundPlayer"' "$src/SoundPlayer.kt" \
        && ok "som: falhas vão para o logcat" || bad "som: erros engolidos em silêncio"
    # 10b) soundFor usa as categorias novas (não as antigas)
    grep -q '"Desempenho", "Apps e jogos", "Processos" ->' "$src/PackBridge.kt" \
        && ok "som: soundFor mapeia as categorias novas" || bad "som: soundFor com categorias antigas"
    if grep -q '"RAM / Limpeza"\|"Touch / Free Fire"\|"Congelar apps"' "$src/PackBridge.kt"; then
        bad "som: soundFor ainda cita categoria antiga"
    else
        ok "som: soundFor sem categorias antigas"
    fi
    # 11) MP3 descomprimidos no APK (openFd exige STORED)
    grep -q 'noCompress += "mp3"' "$ROOT/app/build.gradle.kts" \
        && ok "apk: mp3 sem compressão (openFd funciona)" || bad "apk: mp3 sem noCompress"
    # 12) botão de som do cabeçalho tem handler no shim do app
    grep -q 'getElementById("otmSound")' "$app" \
        && ok "som: botão do cabeçalho tem handler" || bad "som: botão do cabeçalho sem handler"
    # 13) novas cores (prata entre elas) e novas fontes na fonte e no painel gerado
    
    for c in prata dourado ciano grafite ambar; do
        grep -q "data-accent=\"$c\"" "$web" && grep -q "data-accent=\"$c\"" "$app" \
            && ok "cor: '$c' na fonte e no app" || bad "cor: '$c' ausente"
    done
    grep -q 'prata:{accent:' "$web" && ok "cor: paleta 'prata' definida" || bad "cor: paleta 'prata' ausente"
    # fontes notaveis (empacotadas, funcionam offline) — antes eram todas iguais
    for f in sistema minecraft pixel monocraft cartaz condensada futurista quadrada serifa manuscrita mono; do
        grep -q "data-font=\"$f\"" "$web" && grep -q "data-font=\"$f\"" "$app" \
            && ok "fonte: '$f' na fonte e no app" || bad "fonte: '$f' ausente"
    done
    # as fontes vêm empacotadas no app (nada de CDN: sem internet a fonte cai)
    for fnt in pressstart2p monocraft anton bebasneue orbitron russoone playfairdisplay jetbrainsmono caveat; do
        [ -f "$ROOT/web/assets/fonts/$fnt.ttf" ] && [ -f "$ROOT/app/src/main/assets/panel/assets/fonts/$fnt.ttf" ] \
            && ok "fonte empacotada: $fnt.ttf no web e no app" || bad "fonte $fnt.ttf ausente"
    done
    grep -q "font-family:'Monocraft'" "$app" && ok "fonte: @font-face do app definido" || bad "fonte: sem @font-face no app"
    # licença das fontes empacotadas (OFL pede que o crédito acompanhe o arquivo)
    [ -f "$ROOT/web/assets/fonts/CREDITS.md" ] && grep -qi 'Open Font License' "$ROOT/web/assets/fonts/CREDITS.md" \
        && ok "fonte: créditos/licença no web" || bad "fonte: sem créditos no web"
    [ -f "$ROOT/app/src/main/assets/panel/assets/fonts/CREDITS.md" ] \
        && grep -qi 'Open Font License' "$ROOT/app/src/main/assets/panel/assets/fonts/CREDITS.md" \
        && ok "fonte: créditos/licença no app" || bad "fonte: sem créditos no app"
    # o painel flutuante carrega o MESMO .ttf empacotado (não só a fonte do sistema)
    grep -q 'createFromAsset(assets, "panel/assets/fonts/' "$src/OverlayService.kt" \
        && ok "overlay: usa a fonte empacotada escolhida" || bad "overlay: fonte empacotada ausente"
    for f in monocraft.ttf pressstart2p.ttf anton.ttf caveat.ttf jetbrainsmono.ttf; do
        grep -q "\"$f\"" "$src/OverlayService.kt" || bad "overlay: sem o mapeamento de $f"
    done
    ok "overlay: mapeia as fontes empacotadas"
    # toda chave do FONTS do painel tem arquivo no overlay (senão o flutuante cai
    # calado na fonte do sistema e diverge do app)
    python3 - "$app" "$src/OverlayService.kt" <<'PY' && ok "overlay: cobre todas as fontes do painel" || bad "overlay: fonte do painel sem arquivo"
import re, sys
html = open(sys.argv[1], encoding='utf-8').read()
kt = open(sys.argv[2], encoding='utf-8').read()
keys = re.findall(r'^\s{2}([a-z]+):', re.search(r'const FONTS = \{(.*?)\n\};', html, re.S).group(1), re.M)
files = re.findall(r'^\s{12}"([a-z]+)" to "([^"]+)"', re.search(r'FONT_FILES = mapOf\((.*?)\n        \)', kt, re.S).group(1), re.M)
mapped = dict(files)
for k in keys:
    if k == 'sistema':
        continue
    if k not in mapped:
        print("sem mapeamento:", k); sys.exit(1)
    if 'assets/fonts/' + mapped[k] not in kt and mapped[k] not in kt:
        print("arquivo ausente:", k, mapped[k]); sys.exit(1)
sys.exit(0)
PY
}

# --- rodapé/creditos ficam embaixo mesmo em tela curta (não no meio da tela) ---
t_footer_sticky() {
    printf '\n  # rodapé: créditos no fim da tela, não no meio\n'
    # O rodapé subia para o meio da tela em páginas/abas curtas porque o body não
    # era coluna flexível: o conteúdo acabava e o rodapé ficava logo abaixo dele,
    # no meio do vazio. Agora body é flex column e o miolo cresce (flex:1).
    local app="$ROOT/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"
    local login="$ROOT/web/login.php"
    local guia="$ROOT/index.html"
    local pguia="$ROOT/public/guia.html"
    for f in "$app" "$web"; do
        n="$(basename "$f")"
        tr '\n' ' ' < "$f" > "$TMP/ft_$n"
        grep -qE 'body\{[^}]*display:flex; *flex-direction:column' "$TMP/ft_$n" \
            && ok "$n: body é coluna flexível" || bad "$n: body não é flex column"
        grep -qE '\.layout\{[^}]*flex:1 0 auto' "$TMP/ft_$n" \
            && ok "$n: o miolo cresce e empurra o rodapé" || bad "$n: miolo não empurra o rodapé"
    done
    tr '\n' ' ' < "$login" > "$TMP/ft_login"
    grep -qE 'body\{[^}]*display:flex; *flex-direction:column' "$TMP/ft_login" \
        && ok "login.php: body é coluna flexível" || bad "login.php: body não é flex column"
    # o cartão centraliza com margin:auto; o que sobra empurra os créditos ao fim
    grep -qE '\.wrap\{[^}]*margin:auto' "$TMP/ft_login" \
        && ok "login.php: cartão centraliza e empurra os créditos" || bad "login.php: .wrap sem margin:auto"
    for f in "$guia" "$pguia"; do
        tr '\n' ' ' < "$f" > "$TMP/ft_g"
        grep -qE 'body\{[^}]*display:flex; *flex-direction:column' "$TMP/ft_g" \
            && ok "$(basename "$f"): body é coluna flexível" || bad "$(basename "$f"): body não é flex column"
        grep -qE 'main\.wrap\{ *flex:1 0 auto' "$TMP/ft_g" \
            && ok "$(basename "$f"): o miolo cresce e empurra o rodapé" \
            || bad "$(basename "$f"): miolo não empurra o rodapé"
    done
}

t_new_features() {
    printf '\n  # novos recursos: refresh fixo, áudio, compactação, foco de jogo, boot, multitouch\n'
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/new.log"
    # refresh fixo: min = peak = hz, valida 60/90/120/144 e rejeita inválidos
    : > "$TMP_CMD_LOG"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/turbo.sh" refresh_fixed 120 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_out"
    assert_contains "$TMP/nf_out" "120" "refresh_fixed aplica a taxa escolhida"
    grep -q '120.0' "$TMP_STORE/system.peak_refresh_rate" \
        && ok "refresh_fixed trava peak=120" || bad "refresh_fixed sem peak"
    grep -q '120.0' "$TMP_STORE/system.min_refresh_rate" \
        && ok "refresh_fixed trava min=120" || bad "refresh_fixed sem min"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/turbo.sh" refresh_fixed 75 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_bad"
    assert_contains "$TMP/nf_bad" "uso:" "refresh_fixed recusa taxa inválida"
    # áudio de baixa latência e compactação de memória exigiam root: saíram do pack
    grep -q 'audio' "$ROOT/scripts/turbo.sh" && grep -q '^audio()' "$ROOT/scripts/turbo.sh" \
        && bad "turbo ainda tem o módulo audio (root)" || ok "turbo sem o módulo audio (root)"
    grep -q 'mem_compact' "$ROOT/scripts/turbo.sh" \
        && bad "turbo ainda tem mem_compact (root)" || ok "turbo sem mem_compact (root)"
    # foco de jogo (DND extremo)
    : > "$TMP_CMD_LOG"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_focus 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_focus"
    assert_contains "$TMP/nf_focus" "foco de jogo" "game_focus ativa o foco de jogo"
    grep -q 'notification set_dnd on' "$TMP_CMD_LOG" && ok "foco: DND ligado" || bad "foco: sem DND"
    # multitouch
    : > "$TMP_CMD_LOG"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" touch_multi 150 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_multi"
    assert_contains "$TMP/nf_multi" "150ms" "touch_multi aplica a janela"
    grep -q '150' "$TMP_STORE/system.multi_press_timeout" \
        && ok "touch_multi grava multi_press_timeout" || bad "touch_multi sem multi_press_timeout"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" touch_multi 9999 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_multi2"
    assert_contains "$TMP/nf_multi2" "800ms" "touch_multi limita ao máximo 800ms"
    # persistência no boot exigia root (service.d/init.d): saiu do pack
    grep -q 'boot_install\|boot_add' "$ROOT/scripts/common.sh" \
        && bad "common ainda tem helper de boot (root)" || ok "common sem helper de boot (root)"
    grep -q 'OTM_BOOT_DIR\|service.d\|init.d' "$ROOT/scripts/common.sh" \
        && bad "common ainda referencia service.d/init.d" || ok "common sem service.d/init.d"
    # as ações sem root estão registradas no painel
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["turbo.refresh_fixed","game_focus","touch.multi"] as $id)
               echo isset($a[$id]) ? "" : "FALTA:$id ";' > "$TMP/nf_reg" 2>&1
    test ! -s "$TMP/nf_reg" && ok "novas ações no registro do painel" || bad "registro: $(cat "$TMP/nf_reg")"
    grep -q '"turbo.refresh_fixed"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o refresh fixo" || bad "app: actions.json sem refresh fixo"
}

t_panel_state() {
    printf '\n  # estado REAL do aparelho (panel-state.sh) para o painel\n'
    rm -rf "$HOME/.packotm"
    # o aparelho "tem" estes valores reais
    printf 'skiagl' > "$TMP_STORE/prop.debug.hwui.renderer"
    printf '110'    > "$TMP_STORE/system.touch_responsiveness"
    printf '350'    > "$TMP_STORE/system.long_press_timeout"
    printf '0'      > "$TMP_STORE/system.pointer_speed"
    printf '4'      > "$TMP_STORE/system.touch_slop"
    printf '90.0'   > "$TMP_STORE/system.min_refresh_rate"
    printf '90.0'   > "$TMP_STORE/system.peak_refresh_rate"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/st_out"
    grep -q '"renderer":"skiagl"' "$TMP/st_out" && ok "state: lê o renderizador em uso" || bad "state: sem renderer"
    grep -q '"touch_responsiveness":"110"' "$TMP/st_out" && ok "state: lê responsiveness real" || bad "state: sem responsiveness"
    grep -q '"long_press_timeout":"350"' "$TMP/st_out" && ok "state: lê long press real" || bad "state: sem long press"
    grep -q '"pointer_speed":"0"' "$TMP/st_out" && ok "state: lê pointer speed real" || bad "state: sem pointer speed"
    grep -q '"touch_slop":"4"' "$TMP/st_out" && ok "state: lê touch slop real" || bad "state: sem touch slop"
    grep -q '"refresh_peak":"90.0"' "$TMP/st_out" && ok "state: lê o refresh atual" || bad "state: sem refresh"
    # sem prop setada, quem decide é o SISTEMA: no Android 10+ (API>=29) o motor
    # OpenGL foi removido e o padrão é skiagl/skiavk — nunca "opengl" (fonte: AOSP)
    rm -f "$TMP_STORE/prop.debug.hwui.renderer"
    printf '34' > "$TMP_STORE/prop.ro.build.version.sdk"
    rm -f "$TMP_STORE/prop.ro.hwui.use_vulkan"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/st_out2"
    grep -q '"renderer":"skiagl"' "$TMP/st_out2" && ok "state: API 34 sem prop assume SkiaGL (real)" || bad "state: default renderer errado"
    printf 'true' > "$TMP_STORE/prop.ro.hwui.use_vulkan"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/st_out3"
    grep -q '"renderer":"skiavk"' "$TMP/st_out3" && ok "state: com ro.hwui.use_vulkan assume Skia Vulkan" || bad "state: vulkan default errado"
    # em Android antigo (API<29) o OpenGL ainda existia e era o padrão
    printf '28' > "$TMP_STORE/prop.ro.build.version.sdk"
    rm -f "$TMP_STORE/prop.ro.hwui.use_vulkan"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/st_out4"
    grep -q '"renderer":"opengl"' "$TMP/st_out4" && ok "state: API 28 sem prop assume OpenGL (antigo)" || bad "state: default antigo errado"
    # o JSON é válido
    php -r '$j=json_decode(file_get_contents($argv[1]),true);
             echo is_array($j) && isset($j["renderer"]) ? "OK" : "RUIM";' "$TMP/st_out" > "$TMP/st_json" 2>&1
    assert_contains "$TMP/st_json" "OK" "state: JSON válido"
    # lib.php expõe o leitor e o script está na whitelist
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("panel-state.sh", otm_allowed_scripts(), true) ? "whitelist " : "";
             echo function_exists("otm_state_read") ? "reader" : "";' > "$TMP/st_lib" 2>&1
    assert_contains "$TMP/st_lib" "whitelist reader" "lib: leitor de estado na whitelist"
    grep -q "case 'state'" "$ROOT/web/api.php" && ok "api.php: endpoint de estado" || bad "api.php: sem endpoint de estado"
    grep -q '"state" -> stateImpl()' "$ROOT/app/src/main/java/com/otm/pack/PackBridge.kt" \
        && ok "app: ponte responde ao estado real" || bad "app: ponte sem estado"
    grep -q 'fun stateImpl' "$ROOT/app/src/main/java/com/otm/pack/PackBridge.kt" \
        && ok "app: stateImpl presente" || bad "app: sem stateImpl"
    # o painel marca a opção em uso e mostra os valores reais
    grep -q 'applyState' "$ROOT/web/index.php" && ok "painel: aplica o estado real (applyState)" || bad "painel: sem applyState"
    grep -q 'Em uso' "$ROOT/web/index.php" && ok "painel: marca a opção 'Em uso'" || bad "painel: sem marcação de uso"
    grep -q 'functional\|card-choice' "$ROOT/web/index.php" && ok "painel: cartões de escolha presentes" || bad "painel: sem cartões de escolha"
    # catálogo do app carrega os metadados de escolha
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             echo !empty($a["gpu.skiagl"]["state_value"]) ? "r " : "";
             echo !empty($a["touch.headshot"]["state_match"]) ? "t " : "";
             foreach ($a["touch.custom"]["params"] as $p) if (($p["name"]??"")==="tr" && !empty($p["state"])) echo "s";' \
        > "$TMP/st_meta" 2>&1
    assert_contains "$TMP/st_meta" "r t s" "lib: metadados de estado por opção/parâmetro"
    grep -q '"state_value": "skiagl"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem state_value" || bad "app: actions.json sem state_value"
    grep -q '"state_match": "touch:110,350,0,4"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem state_match do toque" || bad "app: actions.json sem state_match"
}

t_panel_stats() {
    printf '\n  # consumo REAL do aparelho (panel-stats.sh): CPU medida, não inventada\n'
    # CPU: o uso vem de /proc/stat (busy/total), NÃO de loadavg/ncores — que não é
    # porcentagem e dava número absurdo (ex.: carga 27.63 com 8 núcleos = "345%").
    grep -q 'cpu_uso_pct' "$ROOT/scripts/panel-stats.sh" \
        && ok "stats: mede o uso da CPU (/proc/stat)" || bad "stats: sem cpu_uso_pct"
    grep -q 'proc/stat' "$ROOT/scripts/panel-stats.sh" \
        && ok "stats: lê /proc/stat para a CPU" || bad "stats: não lê /proc/stat"
    grep -q 'load1 / nc\|load / nc' "$ROOT/web/index.php" \
        && bad "painel: ainda calcula CPU% a partir da carga média" \
        || ok "painel: CPU% não vem mais da carga média"
    grep -q 'load / nc\|load1 / nc' "$ROOT/app/src/main/assets/panel/index.html" \
        && bad "app: ainda calcula CPU% a partir da carga média" \
        || ok "app: CPU% não vem mais da carga média"
    # a carga média continua exibida, mas como carga (não como %)
    grep -q '"carga " + load.toFixed(2)' "$ROOT/web/index.php" \
        && ok "painel: mostra a carga média como carga" || bad "painel: carga média sumiu"
    # bateria: status é texto, não o código cru do dumpsys (1..5)
    grep -q 'bat_status="Descarregando"' "$ROOT/scripts/panel-stats.sh" \
        && ok "stats: traduz o status da bateria para texto" || bad "stats: status da bateria cru"
    # refresh: emite a taxa travada, senão o rodapé "taxa travada (fixa)" é código morto
    grep -q '"refresh_peak"' "$ROOT/scripts/panel-stats.sh" \
        && ok "stats: emite a taxa travada (refresh_peak)" || bad "stats: sem refresh_peak"
    # JSON válido com os campos novos
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/panel-stats.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/ps_out"
    php -r '$j=json_decode(file_get_contents($argv[1]),true);
             echo is_array($j) && array_key_exists("cpu_uso_pct",$j) && array_key_exists("refresh_peak",$j)
                  ? "OK" : "RUIM";' "$TMP/ps_out" > "$TMP/ps_json" 2>&1
    assert_contains "$TMP/ps_json" "OK" "stats: JSON válido com cpu_uso_pct e refresh_peak"
    # o valor medido é porcentagem plausível (0..100), nunca algo como 345
    cpu=$(php -r '$j=json_decode(file_get_contents($argv[1]),true);
             $v=$j["cpu_uso_pct"]??"";
             echo ($v!=="" && (int)$v>=0 && (int)$v<=100) ? "OK" : "FORA";' "$TMP/ps_out" 2>&1)
    [ "$cpu" = "OK" ] && ok "stats: uso da CPU entre 0 e 100%" || bad "stats: uso da CPU fora de 0..100 ($cpu)"
    # o painel (app e web) e o espelho estão alinhados
    grep -q 'cpu_uso_pct' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "app: painel lê cpu_uso_pct" || bad "app: painel sem cpu_uso_pct"
    grep -q 'cpu_uso_pct' "$ROOT/web/index.php" \
        && ok "web: painel lê cpu_uso_pct" || bad "web: painel sem cpu_uso_pct"
    # "ramf" está em dois elementos; querySelector só pega o 1º e o rodapé do card
    # ficava travado em "—". Tem de preencher todos.
    grep -q "querySelectorAll('\[data-stat=\"ramf\"\]')" "$ROOT/web/index.php" \
        && ok "web: preenche os dois ramf (chip e rodapé)" || bad "web: rodapé da RAM travado em —"
    grep -q "querySelectorAll('\[data-stat=\"ramf\"\]')" "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "app: preenche os dois ramf (chip e rodapé)" || bad "app: rodapé da RAM travado em —"
    # nenhum outro data-stat duplicado no HTML (seletor pegaria só o primeiro)
    for f in "$ROOT/web/index.php" "$ROOT/app/src/main/assets/panel/index.html"; do
        php -r '$h=file_get_contents($argv[1]);
                 preg_match_all("/data-stat=\"([a-z]+)\"/", $h, $m, PREG_OFFSET_CAPTURE);
                 $seen=[];
                 foreach ($m[1] as $i=>$kv){ $k=$kv[0]; $line=substr($h, strrpos(substr($h,0,$kv[1]),"\n")+1);
                   if (strpos($line,"querySelector")!==false) continue;
                   if (isset($seen[$k])) echo "DUP:$k "; else $seen[$k]=1; }
                 echo "FIM";' "$f" > "$TMP/dup_$(basename "$f")" 2>&1
        grep -q 'FIM$' "$TMP/dup_$(basename "$f")" && ! grep -q 'DUP:' "$TMP/dup_$(basename "$f")" \
            && ok "sem data-stat duplicado em $(basename "$f")" \
            || bad "data-stat duplicado em $(basename "$f"): $(cat "$TMP/dup_$(basename "$f")")"
    done
    # taxa travada só quando peak == min (o sistema deixa peak=120/min=60 no adaptativo)
    grep -q 'refresh_peak" != "$refresh_min' "$ROOT/scripts/panel-stats.sh" \
        && ok "stats: só marca travada quando peak == min" || bad "stats: marcaria adaptativo como travado"
    st2=$(mktemp -d); b2=$(mktemp -d)
    printf '#!/bin/sh\ncase "$1" in\n get) cat "$TMP_STORE/$2.$3" 2>/dev/null ;;\nesac\nexit 0\n' > "$b2/settings"
    chmod +x "$b2/settings"
    printf '60.0' > "$st2/system.min_refresh_rate"; printf '120.0' > "$st2/system.peak_refresh_rate"
    PATH="$b2:$PATH" TMP_STORE="$st2" OTM_NO_COLOR=1 sh "$ROOT/scripts/panel-stats.sh" > "$TMP/rp_auto" 2>&1
    grep -q '"refresh_peak":""' "$TMP/rp_auto" \
        && ok "stats: adaptativo (60/120) não vira 'travada'" || bad "stats: adaptativo marcado como travado"
    printf '90.0' > "$st2/system.min_refresh_rate"; printf '90.0' > "$st2/system.peak_refresh_rate"
    PATH="$b2:$PATH" TMP_STORE="$st2" OTM_NO_COLOR=1 sh "$ROOT/scripts/panel-stats.sh" > "$TMP/rp_lock" 2>&1
    grep -q '"refresh_peak":"90.0"' "$TMP/rp_lock" \
        && ok "stats: travado (90/90) reporta a taxa" || bad "stats: travado não reportado"
    rm -rf "$st2" "$b2"
}

t_fps_real() {
    printf '\n  # FPS REAL do jogo: frames do SurfaceFlinger, não a taxa de tela\n'
    # o método é o `--latency` do compositor (2ª coluna = horário REAL de
    # apresentação de cada frame). É liberado para o uid 2000 (shell/Shizuku).
    grep -q 'SurfaceFlinger --latency' "$ROOT/scripts/common.sh" \
        && ok "fps: mede pelo SurfaceFlinger --latency" || bad "fps: não usa o --latency"
    grep -q 'SurfaceFlinger --list' "$ROOT/scripts/common.sh" \
        && ok "fps: descobre a camada do app pelo --list" || bad "fps: não lista as camadas"
    # o FPS é derivado dos carimbos de apresentação, nunca da taxa de tela
    grep -q 'refresh_hz' "$ROOT/scripts/fps.sh" \
        && bad "fps: mistura taxa de tela com FPS" || ok "fps: não confunde Hz com FPS"
    # script existe, está na whitelist e é só leitura
    [ -f "$ROOT/scripts/fps.sh" ] && ok "fps.sh existe" || bad "fps.sh ausente"
    grep -q "'fps.sh'" "$ROOT/web/lib.php" \
        && ok "fps.sh está na whitelist do painel" || bad "fps.sh fora da whitelist"
    grep -qE '^(settings put|bkp_set|sh_run)' "$ROOT/scripts/fps.sh" \
        && bad "fps.sh escreve no sistema (devia ser só leitura)" \
        || ok "fps.sh é só leitura"

    # --- camada: prefere a SurfaceView do app em 1º plano --------------------
    printf 'com.dts.freefireth/com.dts.freefireth.FFMainActivity#0\n' > "$TMP_STORE/sf_list"
    printf 'SurfaceView[com.dts.freefireth/FF](BLAST)#0\n' >> "$TMP_STORE/sf_list"
    printf 'Background for SurfaceView[com.dts.freefireth](BLAST)#0\n' >> "$TMP_STORE/sf_list"
    printf 'com.dts.freefireth/.FFMainActivity\n' > "$TMP_STORE/fg"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/fps.sh" layer > "$TMP/fps_layer" 2>&1
    grep -q 'SurfaceView\[com.dts.freefireth/FF\](BLAST)#0' "$TMP/fps_layer" \
        && ok "fps: escolhe a SurfaceView do jogo (não a camada do app)" \
        || bad "fps: escolheu a camada errada"

    # --- FPS a 60: 60 frames a cada 16,66 ms ---------------------------------
    # 1ª linha é o período de vsync (não é frame); as demais são os carimbos.
    { echo "16666666"
      awk 'BEGIN{ t=1000000000; for(i=0;i<60;i++){ printf "%d\t%d\t%d\n", t, t, t; t+=16666666 } }'
    } > "$TMP_STORE/sf_latency"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/fps.sh" now > "$TMP/fps60" 2>&1
    grep -q '#OTM-FPS fps=60 ' "$TMP/fps60" && ok "fps: 60 frames a 16,66 ms = 60 fps" \
        || bad "fps: errou o cálculo a 60 fps ($(grep -o 'fps=[0-9]*' "$TMP/fps60"))"
    grep -q 'frames=60' "$TMP/fps60" && ok "fps: conta os 60 frames" || bad "fps: contagem de frames errada"

    # --- FPS a 120 com slots vazios do buffer misturados ---------------------
    # O buffer circular de 128 posições vem com slots zerados/INT64_MAX. Eles
    # NÃO são frames e não podem entrar na conta (senão o FPS despenca).
    { echo "8333333"
      echo "0	0	0"
      echo "0	9223372036854775807	0"
      awk 'BEGIN{ t=2000000000; for(i=0;i<40;i++){ printf "%d\t%d\t%d\n", t, t, t; t+=8333333 } }'
      echo "0	0	0"
    } > "$TMP_STORE/sf_latency"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/fps.sh" now > "$TMP/fps120" 2>&1
    grep -q '#OTM-FPS fps=120 ' "$TMP/fps120" \
        && ok "fps: 120 fps com slots vazios ignorados" \
        || bad "fps: slots vazios do buffer corromperam a conta ($(grep -o 'fps=[0-9]*' "$TMP/fps120"))"
    grep -q 'frames=40' "$TMP/fps120" && ok "fps: só os frames reais entram na conta" \
        || bad "fps: contou slots vazios como frame"

    # --- sem camada / sem frames: devolve vazio, NÃO inventa ------------------
    : > "$TMP_STORE/sf_list"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/fps.sh" now > "$TMP/fpsnone" 2>&1
    grep -q 'fps=' "$TMP/fpsnone" && bad "fps: inventou FPS sem camada" \
        || ok "fps: sem camada não inventa número (mostra o motivo)"
    # camada existe, mas o jogo está parado (só a linha de vsync)
    printf 'SurfaceView[com.dts.freefireth/FF](BLAST)#0\n' > "$TMP_STORE/sf_list"
    echo "16666666" > "$TMP_STORE/sf_latency"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/fps.sh" now > "$TMP/fpsidle" 2>&1
    grep -q 'fps=' "$TMP/fpsidle" && bad "fps: inventou FPS com o jogo parado" \
        || ok "fps: jogo parado (sem frames) não vira número"

    # --- o painel publica o FPS real no JSON ---------------------------------
    grep -q '"fps"' "$ROOT/scripts/panel-stats.sh" \
        && ok "stats: publica o campo fps" || bad "stats: sem campo fps"
    grep -q '"fps_layer"' "$ROOT/scripts/panel-stats.sh" \
        && ok "stats: publica a camada medida (fps_layer)" || bad "stats: sem fps_layer"
    # o FPS do painel vem do otm_fps_measure (mesma conta do fps.sh), não do Hz
    grep -q 'otm_fps_measure' "$ROOT/scripts/panel-stats.sh" \
        && ok "stats: usa a mesma medição de FPS do pack" || bad "stats: medição de FPS própria"
    # com o jogo em 1º plano, o JSON traz o FPS real
    { echo "16666666"
      awk 'BEGIN{ t=1000000000; for(i=0;i<60;i++){ printf "%d\t%d\t%d\n", t, t, t; t+=16666666 } }'
    } > "$TMP_STORE/sf_latency"
    printf 'SurfaceView[com.dts.freefireth/FF](BLAST)#0\n' > "$TMP_STORE/sf_list"
    printf 'com.dts.freefireth/.FFMainActivity\n' > "$TMP_STORE/fg"
    rm -rf "$HOME/.packotm/game"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/panel-stats.sh" > "$TMP/ps_fps" 2>&1
    grep -q '"fps":"60"' "$TMP/ps_fps" && ok "stats: FPS real no JSON (60)" \
        || bad "stats: FPS ausente/errado no JSON ($(grep -o '"fps":"[^"]*"' "$TMP/ps_fps"))"

    # --- painéis (app e web) mostram o FPS -----------------------------------
    for f in "$ROOT/web/index.php" "$ROOT/app/src/main/assets/panel/index.html"; do
        n=$(basename "$f")
        grep -q 'data-stat="fps"' "$f" && ok "$n: tem o card de FPS" || bad "$n: sem card de FPS"
        grep -q '"fps","stor_total_mb"\|refresh_hz","fps"' "$f" \
            && ok "$n: pede o campo fps no poll" || bad "$n: não pede o fps"
    done
    # o card explica que é FPS do jogo, não a taxa de tela
    grep -q 'FPS do jogo' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "app: card se chama 'FPS do jogo'" || bad "app: card de FPS sem rótulo claro"
    rm -f "$TMP_STORE/sf_list" "$TMP_STORE/sf_latency"
}

t_game_keepalive() {
    printf '\n  # modo gamer: sem restricao de bateria, no maximo 4 processos, anti-relog\n'
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/gk_cmd.log"; : > "$TMP_CMD_LOG"
    export TMP_AM_LOG="$TMP/gk_am.log"; : > "$TMP_AM_LOG"
    # escolhe um jogo que NAO e Free Fire e abre pelo modo gamer
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_open com.mojang.minecraftpe \
        > "$TMP/gk_open" 2>&1
    # 1) sem restricao de bateria: fora do Doze + livre em 2o plano
    grep -q '^deviceidle whitelist +com.mojang.minecraftpe$' "$TMP_CMD_LOG" \
        && ok "game_open tira o jogo do Doze (bateria sem restricao)" || bad "game_open nao isentou do Doze"
    grep -q '^appops set com.mojang.minecraftpe RUN_ANY_IN_BACKGROUND allow$' "$TMP_CMD_LOG" \
        && ok "game_open libera o jogo sempre em 2o plano" || bad "sem 2o plano do jogo"
    grep -q '^appops set com.mojang.minecraftpe WAKE_LOCK allow$' "$TMP_CMD_LOG" \
        && ok "game_open libera wake lock do jogo" || bad "sem wake lock do jogo"
    # 2) no maximo 4 apps em 2o plano (o "no maximo 4 processos")
    assert_contains "$TMP_STORE/global.activity_manager_constants" "max_cached_processes=4" \
        "game_open limita a 4 apps em 2o plano"
    # 3) balde ativo + fora do congelador
    grep -q 'set-standby-bucket com.mojang.minecraftpe active' "$TMP_AM_LOG" \
        && ok "game_open poe o jogo no balde ativo" || bad "sem balde ativo"
    assert_contains "$TMP_STORE/global.cached_apps_freezer" "disabled" "game_open tira do congelador"
    # 4) anti-relog completo (keep-alive) foi acionado
    grep -q 'com.mojang.minecraftpe' "$HOME/.packotm/keepalive/apps" \
        && ok "game_open registra o jogo no anti-relog" || bad "jogo fora do anti-relog"
    # 5) continua abrindo o jogo escolhido, em performance
    grep -q '^game set --mode performance com.mojang.minecraftpe$' "$TMP_CMD_LOG" \
        && ok "game_open aplica Game Mode performance" || bad "sem Game Mode"
    grep -q 'com.mojang.minecraftpe' "$TMP_AM_LOG" \
        && ok "game_open abre o jogo escolhido" || bad "nao abriu o jogo"
    # 6) mescla: nao apaga as outras constantes do aparelho
    printf 'max_phantom_processes=1024' > "$TMP_STORE/global.activity_manager_constants"
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_keepalive com.mojang.minecraftpe \
        > /dev/null 2>&1
    c="$(cat "$TMP_STORE/global.activity_manager_constants")"
    case "$c" in *max_cached_processes=4*) ok "am_set define o limite de 4";; *) bad "am_set sem limite ($c)";; esac
    case "$c" in *max_phantom_processes=1024*) ok "am_set preserva as constantes ja existentes";; *) bad "am_set apagou constante ($c)";; esac
    # 7) pacote invalido e recusado
    : > "$TMP_CMD_LOG"; : > "$TMP_AM_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_keepalive 'foo;rm -rf /' > /dev/null 2>&1
    [ -s "$TMP_CMD_LOG" ] || [ -s "$TMP_AM_LOG" ] \
        && bad "game_keepalive executou pacote invalido" || ok "game_keepalive recusa pacote invalido"
    # 8) grupo registrado + acao no painel
    grep -q ' game_keepalive ' "$ROOT/scripts/adb-tweaks.sh" \
        && ok "game_keepalive registrado nos grupos" || bad "game_keepalive fora dos grupos"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_action("game.keepalive");
             echo $a ? ($a["argv"][1] . " " . ($a["params"][0]["type"] ?? "")) : "AUSENTE";' \
        > "$TMP/gkl" 2>&1
    assert_contains "$TMP/gkl" "game_keepalive pkg" "lib: acao game.keepalive com escolha de jogo"
    grep -q '"game.keepalive"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: catalogo tem game.keepalive" || bad "app: catalogo sem game.keepalive"
    rm -rf "$HOME/.packotm"
}

t_game_open() {
    printf '\n  # modo gamer: o usuário escolhe QUAL jogo abre (não só Free Fire)\n'
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/game.log"; : > "$TMP_CMD_LOG"
    export TMP_AM_LOG="$TMP/game.am"; : > "$TMP_AM_LOG"
    # o grupo existe e está registrado
    grep -q ' game_open ' "$ROOT/scripts/adb-tweaks.sh" \
        && ok "game_open registrado nos grupos" || bad "game_open fora dos grupos"
    # escolher um jogo que NÃO é Free Fire: aplica performance e abre o escolhido
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_open com.mojang.minecraftpe \
        > "$TMP/game_out" 2>&1
    grep -q '^game set --mode performance com.mojang.minecraftpe$' "$TMP_CMD_LOG" \
        && ok "aplica Game Mode no jogo escolhido" || bad "não aplicou no jogo escolhido"
    grep -q 'com.mojang.minecraftpe' "$TMP_AM_LOG" \
        && ok "abre o jogo escolhido (Minecraft)" || bad "não abriu o jogo escolhido"
    assert_eq "com.mojang.minecraftpe" "$(cat "$HOME/.packotm/game/pkg" 2>/dev/null)" \
        "guarda a escolha para as próximas vezes"
    # sem argumento, reusa o jogo salvo (não volta para o Free Fire)
    : > "$TMP_CMD_LOG"; : > "$TMP_AM_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_open > /dev/null 2>&1
    grep -q '^game set --mode performance com.mojang.minecraftpe$' "$TMP_CMD_LOG" \
        && ok "sem argumento usa o jogo salvo" || bad "sem argumento não usou o salvo"
    grep -q 'com.mojang.minecraftpe' "$TMP_AM_LOG" \
        && ok "sem argumento abre o jogo salvo" || bad "sem argumento abriu outro jogo"
    # pacote inválido é recusado (nada de injetar comando no am/cmd)
    : > "$TMP_CMD_LOG"; : > "$TMP_AM_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_open 'foo;rm -rf /' > /dev/null 2>&1
    [ -s "$TMP_CMD_LOG" ] || [ -s "$TMP_AM_LOG" ] \
        && bad "pacote inválido foi executado" || ok "pacote inválido é recusado"
    # o Game Mode geral também cobre o jogo escolhido
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game > /dev/null 2>&1
    grep -q '^game set --mode performance com.mojang.minecraftpe$' "$TMP_CMD_LOG" \
        && ok "Game Mode geral inclui o jogo escolhido" || bad "Game Mode geral ignora o escolhido"
    # o painel oferece a escolha: ação com parâmetro pkg + card na Home
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_action("game_open");
             echo $a ? ($a["argv"][1] . " " . ($a["params"][0]["type"] ?? "") . " "
                        . (($a["params"][0]["optional"] ?? false) ? "opcional" : "obrigatorio")) : "AUSENTE";' \
        > "$TMP/game_lib" 2>&1
    assert_contains "$TMP/game_lib" "game_open pkg opcional" "lib: ação game_open com escolha de jogo"
    for f in "$ROOT/web/index.php" "$ROOT/app/src/main/assets/panel/index.html"; do
        grep -q "runGameHome" "$f" && grep -q 'home-game-pkg' "$f" \
            && ok "$(basename "$f"): Home tem seletor de jogo" \
            || bad "$(basename "$f"): Home sem seletor de jogo"
        grep -q "runActionById('ff_open')" "$f" \
            && bad "$(basename "$f"): Home ainda abre Free Fire fixo" \
            || ok "$(basename "$f"): Home não fixa o Free Fire"
    done
    grep -q '"game_open"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: catálogo tem game_open" || bad "app: catálogo sem game_open"
}

t_pack_stamp() {
    printf '\n  # selo dos scripts: repõe quando o CONTEÚDO muda (mesmo versionName)\n'
    local src="$ROOT/app/src/main/java/com/otm/pack/PackAssets.kt"
    # a causa do "grupo desconhecido: game_open": o selo era só o versionName, então
    # um APK republicado com a MESMA versão não recopiava os scripts no aparelho.
    grep -q 'stampFor' "$src" && ok "selo calculado do conteúdo (stampFor)" \
        || bad "selo ainda é só o versionName (script velho no aparelho)"
    grep -q 'MessageDigest' "$src" && ok "selo usa hash dos assets" || bad "selo sem hash"
    grep -q "stamp.readText() == want" "$src" \
        && ok "recopia quando o hash muda" || bad "não compara o hash"
    # o sync do build precisa achar a fonte da verdade (antes apontava p/ ../scripts)
    local g="$ROOT/app/build.gradle.kts"
    grep -q 'rootProject.file("../scripts")' "$g" \
        && bad "sync ainda aponta p/ ../scripts (inexistente)" \
        || ok "sync usa caminho válido para scripts"
    grep -q 'checkPackSource' "$g" \
        && ok "build falha alto se a fonte sumir" || bad "build pularia o sync em silêncio"
}

t_perm_game() {
    printf '\n  # permissões: o jogo escolhido, não só o Free Fire\n'
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/perm2.log"; : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_open com.mojang.minecraftpe \
        > /dev/null 2>&1
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" perm_game > /dev/null 2>&1
    grep -q '^appops set com.mojang.minecraftpe RUN_IN_BACKGROUND allow$' "$TMP_CMD_LOG" \
        && ok "perm_game libera o jogo escolhido" || bad "perm_game não liberou o jogo escolhido"
    grep -q '^deviceidle whitelist +com.mojang.minecraftpe$' "$TMP_CMD_LOG" \
        && ok "perm_game isenta o jogo escolhido do Doze" || bad "sem isenção do Doze"
    # sem escolha salva, cai no Free Fire (compatível com antes)
    rm -rf "$HOME/.packotm"; : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" perm_game > /dev/null 2>&1
    grep -q '^deviceidle whitelist +com.dts.freefireth$' "$TMP_CMD_LOG" \
        && ok "perm_game sem escolha usa o Free Fire" || bad "perm_game sem escolha falhou"
    # perm_all cobre o jogo escolhido também
    rm -rf "$HOME/.packotm"; : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" game_open com.mojang.minecraftpe \
        > /dev/null 2>&1
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" perm_all > /dev/null 2>&1
    grep -q '^deviceidle whitelist +com.mojang.minecraftpe$' "$TMP_CMD_LOG" \
        && ok "perm_all inclui o jogo escolhido" || bad "perm_all ignora o jogo escolhido"
    # painel: a ação existe e a engrenagem tem o botão
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_action("perm.game");
             echo $a ? ($a["argv"][1] . " " . ($a["params"][0]["type"] ?? "")) : "AUSENTE";' \
        > "$TMP/permg" 2>&1
    assert_contains "$TMP/permg" "perm_game pkg" "lib: ação perm.game com escolha de jogo"
    # a engrenagem tem SÓ o botão do pack; os outros (FF, meu jogo, bateria,
    # uso) saíram das configs a pedido — a ação em si continua no catálogo.
    for b in setPermFF setPermGame setPermBattery setPermUsage; do
        if grep -q "id=\"$b\"" "$ROOT/app/src/main/assets/panel/index.html" \
           || grep -q "id=\"$b\"" "$ROOT/web/index.php"; then
            bad "engrenagem ainda tem o botão $b"
        fi
    done
    ok "engrenagem só com 'Conceder permissões ao pack'"
    grep -q '"perm.game"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: catálogo tem perm.game" || bad "app: catálogo sem perm.game"
    rm -rf "$HOME/.packotm"
}

t_perm_script() {
    printf '\n  # permissões/segundo plano: Doze, appops e bateria (sem root)\n'
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/perm.log"; : > "$TMP_CMD_LOG"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" perm_all 2>&1)
    printf '%s\n' "$out" > "$TMP/permout"
    assert_contains "$TMP/permout" 'Permissões do app do pack' "perm_all libera o app do pack"
    assert_contains "$TMP/permout" 'Permissões do Free Fire' "perm_all libera o Free Fire"
    assert_contains "$TMP/permout" 'sem economia agressiva' "perm_all desliga a economia de bateria"
    grep -q '^deviceidle whitelist +com.otm.pack$' "$TMP_CMD_LOG" \
        && ok "isenta o app do pack do Doze" || bad "não isentou o app do Doze"
    grep -q '^deviceidle whitelist +com.dts.freefireth$' "$TMP_CMD_LOG" \
        && ok "isenta o Free Fire do Doze" || bad "não isentou o Free Fire"
    grep -q '^appops set com.otm.pack RUN_IN_BACKGROUND allow$' "$TMP_CMD_LOG" \
        && ok "libera o app para rodar em segundo plano" || bad "não liberou segundo plano"
    grep -q '^appops set com.dts.freefireth RUN_ANY_IN_BACKGROUND allow$' "$TMP_CMD_LOG" \
        && ok "libera o Free Fire sempre em segundo plano" || bad "não liberou 2º plano do FF"
    # reversível: guarda os comandos de desfazer no backup
    grep -q 'deviceidle whitelist -com.otm.pack' "$HOME/.packotm/undo/adb-tweaks.sh" \
        && ok "reversão do Doze guardada (Reverter TUDO)" || bad "sem reversão do Doze"
    grep -q 'appops set com.otm.pack RUN_IN_BACKGROUND default' "$HOME/.packotm/undo/adb-tweaks.sh" \
        && ok "reversão do appops guardada" || bad "sem reversão do appops"
    # bateria sem economia: aplica de verdade e é reversível
    OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" perm_battery >/dev/null 2>&1
    assert_eq "0" "$(cat "$TMP_STORE/global.low_power" 2>/dev/null)" "economia de bateria desligada"
    assert_eq "0" "$(cat "$TMP_STORE/global.app_standby_enabled" 2>/dev/null)" "App Standby desligado"
    grep -qE 'settings (put|delete) global low_power' "$HOME/.packotm/undo/adb-tweaks.sh" \
        && ok "reversão da bateria guardada" || bad "sem reversão da bateria"
    rm -rf "$HOME/.packotm"
}

t_perm_actions() {
    printf '\n  # painel: ações de permissão registradas e sem root\n'
    if command -v php >/dev/null 2>&1; then
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $ids=["perm.app","perm.ff","perm.battery","perm.all"];
                 $miss=[]; foreach($ids as $i){ if(!otm_action($i)) $miss[]=$i; }
                 echo $miss ? ("FALTA:".implode(",",$miss)) : "OK";' > "$TMP/perma" 2>&1
        assert_contains "$TMP/perma" "OK" "ações de permissão existem no registro"
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $a=otm_action("perm.app");
                 echo ($a && ($a["risk"] ?? "safe")==="safe") ? "SAFE" : "RISCO";' > "$TMP/permb" 2>&1
        assert_contains "$TMP/permb" "SAFE" "permissão do app é ação segura"
    else
        printf '  [skip] php ausente: pulei testes das ações de permissão\n'
    fi
    grep -q 'perm_all\|perm_app' "$ROOT/scripts/adb-tweaks.sh" \
        && ok "grupos de permissão existem no adb-tweaks" || bad "sem grupos de permissão"
    grep -q '"perm.app"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem as permissões" || bad "app: actions.json sem permissões"
    grep -q 'Permissões e segundo plano' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "app: engrenagem mostra as permissões exigidas" || bad "app: sem lista de permissões"
    grep -q 'id="setPermApp"' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "app: botões de permissão existem" || bad "app: sem botões de permissão"
}

t_personalization() {
    printf '\n  # personalização: fonte, tema, cor, DPI e restaurar padrão\n'
    local app="$ROOT/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"
    grep -q 'id="setFont"' "$app" && ok "app: controle de fonte existe" || bad "app: sem fonte"
    grep -q 'id="setScale"' "$app" && ok "app: controle de DPI existe" || bad "app: sem DPI"
    grep -q 'id="gearReset"' "$app" && ok "app: botão restaurar padrão existe" || bad "app: sem restaurar"
    grep -q 'otm-font' "$app" && ok "app: fonte é salva (localStorage)" || bad "app: fonte não persiste"
    grep -q 'otm-scale' "$app" && ok "app: DPI é salvo (localStorage)" || bad "app: DPI não persiste"
    grep -q 'setFontQuiet' "$app" && grep -q 'setScaleQuiet' "$app" \
        && ok "app: fonte/DPI aplicados no painel" || bad "app: fonte/DPI não aplicados"
    # paridade web x app (mesmos controles e mesmas chaves)
    for k in 'id="setFont"' 'id="setScale"' 'id="gearReset"' 'otm-font' 'otm-scale'; do
        grep -q "$k" "$web" || bad "web: falta $k (sem paridade com o app)"
    done
    ok "web: personalização em paridade com o app"
    # DPI não pode reintroduzir o arrasto lateral.
    # Acima de 100% a largura é compensada; abaixo o zoom já encolhe tudo, então a
    # largura fica em 100% (compensar ali é que estourava a tela e trazia o arrasto).
    grep -q 'z > 1 ? "calc(100% / ' "$app" \
        && ok "app: DPI compensa a largura só acima de 100% (sem estouro)" \
        || bad "app: DPI sem compensação condicional de largura"
    grep -q 'z > 1 ? "calc(100% / ' "$web" \
        && ok "web: DPI compensa a largura só acima de 100%" \
        || bad "web: DPI sem compensação condicional de largura"
    grep -q 'overflow-x:clip' "$web" && ok "web: topo clipa o transbordo" || bad "web: transbordo não clipado"
    # faixa de DPI: precisa permitir bem menor que 100% (até 60%) e maior (160%)
    grep -q 'id="setScale" min="60" max="160"' "$app" \
        && ok "app: DPI vai de 60% a 160%" || bad "app: faixa de DPI não cobre 60%"
    grep -q 'id="setScale" min="60" max="160"' "$web" \
        && ok "web: DPI vai de 60% a 160%" || bad "web: faixa de DPI não cobre 60%"
    grep -q 'Math.max(0.6' "$app" && grep -q 'Math.min(1.6' "$app" \
        && ok "app: clamp de DPI bate com a faixa (0.6x..1.6x)" || bad "app: clamp de DPI fora da faixa"
    # banner: frase de venda pedida pelo autor
    grep -q 'liso que nem sabão' "$app" && grep -q 'liso que nem sabão' "$web" \
        && ok "banner: frase de venda no app e no web" || bad "banner: frase de venda ausente"
}


t_usage_access() {
    printf '\n  # acesso a dados de uso (PACKAGE_USAGE_STATS) e métricas de uso\n'
    local app="$ROOT/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"
    local kt="$ROOT/app/src/main/java/com/otm/pack/Usage.kt"
    local br="$ROOT/app/src/main/java/com/otm/pack/PackBridge.kt"
    local man="$ROOT/app/src/main/AndroidManifest.xml"
    # manifesto declara a permissão (com o ignore do lint, é permissão de sistema)
    grep -q 'PACKAGE_USAGE_STATS' "$man" && ok "manifesto: permissão de uso declarada" || bad "manifesto: sem PACKAGE_USAGE_STATS"
    grep -q 'tools:ignore="ProtectedPermissions"' "$man" && ok "manifesto: lint ignorado p/ permissão de sistema" || bad "manifesto: sem tools:ignore"
    # leitor real usa a API do Android, não número inventado
    [ -f "$kt" ] && grep -q 'OPSTR_GET_USAGE_STATS' "$kt" && ok "Usage.kt: checa a autorização via AppOps" || bad "Usage.kt: sem checagem AppOps"
    grep -q 'queryEvents' "$kt" && grep -q 'queryAndAggregateUsageStats' "$kt" \
        && ok "Usage.kt: lê primeiro plano e tempo de uso" || bad "Usage.kt: leitura incompleta"
    grep -q 'ACTION_USAGE_ACCESS_SETTINGS' "$kt" && ok "Usage.kt: abre a tela do sistema" || bad "Usage.kt: não abre a tela"
    # sem autorização devolve vazio (não inventa)
    grep -q 'if (!granted(context)) return o' "$kt" && ok "Usage.kt: sem permissão devolve vazio (—)" || bad "Usage.kt: pode inventar dado"
    # a ponte junta o uso ao stats e expõe o comando
    grep -q 'Usage.snapshot(context)' "$br" && ok "ponte: uso real junto das métricas" || bad "ponte: uso não integrado"
    grep -q '"usage" ->' "$br" && ok "ponte: comando usage existe" || bad "ponte: comando usage ausente"
    # painel (app e web) mostra os cards e o botão
    grep -q 'data-stat="fg"' "$app" && grep -q 'data-stat="usage"' "$app" \
        && ok "app: cards de uso na Home" || bad "app: sem cards de uso"
    # Home reorganizada: métricas em grupos, botão de liberar e atualizar no painel
    [ "$(grep -c 'stat-group' "$app")" -ge 2 ] && ok "app: métricas separadas em grupos" || bad "app: sem grupos de métricas"
    grep -q 'glabel' "$app" && grep -q 'Uso do aparelho' "$app" \
        && ok "app: grupo 'Uso do aparelho' rotulado" || bad "app: grupo de uso sem rótulo"
    grep -q 'id="btnUsagePerm"' "$app" && grep -q 'id="btnUsagePerm"' "$web" \
        && ok "app+web: botão para liberar o uso" || bad "botão de liberar o uso ausente"
    grep -q 'id="btnRefreshStats"' "$app" && grep -q 'boxhead' "$app" \
        && ok "app: atualizar fica no cabeçalho do painel" || bad "app: atualizar fora do cabeçalho"
    grep -q 'id="usageNeed"' "$app" && grep -q 'precisa do Acesso a dados de uso' "$app" \
        && ok "app: chip avisa que o grupo precisa da permissão" || bad "app: sem chip de aviso do grupo"
    # o pedido uma vez por versão existe no app
    grep -q 'Ver o uso real do aparelho' "$ROOT/app/src/main/java/com/otm/pack/Permissions.kt" \
        && ok "app: pede a permissão na primeira abertura" || bad "app: não pede a permissão"
}


t_plugin_mark_once() {
    printf '\n  # plugin 02: loop não duplica/toca o backup após o 1o apply (deep_mark)\n'
    p="$TMP/p02"; rm -rf "$p"; cp -r "$ROOT/00 Otimizações/Plugins AxManager/Nossos/02-webui-control" "$p"
    rm -rf /data/adb/packotm "$p/state" 2>/dev/null
    sh "$p/apply.sh" set CFG_DEEP 1 >/dev/null 2>&1
    sh "$p/apply.sh" apply >/dev/null 2>&1
    st="$(plugin_state "$p")"
    off="$st/deep_off.sh"
    [ -f "$st/deep_mark" ] && ok "1o apply cria o marcador deep_mark ($st)" || bad "1o apply não criou o marcador"
    # simula um backup já gravado (como num aparelho real)
    printf 'freq\techo ondemand > /sys/fake\n' > "$off"
    n1=$(wc -l < "$off")
    sh "$p/apply.sh" apply >/dev/null 2>&1
    sh "$p/apply.sh" apply >/dev/null 2>&1
    n3=$(wc -l < "$off")
    assert_eq "$n1" "$n3" "reaplicar não altera o backup ($n1 -> $n3 linhas)"
    grep -q '^freq' "$off" && ok "conteúdo do backup preservado" || bad "backup foi sobrescrito"
}

t_plugin_restore() {
    printf '\n  # plugin 02: restore remove ANGLE e limpa o marcador\n'
    p="$TMP/p02"
    sh "$p/apply.sh" restore >/dev/null 2>&1
    [ -f "$TMP_STORE/global.angle_gl_driver_selection_pkgs" ] && bad "restore removeu o setting angle" || ok "restore removeu o setting angle"
    st="$(plugin_state "$p")"
    [ -f "$st/deep_mark" ] && bad "restore removeu o deep_mark" || ok "restore removeu o deep_mark"
    rm -rf /data/adb/packotm "$p/state" 2>/dev/null
}

t_freezer_whitelist() {
    printf '\n  # plugin 06: whitelist e proteção do sistema no congelamento\n'
    p="$TMP/p06"; rm -rf "$p"; cp -r "$ROOT/00 Otimizações/Plugins AxManager/Nossos/06-freezer" "$p"
    rm -rf /data/adb/packotm_freezer "$p/state" 2>/dev/null
    export TMP_PM_LOG="$TMP/pm.log"; : > "$TMP_PM_LOG"
    # whitelist: whatsapp nunca congela; blacklist inclui instagram (padrão)
    sh "$p/apply.sh" wl-add com.whatsapp >/dev/null 2>&1
    sh "$p/apply.sh" bl-add com.instagram.android >/dev/null 2>&1
    sh "$p/apply.sh" freeze >/dev/null 2>&1
    # ancora no início: 'unsuspend' também contém 'suspend'
    grep -q '^suspend --user 0 com.instagram.android$' "$TMP_PM_LOG" \
        && ok "congela app da blacklist (instagram)" || bad "não congelou o instagram"
    grep -q '^suspend --user 0 com.whatsapp$\|^disable-user --user 0 com.whatsapp$' "$TMP_PM_LOG" \
        && bad "congelou app da whitelist (whatsapp)" || ok "pulou app da whitelist (whatsapp)"
    grep -q '^suspend --user 0 com.android.systemui$\|^disable-user --user 0 com.android.systemui$' "$TMP_PM_LOG" \
        && bad "congelou app do sistema (systemui)" || ok "protegeu app do sistema (systemui)"
    # freeze-app explícito num app do sistema também é recusado
    sh "$p/apply.sh" freeze-app com.android.systemui >/dev/null 2>&1
    grep -q '^suspend --user 0 com.android.systemui$\|^disable-user --user 0 com.android.systemui$' "$TMP_PM_LOG" \
        && bad "freeze-app furou a proteção do sistema" || ok "freeze-app respeita a proteção do sistema"
    unset TMP_PM_LOG
    rm -rf /data/adb/packotm_freezer "$p/state" 2>/dev/null
}

t_thermal_gate() {
    printf '\n  # deep-tune: módulos root (thermal) saíram do pack\n'
    rm -rf "$HOME/.packotm/deep"
    # thermal exigia root: não é mais um módulo válido
    OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" thermal on </dev/null > "$TMP/th_out" 2>&1
    assert_eq "1" "$?" "thermal on é recusado (módulo root removido)"
    assert_contains "$TMP/th_out" "desconhecido" "deep-tune avisa que thermal não existe mais"
    grep -q 'THERMAL_OK' "$ROOT/scripts/deep-tune.sh" \
        && bad "deep-tune ainda tem a trava térmica (root)" || ok "deep-tune sem trava térmica (root)"
}

t_secret_scanner() {
    printf '\n  # check-secrets: detecta um token plantado\n'
    plant="$ROOT/tests/.tmp_secret_probe"
    printf 'token = ghp_%s\n' "012345678901234567890123456789012345" > "$plant"
    sh "$ROOT/scripts/check-secrets.sh" --all >/dev/null 2>&1
    rc=$?
    rm -f "$plant"
    assert_eq "1" "$rc" "scanner sai com código 1 ao achar token"
}

t_site_html() {
    printf '\n  # index.html: site único (estrutura + JS válido)\n'
    f="$ROOT/index.html"
    [ -f "$f" ] && ok "index.html existe" || { bad "index.html ausente"; return; }
    head -c 200 "$f" | grep -q '<!DOCTYPE html>' && ok "tem DOCTYPE" || bad "sem DOCTYPE"
    tail -c 40 "$f" | grep -q '</html>' && ok "fecha </html>" || bad "não fecha </html>"
    grep -q 'id="cmdlist"' "$f" && ok "tem área de comandos (#cmdlist)" || bad "sem #cmdlist"
    # JS: se houver node, valida a sintaxe do <script>
    if command -v node >/dev/null 2>&1; then
        awk '/<script>/{f=1;next}/<\/script>/{f=0}f' "$f" > "$TMP/site.js"
        node --check "$TMP/site.js" >/dev/null 2>&1 \
            && ok "JS do site sem erro de sintaxe" || bad "JS do site com erro de sintaxe"
    else
        ok "node ausente: pulo a checagem de sintaxe do JS"
    fi
    # a lista de comandos tem categorias de renderizador e congelar
    grep -q 'skiavk' "$f" && ok "inclui comando Vulkan (skiavk)" || bad "sem comando Vulkan"
    grep -q 'pm suspend' "$f" && ok "inclui congelar apps (pm suspend)" || bad "sem congelar apps"
    # a resolução (wm size) está na área de comandos
    grep -q 'wm size reset' "$f" && ok "inclui resolução (wm size)" || bad "sem comando de resolução"
    # o site e a cópia publicada (public/guia.html) precisam ter a MESMA lista de
    # comandos: são dois arquivos, e uma edição só num deles passa despercebida.
    if [ -f "$ROOT/public/guia.html" ]; then
        a="$TMP/guia_site"; b="$TMP/guia_pub"
        sed -n '/^const CMDS = \[/,/^\];/p' "$f" > "$a"
        sed -n '/^const CMDS = \[/,/^\];/p' "$ROOT/public/guia.html" > "$b"
        if [ -s "$a" ] && cmp -s "$a" "$b"; then
            ok "public/guia.html tem a mesma lista de comandos do index.html"
        else
            bad "public/guia.html e index.html divergem na lista de comandos"
        fi
    fi
}

t_marca_trix() {
    printf '\n  # marca: nome Trix, cor padrao prata e icones da logo\n'
    # nome do app (recurso do Android) e titulo do painel/logins
    grep -q '<string name="app_name">Trix</string>' "$ROOT/app/src/main/res/values/strings.xml" \
        && ok "strings.xml: app_name = Trix" || bad "app_name nao e Trix"
    grep -q 'setContentTitle("Trix")' "$ROOT/app/src/main/java/com/otm/pack/OverlayService.kt" \
        && grep -q 'setContentTitle("Trix")' "$ROOT/app/src/main/java/com/otm/pack/Permissions.kt" \
        && ok "notificacoes com o titulo Trix" || bad "notificacao ainda com o nome antigo"
    for f in "$ROOT/web/index.php" "$ROOT/web/login.php" \
             "$ROOT/app/src/main/assets/panel/index.html" \
             "$ROOT/app/src/main/assets/panel/login.html" "$ROOT/public/login.html"; do
        grep -q '<title>.*Trix' "$f" && ok "titulo Trix em ${f#$ROOT/}" || bad "titulo antigo em ${f#$ROOT/}"
    done
    grep -q '00deUdia Otimizações' "$ROOT/web/index.php" \
        && bad "index.php ainda mostra a marca antiga" || ok "marca antiga saiu do painel web"
    # o nome antigo nao pode sobrar no branding (nome de usuario do login continua)
    grep -q '<h1>00 Otimização</h1>\|<h1>00deUdia Otimizações</h1>' "$ROOT/app/src/main/assets/panel/index.html" \
        && bad "painel do app ainda mostra a marca antiga" || ok "painel do app com a marca Trix"

    # cor padrao prata (laranja segue disponivel como opcao)
    grep -q -- '--accent:#c7ccd6' "$ROOT/web/index.php" \
        && grep -q -- '--accent:#c7ccd6' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "cor padrao prata nos dois paineis" || bad "painel sem a cor prata padrao"
    grep -q '<item name="colorPrimary">#C7CCD6</item>' "$ROOT/app/src/main/res/values/themes.xml" \
        && ok "tema Android: colorPrimary prata" || bad "colorPrimary nao e prata"
    grep -q 'data-accent="laranja"' "$ROOT/web/index.php" \
        && ok "laranja continua na paleta (opcao do usuario)" || bad "laranja sumiu da paleta"
    grep -q 'localStorage.getItem("otm-accent") || "prata"' "$ROOT/web/index.php" \
        && grep -q 'localStorage.getItem("otm-accent") || "prata"' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "accent padrao salvo e prata" || bad "accent padrao ainda e laranja"
    grep -q 'accent: String = "#c7ccd6"' "$ROOT/app/src/main/java/com/otm/pack/OtmExec.kt" \
        && ok "cor padrao do flutuante e prata" || bad "flutuante ainda abre laranja"

    # icones: todas as densidades presentes, quadradas, e o foreground do adaptive.
    # Le o cabecalho PNG direto (sem PIL: a suite nao depende de pacote externo).
    icon_out=$(python3 - "$ROOT" <<'PYEOF'
import struct, sys
root = sys.argv[1]
esp = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

def tamanho(p):
    with open(p, 'rb') as fh:
        if fh.read(8) != b'\x89PNG\r\n\x1a\n':
            raise ValueError('nao e PNG')
        fh.read(4)
        if fh.read(4) != b'IHDR':
            raise ValueError('sem IHDR')
        return struct.unpack('>II', fh.read(8))

erros = []
for d, n in esp.items():
    for suf in ('ic_launcher', 'ic_launcher_round'):
        try:
            w, h = tamanho(f'{root}/app/src/main/res/mipmap-{d}/{suf}.png')
        except Exception as e:
            erros.append(f'{suf}-{d}: {e}'); continue
        if (w, h) != (n, n): erros.append(f'{suf}-{d}: {w}x{h} != {n}x{n}')
try:
    w, h = tamanho(f'{root}/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png')
    if (w, h) != (432, 432): erros.append(f'foreground: {w}x{h} != 432x432')
except Exception as e:
    erros.append(f'foreground: {e}')
print('; '.join(erros))
PYEOF
)
    if [ -z "$icon_out" ]; then
        ok "icones: 5 densidades (quadrado + redondo) e foreground 432x432"
    else
        bad "icones com problema: $icon_out"
    fi
    # a logo nova substituiu a antiga: o icone nao pode ser igual ao de antes do
    # rebranding (tag v2.41.2, o ultimo release com a logo velha)
    if git -C "$ROOT" show v2.41.2:app/src/main/res/mipmap-xxxhdpi/ic_launcher.png > "$TMP/ic_old.png" 2>/dev/null; then
        if cmp -s "$TMP/ic_old.png" "$ROOT/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png"; then
            bad "ic_launcher ainda e o antigo (logo nao trocou)"
        else
            ok "ic_launcher trocado pela logo nova"
        fi
    else
        ok "sem versao anterior do icone para comparar"
    fi
}

t_build_plugins() {
    printf '\n  # build-plugins: empacota todos os plugins (nossos + terceiros OSS)\n'
    sh "$ROOT/scripts/build-plugins.sh" >/dev/null 2>&1
    assert_eq "0" "$?" "build-plugins roda sem erro"
    for name in 01-service-loop 02-webui-control 03-battery-thermal 04-cleaner 05-fps-refresh 06-freezer Kang Sakoiire Aapt-for-Plugin; do
        [ -f "$ROOT/releases/$name.zip" ] \
            && assert_eq "ok" "ok" "gera $name.zip" \
            || assert_eq "zip" "ausente" "gera $name.zip"
    done
    rm -f "$ROOT/releases"/*.zip "$ROOT/releases"/*.zip.sha256
}

t_build_modules() {
    printf '\n  # build-modules: empacota os módulos próprios (Modulos/)\n'
    sh "$ROOT/scripts/build-modules.sh" >/dev/null 2>&1
    assert_eq "0" "$?" "build-modules roda sem erro"
    [ -f "$ROOT/releases/WS7_OFF7.zip" ] \
        && assert_eq "ok" "ok" "gera WS7_OFF7.zip" \
        || assert_eq "zip" "ausente" "gera WS7_OFF7.zip"
    rm -f "$ROOT/releases"/*.zip "$ROOT/releases"/*.zip.sha256
}


t_build_pack() {
    printf '\n  # build-pack: gera o zip unico "Pack 00" completo\n'
    sh "$ROOT/scripts/build-pack.sh" >/dev/null 2>&1
    assert_eq "0" "$?" "build-pack roda sem erro"
    v="$(cat "$ROOT/VERSION" 2>/dev/null)"
    pack="$ROOT/releases/Pack-de-Otimizacao-00-v$v.zip"
    [ -f "$pack" ] && ok "gera o zip do pack (v$v)" || { bad "zip do pack ausente"; rm -f "$ROOT/releases"/*.zip "$ROOT/releases"/*.zip.sha256; return; }
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$pack" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); n = z.namelist()
checks = {
 "scripts/adb-tweaks.sh": any(x.endswith('/scripts/adb-tweaks.sh') for x in n),
 "releases/06-freezer.zip": any(x.endswith('/releases/06-freezer.zip') for x in n),
 "Apps/README.md": any(x.endswith('/Apps/README.md') for x in n),
 "pack.sh (raiz)": any(x.endswith('/pack.sh') for x in n),
 "scripts/pack.sh (menu-mestre)": any(x.endswith('/scripts/pack.sh') for x in n),
 "run.sh (nivel 2)": any(x.endswith('/00 Otimiza\u00e7\u00f5es/Scripts SH/run.sh') for x in n),
 "22 .txt Brevent": sum(1 for x in n if '/Comandos Brevent/' in x and x.endswith('.txt')) >= 22,
}
for k, okk in checks.items():
    print(("  [ ok ] " if okk else "  [FAIL] ") + "pack contem " + k)
PY
    fi
    rm -f "$ROOT/releases"/*.zip "$ROOT/releases"/*.zip.sha256
}

t_debloat() {
    printf '\n  # debloat: aplica perfil, registra reversão e reverte tudo\n'
    st="$HOME/.packotm/debloat"
    rm -rf "$st"
    export TMP_PM_LOG="$TMP/pm2.log"; : > "$TMP_PM_LOG"
    export TMP_CMD_LOG="$TMP/cmd2.log"; : > "$TMP_CMD_LOG"
    OTM_MODE=local sh "$ROOT/scripts/debloat.sh" on leve >/dev/null 2>&1
    [ -f "$st/applied" ] && ok "on cria o marcador 'applied'" || bad "on não criou o marcador"
    [ -s "$st/off.sh" ] && ok "on registra reversões em off.sh" || bad "off.sh vazio"
    grep -q 'disable-user --user 0 com.samsung.android.game.gos' "$TMP_PM_LOG"         && ok "desativa bloat do fabricante" || bad "não desativou bloat do fabricante"
    grep -q 'appops set com.facebook.katana RUN_IN_BACKGROUND ignore' "$TMP_CMD_LOG"         && ok "restringe plano de fundo (appops)" || bad "não restringiu appops"
    OTM_MODE=local sh "$ROOT/scripts/debloat.sh" off >/dev/null 2>&1
    [ -f "$st/applied" ] && bad "off não removeu o marcador" || ok "off remove o marcador"
    [ -f "$st/off.sh" ] && bad "off não removeu o off.sh" || ok "off limpa o off.sh"
    # ações avulsas também registram reversão
    OTM_MODE=local sh "$ROOT/scripts/debloat.sh" uninstall com.exemplo >/dev/null 2>&1
    grep -q 'install-existing com.exemplo' "$st/off.sh"         && ok "uninstall registra reinstall (install-existing)" || bad "uninstall não registrou reversão"
    rm -rf "$st"
    unset TMP_PM_LOG TMP_CMD_LOG

    # ---- listas curadas (universal + por marca) ----
    printf '\n  # debloat: listas curadas universal e por marca\n'
    L="$ROOT/scripts/debloat-lists.sh"
    [ -f "$L" ] && ok "debloat-lists.sh existe" || bad "debloat-lists.sh ausente"

    # helper: imprime todos os pacotes das listas
    # aspas em cada variavel: o motivo tem espacos, entao o for sem aspas quebraria
    cat > "$TMP/dbl_dump.sh" <<EOF
. "$L"
for b in UNIVERSAL SAMSUNG XIAOMI MOTOROLA ONEPLUS REALME VIVO HUAWEI ASUS SONY LG TRANSSION; do
    eval "printf '%s\\n' \"\\\$DBL_\$b\""
done
EOF

    for b in UNIVERSAL SAMSUNG XIAOMI MOTOROLA ONEPLUS REALME VIVO HUAWEI ASUS SONY LG TRANSSION; do
        n=$(sh -c ". \"$L\"; printf '%s\n' \"\$DBL_$b\" | grep -c .")
        [ "$n" -ge 5 ] && ok "lista $b tem $n pacotes" || bad "lista $b vazia/curta ($n)"
    done

    sh "$TMP/dbl_dump.sh" > "$TMP/dbl_raw"
    cut -d'|' -f1 "$TMP/dbl_raw" | grep . > "$TMP/dbl_all"
    n_all=$(grep -c . "$TMP/dbl_all")
    [ "$n_all" -gt 300 ] && ok "listas somam $n_all pacotes" || bad "listas curtas ($n_all)"

    # toda linha tem motivo ("pacote|motivo")
    sem=$(grep -vc '|' "$TMP/dbl_raw" || true)
    [ "$sem" -eq 0 ] && ok "toda linha das listas tem motivo" || bad "$sem linha(s) sem motivo"

    # SEGURANCA: nenhuma lista pode conter pacote critico
    perigo='systemui settings providers camera gallery dialer phone telecom telephony mms sms messag contact calendar clock calculator keyboard inputmethod launcher bluetooth nfc wifi biometr fingerprint fpstouch goodix synaptics payment wallet tsm uicc esim updater installer fota accessib talkback accessory watchmanager watchon gear buds cloud backup modem mot5gmod volume vold audio codec keystore credential gms gsf vending framework drm widevine cast mirror usb stylus rro health dex samsungpay smartswitch spooler emergency security knox vpn gatekeeper'
    vaz=0
    for k in $perigo; do
        if grep -qi "$k" "$TMP/dbl_all"; then vaz=1; bad "lista contem pacote critico: $k ($(grep -i "$k" "$TMP/dbl_all" | tr '\n' ' '))"; fi
    done
    [ "$vaz" -eq 0 ] && ok "nenhuma lista contem pacote critico (camera, telefone, sistema...)"

    # protecao em tempo de execucao: recusa pacote critico mesmo se for forçado
    cat > "$TMP/dbl_prot.sh" <<EOF
. "$L"
for p in com.android.systemui com.sec.android.app.camera com.android.dialer com.google.android.gms com.android.vending com.samsung.android.app.watchmanager com.motorola.motofpstouch com.motorola.mot5gmod; do
    case " \$DBL_NEVER " in *" \$p "*) echo "NEVER:\$p"; continue ;; esac
    for k in \$DBL_KEEP; do
        case "\$p" in *"\$k"*) echo "KEEP:\$p"; break ;; esac
    done
done
EOF
    sh "$TMP/dbl_prot.sh" > "$TMP/dbl_prot"
    for p in com.android.systemui com.sec.android.app.camera com.android.dialer com.google.android.gms com.android.vending com.samsung.android.app.watchmanager com.motorola.motofpstouch com.motorola.mot5gmod; do
        grep -q ":$p$" "$TMP/dbl_prot" && ok "protege $p" || bad "nao protegeu $p"
    done

    # preview nao altera nada
    rm -rf "$st"
    OTM_MODE=local OTM_NO_COLOR=1 sh "$ROOT/scripts/debloat.sh" preview samsung > "$TMP/dbl_prev" 2>&1
    assert_contains "$TMP/dbl_prev" "Nada foi alterado" "preview nao altera nada"
    [ -f "$st/applied" ] && bad "preview marcou como aplicado" || ok "preview nao marca como aplicado"

    # apply por marca: remove e registra reversao
    rm -rf "$st"
    OTM_MODE=local OTM_NO_COLOR=1 sh "$ROOT/scripts/debloat.sh" samsung > "$TMP/dbl_ap" 2>&1
    assert_contains "$TMP/dbl_ap" "removido" "debloat por marca remove apps"
    grep -q 'install-existing' "$st/off.sh" 2>/dev/null \
        && ok "debloat por marca registra reversao" || bad "nao registrou reversao"
    OTM_MODE=local sh "$ROOT/scripts/debloat.sh" off >/dev/null 2>&1
    [ -f "$st/applied" ] && bad "off nao limpou" || ok "debloat por marca reverte"

    # marcas: alvos + marca detectada
    OTM_MODE=local OTM_NO_COLOR=1 sh "$ROOT/scripts/debloat.sh" marcas > "$TMP/dbl_m" 2>&1
    assert_contains "$TMP/dbl_m" "universal" "marcas lista os alvos"
    assert_contains "$TMP/dbl_m" "deste aparelho" "marcas mostra a marca detectada"
    rm -rf "$st"

    # nenhum card de debloat pode estar duplicado nos paineis (ja aconteceu:
    # o card de previa ficou duplicado no index.html do app)
    dup=$(grep -o 'data-id="debloat\.[a-z.]*"' "$ROOT/app/src/main/assets/panel/index.html" \
          | sort | uniq -d | head -3)
    [ -z "$dup" ] && ok "app: sem card de debloat duplicado" || bad "app: card duplicado: $dup"
    dup=$(grep -oE "'id' => 'debloat\.[a-z.]*'" "$ROOT/web/lib.php" | sort | uniq -d | head -3)
    [ -z "$dup" ] && ok "web: sem acao de debloat duplicada" || bad "web: acao duplicada: $dup"
    # os dois paineis tem o mesmo conjunto de cards de debloat.
    # compara o web RENDERIZADO (os perfis leve/medio/pesado sao montados no PHP)
    php -r 'require "web/auth.php"; otm_auth_login("00deUdia","159951");
            ob_start(); include "web/index.php"; file_put_contents($argv[1], ob_get_clean());' \
        "$TMP/dbl_web.html" 2>/dev/null
    wa=$(grep -o 'data-id="debloat\.[a-z.]*"' "$TMP/dbl_web.html" | sed 's/data-id="//; s/"$//' | sort -u)
    aa=$(grep -o 'data-id="debloat\.[a-z.]*"' "$ROOT/app/src/main/assets/panel/index.html" | sed 's/data-id="//; s/"$//' | sort -u)
    if [ -n "$wa" ] && [ "$wa" = "$aa" ]; then
        ok "web e app tem os mesmos $(printf '%s\n' "$aa" | grep -c .) cards de debloat"
    else
        bad "cards de debloat divergem entre web e app"
    fi
}

t_dns() {
    printf '\n  # dns.sh: perfis de DNS privado (aplica/reverte)\n'
    f="$ROOT/scripts/dns.sh"
    [ -f "$f" ] && ok "scripts/dns.sh existe" || { bad "dns.sh ausente"; return; }
    OTM_MODE=local OTM_NO_COLOR=1 sh "$f" list > "$TMP/dns_list" 2>&1
    assert_contains "$TMP/dns_list" "adguard" "dns list mostra perfis"
    assert_contains "$TMP/dns_list" "Bloqueio de an" "dns list descreve bloqueio de anuncios"
    st="$HOME/.packotm"; rm -rf "$st/off.sh" "$st/on" "$st/undo" "$st/origins"
    OTM_MODE=local sh "$f" adguard >/dev/null 2>&1
    [ "$(cat "$TMP_STORE/global.private_dns_specifier" 2>/dev/null)" = "dns.adguard-dns.com" ] \
        && ok "dns adguard grava o hostname DoT" || bad "nao gravou o hostname"
    grep -q "private_dns_mode" "$st/undo/dns.sh" 2>/dev/null && ok "dns registra reversao" || bad "sem reversao"
    OTM_MODE=local sh "$f" off >/dev/null 2>&1
    [ "$(cat "$TMP_STORE/global.private_dns_mode" 2>/dev/null)" = "opportunistic" ] \
        && ok "dns off volta para automatico" || bad "off nao restaurou"
    OTM_MODE=local sh "$f" custom dns.exemplo.com >/dev/null 2>&1
    [ "$(cat "$TMP_STORE/global.private_dns_specifier" 2>/dev/null)" = "dns.exemplo.com" ] \
        && ok "dns custom aceita hostname" || bad "custom nao gravou"
    # provedores da lista ampliada de DoT (hostnames verificados)
    n_prof=$(OTM_MODE=local OTM_NO_COLOR=1 sh "$f" list 2>/dev/null | grep -c '^ *[a-z]')
    [ "$n_prof" -ge 30 ] && ok "dns list traz $n_prof perfis" || bad "perfis de DNS: $n_prof (esperado >=30)"
    for pair in "opendns:dns.opendns.com" \
                "opendns-family:familyshield.opendns.com" \
                "cleanbrowsing-family:family-filter-dns.cleanbrowsing.org" \
                "cleanbrowsing-adult:adult-filter-dns.cleanbrowsing.org" \
                "controld-ads:p2.freedns.controld.com" \
                "controld-family:family.freedns.controld.com" \
                "controld-oisd:x-oisd.freedns.controld.com" \
                "mullvad-all:all.dns.mullvad.net" \
                "mullvad-adblock:adblock.dns.mullvad.net" \
                "dns4eu-protective:protective.joindns4.eu" \
                "dns4eu-child-noads:child-noads.joindns4.eu" \
                "dns-sb:dot.sb" \
                "cz-nic:odvr.nic.cz" \
                "digitale-gesellschaft:dns.digitale-gesellschaft.ch" \
                "restena:dnspub.restena.lu" \
                "applied-privacy:dot1.applied-privacy.net" \
                "uncensored:anycast.censurfridns.dk" \
                "adguard-unfiltered:unfiltered.adguard-dns.com" \
                "cloudflare-security:security.cloudflare-dns.com"; do
        id="${pair%%:*}"; host="${pair#*:}"
        rm -rf "$st/off.sh" "$st/on" "$st/undo" "$st/origins"
        OTM_MODE=local sh "$f" "$id" >/dev/null 2>&1
        [ "$(cat "$TMP_STORE/global.private_dns_specifier" 2>/dev/null)" = "$host" ] \
            && ok "dns $id grava $host" || bad "dns $id nao gravou ($host)"
    done
    rm -rf "$st/off.sh" "$st/on" "$st/undo" "$st/origins"
}

t_new_scripts() {
    printf '\n  # doze + gerenciador de processos (dados reais)\n'
    export TMP_CMD_LOG="$TMP/new2.log"; : > "$TMP_CMD_LOG"
    # --- doze: liga/desliga as constantes de idle ---
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" doze on > "$TMP/doze_on" 2>&1
    assert_contains "$TMP/doze_on" "doze" "doze on explica o efeito"
    grep -q 'inactive_to' "$TMP_STORE/global.device_idle_constants" 2>/dev/null \
        && ok "doze on grava as constantes" || bad "doze on sem constantes"
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" doze off > "$TMP/doze_off" 2>&1
    test ! -f "$TMP_STORE/global.device_idle_constants" && ok "doze off remove as constantes" || bad "doze off nao removeu"
    # --- touch_latency: aplica a responsividade e nao falha ---
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" touch_latency 80 300 0 4 > "$TMP/tl_out" 2>&1
    [ "$(cat "$TMP_STORE/system.touch_responsiveness" 2>/dev/null)" = "80" ] \
        && ok "touch_latency aplica responsiveness" || bad "touch_latency nao aplicou"
    [ "$(cat "$TMP_STORE/system.long_press_timeout" 2>/dev/null)" = "300" ] \
        && ok "touch_latency aplica long press" || bad "touch_latency nao aplicou long press"
    grep -q 'failed=1' "$TMP/tl_out" && bad "touch_latency reportou falha" || ok "touch_latency sem falha falsa"
    # --- proc-mgr: lista processos reais e valida entradas ---
    pf="$ROOT/scripts/proc-mgr.sh"
    [ -f "$pf" ] && ok "scripts/proc-mgr.sh existe" || { bad "proc-mgr.sh ausente"; return; }
    OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" > "$TMP/pm_help" 2>&1
    assert_contains "$TMP/pm_help" "proc-mgr.sh" "proc-mgr mostra a ajuda sem argumento"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" top 5 > "$TMP/pm_top" 2>&1
    assert_contains "$TMP/pm_top" "processos" "proc-mgr top lista os processos"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" info com.exemplo > "$TMP/pm_info" 2>&1
    grep -q 'não está rodando\|nao esta rodando\|Processos' "$TMP/pm_info" && ok "proc-mgr info responde por app" || bad "proc-mgr info mudo"
    # --- exceções ("X app não encerra") + encerrar todos ---
    export OTM_TEST_HOME="$TMP/pm_home"; rm -rf "$OTM_TEST_HOME"; mkdir -p "$OTM_TEST_HOME"
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" keep com.exemplo.live > "$TMP/pm_keep" 2>&1
    assert_contains "$TMP/pm_keep" "com.exemplo.live" "proc-mgr keep cria a exceção"
    grep -q 'com.exemplo.live' "$OTM_TEST_HOME/.packotm/procmgr/keep" \
        && ok "exceção fica guardada no estado" || bad "exceção não foi guardada"
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" keep-list > "$TMP/pm_klist" 2>&1
    assert_contains "$TMP/pm_klist" "com.exemplo.live" "proc-mgr keep-list mostra a exceção"
    # a exceção entra na lista que a limpeza respeita (common.sh)
    k="$(HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh -c ". '$ROOT/scripts/common.sh'; otm_keep_list")"
    case " $k " in *" com.exemplo.live "*) ok "exceção vale para o clean/ram-boost" ;;
        *) bad "exceção não entrou em otm_keep_list" ;; esac
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" unkeep com.exemplo.live > "$TMP/pm_unk" 2>&1
    grep -q 'com.exemplo.live' "$OTM_TEST_HOME/.packotm/procmgr/keep" \
        && bad "unkeep não removeu a exceção" || ok "proc-mgr unkeep remove a exceção"
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" keep com.exemplo.a >/dev/null 2>&1
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" keep-clear > "$TMP/pm_kclr" 2>&1
    [ -s "$OTM_TEST_HOME/.packotm/procmgr/keep" ] && bad "keep-clear não limpou" \
        || ok "proc-mgr keep-clear apaga todas"
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" list > "$TMP/pm_list" 2>&1
    grep -q 'app(s) rodando\|nenhum app de usuário rodando' "$TMP/pm_list" \
        && ok "proc-mgr list responde" || bad "proc-mgr list mudo"
    # apps: TODOS os instalados, para proteger quem NÃO está rodando agora
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" apps > "$TMP/pm_apps" 2>&1
    grep -q '#OTM-APP pkg=com.instagram.android protected=0' "$TMP/pm_apps" \
        && ok "proc-mgr apps lista todos os instalados" || bad "proc-mgr apps mudo"
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" keep com.instagram.android >/dev/null 2>&1
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" apps > "$TMP/pm_apps2" 2>&1
    grep -q '#OTM-APP pkg=com.instagram.android protected=1' "$TMP/pm_apps2" \
        && ok "proc-mgr apps marca quem está protegido" || bad "proc-mgr apps sem o flag de exceção"
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" unkeep com.instagram.android >/dev/null 2>&1
    # kill avisa (e não quebra) quando não há privilégio de shell
    HOME="$OTM_TEST_HOME" OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" kill > "$TMP/pm_kill" 2>&1
    grep -q 'sem permissão de shell' "$TMP/pm_kill" && ok "proc-mgr kill avisa sem shell" \
        || bad "proc-mgr kill sem aviso de permissão"
    # renice/ram/cpu/freeze/status/restore exigiam root: saíram do proc-mgr
    OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" renice com.exemplo -5 > "$TMP/pm_bad" 2>&1
    grep -qi 'módulo desconhecido\|uso:' "$TMP/pm_bad" \
        && ok "proc-mgr não tem mais o comando renice (root)" || bad "proc-mgr ainda aceita renice"
    grep -q 'require_root\|cmd_renice\|cmd_freeze' "$pf" \
        && bad "proc-mgr ainda tem código root" || ok "proc-mgr sem código root"
    # --- registro no painel + app ---
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["doze.on","doze.off","doze.status","proc.top","proc.info",
                       "touch.latency"] as $id)
               echo isset($a[$id]) ? "" : "FALTA:$id ";' > "$TMP/pm_reg" 2>&1
    test ! -s "$TMP/pm_reg" && ok "novas acoes no registro do painel" || bad "registro: $(cat "$TMP/pm_reg")"
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("proc-mgr.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' > "$TMP/pm_lib" 2>&1
    assert_contains "$TMP/pm_lib" "ok" "proc-mgr.sh na whitelist"
    grep -q '"proc-mgr.sh"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o gerenciador de processos" || bad "app: actions.json sem proc-mgr"
    grep -q '"doze.on"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o sono profundo" || bad "app: actions.json sem doze"
    # --- painel: home + Visual + leitura de stats ---
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo function_exists("otm_stats_read") ? "reader" : "";' > "$TMP/pm_stats" 2>&1
    assert_contains "$TMP/pm_stats" "reader" "lib: leitor de stats presente"
    grep -q "case 'stats'" "$ROOT/web/api.php" && ok "api.php: endpoint de stats" || bad "api.php: sem stats"
    grep -q 'fun statsImpl' "$ROOT/app/src/main/java/com/otm/pack/PackBridge.kt" \
        && ok "app: statsImpl presente" || bad "app: sem statsImpl"
    grep -q 'startStats' "$ROOT/web/index.php" && ok "painel: liga o polling das metricas" || bad "painel: sem startStats"
    rm -rf "$HOME/.packotm"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_game_per_app() {
    printf '\n  # game-per-app.sh: resolução do jogo por app (downscale) e "auto"\n'
    f="$ROOT/scripts/game-per-app.sh"
    [ -f "$f" ] && ok "scripts/game-per-app.sh existe" || { bad "game-per-app.sh ausente"; return; }
    rm -rf "$HOME/.packotm"
    # o teste roda em ordem alfabética de funções: um teste anterior pode ter
    # deixado um SDK antigo no store (o Game Mode exige API 31+).
    printf '34' > "$TMP_STORE/prop.ro.build.version.sdk"
    # downscale por perfil: cada perfil tem seu fator (nada de número inventado)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply com.exemplo.game fps > "$TMP/gpa_fps" 2>&1
    v="$(cat "$TMP_STORE/dc.game_overlay.com.exemplo.game" 2>/dev/null)"
    case "$v" in *downscaleFactor=0.9*) ok "apply fps grava o downscale 0.9" ;;
        *) bad "apply fps não gravou o overlay ($v)" ;; esac
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply com.exemplo.game max >/dev/null 2>&1
    v="$(cat "$TMP_STORE/dc.game_overlay.com.exemplo.game" 2>/dev/null)"
    case "$v" in *downscaleFactor=0.5*) ok "apply max grava o downscale 0.5" ;;
        *) bad "apply max não gravou o overlay ($v)" ;; esac
    # "auto" resolve pelo jogo escolhido no pack (o flutuante não sabe qual é)
    mkdir -p "$HOME/.packotm/game"
    printf 'com.exemplo.escolhido\n' > "$HOME/.packotm/game/pkg"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply auto fps > "$TMP/gpa_auto" 2>&1
    [ -f "$TMP_STORE/dc.game_overlay.com.exemplo.escolhido" ] \
        && ok "apply auto usa o jogo escolhido no pack" || bad "apply auto não resolveu o jogo"
    # reset e show também aceitam "auto" (o flutuante usa os três)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" show auto > "$TMP/gpa_show" 2>&1
    grep -q 'com.exemplo.escolhido' "$TMP/gpa_show" \
        && ok "show auto mostra o jogo escolhido" || bad "show auto não resolveu o jogo"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" reset auto > "$TMP/gpa_reset" 2>&1
    test ! -f "$TMP_STORE/dc.game_overlay.com.exemplo.escolhido" \
        && ok "reset auto remove o overlay do jogo" || bad "reset auto não removeu"
    # sem jogo escolhido e sem app em 1º plano: cai no Free Fire (o MESMO
    # padrão do `adb-tweaks.sh game_open`) em vez de dar erro no meio da
    # partida. Antes o "auto" do flutuante falhava nesse caso.
    rm -f "$HOME/.packotm/game/pkg"
    rm -f "$TMP_STORE/fg"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply auto fps > "$TMP/gpa_no" 2>&1
    grep -q 'com.dts.freefireth' "$TMP/gpa_no" \
        && ok "auto sem jogo cai no Free Fire (não falha no flutuante)" \
        || bad "auto sem jogo não usou o padrão do game_open"
    # e o jogo escolhido continua ganhando do padrão
    printf 'com.exemplo.escolhido\n' > "$HOME/.packotm/game/pkg"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" show auto > "$TMP/gpa_esc" 2>&1
    grep -q 'com.exemplo.escolhido' "$TMP/gpa_esc" \
        && ok "auto prefere o jogo escolhido ao padrão" || bad "auto ignorou a escolha"
    rm -f "$HOME/.packotm/game/pkg"
    rm -rf "$HOME/.packotm"
}

t_modules() {
    printf '\n  # modules.sh: lista e executa modulos/plugins da pasta\n'
    f="$ROOT/scripts/modules.sh"
    [ -f "$f" ] && ok "scripts/modules.sh existe" || { bad "modules.sh ausente"; return; }
    OTM_NO_COLOR=1 sh "$f" list > "$TMP/mod_list" 2>&1
    assert_contains "$TMP/mod_list" "WS7_OFF7" "modules list acha modulo em Modulos/"
    assert_contains "$TMP/mod_list" "06-freezer" "modules list acha plugin em Plugins/"
    OTM_NO_COLOR=1 sh "$f" actions WS7_OFF7 > "$TMP/mod_actions" 2>&1
    assert_contains "$TMP/mod_actions" "action.sh" "actions lista os scripts do modulo"
    OTM_NO_COLOR=1 sh "$f" info WS7_OFF7 > "$TMP/mod_info" 2>&1
    assert_contains "$TMP/mod_info" "version" "info mostra a versao do modulo"
    if OTM_MODE=local sh "$f" run WS7_OFF7 >/dev/null 2>&1; then
        ok "run executa a acao do modulo"
    else
        bad "run falhou"
    fi
    OTM_MODE=local OTM_NO_COLOR=1 sh "$ROOT/scripts/pack.sh" modules list > "$TMP/pack_mods" 2>&1
    assert_contains "$TMP/pack_mods" "WS7_OFF7" "pack.sh modules delega p/ modules.sh"
}

t_web() {
    printf '\n  # main.sh + painel web (PHP)\n'
    [ -f "$ROOT/main.sh" ] && ok "main.sh na raiz existe" || { bad "main.sh ausente"; return; }
    sh "$ROOT/main.sh" --help > "$TMP/main_help" 2>&1
    assert_contains "$TMP/main_help" "web start" "main.sh --help mostra o servidor web"
    OTM_MODE=local OTM_NO_COLOR=1 sh "$ROOT/main.sh" status > "$TMP/main_status" 2>&1
    assert_contains "$TMP/main_status" "PACK" "main.sh status mostra o status geral"

    for f in lib.php api.php index.php; do
        [ -f "$ROOT/web/$f" ] && ok "web/$f existe" || bad "web/$f ausente"
    done

    if command -v php >/dev/null 2>&1; then
        for f in lib.php api.php index.php; do
            php -l "$ROOT/web/$f" >/dev/null 2>&1 && ok "php -l web/$f" || bad "erro de sintaxe em web/$f"
        done
        # segurança: o registro tem ações de DNS, renderizador e por-app
        php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
                 echo isset($a["dns.adguard"])?"dns ":"", isset($a["gpu.skiavk"])?"gpu ":"",
                      isset($a["app.angle"])?"app ":"", isset($a["debloat.medio"])?"debloat\n":"";' \
            > "$TMP/web_actions" 2>&1
        assert_contains "$TMP/web_actions" "dns gpu app debloat" "registro cobre dns/gpu/app/debloat"
        # validação rejeita pacote malicioso
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $r=otm_run("app.angle",["pkg"=>"com.x; rm -rf /"],false);
                 echo $r["ok"]?"ACEITOU":"RECUSOU";' > "$TMP/web_sec" 2>&1
        assert_contains "$TMP/web_sec" "RECUSOU" "validação recusa pacote malicioso"
        # ação com confirmação exige confirm=1
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $r=otm_run("debloat.leve",[],false);
                 echo !empty($r["need_confirm"])?"PEDE":"NAO";' > "$TMP/web_conf" 2>&1
        assert_contains "$TMP/web_conf" "PEDE" "debloat exige confirmação"
        # o painel é renderizado no PHP (marca, menu e cards no HTML servido)
        # exige login: primeiro a tela de entrada, depois o painel autenticado.
        php -r '$_SERVER["REQUEST_METHOD"]="GET"; require "'"$ROOT"'/web/index.php";' \
            > "$TMP/web_login" 2>&1
        assert_contains "$TMP/web_login" "Entrar" "sem sessão, index.php mostra a tela de login"
        grep -q 'name="csrf"' "$TMP/web_login" && ok "login tem token CSRF" || bad "login sem CSRF"
        # login correto libera o painel
        php -r 'require "'"$ROOT"'/web/auth.php"; otm_auth_start();
                 $_SESSION["otm_user"]="00deUdia"; $_SERVER["REQUEST_METHOD"]="GET";
                 require "'"$ROOT"'/web/index.php";' \
            > "$TMP/web_html" 2>&1
        assert_contains "$TMP/web_html" "Bem-vindo ao Trix" "index.php traz a marca Trix"
        n_cards=$(grep -c 'class="card"' "$TMP/web_html")
        [ "$n_cards" -ge 85 ] && ok "index.php renderiza os cards no servidor ($n_cards)" \
            || bad "poucos cards renderizados ($n_cards)"
        n_sec=$(grep -c '<section id=' "$TMP/web_html")
        [ "$n_sec" -eq 13 ] && ok "index.php renderiza a home + 11 categorias + Terminal" || bad "seções: $n_sec (esperado 13)"
        for cat in "Geral" "Flutuante" "Display &amp; Touch" "Desempenho" "Dispositivos" "DNS e rede" "Latência e ping" "Processos" "Debloat" "Apps e jogos" "Sistema"; do
            assert_contains "$TMP/web_html" "$cat" "index.php tem a categoria $cat"
        done
        # "Sensi e mira" virou "Flutuante" e ficou só com o botão do painel flutuante
        grep -q 'Sensi e mira' "$TMP/web_html" && bad "a categoria antiga 'Sensi e mira' ainda existe" \
            || ok "categoria 'Sensi e mira' renomeada para 'Flutuante'"
        n_flut=$(awk '/<section id="g-Flutuante"/{f=1} f&&/data-id=/{n++} /<\/section>/{if(f){print n; exit}}' "$TMP/web_html")
        [ "$n_flut" = "1" ] && ok "a aba Flutuante tem só o botão do painel flutuante" \
            || bad "aba Flutuante com ${n_flut:-0} ações (esperado 1)"
        # Terminal: seção própria + campo de comando
        assert_contains "$TMP/web_html" 'id="g-Terminal"' "index.php tem a aba Terminal"
        assert_contains "$TMP/web_html" 'id="termInput"' "Terminal tem campo de comando"
        assert_contains "$TMP/web_html" 'id="termOut"' "Terminal tem área de saída"
        assert_contains "$TMP/web_html" 'do=term' "Terminal envia para api.php do=term"
        # Logs: painel próprio, histórico completo (log_all)
        assert_contains "$TMP/web_html" 'id="logspanel"' "index.php tem o painel de Logs"
        assert_contains "$TMP/web_html" 'id="btnLogs"' "cabeçalho tem o botão Logs"
        assert_contains "$TMP/web_html" 'log_all' "Logs usa o histórico completo (log_all)"
        grep -q 'id="btnConsole"' "$TMP/web_html" && bad "ainda existe o botão Console" \
            || ok "Console renomeado para Logs/Terminal"
        # seletor de apps com nome + ícone (sem digitar pacote)
        assert_contains "$TMP/web_html" 'data-apppick' "há o seletor de apps por nome/ícone"
        assert_contains "$TMP/web_html" 'id="appModal"' "seletor de apps tem a lista (modal)"
        grep -q 'list="applist"' "$TMP/web_html" && bad "ainda pede o pacote digitado (datalist)" \
            || ok "pacote não é mais digitado (sem datalist)"
        # home + área de métricas reais (consumo do aparelho)
        assert_contains "$TMP/web_html" 'data-g="Home"' "index.php tem a home"
        assert_contains "$TMP/web_html" "Consumo real do aparelho" "index.php tem a área de consumo real"
        assert_contains "$TMP/web_html" "Sistema agora" "index.php separa as métricas em grupos"
        assert_contains "$TMP/web_html" "Uso do aparelho" "index.php tem o grupo de uso do aparelho"
        for k in ram cpu bat stor disp up; do
            grep -q "data-stat=\"$k\"" "$TMP/web_html" && ok "Visual tem o medidor $k" || bad "Visual sem o medidor $k"
        done
        # categoria própria de DNS com muitos perfis
        n_dns=$(grep -o 'id="dns\.[a-z0-9-]*"' "$TMP/web_html" | sort -u | wc -l)
        [ "$n_dns" -ge 30 ] && ok "categoria DNS e rede com $n_dns perfis" || bad "perfis de DNS: $n_dns (esperado >=30)"
        grep -q '<section id="g-Rede' "$TMP/web_html" && bad "Rede ainda é seção separada" \
            || ok "Rede/DNS não é mais seção separada (virou 'DNS e rede')"
        # grupos de escolha: opções lado a lado com botão "Selecionar"
        n_choice=$(grep -c 'card card-choice' "$TMP/web_html")
        [ "$n_choice" -eq 12 ] && ok "renderiza 12 grupos de escolha (renderizador, app, refresh, DNS, toque, game clean, RAM, limite de processos, efeitos, barras, ícones da barra, bateria)" \
            || bad "grupos de escolha: $n_choice (esperado 12)"
        n_opts=$(grep -c 'class="opt"' "$TMP/web_html")
        # 43 = 37 opções de grupo (6 renderizadores + 1 app + 4 refresh + 7 DNS + 5
        # toques + 2 game clean + 2 RAM + 4 limite + 2 efeitos + 4 barras + 2 ícones
        # + 2 bateria) + os 2 botões do card de Perfil de Desempenho.
        [ "$n_opts" -eq 43 ] && ok "opções lado a lado: 6 renderizadores (com Automático) + 1 app + 4 refresh + 7 DNS + 5 toques + 2 game clean + 2 RAM + 4 limite + 2 efeitos + 4 barras + 2 ícones + 2 bateria ($n_opts)" \
            || bad "opções lado a lado: $n_opts (esperado 43)"
        assert_contains "$TMP/web_html" ">Selecionar<" "opções usam o rótulo Selecionar"
        # barras do sistema: cada bloco é um card de ligar/desligar (não botões soltos)
        assert_contains "$TMP/web_html" 'data-choice="sysbars_icons"' \
            "ícones da barra de cima são um card de ligar/desligar"
        assert_contains "$TMP/web_html" 'data-choice="sysbars_battery"' \
            "bateria em % é um card de ligar/desligar"
        assert_contains "$TMP/web_html" 'data-state-key="sysbars_icons_clean"' \
            "card de ícones lê o estado real (só o essencial / todos)"
        assert_contains "$TMP/web_html" 'data-state-value="clean"' \
            "ícones: opção 'Só o essencial' casa com o estado lido"
        assert_contains "$TMP/web_html" 'data-state-key="sysbars_battery"' \
            "card de bateria lê o estado real"
        assert_contains "$TMP/web_html" 'data-state-value="1"' \
            "bateria: opção 'Número (%)' casa com o estado lido"
        # taxa de atualização: escolha 60/90/120/automático (usuário prefere 60Hz)
        assert_contains "$TMP/web_html" 'data-choice="refresh"' "há o cartão de taxa de atualização (Hz)"
        for hz in 'refresh.60' 'refresh.90' 'refresh.120' 'refresh.auto'; do
            grep -q "data-opt=\"$hz\"" "$TMP/web_html" && ok "taxa de atualização tem $hz" || bad "sem $hz"
        done
        assert_contains "$TMP/web_html" 'data-state-value="60.0"' "60Hz casa com a taxa travada lida do aparelho"
        # a home mostra a TAXA de tela (refresh), não um número fixo errado
        assert_contains "$TMP/web_html" "Taxa de tela" "home mostra a taxa de tela (refresh)"
        # motor gráfico por app: seletor de pacote + driver, e "multithread" desempata pelo backend
        assert_contains "$TMP/web_html" 'data-choice="renderapp"' "há o cartão de driver por app"
        assert_contains "$TMP/web_html" 'data-p="pkg"' "driver por app escolhe o app"
        assert_contains "$TMP/web_html" 'data-state-backend-value="skiaglthreaded"' \
            "renderizador multithread desempata pelo backend"
        # DNS vira escolha (como o renderizador) na categoria "DNS e rede"
        assert_contains "$TMP/web_html" 'data-choice="dns_fast"' "DNS é um grupo de escolha"
        assert_contains "$TMP/web_html" 'data-state-value="one.one.one.one"' \
            "escolha de DNS casa pelo host DoT (host quebrado corrigido)"
        # ajuste fino com slider (arrastar) + campo numérico
        n_slider=$(grep -c 'class="slider"' "$TMP/web_html")
        [ "$n_slider" -ge 4 ] && ok "parâmetros numéricos viram sliders ($n_slider)" \
            || bad "sliders: $n_slider (esperado >=4)"
        grep -q 'type="range"' "$TMP/web_html" && ok "slider arrastável presente" || bad "sem range"
        grep -q 'data-pnum' "$TMP/web_html" && ok "campo numérico ao lado do slider" || bad "sem campo numérico"
        grep -q '@media' "$TMP/web_html" && ok "index.php tem CSS responsivo" || bad "sem media queries"
        grep -q 'backdrop-filter' "$TMP/web_html" && ok "index.php usa efeito de vidro (glass)" || bad "sem glass"
        n_help=$(grep -c 'help-btn' "$TMP/web_html")
        [ "$n_help" -ge 85 ] && ok "cada ação tem botão de ajuda ($n_help)" || bad "botões de ajuda: $n_help"
        # toda ação tem explicação para o usuário
        php -r 'require "'"$ROOT"'/web/lib.php"; $n=0;
                 foreach (otm_actions() as $a) { if (trim($a["help"] ?? "") === "") $n++; }
                 echo "sem_help=$n\n";' > "$TMP/web_help" 2>&1
        assert_contains "$TMP/web_help" "sem_help=0" "todas as ações têm explicação (help)"
        # novas categorias extremas e sem root estão no registro e no HTML
        # os ajustes que exigiam root (ext.gpu, ext.turbo...) saíram; sobram os sem root
        php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
                 $root=0; foreach ($a as $x) if (($x["risk"]??"")==="root") $root++;
                 echo isset($a["adv.obscure"])?"adv ":"", isset($a["ext.gpu"])?"gpu ":"",
                      isset($a["ext.turbo"])?"turbo ":"", "root=$root\n";' > "$TMP/web_ext" 2>&1
        assert_contains "$TMP/web_ext" "adv" "registro mantém os ajustes avançados sem root"
        assert_contains "$TMP/web_ext" "root=0" "nenhuma ação do painel exige root"
        # o modo extremo (root) saiu; as ações sem root seguem agrupadas em Desempenho
        php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
                 foreach (["adv.obscure","ext.display","ext.dexopt"] as $id)
                   echo (isset($a[$id]) && $a[$id]["group"]!==""?"ok ":"ERRO ");
                 echo "\n";' > "$TMP/web_cat" 2>&1
        assert_contains "$TMP/web_cat" "ok ok ok" "ajustes sem root agrupados corretamente"
        n_cards=$(grep -c 'class="card"' "$TMP/web_html")
        [ "$n_cards" -ge 110 ] && ok "index.php renderiza os cards novos ($n_cards)" \
            || bad "poucos cards renderizados ($n_cards)"
        # --- Sistema (configs), animações e verificação real ---
        assert_contains "$TMP/web_html" "Sistema" "index.php tem a categoria Sistema"
        grep -q '@keyframes' "$TMP/web_html" && ok "index.php tem animações (@keyframes)" || bad "sem animações"
        grep -q 'prefers-reduced-motion' "$TMP/web_html" && ok "respeita prefers-reduced-motion" || bad "sem prefers-reduced-motion"
        php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
                 echo isset($a["config.set"])?"set ":"", isset($a["config.test"])?"test\n":"";' \
            > "$TMP/web_cfg" 2>&1
        assert_contains "$TMP/web_cfg" "set test" "registro tem ações de Sistema (config)"
        # parse do resultado da verificação real
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $v=otm_parse_result("#OTM-RESULT tag=x applies=3 changed=2 failed=1 ok=1");
                 echo ((int)$v["applies"]===3 && (int)$v["changed"]===2 && (int)$v["failed"]===1) ? "PARSEOK":"PARSEBAD";' \
            > "$TMP/web_parse" 2>&1
        assert_contains "$TMP/web_parse" "PARSEOK" "otm_parse_result lê a linha #OTM-RESULT"
        # sem acesso, aplicar algo NÃO pode dizer que deu certo. Store limpo +
        # stubs que engolem settings E setprop: se o setprop real (ou um valor
        # velho no store) ainda aparecesse, o renderizador viraria um "changed"
        # solitário e mascararia a falha.
        mkdir -p "$TMP/bin_noop" "$TMP/store_noop"
        printf '#!/bin/sh\nexit 0\n' > "$TMP/bin_noop/settings"
        printf '#!/bin/sh\nexit 0\n' > "$TMP/bin_noop/setprop"
        chmod +x "$TMP/bin_noop/settings" "$TMP/bin_noop/setprop"
        TMP_STORE="$TMP/store_noop" PATH="$TMP/bin_noop:$PATH" OTM_MODE=local php -r 'require "'"$ROOT"'/web/lib.php";
                 $r=otm_run("perf",[],false);
                 echo (!empty($r["applied"]) && empty($r["real"])) ? "FALHA_REAL":"MASCARADO";' \
            > "$TMP/web_real" 2>&1
        assert_contains "$TMP/web_real" "FALHA_REAL" "sem acesso real, ação aplicadora vira erro (não mascara)"
        # Logs: histórico completo (log_all) devolve tudo, sem truncar
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $all = otm_log_all(); $recent = otm_log_read(1);
                 echo (count($all) >= count($recent)) ? "ALL_OK" : "ALL_BAD";' \
            > "$TMP/web_logall" 2>&1
        assert_contains "$TMP/web_logall" "ALL_OK" "otm_log_all devolve o histórico completo"
        # Terminal: comando cru roda e entra no log (comando seguro e inofensivo)
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $r = otm_run_command("echo otm-term-ok");
                 echo (strpos($r["out"], "otm-term-ok") !== false) ? "TERM_OK" : "TERM_BAD";' \
            > "$TMP/web_term" 2>&1
        assert_contains "$TMP/web_term" "TERM_OK" "otm_run_command executa o comando digitado"
        # Terminal recusa comando vazio
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $r = otm_run_command("   ");
                 echo ($r["ok"] === false) ? "VAZIO_OK" : "VAZIO_BAD";' \
            > "$TMP/web_termempty" 2>&1
        assert_contains "$TMP/web_termempty" "VAZIO_OK" "otm_run_command recusa comando vazio"
        # Terminal aparece no histórico (Logs) depois de rodar
        php -r 'require "'"$ROOT"'/web/lib.php";
                 otm_run_command("echo registra-no-log");
                 $hit = false;
                 foreach (otm_log_all() as $l) if (($l["id"] ?? "") === "terminal") $hit = true;
                 echo $hit ? "LOG_TERM" : "SEM_LOG";' \
            > "$TMP/web_termllog" 2>&1
        assert_contains "$TMP/web_termllog" "LOG_TERM" "Terminal registra a execução em Logs"
        # apps_meta: devolve uma lista (mesmo vazia) sem quebrar
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $m = otm_apps_meta();
                 echo is_array($m) ? "META_OK" : "META_BAD";' \
            > "$TMP/web_appsmeta" 2>&1
        assert_contains "$TMP/web_appsmeta" "META_OK" "otm_apps_meta devolve a lista de apps (nome/ícone)"
    else
        printf '  [skip] php ausente: pulei testes do painel web\n'
    fi
}

t_panel_v219() {
    printf '\n  # painel v2.19: refresh 60Hz, logs completos, terminal, seletor de apps\n'
    local src="$ROOT/app/src/main/java/com/otm/pack"
    local app="$ROOT/app/src/main/assets/panel/index.html"
    local lib="$ROOT/web/lib.php"
    local api="$ROOT/web/api.php"
    # taxa de atualização: escolha 60/90/120/auto e a home mostra a taxa de tela
    grep -q "'id' => 'refresh.60'" "$lib" && ok "registro tem 60Hz" || bad "registro sem 60Hz"
    grep -q "'id' => 'refresh.auto'" "$lib" && ok "registro tem refresh automático" || bad "registro sem automático"
    grep -q "state' => 'refresh_peak'" "$lib" && ok "escolha de refresh casa pela taxa travada" || bad "sem state refresh_peak"
    grep -q 'Taxa de tela' "$app" && ok "app: home mostra a taxa de tela" || bad "app: home sem taxa de tela"
    # Logs completos: ponte + api + painel
    grep -q '"log_all" -> logAllImpl()' "$src/PackBridge.kt" && ok "bridge: log_all (histórico completo)" || bad "bridge sem log_all"
    grep -q 'log_all' "$api" && ok "api.php: log_all" || bad "api.php sem log_all"
    grep -q 'id="logspanel"' "$app" && ok "app: painel de Logs" || bad "app sem painel de Logs"
    grep -q 'id="btnLogs"' "$app" && ok "app: botão Logs" || bad "app sem botão Logs"
    # Logs detalhados: dizem POR QUE falhou e guardam a saída crua (não só "erro")
    grep -q 'function otm_fail_reasons' "$lib" && ok "lib.php: extrai as razões da falha" || bad "log sem razões"
    grep -q "'reasons' =>" "$lib" && ok "lib.php: grava as razões no log" || bad "log sem campo reasons"
    grep -q "'out' => otm_clip" "$lib" && ok "lib.php: grava a saída crua (limitada)" || bad "log sem saída crua"
    grep -q 'function otm_log_trim' "$lib" && grep -q 'private fun trimLog' "$src/PackBridge.kt" \
        && ok "log: podado dos dois lados (não cresce sem fim)" || bad "log sem poda"
    grep -q 'private fun failReasons' "$src/PackBridge.kt" && ok "bridge: extrai as razões da falha" || bad "bridge sem razões"
    grep -q '.put("reasons", JSONArray(failReasons(out)))' "$src/PackBridge.kt" \
        && ok "bridge: grava as razões no log" || bad "bridge log sem reasons"
    grep -q 'has-det' "$app" && grep -q 'has-det' "$ROOT/web/index.php" \
        && ok "app+web: log abre os detalhes no toque" || bad "log sem detalhes"
    grep -q 'class="why"' "$app" && grep -q 'class="why"' "$ROOT/web/index.php" \
        && ok "app+web: log mostra a lista de razões" || bad "log sem lista de razões"
    # as duas pontes (PHP e Kotlin) gravam o MESMO formato de log
    for k in applies changed failed reasons out; do
        grep -q "'$k' =>" "$lib" && grep -q ".put(\"$k\"" "$src/PackBridge.kt" \
            || bad "log: campo $k não está nos dois lados"
    done
    ok "log: mesmo formato no PHP e no Kotlin"
    # Terminal real: ponte + api + painel
    grep -q '"term" -> termImpl(payload)' "$src/PackBridge.kt" && ok "bridge: terminal (term)" || bad "bridge sem term"
    grep -q 'private fun termImpl' "$src/PackBridge.kt" && ok "bridge: termImpl executa comando" || bad "bridge sem termImpl"
    grep -q "=== 'term'" "$api" && grep -q 'otm_run_command' "$api" && ok "api.php: endpoint do terminal" || bad "api.php sem terminal"
    grep -q 'function otm_run_command' "$lib" && ok "lib.php: otm_run_command" || bad "lib.php sem otm_run_command"
    grep -q 'id="termInput"' "$app" && ok "app: campo do terminal" || bad "app sem campo do terminal"
    # seletor de apps com nome + ícone (sem digitar pacote)
    grep -q '"apps_meta" -> appsMetaImpl()' "$src/PackBridge.kt" && ok "bridge: apps_meta (nome/ícone)" || bad "bridge sem apps_meta"
    grep -q 'getApplicationIcon' "$src/PackBridge.kt" && ok "bridge: pega o ícone do app (PackageManager)" || bad "bridge sem ícone"
    grep -q 'Base64' "$src/PackBridge.kt" && ok "bridge: ícone em base64 para o WebView" || bad "bridge sem base64"
    grep -q 'function otm_apps_meta' "$lib" && ok "lib.php: otm_apps_meta" || bad "lib.php sem otm_apps_meta"
    grep -q 'apps_meta' "$api" && ok "api.php: apps_meta" || bad "api.php sem apps_meta"
    grep -q 'data-apppick' "$app" && ok "app: seletor de apps (nome/ícone)" || bad "app sem seletor de apps"
    grep -q 'list="applist"' "$app" && bad "app: ainda pede pacote digitado" || ok "app: pacote não é digitado"
    # terminal do app executa via shell privilegiado (não por api.php)
    grep -q 'otm("term"' "$app" && ok "app: terminal usa a ponte nativa" || bad "app: terminal sem ponte"
}

t_keepalive() {
    printf '\n  # anti-relog: manter o app vivo (não relogar ao reabrir)\n'
    local f="$ROOT/scripts/keep-alive.sh"
    local app="$ROOT/app/src/main/assets/panel/actions.json"
    [ -f "$f" ] && ok "scripts/keep-alive.sh existe" || { bad "keep-alive.sh ausente"; return; }
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" > "$TMP/ka_help" 2>&1
    assert_contains "$TMP/ka_help" "relogar" "keep-alive explica o anti-relog sem argumento"
    # pacote inválido é recusado
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" on "pkg inválido" > "$TMP/ka_bad" 2>&1
    assert_contains "$TMP/ka_bad" "inválido" "keep-alive recusa pacote inválido"
    # sem privilégio de shell: avisa e NÃO aplica
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/ka_cmd.log"; : > "$TMP_CMD_LOG"
    export TMP_AM_LOG="$TMP/ka_cmd.log"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" on com.exemplo > "$TMP/ka_local" 2>&1
    grep -q 'permissão de shell' "$TMP/ka_local" && ok "keep-alive avisa sem shell" || bad "keep-alive sem aviso de shell"
    grep -q 'deviceidle whitelist' "$TMP_CMD_LOG" && bad "keep-alive aplicou sem shell" || ok "keep-alive não aplica sem shell"
    # com privilégio (root): aplica Doze, 2º plano, wake lock e standby
    rm -rf "$HOME/.packotm"
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" on com.exemplo > "$TMP/ka_on" 2>&1
    grep -q 'deviceidle whitelist +com.exemplo' "$TMP_CMD_LOG" && ok "keep-alive isenta do Doze" || bad "keep-alive sem isenção do Doze"
    grep -q 'RUN_IN_BACKGROUND allow' "$TMP_CMD_LOG" && ok "keep-alive libera 2º plano" || bad "keep-alive sem 2º plano"
    grep -q 'RUN_ANY_IN_BACKGROUND allow' "$TMP_CMD_LOG" && ok "keep-alive libera 2º plano sempre" || bad "keep-alive sem RUN_ANY"
    grep -q 'WAKE_LOCK allow' "$TMP_CMD_LOG" && ok "keep-alive libera wake lock" || bad "keep-alive sem wake lock"
    grep -q 'set-standby-bucket com.exemplo active' "$TMP_CMD_LOG" && ok "keep-alive põe no balde ativo" || bad "keep-alive sem balde ativo"
    grep -q 'failed=' "$TMP/ka_on" && ok "keep-alive emite o resultado (#OTM-RESULT)" || bad "keep-alive sem #OTM-RESULT"
    # lista de protegidos + status
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" list > "$TMP/ka_list" 2>&1
    assert_contains "$TMP/ka_list" "com.exemplo" "keep-alive lista o app protegido"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" status com.exemplo > "$TMP/ka_status" 2>&1
    assert_contains "$TMP/ka_status" "ANTI-RELOG" "keep-alive status mostra o resumo"
    # off remove da lista
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" off com.exemplo > "$TMP/ka_off" 2>&1
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" list > "$TMP/ka_list2" 2>&1
    grep -q 'com.exemplo' "$TMP/ka_list2" && bad "keep-alive off não removeu" || ok "keep-alive off remove da lista"
    # restore limpa tudo
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" on com.exemplo >/dev/null 2>&1
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" restore > "$TMP/ka_restore" 2>&1
    grep -q 'deviceidle whitelist -com.exemplo' "$TMP_CMD_LOG" && ok "keep-alive restore desfaz o Doze" || bad "keep-alive restore não desfez"
    # registro no painel + whitelist + catálogo do app
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["keep.on","keep.game","keep.off","keep.status","keep.list","keep.restore"] as $id)
               echo isset($a[$id]) ? "" : "FALTA:$id ";' > "$TMP/ka_reg" 2>&1
    test ! -s "$TMP/ka_reg" && ok "ações anti-relog no registro do painel" || bad "registro: $(cat "$TMP/ka_reg")"
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("keep-alive.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' > "$TMP/ka_lib" 2>&1
    assert_contains "$TMP/ka_lib" "ok" "keep-alive.sh na whitelist"
    grep -q '"keep-alive.sh"' "$app" && ok "app: actions.json tem o anti-relog" || bad "app: actions.json sem anti-relog"
    grep -q '"keep.on"' "$app" && ok "app: catálogo tem a ação keep.on" || bad "app: catálogo sem keep.on"
    rm -rf "$HOME/.packotm"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_gameclean() {
    printf '\n  # game clean: deixa o jogo limpo e otimizado\n'
    local f="$ROOT/scripts/game-clean.sh"
    local app="$ROOT/app/src/main/assets/panel/actions.json"
    [ -f "$f" ] && ok "scripts/game-clean.sh existe" || { bad "game-clean.sh ausente"; return; }
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" > "$TMP/gc_help" 2>&1
    assert_contains "$TMP/gc_help" "GAME CLEAN\|Game Clean" "game-clean explica o que faz sem argumento"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" on "pkg inválido" > "$TMP/gc_bad" 2>&1
    assert_contains "$TMP/gc_bad" "inválido" "game-clean recusa pacote inválido"
    # sem shell: avisa e não aplica
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/gc_cmd.log"; : > "$TMP_CMD_LOG"
    export TMP_AM_LOG="$TMP/gc_cmd.log"
    export TMP_PM_LOG="$TMP/gc_cmd.log"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" on com.exemplo > "$TMP/gc_local" 2>&1
    grep -q 'sem shell' "$TMP/gc_local" && ok "game-clean avisa sem shell" || bad "game-clean sem aviso de shell"
    # com privilégio (root): aplica limpeza, RAM, Game Mode, silêncio e telemetria
    rm -rf "$HOME/.packotm"; : > "$TMP_CMD_LOG"
    # estado inicial: notificações ligadas (o off deve restaurar isto)
    printf '1' > "$TMP_STORE/global.heads_up_notifications_enabled"
    printf '1' > "$TMP_STORE/global.notification_bubbles"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" on com.exemplo > "$TMP/gc_on" 2>&1
    assert_contains "$TMP_STORE/global.activity_manager_constants" "max_cached_processes=4" "game-clean põe a RAM no perfil gaming"
    assert_eq "4" "$(cat "$TMP_STORE/dc.activity_manager.max_cached_processes" 2>/dev/null)" \
        "game-clean escreve o limite de processos onde o Android 10+ lê (device_config)"
    grep -q 'deviceidle whitelist +com.exemplo' "$TMP_CMD_LOG" && ok "game-clean isenta o jogo do Doze" || bad "game-clean sem Doze"
    grep -q 'game set --mode performance com.exemplo' "$TMP_CMD_LOG" && ok "game-clean liga Game Mode performance" || bad "game-clean sem Game Mode"
    assert_contains "$TMP_STORE/global.game_driver_all_apps" "1" "game-clean liga o driver de jogo"
    assert_contains "$TMP_STORE/global.heads_up_notifications_enabled" "0" "game-clean silencia heads-up"
    assert_contains "$TMP_STORE/global.notification_bubbles" "0" "game-clean desliga bolhas"
    grep -q 'trim-caches' "$TMP_CMD_LOG" && ok "game-clean poda cache" || bad "game-clean sem trim"
    grep -q 'force-stop com.spotify.music' "$TMP_CMD_LOG" && bad "modo normal não devia matar mídia" || ok "modo normal poupa apps de mídia"
    assert_contains "$TMP/gc_on" "Game Clean pronto" "game-clean conclui com o resumo"
    # anti-relog entrou junto
    grep -qxF "com.exemplo" "$HOME/.packotm/keepalive/apps" && ok "game-clean protege o jogo (anti-relog)" || bad "game-clean não protegeu"
    # status lê de volta
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" status com.exemplo > "$TMP/gc_status" 2>&1
    assert_contains "$TMP/gc_status" "GAME CLEAN" "game-clean status mostra o resumo"
    assert_contains "$TMP/gc_status" "com.exemplo" "game-clean status mostra o jogo"
    # modo máximo encerra mídia/chat conhecidos
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" on com.exemplo max > "$TMP/gc_max" 2>&1
    grep -q 'force-stop com.spotify.music' "$TMP_CMD_LOG" && ok "game-clean máximo encerra apps de mídia" || bad "game-clean máximo não encerrou mídia"
    # off desfaz (notificações voltam, anti-relog sai)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" off com.exemplo > "$TMP/gc_off" 2>&1
    assert_contains "$TMP_STORE/global.heads_up_notifications_enabled" "1" "game-clean off religa notificações"
    grep -q 'game set --mode standard com.exemplo' "$TMP_CMD_LOG" && ok "game-clean off tira o Game Mode" || bad "game-clean off manteve Game Mode"
    grep -qxF "com.exemplo" "$HOME/.packotm/keepalive/apps" && bad "game-clean off não removeu o anti-relog" || ok "game-clean off remove o anti-relog"
    # registro no painel + whitelist + catálogo do app
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["clean.normal","clean.max","clean.off","clean.status"] as $id)
               echo isset($a[$id]) ? "" : "FALTA:$id ";' > "$TMP/gc_reg" 2>&1
    test ! -s "$TMP/gc_reg" && ok "ações do Game Clean no registro do painel" || bad "registro: $(cat "$TMP/gc_reg")"
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("game-clean.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' > "$TMP/gc_lib" 2>&1
    assert_contains "$TMP/gc_lib" "ok" "game-clean.sh na whitelist"
    php -r 'require "'"$ROOT"'/web/lib.php"; echo isset(otm_choices()["gameclean"]) ? "ok":"falta";' > "$TMP/gc_ch" 2>&1
    assert_contains "$TMP/gc_ch" "ok" "grupo de escolha gameclean declarado"
    grep -q '"game-clean.sh"' "$app" && ok "app: actions.json tem o Game Clean" || bad "app: actions.json sem Game Clean"
    grep -q '"clean.normal"' "$app" && ok "app: catálogo tem a ação clean.normal" || bad "app: catálogo sem clean.normal"
    rm -rf "$HOME/.packotm"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_smart_opt() {
    printf '\n  # otimizador inteligente: lê o aparelho, decide e aplica sob medida\n'
    local f="$ROOT/scripts/smart-opt.sh"
    [ -f "$f" ] && ok "scripts/smart-opt.sh existe" || { bad "smart-opt.sh ausente"; return; }
    # sem argumento: explica o que faz
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" > "$TMP/so_help" 2>&1
    assert_contains "$TMP/so_help" "Otimizador Inteligente" "smart-opt se apresenta sem argumento"
    # perfil inválido é recusado
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" plan bogus > "$TMP/so_bad" 2>&1
    assert_contains "$TMP/so_bad" "inválido" "smart-opt recusa perfil inválido"
    # analyze: lê o aparelho de verdade e NÃO altera nada
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/so.log" TMP_AM_LOG="$TMP/so.log"; : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" analyze > "$TMP/so_an" 2>&1
    assert_contains "$TMP/so_an" "nota" "analyze mostra a nota do aparelho"
    assert_contains "$TMP/so_an" "classe" "analyze mostra a classe do aparelho"
    assert_contains "$TMP/so_an" "RAM" "analyze mostra a RAM"
    grep -q 'settings put\|am set\|appops' "$TMP_CMD_LOG" \
        && bad "analyze alterou o sistema (devia ser só leitura)" \
        || ok "analyze não altera nada (só leitura)"
    # a classificação reage ao aparelho: RAM maior => nota não menor
    r1="$(OTM_NO_COLOR=1 OTM_MODE=su sh "$f" analyze 2>&1 | awk '/nota/{print $2}' | tr -cd '0-9')"
    case "$r1" in ''|*[!0-9]*) bad "nota do aparelho não é numérica ($r1)" ;; *) ok "nota numérica ($r1/100)" ;; esac
    # plan: explica as decisões, ainda sem alterar
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" plan desempenho > "$TMP/so_plan" 2>&1
    assert_contains "$TMP/so_plan" "PLANO DO OTIMIZADOR" "plan mostra o plano"
    assert_contains "$TMP/so_plan" "renderizador" "plan explica o renderizador escolhido"
    assert_contains "$TMP/so_plan" "RAM em cache" "plan explica a RAM escolhida"
    assert_contains "$TMP/so_plan" "taxa de tela" "plan explica a taxa de tela"
    grep -q 'settings put\|am set' "$TMP_CMD_LOG" \
        && bad "plan alterou o sistema (devia ser só leitura)" \
        || ok "plan não altera nada (só leitura)"
    # perfis diferentes => decisões diferentes (deixa de ser "um pacote para todos")
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" plan bateria > "$TMP/so_bat" 2>&1
    assert_contains "$TMP/so_bat" "60 Hz" "perfil bateria trava a tela em 60Hz"
    mkdir -p "$HOME/.packotm/game"; echo "com.dts.freefireth" > "$HOME/.packotm/game/pkg"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" plan jogo > "$TMP/so_jogo" 2>&1
    assert_contains "$TMP/so_jogo" "4 apps" "perfil jogo limita a 4 apps em cache"
    assert_contains "$TMP/so_jogo" "anti-relog" "perfil jogo menciona o anti-relog"
    rm -rf "$HOME/.packotm/game"
    # apply: aplica de verdade (delega aos módulos) e confirma mudança
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/so2.log" TMP_AM_LOG="$TMP/so2.log"; : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply equilibrado > "$TMP/so_ap" 2>&1
    assert_contains "$TMP/so_ap" "otimização aplicada" "apply conclui e avisa"
    assert_eq "equilibrado" "$(cat "$HOME/.packotm/smart/last" 2>/dev/null)" "apply grava o perfil aplicado"
    [ -n "$(cat "$TMP_STORE/global.window_animation_scale" 2>/dev/null)" ] \
        && ok "apply mexeu nas animações (base de performance)" || bad "apply não aplicou a base"
    assert_contains "$TMP_STORE/global.activity_manager_constants" "max_cached_processes" \
        "apply ajustou a RAM (activity_manager_constants)"
    # as mudanças contam como reais para o painel (applies>0 e changed>0)
    grep -q 'applies=0' "$TMP/so_ap" && bad "apply não contou nenhuma tentativa" \
        || ok "apply reporta mudanças ao painel"
    # status: mostra o que foi aplicado
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" status > "$TMP/so_st" 2>&1
    assert_contains "$TMP/so_st" "perfil aplicado" "status mostra o perfil aplicado"
    assert_contains "$TMP/so_st" "equilibrado" "status mostra o perfil correto"
    # restore: desfaz e limpa o marcador
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" restore > "$TMP/so_rs" 2>&1
    assert_contains "$TMP/so_rs" "original" "restore avisa que voltou ao original"
    [ -f "$HOME/.packotm/smart/last" ] && bad "restore não limpou o perfil" \
        || ok "restore limpa o perfil aplicado"
    # auto: o comando unico faz analise + aplicacao numa tacada
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/so3.log" TMP_AM_LOG="$TMP/so3.log"; : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" auto > "$TMP/so_auto1" 2>&1
    assert_contains "$TMP/so_auto1" "análise" "auto comeca pela analise do aparelho"
    assert_contains "$TMP/so_auto1" "nota" "auto mostra a nota"
    # auto = analisa, aplica E mede antes/depois (o resultado tem de aparecer)
    assert_contains "$TMP/so_auto1" "TESTE DE DESEMPENHO" "auto roda o teste de desempenho"
    assert_contains "$TMP/so_auto1" "resultado:" "auto diz se melhorou, piorou ou ficou estável"
    [ -n "$(cat "$HOME/.packotm/smart/last" 2>/dev/null)" ] \
        && ok "auto grava o perfil aplicado" || bad "auto nao gravou o perfil"
    # a escolha do jogo muda o perfil automático para "jogo"
    mkdir -p "$HOME/.packotm/game"; echo "com.dts.freefireth" > "$HOME/.packotm/game/pkg"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" plan auto > "$TMP/so_auto" 2>&1
    assert_contains "$TMP/so_auto" "(perfil jogo)" "com jogo escolhido, o perfil auto vira jogo"
    # registro no painel + whitelist + catálogo do app
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             echo isset($a["smart.auto"]) ? "" : "FALTA:smart.auto";' > "$TMP/so_reg" 2>&1
    test ! -s "$TMP/so_reg" && ok "otimizador no registro do painel (acao unica)" || bad "registro: $(cat "$TMP/so_reg")"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["smart.analyze","smart.plan","smart.apply","smart.status"] as $id)
               if (isset($a[$id])) echo "SOBROU:$id ";' > "$TMP/so_reg2" 2>&1
    test ! -s "$TMP/so_reg2" && ok "as 4 acoes antigas sairam do registro" || bad "sobraram: $(cat "$TMP/so_reg2")"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_action("smart.auto");
             echo $a["argv"][0]." ".$a["argv"][1];' > "$TMP/so_arg" 2>&1
    assert_contains "$TMP/so_arg" "smart-opt.sh auto" "a acao unica roda o comando auto"
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("smart-opt.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' > "$TMP/so_lib" 2>&1
    assert_contains "$TMP/so_lib" "ok" "smart-opt.sh na whitelist"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_action("smart.auto");
             echo ($a && ($a["risk"]??"")==="careful" && !empty($a["confirm"])) ? "cuidado" : "?";' \
        > "$TMP/so_risk" 2>&1
    assert_contains "$TMP/so_risk" "cuidado" "aplicar o otimizador é 'cuidado' e pede confirmação"
    grep -q '"smart.auto"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o otimizador" || bad "app: actions.json sem o otimizador"
    grep -q 'data-id="smart.auto"' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "app: card do otimizador no painel" || bad "app: painel sem o card do otimizador"
    # o painel do app precisa do objeto ACTIONS com a ação nova (senão o card fica mudo)
    grep -q '"smart.auto"' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "app: ACTIONS embutido tem o otimizador" || bad "app: ACTIONS sem o otimizador"
    # nome único pedido: "Otimizador inteligente" (sem sufixo de sub-ação)
    grep -q '<h3>Otimizador inteligente</h3>' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "app: nome unico \"Otimizador inteligente\"" || bad "app: nome do card mudou"
    grep -q 'data-qa="smart.auto"' "$ROOT/app/src/main/assets/panel/index.html" \
        && grep -q 'data-qa="smart.auto"' "$ROOT/web/index.php" \
        && ok "botao unico na Home dos dois paineis" || bad "botao da Home divergiu"
    # o script novo precisa estar no espelho do app
    [ -f "$ROOT/app/src/main/assets/pack/scripts/smart-opt.sh" ] \
        && ok "espelho: smart-opt.sh presente" || bad "espelho: smart-opt.sh ausente"
    # pack.sh delega
    OTM_NO_COLOR=1 OTM_MODE=local sh "$ROOT/scripts/pack.sh" smart plan auto > "$TMP/so_pack" 2>&1
    assert_contains "$TMP/so_pack" "PLANO DO OTIMIZADOR" "pack.sh delega para smart-opt.sh"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$ROOT/scripts/pack.sh" smart > "$TMP/so_pack2" 2>&1
    assert_contains "$TMP/so_pack2" "OTIMIZADOR INTELIGENTE" "pack.sh smart (sem arg) faz tudo"
    # --- leituras novas: o otimizador decide também pelo estado ATUAL ---
    assert_contains "$TMP/so_an" "RAM livre" "analyze mostra a RAM livre agora"
    grep -q 'dumpsys thermalservice' "$f" \
        && ok "coleta o throttling térmico (dumpsys thermalservice)" || bad "sem leitura do estado térmico"
    grep -q 'settings get global low_power' "$f" \
        && ok "coleta o estado da economia de energia" || bad "sem leitura da economia de energia"
    # --- v2: análise mais profunda, rigor, medição e comparação ---
    for leitura in 'proc/pressure/memory' 'vm.swappiness' 'wm density' \
                   'cpufreq' 'Features'; do
        grep -q "$leitura" "$f" && ok "v2: lê $leitura" || bad "v2: sem leitura de $leitura"
    done
    # os pontos fracos do aparelho aparecem no relatório (o que segura a nota)
    grep -q 'SO_WEAK' "$f" && ok "v2: aponta os pontos fracos do aparelho" \
        || bad "v2: sem pontos fracos"
    # medição: existe a nota de desempenho e ela normaliza pelo que foi lido
    grep -q 'so_measure()' "$f" && ok "v2: tem medição de desempenho" || bad "v2: sem medição"
    grep -q 'so_measure_avg()' "$f" && ok "v2: mede 3× e tira a média" || bad "v2: sem média"
    # bench: mede antes x depois e diz o resultado
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" bench equilibrado > "$TMP/so_bench" 2>&1
    assert_contains "$TMP/so_bench" "TESTE DE DESEMPENHO" "bench anuncia o teste"
    assert_contains "$TMP/so_bench" "antes" "bench mostra a medição de antes"
    assert_contains "$TMP/so_bench" "depois" "bench mostra a medição de depois"
    assert_contains "$TMP/so_bench" "resultado:" "bench conclui o resultado"
    [ -s "$HOME/.packotm/smart/bench" ] && ok "bench guarda a medição" || bad "bench não guardou"
    # compare: testa combinações e declara o vencedor
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" compare desempenho > "$TMP/so_cmp" 2>&1
    assert_contains "$TMP/so_cmp" "COMPARANDO COMBINA" "compare anuncia a comparação"
    assert_contains "$TMP/so_cmp" "testando" "compare testa mais de um caminho"
    assert_contains "$TMP/so_cmp" "vencedor" "compare declara o vencedor"
    # rigor: perfil inválido é recusado no bench/compare também
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" bench bogus > "$TMP/so_bad2" 2>&1
    assert_contains "$TMP/so_bad2" "inválido" "bench recusa perfil inválido"
    # o apply continua confirmando cada ajuste (leitura de volta)
    grep -q 'so_verify' "$f" && ok "v2: apply confirma cada ajuste lendo de volta" \
        || bad "v2: apply não confirma"
    # a memória do kernel é ajustada com verificação (otm_sysctl lê de volta)
    grep -q 'otm_sysctl vm.swappiness' "$f" \
        && ok "v2: ajusta vm.swappiness conforme a RAM" || bad "v2: sem vm.swappiness"
    grep -q 'otm_ram_livre_mb' "$f" \
        && ok "coleta a RAM realmente livre (otm_ram_livre_mb)" || bad "sem leitura da RAM livre"
    # com o aparelho apertado, a decisão muda (menos apps em cache, limpeza funda)
    grep -q 'D_APERTADO' "$f" \
        && ok "decide pela pressão de memória (D_APERTADO)" || bad "sem decisão por pressão de memória"
    grep -q 'D_THERMAL=cautela' "$f" && grep -q '2|3|4|5) D_THERMAL=cautela' "$f" \
        && ok "cautela térmica também pelo throttling atual" || bad "cautela térmica só por SoC"
    grep -q 'PSAVER' "$f" \
        && ok "respeita a economia de energia já ligada" || bad "ignora a economia de energia ligada"
    rm -rf "$HOME/.packotm"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_smart_bigdump() {
    printf '\n  # dumpsys grande (Samsung) não pode estourar o argv nem colar a bateria\n'
    local f="$ROOT/scripts/smart-opt.sh"
    local bin="$TMP/bin_big" st="$TMP/store_big"
    rm -rf "$bin" "$st"; mkdir -p "$bin" "$st"
    # `dumpsys display` passa de 380 KB (o caso real do SM-A075M) e o battery traz
    # uma linha " level:" por UID, como no Android 14+. O dump grande ia como
    # ARGUMENTO do printf externo (toybox) e morria com E2BIG.
    cat > "$bin/dumpsys" <<'EOF'
#!/bin/sh
case "$1" in
display)
  i=0
  while [ $i -lt 5000 ]; do
    echo "  DisplayDeviceInfo$i: fps=120.0 modeId=$i padding padding padding padding"
    i=$((i + 1))
  done
  ;;
battery)
  echo "  AC powered: false"
  # o dump real traz uma linha " level: NN" por UID/consumidor (dezenas delas).
  # O awk sem `exit` imprimia TODAS e o _num colava os dígitos num número só —
  # era o "lixo" de centenas de dígitos na linha da bateria.
  i=0
  while [ $i -lt 40 ]; do
    echo "  uid $i level: 8$((i % 10))"
    i=$((i + 1))
  done
  echo "  level: 85"
  echo "  temperature: 300"
  ;;
*) echo "" ;;
esac
exit 0
EOF
    chmod +x "$bin/dumpsys"
    out="$(TMP_STORE="$st" PATH="$bin:$PATH" OTM_NO_COLOR=1 OTM_MODE=local \
        sh "$f" analyze 2>&1)"
    # o dump tem de ser grande o bastante para estourar o limite de argv
    [ "$("$bin/dumpsys" display | wc -c)" -gt 131072 ] \
        && ok "cenário: dumpsys display acima do limite de argv" \
        || bad "cenário de teste fraco (dump pequeno)"
    # o caminho seguro é o stdin (otm_echo): um argumento de 400 KB estoura o
    # limite do kernel no Android, onde printf/sed/grep são binários (toybox).
    # Aqui o `sh` do PC tem printf builtin e não reproduz o E2BIG, então o teste
    # prova o MECANISMO: o texto grande tem de sair inteiro pelo otm_echo.
    big="$(python3 -c 'print("x" * 400000)')"
    n="$(. "$ROOT/scripts/common.sh" 2>/dev/null; otm_echo "$big" | wc -c)"
    [ "$n" -ge 400000 ] \
        && ok "otm_echo entrega 400 KB pelo stdin (sem passar por argv)" \
        || bad "otm_echo truncou o texto grande ($n bytes)"
    # e a leitura da taxa de tela NÃO pode mandar o dump como argumento
    grep -q "printf '%s\\\\n' \"\$out\"" "$f" \
        && bad "display_max_hz ainda passa o dump como argumento" \
        || ok "display_max_hz não passa o dump como argumento"
    printf '%s\n' "$out" | grep -q 'Argument list too long' \
        && bad "o dump grande foi passado como argumento (E2BIG)" \
        || ok "dump grande não vai mais como argumento (sem E2BIG)"
    # a taxa de tela volta a ser lida (era o efeito prático do E2BIG)
    printf '%s\n' "$out" | grep -q '120 Hz suportado' \
        && ok "lê a taxa de tela com dump grande (120 Hz)" \
        || bad "não leu a taxa de tela: $(printf '%s\n' "$out" | grep 'tela ')"
    # a bateria é um número só (não os dígitos de todas as linhas colados)
    printf '%s\n' "$out" | grep -q 'bateria *85%' \
        && ok "bateria correta com várias linhas ' level:' (85%)" \
        || bad "bateria errada: $(printf '%s\n' "$out" | grep 'bateria ')"
    # e o valor gigante colado não aparece em lugar nenhum
    printf '%s\n' "$out" | grep -qE 'bateria[^0-9]*[0-9]{4,}' \
        && bad "a bateria ainda vem com dígitos colados" \
        || ok "sem número gigante de bateria"
    # a temperatura (mesmo padrão multi-linha) também vem de uma linha só
    grep -q "otm_batt_get temperature" "$ROOT/scripts/common.sh" \
        && ok "temperatura lê a linha canônica (otm_batt_get)" \
        || bad "temperatura ainda soma as linhas"
    rm -rf "$bin" "$st"
}

t_smart_learning() {
    printf '\n  # otimizador que APRENDE: memória por aparelho e ciclo completo\n'
    local f="$ROOT/scripts/smart-opt.sh"
    # a memória existe e é por assinatura de hardware (não global)
    grep -q 'SO_MEM=' "$f" && ok "v3: existe memória do aparelho (SO_MEM)" || bad "v3: sem memória"
    grep -q 'so_mem_key()' "$f" && ok "v3: memória tem chave por hardware" || bad "v3: sem chave de memória"
    grep -q 'so_mem_get()' "$f" && grep -q 'so_mem_set()' "$f" \
        && ok "v3: memória tem leitura e escrita" || bad "v3: memória incompleta"
    # decide() consulta a memória (é o que faz ele aprender de verdade)
    grep -q 'D_MEM_RENDER="$(so_mem_get renderer)"' "$f" \
        && ok "v3: decide usa o renderizador que venceu aqui" || bad "v3: decide ignora a memória (renderer)"
    grep -q 'D_MEM_HZ="$(so_mem_get hz)"' "$f" \
        && ok "v3: decide usa a taxa de tela que venceu aqui" || bad "v3: decide ignora a memória (hz)"
    # compare grava na memória (fecha o ciclo do aprendizado)
    grep -q 'so_mem_set renderer' "$f" && grep -q 'so_mem_set hz' "$f" \
        && ok "v3: compare grava o vencedor na memória" || bad "v3: compare não grava na memória"
    # auto = ciclo completo, com snapshot de segurança e resumo único
    grep -q 'snapshot.sh" save' "$f" \
        && ok "v3: auto tira snapshot de segurança antes" || bad "v3: auto sem snapshot de segurança"
    grep -q 'RESULTADO FINAL' "$f" && ok "v3: auto mostra UM resultado no fim" || bad "v3: auto sem resumo final"
    grep -q 'cmd_compare "$prof"' "$f" && ok "v3: auto testa as combinações" || bad "v3: auto não compara"

    # comportamento REAL: o auto grava a memória e o `mem` mostra o que aprendeu
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" auto > "$TMP/so_auto_mem" 2>&1
    [ -f "$HOME/.packotm/smart/memory" ] && ok "v3: auto grava a memória do aparelho" \
        || bad "v3: auto não gravou a memória"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" mem > "$TMP/so_mem" 2>&1
    assert_contains "$TMP/so_mem" "APRENDEU" "v3: 'mem' mostra o que ele aprendeu"
    assert_contains "$TMP/so_mem" "melhor renderizador" "v3: 'mem' mostra o renderizador vencedor"
    assert_contains "$TMP/so_mem" "vezes que rodou aqui" "v3: 'mem' conta as execuções"

    # a chave da assinatura sai do próprio arquivo (sem adivinhar o formato)
    k="$(sed -n 's/^\([^ ]*\) runs=.*/\1/p' "$HOME/.packotm/smart/memory" | head -1)"
    if [ -n "$k" ]; then
        # a memória MUDA a decisão. O valor tem de ser DIFERENTE do padrão, senão
        # o teste passaria mesmo sem a memória (no harness a GPU não é lida e o
        # padrão já é skiagl — por isso aqui o vencedor é skiavk).
        printf '%s renderer=skiavk\n%s hz=90\n' "$k" "$k" > "$HOME/.packotm/smart/memory"
        OTM_NO_COLOR=1 OTM_MODE=su sh "$f" plan > "$TMP/so_memplan" 2>&1
        assert_contains "$TMP/so_memplan" "skiavk" "v3: o plano começa pelo renderizador que venceu aqui"
        assert_contains "$TMP/so_memplan" "90 Hz" "v3: o plano começa pela taxa que venceu aqui"
        # 'mem' mostra a taxa que venceu (só aparece depois de haver uma medida)
        OTM_NO_COLOR=1 OTM_MODE=su sh "$f" mem > "$TMP/so_mem2" 2>&1
        assert_contains "$TMP/so_mem2" "melhor taxa de tela" "v3: 'mem' mostra a taxa vencedora"
        # a memória de OUTRO aparelho não é herdada (chave diferente)
        printf 'OUTRO|APARELHO|99999|0|0 renderer=skiavk\nOUTRO|APARELHO|99999|0|0 hz=90\n' \
            > "$HOME/.packotm/smart/memory"
        OTM_NO_COLOR=1 OTM_MODE=su sh "$f" plan > "$TMP/so_other" 2>&1
        grep -q 'skiavk' "$TMP/so_other" && bad "v3: herdou memória de outro aparelho" \
            || ok "v3: memória de outro aparelho não é herdada"
        OTM_NO_COLOR=1 OTM_MODE=su sh "$f" mem > "$TMP/so_mem3" 2>&1
        assert_contains "$TMP/so_mem3" "ainda não testei" "v3: 'mem' avisa quando não há nada aprendido aqui"
    else
        bad "v3: não consegui ler a chave de memória do arquivo"
    fi
    # o resumo final sai com o vencedor
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" auto > "$TMP/so_full" 2>&1
    assert_contains "$TMP/so_full" "RESULTADO FINAL" "v3: auto termina com o resultado final"
    assert_contains "$TMP/so_full" "config aplicada" "v3: o resultado diz o que ficou aplicado"
    [ -f "$HOME/.packotm/smart/memory" ] && ok "v3: auto grava a memória do aparelho" \
        || bad "v3: auto não gravou a memória"
    rm -rf "$HOME/.packotm"
}

t_backup_crypto() {
    printf '\n  # backup: arquivo cifrado que devolve as configurações\n'
    local f="$ROOT/scripts/backup.sh"
    [ -f "$f" ] && ok "scripts/backup.sh existe" || { bad "backup.sh ausente"; return; }
    sh -n "$f" 2>/dev/null && ok "backup.sh tem sintaxe válida" || bad "backup.sh com erro de sintaxe"

    # ida e volta REAL: coleta, mexe no aparelho e restaura
    rm -rf "$HOME/.packotm"
    settings put global window_animation_scale 0.5
    settings put global force_gpu_rendering 1
    settings put system peak_refresh_rate 120.0
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" collect > "$TMP/bk_pack" 2>&1
    assert_contains "$TMP/bk_pack" "#TRIX-BACKUP-V1" "collect assina o pacote"
    assert_contains "$TMP/bk_pack" "global window_animation_scale 0.5" "collect guarda a animação atual"
    assert_contains "$TMP/bk_pack" "system peak_refresh_rate 120.0" "collect guarda a taxa de tela"

    # o otimizador mexe em tudo
    settings put global window_animation_scale 0
    settings put global force_gpu_rendering 0
    settings put system peak_refresh_rate 60.0
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" restore "$TMP/bk_pack" > "$TMP/bk_res" 2>&1
    assert_eq "0.5" "$(settings get global window_animation_scale)" "restore devolve a animação"
    assert_eq "1" "$(settings get global force_gpu_rendering)" "restore devolve o force gpu"
    assert_eq "120.0" "$(settings get system peak_refresh_rate)" "restore devolve a taxa de tela"

    # arquivo que não é backup é recusado (não aplica lixo)
    echo "isto nao e um backup" > "$TMP/bk_fake"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" restore "$TMP/bk_fake" > "$TMP/bk_bad" 2>&1
    assert_contains "$TMP/bk_bad" "não é um backup" "restore recusa arquivo alheio"
    # arquivo inexistente também é recusado com recado claro
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" restore "$TMP/nao_existe" > "$TMP/bk_miss" 2>&1
    assert_contains "$TMP/bk_miss" "não encontrado" "restore avisa quando o arquivo não existe"

    # o núcleo de criptografia do app: envelope, IV novo, adulteração detectada
    local core="$ROOT/app/src/main/java/com/otm/pack/OtmBackupCore.kt"
    [ -f "$core" ] && ok "app: OtmBackupCore.kt existe" || bad "app: sem núcleo de criptografia"
    grep -q 'AES/GCM/NoPadding' "$core" && ok "app: usa AES-GCM (cifra + autentica)" \
        || bad "app: cifra não é GCM"
    grep -q 'SecureRandom' "$core" && ok "app: IV aleatório (não reaproveita)" || bad "app: IV fixo"
    grep -q 'AndroidKeyStore' "$ROOT/app/src/main/java/com/otm/pack/OtmBackup.kt" \
        && ok "app: a chave vive no Keystore (não sai do aparelho)" || bad "app: chave fora do Keystore"
    # e o mesmo formato existe no lado web
    grep -q 'aes-256-gcm' "$ROOT/web/backup.php" && ok "web: cifra com aes-256-gcm" || bad "web: sem GCM"
    grep -q 'OTM_BKP_HEADER' "$ROOT/web/backup.php" && grep -q 'TRIX BACKUP' "$core" \
        && ok "web e app usam o mesmo envelope" || bad "envelopes divergem"

    # as ações de backup existem nos dois painéis e na whitelist
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["backup.export","backup.import","backup.list"] as $id)
               echo isset($a[$id]) ? "" : "FALTA:$id ";' > "$TMP/bk_reg" 2>&1
    test ! -s "$TMP/bk_reg" && ok "ações de backup no registro do painel" || bad "registro: $(cat "$TMP/bk_reg")"
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("backup.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' > "$TMP/bk_lib" 2>&1
    assert_contains "$TMP/bk_lib" "ok" "backup.sh na whitelist"
    grep -q '"backup.export"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o backup" || bad "app: actions.json sem backup"
    grep -q 'data-hub="backup.export"' "$ROOT/app/src/main/assets/panel/index.html" \
        && grep -q 'data-hub="backup.export"' "$ROOT/web/index.php" \
        && ok "botões de backup nos dois painéis" || bad "botões de backup divergem"
    [ -f "$ROOT/app/src/main/assets/pack/scripts/backup.sh" ] \
        && ok "espelho: backup.sh presente" || bad "espelho: backup.sh ausente"
    # a ponte do app liga os botões ao código nativo (não a script)
    grep -q '"backup_export"' "$ROOT/app/src/main/java/com/otm/pack/PackBridge.kt" \
        && ok "app: a ponte atende o backup" || bad "app: ponte sem backup"
    rm -rf "$HOME/.packotm"
}

t_smart_card_single() {
    printf '\n  # card do otimizador: UM botão (sem hub de sub-ações)\n'
    local web="$ROOT/web/index.php" panel="$ROOT/app/src/main/assets/panel/index.html"
    # o hub com os 11 botões internos saiu
    for f in "$web" "$panel"; do
        n=$(grep -c 'data-hub="smart\.' "$f")
        [ "$n" = "0" ] && ok "$(basename "$f"): sem sub-ações do otimizador" \
            || bad "$(basename "$f"): ainda tem $n sub-ações do otimizador"
        # o select de perfil do card saiu (o app decide sozinho)
        grep -q 'data-p="perfil"' "$f" \
            && bad "$(basename "$f"): ainda tem select de perfil" \
            || ok "$(basename "$f"): sem select de perfil (decide sozinho)"
        # os botões de segurança ficaram
        grep -q 'data-hub="backup.export"' "$f" && grep -q 'data-hub="backup.import"' "$f" \
            && ok "$(basename "$f"): salvar/restaurar presentes" || bad "$(basename "$f"): sem backup"
        # e o aviso de que pode demorar
        grep -q 'demorar' "$f" && ok "$(basename "$f"): avisa que pode demorar" \
            || bad "$(basename "$f"): sem aviso de demora"
    done
    # a ação virou comando único, com confirmação e 'cuidado'
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_action("smart.auto");
             echo count($a["params"])===0 ? "semparams" : "temparams";' > "$TMP/sc_p" 2>&1
    assert_contains "$TMP/sc_p" "semparams" "a ação não pede mais parâmetro (um botão só)"

    # rede de segurança: as ações de recuperação precisam de botão nos DOIS
    # painéis. Ao remover o hub do otimizador, "Reverter TUDO" e o snapshot
    # ficaram sem nenhum botão — o usuário perdeu como desfazer.
    for id in restore_all snapshot_save backup.export backup.import; do
        if grep -q "data-hub=\"$id\"\|data-qa=\"$id\"" "$web" \
           && grep -q "data-hub=\"$id\"\|data-qa=\"$id\"" "$panel"; then
            ok "recuperação alcançável nos dois painéis: $id"
        else
            bad "ação de recuperação sem botão: $id"
        fi
    done
}

t_ramboost() {
    printf '\n  # liberar RAM: encerra o fundo, poda cache e reporta o ganho\n'
    local f="$ROOT/scripts/ram-boost.sh"
    [ -f "$f" ] && ok "scripts/ram-boost.sh existe" || { bad "ram-boost.sh ausente"; return; }
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" > "$TMP/rb_help" 2>&1
    assert_contains "$TMP/rb_help" "LIBERAR RAM\|ram-boost" "ram-boost explica o que faz sem argumento"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" boost bogus > "$TMP/rb_bad" 2>&1
    assert_contains "$TMP/rb_bad" "inválido" "ram-boost recusa modo inválido"
    # sem shell: recusa
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" boost >/dev/null 2>&1
    assert_eq "1" "$?" "ram-boost sem shell é recusado"
    # com root: encerra apps de 3º plano, poda cache e mostra o ganho
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/rb.log" TMP_AM_LOG="$TMP/rb.log" TMP_PM_LOG="$TMP/rb.log"
    : > "$TMP_CMD_LOG"
    # protege um app no anti-relog: ele NÃO pode ser encerrado
    mkdir -p "$HOME/.packotm/keepalive"; echo "com.instagram.android" > "$HOME/.packotm/keepalive/apps"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" boost normal > "$TMP/rb_on" 2>&1
    grep -q 'force-stop com.whatsapp' "$TMP_CMD_LOG" && ok "ram-boost encerra apps de fundo" || bad "ram-boost não encerrou o fundo"
    grep -q 'force-stop com.instagram.android' "$TMP_CMD_LOG" && bad "ram-boost matou um protegido" || ok "ram-boost poupa os protegidos no anti-relog"
    grep -q 'trim-caches' "$TMP_CMD_LOG" && ok "ram-boost poda o cache" || bad "ram-boost sem trim-caches"
    grep -q 'force-stop com.spotify.music' "$TMP_CMD_LOG" && bad "modo normal não devia matar mídia" || ok "modo normal poupa apps de mídia"
    assert_contains "$TMP/rb_on" "RAM livre" "ram-boost mostra a RAM livre"
    # modo máximo encerra mídia conhecida
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" boost max > "$TMP/rb_max" 2>&1
    grep -q 'force-stop com.spotify.music' "$TMP_CMD_LOG" && ok "ram-boost máximo encerra mídia" || bad "ram-boost máximo não encerrou mídia"
    # status mostra o protegido
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" status > "$TMP/rb_st" 2>&1
    assert_contains "$TMP/rb_st" "RAM" "ram-boost status mostra a RAM"
    assert_contains "$TMP/rb_st" "com.instagram.android" "ram-boost status lista os protegidos"
    # registro no painel + whitelist + catálogo
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["ram.normal","ram.max","ram.status"] as $id) echo isset($a[$id]) ? "" : "FALTA:$id ";' \
        > "$TMP/rb_reg" 2>&1
    test ! -s "$TMP/rb_reg" && ok "ações de RAM no registro do painel" || bad "registro: $(cat "$TMP/rb_reg")"
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("ram-boost.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' > "$TMP/rb_lib" 2>&1
    assert_contains "$TMP/rb_lib" "ok" "ram-boost.sh na whitelist"
    php -r 'require "'"$ROOT"'/web/lib.php"; echo isset(otm_choices()["ramboost"]) ? "ok":"falta";' > "$TMP/rb_ch" 2>&1
    assert_contains "$TMP/rb_ch" "ok" "grupo de escolha ramboost declarado"
    grep -q '"ram-boost.sh"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o Liberar RAM" || bad "app: actions.json sem ram-boost"
    rm -rf "$HOME/.packotm"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_clean() {
    printf '\n  # clean: motor único de limpeza (fundo/suave/normal) + scan + off\n'
    local f="$ROOT/scripts/clean.sh"
    [ -f "$f" ] && ok "scripts/clean.sh existe" || { bad "clean.sh ausente"; return; }
    # ajuda e fase inválida
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" > "$TMP/cl_help" 2>&1
    assert_contains "$TMP/cl_help" "CLEAN\|Clean\|Limpeza" "clean explica o que faz sem argumento"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" now bogus > "$TMP/cl_bad" 2>&1
    assert_contains "$TMP/cl_bad" "inválida" "clean recusa fase inválida"
    # sem shell: recusa
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" now suave >/dev/null 2>&1
    assert_eq "1" "$?" "clean sem shell é recusado"
    # scan: só lê, não mexe em settings
    rm -rf "$HOME/.packotm"; : > "$TMP_STORE/global.window_animation_scale"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" scan > "$TMP/cl_scan" 2>&1
    assert_contains "$TMP/cl_scan" "RAM" "clean scan mostra a RAM"
    [ -s "$TMP_STORE/global.window_animation_scale" ] && bad "scan não deveria mexer em settings" \
        || ok "scan não altera nada"
    # fase fundo: libera RAM (encerra fundo + poda cache) e NÃO suaviza
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/cl.log" TMP_AM_LOG="$TMP/cl.log" TMP_PM_LOG="$TMP/cl.log"
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" now fundo > "$TMP/cl_fundo" 2>&1
    grep -q 'force-stop com.whatsapp' "$TMP_CMD_LOG" && ok "clean fundo encerra apps de fundo" || bad "clean fundo não encerrou o fundo"
    grep -q 'trim-caches' "$TMP_CMD_LOG" && ok "clean fundo poda o cache" || bad "clean fundo sem trim-caches"
    [ -s "$TMP_STORE/global.window_animation_scale" ] && bad "fase fundo não devia suavizar" \
        || ok "fase fundo não mexe em animações"
    # fase suave: libera RAM + suaviza sem root (animações 0, blur off, doze)
    rm -rf "$HOME/.packotm"
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" now suave > "$TMP/cl_suave" 2>&1
    assert_contains "$TMP_STORE/global.window_animation_scale" "0" "clean suave zera as animações"
    assert_contains "$TMP_STORE/global.disable_window_blurs" "1" "clean suave desliga o blur"
    assert_contains "$TMP_STORE/global.device_idle_constants" "light_after_inactive_to" "clean suave afina o doze"
    assert_contains "$HOME/.packotm/clean/applied" "suave" "clean grava a fase aplicada"
    assert_contains "$TMP/cl_suave" "Clean pronto" "clean conclui com o resumo"
    # a fase 'normal' (suavização profunda root) saiu: agora só fundo|suave
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" now normal > "$TMP/cl_normal" 2>&1
    assert_contains "$TMP/cl_normal" "inválida" "clean recusa a fase 'normal' (era root)"
    # status + off (desfaz a suavização)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" status > "$TMP/cl_st" 2>&1
    assert_contains "$TMP/cl_st" "CLEAN" "clean status mostra o resumo"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" off > "$TMP/cl_off" 2>&1
    [ -f "$HOME/.packotm/clean/applied" ] && bad "clean off deixou o marcador" || ok "clean off limpa o marcador"
    # integração: adb-tweaks delega ao clean e expõe os grupos novos
    OTM_NO_COLOR=1 OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" list > "$TMP/cl_list" 2>&1
    assert_contains "$TMP/cl_list" "clean_scan" "adb-tweaks lista o grupo clean_scan"
    grep -q 'clean_deep' "$TMP/cl_list" && bad "grupo clean_deep (root) ainda existe" \
        || ok "grupo clean_deep (root) removido"
    grep -q 'aot' "$TMP/cl_list" && bad "grupo aot (root/placebo) ainda existe" || ok "grupo aot removido"
    # registro no painel + whitelist + catálogo
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["clean","clean.scan","clean.undo"] as $id) echo isset($a[$id]) ? "" : "FALTA:$id ";' \
        > "$TMP/cl_reg" 2>&1
    test ! -s "$TMP/cl_reg" && ok "ações do Clean no registro do painel" || bad "registro: $(cat "$TMP/cl_reg")"
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("clean.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' > "$TMP/cl_lib" 2>&1
    assert_contains "$TMP/cl_lib" "ok" "clean.sh na whitelist"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             echo isset($a["clean.aot"]) ? "AINDA" : "removido";' > "$TMP/cl_aot" 2>&1
    assert_contains "$TMP/cl_aot" "removido" "ação clean.aot removida do registro"
    grep -q '"clean.sh"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o Clean" || bad "app: actions.json sem clean.sh"
    grep -q '"clean.deep"' "$ROOT/app/src/main/assets/panel/actions.json" \
        && bad "app: actions.json ainda tem clean.deep (root)" || ok "app: actions.json sem clean.deep"
    rm -rf "$HOME/.packotm"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_resolution() {
    printf '\n  # resolução de tela: perfis de vários aparelhos + custom\n'
    local f="$ROOT/scripts/resolution.sh"
    [ -f "$f" ] && ok "scripts/resolution.sh existe" || { bad "resolution.sh ausente"; return; }
    # a lista tem perfis de aparelhos reais e nomes legíveis
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" list > "$TMP/res_list" 2>&1
    assert_contains "$TMP/res_list" "720x1600" "lista traz o 720p alto (celular comum)"
    assert_contains "$TMP/res_list" "1080x2340" "lista traz o 1080p alto"
    assert_contains "$TMP/res_list" "1440x3200" "lista traz o QHD alto"
    assert_contains "$TMP/res_list" "RESOLUÇÕES DISPONÍVEIS" "lista se identifica"
    # aplica um perfil pelo nome e confere que o wm size recebeu o valor
    rm -rf "$HOME/.packotm"
    : > "$TMP/res.log"; export TMP_CMD_LOG="$TMP/res.log"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply 720x1600 > "$TMP/res_ap" 2>&1
    assert_contains "$TMP/res_ap" "720x1600" "apply aplica a resolução pedida"
    grep -q 'wm size 720x1600' "$TMP/res.log" \
        && ok "apply manda 'wm size' com o valor certo" || bad "apply não chamou wm size"
    # resolução custom em WxH é aceita
    : > "$TMP/res.log"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply 900x1800 > "$TMP/res_c" 2>&1
    grep -q 'wm size 900x1800' "$TMP/res.log" \
        && ok "apply aceita resolução personalizada" || bad "custom não passou"
    # valores inválidos são recusados (nada de quebrar a tela)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply 99x99 > "$TMP/res_bad" 2>&1
    assert_contains "$TMP/res_bad" "pequena demais" "apply recusa resolução minúscula"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply 99999x99999 > "$TMP/res_bad2" 2>&1
    assert_contains "$TMP/res_bad2" "grande demais" "apply recusa resolução absurda"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" apply abc > "$TMP/res_bad3" 2>&1
    assert_contains "$TMP/res_bad3" "desconhecido" "apply recusa nome inexistente"
    # reset devolve a de fábrica
    : > "$TMP/res.log"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" reset > "$TMP/res_rst" 2>&1
    grep -q 'wm size reset' "$TMP/res.log" \
        && ok "reset devolve a resolução de fábrica" || bad "reset não chamou wm size reset"
    # a resolução de fábrica fica guardada (o restore do pack depende disso)
    grep -q 'ST/res/orig' "$f" && ok "guarda a resolução de fábrica" || bad "não guarda a original"
    unset TMP_CMD_LOG
    # whitelist do painel + catálogo
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("resolution.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' \
        > "$TMP/res_lib" 2>&1
    assert_contains "$TMP/res_lib" "ok" "resolution.sh na whitelist"
    # espelho do app
    [ -f "$ROOT/app/src/main/assets/pack/scripts/resolution.sh" ] \
        && ok "espelho: resolution.sh presente" || bad "espelho: resolution.sh ausente"
}

t_smart_clean_protect() {
    printf '\n  # limpeza inteligente: nunca fecha o overlay, o app do pack nem o app em uso\n'
    local f="$ROOT/scripts/clean.sh"
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/sc.log" TMP_AM_LOG="$TMP/sc.log" TMP_PM_LOG="$TMP/sc.log"
    : > "$TMP_CMD_LOG"
    # o app na tela agora é o jogo (o usuário está na partida)
    printf 'com.dts.freefireth' > "$TMP_STORE/fg"
    # escolhe um jogo no Modo Competitivo diferente do que está em foco
    mkdir -p "$HOME/.packotm/game"; printf 'com.mojang.minecraftpe' > "$HOME/.packotm/game/pkg"
    # protege um app no anti-relog
    mkdir -p "$HOME/.packotm/keepalive"; printf 'com.instagram.android\n' > "$HOME/.packotm/keepalive/apps"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" now fundo > "$TMP/sc_out" 2>&1
    # o app EM PRIMEIRO PLANO nunca é encerrado
    grep -q 'force-stop com.dts.freefireth' "$TMP_CMD_LOG" \
        && bad "limpeza fechou o app em primeiro plano" || ok "limpeza poupa o app em primeiro plano"
    # o jogo escolhido no Modo Competitivo nunca é encerrado
    grep -q 'force-stop com.mojang.minecraftpe' "$TMP_CMD_LOG" \
        && bad "limpeza fechou o jogo do Modo Competitivo" || ok "limpeza poupa o jogo escolhido"
    # os protegidos no anti-relog continuam poupados
    grep -q 'force-stop com.instagram.android' "$TMP_CMD_LOG" \
        && bad "limpeza fechou um protegido no anti-relog" || ok "limpeza poupa os protegidos no anti-relog"
    # o próprio app do pack está no OTM_SYS_KEEP (nunca é encerrado)
    grep -q 'com.otm.pack' "$ROOT/scripts/common.sh" \
        && ok "o app do pack está na lista de protegidos" || bad "com.otm.pack fora da proteção"
    # os outros apps de fundo SÃO encerrados (a limpeza ainda funciona)
    grep -q 'force-stop com.whatsapp' "$TMP_CMD_LOG" \
        && ok "limpeza ainda encerra os apps de fundo" || bad "limpeza não encerrou nada"
    # o overlay do jogo (o painel flutuante) é protegido pelo pacote do app
    printf 'com.otm.pack' > "$TMP_STORE/fg"
    : > "$TMP_CMD_LOG"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$f" now fundo > /dev/null 2>&1
    grep -q 'force-stop com.otm.pack' "$TMP_CMD_LOG" \
        && bad "limpeza fechou o app do pack (derrubaria o overlay)" || ok "limpeza nunca fecha o app do pack/overlay"
    # ram-boost usa a mesma proteção
    : > "$TMP_CMD_LOG"
    printf 'com.dts.freefiremax' > "$TMP_STORE/fg"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/ram-boost.sh" boost normal > /dev/null 2>&1
    grep -q 'force-stop com.dts.freefiremax' "$TMP_CMD_LOG" \
        && bad "ram-boost fechou o app em primeiro plano" || ok "ram-boost também poupa o app em primeiro plano"
    # otm_keep_list junta jogo + anti-relog + primeiro plano, sem repetir
    OTM_NO_COLOR=1 OTM_MODE=su sh -c '. "'"$ROOT"'/scripts/common.sh"; otm_keep_list' > "$TMP/sc_keep" 2>&1
    assert_contains "$TMP/sc_keep" "com.dts.freefiremax" "otm_keep_list inclui o app em primeiro plano"
    assert_contains "$TMP/sc_keep" "com.mojang.minecraftpe" "otm_keep_list inclui o jogo escolhido"
    d=$(tr ' ' '\n' < "$TMP/sc_keep" | grep -c '^com.dts.freefiremax$')
    [ "$d" = "1" ] && ok "otm_keep_list não repete pacotes" || bad "otm_keep_list repetiu ($d)"
    rm -rf "$HOME/.packotm" "$TMP_STORE/fg"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_privilege_detect() {
    printf '\n  # privilégio: processo que já é shell (Shizuku/ADB) não pode ser recusado\n'
    # O app roda os scripts pelo Shizuku: o processo JÁ nasce como uid 2000 e não
    # existe `rish`/`adb` no PATH. Antes o pack se dizia "sem shell" e o botão
    # "Clean Phone" falhava sempre, mesmo com o Shizuku conectado.
    local ub="$TMP/uidbin"; mkdir -p "$ub"
    printf '#!/bin/sh\necho 2000\n' > "$ub/id"; chmod +x "$ub/id"
    rm -rf "$HOME/.packotm"
    export TMP_CMD_LOG="$TMP/pd.log" TMP_AM_LOG="$TMP/pd.log" TMP_PM_LOG="$TMP/pd.log"
    : > "$TMP_CMD_LOG"
    out="$(PATH="$ub:$PATH" OTM_NO_COLOR=1 sh "$ROOT/scripts/adb-tweaks.sh" clean 2>&1)"
    printf '%s' "$out" | grep -q 'sem permissão de shell' \
        && bad "uid 2000 (Shizuku) recusado como se não tivesse shell" \
        || ok "uid 2000 (Shizuku/ADB) é aceito como shell"
    grep -q 'trim-caches' "$TMP_CMD_LOG" && ok "uid 2000 realmente executa a limpeza" \
        || bad "uid 2000 não executou a limpeza"
    PATH="$ub:$PATH" OTM_NO_COLOR=1 sh "$ROOT/scripts/config.sh" show 2>&1 | grep -q 'direct' \
        && ok "config.sh reporta o modo direct" || bad "config.sh não detecta o modo direct"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_undo_scope() {
    printf '\n  # reversão por escopo: desfazer uma ação não apaga o que outra aplicou\n'
    rm -rf "$HOME/.packotm"
    printf '0.5' > "$TMP_STORE/global.window_animation_scale"   # valor original do aparelho
    export TMP_CMD_LOG="$TMP/us.log"; : > "$TMP_CMD_LOG"
    OTM_MODE=su OTM_NO_COLOR=1 sh "$ROOT/scripts/clean.sh" now suave >/dev/null 2>&1
    assert_eq "0" "$(cat "$TMP_STORE/global.window_animation_scale" 2>/dev/null)" \
        "clean zera as animações"
    OTM_MODE=su OTM_NO_COLOR=1 sh "$ROOT/scripts/adb-tweaks.sh" perf >/dev/null 2>&1
    assert_eq "0.5" "$(cat "$TMP_STORE/global.window_animation_scale" 2>/dev/null)" \
        "performance põe 0.5x"
    # desfazer SÓ o clean não pode tocar no que o performance aplicou
    OTM_MODE=su OTM_NO_COLOR=1 sh "$ROOT/scripts/clean.sh" off >/dev/null 2>&1
    assert_eq "0.5" "$(cat "$TMP_STORE/global.window_animation_scale" 2>/dev/null)" \
        "clean off preserva o 0.5x do performance"
    [ -s "$HOME/.packotm/undo/adb-tweaks.sh" ] && ok "performance mantém a própria reversão" \
        || bad "performance perdeu a reversão"
    # restaurar tudo volta ao valor ORIGINAL do aparelho (não ao de outra ação)
    OTM_MODE=su OTM_NO_COLOR=1 sh "$ROOT/scripts/adb-tweaks.sh" restore_all >/dev/null 2>&1
    assert_eq "0.5" "$(cat "$TMP_STORE/global.window_animation_scale" 2>/dev/null)" \
        "restore_all volta ao valor original do aparelho"
    rm -rf "$HOME/.packotm"
    unset TMP_CMD_LOG TMP_AM_LOG TMP_PM_LOG
}

t_undo_scopes_declared() {
    printf '\n  # todo script que guarda reversão declara o próprio escopo\n'
    for f in "$ROOT"/scripts/*.sh; do
        b="$(basename "$f")"
        [ "$b" = "common.sh" ] && continue
        grep -q 'bkp_set\|bkp_raw' "$f" || continue
        grep -q 'scope_begin' "$f" && ok "$b isola a reversão (scope_begin)" \
            || bad "$b guarda reversão sem scope_begin"
    done
}

t_no_silent_conflicts() {
    printf '\n  # conflitos entre ações: mesma chave, valores divergentes ficam explícitos\n'
    # Duas ações que escrevem a MESMA chave com valores diferentes se atropelam:
    # aplicar uma depois da outra deixa o aparelho num estado misto (era a causa
    # do "mais engasgado do que fluido"). Aqui os pares conhecidos e INTENCIONAIS
    # ficam declarados; qualquer par novo que apareça quebra o teste.
    local allow="
        global activity_manager_constants
        global animator_duration_scale
        global transition_animation_scale
        global window_animation_scale
        global heads_up_notifications_enabled
        global notification_bubbles
        global low_power
        # desfoque/transparência: liga (effects on) e desliga (effects off, perf,
        # gpu, fluidez, clean) — par intencional, igual ao low_power
        global disable_window_blurs
        global accessibility_reduce_transparency
        global app_standby_enabled
        global adaptive_battery_management_enabled
        global private_dns_mode
        global private_dns_specifier
        global settings_enable_monitor_phantom_procs
        global wifi_scan_always_enabled
        global ble_scan_always_enabled
        system peak_refresh_rate
        system min_refresh_rate
        system long_press_timeout
        system multi_press_timeout
        system pointer_speed
        system touch_slop
        # barras do sistema: os pares visível/escondido e ligado/desligado do
        # grupo `sysbars` são intencionais (mesma ação, dois botões)
        global policy_control
        system clock_seconds
        system status_bar_show_battery_percent
        # Wi-Fi e rede: os pares liga/desliga (wifi_off, mobile_net_off,
        # net_tune off) devolvem o valor oposto ao da ação de ligar.
        global wifi_wakeup_enabled
        global wifi_power_save
        global mobile_data_always_on
        global network_avoid_bad_wifi
        global wifi_scan_throttle_enabled
        # DND: dnd() entra em alarmes-apenas (3) e dnd_off() volta a 0.
        secure zen_mode
        # renderização por GPU: gpu() liga e gpu_off() devolve ao sistema.
        global force_gpu_rendering
        global game_driver_all_apps
        # economia de dados: mobile_net() desliga e mobile_net_off() devolve.
        # É o par liga/desliga (mesma chave, valores opostos), intencional.
        global data_saver_mode
    "
    python3 - "$ROOT" "$allow" <<'PYEOF' > "$TMP/conf"
import re,sys,glob,collections,os
root=sys.argv[1]
allow=set(x.strip() for x in sys.argv[2].split('\n') if x.strip() and not x.strip().startswith('#'))
keys=collections.defaultdict(lambda: collections.defaultdict(set))
for f in glob.glob(os.path.join(root,'scripts','*.sh')):
    for ln,l in enumerate(open(f,encoding='utf-8',errors='ignore'),1):
        m=re.search(r'bkp_set\s+(\S+)\s+(\S+)\s+(.+?)\s*$', l)
        if not m: continue
        ns,k,v=m.group(1),m.group(2).strip('"'),m.group(3).strip()
        # linhas dentro de um `case ... esac` terminam com ";;": nao fazem
        # parte do valor gravado
        v=re.sub(r'\s*;;\s*$','',v).strip()
        if ns.startswith('$'): continue
        keys[ns+' '+k][os.path.basename(f)].add(v)
for k,d in sorted(keys.items()):
    vals=set()
    for vs in d.values(): vals|=vs
    if len(vals)>1 and k not in allow:
        print("NOVO_CONFLITO", k, sorted(d))
PYEOF
    if [ -s "$TMP/conf" ]; then
        bad "surgiram conflitos não declarados entre ações: $(head -1 "$TMP/conf")"
    else
        ok "nenhum conflito silencioso novo entre ações"
    fi
    # as chaves compartilhadas continuam sendo gravadas por quem deveria
    grep -q 'window_animation_scale' "$ROOT/scripts/adb-tweaks.sh" \
        && ok "animações seguem em adb-tweaks.sh" || bad "animações sumiram do adb-tweaks"
}


t_pack() {
    printf '\n  # pack.sh: menu-mestre (help, status, delegação)\n'
    f="$ROOT/scripts/pack.sh"
    [ -f "$f" ] && ok "scripts/pack.sh existe" || { bad "pack.sh ausente"; return; }
    sh "$f" --help > "$TMP/pack_help" 2>&1
    assert_contains "$TMP/pack_help" "menu interativo" "pack.sh --help mostra uso"
    OTM_MODE=local OTM_NO_COLOR=1 sh "$f" status > "$TMP/pack_status" 2>&1
    assert_contains "$TMP/pack_status" "STATUS DO PACK" "pack.sh status mostra o status"
    st="$HOME/.packotm/debloat"; rm -rf "$st"
    export TMP_PM_LOG="$TMP/pm3.log"; : > "$TMP_PM_LOG"
    OTM_MODE=local sh "$f" debloat on leve >/dev/null 2>&1
    [ -f "$st/applied" ] && ok "pack.sh delega p/ debloat.sh" || bad "pack.sh não delegou p/ debloat"
    OTM_MODE=local sh "$f" debloat off >/dev/null 2>&1
    rm -rf "$st"
    [ -f "$ROOT/pack.sh" ] && ok "launcher pack.sh na raiz existe" || bad "launcher da raiz ausente"
    sh "$ROOT/00 Otimizações/Scripts SH/run.sh" --help > "$TMP/run_help" 2>&1
    assert_contains "$TMP/run_help" "menu interativo" "run.sh delega ao menu-mestre"
    unset TMP_PM_LOG
}

t_proc_limit() {
    printf '\n  # limite de processos: escreve onde o Android 10+ lê e confere\n'
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    rm -f "$TMP_STORE/dc.activity_manager.max_cached_processes"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" proc_limit 4 > "$TMP/pl4" 2>&1
    assert_eq "4" "$(cat "$TMP_STORE/dc.activity_manager.max_cached_processes" 2>/dev/null)" \
        "proc_limit 4 grava no device_config (Android 10+)"
    assert_contains "$TMP_STORE/global.activity_manager_constants" "max_cached_processes=4" \
        "proc_limit 4 mantém o setting em sincronia"
    assert_contains "$TMP/pl4" "OK" "proc_limit confirma quando a leitura bate"
    # lido de volta pelo mesmo caminho do painel
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" proc_limit status 2>&1)
    printf '%s\n' "$out" > "$TMP/pl_status"
    assert_contains "$TMP/pl_status" "4" "proc_limit status mostra o valor real (4)"
    # padrão: apaga o override e o status volta a dizer "padrão"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" proc_limit padrao > "$TMP/ploff" 2>&1
    test ! -f "$TMP_STORE/dc.activity_manager.max_cached_processes" \
        && ok "proc_limit padrao apaga o override" || bad "proc_limit padrao nao apagou"
    # valor fora da faixa é recusado
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" proc_limit 999 > "$TMP/plbad" 2>&1
    assert_contains "$TMP/plbad" "uso:" "proc_limit recusa valor inválido"
    # reversão registrada: restore_all limpa o que o pack escreveu
    grep -q 'device_config delete activity_manager' "$HOME/.packotm/undo/adb-tweaks.sh" \
        && ok "proc_limit é reversível (undo com device_config delete)" || bad "proc_limit sem reversão"
    # o pack recomendado (all) fecha com o limite de 4
    grep -q 'proc_limit_set 4' "$ROOT/scripts/adb-tweaks.sh" \
        && ok "pack recomendado aplica o limite de 4" || bad "all sem proc_limit"
    grep -q 'latency' "$ROOT/scripts/adb-tweaks.sh" \
        && ok "pack recomendado inclui a latência" || bad "all sem latência"
    # nenhum script pode voltar a escrever o limite só no setting
    ! grep -rqE 'am_set max_cached_processes=[1-9]' "$ROOT/scripts/" \
        && ok "nenhum script escreve o limite só no setting" \
        || bad "ainda há am_set max_cached_processes=<n>"
    rm -rf "$HOME/.packotm"
}

t_effects() {
    printf '\n  # efeitos visuais: desfoque/transparência ligam, desligam e revertem\n'
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    # desligar (o que o pack faz nas ações de desempenho)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" effects off > "$TMP/fx_off" 2>&1
    assert_eq "1" "$(cat "$TMP_STORE/global.disable_window_blurs" 2>/dev/null)" \
        "effects off desliga o desfoque"
    assert_eq "1" "$(cat "$TMP_STORE/global.accessibility_reduce_transparency" 2>/dev/null)" \
        "effects off desliga a transparência"
    assert_contains "$TMP/fx_off" "desfoque" "effects off explica o que fez"
    # ligar de volta (o card que devolve o blur do teclado/barra)
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" effects on > "$TMP/fx_on" 2>&1
    assert_eq "0" "$(cat "$TMP_STORE/global.disable_window_blurs" 2>/dev/null)" \
        "effects on religa o desfoque"
    assert_eq "0" "$(cat "$TMP_STORE/global.accessibility_reduce_transparency" 2>/dev/null)" \
        "effects on religa a transparência"
    # status lê o estado real, não o que foi escrito
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" effects status > "$TMP/fx_st" 2>&1
    assert_contains "$TMP/fx_st" "ligado" "effects status mostra o estado real"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" effects off >/dev/null 2>&1
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" effects status > "$TMP/fx_st2" 2>&1
    assert_contains "$TMP/fx_st2" "desligado" "effects status detecta o desfoque desligado"
    # valor inválido é recusado
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" effects xyz > "$TMP/fx_bad" 2>&1
    assert_contains "$TMP/fx_bad" "uso:" "effects recusa argumento inválido"
    # REVERSÃO: o bug era o blur/transparência saírem por sh_run (sem undo)
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" fluidez >/dev/null 2>&1
    grep -q 'disable_window_blurs' "$HOME/.packotm/undo/adb-tweaks.sh" \
        && ok "fluidez registra a reversão do desfoque" || bad "fluidez não reverte o desfoque"
    grep -q 'accessibility_reduce_transparency' "$HOME/.packotm/undo/adb-tweaks.sh" \
        && ok "fluidez registra a reversão da transparência" || bad "fluidez não reverte a transparência"
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" window_tweaks >/dev/null 2>&1
    # Bug A: o modo imersivo (policy_control immersive.*) ESTICAVA o conteúdo
    # para baixo da barra de gestos (a busca do YouTube ficava atrás dela).
    # window_tweaks não pode mais escrever imersivo.
    ! grep -q 'policy_control' "$HOME/.packotm/undo/adb-tweaks.sh" \
        && ok "window_tweaks não mexe mais no modo imersivo" \
        || bad "window_tweaks ainda escreve policy_control (esticava o conteúdo)"
    # nenhum script pode voltar a mexer no blur por sh_run (sem reversão)
    ! grep -rn 'sh_run "settings put global disable_window_blurs' "$ROOT/scripts/" >/dev/null 2>&1 \
        && ok "nenhum script escreve o desfoque fora da reversão" \
        || bad "ainda há sh_run com disable_window_blurs"
    ! grep -rn 'sh_run "settings put global accessibility_reduce_transparency' "$ROOT/scripts/" >/dev/null 2>&1 \
        && ok "nenhum script escreve a transparência fora da reversão" \
        || bad "ainda há sh_run com accessibility_reduce_transparency"
    rm -rf "$HOME/.packotm"
}

t_latency() {
    printf '\n  # latência / ping: aplica sysctl, confere e reverte\n'
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" latency > "$TMP/lat_on" 2>&1
    assert_contains "$TMP/lat_on" "Latência" "latency explica o efeito"
    # os knobs que mudam o ping de verdade foram escritos
    assert_eq "bbr" "$(cat "$TMP_STORE/sys.net.ipv4.tcp_congestion_control" 2>/dev/null)" \
        "latency liga o BBR (o stub anuncia bbr disponível)"
    assert_eq "1" "$(cat "$TMP_STORE/sys.net.ipv4.tcp_low_latency" 2>/dev/null)" \
        "latency liga o low latency"
    assert_eq "0" "$(cat "$TMP_STORE/sys.net.ipv4.tcp_autocorking" 2>/dev/null)" \
        "latency desliga o autocorking"
    assert_eq "16384" "$(cat "$TMP_STORE/sys.net.ipv4.tcp_notsent_lowat" 2>/dev/null)" \
        "latency encurta o notsent_lowat"
    assert_contains "$TMP_STORE/sys.net.ipv4.tcp_rmem" "6291456" "latency ajusta o buffer de recepção"
    grep -q 'tcp_congestion_control' "$HOME/.packotm/undo/adb-tweaks.sh" \
        && ok "latency guarda reversão do congestion control" || bad "latency sem reversão"
    assert_contains "$TMP/lat_on" "#OTM-RESULT" "latency emite #OTM-RESULT"
    ch=$(grep '#OTM-RESULT' "$TMP/lat_on" | sed -n 's/.*changed=\([0-9]*\).*/\1/p')
    [ "${ch:-0}" -ge 5 ] && ok "latency confirmou mudança real (changed=$ch)" \
        || bad "latency não confirmou mudanças (changed=$ch)"
    # kernel sem BBR: não inventa, avisa e segue
    rm -rf "$HOME/.packotm"
    mkdir -p "$TMP/bin_nobbr"
    printf '#!/bin/sh\ncase "$1" in -n) echo "cubic reno";; -w) exit 0;; esac\n' > "$TMP/bin_nobbr/sysctl"
    chmod +x "$TMP/bin_nobbr/sysctl"
    out=$(PATH="$TMP/bin_nobbr:$PATH" OTM_NO_COLOR=1 OTM_MODE=su \
        sh "$ROOT/scripts/adb-tweaks.sh" latency 2>&1)
    printf '%s\n' "$out" > "$TMP/lat_nobbr"
    assert_contains "$TMP/lat_nobbr" "sem BBR" "latency avisa quando o kernel não tem BBR"
    # reversão: os valores antigos são restaurados
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" latency_reset > "$TMP/lat_off" 2>&1
    assert_contains "$TMP/lat_off" "restaurar" "latency_reset explica a reversão"
    rm -rf "$TMP/bin_nobbr" "$HOME/.packotm"
}

t_sensi() {
    printf '\n  # sensi: gerador sob medida, só leitura\n'
    f="$ROOT/scripts/sensi.sh"
    [ -f "$f" ] && ok "scripts/sensi.sh existe" || { bad "sensi.sh ausente"; return; }
    # não pode mexer em NADA: nenhuma chamada de escrita (settings put, setprop...)
    ! grep -qE '^\s*(settings put|setprop|device_config put)' "$f" \
        && ok "sensi.sh não escreve nada no aparelho" || bad "sensi.sh escreve no aparelho"
    ! grep -q 'bkp_set' "$f" && ok "sensi.sh não registra reversão (não altera)" \
        || bad "sensi.sh tem bkp_set"
    rm -rf "$HOME/.packotm"
    out=$(OTM_NO_COLOR=1 OTM_MODE=local sh "$f" 2>&1)
    printf '%s\n' "$out" > "$TMP/sn_out"
    assert_contains "$TMP/sn_out" "GERADOR DE SENSI" "sensi mostra o cabeçalho"
    assert_contains "$TMP/sn_out" "Geral" "sensi mostra a sensi Geral"
    assert_contains "$TMP/sn_out" "Ponto vermelho" "sensi mostra o ponto vermelho"
    assert_contains "$TMP/sn_out" "AWM" "sensi mostra a mira AWM"
    assert_contains "$TMP/sn_out" "Botão de atirar" "sensi mostra o tamanho do botão"
    assert_contains "$TMP/sn_out" "máximo 50%" "sensi lembra o teto de 50% do botão"
    assert_contains "$TMP/sn_out" "NÃO altera nada" "sensi avisa que não altera nada"
    # todos os valores ficam na faixa válida do jogo (0-100)
    vals=$(printf '%s\n' "$out" | sed -n 's/^ *\(Geral\|Ponto vermelho\|Mira 2x\|Mira 4x\|AWM \/ mira livre\) *\([0-9]*\)$/\2/p')
    [ -n "$vals" ] && bad_count=0 || bad_count=1
    for v in $vals; do
        [ "$v" -ge 0 ] 2>/dev/null && [ "$v" -le 100 ] 2>/dev/null || bad_count=1
    done
    [ "$bad_count" = "0" ] && ok "todos os valores ficam entre 0 e 100" \
        || bad "valor fora de 0..100 ($vals)"
    # o teto do botão nunca passa de 50%
    btn=$(printf '%s\n' "$out" | sed -n 's/.*Botão de atirar *\([0-9]*\)%.*/\1/p' | head -1)
    [ -n "$btn" ] && [ "$btn" -le 50 ] 2>/dev/null && ok "botão de atirar respeita o teto (${btn}%)" \
        || bad "botão de atirar acima de 50% ($btn)"
    # analyze mostra o que foi lido e os fatores
    OTM_NO_COLOR=1 OTM_MODE=local sh "$f" analyze > "$TMP/sn_an" 2>&1
    assert_contains "$TMP/sn_an" "densidade" "sensi analyze mostra a densidade lida"
    assert_contains "$TMP/sn_an" "fatores aplicados" "sensi analyze mostra os fatores"
    assert_contains "$TMP/sn_an" "1.000" "sensi analyze mostra fatores neutros no padrão"
    # perfis: headshot > sniper no valor geral
    g1=$(OTM_NO_COLOR=1 OTM_MODE=local sh "$f" ff headshot 2>&1 | head -1 | awk '{print $1}')
    g2=$(OTM_NO_COLOR=1 OTM_MODE=local sh "$f" ff sniper 2>&1 | head -1 | awk '{print $1}')
    [ "${g1:-0}" -gt "${g2:-0}" ] 2>/dev/null && ok "perfil headshot fica acima do sniper ($g1 > $g2)" \
        || bad "perfis não se diferenciam ($g1 vs $g2)"
    # ff imprime exatamente 5 valores
    n=$(OTM_NO_COLOR=1 OTM_MODE=local sh "$f" ff 2>&1 | head -1 | wc -w)
    [ "$n" = "5" ] && ok "sensi ff imprime os 5 valores do Free Fire" \
        || bad "sensi ff imprimiu $n valores"
    # aparelho diferente -> sensi diferente (tela densa cai, tela leve sobe)
    mkdir -p "$TMP/bin_den"
    printf '#!/bin/sh\ncase "$1$2" in "wm size") echo "Physical size: 720x1600";;\n"wm density") echo "Physical density: 320";;\nesac\nexit 0\n' > "$TMP/bin_den/wm"
    chmod +x "$TMP/bin_den/wm"
    g3=$(PATH="$TMP/bin_den:$PATH" OTM_NO_COLOR=1 OTM_MODE=local sh "$f" ff 2>&1 | head -1 | awk '{print $1}')
    [ -n "$g3" ] && ok "sensi responde à tela do aparelho (720p/320dpi -> $g3)" \
        || bad "sensi não leu a tela alternativa"
    rm -rf "$TMP/bin_den" "$HOME/.packotm"
}

# --- execução ----------------------------------------------------------------
printf '  ==================================================\n'
printf '  Testes do Pack de Otimização\n'
printf '  ==================================================\n'
setup_stubs
t_syntax
t_angle_tag
t_renderer_app
t_per_module
t_extreme
t_adv_noroot
t_sysbars
t_gfxdriver
t_realverify
t_realverify_deep
t_config
t_auth
t_panel_db
t_noroot_only
t_pack_scripts_mirror
t_app_login
t_app_exec
t_app_fixes
t_footer_sticky
t_new_features
t_panel_state
t_panel_stats
t_fps_real
t_game_keepalive
t_game_open
t_pack_stamp
t_perm_game
t_perm_script
t_perm_actions
t_personalization
t_usage_access
t_side_fixed
t_plugin_mark_once
t_plugin_restore
t_freezer_whitelist
t_overlay() {
    printf '\n  # painel flutuante (overlay sobre o jogo)\n'
    local src="$ROOT/app/src/main/java/com/otm/pack"
    local man="$ROOT/app/src/main/AndroidManifest.xml"
    local svc="$src/OverlayService.kt"

    [ -f "$svc" ] && ok "OverlayService existe" || { bad "OverlayService ausente"; return; }
    # permissão de sobreposição declarada (sem ela o Android não deixa o painel sobre o jogo)
    grep -q 'SYSTEM_ALERT_WINDOW' "$man" \
        && ok "manifest pede SYSTEM_ALERT_WINDOW" || bad "manifest sem SYSTEM_ALERT_WINDOW"
    # o serviço é de primeiro plano e do tipo exigido no Android 14
    grep -q 'foregroundServiceType="specialUse"' "$man" \
        && ok "service declara foregroundServiceType" || bad "service sem foregroundServiceType"
    grep -q 'FOREGROUND_SERVICE_SPECIAL_USE' "$man" \
        && ok "manifest pede FOREGROUND_SERVICE_SPECIAL_USE" || bad "sem permissão specialUse"
    # janela de sobreposição de verdade (TYPE_APPLICATION_OVERLAY)
    grep -q 'TYPE_APPLICATION_OVERLAY' "$svc" \
        && ok "janela usa TYPE_APPLICATION_OVERLAY" || bad "sem TYPE_APPLICATION_OVERLAY"
    # usa o executor compartilhado (não reimplementa o comando)
    grep -q 'OtmExec.run' "$svc" \
        && ok "overlay usa o executor compartilhado" || bad "overlay não usa OtmExec"
    # a sensi e os perfis de toque estão no painel flutuante
    grep -q 'sensi.sh' "$svc" && ok "overlay aplica o headshot da sensi" || bad "overlay sem sensi.sh"
    grep -q 'ff-touch.sh' "$svc" && ok "overlay troca o perfil de toque" || bad "overlay sem ff-touch.sh"
    for p in balanced headshot spray sniper speed; do
        grep -q "\"$p\"" "$svc" || bad "overlay sem o perfil $p"
    done
    ok "overlay tem os 5 perfis de toque"
    # o painel flutuante se chama só "00" (não "Sensi & mira")
    grep -q 'text = "00"' "$svc" && ok "overlay se chama só '00'" || bad "overlay não usa o nome '00'"
    grep -q 'text = "Sensi & mira"' "$svc" && bad "overlay ainda mostra o título antigo" \
        || ok "overlay não usa mais o título antigo"
    # organizado em CATEGORIAS (abas), não numa lista única
    grep -q 'TABS' "$svc" && ok "overlay tem categorias (abas)" || bad "overlay sem categorias"
    for t in Monitor Jogo Toque Motor Processos Atalhos; do
        grep -q "\"$t\"" "$svc" && ok "overlay tem a aba '$t'" || bad "overlay sem a aba '$t'"
    done
    # a ORDEM do `when` do tabView tem de casar com a ordem de TABS: um índice
    # trocado mostra o conteúdo de uma aba no rótulo de outra (o FPS saía em
    # "Processos" e "Monitor" abria os perfis de toque). Compara os dois lados.
    python3 - "$svc" <<'PY' && ok "overlay casa o índice da aba com o conteúdo certo" \
        || bad "overlay: índice da aba fora de sincronia com TABS"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
tabs = re.search(r'TABS\s*=\s*listOf\(([^)]*)\)', src)
tv = re.search(r'private fun tabView\(index: Int\): View = when \(index\) \{(.*?)\n    \}', src, re.S)
if not (tabs and tv):
    sys.exit(1)
nomes = re.findall(r'"([^"]+)"', tabs.group(1))
# cada aba tem de ter uma função própria, na MESMA ordem dos rótulos
esperado = ["monitorTab", "gameTab", "touchTab", "engineTab", "procTab", "shortcutsTab"]
achado = re.findall(r'(\w+Tab)\(\)', tv.group(1))
sys.exit(0 if achado == esperado and len(nomes) == len(esperado) else 1)
PY
    # o FPS fica na PRIMEIRA aba (é o que o usuário abre no meio da partida)
    grep -q '0 -> monitorTab()' "$svc" \
        && ok "a aba do FPS é a primeira (índice 0)" || bad "o FPS não está na primeira aba"
    # a aba Monitor mostra o FPS REAL (SurfaceFlinger), não a taxa de tela
    grep -q 'panel-stats.sh' "$svc" && ok "overlay usa o panel-stats na aba Monitor" \
        || bad "overlay não lê o consumo real"
    grep -q 'FPS do jogo' "$svc" && ok "overlay mostra o FPS do jogo no monitor" \
        || bad "overlay sem FPS no monitor"
    grep -q 's\["fps"\]\|"fps"' "$svc" && ok "overlay lê o campo fps do painel" \
        || bad "overlay ignora o campo fps"
    grep -q 'private fun monitorTab' "$svc" && ok "overlay tem a aba Monitor" \
        || bad "overlay sem a aba Monitor"
    # o monitor não inventa: campo ausente vira "—"
    grep -q 'monitorRow' "$svc" && grep -q '?: "—"' "$svc" \
        && ok "overlay mostra '—' no que o aparelho não informou" || bad "overlay sem fallback do monitor"
    # o monitor se atualiza sozinho (senão o FPS fica congelado na partida)
    grep -q 'postDelayed(4000)' "$svc" && ok "overlay atualiza o monitor sozinho" \
        || bad "overlay com monitor congelado"
    # a aba fica alta: precisa de rolagem, senão os últimos botões somem
    grep -q 'ScrollView' "$svc" && ok "overlay tem rolagem (abas altas)" \
        || bad "overlay sem rolagem"
    # TAMANHO ESTÁVEL: a janela não pode medir WRAP_CONTENT na largura, senão
    # cada aba tem um tamanho e o painel "pula" ao trocar de aba
    grep -q 'private fun panelWidth()' "$svc" && grep -q 'private fun panelMaxHeight()' "$svc" \
        && ok "overlay tem largura fixa e teto de altura" \
        || bad "overlay com tamanho variável por aba"
    grep -q 'baseParams(panelWidth())' "$svc" \
        && ok "o painel nasce com a largura fixa" || bad "painel nasce com largura variável"
    grep -q 'minimumWidth' "$svc" && bad "overlay ainda usa minimumWidth (largura varia)" \
        || ok "overlay não depende de minimumWidth"
    # a bolha (minimizado) tem tamanho FIXO: o ícone é adaptive icon e, solto
    # num ImageView, não tem tamanho confiável (saía grande/irregular)
    grep -q 'BUBBLE_DP' "$svc" && ok "a bolha tem tamanho fixo (BUBBLE_DP)" \
        || bad "bolha sem tamanho fixo"
    grep -q 'baseParams(if (value) dp(BUBBLE_DP) else panelWidth())' "$svc" \
        && ok "minimizar usa o tamanho certo em cada estado" \
        || bad "minimizar não fixa o tamanho"
    # os rótulos das 5 abas não cabem numa linha só no painel estreito
    grep -q 'TAB_COLS' "$svc" && ok "as abas quebram em linhas (rótulo legível)" \
        || bad "abas numa linha só (rótulo cortado)"
    # o painel não pode voltar a ser estreito nem virar a tela do jogo: a faixa
    # sadia é "painel de verdade, mas ainda deixando o jogo à vista". 0.46 ficava
    # fino; 0.70 tomava a tela (reclamação: "o painel tá mtt grande").
    python3 - "$svc" <<'PY' && ok "painel tem largura de painel (não fica fino nem toma a tela)" \
        || bad "largura do painel fora da faixa 0.5..0.65"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'PANEL_W_FRAC\s*=\s*([0-9.]+)f', src)
sys.exit(0 if m and 0.5 <= float(m.group(1)) <= 0.65 else 1)
PY
    # a altura não pode reservar mais da metade da tela por cima do jogo
    python3 - "$svc" <<'PY' && ok "altura do painel deixa o jogo à vista (<= 0.55)" \
        || bad "painel alto demais (altura > 0.55 da tela)"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'PANEL_H_FRAC\s*=\s*([0-9.]+)f', src)
sys.exit(0 if m and float(m.group(1)) <= 0.55 else 1)
PY
    # o teto de largura não pode passar da própria tela (aparelho estreito)
    python3 - "$svc" <<'PY' && ok "o teto da largura respeita a tela (não estoura a borda)" \
        || bad "teto de largura pode passar da tela"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
sys.exit(0 if re.search(r'minOf\(dp\(320\),\s*tela - dp\(16\)\)', src) else 1)
PY
    # reduzir a resolução (wm size) muda as métricas: a janela precisa se
    # reajustar, senão o painel fica maior que a tela nova (parecia "enorme")
    grep -q 'override fun onConfigurationChanged' "$svc" \
        && ok "o painel se reajusta quando a resolução muda" \
        || bad "painel não se reajusta após wm size (fica maior que a tela)"
    grep -q 'updateViewLayout' "$svc" \
        && ok "o reajuste aplica a janela de novo" || bad "reajuste sem updateViewLayout"
    # a bolha usa o PNG redondo: o adaptive icon (ic_launcher) desenha o logo em
    # ~66% do quadro e deixava a bolha com um logo pequeno perdido num círculo
    grep -q 'R.mipmap.ic_launcher_round' "$svc" \
        && ok "a bolha usa o ícone redondo (preenche o círculo)" \
        || bad "bolha usa o adaptive icon (logo pequeno e torto)"
    # TODA chamada do overlay tem de apontar para um script que existe. Um nome
    # de script errado só apareceria em runtime, no meio da partida.
    python3 - "$svc" "$ROOT/scripts" <<'PY' && ok "overlay só chama scripts que existem" \
        || bad "overlay chama script inexistente"
import os, re, sys
src = open(sys.argv[1], encoding="utf-8").read()
d = sys.argv[2]
chamadas = set(re.findall(r'runScript\(\s*"([^"]+\.sh)"', src))
faltando = sorted(c for c in chamadas if not os.path.isfile(os.path.join(d, c)))
if faltando:
    print("     faltando:", ", ".join(faltando))
sys.exit(1 if faltando else 0)
PY
    # os valores de multitouch respeitam o limite do script (100..800); 10 seria
    # recusado e o botão não faria nada
    python3 - "$svc" <<'PY' && ok "overlay usa multitouch dentro do limite (100..800)" \
        || bad "overlay manda multitouch fora do limite"
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
vals = [int(v) for v in re.findall(r'"touch_multi",\s*"(\d+)"', src)]
sys.exit(1 if any(v < 100 or v > 800 for v in vals) else 0)
PY
    # RODA de verdade cada chamada do overlay contra os stubs. O que se procura
    # aqui é ERRO DE ARGUMENTO (perfil inexistente, valor fora do limite, ação
    # desconhecida) — isso só apareceria no meio da partida, quando o usuário
    # apertasse o botão. Chamadas com valor dinâmico (vindo de uma lista) são
    # puladas: o valor real não está no fonte.
    python3 - "$svc" > "$TMP/overlay_calls" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
pat = re.compile(r'runScript\(\s*"([^"]+)"\s*,\s*listOf\(([^)]*)\)', re.S)
for m in pat.finditer(src):
    inner = m.group(2).strip()
    if not inner:
        print(m.group(1)); continue
    # separa os argumentos no nível de cima e exige que TODOS sejam literal
    args, buf, depth, instr = [], "", 0, False
    for ch in inner:
        if ch == '"': instr = not instr
        elif ch == '(' and not instr: depth += 1
        elif ch == ')' and not instr: depth -= 1
        elif ch == ',' and depth == 0 and not instr:
            args.append(buf.strip()); buf = ""; continue
        buf += ch
    args.append(buf.strip())
    if any(not re.fullmatch(r'"[^"]*"', a) for a in args):
        continue  # valor dinâmico: não dá para saber aqui
    print(m.group(1) + "\t" + "\t".join(a[1:-1] for a in args))
PY
    n_ok=0; n_bad=0
    while IFS="$(printf '\t')" read -r script a1 a2 a3 a4; do
        [ -z "$script" ] && continue
        set -- $script $a1 $a2 $a3 $a4
        out=$(OTM_NO_COLOR=1 OTM_MODE=su timeout 25 sh "$ROOT/scripts/$1" "$2" "$3" "$4" "$5" 2>&1)
        # Argumento recusado = "uso: ..." / "perfil desconhecido:" / "ação
        # desconhecida:" (os `err` dos scripts põem os dois-pontos). NÃO conta
        # "desconhecido" solto (o smart-opt chama assim um SoC que não conhece)
        # nem o "Uso:" da ajuda do ff-touch (maiúsculo, é texto de ajuda).
        if printf '%s' "$out" | grep -qE 'uso:|desconhecid[oa]:|inv[aá]lid'; then
            n_bad=$((n_bad+1))
            printf '       %s %s -> %s\n' "$1" "$2 $3 $4 $5" "$(printf '%s' "$out" | head -1)"
        else
            n_ok=$((n_ok+1))
        fi
    done < "$TMP/overlay_calls"
    [ "$n_bad" = 0 ] && ok "todo argumento do overlay é aceito pelo script ($n_ok chamadas)" \
        || bad "overlay manda $n_bad argumento(s) que o script recusa"
    # as novas ações do flutuante chamam os scripts do pack (nada reimplementado)
    for c in 'turbo.sh' 'dns.sh' 'ram-boost.sh' 'snapshot.sh' 'game-per-app.sh'; do
        grep -q "$c" "$svc" || bad "overlay sem atalho para $c"
    done
    ok "overlay tem os atalhos novos (rede, fluidez, RAM, jogo, snapshot)"
    # a resolução por jogo usa "auto": o flutuante não sabe qual é o jogo
    grep -q 'listOf("apply", "auto"' "$svc" \
        && ok "overlay deixa o script resolver o jogo (auto)" \
        || bad "overlay chuta o pacote do jogo"
    # reduzir a resolução do jogo (mais FPS) com os 3 perfis + reset
    grep -q 'GAME_SCALES' "$svc" && ok "overlay tem os perfis de resolução" \
        || bad "overlay sem os perfis de resolução"
    for s in 'fps" to "FPS' 'balanced' 'max'; do
        grep -q "$s" "$svc" || bad "overlay sem o perfil de resolução '$s'"
    done
    ok "overlay tem os 3 perfis de resolução do jogo"
    grep -q 'listOf("reset", "auto")' "$svc" \
        && ok "overlay sabe resetar a resolução do jogo" \
        || bad "overlay sem o reset de resolução"
    # escolher QUALQUER app para não ser encerrado (não só o que está rodando)
    grep -q 'listOf("apps")' "$svc" \
        && ok "overlay lista todos os apps (exceção fora dos que rodam)" \
        || bad "overlay só protege quem está rodando"
    grep -q 'procAllBox' "$svc" && ok "overlay tem a lista de todos os apps" \
        || bad "overlay sem a lista de todos os apps"
    grep -q 'REFRESH_RATES' "$svc" && ok "overlay tem as taxas de tela fixas" \
        || bad "overlay sem as taxas de tela"
    # a aba Processos: limite de 2º plano, encerrar todos e exceções ("X não encerra")
    grep -q 'proc-mgr.sh' "$svc" && ok "overlay usa o gerenciador de processos" \
        || bad "overlay sem proc-mgr.sh"
    grep -q 'listOf("kill")' "$svc" && ok "overlay tem o encerrar todos" || bad "overlay sem encerrar todos"
    grep -q 'keep-fg' "$svc" && ok "overlay cria exceção para o app em 1º plano" \
        || bad "overlay sem exceção do 1º plano"
    grep -q 'PROC_LIMITS' "$svc" && ok "overlay escolhe o limite de processos em 2º plano" \
        || bad "overlay sem o seletor de limite"
    grep -q '#OTM-PROC' "$svc" && ok "overlay lê a lista de apps rodando" \
        || bad "overlay não lê a lista de processos"
    grep -q 'getApplicationLabel' "$svc" && ok "overlay mostra o nome do app (não só o pacote)" \
        || bad "overlay sem nome legível do app"
    # a aba "Sensi" saiu: o flutuante é para o meio da partida, não para ler número
    if grep -q 'sensiTab\|"Sensi"' "$svc"; then
        bad "overlay ainda tem a aba Sensi"
    else
        ok "overlay sem a aba Sensi"
    fi
    grep -q 'sectionHeader(' "$svc" && ok "overlay tem cabeçalhos de seção" || bad "overlay sem seções"
    # o botão de escolher o MOTOR de renderização está no painel flutuante
    grep -q 'RENDERERS' "$svc" && ok "overlay tem o seletor de motor de renderização" \
        || bad "overlay sem o seletor de motor"
    grep -q 'listOf("renderer", e.first)' "$svc" && ok "overlay chama adb-tweaks.sh renderer" \
        || bad "overlay não chama o renderer do pack"
    for r in auto skiagl skiavk; do
        grep -q "\"$r\" to" "$svc" || bad "overlay sem o motor $r"
    done
    ok "overlay tem os motores de renderização principais"
    # fundo arredondado (visual mais organizado)
    grep -q 'rounded(' "$svc" && ok "overlay usa fundo arredondado" || bad "overlay sem estilo arredondado"
    # visual melhor: botões de vidro + blur do sistema
    grep -q 'FLAG_BLUR_BEHIND' "$svc" && grep -q 'blurBehindRadius' "$svc" \
        && ok "overlay pede blur do fundo (Android 12+)" || bad "overlay sem blur"
    grep -q 'private fun pill(' "$svc" && grep -q 'C_GLASS' "$svc" \
        && ok "overlay usa botões de vidro (pílula translúcida)" || bad "overlay sem botões de vidro"
    # o flutuante usa o tema do app (cor de destaque e fonte escolhidas no painel)
    grep -q 'OtmUi.accent' "$svc" && grep -q 'OtmUi.font' "$svc" \
        && ok "overlay usa a cor/fonte escolhidas no painel" || bad "overlay com tema fixo"
    grep -q 'OtmUi.onChanged' "$svc" && grep -q 'private fun rebuild()' "$svc" \
        && ok "overlay se redesenha quando o tema muda" || bad "overlay não acompanha o tema"
    # minimizar vira só o ÍCONE do app; tocar no ícone volta ao painel completo
    grep -q 'R.mipmap.ic_launcher' "$svc" && ok "overlay minimizado usa o ícone do app" \
        || bad "overlay minimizado não usa o ícone do app"
    grep -q 'ImageView' "$svc" && ok "overlay tem a bolha (ícone) de minimizado" \
        || bad "overlay sem ImageView para o ícone"
    grep -q 'setMinimized(false)' "$svc" && ok "tocar no ícone devolve o painel" \
        || bad "ícone não devolve o painel ao ser tocado"
    # a bolha minimizada tem de ARRASTAR: o toque é tratado pelo container, que
    # também tem o dragger. Se o ImageView de dentro tivesse listener de clique,
    # ele viraria "clickable" e engoliria o toque antes do container — a bolha
    # ficava presa no lugar. (Era o bug relatado no aparelho.)
    awk '/private fun bubbleView/,/^    }/' "$svc" > "$TMP/bubble"
    python3 - "$TMP/bubble" <<'PY' > "$TMP/bubbleres" 2>&1
import re, sys
s = open(sys.argv[1], encoding='utf-8').read()
i = s.index('ImageView(')
j = s.index('apply {', i)
depth, fim = 0, len(s)
for m in re.finditer(r'[{}]', s[j + len('apply {') - 1:]):
    depth += 1 if m.group(0) == '{' else -1
    if depth == 0:
        fim = j + len('apply {') - 1 + m.end()
        break
blk = s[j:fim]
if 'setOnClickListener' in blk:
    print('ImageView com clique engole o arrasto da bolha')
elif 'setOnClickListener' not in s:
    print('bolha sem clique para voltar ao painel')
else:
    print('OK')
PY
    assert_contains "$TMP/bubbleres" "OK" "app: bolha minimizada arrasta (clique no container)"
    # o acesso ao shell vem de fora (o Service não pede permissão sozinho)
    grep -q 'OtmRunner.current' "$src/PanelActivity.kt" \
        && ok "Activity publica o runner para o overlay" || bad "Activity não publica o runner"
    # sem permissão de sobreposição, manda o usuário para a tela do sistema
    grep -q 'ACTION_MANAGE_OVERLAY_PERMISSION' "$src/PanelActivity.kt" \
        && ok "Activity abre a tela de permissão de sobreposição" || bad "sem ACTION_MANAGE_OVERLAY_PERMISSION"
    # a ponte expõe o tipo "overlay" e o painel chama por ele
    grep -q '"overlay" ->' "$src/PackBridge.kt" \
        && ok "ponte trata o tipo overlay" || bad "ponte sem o tipo overlay"
    grep -q 'OTM.call("overlay"' "$ROOT/app/src/main/assets/panel/index.html" \
        && ok "painel do app chama o overlay" || bad "painel do app não chama o overlay"
    # o Service se recupera sozinho se o processo for reiniciado (o estático
    # OtmRunner volta nulo e TODA ação do flutuante dava erro no meio da partida)
    grep -q 'private fun shellRunner()' "$svc" \
        && ok "overlay tem um único ponto para o transporte de shell" \
        || bad "overlay sem shellRunner()"
    grep -q 'OtmRunner.current ?: runner' "$svc" \
        && ok "o transporte cai no recuperado quando o estático some" \
        || bad "overlay não usa o transporte recuperado"
    grep -q 'private fun registerShizukuRecovery()' "$svc" \
        && ok "overlay reconecta o Shizuku sozinho (processo reiniciado)" \
        || bad "overlay não se recupera sem abrir o app"
    grep -q 'addBinderReceivedListenerSticky' "$svc" \
        && ok "recuperação espera o binder do Shizuku chegar" \
        || bad "recuperação sem listener sticky"
    # nenhuma ação pode voltar a ler o estático direto (era a causa dos erros)
    grep -q 'OtmExec.run(this@OverlayService, OtmRunner.current' "$svc" \
        && bad "alguma ação ainda lê OtmRunner.current direto" \
        || ok "nenhuma ação lê o estático direto (só shellRunner())"
    # o veredito respeita o "ok=" dos scripts de leitura (sensi/ver tuning):
    # sem isso o flutuante dizia "sem mudança" no que é só leitura
    grep -q 'v\["ok"\]' "$svc" \
        && ok "overlay usa o veredito ok= dos scripts" || bad "overlay ignora ok="
    grep -q 'sem permissão de shell' "$svc" \
        && ok "overlay diz o que fazer quando falta o acesso" \
        || bad "overlay só diz 'falhou' sem orientar"
    # no site (PC) o overlay avisa que é só no celular
    grep -q 'Painel flutuante: use o app no celular' "$ROOT/web/index.php" \
        && ok "site avisa que o overlay é só no app" || bad "site sem aviso do overlay"
    # a ação aparece no catálogo dos dois painéis (mesma fonte: lib.php)
    grep -q 'overlay.sensi' "$ROOT/web/lib.php" \
        && ok "lib.php registra a ação do painel flutuante" || bad "lib.php sem overlay.sensi"
    grep -q 'overlay.sensi' "$ROOT/app/src/main/assets/panel/actions.json" \
        && ok "catálogo do app tem a ação do painel flutuante" || bad "actions.json sem overlay.sensi"
}


# --- toque do painel: só o dedo parado e curto dispara ------------------------
# O bug relatado no aparelho: arrastar a lista disparava o botão onde o dedo
# soltou (o "click" sintético do fim do scroll). A correção tem de estar no HTML
# dos DOIS painéis: o do app (index.html) e o do site (index.php).
t_tap_only() {
    printf '\n  # toque: arrastar não dispara botão (só toque parado e curto)\n'
    local app="$ROOT/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"

    for f in "$app" "$web"; do
        grep -q 'function tapOnly(el, fn)' "$f" \
            && ok "$(basename "$f"): tem o guarda de toque (tapOnly)" \
            || bad "$(basename "$f"): sem tapOnly (clique sintético dispara botão)"
        grep -q 'pointercancel' "$f" \
            && ok "$(basename "$f"): o guarda cancela no começo do arrasto" \
            || bad "$(basename "$f"): tapOnly sem pointercancel"
        # O cancelamento só pelo pointercancel não bastava: quando o dedo começa
        # no botão e arrasta, o navegador nem sempre emite o cancelamento e o
        # clique sintético do fim do scroll abria o botão. O arrasto é pego pela
        # variação do dedo (pointermove), pela posição no fim do toque (pointerup)
        # e pela rolagem da página.
        grep -q 'pointerup' "$f" \
            && ok "$(basename "$f"): confere a posição no fim do toque (pointerup)" \
            || bad "$(basename "$f"): tapOnly não confere a posição no pointerup"
        # pointerleave NÃO pode voltar: no toque ele dispara em TODO toque válido
        # (o dedo sai do elemento ao levantar), vinha antes do click e cancelava
        # tudo. Isso deixava os botões mortos, sem erro nenhum. A checagem ignora
        # comentários para não dar falso positivo pela citação do aviso.
        if grep -qE "addEventListener\(['\"]pointerleave" "$f"; then
            bad "$(basename "$f"): registra pointerleave no toque (mata todo clique válido)"
        else
            ok "$(basename "$f"): sem pointerleave no caminho do toque"
        fi
        grep -qE 'addEventListener\("scroll", cancel' "$f" \
            && ok "$(basename "$f"): cancela se a página rolar durante o toque" \
            || bad "$(basename "$f"): tapOnly não cancela na rolagem"
        # o toque tem de ser CURTO: um dedo parado por muito tempo não é clique
        grep -qE 'TAP_MS' "$f" \
            && ok "$(basename "$f"): o guarda limita a duração do toque" \
            || bad "$(basename "$f"): tapOnly sem limite de duração"
        # nenhum onclick cru pode sobrar: ele fura o guarda e dispara no scroll
        if grep -q 'onclick=' "$f"; then
            bad "$(basename "$f"): ainda há onclick cru (fura o guarda de toque)"
        else
            ok "$(basename "$f"): nenhum onclick cru (tudo passa pelo guarda)"
        fi
        # o disparo não pode ser um onclick puro: é isso que o scroll aciona
        grep -qE '\[data-run\]"\)\.forEach\(b => b\.onclick' "$f" \
            && bad "$(basename "$f"): [data-run] ainda usa onclick puro" \
            || ok "$(basename "$f"): [data-run] passa pelo guarda"
        grep -qE '\[data-vital-go\]"\)\.forEach\(b => b\.onclick' "$f" \
            && bad "$(basename "$f"): botão de vitalidade ainda usa onclick puro" \
            || ok "$(basename "$f"): botão de vitalidade passa pelo guarda"
    done
    # o gatilho nativo do app (o botão do cabeçalho) usa o mesmo critério
    local pa="$ROOT/app/src/main/java/com/otm/pack/PanelActivity.kt"
    grep -q 'function tapOnly(el, fn)' "$pa" \
        && ok "app: o botão do cabeçalho (flutuante) usa o mesmo guarda" \
        || bad "app: cabeçalho sem guarda de toque"
    grep -q 'pointercancel' "$pa" \
        && ok "app: o guarda do cabeçalho cancela no arrasto" \
        || bad "app: guarda do cabeçalho sem pointercancel"
    grep -q 'pointerup' "$pa" \
        && ok "app: o guarda do cabeçalho confere a posição no fim do toque" \
        || bad "app: guarda do cabeçalho não confere o pointerup"
    if grep -qE "addEventListener\(['\"]pointerleave" "$pa"; then
        bad "app: guarda do cabeçalho registra pointerleave (mata todo clique válido)"
    else
        ok "app: guarda do cabeçalho sem pointerleave no caminho do toque"
    fi
    grep -qE "addEventListener\(['\"]scroll['\"], cancel" "$pa" \
        && ok "app: o guarda do cabeçalho cancela na rolagem" \
        || bad "app: guarda do cabeçalho não cancela na rolagem"
}

t_shizuku_reconnect() {
    printf '\n  # Shizuku: não pedir permissão de novo a cada abertura\n'
    local pa="$ROOT/app/src/main/java/com/otm/pack/PanelActivity.kt"

    # A causa do bug: o binder do Shizuku chega DEPOIS do onCreate. Checar a
    # permissão só lá dentro concluía "não autorizado" com a permissão já dada.
    grep -q 'addBinderReceivedListenerSticky' "$pa" \
        && ok "espera o binder chegar (listener sticky)" || bad "não espera o binder (bug do pedido repetido)"
    grep -q 'OnBinderReceivedListener' "$pa" \
        && ok "reconecta quando o binder chega" || bad "sem OnBinderReceivedListener"
    grep -q 'addBinderDeadListener' "$pa" \
        && ok "limpa o runner quando o Shizuku morre" || bad "sem OnBinderDeadListener"
    # reconectar é silencioso: nada de requestPermission no caminho automático
    grep -q 'fun tryAutoConnectShizuku' "$pa" \
        && ok "conexão automática num ponto único" || bad "sem tryAutoConnectShizuku"
    awk '/fun tryAutoConnectShizuku/,/^    }/' "$pa" | grep -q 'requestPermission' \
        && bad "auto-conexão pede permissão (volta o bug)" \
        || ok "auto-conexão não pede permissão"
    # e volta do app do Shizuku reconecta sem perguntar
    grep -q 'override fun onResume' "$pa" \
        && ok "onResume tenta reconectar" || bad "sem onResume (permissão dada por fora não conecta)"
    # os listeners são removidos para não vazar a Activity
    grep -q 'removeBinderReceivedListener' "$pa" && grep -q 'removeBinderDeadListener' "$pa" \
        && ok "listeners removidos no onDestroy" || bad "listeners não removidos (vaza Activity)"
}

t_vitality() {
    printf '\n  # vitalidade: motor de longevidade (sem aparelho)\n'
    local vit="$ROOT/scripts/vitality.sh"
    local home="$TMP/vital_home"

    rm -rf "$home"; mkdir -p "$home"
    # OTM_MODE=direct simula o privilégio de shell (Shizuku/ADB já abriram o shell).
    # OTM_VIT_* injetam as leituras da bateria para verificar as decisões.
    # POSIX: nada de "${@:4}" (o dash do `sh` não entende). shift resolve.
    vl() { _h="$1"; _c="$2"; _t="$3"; _l="$4"; _s="$5"; shift 5
           HOME="$home" OTM_MODE=direct OTM_VIT_HEALTH="$_h" OTM_VIT_CYCLES="$_c" \
               OTM_VIT_TEMP="$_t" OTM_VIT_LEVEL="$_l" OTM_VIT_STATUS="$_s" \
               sh "$vit" "$@"; }
    score() { vl "$1" "$2" "$3" "$4" "$5" score 2>/dev/null | grep -E '^[0-9]+$' | head -1; }
    alrt()  { vl "$1" "$2" "$3" "$4" "$5" tick 2>/dev/null | grep -o 'alert=[^ ]*' | cut -d= -f2; }

    # 1) saúde real = base da nota; sem leitura NÃO inventa número
    [ "$(score 91 '' 35 60 discharging)" = 91 ] && ok "saúde vira a base da nota (91%)" \
        || bad "nota não reflete a saúde"
    [ -z "$(score '' '' '' '' '')" ] && ok "sem leitura de bateria: sem nota (não inventa)" \
        || bad "inventou nota sem leitura"
    [ -z "$(score abc '' '' '' '')" ] && ok "leitura inválida: sem nota" || bad "aceitou leitura inválida"
    [ -z "$(score 999 '' '' '' '')" ] && ok "saúde absurda (999%): descartada" || bad "aceitou 999%"
    vl abc '' '' '' '' score 2>&1 | grep -q 'Illegal' && bad "erro de shell com leitura inválida" \
        || ok "sem erro de shell com leitura inválida"

    # 2) ciclos e calor penalizam (desgaste acumulado e agressão)
    [ "$(score 91 900 30 60 discharging)" = 79 ] && ok "muitos ciclos (900): penaliza 12" \
        || bad "não penalizou ciclos altos"
    [ "$(score 91 500 30 60 discharging)" = 85 ] && ok "ciclos médios (500): penaliza 6" \
        || bad "não penalizou ciclos médios"
    [ "$(score 91 100 45 60 discharging)" = 81 ] && ok "calor (45°C): penaliza 10" \
        || bad "não penalizou o calor"

    # 3) guardião: avisa carga alta UMA vez por ciclo (não fica repetindo)
    rm -f "$home/.packotm/vitality"/f_* 2>/dev/null
    [ -n "$(alrt 91 '' 35 85 charging)" ] && ok "carregando a 85%: avisa (acima de 80%)" \
        || bad "não avisou carga alta"
    [ -z "$(alrt 91 '' 35 85 charging)" ] && ok "não repete o aviso a cada leitura" \
        || bad "ficou repetindo o aviso"
    vl 91 '' 35 70 charging tick >/dev/null 2>&1     # desceu: limpa o aviso
    [ -n "$(alrt 91 '' 35 85 charging)" ] && ok "novo ciclo de carga: avisa de novo" \
        || bad "não avisou no ciclo seguinte"
    [ -n "$(alrt 91 '' 44 50 charging)" ] && ok "carregando quente (44°C): avisa" \
        || bad "não avisou calor na tomada"
    [ -n "$(alrt 91 '' 41 50 discharging)" ] && ok "quente fora da tomada: aviso leve" \
        || bad "não avisou aparelho quente"
    [ -z "$(alrt 91 '' 32 50 discharging)" ] && ok "tudo normal: sem alerta" || bad "alerta falso"

    # 4) contadores do guardião acumulam e aparecem
    vl 91 '' 35 85 charging tick >/dev/null 2>&1
    vl 91 '' 35 70 charging tick >/dev/null 2>&1
    vl 91 '' 35 85 charging tick >/dev/null 2>&1
    vl 91 '' 35 50 discharging guard 2>/dev/null | grep -q 'cargas acima de 80%: [2-9]' \
        && ok "guardião conta as cargas altas" || bad "guardião não contou"

    # 5) modo longevidade: aplica de verdade (com os stubs) e é reversível
    local store="$TMP/store"
    rm -f "$store"/* 2>/dev/null
    HOME="$home" TMP_STORE="$store" PATH="$TMP/bin:$PATH" OTM_MODE=local \
        sh "$vit" care on >/dev/null 2>&1
    [ "$(cat "$store/system.peak_refresh_rate" 2>/dev/null)" = "60.0" ] \
        && ok "care on: tela em 60Hz (economia real)" || bad "care não fixou 60Hz"
    [ "$(cat "$store/global.wifi_scan_always_enabled" 2>/dev/null)" = "0" ] \
        && ok "care on: desliga varredura de Wi-Fi" || bad "care não desligou o scan"
    [ "$(cat "$store/global.adaptive_battery_management_enabled" 2>/dev/null)" = "1" ] \
        && ok "care on: economia do sistema LIGADA (o pack a desligava)" \
        || bad "care não ligou a economia do sistema"
    grep -q 'peak_refresh_rate' "$home/.packotm/undo/vitality.sh" 2>/dev/null \
        && ok "care registra a reversão no escopo vitality" || bad "care não registra reversão"
    HOME="$home" TMP_STORE="$store" PATH="$TMP/bin:$PATH" OTM_MODE=local \
        sh "$vit" care status 2>/dev/null | grep -q 'modo longevidade: on' \
        && ok "care status reporta ligado" || bad "care status errado"
    HOME="$home" TMP_STORE="$store" PATH="$TMP/bin:$PATH" OTM_MODE=local \
        sh "$vit" care off >/dev/null 2>&1
    HOME="$home" TMP_STORE="$store" PATH="$TMP/bin:$PATH" OTM_MODE=local \
        sh "$vit" care status 2>/dev/null | grep -q 'modo longevidade: off' \
        && ok "care off volta ao padrão" || bad "care off não voltou"

    # 6) optimize: o botao unico liga o cuidado E mostra o diagnostico
    rm -f "$home/.packotm/vitality/care" "$store"/* 2>/dev/null
    out="$(HOME="$home" TMP_STORE="$store" PATH="$TMP/bin:$PATH" OTM_MODE=local \
        OTM_VIT_HEALTH=88 OTM_VIT_CYCLES=210 OTM_VIT_LEVEL=57 OTM_VIT_TEMP=35 OTM_VIT_STATUS=discharging \
        sh "$vit" optimize 2>&1)"
    printf '%s' "$out" | grep -q 'saúde real: 88%' && ok "optimize mostra a saúde real" \
        || bad "optimize não mostrou a saúde"
    printf '%s' "$out" | grep -q 'nota de vitalidade: 88/100' && ok "optimize mostra a nota" \
        || bad "optimize não mostrou a nota"
    [ "$(cat "$store/system.peak_refresh_rate" 2>/dev/null)" = "60.0" ] \
        && ok "optimize ligou o modo longevidade (60Hz)" || bad "optimize não ligou o cuidado"
    [ "$(printf '%s' "$out" | grep -c '^#OTM-RESULT')" = 1 ] \
        && ok "optimize emite UMA linha de resultado (painel lê a primeira)" \
        || bad "optimize emite resultado duplicado"
    printf '%s' "$out" | grep -q '#OTM-VITAL' && ok "optimize publica o estado de vitalidade" \
        || bad "optimize sem linha #OTM-VITAL"

    # 6b) BUGS DO PAINEL (relatados pelo usuário): os botões de vitalidade precisam
    # respeitar a confirmação da ação e os cartões de opção precisam ficar lado a lado.
    local panel="$ROOT/app/src/main/assets/panel/index.html"
    # Bug #1: `.opts` fora de `.card-choice` (card Perfil de Desempenho) empilhava os
    # botões porque a regra de flex só valia para `.card-choice .opts`.
    grep -qE '^\.opts\{display:flex' "$panel" \
        && ok "painel: .opts é flex para QUALQUER card (Perfil de Desempenho lado a lado)" \
        || bad "painel: .opts ainda preso a .card-choice (botões empilhados)"
    grep -q '\.card-choice \.opts{display:flex' "$panel" \
        && bad "painel: regra antiga .card-choice .opts voltou" \
        || ok "painel: sem a regra antiga que empilhava o card"
    # Bug #2: clicar em "Otimizar saúde do telefone" (vital.optimize, que pede
    # confirmação) não pode chamar doRun com confirmed=false fixo — isso pulava o
    # modal e o servidor respondia "esta ação pede confirmação".
    grep -q 'if (a.confirm){ b.dataset.vitalId = id; askConfirm(b, a); return; }' "$panel" \
        && ok "painel: botão de vitalidade pede confirmação antes de rodar" \
        || bad "painel: botão de vitalidade pula a confirmação (erro 'pede confirmação')"
    grep -q 'p.dataset.vitalGo) doRun(ACTIONS\[p.dataset.vitalId\], {}, true, p)' "$panel" \
        && ok "painel: confirmar reexecuta a ação de vitalidade com confirm=true" \
        || bad "painel: runPending não sabe reexecutar a ação de vitalidade"
    grep -q 'function askConfirm(node, a)' "$panel" \
        && ok "painel: modal de confirmação extraído (askConfirm)" \
        || bad "painel: sem askConfirm"
    # o web (index.php) tem os mesmos cartões: precisa das mesmas correções
    grep -qE '^\.opts\{display:flex' "$ROOT/web/index.php" \
        && ok "web: .opts é flex para qualquer card" || bad "web: .opts preso a .card-choice"
    grep -q 'if (a.confirm){ b.dataset.vitalId = id; askConfirm(b, a); return; }' "$ROOT/web/index.php" \
        && ok "web: botão de vitalidade pede confirmação" || bad "web: vitalidade pula a confirmação"

    # 7) diag é SÓ LEITURA: não mexe em nada (nenhum applies)
    out="$(vl 91 120 36 64 discharging diag 2>&1)"
    printf '%s' "$out" | grep -q 'applies=0' && ok "diag é só leitura (applies=0)" \
        || bad "diag mexeu no aparelho"
    printf '%s' "$out" | grep -q 'saúde real: 91%' && ok "diag mostra a saúde real" \
        || bad "diag não mostrou a saúde"

    printf '\n  # vitalidade: registro de ações\n'
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
            $need=["vital.optimize"=>["vitality.sh","optimize"],
                   "vital.diag"=>["vitality.sh","diag"],
                   "vital.care_on"=>["vitality.sh","care","on"],
                   "vital.care_off"=>["vitality.sh","care","off"],
                   "vital.guard"=>["vitality.sh","guard"],
                   "vital.status"=>["vitality.sh","status"]];
            $ok=true;
            foreach($need as $k=>$v){ if(($a[$k]["argv"] ?? null) !== $v) $ok=false; }
            echo $ok ? "OK" : "NAO";' | grep -q OK \
        && ok "ações de vitalidade registradas com argv correto" || bad "ações de vitalidade erradas"
    php -r 'require "'"$ROOT"'/web/lib.php";
            echo in_array("vitality.sh", otm_allowed_scripts(), true) ? "OK":"NAO";' | grep -q OK \
        && ok "vitality.sh na whitelist" || bad "script fora da whitelist"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
            echo ($a["vital.care_off"]["risk"] ?? "") === "safe" ? "OK":"NAO";' | grep -q OK \
        && ok "desligar a longevidade é risk=safe" || bad "care_off não é safe"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
            echo ($a["vital.diag"]["group"] ?? "") === "Geral" ? "OK":"NAO";' | grep -q OK \
        && ok "Vitalidade dissolvida: ações em Geral" || bad "vital.diag fora de Geral"
    # GUARDA DE REGRESSÃO: o que já existia NÃO pode sumir (o usuário foi claro:
    # "não é pra remover nada"). Se alguém tirar, o teste acusa.
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
            $need=["turbo.perfmode_on","turbo.perfmode_off","apply","smart.auto",
                   "restore_all","game.keepalive","perm.battery","debloat.app.uninstall",
                   "profile.custom.apply","dns.cloudflare"];
            $falt=[];
            foreach($need as $k){ if(!isset($a[$k])) $falt[]=$k; }
            echo $falt ? "FALTA: ".implode(",",$falt) : "OK";' | grep -q OK \
        && ok "nada do pack original foi removido (pack, perfis, debloat, DNS...)" \
        || bad "alguma ação original do pack sumiu"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
            $n=0; foreach(array_keys($a) as $k){ if(strpos($k,"pilot.")===0) $n++; }
            echo $n===0 ? "OK":"NAO";' | grep -q OK \
        && ok "não existe mais ação de piloto forçado" || bad "sobrou ação de piloto"
    [ -f "$ROOT/scripts/thermal-pilot.sh" ] && bad "thermal-pilot.sh ainda existe" \
        || ok "thermal-pilot.sh removido (forçava o aparelho)"
    # vital.optimize: o botão único de saúde existe e é careful+confirm
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
            $v=$a["vital.optimize"] ?? null;
            echo ($v && $v["argv"]===["vitality.sh","optimize"] && $v["risk"]==="careful" && !empty($v["confirm"])) ? "OK":"NAO";' \
        | grep -q OK && ok "vital.optimize registrado (careful + confirmação)" \
        || bad "vital.optimize errado"

    printf '\n  # vitalidade: cockpit nos dois painéis\n'
    local app="$ROOT/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"
    for f in "$app" "$web"; do
        grep -q 'data-vital-card' "$f" && ok "$(basename "$f"): card de vitalidade existe" \
            || bad "$(basename "$f"): sem card de vitalidade"
        grep -q 'renderVital' "$f" && ok "$(basename "$f"): desenha o estado real" \
            || bad "$(basename "$f"): não desenha o estado"
        grep -q 'data-perfmode-card' "$f" && ok "$(basename "$f"): card Perfil de Desempenho presente" \
            || bad "$(basename "$f"): REMOVIDO o card Perfil de Desempenho"
        grep -q 'applyPerfmode' "$f" && ok "$(basename "$f"): Perfil de Desempenho responde" \
            || bad "$(basename "$f"): Perfil de Desempenho sem handler"
        grep -q 'Otimizar saúde do telefone' "$f" && ok "$(basename "$f"): botão de saúde do telefone" \
            || bad "$(basename "$f"): sem o botão de saúde"
        grep -q 'querySelectorAll(".card-choice .opt")' "$f" \
            && ok "$(basename "$f"): handler de .opt escopado" || bad "$(basename "$f"): handler global"
        grep -q 'vital.care_on' "$f" && grep -q 'vital.guard' "$f" \
            && ok "$(basename "$f"): botões ligam a ações reais" || bad "$(basename "$f"): botões soltos"
    done
    # paridade web x app do card e do JS
    python3 - "$app" "$web" <<'PY' | grep -q IGUAIS \
        && ok "web e app: card de vitalidade idêntico" || bad "web e app: card divergiu"
import re, sys
def blk(p, pat):
    s = open(p, encoding='utf-8').read()
    m = re.search(pat, s)
    return re.sub(r'\s+', ' ', m.group(0)).strip() if m else None
C = r'<div class="panelbox[^"]*config-gpu-card[\s\S]*?\n      </div>'
J = r'/\* ---- vitalidade: cockpit de longevidade -+\n[\s\S]*?\n\}\)+;\n'
print("IGUAIS" if blk(sys.argv[1], C) and blk(sys.argv[1], C) == blk(sys.argv[2], C)
      and blk(sys.argv[1], J) == blk(sys.argv[2], J) else "DIFERENTES")
PY

    # o estado de vitalidade chega ao painel
    PATH="$TMP/bin:$PATH" OTM_MODE=local sh "$ROOT/scripts/panel-state.sh" > "$TMP/vst" 2>/dev/null
    python3 - "$TMP/vst" <<'PY' | grep -q OK \
        && ok "panel-state emite os campos de vitalidade" || bad "panel-state sem campos de vitalidade"
import json, sys
d = json.load(open(sys.argv[1]))
need = ["vital_health","vital_cycles","vital_temp","vital_score","vital_care","vital_w80","vital_alert"]
print("OK" if all(k in d for k in need) else "NAO")
PY
    grep -q 'vitality.sh" tick' "$ROOT/scripts/panel-stats.sh" \
        && ok "panel-stats chama o tick (batimento do guardião)" \
        || bad "panel-stats não chama o tick"
    # GUARDA: o ACTIONS do web é GERADO pelo PHP a cada requisição (não é JSON fixo).
    # Um JSON fixo envelhece: adicionar uma ação no lib.php deixaria de aparecer no web.
    grep -q 'json_encode(array_column' "$web" \
        && ok "web: ACTIONS é gerado pelo PHP (não é JSON fixo)" \
        || bad "web: ACTIONS virou JSON fixo (o web para de ver ações novas)"
    # GUARDA: o card Perfil de Desempenho continua respondendo de verdade (não é decorativo)
    for f in "$app" "$web"; do
        grep -q 'turbo.perfmode_on' "$f" && grep -q 'turbo.perfmode_off' "$f" \
            && ok "$(basename "$f"): Perfil de Desempenho chama as ações reais" \
            || bad "$(basename "$f"): Perfil de Desempenho sem ação real"
    done

    # o espelho do app bate com scripts/
    cmp -s "$ROOT/scripts/vitality.sh" "$ROOT/app/src/main/assets/pack/scripts/vitality.sh" \
        && ok "vitality.sh espelhado no app" || bad "espelho do vitality.sh divergiu"
}

# --- perfil personalizado: escolhas (seg) e liga/desliga (toggle) -------------
t_custom_profile() {
    printf '\n  # perfil personalizado: escolhas e toggles liga/desliga\n'
    local panel="$ROOT/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"

    # 1) a fonte única das opções tem as duas formas: escolha e liga/desliga
    php -r 'require "'"$ROOT"'/web/lib.php"; $o=otm_custom_profile_opts();
             $seg=0; $tgl=0; foreach ($o as $c){ ($c["kind"] ?? "seg")==="toggle" ? $tgl++ : $seg++; }
             echo "seg=$seg toggle=$tgl total=" . count($o) . "\n";' > "$TMP/cp_kinds" 2>&1
    assert_contains "$TMP/cp_kinds" "toggle=" "perfil: há opções liga/desliga"
    assert_contains "$TMP/cp_kinds" "seg=" "perfil: há opções de escolha"
    php -r 'require "'"$ROOT"'/web/lib.php"; $o=otm_custom_profile_opts();
             $bad=0; foreach ($o as $c){
               if (($c["kind"] ?? "seg") !== "toggle") continue;
               $t=$c["tgl"] ?? null;
               if (!is_array($t) || ($t["off"] ?? "")==="" || ($t["on"] ?? "")==="") $bad++;
               if (($t["off"] ?? null) === ($t["on"] ?? null)) $bad++;
             }
             echo $bad===0 ? "OK\n" : "RUIM:$bad\n";' > "$TMP/cp_tgl" 2>&1
    assert_contains "$TMP/cp_tgl" "OK" "perfil: todo toggle tem off e on distintos"

    # 2) o argv da ação cobre TODAS as chaves, na MESMA ordem do script
    php -r 'require "'"$ROOT"'/web/lib.php";
             $a=otm_actions()["profile.custom.apply"];
             $args=array_values(array_filter($a["argv"], fn($v)=>$v!=="profile-custom.sh"&&$v!=="apply"));
             $names=array_map(fn($p)=>"{".$p["name"]."}", $a["params"]);
             echo implode(" ",$args) === implode(" ",$names) ? "OK\n" : "DIVERGE\n";
             echo count($args), "\n";' > "$TMP/cp_argv" 2>&1
    assert_contains "$TMP/cp_argv" "OK" "perfil: argv casa com params (mesma ordem)"
    # a MESMA ordem também no script: os argumentos são posicionais, então um
    # PC_ORDER fora de sincronia aplica a opção errada em silêncio.
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions()["profile.custom.apply"];
             echo implode(" ", array_map(fn($p)=>$p["name"], $a["params"])), "\n";' > "$TMP/cp_php" 2>&1
    awk '/^PC_ORDER="/{f=1} f{printf "%s ", $0} f&&/"[ \t]*$/{exit}' "$ROOT/scripts/profile-custom.sh" \
        | tr -d '\\"' | sed 's/PC_ORDER=//' | tr -s ' ' | sed 's/^ //; s/ $//' > "$TMP/cp_sh"
    [ "$(cat "$TMP/cp_php")" = "$(cat "$TMP/cp_sh")" ] \
        && ok "perfil: PC_ORDER igual ao argv do painel (mesma ordem)" \
        || bad "perfil: PC_ORDER fora de sincronia com o painel"

    # 3) o toggle tem marcação, CSS e clique nos DOIS painéis
    for f in "$panel" "$web"; do
        grep -q 'data-kind="toggle"' "$f" \
            && ok "$(basename "$f"): linhas de toggle marcadas" || bad "$(basename "$f"): sem data-kind"
        # o switch do perfil é .cpsw (o .sw é o swatch de cor da aparência;
        # os dois colidiam no mesmo nome e o switch virava pílula cinza).
        grep -q 'class="cpsw"' "$f" \
            && ok "$(basename "$f"): o switch existe no HTML" || bad "$(basename "$f"): sem switch"
        grep -q 'aria-checked' "$f" \
            && ok "$(basename "$f"): o switch tem estado acessível" || bad "$(basename "$f"): switch sem aria-checked"
        grep -qE '^\.cpsw\[aria-checked="true"\]' "$f" \
            && ok "$(basename "$f"): o CSS pinta o switch ligado" || bad "$(basename "$f"): CSS do switch ausente"
        grep -q 'data-off=' "$f" \
            && ok "$(basename "$f"): o switch carrega o valor desligado" || bad "$(basename "$f"): switch sem valor off"
        grep -q 'data-on=' "$f" \
            && ok "$(basename "$f"): o switch carrega o valor ligado" || bad "$(basename "$f"): switch sem valor on"
        grep -q 'const CPROF_DEFAULT' "$f" \
            && ok "$(basename "$f"): o padrão vem da fonte única" || bad "$(basename "$f"): sem CPROF_DEFAULT"
    done

    # 4) o padrão do toggle é DESLIGADO (nunca liga nada sozinho)
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions()["profile.custom.apply"];
             $o=otm_custom_profile_opts(); $bad=[];
             foreach ($o as $c){ if (($c["kind"] ?? "seg") !== "toggle") continue;
               foreach ($a["params"] as $p) if ($p["name"]===$c["k"] && $p["default"]!==$c["tgl"]["off"]) $bad[]=$c["k"]; }
             echo $bad ? "RUIM:".implode(",",$bad)."\n" : "OK\n";' > "$TMP/cp_def" 2>&1
    assert_contains "$TMP/cp_def" "OK" "perfil: toggle começa desligado no painel"

    # 5) o script aceita os valores do toggle e não quebra com valor inválido
    local home="$TMP/cp_home" cfg="$TMP/cp_home/.packotm/profile-custom/config"
    rm -rf "$home"; mkdir -p "$home"
    pc() { HOME="$home" OTM_MODE=local sh "$ROOT/scripts/profile-custom.sh" "$@"; }
    pc set telemetry=off gpu=on 2>&1 | grep -qi 'inválid\|erro' \
        && bad "perfil: recusou um toggle válido" || ok "perfil: aceita os valores do toggle"
    grep -q '^telemetry=off$' "$cfg" 2>/dev/null && grep -q '^gpu=on$' "$cfg" 2>/dev/null \
        && ok "perfil: guarda a escolha do toggle" || bad "perfil: não guardou o toggle"
    pc set telemetry=banana >/dev/null 2>&1
    grep -q '^telemetry=off$' "$cfg" 2>/dev/null \
        && ok "perfil: valor inválido não sobrescreve o válido" || bad "perfil: aceitou valor inválido"
    # toda chave do PC_ORDER aceita um valor NÃO padrão (o de ligar): prova que o
    # script reconhece a chave e grava o valor, e não só ecoa o default no `show`.
    local key val missing="" rc
    for key in $(awk '/^PC_ORDER="/{f=1} f{printf "%s ", $0} f&&/"[ \t]*$/{exit}' \
                     "$ROOT/scripts/profile-custom.sh" | tr -d '\\"' | sed 's/PC_ORDER=//'); do
        val="$(pc_opts_of "$key")"
        pc set "$key" "$val" >/dev/null 2>&1; rc=$?
        [ "$rc" = "0" ] || missing="$missing $key=$val(rc=$rc)"
        grep -q "^$key=$val\$" "$home/.packotm/profile-custom/config" 2>/dev/null \
            || missing="$missing $key=não-gravou"
    done
    [ -z "$missing" ] && ok "perfil: todas as chaves do script aceitam um valor de ligar" \
        || bad "perfil: chaves recusadas:$missing"
    rm -rf "$home"
}

# valor de "ligar" de uma chave (o último da lista), lido do próprio script: garante
# que o teste não invente um valor que o script recusa.
pc_opts_of() {
    sed -n "s/^[[:space:]]*$1)[[:space:]]*echo \"\([^\"]*\)\".*/\1/p" \
        "$ROOT/scripts/profile-custom.sh" | awk '{print $NF}'
}

t_thermal_gate
t_secret_scanner
t_site_html
t_marca_trix
t_build_plugins
t_build_modules
t_build_pack
t_debloat
t_dns
t_game_per_app
t_new_scripts
t_modules
t_web
t_panel_v219
t_keepalive
t_gameclean
t_ramboost
t_resolution
t_smart_opt
t_smart_bigdump
t_smart_learning
t_backup_crypto
t_smart_card_single
t_clean
t_smart_clean_protect
t_privilege_detect
# --- interruptores (liga/desliga) e o painel de saude dentro de Geral ---------
t_toggles_registry() {
    printf '\n  # interruptores: registro, estado real e paridade web/app\n'
    local panel="$ROOT/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"
    local st="$ROOT/scripts/panel-state.sh"

    # 1) o registro tem interruptores e todo um tem par on/off distinto
    php -r 'require "'"$ROOT"'/web/lib.php"; $t=otm_toggles();
             echo count($t), "\n";' > "$TMP/tg_n" 2>&1
    [ "$(cat "$TMP/tg_n")" -ge 10 ] && ok "registro: ha interruptores ($(cat "$TMP/tg_n"))" \
        || bad "registro: poucos interruptores ($(cat "$TMP/tg_n"))"
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions(); $t=otm_toggles(); $bad=[];
             foreach ($t as $id=>$g){
               foreach (["on","off"] as $k){
                 $aid=$g[$k] ?? "";
                 if ($aid==="" || !isset($a[$aid])) { $bad[]="$id.$k->$aid"; continue; }
               }
               if (($g["on"] ?? "") === ($g["off"] ?? "")) $bad[]="$id: on==off";
             }
             echo $bad ? implode(", ", $bad) : "OK";' > "$TMP/tg_ids" 2>&1
    assert_contains "$TMP/tg_ids" "OK" "registro: todo interruptor aponta para acoes que existem"

    # 2) o estado de cada interruptor e REAL: a chave vem de panel-state.sh
    #    (nao pode ser inventada no painel)
    php -r 'require "'"$ROOT"'/web/lib.php"; foreach (otm_toggles() as $g){
               if (($g["state"] ?? "") !== "") echo $g["state"], "\n"; }' > "$TMP/tg_keys" 2>&1
    : > "$TMP/tg_missing"
    while read -r k; do
        [ -n "$k" ] || continue
        grep -q "\"$k\"" "$st" || echo "$k" >> "$TMP/tg_missing"
    done < "$TMP/tg_keys"
    [ ! -s "$TMP/tg_missing" ] \
        && ok "estado real: toda chave de interruptor vem de panel-state.sh" \
        || bad "estado inventado no painel: $(tr '\n' ' ' < "$TMP/tg_missing")"

    # 3) os interruptores aparecem nos DOIS paineis com o mesmo conjunto de acoes.
    #    O web e um template PHP: o que importa e o HTML RENDERIZADO, nao a fonte.
    php -r 'require "'"$ROOT"'/web/auth.php"; otm_auth_start(); $_SESSION["otm_user"]="x";
             $_SERVER["REQUEST_METHOD"]="GET"; ob_start();
             require "'"$ROOT"'/web/index.php"; echo ob_get_clean();' > "$TMP/tg_web.html" 2>/dev/null
    for f in "$panel" "$TMP/tg_web.html"; do
        n=$(grep -o 'data-toggle="[^"]*"' "$f" | sort -u | wc -l)
        [ "$n" -ge 10 ] && ok "$(basename "$f"): interruptores renderizados ($n)" \
            || bad "$(basename "$f"): faltam interruptores ($n)"
        grep -q 'data-on-state' "$f" && ok "$(basename "$f"): estado do interruptor ligado ao DOM" \
            || bad "$(basename "$f"): sem data-on-state"
    done
    a=$(grep -o 'data-toggle="[^"]*"' "$panel" | sort -u)
    b=$(grep -o 'data-toggle="[^"]*"' "$TMP/tg_web.html" | sort -u)
    [ "$a" = "$b" ] && ok "interruptores: web e app tem o mesmo conjunto" \
        || bad "interruptores: web e app divergem"

    # 4) o par de valores que acende o interruptor casa com o estado real lido
    php -r 'require "'"$ROOT"'/web/lib.php"; $bad=[];
             foreach (otm_toggles() as $id=>$g){
               $v=$g["on_values"] ?? null;
               if (!is_array($v) || count($v)===0) $bad[]=$id;
             }
             echo $bad ? implode(", ", $bad) : "OK";' > "$TMP/tg_vals" 2>&1
    assert_contains "$TMP/tg_vals" "OK" "interruptores: todo um declara o valor que o acende"

    # 5) saude do telefone: um unico card (na Home), sem categoria propria
    n=$(grep -c 'data-vital-card' "$web")
    [ "$n" -ge 1 ] && ok "saude do telefone: card existe no painel web" \
        || bad "saude do telefone: card sumiu"
    grep -q 'class="vpick"' "$web" && ok "saude do telefone: card virou seletor (vpick)" \
        || bad "saude do telefone: sem seletor"
    if grep -q 'id="g-Vitalidade"' "$web" || grep -q 'id="g-Vitalidade"' "$panel"; then
        bad "saude do telefone: ainda existe categoria Vitalidade separada"
    else
        ok "saude do telefone: dissolvida nas abas (sem categoria propria)"
    fi
}

t_toggles_registry
t_undo_scope
t_undo_scopes_declared
t_no_silent_conflicts
t_vitality
t_custom_profile
t_pack
t_proc_limit
t_latency
t_sensi
t_effects
t_overlay
t_tap_only
t_shizuku_reconnect

printf '\n  --------------------------------------------------\n'
printf '  %d passaram, %d falharam\n' "$PASS" "$FAIL"
printf '  --------------------------------------------------\n'
rm -rf "$TMP"
[ "$FAIL" = "0" ] || exit 1
exit 0
