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
  put)    printf '%s' "$4" > "$TMP_STORE/$2.$3" ;;
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
    # pm: registra chamadas e simula `pm list packages`
    cat > "$TMP/bin/pm" <<'EOF'
#!/bin/sh
[ -n "$TMP_PM_LOG" ] && echo "$*" >> "$TMP_PM_LOG"
if [ "$1" = "list" ]; then
    shift
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
    printf '#!/bin/sh\ncase "$1" in -n) echo cubic;; esac\nexit 0\n' > "$TMP/bin/sysctl"
    printf '#!/bin/sh\necho ""\n' > "$TMP/bin/getprop"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/setprop"
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

t_per_module() {
    printf '\n  # deep-tune: reverter um módulo não afeta os outros\n'
    rm -rf "$HOME/.packotm/deep"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle add com.dts.freefireth >/dev/null 2>&1
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" freq off >/dev/null 2>&1
    assert_contains "$(deep_off)" '^angle' "freq off preserva as linhas do angle"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" restore >/dev/null 2>&1
}

# descobre onde o plugin guardou o estado (STATE pode cair no fallback $DIR/state)
plugin_state() {
    if [ -f /data/adb/packotm/deep_mark ] || [ -d /data/adb/packotm ]; then
        echo /data/adb/packotm
    else
        echo "$1/state"
    fi
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
    printf '\n  # deep-tune: trava térmica exige confirmação explícita\n'
    rm -rf "$HOME/.packotm/deep"
    # não interativo e sem THERMAL_OK: deve recusar (código != 0)
    OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" thermal on </dev/null >/dev/null 2>&1
    assert_eq "1" "$?" "thermal on sem confirmação é recusado"
    # com THERMAL_OK=1: prossegue (sem zonas térmicas, apenas não aplica nada)
    THERMAL_OK=1 OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" thermal on </dev/null >/dev/null 2>&1
    assert_eq "0" "$?" "thermal on com THERMAL_OK=1 é aceito"
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
}

# --- execução ----------------------------------------------------------------
printf '  ==================================================\n'
printf '  Testes do Pack de Otimização\n'
printf '  ==================================================\n'
setup_stubs
t_syntax
t_angle_tag
t_per_module
t_plugin_mark_once
t_plugin_restore
t_freezer_whitelist
t_thermal_gate
t_secret_scanner
t_site_html
t_build_plugins
t_build_modules
t_build_pack
t_debloat

printf '\n  --------------------------------------------------\n'
printf '  %d passaram, %d falharam\n' "$PASS" "$FAIL"
printf '  --------------------------------------------------\n'
rm -rf "$TMP"
[ "$FAIL" = "0" ] || exit 1
exit 0
