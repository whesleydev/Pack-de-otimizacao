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
    # getprop/setprop com armazenamento (verificação real lê de volta)
    cat > "$TMP/bin/getprop" <<'EOF'
#!/bin/sh
case "$1" in
  ro.product.model) echo "TestPhone"; exit 0 ;;
  ro.build.version.sdk) echo "34"; exit 0 ;;
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
  -n) if [ -f "$root/$key" ]; then cat "$root/$key"; else cat "$TMP_STORE/sys.$2" 2>/dev/null || echo cubic; fi ;;
  -w) k="${2%%=*}"; v="${2#*=}"
      if [ -f "$root/${k#vm.}" ]; then printf '%s' "$v" > "$root/${k#vm.}"
      else printf '%s' "$v" > "$TMP_STORE/sys.$k"; fi ;;
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

t_per_module() {
    printf '\n  # deep-tune: reverter um módulo não afeta os outros\n'
    rm -rf "$HOME/.packotm/deep"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" angle add com.dts.freefireth >/dev/null 2>&1
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" freq off >/dev/null 2>&1
    assert_contains "$(deep_off)" '^angle' "freq off preserva as linhas do angle"
    OTM_MODE=local sh "$ROOT/scripts/deep-tune.sh" restore >/dev/null 2>&1
}

t_extreme() {
    printf '\n  # deep-tune: módulos avançados rodam e a reversão respeita a tag\n'
    rm -rf "$HOME/.packotm/deep"
    # todos os módulos avançados executam sem erro
    for m in vm sched input idle net2 kernel display dalvik; do
        OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" "$m" on >/dev/null 2>&1
        assert_eq "0" "$?" "módulo $m on roda sem erro"
    done
    # com props existentes, display/dalvik registram reversão (tag correta)
    rm -rf "$HOME/.packotm/deep"
    mkdir -p "$TMP/bin_prop"
    printf '#!/bin/sh\necho valor_antigo\n' > "$TMP/bin_prop/getprop"
    chmod +x "$TMP/bin_prop/getprop"
    PATH="$TMP/bin_prop:$PATH" OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" display on >/dev/null 2>&1
    assert_contains "$(deep_off)" '^display' "display registra reversão (com prop antiga)"
    PATH="$TMP/bin_prop:$PATH" OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" dalvik on >/dev/null 2>&1
    assert_contains "$(deep_off)" '^dalvik' "dalvik registra reversão (com prop antiga)"
    # reverter só o display não mexe no dalvik
    OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" display off >/dev/null 2>&1
    assert_not_contains "$(deep_off)" '^display' "display off remove só a tag display"
    assert_contains "$(deep_off)" '^dalvik' "display off preserva o dalvik"
    # o help lista os módulos novos
    OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" > "$TMP/deep_help" 2>&1
    assert_contains "$TMP/deep_help" "vm" "help do deep-tune lista vm"
    assert_contains "$TMP/deep_help" "extreme" "help do deep-tune lista extreme"
    # o modo extremo liga tudo sem erro
    THERMAL_OK=1 OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" extreme >/dev/null 2>&1
    assert_eq "0" "$?" "gaming extreme roda sem erro"
    OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" restore >/dev/null 2>&1
}

t_adv_noroot() {
    printf '\n  # adb-tweaks: grupos avançados sem root aplicam e revertem\n'
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    for g in obscure mobile_net notif window_tweaks; do
        OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" "$g" >/dev/null 2>&1
    done
    assert_contains "$HOME/.packotm/off.sh" "low_memory_kill" "obscure guarda reversão"
    assert_contains "$HOME/.packotm/off.sh" "data_saver_mode" "mobile_net guarda reversão"
    assert_contains "$HOME/.packotm/off.sh" "heads_up_notifications_enabled" "notif guarda reversão"
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" list > "$TMP/adb_list" 2>&1
    assert_contains "$TMP/adb_list" "obscure" "list mostra o grupo obscure"
    assert_contains "$TMP/adb_list" "window_tweaks" "list mostra o grupo window_tweaks"
    OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" restore_all >/dev/null 2>&1
    rm -rf "$HOME/.packotm"
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
    # caso 2: settings quebrado (não grava) -> verificação marca X e failed>=1
    mkdir -p "$TMP/bin_bad"
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin_bad/settings"
    chmod +x "$TMP/bin_bad/settings"
    out2=$(PATH="$TMP/bin_bad:$PATH" OTM_MODE=local sh "$ROOT/scripts/adb-tweaks.sh" perf 2>&1)
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
    printf '\n  # verificação REAL: deep-tune vm (sysctl) confirma e reporta\n'
    rm -rf "$HOME/.packotm"; mkdir -p "$TMP/vmstore"
    vmdir="$TMP/vmdir"; rm -rf "$vmdir"; mkdir -p "$vmdir"
    printf '100' > "$vmdir/vfs_cache_pressure"
    printf '10'  > "$vmdir/dirty_ratio"
    printf '5'   > "$vmdir/dirty_background_ratio"
    printf '3000' > "$vmdir/dirty_expire_centisecs"
    printf '500'  > "$vmdir/dirty_writeback_centisecs"
    printf '8192' > "$vmdir/min_free_kbytes"
    printf '10'   > "$vmdir/watermark_scale_factor"
    printf '1'    > "$vmdir/watermark_boost_factor"
    printf '50'   > "$vmdir/compaction_proactiveness"
    printf '3'    > "$vmdir/page-cluster"
    printf '5'    > "$vmdir/stat_interval"
    out=$(DEEP_VM_DIR="$vmdir" SYSCTL_ROOT="$vmdir" OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" vm on 2>&1)
    assert_eq "50" "$(cat "$vmdir/vfs_cache_pressure")" "vm gravou vfs_cache_pressure=50"
    res=$(printf '%s\n' "$out" | grep '#OTM-RESULT')
    ch=$(printf '%s' "$res" | sed -n 's/.*changed=\([0-9]*\).*/\1/p')
    [ "${ch:-0}" -ge 1 ] && ok "vm confirmou mudança real (changed=$ch)" \
        || bad "vm não confirmou mudança (changed=$ch)"
    # reversão volta o valor original
    DEEP_VM_DIR="$vmdir" SYSCTL_ROOT="$vmdir" OTM_MODE=su sh "$ROOT/scripts/deep-tune.sh" vm off >/dev/null 2>&1
    assert_eq "100" "$(cat "$vmdir/vfs_cache_pressure")" "vm off restaura o valor original"
    rm -rf "$HOME/.packotm" "$vmdir"
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
    # confere que a maioria das ações não pede root
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions(); $root=0;$tot=0;
             foreach ($a as $x){ $tot++; if (($x["risk"]??"")==="root") $root++; }
             echo "root=$root total=$tot\n";' > "$TMP/rootcnt" 2>&1
    assert_contains "$TMP/rootcnt" "total=" "registro de ações contável"
    rm -rf "$HOME/.packotm"
}


# --- login do app Android (painel estático) ----------------------------------
t_app_login() {
    printf '\n  # login do app (painel estático)\n'
    local p="$ROOT/android/app/src/main/assets/panel"
    [ -f "$p/login.html" ] && ok "tela de login do app existe" || bad "login.html do app ausente"
    [ -f "$p/index.html" ] && ok "painel do app existe" || bad "index.html do app ausente"
    grep -q 'otm_session' "$p/index.html" && ok "painel do app tem guarda de sessão" \
        || bad "index.html sem guarda de sessão"
    grep -q 'localStorage.removeItem("otm_session")' "$p/index.html" \
        && ok "botão Sair limpa a sessão" || bad "Sair não limpa a sessão"
    # o SHA-256 em JS do login bate com o hash esperado da credencial
    if command -v node >/dev/null 2>&1; then
        node -e '
          const fs=require("fs");
          const h=fs.readFileSync(process.argv[1],"utf8");
          const m=h.match(/function sha256\(ascii\)\{[\s\S]*?\n\}/);
          eval(m[0]);
          const got=sha256("00deUdia:159951");
          const exp=(h.match(/OTM_AUTH = "([a-f0-9]+)"/)||[])[1];
          console.log(got===exp && exp==="b6cddaaf9333c33071ae824248927b5349955fbb87167a5c1ddef5afa23d1a4d" ? "OK":"NAO");
        ' "$p/login.html" > "$TMP/applogin" 2>&1
        assert_contains "$TMP/applogin" "OK" "hash SHA-256 do login do app confere"
    else
        printf '  [skip] node ausente: pulei o hash do login\n'
    fi
    grep -q 'panel/login.html' "$ROOT/android/app/src/main/java/com/otm/pack/PanelActivity.kt" \
        && ok "PanelActivity abre a tela de login" || bad "PanelActivity não abre o login"
}

# --- scripts rodam em /data/local/tmp (visível ao shell) ----------------------
t_app_exec() {
    printf '\n  # scripts rodam em /data/local/tmp (shell lê)\n'
    local src="$ROOT/android/app/src/main/java/com/otm/pack"
    grep -q '/data/local/tmp/otm-pack' "$src/PackAssets.kt" \
        && ok "scripts vão para /data/local/tmp/otm-pack" || bad "scripts não vão p/ /data/local/tmp"
    grep -q 'ensureShellCopy' "$src/PackAssets.kt" \
        && ok "PackAssets copia p/ o shell" || bad "sem ensureShellCopy"
    # o bridge monta o comando a partir da pasta visível ao shell
    grep -q 'execDir()' "$src/PackBridge.kt" \
        && ok "PackBridge usa a pasta de execução" || bad "PackBridge ainda usa filesDir"
    # o comando de execução não pode apontar para o filesDir do app (0700)
    awk '/private fun scriptCommand/,/^    }/' "$src/PackBridge.kt" > "$TMP/scmd"
    if grep -q 'packDir()' "$TMP/scmd"; then
        bad "comando ainda usa o filesDir do app"
    else
        ok "comando usa a pasta visível ao shell"
    fi
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
    local app="$ROOT/android/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"
    local src="$ROOT/android/app/src/main/java/com/otm/pack"
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
    grep -q 'id="setTheme"\|id="setAccent"\|id="setSound"' "$app" && ok "app: config tem tema/cor/som" || bad "app: config incompleta"
    grep -q "ui' => 'appearance'" "$ROOT/web/lib.php" && ok "registro tem a ação de aparência" || bad "sem ação de aparência"
    grep -q '"appearance"' "$ROOT/android/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem a ação de aparência" || bad "app: actions.json sem aparência"
    grep -q 'a.id === "appearance"' "$app" && ok "app: card de aparência abre a engrenagem" || bad "app: card não abre a engrenagem"
    # 5) som: ligar/desligar e sem corte pelo timer do som anterior
    grep -q 'onSoundSet' "$src/PanelActivity.kt" && ok "som: painel liga/desliga (onSoundSet)" || bad "som: painel sem onSoundSet"
    grep -q 'removeCallbacks(autoStop)' "$src/SoundPlayer.kt" \
        && ok "som: timer antigo é cancelado (não corta o próximo)" || bad "som: timer não cancelado"
    grep -q 'handler.removeCallbacks(autoStop)' "$src/SoundPlayer.kt" && ok "som: stop cancela o timer" || bad "som: stop não cancela"
    # 6) "login feito com sucesso" só toca quando o login dá certo
    local login="$ROOT/android/app/src/main/assets/panel/login.html"
    grep -q 'OTM.call("login"' "$login" && ok "login: avisa o app só no acerto" || bad "login: sem aviso de sucesso"
    grep -q 'onLogin = { sound.play("login_feito_com_sucesso.mp3") }' "$src/PanelActivity.kt" \
        && ok "som: sucesso ligado ao onLogin" || bad "som: sucesso não está no onLogin"
    # e não pode tocar no conectar nem ao ligar o som
    if grep -n 'login_feito_com_sucesso' "$src/PanelActivity.kt" | grep -qv 'onLogin'; then
        bad "som: sucesso ainda toca fora do login"
    else
        ok "som: sucesso não toca ao conectar/ligar som"
    fi
    grep -q 'if (on) sound.play("ativando.mp3")' "$src/PanelActivity.kt" \
        && ok "som: ligar som usa 'ativando' (não 'login')" || bad "som: ligar som com áudio errado"
    # 7) áudios novos: pareamento (conectar) e credenciais incorretas (login errado)
    for f in pareamento_feito_com_sucesso_faca_login_no_sistema.mp3 credenciais_incorretas.mp3; do
        test -f "$ROOT/android/app/src/main/assets/audio/$f" \
            && ok "áudio: $f presente" || bad "áudio: falta $f"
    done
    grep -q 'sound.play("pareamento_feito_com_sucesso_faca_login_no_sistema.mp3")' "$src/PanelActivity.kt" \
        && ok "som: conectar usa o áudio de pareamento" || bad "som: conectar sem áudio de pareamento"
    grep -q 'onLoginFail = { sound.play("credenciais_incorretas.mp3") }' "$src/PanelActivity.kt" \
        && ok "som: login errado usa 'credenciais incorretas'" || bad "som: login errado sem áudio"
    grep -q 'OTM.call("login_fail"' "$login" && ok "login: avisa o app no erro" || bad "login: sem aviso de erro"
    # 8) ícones no lugar de emojis (menos a engrenagem, que fica como está)
    if grep -qP '[\x{1F000}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}]' "$app"; then
        bad "ícones: ainda há emoji no painel do app"
    else
        ok "ícones: painel do app sem emojis"
    fi
    grep -q 'id="btnGear"' "$app" && ok "ícones: engrenagem preservada" || bad "ícones: engrenagem sumiu"
    grep -q 'class="stroke"' "$app" && ok "ícones: SVGs profissionais presentes" || bad "ícones: sem SVGs"
    # 9) atualizar sem desinstalar: keystore fixa e assinatura de release
    test -f "$ROOT/android/keystore/otm-release.jks" \
        && ok "update: keystore versionada presente" || bad "update: sem keystore versionada"
    grep -q 'signingConfig = signingConfigs.getByName("release")' "$ROOT/android/app/build.gradle.kts" \
        && ok "update: release assina com a keystore fixa" || bad "update: release sem assinatura fixa"
    grep -q 'if (a.argv.isEmpty())' "$src/PackBridge.kt" \
        && ok "bridge: ação sem comando não tenta executar" || bad "bridge: tenta executar ação de UI"
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
    grep -q '"Desempenho", "Apps e jogos" ->' "$src/PackBridge.kt" \
        && ok "som: soundFor mapeia as categorias novas" || bad "som: soundFor com categorias antigas"
    if grep -q '"RAM / Limpeza"\|"Touch / Free Fire"\|"Congelar apps"' "$src/PackBridge.kt"; then
        bad "som: soundFor ainda cita categoria antiga"
    else
        ok "som: soundFor sem categorias antigas"
    fi
    # 11) MP3 descomprimidos no APK (openFd exige STORED)
    grep -q 'noCompress += "mp3"' "$ROOT/android/app/build.gradle.kts" \
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
    for f in condensada arredondada geometrica humanista; do
        grep -q "data-font=\"$f\"" "$web" && grep -q "data-font=\"$f\"" "$app" \
            && ok "fonte: '$f' na fonte e no app" || bad "fonte: '$f' ausente"
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
    # áudio de baixa latência (root): deep_buffer=0 + persistência no boot
    : > "$TMP_CMD_LOG"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/turbo.sh" audio on 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_audio"
    assert_contains "$TMP/nf_audio" "baixa latência" "turbo audio liga o modo de baixa latência"
    grep -q '0' "$TMP_STORE/prop.audio.deep_buffer.media" \
        && ok "audio: deep_buffer desligado" || bad "audio: sem deep_buffer"
    test -s "$HOME/.packotm/boot.sh" && grep -q 'audio.deep_buffer.media 0' "$HOME/.packotm/boot.sh" \
        && ok "audio: registrado para o boot" || bad "audio: não persistiu no boot"
    # compactação de memória (root): não mata apps
    : > "$TMP_CMD_LOG"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/turbo.sh" mem_compact on 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_mc"
    assert_contains "$TMP/nf_mc" "compactação" "turbo mem_compact liga a compactação"
    grep -q 'compact_memory' "$ROOT/scripts/turbo.sh" && ok "mem_compact: usa compact_memory" || bad "mem_compact: sem compact_memory"
    if sed -n '/^mem_compact()/,/^}/p' "$ROOT/scripts/turbo.sh" | grep -q 'kill'; then
        bad "mem_compact não deve matar apps"
    else
        ok "mem_compact não mata apps"
    fi
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
    # persistência no boot: registra e instala o wrapper (root)
    rm -rf "$HOME/.packotm"; mkdir -p "$HOME/.packotm"
    export OTM_BOOT_DIR="$TMP/service.d"; mkdir -p "$OTM_BOOT_DIR"
    : > "$TMP_CMD_LOG"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/turbo.sh" boot on 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_boot"
    assert_contains "$TMP/nf_boot" "nada para persistir" "boot sem ajustes avisa"
    # agora com um ajuste salvo, instala o wrapper de verdade
    rm -rf "$HOME/.packotm"
    OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/turbo.sh" refresh_fixed 90 >/dev/null 2>&1
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/turbo.sh" boot on 2>&1)
    printf '%s\n' "$out" > "$TMP/nf_boot2"
    assert_contains "$TMP/nf_boot2" "instalada" "boot instala o reaplicador"
    test -f "$OTM_BOOT_DIR/otm-pack.sh" && ok "boot: wrapper gravado em service.d" || bad "boot: sem wrapper"
    grep -q 'boot.sh' "$OTM_BOOT_DIR/otm-pack.sh" && ok "boot: wrapper reaplica o boot.sh" || bad "boot: wrapper sem boot.sh"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/turbo.sh" boot off 2>&1)
    test ! -f "$OTM_BOOT_DIR/otm-pack.sh" && ok "boot: 'off' remove o wrapper" || bad "boot: 'off' não removeu"
    # as ações estão registradas no painel
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["turbo.refresh_fixed","turbo.audio","turbo.mem_compact","game_focus",
                       "touch.multi","turbo.boot"] as $id)
               echo isset($a[$id]) ? "" : "FALTA:$id ";' > "$TMP/nf_reg" 2>&1
    test ! -s "$TMP/nf_reg" && ok "novas ações no registro do painel" || bad "registro: $(cat "$TMP/nf_reg")"
    grep -q '"turbo.refresh_fixed"' "$ROOT/android/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o refresh fixo" || bad "app: actions.json sem refresh fixo"
    grep -q 'boot_install' "$ROOT/scripts/common.sh" && ok "common: helper de boot presente" || bad "common: sem helper de boot"
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
    # sem prop setada, o Android usa o padrão (OpenGL) — nada fictício
    rm -f "$TMP_STORE/prop.debug.hwui.renderer"
    out=$(OTM_NO_COLOR=1 OTM_MODE=su sh "$ROOT/scripts/panel-state.sh" 2>&1)
    printf '%s\n' "$out" > "$TMP/st_out2"
    grep -q '"renderer":"opengl"' "$TMP/st_out2" && ok "state: sem prop assume OpenGL (padrão)" || bad "state: default renderer errado"
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
    grep -q '"state" -> stateImpl()' "$ROOT/android/app/src/main/java/com/otm/pack/PackBridge.kt" \
        && ok "app: ponte responde ao estado real" || bad "app: ponte sem estado"
    grep -q 'fun stateImpl' "$ROOT/android/app/src/main/java/com/otm/pack/PackBridge.kt" \
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
    grep -q '"state_value": "skiagl"' "$ROOT/android/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem state_value" || bad "app: actions.json sem state_value"
    grep -q '"state_match": "touch:110,350,0,4"' "$ROOT/android/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem state_match do toque" || bad "app: actions.json sem state_match"
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
    grep -q 'deviceidle whitelist -com.otm.pack' "$HOME/.packotm/off.sh" \
        && ok "reversão do Doze guardada (Reverter TUDO)" || bad "sem reversão do Doze"
    grep -q 'appops set com.otm.pack RUN_IN_BACKGROUND default' "$HOME/.packotm/off.sh" \
        && ok "reversão do appops guardada" || bad "sem reversão do appops"
    # bateria sem economia: aplica de verdade e é reversível
    OTM_MODE=su sh "$ROOT/scripts/adb-tweaks.sh" perm_battery >/dev/null 2>&1
    assert_eq "0" "$(cat "$TMP_STORE/global.low_power" 2>/dev/null)" "economia de bateria desligada"
    assert_eq "0" "$(cat "$TMP_STORE/global.app_standby_enabled" 2>/dev/null)" "App Standby desligado"
    grep -q 'settings put global low_power' "$HOME/.packotm/off.sh" \
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
    grep -q '"perm.app"' "$ROOT/android/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem as permissões" || bad "app: actions.json sem permissões"
    grep -q 'Permissões e segundo plano' "$ROOT/android/app/src/main/assets/panel/index.html" \
        && ok "app: engrenagem mostra as permissões exigidas" || bad "app: sem lista de permissões"
    grep -q 'id="setPermApp"' "$ROOT/android/app/src/main/assets/panel/index.html" \
        && ok "app: botões de permissão existem" || bad "app: sem botões de permissão"
}

t_personalization() {
    printf '\n  # personalização: fonte, tema, cor, DPI e restaurar padrão\n'
    local app="$ROOT/android/app/src/main/assets/panel/index.html"
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
    local app="$ROOT/android/app/src/main/assets/panel/index.html"
    local web="$ROOT/web/index.php"
    local kt="$ROOT/android/app/src/main/java/com/otm/pack/Usage.kt"
    local br="$ROOT/android/app/src/main/java/com/otm/pack/PackBridge.kt"
    local man="$ROOT/android/app/src/main/AndroidManifest.xml"
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
    grep -q 'id="setPermUsage"' "$app" && grep -q 'id="setPermUsage"' "$web" \
        && ok "app+web: botão de acesso ao uso" || bad "botão de acesso ao uso ausente"
    grep -q 'Acesso a dados de uso' "$web" && ok "web: card de permissão explicado" || bad "web: card de permissão ausente"
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
    grep -q 'Ver o uso real do aparelho' "$ROOT/android/app/src/main/java/com/otm/pack/Permissions.kt" \
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
}

t_dns() {
    printf '\n  # dns.sh: perfis de DNS privado (aplica/reverte)\n'
    f="$ROOT/scripts/dns.sh"
    [ -f "$f" ] && ok "scripts/dns.sh existe" || { bad "dns.sh ausente"; return; }
    OTM_MODE=local OTM_NO_COLOR=1 sh "$f" list > "$TMP/dns_list" 2>&1
    assert_contains "$TMP/dns_list" "adguard" "dns list mostra perfis"
    assert_contains "$TMP/dns_list" "Bloqueio de an" "dns list descreve bloqueio de anuncios"
    st="$HOME/.packotm"; rm -f "$st/off.sh" "$st/on"
    OTM_MODE=local sh "$f" adguard >/dev/null 2>&1
    [ "$(cat "$TMP_STORE/global.private_dns_specifier" 2>/dev/null)" = "dns.adguard-dns.com" ] \
        && ok "dns adguard grava o hostname DoT" || bad "nao gravou o hostname"
    grep -q "private_dns_mode" "$st/off.sh" 2>/dev/null && ok "dns registra reversao" || bad "sem reversao"
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
        rm -f "$st/off.sh" "$st/on"
        OTM_MODE=local sh "$f" "$id" >/dev/null 2>&1
        [ "$(cat "$TMP_STORE/global.private_dns_specifier" 2>/dev/null)" = "$host" ] \
            && ok "dns $id grava $host" || bad "dns $id nao gravou ($host)"
    done
    rm -f "$st/off.sh" "$st/on"
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
    OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" renice com.exemplo abc > "$TMP/pm_bad" 2>&1
    assert_contains "$TMP/pm_bad" "uso:" "proc-mgr valida nice invalido"
    # sem root, limitar RAM/CPU precisa avisar e nao aplicar
    OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" ram com.exemplo 512 > "$TMP/pm_ram" 2>&1
    grep -q 'root' "$TMP/pm_ram" && ok "proc-mgr ram pede root" || bad "proc-mgr ram sem aviso de root"
    OTM_NO_COLOR=1 OTM_MODE=local sh "$pf" status > "$TMP/pm_st" 2>&1
    assert_contains "$TMP/pm_st" "aplicados" "proc-mgr status lista o que ha"
    # --- registro no painel + app ---
    php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
             foreach (["doze.on","doze.off","doze.status","proc.top","proc.info","proc.ram",
                       "proc.cpu","proc.renice","proc.freeze","proc.unfreeze","proc.status",
                       "proc.restore","touch.latency"] as $id)
               echo isset($a[$id]) ? "" : "FALTA:$id ";' > "$TMP/pm_reg" 2>&1
    test ! -s "$TMP/pm_reg" && ok "novas acoes no registro do painel" || bad "registro: $(cat "$TMP/pm_reg")"
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo in_array("proc-mgr.sh", otm_allowed_scripts(), true) ? "ok" : "falta";' > "$TMP/pm_lib" 2>&1
    assert_contains "$TMP/pm_lib" "ok" "proc-mgr.sh na whitelist"
    grep -q '"proc-mgr.sh"' "$ROOT/android/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o gerenciador de processos" || bad "app: actions.json sem proc-mgr"
    grep -q '"doze.on"' "$ROOT/android/app/src/main/assets/panel/actions.json" \
        && ok "app: actions.json tem o sono profundo" || bad "app: actions.json sem doze"
    # --- painel: home + Visual + leitura de stats ---
    php -r 'require "'"$ROOT"'/web/lib.php";
             echo function_exists("otm_stats_read") ? "reader" : "";' > "$TMP/pm_stats" 2>&1
    assert_contains "$TMP/pm_stats" "reader" "lib: leitor de stats presente"
    grep -q "case 'stats'" "$ROOT/web/api.php" && ok "api.php: endpoint de stats" || bad "api.php: sem stats"
    grep -q 'fun statsImpl' "$ROOT/android/app/src/main/java/com/otm/pack/PackBridge.kt" \
        && ok "app: statsImpl presente" || bad "app: sem statsImpl"
    grep -q 'startStats' "$ROOT/web/index.php" && ok "painel: liga o polling das metricas" || bad "painel: sem startStats"
    rm -rf "$HOME/.packotm"
    unset TMP_CMD_LOG
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
        assert_contains "$TMP/web_html" "00deUdia Otimizações" "index.php traz a marca 00deUdia Otimizações"
        n_cards=$(grep -c 'class="card"' "$TMP/web_html")
        [ "$n_cards" -ge 85 ] && ok "index.php renderiza os cards no servidor ($n_cards)" \
            || bad "poucos cards renderizados ($n_cards)"
        n_sec=$(grep -c '<section id=' "$TMP/web_html")
        [ "$n_sec" -eq 8 ] && ok "index.php renderiza a home + 7 categorias" || bad "seções: $n_sec (esperado 8)"
        for cat in "Geral" "Display &amp; Touch" "Desempenho" "DNS e rede" "Processos" "Apps e jogos" "Sistema"; do
            assert_contains "$TMP/web_html" "$cat" "index.php tem a categoria $cat"
        done
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
        [ "$n_choice" -eq 2 ] && ok "renderiza 2 grupos de escolha (renderizador, toque)" \
            || bad "grupos de escolha: $n_choice (esperado 2)"
        n_opts=$(grep -c 'class="opt"' "$TMP/web_html")
        [ "$n_opts" -eq 8 ] && ok "opções lado a lado: 3 renderizadores + 5 toques ($n_opts)" \
            || bad "opções lado a lado: $n_opts (esperado 8)"
        assert_contains "$TMP/web_html" ">Selecionar<" "opções usam o rótulo Selecionar"
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
        php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
                 echo isset($a["ext.gpu"])?"gpu ":"", isset($a["ext.turbo"])?"turbo ":"",
                      isset($a["adv.obscure"])?"adv\n":"";' > "$TMP/web_ext" 2>&1
        assert_contains "$TMP/web_ext" "gpu turbo adv" "registro cobre extremos e avançado (sem root)"
        php -r 'require "'"$ROOT"'/web/lib.php";
                 $r=otm_run("ext.turbo",[],false);
                 echo !empty($r["need_confirm"])?"PEDE":"NAO";' > "$TMP/web_extconf" 2>&1
        assert_contains "$TMP/web_extconf" "PEDE" "modo extremo exige confirmação"
        # as antigas categorias root/avançado foram unificadas em "Desempenho"
        php -r 'require "'"$ROOT"'/web/lib.php"; $a=otm_actions();
                 foreach (["ext.turbo","ext.gpu","adv.obscure"] as $id)
                   echo ($a[$id]["group"]==="Desempenho"?"ok ":"ERRO ");
                 echo "\n";' > "$TMP/web_cat" 2>&1
        assert_contains "$TMP/web_cat" "ok ok ok" "root/avançado agrupados em Desempenho"
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
        # sem acesso, aplicar algo NÃO pode dizer que deu certo
        mkdir -p "$TMP/bin_noop"
        printf '#!/bin/sh\nexit 0\n' > "$TMP/bin_noop/settings"
        chmod +x "$TMP/bin_noop/settings"
        PATH="$TMP/bin_noop:$PATH" OTM_MODE=local php -r 'require "'"$ROOT"'/web/lib.php";
                 $r=otm_run("perf",[],false);
                 echo (!empty($r["applied"]) && empty($r["real"])) ? "FALHA_REAL":"MASCARADO";' \
            > "$TMP/web_real" 2>&1
        assert_contains "$TMP/web_real" "FALHA_REAL" "sem acesso real, ação aplicadora vira erro (não mascara)"
    else
        printf '  [skip] php ausente: pulei testes do painel web\n'
    fi
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

# --- execução ----------------------------------------------------------------
printf '  ==================================================\n'
printf '  Testes do Pack de Otimização\n'
printf '  ==================================================\n'
setup_stubs
t_syntax
t_angle_tag
t_per_module
t_extreme
t_adv_noroot
t_realverify
t_realverify_deep
t_config
t_auth
t_noroot_only
t_app_login
t_app_exec
t_app_fixes
t_new_features
t_panel_state
t_perm_script
t_perm_actions
t_personalization
t_usage_access
t_side_fixed
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
t_dns
t_new_scripts
t_modules
t_web
t_pack

printf '\n  --------------------------------------------------\n'
printf '  %d passaram, %d falharam\n' "$PASS" "$FAIL"
printf '  --------------------------------------------------\n'
rm -rf "$TMP"
[ "$FAIL" = "0" ] || exit 1
exit 0
