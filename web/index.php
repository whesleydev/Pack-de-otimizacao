<?php
declare(strict_types=1);
/**
 * Trix — painel de controle (PHP).
 *
 * A estrutura (menu de categorias e cards de ação) é renderizada aqui no servidor
 * a partir do registro em lib.php. O JavaScript só cuida de trocar de categoria,
 * executar via api.php, mostrar saída e a explicação de cada ação.
 */
require __DIR__ . '/lib.php';
require_once __DIR__ . '/auth.php';

// --- login obrigatório --------------------------------------------------------
$erro_login = '';
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && isset($_POST['user'], $_POST['pass'])) {
    if (!otm_csrf_ok($_POST['csrf'] ?? null)) {
        $erro_login = 'Sessão expirada. Tente de novo.';
    } elseif (otm_auth_login((string)$_POST['user'], (string)$_POST['pass'])) {
        header('Location: index.php');
        exit;
    } else {
        $erro_login = 'Usuário ou senha incorretos.';
    }
}
if (isset($_GET['sair'])) {
    otm_auth_logout();
    header('Location: index.php');
    exit;
}
if (!otm_auth_logged_in()) {
    if ($erro_login !== '') $_GET['erro'] = $erro_login;
    require __DIR__ . '/login.php';
    exit;
}

$actions = array_values(otm_actions());

// Ordem fixa das categorias. Menu enxuto: 7 grupos (Rede/DNS separados) + a Home.
$GROUP_ORDER = ['Geral', 'Flutuante', 'Display & Touch', 'Desempenho', 'Dispositivos', 'DNS e rede', 'Latência e ping', 'Processos', 'Debloat', 'Apps e jogos', 'Sistema'];
$GROUP_ALIAS = ['Rede e conexão' => 'DNS e rede'];
$byGroup = [];
foreach ($actions as $a) {
    $g = $GROUP_ALIAS[$a['group']] ?? $a['group'];
    $a['_group'] = $g;
    $byGroup[$g][] = $a;
}
$groups = [];
foreach ($GROUP_ORDER as $g) { if (!empty($byGroup[$g])) $groups[$g] = $byGroup[$g]; }
foreach ($byGroup as $g => $items) { if (!isset($groups[$g])) $groups[$g] = $items; }  // fallback

$meta = [
    'Geral'           => ['t' => 'Geral',            's' => 'Aplique o conjunto seguro, reverta tudo, salve snapshot e rode módulos.'],
    'Flutuante'       => ['t' => 'Flutuante',        's' => 'Ative o painel flutuante (overlay) para usar a sensi e os perfis por cima do jogo.'],
    'Display & Touch' => ['t' => 'Display & Touch',  's' => 'Renderizador, motor gráfico e sensibilidade de toque (Free Fire).'],
    'Desempenho'      => ['t' => 'Desempenho',       's' => 'RAM, limpeza, turbo, tela/bateria, sono profundo, congelar apps e ajustes profundos (root).'],
    'DNS e rede'      => ['t' => 'DNS e rede',       's' => 'Escolha o DNS privado (30+ perfis), meça a latência e ajuste Wi-Fi e buffers TCP.'],
    'Processos'       => ['t' => 'Processos',        's' => 'Veja o que gasta RAM/CPU de verdade e limite, priorize ou congele um app.'],
    'Debloat'         => ['t' => 'Debloat',          's' => 'Remova bloatware com lista curada: universal (qualquer marca) ou por fabricante. Sempre reversível.'],
    'Apps e jogos'    => ['t' => 'Apps e jogos',     's' => 'Tuning por app/jogo e Game Mode. O debloat agora tem aba própria.'],
    'Latência e ping' => ['t' => 'Latência e ping','s' => 'Congestion control, buffers TCP, low latency e ECN: o que muda o ping de verdade.'],
    'Sistema'         => ['t' => 'Sistema',          's' => 'Como o pack conversa com o Android, permissões, aparência e diagnóstico.'],
];

$riskLabel = ['safe' => 'seguro', 'careful' => 'cuidado', 'root' => 'root'];

// --- Perfil personalizado: opções do menu (o painel monta e envia ligadas) ----
// A ordem das chaves é a mesma do argv de profile.custom.apply em lib.php.
$CPROF = otm_custom_profile_opts();
$CPROF_DEFAULT = [];
foreach ($CPROF as $c) {
    // o padrão é o valor do estado "desligado" no toggle; nos demais, a 1ª opção
    $CPROF_DEFAULT[$c['k']] = ($c['kind'] ?? 'seg') === 'toggle'
        ? $c['tgl']['off'] : $c['opts'][0][0];
}

// --- Terminal (aba própria): executa comandos crus via api.php do=term ---------
// O Terminal é renderizado no servidor como uma seção a mais do menu. Ele não é
// um "card de ação" (o comando é livre), por isso fica fora do registro.
$TERMINAL_HTML = <<<'HTML'
    <section id="g-Terminal" data-g="Terminal" hidden>
      <div class="head">
        <h2>Terminal</h2>
        <p>Rode comandos no aparelho pelo mesmo acesso do pack (Shizuku, ADB por Wi-Fi ou root).</p>
      </div>
      <div class="note">
        <span aria-hidden="true">ⓘ</span>
        <div><b>Cuidado:</b> aqui o comando vai direto para o shell do Android. Use com calma — um comando errado pode desconfigurar o aparelho. O histórico fica salvo e aparece em <b>Logs</b>.</div>
      </div>
      <article class="card" style="gap:0">
        <div class="row"><h3>Executar comando</h3></div>
        <p class="sub">Exemplos: <code>getprop ro.product.model</code> · <code>settings get system peak_refresh_rate</code> · <code>pm list packages -3</code></p>
        <div class="termwrap">
          <pre class="termout" id="termOut" aria-live="polite"></pre>
          <div class="termrow">
            <span class="pfx">$</span>
            <input id="termInput" type="text" autocomplete="off" autocapitalize="off" spellcheck="false"
                   placeholder="digite um comando e toque em Executar" aria-label="Comando">
            <button class="btn primary" id="termRun" type="button" style="width:auto">Executar</button>
          </div>
          <p class="termhint">Histórico: use as setas ↑/↓ no campo. <button class="jump" id="termClear" type="button" style="border-radius:999px;padding:4px 10px">limpar tela</button></p>
        </div>
      </article>
    </section>
HTML;

// --- seletor de apps (nome + ícone): substitui o input de pacote ------------
// O usuário NÃO digita o pacote: o botão abre a lista de apps instalados (com
// nome e ícone). O pacote escolhido vai num input escondido, que o `collect()`
// lê como qualquer outro parâmetro.
function otm_pkg_picker(string $pid, string $name, string $default = ''): string {
    $pidh = htmlspecialchars($pid, ENT_QUOTES);
    $nameh = htmlspecialchars($name, ENT_QUOTES);
    $defh = htmlspecialchars($default, ENT_QUOTES);
    $cur = $default !== '' ? $defh : 'Nenhum app escolhido';
    ob_start(); ?>
      <div class="apppick" role="button" tabindex="0" data-apppick
           aria-label="Escolher app (<?= $nameh ?>)">
        <input type="hidden" id="<?= $pidh ?>" data-p="<?= $nameh ?>" value="<?= $defh ?>">
        <span class="appslot"><span class="noico">?</span><span class="nm"><b><?= $cur ?></b><small>toque para escolher</small></span></span>
        <span class="chev"><svg class="stroke" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 6 6 6-6 6"/></svg></span>
      </div>
    <?php return (string) ob_get_clean();
}

// --- grupos de escolha: opções lado a lado num único cartão -------------------
$CHOICE = otm_choices();
$choiceMembers = [];               // choiceKey => [ações]
foreach ($actions as $a) { if (!empty($a['choice'])) $choiceMembers[$a['choice']][] = $a; }
// dados que o JS usa para marcar a opção em uso (lida do aparelho)
$choiceMeta = [];
foreach ($CHOICE as $k => $c) {
    $opts = [];
    foreach ($choiceMembers[$k] ?? [] as $a) {
        $opts[] = [
            'id' => $a['id'], 'label' => $a['option'] ?? $a['label'],
            'desc' => $a['desc'] ?? '', 'risk' => $a['risk'] ?? 'safe',
            'state_value' => $a['state_value'] ?? null, 'state_match' => $a['state_match'] ?? null,
            'state_backend_value' => $a['state_backend_value'] ?? null,
            'state_auto' => !empty($a['state_auto']),
        ];
    }
    // parâmetros extras do grupo (ex.: escolher o app no motor por app)
    $params = $choiceMembers[$k][0]['params'] ?? [];
    $choiceMeta[$k] = ['title' => $c['title'], 'desc' => $c['desc'], 'risk' => $c['risk'] ?? 'safe',
                       'state' => $c['state'] ?? null, 'state_backend' => $c['state_backend'] ?? null,
                       'app' => !empty($c['app']), 'params' => $params, 'opts' => $opts];
}

$token = is_file(__DIR__ . '/.token') ? trim((string) file_get_contents(__DIR__ . '/.token')) : '';
$first = array_key_first($groups);
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="dark">
<title>Trix</title>
<style>
/* Fontes empacotadas (funcionam sem internet e sem CDN). */
@font-face{font-family:'Press Start 2P';src:url('assets/fonts/pressstart2p.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Monocraft';src:url('assets/fonts/monocraft.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Anton';src:url('assets/fonts/anton.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Bebas Neue';src:url('assets/fonts/bebasneue.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Orbitron';src:url('assets/fonts/orbitron.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Russo One';src:url('assets/fonts/russoone.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Playfair Display';src:url('assets/fonts/playfairdisplay.ttf') format('truetype');font-display:swap}
@font-face{font-family:'JetBrains Mono';src:url('assets/fonts/jetbrainsmono.ttf') format('truetype');font-display:swap}
@font-face{font-family:'Caveat';src:url('assets/fonts/caveat.ttf') format('truetype');font-display:swap}
/* ---- identidade: tinta neutra + prata, com efeito de vidro ------------------
   O app é SÓ modo escuro: não existe tema claro nem alternância. As cores
   escuras ficam direto no :root, sem depender do sistema operacional. */
:root{
  --paper:#0d0c0a; --ink:#f3efe7; --muted:#a49d90;
  --line:rgba(255,255,255,.12); --line-strong:rgba(255,255,255,.2);
  --accent:#c7ccd6; --accent-ink:#14161a; --teal:#31c0a5; --warn:#e0a53a; --danger:#ff6b5e;
  --glass:rgba(30,28,24,.5); --glass-2:rgba(30,28,24,.34);
  --glass-card:rgba(26,24,21,.82); --glass-bar:rgba(26,24,21,.76);
  --blur:saturate(165%) blur(22px);
  --ring:rgba(199,204,214,.40);
  --shadow:0 1px 2px rgba(0,0,0,.45),0 16px 40px -20px rgba(0,0,0,.8);
  --r:16px; --r-sm:11px;
  --font:"Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif;
  --mono:ui-monospace,"SFMono-Regular",Menlo,Consolas,monospace;
  --top:58px;
}

*{box-sizing:border-box}
[hidden]{display:none!important}
html{scroll-behavior:smooth;overflow-x:clip}
html,body{margin:0}
body{
  font-family:var(--font); color:var(--ink); line-height:1.55; min-height:100dvh;
  -webkit-text-size-adjust:100%; overflow-x:clip;
  background:var(--paper);
  /* Coluna flexível: sem isto o rodapé sobe para o meio da tela quando a
     categoria aberta tem pouco conteúdo (a aba Flutuante, por exemplo). */
  display:flex; flex-direction:column;
}
/* papel de parede: fundo preenche a tela e a imagem aparece inteira (sem corte) */
html::before{content:"";position:fixed;inset:0;z-index:-3;
  background:url('assets/wallpaper.jpeg') center/cover no-repeat}
body::after{content:"";position:fixed;inset:0;z-index:-2;
  background:url('assets/wallpaper.jpeg') center/contain no-repeat}
/* véu para dar contraste ao conteúdo sobre o wallpaper */
body::before{content:"";position:fixed;inset:0;z-index:-1;background:var(--paper);opacity:.62}
a{color:var(--accent)}
button{font:inherit;color:inherit}

/* ---- topo (vidro) --------------------------------------------------------- */
.top{
  position:sticky; top:0; z-index:40; min-height:var(--top);
  display:flex; align-items:center; flex-wrap:wrap; gap:8px; row-gap:8px;
  padding:8px clamp(10px,3vw,20px);
  background:var(--glass-bar); backdrop-filter:var(--blur); -webkit-backdrop-filter:var(--blur);
  border-bottom:1px solid var(--line);
}
.mark{width:36px;height:36px;flex:none;border-radius:11px;background:var(--accent);color:var(--accent-ink);
  display:grid;place-items:center;font-weight:800;font-size:14px;letter-spacing:-.05em}
.name{font-weight:800;letter-spacing:-.02em;font-size:15px;line-height:1.05;white-space:nowrap;min-width:0;overflow:hidden;text-overflow:ellipsis}
.name small{display:block;font-weight:500;font-size:11px;color:var(--muted);letter-spacing:0}
.grow{flex:1}
.iconbtn{
  border:1px solid var(--line);background:var(--glass-2);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border-radius:10px;padding:8px 11px;cursor:pointer;font-size:13px;font-weight:600;flex:none;
  display:inline-flex;align-items:center;gap:6px;transition:.15s;white-space:nowrap;text-decoration:none
}
.iconbtn svg{width:17px;height:17px;display:block}
.iconbtn svg.stroke{fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.iconbtn svg.stroke path{fill:none;stroke:currentColor}
.iconbtn:hover{border-color:var(--line-strong)}
.iconbtn:focus-visible{outline:2px solid var(--ring);outline-offset:1px}
.burger{display:none}

/* ---- faixa/banner --------------------------------------------------------- */
.banner{position:relative;overflow:hidden;border-bottom:1px solid var(--line);
  background:url('assets/banner.jpeg') center/cover no-repeat #241f19;color:#fff}
.banner::after{content:"";position:absolute;inset:0;
  background:linear-gradient(90deg,rgba(18,14,10,.9),rgba(18,14,10,.5) 60%,rgba(18,14,10,.78))}
.banner .in{position:relative;z-index:1;max-width:1180px;margin:0 auto;
  padding:clamp(18px,5vw,38px) clamp(12px,3vw,22px)}
.banner h1{margin:0;font-size:clamp(20px,4.6vw,33px);font-weight:800;letter-spacing:-.03em}
.banner p{margin:6px 0 0;color:#e9e2d7;font-size:clamp(12.5px,2.6vw,15px);max-width:62ch}
.banner .tag{display:inline-flex;align-items:center;gap:7px;margin-top:13px;padding:5px 11px;border-radius:999px;
  background:rgba(255,255,255,.15);border:1px solid rgba(255,255,255,.28);font-size:12px;font-weight:600}
.dot{width:7px;height:7px;border-radius:50%;background:var(--teal)}

/* ---- animações ------------------------------------------------------------- */
@keyframes otmRise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
@keyframes otmFade{from{opacity:0}to{opacity:1}}
@keyframes otmPop{from{opacity:0;transform:scale(.94)}to{opacity:1;transform:none}}
@keyframes otmSheen{0%{background-position:-160% 0}60%,100%{background-position:260% 0}}
@keyframes otmPulse{0%,100%{box-shadow:0 0 0 0 var(--ring)}50%{box-shadow:0 0 0 6px transparent}}
@keyframes otmSpin{to{transform:rotate(360deg)}}
/* ---- Ação principal: limpeza inteligente (Clean Phone) ---------------------- */
.hero{position:relative;overflow:hidden;border:1px solid var(--line);border-radius:var(--r);
  background:var(--glass-card);padding:20px;margin:0 0 4px}
.hero-glow{position:absolute;inset:-40% -20% auto -20%;height:180px;pointer-events:none;
  background:radial-gradient(60% 100% at 50% 0%,var(--ring),transparent 70%);opacity:.5}
.hero-body{position:relative;display:flex;flex-direction:column;gap:14px}
.hero-head{display:flex;align-items:center;gap:14px}
.hero-ico{flex:0 0 auto;width:48px;height:48px;border-radius:14px;display:grid;place-items:center;
  color:var(--accent-ink);background:linear-gradient(145deg,var(--accent),color-mix(in srgb,var(--accent) 72%,#000));
  box-shadow:0 6px 18px var(--ring)}
.hero-ico svg{width:26px;height:26px}
.hero-txt{min-width:0}
.hero-kicker{display:block;font-size:10.5px;font-weight:800;letter-spacing:.09em;text-transform:uppercase;color:var(--muted)}
.hero-title{margin:2px 0 2px;font-size:22px;font-weight:800;letter-spacing:-.01em}
.hero-sub{margin:0;font-size:13px;color:var(--muted)}
.hero-meta{display:flex;flex-wrap:wrap;gap:8px}
.hero-chip{font-size:12px;font-weight:700;color:var(--muted);border:1px solid var(--line);
  background:var(--glass-2);border-radius:999px;padding:5px 11px}
.hero-btn{position:relative;width:100%;border:0;cursor:pointer;border-radius:14px;padding:15px 18px;
  display:flex;align-items:center;justify-content:center;gap:10px;font-size:15px;font-weight:800;
  color:var(--accent-ink);background:linear-gradient(135deg,var(--accent),color-mix(in srgb,var(--accent) 78%,#000));
  box-shadow:0 8px 24px var(--ring);transition:transform .16s ease,box-shadow .16s ease,filter .16s ease}
.hero-btn:hover{filter:brightness(1.05)}
.hero-btn:active{transform:translateY(1px) scale(.995)}
.hero-btn:focus-visible{outline:2px solid var(--accent);outline-offset:3px}
.hero-btn[disabled]{opacity:.75;cursor:progress}
.hb-ico{width:19px;height:19px;flex:0 0 auto}
.hb-load{display:none;width:16px;height:16px;border-radius:50%;flex:0 0 auto;
  border:2px solid color-mix(in srgb,var(--accent-ink) 35%,transparent);border-top-color:var(--accent-ink);
  animation:otmSpin .8s linear infinite}
.hero-btn.busy .hb-load{display:block}
.hero-note{margin:0;font-size:11.5px;color:var(--muted);text-align:center}
@media (prefers-reduced-motion: reduce){
  .hero-btn{transition:none}
  .hb-load{animation:none}
}
.mt-16{margin-top:16px}
@media (prefers-reduced-motion: reduce){
  *{animation-duration:.001ms!important;animation-iteration-count:1!important;transition-duration:.001ms!important}
  html{scroll-behavior:auto}
}

/* ---- layout --------------------------------------------------------------- */
.layout{max-width:1180px;margin:0 auto;display:grid;grid-template-columns:250px minmax(0,1fr);
  gap:clamp(14px,3vw,28px);padding:clamp(14px,3vw,26px) clamp(12px,3vw,22px);
  width:100%; flex:1 0 auto}
.side{align-self:start;position:static}
.side .panel{
  position:fixed; top:calc(var(--top) + 12px); z-index:30;
  left:calc(max((100vw - 1180px) / 2, 0px) + clamp(12px,3vw,22px)); width:250px;
  background:var(--glass); backdrop-filter:var(--blur); -webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line); border-radius:var(--r); box-shadow:var(--shadow);
  padding:12px; max-height:calc(100dvh - var(--top) - 24px); overflow:auto
}
.side h2{font-size:11px;text-transform:uppercase;letter-spacing:.12em;color:var(--muted);margin:2px 0 10px 8px}
.nav{display:flex;flex-direction:column;gap:6px}
.nav a{display:flex;align-items:center;gap:11px;padding:11px 12px;border-radius:13px;
  color:var(--ink);text-decoration:none;font-size:14px;font-weight:600;border:1px solid var(--line);
  position:relative;background:var(--glass-2);transition:background .15s ease, border-color .15s ease, transform .12s ease}
.nav a .c{width:9px;height:9px;border-radius:50%;background:var(--line-strong);flex:none;transition:background .2s, box-shadow .2s}
.nav a:hover{background:var(--glass);transform:translateX(2px);border-color:var(--line-strong)}
.nav a:active{transform:translateX(0) scale(.99)}
.nav a[aria-current="true"]{background:var(--glass);border-color:color-mix(in srgb,var(--accent) 45%,var(--line-strong))}
.nav a[aria-current="true"]::before{content:"";position:absolute;left:-1px;top:8px;bottom:8px;width:3px;
  border-radius:3px;background:var(--accent);animation:otmPop .25s both}
.nav a[aria-current="true"] .c{background:var(--accent);box-shadow:0 0 0 4px color-mix(in srgb,var(--accent) 22%,transparent)}
.nav .count{margin-left:auto;font-size:11px;color:var(--muted);font-weight:700;
  background:var(--glass-2);border:1px solid var(--line);border-radius:999px;padding:1px 8px;min-width:22px;text-align:center}

/* ---- conteúdo ------------------------------------------------------------- */
.head h2{margin:0;font-size:clamp(18px,3.6vw,23px);font-weight:800;letter-spacing:-.02em}
.head p{margin:4px 0 0;color:var(--muted);font-size:14px}
.note{display:flex;gap:10px;align-items:flex-start;margin:16px 0;padding:12px 14px;border-radius:var(--r-sm);
  background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line);color:var(--muted);font-size:13px}
.note b{color:var(--ink)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,290px),1fr));gap:13px}
section[hidden]{display:none}

.card{
  background:var(--glass-card);
  border:1px solid var(--line); border-radius:var(--r); padding:15px;
  display:flex; flex-direction:column; gap:9px; box-shadow:var(--shadow);
  animation:otmRise .42s cubic-bezier(.2,.7,.3,1) both;
  animation-delay:calc(var(--i,0)*45ms);
  transition:transform .18s ease, box-shadow .18s ease, border-color .18s ease
}
@media (hover:hover){
  .card:hover{transform:translateY(-3px);border-color:var(--line-strong);
    box-shadow:0 2px 4px rgba(25,22,18,.08),0 22px 46px -22px rgba(25,22,18,.45)}
}
.card:active{transform:translateY(-1px) scale(.995)}
section[data-g] .head{animation:otmFade .3s both}
.card .row{display:flex;align-items:flex-start;gap:8px}
.card h3{margin:0;font-size:14.5px;font-weight:700;flex:1;letter-spacing:-.01em}
.card p{margin:0;color:var(--muted);font-size:12.8px}
.chip{font-size:10.5px;font-weight:800;text-transform:uppercase;letter-spacing:.06em;padding:3px 8px;
  border-radius:999px;border:1px solid var(--line-strong);color:var(--muted);white-space:nowrap}
.chip.careful{color:var(--warn);border-color:color-mix(in srgb,var(--warn) 45%,var(--line))}
.chip.root{color:var(--danger);border-color:color-mix(in srgb,var(--danger) 45%,var(--line))}
.help-btn{flex:none;width:26px;height:26px;border-radius:50%;border:1px solid var(--line-strong);
  background:var(--glass-2);cursor:pointer;font-weight:800;font-size:13px;line-height:1;display:grid;place-items:center}
.help-btn:hover{border-color:var(--accent);color:var(--accent)}
.fields{display:grid;grid-template-columns:1fr 1fr;gap:9px}
.field{display:flex;flex-direction:column;gap:5px}
.field.wide{grid-column:1/-1}
.field label{font-size:11px;font-weight:700;color:var(--muted);letter-spacing:.02em}
.field input{width:100%;padding:9px 11px;border-radius:var(--r-sm);border:1px solid var(--line-strong);
  background:var(--glass-2);color:var(--ink);font-size:14px;backdrop-filter:var(--blur)}
.field input:focus-visible{outline:2px solid var(--ring);outline-offset:1px;border-color:var(--accent)}
.go{margin-top:auto;display:flex;gap:8px}
.btn{border:1px solid var(--line-strong);background:var(--glass-2);border-radius:var(--r-sm);
  padding:10px 15px;font-size:13.5px;font-weight:700;cursor:pointer;position:relative;overflow:hidden;
  transition:transform .12s ease,border-color .15s ease,filter .15s ease,box-shadow .15s ease}
.btn:hover{border-color:var(--accent)}
.btn:active{transform:scale(.97)}
.btn.primary{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}
.btn.primary:hover{filter:brightness(1.06)}
.btn.danger{background:var(--danger);border-color:var(--danger);color:#fff}
.btn:disabled{opacity:.55;cursor:progress}
.btn.busy::before{content:"";display:inline-block;width:12px;height:12px;margin-right:7px;vertical-align:-2px;
  border:2px solid currentColor;border-right-color:transparent;border-radius:50%;animation:otmSpin .7s linear infinite}
.help-btn{transition:transform .15s ease,border-color .15s,color .15s}
.help-btn:active{transform:scale(.9)}

/* ---- cartão de escolha: opções lado a lado -------------------------------- */
.opts{display:flex;flex-wrap:wrap;gap:8px}
.opt{flex:1 1 88px;min-width:88px;display:flex;flex-direction:column;align-items:center;gap:3px;
  padding:12px 8px;border-radius:var(--r-sm);border:1px solid var(--line-strong);
  background:var(--glass-2);cursor:pointer;color:var(--ink);text-align:center;
  transition:transform .12s ease,border-color .15s ease,background .15s ease}
.opt:hover{border-color:var(--accent)}
.opt:active{transform:scale(.97)}
.opt .opt-t{font-size:13px;font-weight:700;line-height:1.2}
.opt .opt-s{font-size:10.5px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--muted)}
.opt[aria-pressed="true"]{border-color:var(--accent);background:color-mix(in srgb,var(--accent) 16%,var(--glass-2))}
.opt[aria-pressed="true"] .opt-t{color:var(--accent)}
.opt[aria-pressed="true"] .opt-s{color:var(--accent)}
/* ---- hub do otimizador inteligente (cards fundidos num só) ---------------- */
.hub-sub-t{font-size:10.5px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;
  color:var(--muted);margin:14px 0 7px}
.hub-grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(128px,1fr));gap:8px}
.hub-grid .hbtn{display:flex;flex-direction:column;align-items:center;gap:3px;
  padding:12px 8px;border-radius:var(--r-sm);border:1px solid var(--line-strong);
  background:var(--glass-2);cursor:pointer;color:var(--ink);text-align:center;
  transition:transform .12s ease,border-color .15s ease,background .15s ease}
.hub-grid .hbtn:hover{border-color:var(--accent)}
.hub-grid .hbtn:active{transform:scale(.97)}
.hub-grid .hbtn .opt-t{font-size:13px;font-weight:700;line-height:1.2}
.hub-grid .hbtn .opt-s{font-size:10.5px;font-weight:700;letter-spacing:.04em;text-transform:uppercase;color:var(--muted)}
.hub-grid .hbtn{flex:none;min-width:0}
.hub-grid .hbtn .opt-s{white-space:nowrap;overflow:hidden;text-overflow:ellipsis;max-width:100%}
.now{font-size:12px;color:var(--muted);border-top:1px dashed var(--line);padding-top:8px;margin-top:2px}
.now b{color:var(--ink)}

/* ---- vitalidade: cockpit de longevidade ---------------------------------- */
.vital-gauge{position:relative;height:10px;border-radius:999px;background:var(--glass-2);
  border:1px solid var(--line);overflow:hidden;margin:12px 0 6px}
.vital-gauge i{position:absolute;inset:0 auto 0 0;width:0;border-radius:999px;
  background:linear-gradient(90deg,var(--danger),var(--warn),var(--teal));transition:width .6s ease}
.vital-gauge u{position:absolute;top:-2px;bottom:-2px;width:2px;background:var(--ink);
  opacity:.5;border-radius:2px}
.vital-head{display:flex;align-items:baseline;gap:10px;flex-wrap:wrap}
.vital-score{font-family:var(--mono);font-size:30px;font-weight:700;line-height:1;
  color:var(--ink);letter-spacing:-.02em}
.vital-score span{font-size:15px;color:var(--muted);font-weight:600}
.vital-badge{font-size:10.5px;font-weight:800;letter-spacing:.06em;text-transform:uppercase;
  padding:3px 9px;border-radius:999px;border:1px solid var(--line-strong);color:var(--muted);
  background:var(--glass-2)}
.vital-badge.good{border-color:var(--teal);color:var(--teal);
  background:color-mix(in srgb,var(--teal) 14%,var(--glass-2))}
.vital-badge.warn{border-color:var(--warn);color:var(--warn);
  background:color-mix(in srgb,var(--warn) 14%,var(--glass-2))}
.vital-badge.bad{border-color:var(--danger);color:var(--danger);
  background:color-mix(in srgb,var(--danger) 14%,var(--glass-2))}
.vital-badge.off{opacity:.75}
.vital-stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(96px,1fr));gap:10px;margin-top:12px}
.vital-stats div{background:var(--glass-2);border:1px solid var(--line);border-radius:var(--r-sm);
  padding:9px 10px}
.vital-stats b{display:block;font-family:var(--mono);font-size:16px;font-weight:700;color:var(--ink)}
.vital-stats s{display:block;font-size:10px;font-weight:700;letter-spacing:.04em;
  text-transform:uppercase;color:var(--muted);text-decoration:none;margin-top:2px}
.vital-actions{display:flex;gap:8px;flex-wrap:wrap;margin-top:12px}
.vital-actions .btn{flex:1 1 130px;justify-content:center}
@media (prefers-reduced-motion:reduce){.vital-gauge i{transition:none}}

/* ---- sliders (ajuste fino) ------------------------------------------------ */
.slider{display:flex;align-items:center;gap:10px}
.slider input[type=range]{flex:1;min-width:0;accent-color:var(--accent);height:26px}
.slider .num{width:66px;flex:none;padding:7px 8px;border-radius:var(--r-sm);border:1px solid var(--line-strong);
  background:var(--glass-2);color:var(--ink);font-size:14px;font-weight:700;text-align:center}
.slider .num:focus-visible{outline:2px solid var(--ring);outline-offset:1px;border-color:var(--accent)}
.field-val{float:right;font-weight:800;color:var(--accent);font-size:11px}

/* ---- gaveta lateral (celular) -------------------------------------------- */
.scrim{position:fixed;inset:0;z-index:54;background:rgba(12,10,8,.5);backdrop-filter:blur(3px);
  opacity:0;visibility:hidden;transition:opacity .24s ease, visibility .24s}
body.drawer .scrim{opacity:1;visibility:visible}
.side-close{display:none}

/* ---- console -------------------------------------------------------------- */
.console{position:fixed;left:0;right:0;bottom:0;z-index:60;transform:translateY(102%);transition:transform .26s cubic-bezier(.2,.8,.3,1);
  background:rgba(12,11,9,.92);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  color:#ece6da;border-top:1px solid rgba(255,255,255,.12);max-height:56vh;display:flex;flex-direction:column;
  box-shadow:0 -14px 44px -22px rgba(0,0,0,.85);
  padding-bottom:env(safe-area-inset-bottom,0)}
.console.open{transform:none}
.console .bar{display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid rgba(255,255,255,.12)}
.console .bar b{font-size:13px}
.console pre{margin:0;padding:14px 16px;overflow:auto;font-family:var(--mono);font-size:12.5px;white-space:pre-wrap}
.close-x{border:1px solid rgba(255,255,255,.2);background:transparent;color:#ece6da;border-radius:8px;padding:6px 10px;cursor:pointer;display:inline-flex;align-items:center;gap:6px}
.close-x svg{width:12px;height:12px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}

/* ---- modal ---------------------------------------------------------------- */
.mask{position:fixed;inset:0;z-index:70;background:rgba(12,10,8,.55);backdrop-filter:blur(4px);
  display:none;place-items:center;padding:16px;animation:otmFade .18s both}
.mask.open{display:grid}
.modal{background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line-strong);border-radius:20px;max-width:min(92vw,460px);width:100%;
  padding:22px;box-shadow:var(--shadow);max-height:86dvh;overflow:auto;animation:otmPop .26s cubic-bezier(.2,.8,.3,1) both}
.modal h3{margin:0 0 6px;font-size:18px;letter-spacing:-.02em}
.modal p{margin:0 0 14px;color:var(--muted);font-size:13.5px}
.modal .long{color:var(--ink);font-size:13.5px;line-height:1.6;margin:0 0 16px;
  padding:12px 14px;border-radius:var(--r-sm);background:var(--glass-2);border:1px solid var(--line)}
.ack{display:flex;gap:10px;align-items:flex-start;padding:12px;border:1px solid var(--line-strong);
  border-radius:var(--r-sm);background:var(--glass-2);font-size:13px;margin-bottom:16px}
.ack input{margin-top:2px;flex:none}
.modal .row{display:flex;gap:10px;justify-content:flex-end;flex-wrap:wrap}
.toast{position:fixed;left:50%;bottom:20px;transform:translate(-50%,14px);z-index:80;
  background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line-strong);border-left:4px solid var(--accent);border-radius:12px;
  padding:11px 16px;font-size:13px;box-shadow:var(--shadow);opacity:0;transition:.2s;max-width:92vw}
.toast.show{opacity:1;transform:translate(-50%,0)}
.toast.ok{border-left-color:var(--teal)} .toast.bad{border-left-color:var(--danger)}

/* ---- configurações (engrenagem) ------------------------------------------ */
.set-group{margin:0 0 16px}
.set-label{font-size:11px;font-weight:700;color:var(--muted);letter-spacing:.06em;text-transform:uppercase;margin:0 0 8px 2px}
.seg{display:flex;gap:6px;background:var(--glass-2);border:1px solid var(--line);border-radius:12px;padding:4px}
.seg-btn{flex:1;border:0;background:transparent;border-radius:9px;padding:9px 8px;font-size:13px;font-weight:700;cursor:pointer;color:var(--muted)}
.seg-btn[aria-pressed="true"]{background:var(--accent);color:var(--accent-ink)}
#setFont{flex-wrap:wrap}
#setFont .seg-btn{flex:1 1 30%;min-width:30%}
.swatches{display:flex;gap:10px;flex-wrap:wrap}
.sw{width:34px;height:34px;border-radius:10px;border:2px solid var(--line-strong);background:var(--sw);cursor:pointer;transition:.15s}
.sw[aria-pressed="true"]{border-color:var(--ink);box-shadow:0 0 0 2px var(--ring)}
/* cor personalizada: seletor do sistema + campo hex + botão de aplicar */
.custom-color{margin-top:12px;padding-top:12px;border-top:1px solid var(--line)}
.cc-label{display:block;font-size:12px;font-weight:700;color:var(--muted);margin:0 0 6px 2px}
.cc-row{display:flex;gap:8px;align-items:center;flex-wrap:wrap}
.cc-row input[type="color"]{width:46px;height:40px;flex:none;padding:2px;border:1px solid var(--line-strong);
  border-radius:var(--r-sm);background:var(--glass-2);cursor:pointer}
.cc-hex{flex:1 1 110px;min-width:110px;padding:10px 12px;border-radius:var(--r-sm);border:1px solid var(--line-strong);
  background:var(--glass-2);color:var(--ink);font-family:var(--mono);font-size:14px;letter-spacing:.04em}
.cc-hex:focus-visible{outline:none;border-color:var(--accent);box-shadow:0 0 0 3px var(--ring)}
.cc-row .btn{flex:none;width:auto;padding:10px 14px}
.switch{display:flex;align-items:center;gap:10px;font-size:14px;cursor:pointer}
.switch input{width:18px;height:18px;accent-color:var(--accent)}
.set-hint{font-size:12px;color:var(--muted);margin:6px 0 0 2px}
.slider{display:flex;align-items:center;gap:10px}
.slider input[type=range]{flex:1;accent-color:var(--accent);min-width:0}
.slider .val{min-width:56px;text-align:right;font-size:13px;font-weight:700;color:var(--accent)}
.modal.wide{max-width:520px;max-height:86vh;overflow:auto}
/* ---- Perfil personalizado (linhas com opções lado a lado) -------------------- */
.cp-list{display:flex;flex-direction:column;gap:10px;margin:0 0 14px}
.cp-row{border:1px solid var(--line);border-radius:12px;background:var(--glass-2);padding:10px 12px}
.cp-info{display:flex;flex-direction:column;gap:2px;margin:0 0 8px}
.cp-info b{font-size:13.5px}
.cp-info span{font-size:11.5px;color:var(--muted)}
.cp-seg{flex-wrap:wrap}
.cp-seg .seg-btn{flex:1 1 auto;min-width:72px;font-size:12.5px;padding:8px 10px}
.cp-row[data-kind="toggle"]{display:flex;align-items:center;gap:12px}
.cp-row[data-kind="toggle"] .cp-info{margin:0;flex:1}
.cpsw{flex:0 0 auto;width:46px;height:26px;border:0;border-radius:999px;background:var(--line);position:relative;cursor:pointer;padding:0;transition:background .18s}
.cpsw i{position:absolute;top:3px;left:3px;width:20px;height:20px;border-radius:50%;background:#fff;transition:transform .18s}
.cpsw[aria-checked="true"]{background:var(--accent)}
.cpsw[aria-checked="true"] i{transform:translateX(20px)}
.set-actions{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 14px}
.set-actions .btn{flex:1;min-width:120px}
.perms{display:flex;flex-direction:column;gap:8px}
.perm{display:flex;gap:10px;align-items:flex-start;padding:10px 12px;border:1px solid var(--line);border-radius:12px;background:var(--glass-2)}
.perm .ico{width:30px;height:30px;flex:none;border-radius:9px;display:grid;place-items:center;background:var(--accent);color:var(--accent-ink);font-size:15px}
.perm .ico svg{width:16px;height:16px;fill:none;stroke:currentColor;stroke-width:2;stroke-linecap:round;stroke-linejoin:round}
.perm b{display:block;font-size:13.5px}
.perm span{display:block;font-size:12px;color:var(--muted);line-height:1.45}
.perm .tag{display:inline-block;margin-top:5px;font-size:10.5px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;color:var(--warn)}

/* ---- responsivo ----------------------------------------------------------- */
@media (max-width:960px){
  .layout{grid-template-columns:1fr;gap:14px;padding-left:clamp(12px,4vw,20px);padding-right:clamp(12px,4vw,20px)}
  .side{position:fixed;top:0;left:0;bottom:0;width:min(86vw,320px);z-index:56;padding:14px;
    transform:translateX(-104%);transition:transform .26s cubic-bezier(.2,.8,.3,1);
    padding-bottom:calc(14px + env(safe-area-inset-bottom,0))}
  .side .panel{position:static;width:auto;left:auto;top:auto;max-height:100%;height:100%;border-radius:0 var(--r) var(--r) 0;padding-top:calc(56px + env(safe-area-inset-top,0));
    overflow:auto}
  body.drawer .side{transform:none}
  .side-close{display:inline-flex;position:absolute;top:calc(12px + env(safe-area-inset-top,0));right:12px}
  .burger{display:inline-flex}
}
@media (max-width:560px){
  :root{--top:58px}
  .name small{display:none}
  .hide-sm{display:none}
  .grid{grid-template-columns:1fr}
  .fields{grid-template-columns:1fr}
  .banner .in{padding:16px 14px}
  .head h2{font-size:19px}
  .card{padding:14px}
  .btn{width:100%;padding:12px 15px}   /* alvo de toque maior no celular */
  .go{gap:10px}
  .console{max-height:70dvh}
  .toast{bottom:calc(16px + env(safe-area-inset-bottom,0))}
  .top{gap:6px;padding:7px clamp(8px,3vw,16px)}
  .iconbtn{padding:8px 10px;font-size:12.5px}
}
@media (max-width:380px){
  .name{font-size:14px}
  .mark{width:32px;height:32px;font-size:12px}
  .card{padding:12px}
}
/* ---- rodapé / créditos ---------------------------------------------------- */
.credits{border-top:1px solid var(--line); background:var(--glass); backdrop-filter:var(--blur);
  -webkit-backdrop-filter:var(--blur); padding:22px clamp(12px,3vw,22px)}
.credits .in{max-width:1180px; margin:0 auto; display:flex; align-items:center; gap:16px; flex-wrap:wrap}
.credits .cwho{display:flex; flex-direction:column; gap:3px; min-width:0}
.credits .ctitle{margin:0; font-size:11px; text-transform:uppercase; letter-spacing:.12em; color:var(--muted); font-weight:700}
.credits .who{font-size:13px; color:var(--muted); margin:0}
.credits .who b{color:var(--ink)}
.credits .who code{color:var(--accent); background:var(--glass-2); border:1px solid var(--line);
  border-radius:6px; padding:1px 6px}
.credits .sp{flex:1}
.credits .clinks{display:flex; gap:10px; flex-wrap:wrap}
.dcb{display:inline-flex; align-items:center; gap:7px; text-decoration:none; color:var(--ink);
  border:1px solid var(--line); background:var(--glass-2); border-radius:10px; padding:8px 12px;
  font-size:12.5px; font-weight:700; transition:.15s; white-space:nowrap}
.dcb:hover{border-color:var(--accent); transform:translateY(-1px)}
.dcb:focus-visible{outline:2px solid var(--ring); outline-offset:1px}
.dcb svg{width:16px; height:16px; fill:currentColor; flex:none}
.dcb .arw{display:inline-flex; color:var(--muted)}
.dcb .arw svg{width:12px; height:12px; stroke:currentColor; fill:none; stroke-width:2; stroke-linecap:round; stroke-linejoin:round}
@media (max-width:520px){ .credits .who{font-size:12px} .credits .in{gap:9px} }

/* ---- logs (histórico completo) -------------------------------------------- */
.logspanel{position:fixed;left:0;right:0;bottom:0;z-index:62;transform:translateY(102%);
  transition:transform .26s cubic-bezier(.2,.8,.3,1);background:var(--paper);
  border-top:1px solid var(--line);max-height:82dvh;display:flex;flex-direction:column;
  box-shadow:0 -18px 44px -24px rgba(0,0,0,.5)}
.logspanel.open{transform:none}
.logspanel .bar{display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid var(--line)}
.logspanel .bar b{font-size:13px}
.logspanel .body{margin:0;padding:14px 16px;overflow:auto;font-family:var(--mono);font-size:12.5px}
.logsrow{display:flex;gap:10px;align-items:baseline;padding:6px 0;border-bottom:1px solid var(--line)}
.logsrow .st{flex:none;font-weight:800}
.logsrow .st.ok{color:var(--teal)} .logsrow .st.no{color:var(--danger)}
.logsrow .ts{flex:none;color:var(--muted)}
.logsrow .lb{flex:1;min-width:0;word-break:break-word}
.logsrow .cmd{color:var(--muted);font-size:11.5px;display:block;word-break:break-all}
/* Detalhes do log: o que o script tentou, o que falhou e a saída crua. */
.logsrow.has-det{cursor:pointer}
.logsrow .det{margin:6px 0 2px;padding:8px 10px;border-left:2px solid var(--line-strong);
  background:var(--glass-2);border-radius:0 var(--r-sm) var(--r-sm) 0}
.logsrow .det .why{margin:0 0 6px;padding:0;list-style:none}
.logsrow .det .why li{color:var(--danger);font-size:12px;margin:0 0 3px;word-break:break-word}
.logsrow .det .why li::before{content:"! ";font-weight:800}
.logsrow .det .counts{color:var(--muted);font-size:11.5px;margin:0 0 6px}
.logsrow .det pre{margin:0;padding:0;max-height:220px;overflow:auto;font-family:var(--mono);
  font-size:11.5px;white-space:pre-wrap;word-break:break-word;color:var(--ink);opacity:.86}
.logsrow .chev{flex:none;color:var(--muted);font-size:11px}
.logs-empty{color:var(--muted);padding:8px 0}

/* ---- terminal real -------------------------------------------------------- */
.termwrap{display:flex;flex-direction:column;gap:10px;margin-top:14px}
.termout{background:#0b0b0c;color:#e8e8e6;border:1px solid var(--line);border-radius:var(--r-sm);
  padding:14px;font-family:var(--mono);font-size:12.5px;white-space:pre-wrap;word-break:break-word;
  min-height:220px;max-height:52dvh;overflow:auto;margin:0}
.termout .c{color:#8fd3ff}
.termrow{display:flex;gap:8px;align-items:center}
.termrow .pfx{font-family:var(--mono);color:var(--accent);font-weight:800}
.termrow input{flex:1;font-family:var(--mono)}
.termhint{color:var(--muted);font-size:12px;margin:6px 0 0}
.termhint code{background:var(--glass-2);border:1px solid var(--line);border-radius:6px;padding:1px 5px}

/* ---- seletor de apps (nome + ícone) --------------------------------------- */
.apppick{display:flex;align-items:center;gap:10px;width:100%;text-align:left;cursor:pointer;
  border:1px solid var(--line-strong);background:var(--glass-2);border-radius:var(--r-sm);
  padding:8px 10px;color:var(--ink);font:inherit}
.apppick:hover{border-color:var(--accent)}
.apppick img{width:34px;height:34px;border-radius:9px;flex:none;object-fit:cover;background:var(--glass-2)}
.apppick .noico{width:34px;height:34px;border-radius:9px;flex:none;display:grid;place-items:center;
  background:var(--glass-2);border:1px solid var(--line);font-weight:800;color:var(--muted);font-size:14px}
.apppick .nm{min-width:0;display:flex;flex-direction:column;line-height:1.25}
.apppick .nm b{font-size:13.5px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.apppick .nm small{color:var(--muted);font-size:11.5px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.apppick .chev{margin-left:auto;color:var(--muted);flex:none}
.appmodal{position:fixed;inset:0;z-index:70;background:rgba(10,8,6,.5);backdrop-filter:blur(3px);
  display:none;align-items:flex-end;justify-content:center;padding:0}
.appmodal.open{display:flex}
.appsheet{width:100%;max-width:560px;background:var(--paper);border:1px solid var(--line);
  border-radius:18px 18px 0 0;max-height:86dvh;display:flex;flex-direction:column;box-shadow:var(--shadow);
  animation:otmRise .22s cubic-bezier(.2,.7,.3,1) both}
@media (min-width:600px){ .appmodal{align-items:center;padding:20px} .appsheet{border-radius:18px;max-height:80dvh} }
.appsheet .hd{display:flex;align-items:center;gap:10px;padding:14px 16px;border-bottom:1px solid var(--line)}
.appsheet .hd b{font-size:15px}
.appsheet .srch{margin:12px 16px 0;padding:11px 13px;border:1px solid var(--line-strong);border-radius:var(--r-sm);
  background:var(--glass-2);color:var(--ink);font:inherit;width:calc(100% - 32px)}
.applist{overflow:auto;padding:10px 12px 16px;margin:0;list-style:none}
.appitem{display:flex;align-items:center;gap:11px;padding:9px 8px;border-radius:11px;cursor:pointer}
.appitem:hover,.appitem:focus-visible{background:var(--glass-2);outline:none}
.appitem img,.appitem .noico{width:38px;height:38px;border-radius:10px;flex:none;object-fit:cover}
.appitem .noico{display:grid;place-items:center;background:var(--glass-2);border:1px solid var(--line);font-weight:800;color:var(--muted)}
.appitem .nm{min-width:0;display:flex;flex-direction:column;line-height:1.3}
.appitem .nm b{font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.appitem .nm small{color:var(--muted);font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.appitem .pk{font-size:11px;color:var(--muted);margin-top:1px}
@media (max-height:520px){
  .side .panel{padding-top:48px}
  .console{max-height:80dvh}
}

/* ---- HOME + VISUAL (métricas reais do aparelho) ---------------------------- */
.home{max-width:1180px;margin:0 auto;padding:20px clamp(12px,3vw,22px) 40px}
.home .hero{
  border:1px solid var(--line);border-radius:var(--r);box-shadow:var(--shadow);
  background:
    radial-gradient(120% 140% at 100% 0,color-mix(in srgb,var(--accent) 22%,transparent),transparent 60%),
    var(--glass-card);
  padding:clamp(18px,4vw,28px);margin-bottom:16px;animation:otmUp .4s both}
.home .hero h2{margin:0;font-size:clamp(20px,4.4vw,30px);font-weight:800;letter-spacing:-.03em}
.home .hero p{margin:6px 0 0;color:var(--muted);max-width:64ch}
.home .hero .hi{color:var(--accent)}
.home .cols{display:grid;grid-template-columns:1.25fr .9fr;gap:16px;align-items:start}
@media (max-width:860px){.home .cols{grid-template-columns:1fr}}
.panelbox{border:1px solid var(--line);border-radius:var(--r);background:var(--glass-card);
  box-shadow:var(--shadow);padding:16px;animation:otmUp .45s both}
.panelbox h3{margin:0 0 2px;font-size:15px;font-weight:800;letter-spacing:-.01em}
.panelbox .sub{margin:0 0 14px;color:var(--muted);font-size:12.5px}
.stats{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:12px}
.stat{border:1px solid var(--line);border-radius:var(--r-sm);padding:12px 13px;background:var(--glass-2)}
.stat .k{display:flex;align-items:center;gap:7px;font-size:11.5px;font-weight:700;color:var(--muted);
  text-transform:uppercase;letter-spacing:.06em}
.stat .k .ic{width:15px;height:15px;flex:none;color:var(--accent)}
.stat .v{font-size:clamp(20px,5vw,27px);font-weight:800;letter-spacing:-.03em;margin-top:6px;line-height:1.1;
  font-variant-numeric:tabular-nums}
.stat .v small{font-size:12px;font-weight:600;color:var(--muted);margin-left:3px}
.stat .m{margin-top:9px;height:7px;border-radius:999px;background:var(--line);overflow:hidden}
.stat .m > i{display:block;height:100%;width:0;border-radius:999px;background:var(--accent);
  transition:width .5s cubic-bezier(.22,1,.36,1)}
.stat .m.g > i{background:linear-gradient(90deg,var(--teal),#7ad9c3)}
.stat .m.w > i{background:linear-gradient(90deg,var(--warn),#f0c25e)}
.stat .m.b > i{background:linear-gradient(90deg,var(--danger),#ff9d92)}
.stat .foot{margin-top:7px;font-size:11.5px;color:var(--muted);font-variant-numeric:tabular-nums}
/* cabeçalho do painel de métricas: título + botão de atualizar na mesma linha */
.panelbox .boxhead{display:flex;align-items:flex-start;justify-content:space-between;gap:10px;margin-bottom:12px}
.panelbox .boxhead h3{margin:0}
.panelbox .boxhead .sub{margin:3px 0 0}
/* grupos de métricas: separa "sistema agora" de "uso do aparelho" */
.stat-group + .stat-group{margin-top:16px;padding-top:14px;border-top:1px dashed var(--line)}
.glabel{display:flex;align-items:center;flex-wrap:wrap;gap:8px;font-size:11.5px;font-weight:800;
  text-transform:uppercase;letter-spacing:.07em;color:var(--muted);margin:0 0 10px}
.glabel .live{text-transform:none;letter-spacing:0}
.glabel .need{font-weight:600;text-transform:none;letter-spacing:0;font-size:11px;color:var(--muted);
  border:1px solid var(--line);border-radius:999px;padding:2px 9px}
.live{display:inline-flex;align-items:center;gap:6px;font-size:11px;font-weight:700;color:var(--teal)}
.live .dot{width:7px;height:7px;border-radius:50%;background:var(--teal);box-shadow:0 0 0 0 color-mix(in srgb,var(--teal) 55%,transparent);
  animation:otmPulse 2s infinite}
@keyframes otmPulse{0%{box-shadow:0 0 0 0 color-mix(in srgb,var(--teal) 50%,transparent)}
  70%{box-shadow:0 0 0 8px transparent}100%{box-shadow:0 0 0 0 transparent}}
@keyframes otmUp{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}
.qa{display:grid;grid-template-columns:1fr 1fr;gap:10px}
@media (max-width:420px){.qa{grid-template-columns:1fr}}
.qa button,.qa a{
  display:flex;align-items:center;gap:10px;text-decoration:none;color:var(--ink);cursor:pointer;
  border:1px solid var(--line);background:var(--glass-2);border-radius:var(--r-sm);padding:12px 13px;
  font:inherit;font-weight:700;font-size:13.5px;text-align:left;transition:transform .14s,border-color .14s,background .14s}
.qa button:hover,.qa a:hover{transform:translateY(-2px);border-color:var(--accent);background:var(--glass)}
.qa .ic{width:30px;height:30px;flex:none;border-radius:9px;display:grid;place-items:center;
  background:color-mix(in srgb,var(--accent) 16%,transparent);color:var(--accent)}
.qa .ic svg{width:17px;height:17px}
.qa .tx{display:flex;flex-direction:column;line-height:1.25}
.qa .tx small{color:var(--muted);font-weight:500;font-size:11.5px}
.jump{display:flex;flex-wrap:wrap;gap:8px;margin-top:4px}
.jump button{border:1px solid var(--line);background:var(--glass-2);color:var(--ink);border-radius:999px;
  padding:7px 13px;font:inherit;font-weight:700;font-size:12.5px;cursor:pointer;transition:.15s}
.jump button:hover{border-color:var(--accent);transform:translateY(-1px)}
.stale{color:var(--muted);font-size:11.5px}
@media (prefers-reduced-motion:reduce){
  .home .hero,.panelbox{animation:none}
  .stat .m > i{transition:none}
  .live .dot{animation:none}
}
</style>
</head>
<body>
<header class="top">
  <button class="iconbtn burger" id="burger" aria-label="Abrir categorias" aria-expanded="false"><svg class="stroke" viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6h18M3 12h18M3 18h18"/></svg></button>
  <div class="mark" aria-hidden="true">TX</div>
  <div class="name">Trix<small>Otimizações</small></div>
  <div class="grow"></div>
  <button class="iconbtn" id="btnLogs" aria-label="Ver o histórico de logs" title="Logs"><svg class="stroke" viewBox="0 0 24 24" aria-hidden="true"><path d="M4 6h16M4 12h16M4 18h10"/></svg></button>
  <button class="iconbtn" id="btnGear" aria-label="Configurações" title="Configurações"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 15.5A3.5 3.5 0 1 1 12 8.5a3.5 3.5 0 0 1 0 7Zm7.43-2.53c.04-.32.07-.64.07-.97s-.03-.66-.07-.98l2.11-1.65a.5.5 0 0 0 .12-.64l-2-3.46a.5.5 0 0 0-.61-.22l-2.49 1a7.3 7.3 0 0 0-1.69-.98l-.38-2.65A.5.5 0 0 0 14 2h-4a.5.5 0 0 0-.49.42l-.38 2.65c-.61.25-1.17.59-1.69.98l-2.49-1a.5.5 0 0 0-.61.22l-2 3.46a.5.5 0 0 0 .12.64L4.57 11c-.04.32-.07.65-.07.98s.03.65.07.97l-2.11 1.66a.5.5 0 0 0-.12.64l2 3.46c.14.24.42.34.68.22l2.49-1c.52.39 1.08.72 1.69.98l.38 2.65c.04.24.24.42.49.42h4c.25 0 .46-.18.49-.42l.38-2.65c.61-.25 1.17-.59 1.69-.98l2.49 1c.26.11.54.02.68-.22l2-3.46a.5.5 0 0 0-.12-.64l-2.11-1.66Z"/></svg></button>
</header>

<div class="banner">
  <div class="in">
    <h1>Bem-vindo ao Trix</h1>
    <p>DNS, RAM, renderizador, touch do Free Fire, debloat e ajustes profundos — tudo num lugar só. Deixe seu celular liso que nem sabão. Toque no <b>?</b> de cada cartão para saber o que ele faz.</p>
    <span class="tag"><span class="dot"></span>conectado ao pack local</span>
  </div>
</div>

<div class="scrim" id="scrim"></div>

<div class="layout">
  <aside class="side" id="side" aria-label="Categorias">
    <div class="panel">
      <button class="iconbtn side-close" id="sideClose" aria-label="Fechar"><svg class="stroke" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button>
      <h2>Categorias</h2>
      <nav class="nav" id="nav">
        <a href="#Painel" data-g="Painel" aria-current="true"><span class="c"></span>Painel<span class="count" id="navHomeCount" hidden></span></a>
        <?php foreach ($groups as $g => $items): ?>
          <a href="#<?= htmlspecialchars(rawurlencode($g), ENT_QUOTES) ?>" data-g="<?= htmlspecialchars($g, ENT_QUOTES) ?>"
             aria-current="false">
            <span class="c"></span><?= htmlspecialchars($meta[$g]['t'] ?? $g) ?>
            <span class="count"><?= count($items) ?></span>
          </a>
        <?php endforeach; ?>
        <a href="#Terminal" data-g="Terminal" aria-current="false"><span class="c"></span>Terminal</a>
      </nav>
    </div>
  </aside>

  <main class="content">
    <section id="g-Painel" data-g="Painel" class="home">
      <!-- Ação principal: limpeza inteligente (card de destaque) -->
      <section class="hero" aria-label="Limpeza inteligente">
        <div class="hero-glow" aria-hidden="true"></div>
        <div class="hero-body">
          <div class="hero-head">
            <span class="hero-ico" aria-hidden="true">
              <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round">
                <path d="M12 3 5 6.5v4.8c0 4.3 2.9 7.9 7 9.2 4.1-1.3 7-4.9 7-9.2V6.5L12 3Z"/>
                <path d="M9.2 12.1l2 2 3.6-4"/>
              </svg>
            </span>
            <div class="hero-txt">
              <span class="hero-kicker">Otimização em 1 toque</span>
              <h2 class="hero-title">Clean Phone</h2>
              <p class="hero-sub">Libera RAM, limpa cache e alivia o sistema.</p>
            </div>
          </div>
          <div class="hero-meta">
            <span class="hero-chip" data-stat="ramf">—</span>
            <span class="hero-chip" id="heroStatus">Pronto para otimizar</span>
          </div>
          <button class="hero-btn" id="rocketBtn" type="button" onclick="runActionById('clean')">
            <svg class="hb-ico" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
              <path d="M13 2 4.5 13.5H11l-1 8.5L19.5 10H13l0-8Z"/>
            </svg>
            <span class="hb-txt">Otimizar agora</span>
            <span class="hb-load" aria-hidden="true"></span>
          </button>
          <p class="hero-note">Nada é encerrado sem necessidade — o pack ajusta só o que está pesando.</p>
        </div>
      </section>

      <!-- Perfil de desempenho fixo (Desempenho x Equilibrado) -->
      <div class="panelbox config-gpu-card" data-perfmode-card style="margin-top:16px;">
        <h3>Perfil de Desempenho</h3>
        <p class="sub">Fixa o desempenho no máximo ou deixa o sistema equilibrar sozinho. Vale para o aparelho todo.</p>
        <div class="opts" role="group" aria-label="Perfil de desempenho">
          <button class="opt" type="button" data-perfmode="on" aria-pressed="false">
            <span class="opt-t">Desempenho</span>
            <span class="opt-s" data-label="Máx FPS">Máx FPS</span>
          </button>
          <button class="opt" type="button" data-perfmode="off" aria-pressed="false">
            <span class="opt-t">Equilibrado</span>
            <span class="opt-s" data-label="Estável">Estável</span>
          </button>
        </div>
        <div class="now" data-now hidden></div>
      </div>

      <!-- Vitalidade: cuidar para durar (nao forca o aparelho) -->
      <div class="panelbox config-gpu-card" data-vital-card style="margin-top:16px;">
        <h3>Saúde do telefone</h3>
        <p class="sub">Cuida para o aparelho durar: mede a saúde real da bateria, reduz o desgaste e avisa os hábitos que encurtam a vida. Nada aqui força o celular.</p>
        <div class="vital-head">
          <div class="vital-score" data-vital="score">—<span>/100</span></div>
          <span class="vital-badge off" data-vital="badge">sem leitura</span>
        </div>
        <div class="vital-gauge" data-vital="gauge"><i data-vital="fill"></i><u data-vital="mark"></u></div>
        <div class="vital-stats">
          <div><b data-vital="health">—</b><s>saúde da bateria</s></div>
          <div><b data-vital="cycles">—</b><s>ciclos de carga</s></div>
          <div><b data-vital="temp">—</b><s>temperatura</s></div>
          <div><b data-vital="w80">0</b><s>cargas acima de 80%</s></div>
        </div>
        <div class="vital-actions">
          <button class="btn primary" type="button" data-vital-go="optimize">Otimizar saúde do telefone</button>
          <button class="btn" type="button" data-vital-go="care_off">Desligar</button>
          <button class="btn" type="button" data-vital-go="diag">Diagnóstico</button>
          <button class="btn" type="button" data-vital-go="guard">Guardião</button>
        </div>
        <div class="now" data-vital="now" hidden></div>
      </div>

      <!-- Game Lab & Perfis -->
      <div class="panelbox mt-16 gamelab-section" style="border: 1px solid var(--line); border-radius: var(--r); padding: 16px; background: var(--glass-card);">
        <h3>Game Lab & Perfis</h3>
        <p class="sub">Modos otimizados para extrair o máximo do seu hardware com inteligência.</p>
        <div class="gamelab-grid" style="display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 16px; margin-top: 12px;">
          <div class="card" style="padding: 16px; background: var(--paper); border-radius: var(--r-sm);">
            <h4 style="margin:0 0 8px; color:var(--accent);">1. Modo Batata (2GB a 4GB RAM)</h4>
            <p class="sub" style="font-size:0.85em; margin-bottom:8px;">Sobrevivência de FPS e liberação cirúrgica de memória para jogos rodarem liso sem fechar sozinhos.</p>
            <ul style="font-size:0.82em; padding-left:16px; margin:0 0 12px; color:var(--muted);">
              <li>Animações desativadas (0x)</li>
              <li>Limite de 1 ou 2 apps em 2º plano</li>
              <li>Compilação Dexopt recomendada</li>
              <li>Resolução/DPI reduzida</li>
            </ul>
            <button class="btn" onclick="runActionById('clean')" style="width:100%;">Ativar Modo Batata</button>
          </div>
          <div class="card" style="padding: 16px; background: var(--paper); border-radius: var(--r-sm); border: 1.5px solid var(--accent);">
            <h4 style="margin:0 0 8px; color:var(--accent);">2. Modo Competitivo (Free Fire / CODM / FF MAX) — Recomendado</h4>
            <p class="sub" style="font-size:0.85em; margin-bottom:8px;">Equilíbrio perfeito de latência de toque ultra baixa, prioridade total na CPU e bloqueio de interferências.</p>
            <ul style="font-size:0.82em; padding-left:16px; margin:0 0 12px; color:var(--muted);">
              <li>Driver de jogo ativado no App</li>
              <li>Jogo sem restrição de bateria</li>
              <li>No máximo 4 apps em 2º plano (mais RAM p/ o jogo)</li>
              <li>Anti-relog: não fecha nem volta ao login</li>
              <li>Sensibilidade e velocidade de ponteiro no máximo</li>
              <li>Não Perturbe ativado para evitar notificações</li>
            </ul>
            <div class="fields">
              <div class="field wide">
                <label for="home-game-pkg">Qual jogo abrir</label>
                <?= otm_pkg_picker('home-game-pkg', 'pkg') ?>
              </div>
            </div>
            <button class="btn primary" onclick="runGameHome(this)" style="width:100%;">Ativar Competitivo</button>
          </div>
          <div class="card" style="padding: 16px; background: var(--paper); border-radius: var(--r-sm);">
            <h4 style="margin:0 0 8px; color:var(--accent);">3. Modo 90Hz / 120Hz Ultra Fluido</h4>
            <p class="sub" style="font-size:0.85em; margin-bottom:8px;">Configuração avançada para telas de alta taxa de atualização, mantendo quadros constantes.</p>
            <ul style="font-size:0.82em; padding-left:16px; margin:0 0 12px; color:var(--muted);">
              <li>Taxa de atualização forçada no pico</li>
              <li>Compilação Speed-profile ativada</li>
              <li>Buffer de log reduzido para mínimo atraso</li>
              <li>Controle térmico preventivo</li>
            </ul>
            <button class="btn" onclick="runActionById('turbo.refresh_max')" style="width:100%;">Ativar 90Hz/120Hz</button>
          </div>
          <div class="card" style="padding: 16px; background: var(--paper); border-radius: var(--r-sm);">
            <h4 style="margin:0 0 8px; color:var(--accent);">4. Modo Econômico</h4>
            <p class="sub" style="font-size:0.85em; margin-bottom:8px;">Ideal para quando a bateria está abaixo de 25% ou o celular esquentou após horas de jogo.</p>
            <ul style="font-size:0.82em; padding-left:16px; margin:0 0 12px; color:var(--muted);">
              <li>Taxa de atualização em 60Hz estável</li>
              <li>Economia inteligente de energia</li>
              <li>Desativação de serviços desnecessários</li>
              <li>Menos atividade em segundo plano</li>
            </ul>
            <button class="btn" onclick="runActionById('refresh.60')" style="width:100%;">Ativar Modo Econômico</button>
          </div>
          <div class="card" style="padding: 16px; background: var(--paper); border-radius: var(--r-sm);">
            <h4 style="margin:0 0 8px; color:var(--accent);">5. Personalizado</h4>
            <p class="sub" style="font-size:0.85em; margin-bottom:8px;">Monte o seu perfil: ligue só o que quiser e aplique quando estiver pronto.</p>
            <button class="btn primary" onclick="runActionById('profile.custom')" style="width:100%;">Configurar Personalizado</button>
          </div>
        </div>
      </div>
      <div class="cols">
        <div class="panelbox" id="visual">
          <div class="boxhead">
            <div>
              <h3>Consumo real do aparelho</h3>
              <p class="sub">Atualiza sozinho a cada 4 s enquanto você está aqui.</p>
            </div>
            <button type="button" class="jump" id="btnRefreshStats">Atualizar</button>
          </div>

          <div class="stat-group">
            <div class="glabel">Sistema agora <span class="live" id="liveBadge" hidden><span class="dot"></span>ao vivo</span></div>
            <div class="stats">
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="7" width="16" height="10" rx="2"/><path d="M8 7V5m4 2V5m4 2V5M8 17v2m4-2v2m4-2v2"/></svg>Memória RAM</div>
                <div class="v" data-stat="ram">—</div>
                <div class="m" data-m="ram"><i></i></div>
                <div class="foot" data-stat="ramf">—</div>
              </div>
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a9 9 0 1 0 9 9"/><path d="M12 12l5-3"/></svg>Carga da CPU</div>
                <div class="v" data-stat="cpu">—</div>
                <div class="m" data-m="cpu"><i></i></div>
                <div class="foot" data-stat="cpuf">—</div>
              </div>
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="8" width="17" height="8" rx="2"/><path d="M22 11v2"/><path d="M6 11v2m4-2v2m4-2v2"/></svg>Bateria</div>
                <div class="v" data-stat="bat">—</div>
                <div class="m" data-m="bat"><i></i></div>
                <div class="foot" data-stat="batf">—</div>
              </div>
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v18"/><path d="M5 8h14"/><path d="M7 8l-3 6h6z"/><path d="M17 8l-3 6h6z"/></svg>Armazenamento</div>
                <div class="v" data-stat="stor">—</div>
                <div class="m" data-m="stor"><i></i></div>
                <div class="foot" data-stat="storf">—</div>
              </div>
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="14" rx="2"/><path d="M8 20h8M12 18v2"/></svg>Taxa de tela</div>
                <div class="v" data-stat="disp">—</div>
                <div class="foot" data-stat="dispf">—</div>
              </div>
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 4 14h6l-1 8 9-12h-6z"/></svg>FPS do jogo</div>
                <div class="v" data-stat="fps">—</div>
                <div class="foot" data-stat="fpsf">—</div>
              </div>
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>Tempo ligado</div>
                <div class="v" data-stat="up">—</div>
                <div class="foot" data-stat="upf">—</div>
              </div>
            </div>
          </div>

          <div class="stat-group">
            <div class="glabel">Uso do aparelho <span class="need" id="usageNeed">precisa do Acesso a dados de uso</span></div>
            <div class="stats">
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="16" rx="2"/><path d="M3 9h18"/><circle cx="6.5" cy="6.5" r=".8" fill="currentColor" stroke="none"/></svg>App em primeiro plano</div>
                <div class="v" data-stat="fg">—</div>
                <div class="foot" data-stat="fgf">—</div>
              </div>
              <div class="stat">
                <div class="k"><svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 19V5"/><path d="M4 19h16"/><rect x="7" y="12" width="3" height="7"/><rect x="12" y="8" width="3" height="11"/><rect x="17" y="10" width="3" height="9"/></svg>Uso nas últimas 24 h</div>
                <div class="v" data-stat="usage">—</div>
                <div class="foot" data-stat="usagef">—</div>
              </div>
            </div>
            <p class="stale" id="usageHint" hidden>Estes dois cartões só aparecem com número depois que você libera o <b>Acesso a dados de uso</b>. Toque em <b>Liberar</b> para abrir a tela do sistema.</p>
            <p class="stale" id="usagePermRow" style="margin-top:8px">
              <button type="button" class="jump" id="btnUsagePerm" style="border-radius:999px;padding:6px 12px;font-weight:700">Liberar acesso a dados de uso</button>
            </p>
          </div>

          <p class="stale" id="statsHint" hidden>Sem leitura do aparelho agora — os valores aparecem como “—”. Toque em “Atualizar” ou abra o app no celular.</p>
        </div>
        <div class="panelbox">
          <h3>Comece por aqui</h3>
          <p class="sub">As ações mais usadas, com um toque.</p>
          <div class="qa">
            <button type="button" data-qa="smart.auto">
              <span class="ic"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="11" cy="11" r="7"/><path d="m21 21-4.3-4.3"/></svg></span>
              <span class="tx">Otimizador inteligente<small>Analisa e otimiza o seu celular</small></span></button>
            <button type="button" data-qa="snapshot_save">
              <span class="ic"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3v12"/><path d="m7 10 5 5 5-5"/><path d="M5 21h14"/></svg></span>
              <span class="tx">Salvar snapshot<small>Ponto de retorno seguro</small></span></button>
            <button type="button" data-qa="clean">
              <span class="ic"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M9 7V5h6v2m-8 0 1 13h8l1-13"/></svg></span>
              <span class="tx">Limpar cache e RAM<small>Libera memória e suaviza</small></span></button>
            <button type="button" data-qa="fluidez">
              <span class="ic"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M13 2 4 14h7l-1 8 9-12h-7z"/></svg></span>
              <span class="tx">Fluidez geral<small>Toque, Hz e animações</small></span></button>
            <button type="button" data-qa="ff">
              <span class="ic"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2s4 4 4 9a4 4 0 0 1-8 0c0-2 1-3 1-3s-1 3 1 5"/><path d="M12 22a7 7 0 0 0 7-7c0-4-3-7-3-7"/></svg></span>
              <span class="tx">Abrir Free Fire otimizado<small>Prepara e entra no jogo</small></span></button>
          </div>
          <p class="sub" style="margin:16px 0 6px">Ir para uma categoria</p>
          <div class="jump" id="jump"></div>
        </div>
      </div>
    </section>
    <?php foreach ($groups as $g => $items): ?>
      <section id="g-<?= htmlspecialchars(rawurlencode($g), ENT_QUOTES) ?>" data-g="<?= htmlspecialchars($g, ENT_QUOTES) ?>" hidden>
        <div class="head">
          <h2><?= htmlspecialchars($meta[$g]['t'] ?? $g) ?></h2>
          <p><?= htmlspecialchars($meta[$g]['s'] ?? '') ?></p>
        </div>
        <div class="note">
          <span aria-hidden="true">ⓘ</span>
          <div><b>Antes de mexer:</b> salve um <b>snapshot</b> na aba Geral para poder voltar.
          Ações <b>cuidado</b> e <b>root</b> pedem confirmação e são reversíveis.</div>
        </div>
        <div class="grid">
          <?php
          $renderedChoice = [];
          foreach ($items as $ci => $a):
            // Ações fundidas dentro do "Otimizador inteligente" não viram card
            // próprio (card => false em lib.php): elas aparecem como botões no
            // hub do otimizador. O id continua no ACTIONS, que é o que o JS usa.
            if (($a['card'] ?? true) === false) continue;
            // opções de um grupo de escolha viram um único cartão, na 1ª posição
            if (!empty($a['choice'])):
              $ck = $a['choice'];
              if (isset($renderedChoice[$ck])) continue;
              $renderedChoice[$ck] = true;
              $c = $choiceMeta[$ck];
              $crisk = $c['risk']; ?>
              <article class="card card-choice" data-choice="<?= htmlspecialchars($ck, ENT_QUOTES) ?>"
                       data-state-key="<?= htmlspecialchars((string)($c['state'] ?? ''), ENT_QUOTES) ?>"
                       data-state-backend="<?= htmlspecialchars((string)($c['state_backend'] ?? ''), ENT_QUOTES) ?>"
                       style="--i:<?= (int)($ci % 12) ?>">
                <div class="row">
                  <h3><?= htmlspecialchars($c['title']) ?></h3>
                  <span class="chip <?= htmlspecialchars($crisk, ENT_QUOTES) ?>"><?= htmlspecialchars($riskLabel[$crisk] ?? $crisk) ?></span>
                </div>
                <p><?= htmlspecialchars($c['desc']) ?></p>
                <?php if (!empty($c['app'])): ?>
                  <div class="fields">
                    <?php foreach ($c['params'] as $p):
                      $pid = htmlspecialchars($ck . '-' . $p['name'], ENT_QUOTES); ?>
                      <div class="field wide">
                        <label for="<?= $pid ?>"><?= htmlspecialchars($p['label']) ?></label>
                        <?php if (($p['type'] ?? '') === 'enum'): ?>
                          <select id="<?= $pid ?>" data-p="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>">
                            <?php foreach (($p['options'] ?? []) as $opt): ?>
                              <option value="<?= htmlspecialchars((string) $opt, ENT_QUOTES) ?>"
                                <?= ((string) $opt === (string) ($p['default'] ?? '')) ? ' selected' : '' ?>><?= htmlspecialchars((string) $opt) ?></option>
                            <?php endforeach; ?>
                          </select>
                        <?php else: ?>
                          <?php if (($p['type'] ?? '') === 'pkg'): ?>
                            <?= otm_pkg_picker($ck . '-' . $p['name'], $p['name'], (string) ($p['default'] ?? '')) ?>
                          <?php else: ?>
                          <input id="<?= $pid ?>" data-p="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>"
                                 type="text" value="<?= htmlspecialchars((string) ($p['default'] ?? ''), ENT_QUOTES) ?>">
                          <?php endif; ?>
                        <?php endif; ?>
                      </div>
                    <?php endforeach; ?>
                  </div>
                <?php endif; ?>
                <div class="opts" role="group" aria-label="<?= htmlspecialchars($c['title'], ENT_QUOTES) ?>">
                  <?php foreach ($c['opts'] as $o): ?>
                    <button class="opt" type="button" data-opt="<?= htmlspecialchars($o['id'], ENT_QUOTES) ?>"
                            data-optlabel="<?= htmlspecialchars($o['label'], ENT_QUOTES) ?>"
                            data-state-value="<?= htmlspecialchars((string)($o['state_value'] ?? ''), ENT_QUOTES) ?>"
                            data-state-match="<?= htmlspecialchars((string)($o['state_match'] ?? ''), ENT_QUOTES) ?>"
                            data-state-backend-value="<?= htmlspecialchars((string)($o['state_backend_value'] ?? ''), ENT_QUOTES) ?>"
                            <?= !empty($o['state_auto']) ? 'data-state-auto="1" ' : '' ?>aria-pressed="false">
                      <span class="opt-t"><?= htmlspecialchars($o['label']) ?></span>
                      <span class="opt-s">Selecionar</span>
                    </button>
                  <?php endforeach; ?>
                </div>
                <div class="now" data-now hidden></div>
              </article>
            <?php
              continue;
            endif;
            $risk = $a['risk'] ?? 'safe'; ?>
            <article class="card" data-id="<?= htmlspecialchars($a['id'], ENT_QUOTES) ?>"
                     style="--i:<?= (int)($ci % 12) ?>">
              <div class="row">
                <h3><?= htmlspecialchars($a['label']) ?></h3>
                <span class="chip <?= htmlspecialchars($risk, ENT_QUOTES) ?>"><?= htmlspecialchars($riskLabel[$risk] ?? $risk) ?></span>
                <button class="help-btn" data-help="<?= htmlspecialchars($a['id'], ENT_QUOTES) ?>"
                        aria-label="O que faz: <?= htmlspecialchars($a['label'], ENT_QUOTES) ?>" title="O que isso faz?">?</button>
              </div>
              <?php if (!empty($a['desc'])): ?><p><?= htmlspecialchars($a['desc']) ?></p><?php endif; ?>
              <?php if ($a['id'] === 'smart.auto'): ?>
                <div class="hub-sub-t">Otimizador completo</div>
                <div class="hub-grid" role="group" aria-label="Otimizador: leituras e testes">
                  <button class="hbtn" type="button" data-hub="smart.report"><span class="opt-t">Analisar aparelho</span><span class="opt-s">só leitura</span></button>
                  <button class="hbtn" type="button" data-hub="smart.decide"><span class="opt-t">Ver plano</span><span class="opt-s">antes de aplicar</span></button>
                  <button class="hbtn" type="button" data-hub="smart.bench"><span class="opt-t">Medir antes x depois</span><span class="opt-s">prova o ganho</span></button>
                  <button class="hbtn" type="button" data-hub="smart.compare"><span class="opt-t">Comparar combinações</span><span class="opt-s">fica com a melhor</span></button>
                  <button class="hbtn" type="button" data-hub="smart.state"><span class="opt-t">O que está ativo</span><span class="opt-s">só leitura</span></button>
                </div>
                <div class="hub-sub-t">Snapshot e reversão</div>
                <div class="hub-grid" role="group" aria-label="Snapshot e reversão">
                  <button class="hbtn" type="button" data-hub="snapshot_save"><span class="opt-t">Salvar snapshot</span><span class="opt-s">ponto de retorno</span></button>
                  <button class="hbtn" type="button" data-hub="snapshot_list"><span class="opt-t">Ver snapshots</span><span class="opt-s">só leitura</span></button>
                  <button class="hbtn" type="button" data-hub="snapshot_diff"><span class="opt-t">Comparar com o último</span><span class="opt-s">só leitura</span></button>
                  <button class="hbtn" type="button" data-hub="snapshot_restore"><span class="opt-t">Restaurar último</span><span class="opt-s">volta à foto</span></button>
                  <button class="hbtn" type="button" data-hub="restore_all"><span class="opt-t">Reverter TUDO</span><span class="opt-s">estado de fábrica</span></button>
                </div>
              <?php endif; ?>
              <?php if (!empty($a['params'])): ?>
                <div class="fields">
                  <?php foreach ($a['params'] as $p):
                    $t = $p['type'] ?? 'text';
                    $wide = in_array($t, ['pkg', 'host', 'text', 'name', 'enum'], true);
                    $pid = htmlspecialchars($a['id'] . '-' . $p['name'], ENT_QUOTES);
                    $slider = in_array($t, ['int', 'float'], true) && isset($p['min'], $p['max']); ?>
                    <div class="field<?= $wide ? ' wide' : '' ?>">
                      <label for="<?= $pid ?>"><?= htmlspecialchars($p['label']) ?><?php
                        if ($slider): ?> <span class="field-val" data-for="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>"><?= htmlspecialchars((string)($p['default'] ?? '')) ?></span><?php endif; ?></label>
                      <?php if ($t === 'enum'): ?>
                        <select id="<?= $pid ?>" data-p="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>">
                          <?php foreach (($p['options'] ?? []) as $opt): ?>
                            <option value="<?= htmlspecialchars((string) $opt, ENT_QUOTES) ?>"
                              <?= ((string) $opt === (string) ($p['default'] ?? '')) ? ' selected' : '' ?>><?= htmlspecialchars((string) $opt) ?></option>
                          <?php endforeach; ?>
                        </select>
                      <?php elseif ($slider): ?>
                        <div class="slider">
                          <input id="<?= $pid ?>" data-p="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>"
                                 data-state="<?= htmlspecialchars((string)($p['state'] ?? ''), ENT_QUOTES) ?>"
                                 type="range" value="<?= htmlspecialchars((string) ($p['default'] ?? ''), ENT_QUOTES) ?>"
                                 min="<?= htmlspecialchars((string) $p['min'], ENT_QUOTES) ?>"
                                 max="<?= htmlspecialchars((string) $p['max'], ENT_QUOTES) ?>"
                                 step="<?= htmlspecialchars((string) ($p['step'] ?? 1), ENT_QUOTES) ?>">
                          <input class="num" type="number" data-pnum="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>"
                                 data-state="<?= htmlspecialchars((string)($p['state'] ?? ''), ENT_QUOTES) ?>"
                                 value="<?= htmlspecialchars((string) ($p['default'] ?? ''), ENT_QUOTES) ?>"
                                 min="<?= htmlspecialchars((string) $p['min'], ENT_QUOTES) ?>"
                                 max="<?= htmlspecialchars((string) $p['max'], ENT_QUOTES) ?>"
                                 step="<?= htmlspecialchars((string) ($p['step'] ?? 1), ENT_QUOTES) ?>"
                                 inputmode="numeric" aria-label="<?= htmlspecialchars($p['label'], ENT_QUOTES) ?>">
                        </div>
                      <?php else: ?>
                      <?php if ($t === 'pkg'): ?>
                        <?= otm_pkg_picker($pid, $p['name'], (string) ($p['default'] ?? '')) ?>
                      <?php else: ?>
                      <input id="<?= $pid ?>"
                             data-p="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>"
                             type="<?= in_array($t, ['int', 'float'], true) ? 'number' : 'text' ?>"
                             value="<?= htmlspecialchars((string) ($p['default'] ?? ''), ENT_QUOTES) ?>"
                             <?= $t === 'host' ? 'placeholder="dns.exemplo.com"' : '' ?>
                             <?= isset($p['min']) ? 'min="' . htmlspecialchars((string) $p['min'], ENT_QUOTES) . '"' : '' ?>
                             <?= isset($p['max']) ? 'max="' . htmlspecialchars((string) $p['max'], ENT_QUOTES) . '"' : '' ?>
                             <?= isset($p['step']) ? 'step="' . htmlspecialchars((string) $p['step'], ENT_QUOTES) . '"' : '' ?>>
                      <?php endif; ?>
                      <?php endif; ?>
                    </div>
                  <?php endforeach; ?>
                </div>
              <?php endif; ?>
              <div class="go">
                <button class="btn <?= $risk === 'safe' ? 'primary' : '' ?>" data-run>Executar</button>
              </div>
            </article>
          <?php endforeach; ?>
        </div>
      </section>
    <?php endforeach; ?>
<?= $TERMINAL_HTML ?>
  </main>
</div>

<footer class="credits">
  <div class="in">
    <div class="cwho">
      <p class="ctitle">Créditos</p>
      <p class="who">Feito por <b>00deUdia</b> · Discord <code>cute_axolotl_51194</code></p>
    </div>
    <span class="sp"></span>
    <div class="clinks">
      <a class="dcb" href="https://discord.com/users/cute_axolotl_51194" target="_blank" rel="noopener"
         title="Abrir meu perfil no Discord">
        <svg viewBox="0 0 127.14 96.36" aria-hidden="true"><path d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z"/></svg>
        Meu Discord <span class="arw"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 17 17 7M9 7h8v8"/></svg></span>
      </a>
      <a class="dcb" href="https://discord.gg/w9hFBeVKw8" target="_blank" rel="noopener"
         title="Entrar no meu servidor do Discord">
        <svg viewBox="0 0 127.14 96.36" aria-hidden="true"><path d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z"/></svg>
        Servidor <span class="arw"><svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 17 17 7M9 7h8v8"/></svg></span>
      </a>
    </div>
  </div>
</footer>

<div class="console" id="console" role="region" aria-label="Saída">
  <div class="bar"><b id="consoleTitle">Saída</b><span class="grow"></span>
    <button class="close-x" id="consoleClose">fechar <svg class="stroke" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button></div>
  <pre id="consoleOut"></pre>
</div>

<div class="logspanel" id="logspanel" role="region" aria-label="Logs">
  <div class="bar"><b>Logs</b><span class="grow"></span>
    <button class="jump" id="logsRefresh" type="button" style="border-radius:999px;padding:6px 12px">Atualizar</button>
    <button class="close-x" id="logsClose">fechar <svg class="stroke" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button></div>
  <div class="body" id="logsBody"></div>
</div>

<div class="appmodal" id="appModal" role="dialog" aria-modal="true" aria-label="Escolher app">
  <div class="appsheet">
    <div class="hd"><b>Escolher app</b><span class="grow"></span>
      <button class="close-x" id="appModalClose">fechar <svg class="stroke" viewBox="0 0 24 24" aria-hidden="true"><path d="M6 6l12 12M18 6 6 18"/></svg></button></div>
    <input class="srch" id="appSearch" type="text" placeholder="Buscar por nome ou pacote…" autocomplete="off" autocapitalize="off" spellcheck="false">
    <ul class="applist" id="appList"></ul>
  </div>
</div>

<div class="mask" id="mask" role="dialog" aria-modal="true" aria-labelledby="mTitle">
  <div class="modal">
    <h3 id="mTitle">Confirmar</h3>
    <p id="mDesc"></p>
    <div class="long" id="mLong" hidden></div>
    <label class="ack" id="mAck"><input type="checkbox" id="mCheck">
      <span id="mAckLabel">Estou ciente dos riscos e quero continuar.</span></label>
    <div class="row">
      <button class="btn" id="mCancel">Cancelar</button>
      <button class="btn danger" id="mGo" disabled>Executar mesmo assim</button>
    </div>
  </div>
</div>

<div class="mask" id="profMask" role="dialog" aria-modal="true" aria-labelledby="profTitle">
  <div class="modal wide">
    <h3 id="profTitle">Perfil personalizado</h3>
    <p>Ligue só o que você quer. Ao aplicar, o pack parte de um estado limpo e liga apenas os recursos marcados.</p>

    <div class="cp-list" id="profList">
<?php foreach ($CPROF as $c): ?>
      <div class="cp-row" data-key="<?= htmlspecialchars($c['k'], ENT_QUOTES) ?>"<?= ($c['kind'] ?? 'seg') === 'toggle' ? ' data-kind="toggle"' : '' ?>>
        <div class="cp-info"><b><?= htmlspecialchars($c['t'], ENT_QUOTES) ?></b><span><?= htmlspecialchars($c['s'], ENT_QUOTES) ?></span></div>
<?php if (($c['kind'] ?? 'seg') === 'toggle'): ?>
        <button class="cpsw" type="button" role="switch" aria-checked="false" aria-label="<?= htmlspecialchars($c['t'], ENT_QUOTES) ?>"
                data-on="<?= htmlspecialchars($c['tgl']['on'], ENT_QUOTES) ?>" data-off="<?= htmlspecialchars($c['tgl']['off'], ENT_QUOTES) ?>"><i></i></button>
<?php else: ?>
        <div class="seg cp-seg">
<?php foreach ($c['opts'] as $i => $o): ?>
          <button class="seg-btn" type="button" data-val="<?= htmlspecialchars($o[0], ENT_QUOTES) ?>"<?= $i === 0 ? ' aria-pressed="true"' : ' aria-pressed="false"' ?>><?= htmlspecialchars($o[1], ENT_QUOTES) ?></button>
<?php endforeach; ?>
        </div>
<?php endif; ?>
      </div>
<?php endforeach; ?>
    </div>

    <div class="set-hint" id="profHint">Nada foi aplicado ainda — escolha os recursos e toque em Aplicar.</div>

    <div class="row">
      <button class="btn" id="profReset" type="button">Limpar escolhas</button>
      <button class="btn danger" id="profOff" type="button">Desligar perfil</button>
    </div>
    <div class="row" style="margin-top:8px">
      <button class="btn" id="profClose" type="button">Fechar</button>
      <button class="btn primary" id="profApply" type="button">Aplicar perfil</button>
    </div>
  </div>
</div>

<div class="mask" id="gearMask" role="dialog" aria-modal="true" aria-labelledby="gearTitle">
  <div class="modal wide">
    <h3 id="gearTitle">Configurações</h3>
    <p>Permissões, aparência e som. Fica tudo salvo neste aparelho.</p>

    <div class="set-group">
      <div class="set-label">Permissões e segundo plano</div>
      <div class="perms" id="permList">
        <div class="perm"><span class="ico" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M6 9a6 6 0 0 1 12 0c0 5 2 6 2 6H4s2-1 2-6"/><path d="M10 20a2 2 0 0 0 4 0"/></svg></span><div>
          <b>Notificações</b><span>Mostrar o aviso do pack e o andamento das ações.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true"><svg viewBox="0 0 24 24"><rect x="2" y="8" width="17" height="8" rx="2"/><path d="M22 11v2"/><path d="M5.5 11h6"/></svg></span><div>
          <b>Bateria sem restrição</b><span>Do próprio app do pack: sem isso o Android o adormece e as otimizações param sozinhas. É o diálogo do sistema.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M17 2 7 13h6l-1 9 10-11h-6l1-9Z"/></svg></span><div>
          <b>Rodar em segundo plano</b><span>Mantém o pack ativo quando a tela apaga ou você troca de app.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M12 3 5 6v5c0 4.2 2.9 7.9 7 9 4.1-1.1 7-4.8 7-9V6l-7-3Z"/></svg></span><div>
          <b>Isento do Doze</b><span>Impede o sistema de congelar o pack e o jogo em modo de espera.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M5 12.5a10 10 0 0 1 14 0"/><path d="M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19.5" r="1.2" fill="currentColor" stroke="none"/></svg></span><div>
          <b>Acesso por Shizuku ou ADB</b><span>É o que dá poder de shell ao pack. Configure em Configs.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true"><svg viewBox="0 0 24 24"><path d="M4 19V5"/><path d="M4 19h16"/><rect x="7" y="12" width="3" height="7"/><rect x="12" y="8" width="3" height="11"/><rect x="17" y="10" width="3" height="9"/></svg></span><div>
          <b>Acesso a dados de uso</b><span>Mostra o app em primeiro plano e o tempo de uso real na Home.</span></div></div>
      </div>
      <div class="set-actions">
        <button class="btn primary" id="setPermApp" type="button">Conceder permissões ao pack</button>
      </div>
      <div class="set-hint" id="setPermHint">Precisa de Shizuku, ADB por Wi-Fi ou root. Dá para desfazer em "Reverter TUDO".</div>
    </div>

    <div class="set-group">
      <div class="set-label">Cor de destaque</div>
      <div class="swatches" id="setAccent">
        <button class="sw" data-accent="laranja" style="--sw:#ff6a2b" aria-label="Laranja" type="button"></button>
        <button class="sw" data-accent="azul" style="--sw:#2f7bff" aria-label="Azul" type="button"></button>
        <button class="sw" data-accent="verde" style="--sw:#17a673" aria-label="Verde" type="button"></button>
        <button class="sw" data-accent="roxo" style="--sw:#8b5cf6" aria-label="Roxo" type="button"></button>
        <button class="sw" data-accent="rosa" style="--sw:#ec4899" aria-label="Rosa" type="button"></button>
        <button class="sw" data-accent="vermelho" style="--sw:#e5484d" aria-label="Vermelho" type="button"></button>
        <button class="sw" data-accent="prata" style="--sw:#c7ccd6" aria-label="Prata" type="button"></button>
        <button class="sw" data-accent="dourado" style="--sw:#d4a017" aria-label="Dourado" type="button"></button>
        <button class="sw" data-accent="ciano" style="--sw:#06b6d4" aria-label="Ciano" type="button"></button>
        <button class="sw" data-accent="grafite" style="--sw:#6b7280" aria-label="Grafite" type="button"></button>
        <button class="sw" data-accent="ambar" style="--sw:#f59e0b" aria-label="Âmbar" type="button"></button>
      </div>
      <div class="custom-color">
        <label class="cc-label" for="setAccentCustom">Cor personalizada</label>
        <div class="cc-row">
          <input type="color" id="setAccentCustom" value="#c7ccd6" aria-label="Escolher uma cor personalizada">
          <input type="text" id="setAccentHex" class="cc-hex" maxlength="7" spellcheck="false"
                 inputmode="text" placeholder="#rrggbb" aria-label="Código da cor (hex)">
          <button class="btn" id="setAccentApply" type="button">Usar esta cor</button>
        </div>
        <div class="set-hint">Escolha no seletor ou digite um código <b>#rrggbb</b>. A cor fica salva neste aparelho.</div>
      </div>
    </div>

    <div class="set-group">
      <div class="set-label">Fonte</div>
      <div class="seg" id="setFont">
        <button class="seg-btn" data-font="sistema" type="button">Sistema</button>
        <button class="seg-btn" data-font="minecraft" type="button">Minecraft</button>
        <button class="seg-btn" data-font="pixel" type="button">Pixel 8-bit</button>
        <button class="seg-btn" data-font="monocraft" type="button">Monocraft</button>
        <button class="seg-btn" data-font="cartaz" type="button">Cartaz</button>
        <button class="seg-btn" data-font="condensada" type="button">Condensada</button>
        <button class="seg-btn" data-font="futurista" type="button">Futurista</button>
        <button class="seg-btn" data-font="quadrada" type="button">Quadrada</button>
        <button class="seg-btn" data-font="serifa" type="button">Serifa</button>
        <button class="seg-btn" data-font="manuscrita" type="button">Manuscrita</button>
        <button class="seg-btn" data-font="mono" type="button">Mono</button>
      </div>
      <div class="set-hint">Fontes empacotadas no app (funcionam sem internet). A "Sistema" usa a fonte do seu Android.</div>
    </div>

    <div class="set-group">
      <div class="set-label">Tamanho da interface (DPI)</div>
      <div class="slider"><span style="font-size:12px;color:var(--muted)">DPI</span>
        <input type="range" id="setScale" min="60" max="160" step="5" value="100">
        <span class="val" id="setScaleVal">100%</span></div>
      <div class="set-hint">Diminui ou aumenta tudo no painel (zoom do app, não do sistema). Pode ir até 60% para deixar bem compacto.</div>
    </div>

    <div class="set-group" id="setSoundGroup">
      <div class="set-label">Som</div>
      <label class="switch"><input type="checkbox" id="setSound"><span>Reproduzir sons ao executar</span></label>
      <div class="set-hint">Se o volume de mídia do aparelho estiver no mínimo, não dá para ouvir.</div>
    </div>

    <div class="row">
      <button class="btn" id="gearReset" type="button">Restaurar padrão</button>
      <button class="btn primary" id="gearDone" type="button">Pronto</button>
    </div>
    <div style="margin-top: 14px; text-align: center;">
      <a class="btn danger" href="index.php?sair=1" style="display:block; text-align:center; text-decoration:none; padding:10px; border-radius:var(--r-sm); font-weight:700;">Sair do painel</a>
    </div>
  </div>
</div>

<div class="toast" id="toast" role="status"></div>

<script>
const TOKEN = <?= json_encode($token) ?>;
const ACTIONS = <?= json_encode(array_column($actions, null, 'id'), JSON_UNESCAPED_UNICODE) ?>;
const RISKTXT = {careful:"AÇÃO DE CUIDADO", root:"AÇÃO COM ROOT"};
const $ = s => document.querySelector(s);
let pending = null;

/* toque de verdade: só vale o dedo PARADO e CURTO. No fim de um arrasto (scroll)
   o navegador emite um "click" sintético na posição onde o dedo soltou — era isso
   que disparava botões sem querer. O pointercancel chega assim que a página começa
   a rolar, então arrastar nunca conta como toque. */
function tapOnly(el, fn){
  if (!el) return;
  let sx = 0, sy = 0, st = 0, ok = false;
  el.addEventListener("pointerdown", e => { sx = e.clientX; sy = e.clientY; st = Date.now(); ok = true; }, {passive:true});
  el.addEventListener("pointermove", e => { if (ok && (Math.abs(e.clientX - sx) > 8 || Math.abs(e.clientY - sy) > 8)) ok = false; }, {passive:true});
  el.addEventListener("pointercancel", () => { ok = false; }, {passive:true});
  el.addEventListener("click", e => {
    if (!ok || Date.now() - st > 700){ e.preventDefault(); e.stopPropagation(); return; }
    ok = false; fn(e);
  });
}

/* tema + aparência (engrenagem) — o app é SÓ modo escuro: não há alternância */
const ACCENTS = {
  laranja:{accent:"#ff6a2b",ink:"#180d06",ring:"rgba(255,106,43,.35)"},
  azul:{accent:"#2f7bff",ink:"#04122e",ring:"rgba(47,123,255,.35)"},
  verde:{accent:"#17a673",ink:"#04160f",ring:"rgba(23,166,115,.35)"},
  roxo:{accent:"#8b5cf6",ink:"#120726",ring:"rgba(139,92,246,.35)"},
  rosa:{accent:"#ec4899",ink:"#2a0616",ring:"rgba(236,72,153,.35)"},
  vermelho:{accent:"#e5484d",ink:"#2a0506",ring:"rgba(229,72,77,.35)"},
  prata:{accent:"#c7ccd6",ink:"#14161a",ring:"rgba(199,204,214,.40)"},
  dourado:{accent:"#d4a017",ink:"#241a02",ring:"rgba(212,160,23,.35)"},
  ciano:{accent:"#06b6d4",ink:"#041e24",ring:"rgba(6,182,212,.35)"},
  grafite:{accent:"#6b7280",ink:"#0b0d10",ring:"rgba(107,114,128,.40)"},
  ambar:{accent:"#f59e0b",ink:"#231603",ring:"rgba(245,158,11,.35)"}
};
const FONTS = {
  sistema:'"Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif',
  minecraft:'"Monocraft","Press Start 2P",ui-monospace,monospace',
  pixel:'"Press Start 2P",ui-monospace,monospace',
  monocraft:'"Monocraft",ui-monospace,monospace',
  cartaz:'"Anton","Arial Narrow",system-ui,sans-serif',
  condensada:'"Bebas Neue","Arial Narrow",system-ui,sans-serif',
  futurista:'"Orbitron","Segoe UI",system-ui,sans-serif',
  quadrada:'"Russo One","Segoe UI",system-ui,sans-serif',
  serifa:'"Playfair Display",Georgia,"Times New Roman",serif',
  manuscrita:'"Caveat","Segoe Script",cursive',
  mono:'"JetBrains Mono",ui-monospace,Menlo,Consolas,monospace'
};
/* A cor personalizada é montada a partir do hex: a "tinta" (texto sobre a cor)
   vira branco ou preto conforme o brilho, e o anel de foco usa a mesma cor. */
function accentFromHex(hex){
  const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || "").trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  const r = (n >> 16) & 255, g = (n >> 8) & 255, b = n & 255;
  const lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255;
  const h = "#" + m[1].toLowerCase();
  return { accent: h, ink: lum > 0.6 ? "#14120f" : "#ffffff",
           ring: "rgba(" + r + "," + g + "," + b + ",.38)" };
}
function setAccentQuiet(name){
  const a = ACCENTS[name]; if (!a) return;
  const r = document.documentElement.style;
  r.setProperty("--accent", a.accent); r.setProperty("--accent-ink", a.ink); r.setProperty("--ring", a.ring);
}
/* Aplica a cor personalizada e guarda o valor no localStorage. */
function setCustomAccent(hex){
  const a = accentFromHex(hex);
  if (!a) return false;
  const r = document.documentElement.style;
  r.setProperty("--accent", a.accent); r.setProperty("--accent-ink", a.ink); r.setProperty("--ring", a.ring);
  localStorage.setItem("otm-accent", "custom");
  localStorage.setItem("otm-accent-hex", a.accent);
  return true;
}
function applyStoredAccent(){
  const name = localStorage.getItem("otm-accent") || "prata";
  if (name === "custom"){
    const hex = localStorage.getItem("otm-accent-hex");
    if (hex && setCustomAccent(hex)) return;
  }
  setAccentQuiet(name);
}

/* Avisa o app da cor/fonte atuais: o painel flutuante roda num Service e nao
   enxerga o localStorage, entao ele le de SharedPreferences (bridge ui_prefs). */
function pushUiPrefs(){
  if (!window.OTM) return;
  const r = getComputedStyle(document.documentElement);
  const accent = (r.getPropertyValue("--accent") || "").trim();
  const ink = (r.getPropertyValue("--accent-ink") || "").trim();
  const font = localStorage.getItem("otm-font") || "sistema";
  try { window.OTM.call("ui_prefs", JSON.stringify({accent: accent, ink: ink, font: font}), "ui"); } catch(e){}
}
/* DPI do app: zoom no <html>. A largura vira 100%/escala para o conteúdo não
   ultrapassar a tela quando o zoom AUMENTA (era o que causava o arrasto lateral).
   Abaixo de 100% o zoom já encolhe tudo, então a largura fica em 100% — forçar
   `100%/escala` ali deixava o conteúdo mais largo que a tela e trazia o arrasto
   lateral de volta. */
function setScaleQuiet(pct){
  const z = Math.min(1.6, Math.max(0.6, (pct || 100) / 100));
  const r = document.documentElement.style;
  if (z === 1){ r.removeProperty("zoom"); r.removeProperty("width"); }
  else {
    r.setProperty("zoom", String(z));
    r.setProperty("width", z > 1 ? "calc(100% / " + z + ")" : "100%");
  }
}
function setFontQuiet(name){
  document.documentElement.style.setProperty("--font", FONTS[name] || FONTS.sistema);
}
function syncGear(){
  const a = localStorage.getItem("otm-accent") || "prata";
  document.querySelectorAll("#setAccent .sw").forEach(b => b.setAttribute("aria-pressed", b.dataset.accent === a ? "true" : "false"));
  const cc = document.getElementById("setAccentCustom");
  const ch = document.getElementById("setAccentHex");
  const hex = localStorage.getItem("otm-accent-hex") || "#c7ccd6";
  if (cc) cc.value = hex;
  if (ch && a === "custom") ch.value = hex;
  const f = localStorage.getItem("otm-font") || "sistema";
  document.querySelectorAll("#setFont .seg-btn").forEach(b => b.setAttribute("aria-pressed", b.dataset.font === f ? "true" : "false"));
  const sc = parseInt(localStorage.getItem("otm-scale") || "100", 10);
  const scEl = document.getElementById("setScale"); if (scEl) scEl.value = sc;
  const scVal = document.getElementById("setScaleVal"); if (scVal) scVal.textContent = sc + "%";
  const s = document.getElementById("setSound"); if (s) s.checked = localStorage.getItem("otm-sound") !== "0";
  const sg = document.getElementById("setSoundGroup"); if (sg && !window.OTM) sg.style.display = "none";
  const pl = document.getElementById("setPermHint");
  if (pl && !window.OTM) pl.textContent = "No site (PC) não dá para mexer no aparelho — isso funciona no app do celular.";
}
function setAccent(name){ setAccentQuiet(name); localStorage.setItem("otm-accent", name); pushUiPrefs(); syncGear(); }
function setFont(name){ setFontQuiet(name); localStorage.setItem("otm-font", name); pushUiPrefs(); syncGear(); }
function setScale(pct){ setScaleQuiet(pct); localStorage.setItem("otm-scale", String(pct)); syncGear(); }
function setSound(on){
  localStorage.setItem("otm-sound", on ? "1" : "0");
  try { if (window.OTM) window.OTM.call("sound", on ? "test" : "off", "snd"); } catch(e){}
  syncGear();
}
/* Permissões/segundo plano: manda a ação de registro pelo mesmo caminho das
   outras (no app vira OTM.call; no site, o aviso de que é só no celular). */
function askPermission(id, label){
  if (!window.OTM){ toast("Permissões: use o app no celular.", "bad"); return; }
  openConsole(label, "concedendo…");
  fetch("api.php?do=run", { method:"POST",
    headers:{"Content-Type":"application/json","X-OTM-Token":TOKEN},
    body: JSON.stringify({id:id, params:{}, confirm:false}) })
    .then(r => r.json())
    .then(j => {
      const head = (j.ok ? "[ok] " : "[erro] ") + "[" + (j.code ?? "?") + "]";
      openConsole(label, head + "\n\n" + (j.out || j.error || ""));
      if (j.ok) toast("Feito: " + label, "ok"); else toast("Falhou: " + label, "bad");
    })
    .catch(e => { openConsole(label, "erro: " + e); toast("Erro", "bad"); });
}
(function initAppearance(){
  applyStoredAccent();
  const f = localStorage.getItem("otm-font"); if (f) setFontQuiet(f);
  const sc = localStorage.getItem("otm-scale"); if (sc) setScaleQuiet(parseInt(sc, 10));
  if (localStorage.getItem("otm-sound") === "0" && window.OTM)
    try { window.OTM.call("sound", "off", "init"); } catch(e){}
  pushUiPrefs();
})();
$("#btnGear").onclick = () => { syncGear(); $("#gearMask").classList.add("open"); };
$("#gearDone").onclick = () => $("#gearMask").classList.remove("open");
$("#gearMask").onclick = e => { if (e.target.id === "gearMask") $("#gearMask").classList.remove("open"); };
document.querySelectorAll("#setAccent .sw").forEach(b => b.onclick = () => setAccent(b.dataset.accent));
document.querySelectorAll("#setFont .seg-btn").forEach(b => b.onclick = () => setFont(b.dataset.font));
/* Cor personalizada: o seletor de cor preenche o campo hex; "Usar esta cor"
   aceita qualquer um dos dois. Valor inválido avisa e não muda nada. */
const ccPick = document.getElementById("setAccentCustom");
const ccHex = document.getElementById("setAccentHex");
const ccApply = document.getElementById("setAccentApply");
if (ccPick) ccPick.oninput = e => { if (ccHex) ccHex.value = e.target.value; };
function applyCustomAccent(){
  const v = (ccHex && ccHex.value) || (ccPick && ccPick.value) || "";
  if (!setCustomAccent(v)){ toast("Cor inválida: use #rrggbb", "bad"); return; }
  pushUiPrefs(); syncGear(); toast("Cor personalizada aplicada.", "ok");
}
if (ccApply) ccApply.onclick = applyCustomAccent;
if (ccHex) ccHex.onkeydown = e => { if (e.key === "Enter"){ e.preventDefault(); applyCustomAccent(); } };
document.getElementById("setScale").oninput = e => setScale(parseInt(e.target.value, 10));
document.getElementById("setSound").onchange = e => setSound(e.target.checked);
const PERM_ACTION = { setPermApp: "perm.app" };
const permBtn = (id, label) => { const b = document.getElementById(id); if (b) b.onclick = () => askPermission(PERM_ACTION[id], label); };
permBtn("setPermApp", "Permissões do app do pack");
/* Acesso a dados de uso: não é um script, é uma tela do sistema. No app vira
   OTM.call("usage"); no site, avisa que só funciona no celular. Fica no card da
   Home (o pedido de permissão do app do pack cobre o resto em Configs). */
function openUsageSettings(){
  if (!window.OTM){ toast("Acesso a dados de uso: use o app no celular.", "bad"); return; }
  toast("Abrindo a tela de acesso a dados de uso…", "ok");
  try { window.OTM.call("usage", "", "usage"); } catch(e){}
}
const gearReset = document.getElementById("gearReset");
if (gearReset) gearReset.onclick = () => {
  ["otm-accent","otm-accent-hex","otm-font","otm-scale"].forEach(k => localStorage.removeItem(k));
  setAccentQuiet("prata"); setFontQuiet("sistema"); setScaleQuiet(100);
  pushUiPrefs(); syncGear(); toast("Aparência restaurada ao padrão.", "ok");
};

/* navegação */
function go(g, push){
  if (!g) g = "Painel";
  const secs = document.querySelectorAll("section[data-g]");
  let ok = false;
  secs.forEach(s => { const on = s.dataset.g === g; s.hidden = !on; if (on) ok = true; });
  if (!ok){ g = "Painel"; secs.forEach(s => s.hidden = s.dataset.g !== "Painel"); }
  document.querySelectorAll("#nav a").forEach(a => a.setAttribute("aria-current", a.dataset.g === g ? "true" : "false"));
  document.body.classList.remove("drawer");
  $("#burger").setAttribute("aria-expanded", "false");
  if (push !== false) history.replaceState(null, "", "#" + encodeURIComponent(g));
  window.scrollTo({top:0, behavior:"instant"});
  if (g === "Painel") startStats(); else stopStats();
}
document.querySelectorAll("#nav a").forEach(a => a.onclick = e => { e.preventDefault(); go(a.dataset.g); });
const fromHash = () => { const g = decodeURIComponent(location.hash.slice(1)); go(g || "Painel", false); };

/* gaveta */
$("#burger").onclick = () => { document.body.classList.add("drawer"); $("#burger").setAttribute("aria-expanded","true"); };
$("#scrim").onclick = $("#sideClose").onclick = () => { document.body.classList.remove("drawer"); $("#burger").setAttribute("aria-expanded","false"); };

/* ajuda */
function showHelp(id){
  const a = ACTIONS[id]; if (!a) return;
  $("#mTitle").textContent = a.label;
  $("#mDesc").textContent = a.desc || "";
  const long = $("#mLong");
  long.textContent = a.help || "Sem explicação adicional.";
  long.hidden = false;
  $("#mAck").hidden = true;
  $("#mGo").hidden = true;
  $("#mCancel").textContent = "Entendi";
  pending = null;
  $("#mask").classList.add("open");
}
document.querySelectorAll(".help-btn").forEach(b => b.onclick = () => showHelp(b.dataset.help));

/* executar */
const collect = card => {
  const out = {};
  const a = ACTIONS[card.dataset.id];
  (a.params || []).forEach(p => {
    const i = card.querySelector('[data-p="' + p.name + '"]');
    out[p.name] = i ? i.value.trim() : (p.default ?? "");
  });
  return out;
};
/* abre o modal de confirmação para a ação `a` e guarda `node` como pendente,
   para o runPending saber o que reexecutar depois do "ok". */
function askConfirm(node, a){
  pending = node;
  $("#mTitle").textContent = a.label;
  $("#mDesc").textContent = a.desc || "";
  const long = $("#mLong");
  if (a.help){ long.textContent = a.help; long.hidden = false; } else { long.hidden = true; }
  $("#mAck").hidden = false;
  $("#mGo").hidden = false;
  $("#mCancel").textContent = "Cancelar";
  $("#mAckLabel").textContent = a.risk === "root"
    ? "Estou ciente: mexe no kernel/sistema, pode esquentar ou instabilizar. Quero continuar."
    : "Estou ciente dos riscos e quero continuar.";
  $("#mCheck").checked = false; $("#mGo").disabled = true;
  $("#mask").classList.add("open");
}
function run(card, confirmed){
  const a = ACTIONS[card.dataset.id];
  if (a.confirm && !confirmed){ askConfirm(card, a); return; }
  doRun(a, collect(card), confirmed, card.querySelector("[data-run]"));
}
/* opção de um grupo de escolha (renderizador, driver por app, DNS, toque) */
function collectChoice(card){
  const out = {};
  if (card) card.querySelectorAll("[data-p]").forEach(i => { out[i.dataset.p] = i.value.trim(); });
  return out;
}
function selectOption(btn, confirmed){
  const a = ACTIONS[btn.dataset.opt];
  if (!a) return;
  const card = btn.closest(".card-choice");
  const params = collectChoice(card);
  // grupos que pedem o app: não dá para escolher sem o pacote
  if (card && card.querySelector('[data-p="pkg"]') && !params.pkg){
    toast("Escolha o app primeiro", "bad"); return;
  }
  if (a.confirm && !confirmed){ askConfirm(btn, a); return; }
  doRun(a, params, confirmed, btn);
}
/* reexecuta o que está pendente (cartão comum, opção ou botão de vitalidade)
   depois do "ok" */
function runPending(){
  const p = pending; if (!p) return;
  if (p.dataset.vitalGo) doRun(ACTIONS[p.dataset.vitalId], {}, true, p);
  else if (p._subId) doRun(ACTIONS[p._subId], p._subParams || {}, true, p);
  else if (p.classList.contains("opt")) doRun(ACTIONS[p.dataset.opt], collectChoice(p.closest(".card-choice")), true, p);
  else doRun(ACTIONS[p.dataset.id], collect(p), true, p.querySelector("[data-run]"));
}
async function doRun(a, params, confirmed, btn){
  if (a.id === "appearance"){ syncGear(); $("#gearMask").classList.add("open"); return; }
  if (a.id === "profile.custom"){ openCustomProfile(); return; }
  if (a.id === "profile.custom.apply"){ return applyCustomProfile(a, btn); }
  if (a.ui === "overlay"){ toast("Painel flutuante: use o app no celular (fica sobre o jogo).", "bad"); return; }
  setBusy(true, btn);
  openConsole(a.label, "executando…");
  try{
    const r = await fetch("api.php?do=run", {
      method:"POST",
      headers:{"Content-Type":"application/json","X-OTM-Token":TOKEN},
      body: JSON.stringify({id:a.id, params, confirm:!!confirmed})
    });
    const j = await r.json();
    let head = (j.ok ? "[ok] " : "[erro] ") + "[" + (j.code ?? "?") + "]";
    if (j.applied && !j.real) head += "  — nenhuma mudança real no sistema";
    else if (j.changed > 0) head += "  — " + j.changed + " mudança(s) confirmada(s)";
    openConsole(a.label, head + "\n\n" + (j.out || j.error || ""));
    if (j.ok) toast("Feito: " + a.label, "ok");
    else if (j.applied && !j.real) toast("Nada mudou de verdade — veja Configs", "bad");
    else toast("Falhou: " + a.label, "bad");
    if (j.ok && btn && btn.classList.contains("opt")) loadState();
  }catch(e){ openConsole(a.label, "erro: " + e); toast("Erro de rede", "bad"); }
  setBusy(false, btn);
}
document.querySelectorAll("[data-run]").forEach(b => tapOnly(b, () => run(b.closest(".card"))));
/* só opções de grupo de escolha: um .opt fora de .card-choice tem handler próprio */
document.querySelectorAll(".card-choice .opt").forEach(b => tapOnly(b, () => selectOption(b)));

/* ---- Perfil de Desempenho (turbo.sh perfmode) ------------------------------ */
function applyPerfmode(){
  const card = document.querySelector("[data-perfmode-card]"); if (!card) return;
  const v = String((STATE && STATE.fixed_perf) || "").toLowerCase();
  const on = v === "on", known = v !== "";
  card.querySelectorAll("[data-perfmode]").forEach(b => {
    const active = known && (b.dataset.perfmode === "on") === on;
    b.setAttribute("aria-pressed", active ? "true" : "false");
    const s = b.querySelector(".opt-s");
    if (s) s.textContent = active ? "Em uso" : (s.dataset.label || "Selecionar");
  });
  const now = card.querySelector("[data-now]");
  if (now){
    const txt = !known ? "" : (on ? "Em uso agora: desempenho fixo (mais FPS, esquenta mais)"
                                  : "Em uso agora: equilibrado (o sistema decide)");
    now.textContent = txt; now.hidden = !txt;
  }
}
document.querySelectorAll("[data-perfmode]").forEach(b => tapOnly(b, () => {
  const a = ACTIONS[b.dataset.perfmode === "on" ? "turbo.perfmode_on" : "turbo.perfmode_off"];
  if (!a){ toast("Ação indisponível", "bad"); return; }
  Promise.resolve(doRun(a, {}, false, b)).then(applyPerfmode);
}));

/* ---- vitalidade: cockpit de longevidade ------------------------------------
   O motor (scripts/vitality.sh) mede; aqui só desenhamos o que ele diz. O `tick`
   vem no poll de métricas (4 s), então a nota e os contadores são de verdade.
   Sem leitura de bateria o card diz "sem leitura" - nunca inventa número.      */
function vitalEl(sel){ const c = document.querySelector("[data-vital-card]"); return c && c.querySelector(sel); }
function renderVital(){
  const card = document.querySelector("[data-vital-card]"); if (!card) return;
  const S = (typeof STATS === "object" && STATS) || {};
  const num = v => { const n = parseFloat(v); return isFinite(n) ? n : null; };
  const score  = num(S.vital_score);
  const health = num(S.vital_health);
  const cycles = num(S.vital_cycles);
  const temp   = num(S.vital_temp);
  const w80    = num(S.vital_w80) ?? 0;
  const whot   = num(S.vital_whot) ?? 0;
  const care   = S.vital_care === "on";

  const set = (k, v) => { const e = vitalEl('[data-vital="' + k + '"]'); if (e) e.textContent = v; };

  const sEl = vitalEl('[data-vital="score"]');
  if (sEl) sEl.innerHTML = (score === null ? "—" : score) + "<span>/100</span>";

  const lbl = score === null ? "sem leitura"
            : score >= 90 ? "excelente" : score >= 75 ? "saudável"
            : score >= 60 ? "atenção"   : score >= 40 ? "desgastada" : "troque a bateria";
  const cls = score === null ? "off" : score >= 75 ? "good" : score >= 60 ? "warn" : "bad";
  const bEl = vitalEl('[data-vital="badge"]');
  if (bEl){ bEl.textContent = lbl; bEl.className = "vital-badge " + cls; }

  const fill = vitalEl('[data-vital="fill"]');
  const mark = vitalEl('[data-vital="mark"]');
  if (fill) fill.style.width = (score === null ? 0 : Math.max(0, Math.min(100, score))) + "%";
  if (mark) mark.style.left = "75%";   // abaixo daqui a bateria já pede atenção

  set("health", health === null ? "—" : health + "%");
  set("cycles", cycles === null ? "—" : cycles);
  set("temp",   temp === null ? "—" : temp + "°C");
  set("w80",    w80);

  const now = vitalEl('[data-vital="now"]');
  if (now){
    let t = "";
    if (health === null) t = "Este aparelho não expõe a saúde da bateria sem root. O resto continua funcionando: ciclos, temperatura e o guardião de carga.";
    else if (score >= 75) t = "Bateria saudável. Mantenha o modo longevidade ligado e evite carregar acima de 80% para segurar esse número por mais tempo.";
    else if (score >= 60) t = "Começando a desgastar. Vale ligar o modo longevidade e evitar cargas longas durante a noite.";
    else t = "Bateria desgastada. Evite calor na tomada e cargas acima de 80%; considere avaliar a troca da célula.";
    if (care) t += " Modo longevidade ligado.";
    if (whot > 0) t += " " + whot + " carga(s) com calor contabilizada(s).";
    now.textContent = t; now.hidden = false;
  }
}
document.querySelectorAll("[data-vital-go]").forEach(b => tapOnly(b, async () => {
  const go = b.dataset.vitalGo;
  const id = go === "optimize" ? "vital.optimize" : go === "care_on" ? "vital.care_on"
           : go === "care_off" ? "vital.care_off"
           : go === "diag" ? "vital.diag" : "vital.guard";
  const a = ACTIONS[id]; if (!a){ toast("Ação indisponível", "bad"); return; }
  if (a.confirm){ b.dataset.vitalId = id; askConfirm(b, a); return; }
  await doRun(a, {}, false, b);
  loadStats();
}));

/* ---- estado real do aparelho (renderizador em uso, toque, refresh) ---------- */
let STATE = {};
const TOUCH_KEYS = ["touch_responsiveness","long_press_timeout","pointer_speed","touch_slop"];
function stateNum(v){ const n = parseFloat(v); return (v === undefined || v === null || v === "" || isNaN(n)) ? null : n; }
function applyState(){
  document.querySelectorAll(".card-choice").forEach(card => {
    const key = card.dataset.stateKey || "";
    const bkey = card.dataset.stateBackend || "";
    const isTouch = card.dataset.choice === "touchprofile";
    // backends "multithread" declarados neste card. Uma opção SEM backend
    // (ex.: "SkiaGL") não pode ficar "Em uso" quando o backend real é um dos
    // multithread — senão "SkiaGL" e "SkiaGL multithread" acendiam juntas.
    const mtBackends = Array.from(card.querySelectorAll(".opt[data-state-backend-value]"))
      .map(o => String(o.dataset.stateBackendValue).toLowerCase());
    const curBackend = String(STATE[bkey] || "").toLowerCase();
    let active = null;
    card.querySelectorAll(".opt").forEach(o => {
      let on = false;
      if (o.dataset.stateAuto && key && STATE[key] !== undefined){
        // "Automático": em uso quando NADA foi gravado (o sistema decide).
        // Para o renderizador o prop cru é o que importa — se está vazio, é auto.
        const raw = (key === "renderer") ? String(STATE.renderer_prop || "") : String(STATE[key] || "");
        on = raw === "";
      } else if (o.dataset.stateValue && key && STATE[key] !== undefined && STATE[key] !== ""){
        on = String(STATE[key]).toLowerCase() === o.dataset.stateValue.toLowerCase();
        // "multithread" compartilha o mesmo hwui.renderer; o backend desempata
        if (on && o.dataset.stateBackendValue){
          on = curBackend === String(o.dataset.stateBackendValue).toLowerCase();
        } else if (on && !o.dataset.stateBackendValue && mtBackends.length){
          on = !mtBackends.includes(curBackend);
        }
      } else if (o.dataset.stateMatch){
        const want = o.dataset.stateMatch.split(":")[1].split(",");
        on = TOUCH_KEYS.every((k,i) => stateNum(STATE[k]) !== null && String(stateNum(STATE[k])) === want[i]);
      }
      o.setAttribute("aria-pressed", on ? "true" : "false");
      const s = o.querySelector(".opt-s"); if (s) s.textContent = on ? "Em uso" : "Selecionar";
      if (on) active = o.dataset.optlabel;
    });
    const now = card.querySelector("[data-now]");
    if (!now) return;
    let txt = "";
    if (isTouch){
      const cur = TOUCH_KEYS.map(k => stateNum(STATE[k]));
      if (cur.some(v => v !== null))
        txt = "No aparelho: responsiveness " + (cur[0] ?? "?") + " · long press " + (cur[1] ?? "?") + " ms · pointer " + (cur[2] ?? "?") + " · slop " + (cur[3] ?? "?");
    } else if (key === "renderer" && STATE.renderer){
      txt = "Em uso agora: " + (active || STATE.renderer)
        + (STATE.renderengine_backend ? " (" + STATE.renderengine_backend + ")" : "")
        + (String(STATE.force_gpu) === "1" ? " · GPU forçada" : "");
      const aa = String(STATE.angle_all || ""), gda = String(STATE.game_driver_all || "");
      const ud = String(STATE.updatable_driver || "");
      const extras = [];
      if (aa === "1") extras.push("ANGLE em todos os apps");
      if (gda === "1") extras.push("driver de jogo ligado");
      if (ud === "1") extras.push("driver pré-lançamento");
      else if (ud === "2") extras.push("driver pré-lançamento só no jogo");
      if (extras.length) txt += " · " + extras.join(" · ");
    } else if (key === "sysbars" && STATE.sysbars){
      const icons = String(STATE.sysbars_icons || "");
      const bat = String(STATE.sysbars_battery || "");
      txt = "No aparelho: " + (active || STATE.sysbars)
        + (icons ? " · ícones escondidos: " + icons : "")
        + (bat === "1" ? " · bateria em %" : "");
    } else if (key === "dns_host" && STATE.dns_host){
      txt = "Em uso agora: " + (active || STATE.dns_host);
    } else if (key === "blur" && STATE.blur){
      const b = STATE.blur === "on", t = STATE.reduce_transparency === "on";
      txt = b && t ? "No aparelho: desfoque e transparência ligados"
          : (!b && !t) ? "No aparelho: desfoque e transparência desligados (interface mais leve)"
          : "No aparelho: desfoque " + (b ? "ligado" : "desligado")
            + " · transparência " + (t ? "ligada" : "desligada");
    } else if (key === "proc_limit" && STATE.proc_limit){
      txt = "No aparelho: " + STATE.proc_limit
        + (String(STATE.proc_limit) === "padrão" ? " (o sistema decide)" : " apps em segundo plano");
    } else if (key === "refresh_peak"){
      const rp = stateNum(STATE.refresh_peak), rc = stateNum(STATE.refresh_hz);
      if (rp !== null) txt = "Em uso agora: taxa travada em " + rp + "Hz";
      else if (rc !== null) txt = "Em uso agora: " + rc + "Hz (o sistema decide)";
    }
    now.textContent = txt;
    now.hidden = !txt;
  });
  // sliders: parte do valor REAL do aparelho quando existe
  document.querySelectorAll('.card .slider input[type="range"][data-state]').forEach(range => {
    const v = stateNum(STATE[range.dataset.state]);
    if (v !== null) setSliderValue(range, v);
  });
}
function setSliderValue(range, val){
  const sl = range.closest(".slider"); if (!sl) return;
  range.value = val;
  const num = sl.querySelector("[data-pnum]"); if (num) num.value = val;
  const card = range.closest(".card");
  const fv = card && card.querySelector('.field-val[data-for="' + range.dataset.p + '"]');
  if (fv) fv.textContent = val;
}
document.querySelectorAll(".slider").forEach(sl => {
  const range = sl.querySelector('input[type="range"]');
  const num = sl.querySelector("[data-pnum]");
  if (!range) return;
  range.addEventListener("input", () => setSliderValue(range, range.value));
  if (num) num.addEventListener("input", () => { if (num.value !== "") setSliderValue(range, num.value); });
});
async function loadState(){
  try{ const j = await apiGet("state"); STATE = (j && j.state) || {}; }catch(e){ STATE = {}; }
  applyState();
  applyPerfmode();
}
const setBusy = (b, btn) => {
  document.querySelectorAll("[data-run]").forEach(x => x.disabled = b);
  if (btn) btn.classList.toggle("busy", b);
};

function openConsole(t, out){ $("#consoleTitle").textContent = t; $("#consoleOut").textContent = out; $("#console").classList.add("open"); }
function toast(m, k){ const t = $("#toast"); t.textContent = m; t.className = "toast show " + (k || "");
  clearTimeout(t._h); t._h = setTimeout(() => t.className = "toast", 3200); }
const apiGet = async a => (await fetch("api.php?action=" + a, {headers:{"X-OTM-Token":TOKEN}})).json();

$("#consoleClose").onclick = () => $("#console").classList.remove("open");
$("#mCancel").onclick = () => { $("#mask").classList.remove("open"); pending = null; };
$("#mCheck").onchange = e => $("#mGo").disabled = !e.target.checked;
$("#mGo").onclick = () => { $("#mask").classList.remove("open");
  runPending(); pending = null; };
$("#mask").onclick = e => { if (e.target.id === "mask"){ $("#mask").classList.remove("open"); pending = null; } };
const btnStatus = $("#btnStatus");
if (btnStatus) btnStatus.onclick = async () => { openConsole("Status do aparelho", "lendo…");
  const j = await apiGet("status"); openConsole("Status do aparelho", j.text || "(sem saída)"); };

/* ---- LOGS: histórico completo (sem truncar) -------------------------------- */
function esc(s){ return String(s).replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c])); }
/* Cada linha guarda o que o script tentou (applies/changed/failed), as razões
   da falha e a saída crua. O resumo fica à vista; o resto abre no toque. */
function renderLogs(list){
  const body = document.getElementById("logsBody"); if (!body) return;
  if (!list || !list.length){ body.innerHTML = '<div class="logs-empty">(nada registrado ainda)</div>'; return; }
  body.innerHTML = list.map((x, i) => {
    const st = x.ok ? '<span class="st ok">[ok]</span>' : '<span class="st no">[erro]</span>';
    const ts = x.ts ? String(x.ts).replace("T"," ").replace(/\..*$/,"") : "";
    const cmd = x.cmd ? '<span class="cmd">$ ' + esc(x.cmd) + '</span>' : '';
    const reasons = Array.isArray(x.reasons) ? x.reasons : [];
    const counts = [];
    if (x.applies != null) counts.push(x.applies + " tentativa(s)");
    if (x.changed != null) counts.push(x.changed + " aplicada(s)");
    if (x.failed != null && x.failed > 0) counts.push(x.failed + " falha(s)");
    if (x.code != null && x.code !== 0) counts.push("código " + x.code);
    const why = reasons.length
      ? '<ul class="why">' + reasons.map(r => '<li>' + esc(r) + '</li>').join("") + '</ul>' : '';
    const out = x.out ? '<pre>' + esc(x.out) + '</pre>' : '';
    const hasDet = !!(why || out || counts.length);
    const det = hasDet
      ? '<div class="det" hidden>' + why
        + (counts.length ? '<div class="counts">' + esc(counts.join(" · ")) + '</div>' : '')
        + out + '</div>'
      : '';
    return '<div class="logsrow' + (hasDet ? ' has-det' : '') + '" data-i="' + i + '">'
      + st + '<span class="ts">' + esc(ts) + '</span>'
      + '<span class="lb">' + esc(x.label || x.id || "?") + cmd + det + '</span>'
      + (hasDet ? '<span class="chev">▾</span>' : '') + '</div>';
  }).join("");
  body.querySelectorAll(".logsrow.has-det").forEach(row => {
    row.onclick = () => {
      const d = row.querySelector(".det"); if (!d) return;
      d.hidden = !d.hidden;
      const c = row.querySelector(".chev"); if (c) c.textContent = d.hidden ? "▾" : "▴";
    };
  });
}
async function openLogs(){
  const p = document.getElementById("logspanel"); if (!p) return;
  p.classList.add("open");
  const body = document.getElementById("logsBody");
  if (body) body.innerHTML = "lendo…";
  try{ const j = await apiGet("log_all"); renderLogs(j.log || []); }
  catch(e){ if (body) body.innerHTML = '<div class="logs-empty">erro: ' + esc(e) + '</div>'; }
}
const btnLogs = document.getElementById("btnLogs"); if (btnLogs) btnLogs.onclick = openLogs;
const logsClose = document.getElementById("logsClose"); if (logsClose) logsClose.onclick = () => document.getElementById("logspanel").classList.remove("open");
const logsRefresh = document.getElementById("logsRefresh"); if (logsRefresh) logsRefresh.onclick = openLogs;

/* ---- TERMINAL: executa comandos de verdade --------------------------------- */
let termHist = [], termIdx = -1, termText = "";
function termPaint(t){ const o = document.getElementById("termOut"); if (o) o.textContent = t; }
async function termRunCmd(cmd){
  cmd = (cmd || "").trim(); if (!cmd) return;
  termHist.push(cmd); termIdx = termHist.length;
  const o = document.getElementById("termOut");
  if (o){ o.textContent += (o.textContent ? "\n" : "") + "$ " + cmd + "\n"; o.scrollTop = o.scrollHeight; }
  const inp = document.getElementById("termInput"); if (inp) inp.disabled = true;
  try{
    const r = await fetch("api.php?do=term", {
      method:"POST", headers:{"Content-Type":"application/json","X-OTM-Token":TOKEN},
      body: JSON.stringify({cmd})
    });
    const j = await r.json();
    if (o){ o.textContent += (j.out || "(sem saída)") + "\n"; o.scrollTop = o.scrollHeight; }
  }catch(e){ if (o){ o.textContent += "erro: " + e + "\n"; } }
  if (inp){ inp.disabled = false; inp.focus(); }
}
(function initTerm(){
  const inp = document.getElementById("termInput");
  const run = document.getElementById("termRun");
  if (!inp || !run) return;
  run.onclick = () => { const c = inp.value; inp.value = ""; termRunCmd(c); };
  inp.addEventListener("keydown", e => {
    if (e.key === "Enter"){ e.preventDefault(); const c = inp.value; inp.value = ""; termRunCmd(c); return; }
    if (e.key === "ArrowUp"){
      if (!termHist.length) return; e.preventDefault();
      if (termIdx === termHist.length) termText = inp.value;
      termIdx = Math.max(0, termIdx - 1); inp.value = termHist[termIdx];
    }
    if (e.key === "ArrowDown"){
      if (!termHist.length) return; e.preventDefault();
      termIdx = Math.min(termHist.length, termIdx + 1);
      inp.value = termIdx === termHist.length ? termText : termHist[termIdx];
    }
  });
  const clr = document.getElementById("termClear"); if (clr) clr.onclick = () => termPaint("");
  // histórico salvo no aparelho (app) — no site fica vazio
  apiGet("term_hist").then(j => { (j.history || []).forEach(h => { if (h.cmd) termHist.push(h.cmd); }); termIdx = termHist.length; }).catch(()=>{});
})();
const btnTerm = document.getElementById("btnTerm");
if (btnTerm) btnTerm.onclick = () => { go("Terminal"); const i = document.getElementById("termInput"); if (i) i.focus(); };

/* ---- SELETOR DE APPS (nome + ícone), sem digitar pacote -------------------- */
let APPS = [];           // [{pkg,label,icon}]
let appsLoading = false;
let appTarget = null;    // input [data-p="pkg"] que recebe o pacote escolhido
function appInitial(label, pkg){
  const s = (label || pkg || "?").trim();
  return esc(s.charAt(0).toUpperCase() || "?");
}
function appRowHtml(a){
  const nm = esc(a.label || a.pkg);
  const ico = a.icon ? '<img src="data:image/png;base64,' + a.icon + '" alt="" loading="lazy">'
                     : '<span class="noico">' + appInitial(a.label, a.pkg) + '</span>';
  return ico + '<span class="nm"><b>' + nm + '</b>'
       + (a.label ? '<small>' + esc(a.pkg) + '</small>' : '') + '</span>';
}
function renderAppList(filter){
  const ul = document.getElementById("appList"); if (!ul) return;
  const f = (filter || "").trim().toLowerCase();
  const list = !f ? APPS : APPS.filter(a =>
    (a.label || "").toLowerCase().includes(f) || (a.pkg || "").toLowerCase().includes(f));
  if (!list.length){ ul.innerHTML = '<li class="logs-empty">nenhum app encontrado</li>'; return; }
  ul.innerHTML = list.slice(0, 400).map((a, i) =>
    '<li class="appitem" role="button" tabindex="0" data-i="' + APPS.indexOf(a) + '">' + appRowHtml(a) + '</li>').join("");
  ul.querySelectorAll(".appitem").forEach(li => {
    const pick = () => {
      const a = APPS[parseInt(li.dataset.i, 10)];
      if (!a || !appTarget) return;
      appTarget.value = a.pkg;
      const btn = appTarget.closest(".apppick");
      if (btn) paintAppPick(btn, a);
      closeAppPicker();
    };
    li.onclick = pick;
    li.onkeydown = e => { if (e.key === "Enter" || e.key === " "){ e.preventDefault(); pick(); } };
  });
}
function paintAppPick(btn, a){
  const inp = btn.querySelector('input[data-p="pkg"]'); if (inp && a) inp.value = a.pkg;
  const slot = btn.querySelector(".appslot"); if (!slot) return;
  if (a) slot.innerHTML = appRowHtml(a);
  else {
    const cur = inp ? inp.value.trim() : "";
    slot.innerHTML = '<span class="noico">?</span><span class="nm"><b>' +
      (cur ? esc(cur) : "Nenhum app escolhido") + '</b><small>toque para escolher</small></span>';
  }
}
async function loadApps(){
  if (appsLoading || APPS.length) return;
  appsLoading = true;
  try{
    const j = await apiGet("apps_meta");
    APPS = (j.apps || []).filter(a => a && a.pkg).map(a => ({pkg:a.pkg, label:a.label || "", icon:a.icon || ""}));
  }catch(e){ APPS = []; }
  if (!APPS.length){
    try{ const j = await apiGet("apps"); APPS = (j.apps || []).map(p => ({pkg:p, label:"", icon:""})); }catch(e){}
  }
  appsLoading = false;
}
function openAppPicker(btn){
  appTarget = btn.querySelector('input[data-p="pkg"]');
  const m = document.getElementById("appModal"); if (!m) return;
  m.classList.add("open");
  const s = document.getElementById("appSearch"); if (s) s.value = "";
  const ul = document.getElementById("appList"); if (ul) ul.innerHTML = "carregando…";
  loadApps().then(() => {
    if (appTarget && appTarget.value){
      const cur = APPS.find(a => a.pkg === appTarget.value);
      if (cur) paintAppPick(btn, cur);
    }
    renderAppList("");
    if (s) s.focus();
  });
}
function closeAppPicker(){ const m = document.getElementById("appModal"); if (m) m.classList.remove("open"); }
(function initAppPicker(){
  const s = document.getElementById("appSearch");
  if (s) s.addEventListener("input", () => renderAppList(s.value));
  const c = document.getElementById("appModalClose"); if (c) c.onclick = closeAppPicker;
  const m = document.getElementById("appModal"); if (m) m.onclick = e => { if (e.target.id === "appModal") closeAppPicker(); };
  document.querySelectorAll("[data-apppick]").forEach(btn => {
    btn.onclick = () => openAppPicker(btn);
    btn.onkeydown = e => { if (e.key === "Enter" || e.key === " "){ e.preventDefault(); openAppPicker(btn); } };
  });
})();

/* ---- HOME: métricas reais do aparelho (RAM, CPU, bateria, tela) ------------- */
let STATS = {}, statsTimer = null, statsBusy = false, statsAt = 0;
const STAT_KEYS = ["ram_total_mb","ram_livre_mb","ram_uso_pct","cpu_uso_pct","load1","ncores","cpu_gov","cpu_cur_mhz","cpu_max_mhz","bat_level","bat_temp_c","bat_status","refresh_hz","fps","stor_total_mb","stor_livre_mb","uptime_s","fg_label","screen_time"];
const has = v => v !== undefined && v !== null && String(v) !== "";
const num = v => { const n = parseFloat(v); return (v === "" || v === null || v === undefined || isNaN(n)) ? null : n; };
function setBar(m, pct, cls){ const i = m && m.querySelector("i"); if (i) i.style.width = Math.max(0, Math.min(100, pct)) + "%"; if (m){ m.className = "m" + (cls ? " " + cls : ""); } }
function fmtUp(s){ s = Math.round(s); const d = Math.floor(s/86400), h = Math.floor(s%86400/3600), m = Math.floor(s%3600/60);
  return (d?d+"d ":"") + h + "h " + m + "min"; }
function fmtGB(mb){ const g = mb/1024; return (g >= 10 ? g.toFixed(0) : g.toFixed(1)) + " GB"; }
function renderStats(){
  const S = STATS;
  // RAM
  const ramUse = num(S.ram_uso_pct), tot = num(S.ram_total_mb), free = num(S.ram_livre_mb);
  const ramV = document.querySelector('[data-stat="ram"]');
  if (ramV) ramV.innerHTML = ramUse === null ? "—" : ramUse + "<small>% em uso</small>";
  if (ramUse !== null) setBar(document.querySelector('[data-m="ram"]'), ramUse, ramUse >= 90 ? "b" : ramUse >= 75 ? "w" : "g");
  else setBar(document.querySelector('[data-m="ram"]'), 0, "");
  // "ramf" existe em dois lugares (chip do hero e rodapé do card); querySelector
  // só pegava o primeiro e o rodapé ficava travado em "—". Preenche os dois.
  const ramTxt = (free !== null && tot !== null)
    ? fmtGB(free) + " livres de " + fmtGB(tot)
    : (tot !== null ? "total " + fmtGB(tot) : "o aparelho não informou");
  document.querySelectorAll('[data-stat="ramf"]').forEach(el => { el.textContent = ramTxt; });
  // CPU (uso real medido pelo script; a carga média vai no rodapé, não como %)
  const cpuUse = num(S.cpu_uso_pct), load = num(S.load1), nc = num(S.ncores);
  const cpuV = document.querySelector('[data-stat="cpu"]');
  if (cpuV) cpuV.innerHTML = cpuUse === null ? "—" : cpuUse + "<small>%</small>";
  setBar(document.querySelector('[data-m="cpu"]'), cpuUse === null ? 0 : cpuUse, cpuUse === null ? "" : cpuUse >= 90 ? "b" : cpuUse >= 70 ? "w" : "g");
  const cpuF = document.querySelector('[data-stat="cpuf"]');
  if (cpuF){
    const parts = [];
    if (load !== null) parts.push("carga " + load.toFixed(2));
    if (nc) parts.push(nc + " núcleos");
    if (has(S.cpu_cur_mhz)) parts.push(S.cpu_cur_mhz + (has(S.cpu_max_mhz) ? "/" + S.cpu_max_mhz : "") + " MHz");
    else if (has(S.cpu_gov)) parts.push("gov " + S.cpu_gov);
    cpuF.textContent = parts.length ? parts.join(" · ") : "o aparelho não informou";
  }
  // Bateria
  const bl = num(S.bat_level), bt = num(S.bat_temp_c);
  const batV = document.querySelector('[data-stat="bat"]');
  if (batV) batV.innerHTML = bl === null ? "—" : bl + "<small>%</small>";
  setBar(document.querySelector('[data-m="bat"]'), bl === null ? 0 : bl, bl === null ? "" : (bl <= 15 ? "b" : bl <= 35 ? "w" : "g"));
  const batF = document.querySelector('[data-stat="batf"]');
  if (batF){
    const p = [];
    if (has(S.bat_status)) p.push(S.bat_status);
    if (bt !== null) p.push(bt.toFixed(1) + "°C");
    batF.textContent = p.length ? p.join(" · ") : "o aparelho não informou";
  }
  // Armazenamento
  const st = num(S.stor_total_mb), sf = num(S.stor_livre_mb);
  const storV = document.querySelector('[data-stat="stor"]');
  const storPct = (st && sf !== null) ? Math.round((st - sf) / st * 100) : null;
  if (storV) storV.innerHTML = storPct === null ? "—" : storPct + "<small>% em uso</small>";
  setBar(document.querySelector('[data-m="stor"]'), storPct === null ? 0 : storPct, storPct >= 90 ? "b" : storPct >= 75 ? "w" : "g");
  const storF = document.querySelector('[data-stat="storf"]');
  if (storF) storF.textContent = (st && sf !== null) ? fmtGB(sf) + " livres de " + fmtGB(st) : "o aparelho não informou";
  // Taxa de tela (refresh): mostra a taxa travada se houver, senão a atual
  const dispV = document.querySelector('[data-stat="disp"]');
  const rPeak = num(S.refresh_peak);
  const rCur = num(S.refresh_hz);
  const rShow = rPeak !== null ? rPeak : rCur;
  if (dispV) dispV.innerHTML = rShow !== null ? rShow + "<small>Hz</small>" : "—";
  const dispF = document.querySelector('[data-stat="dispf"]');
  if (dispF) dispF.textContent = rPeak !== null ? "taxa travada (fixa)" : (rCur !== null ? "taxa atual da tela" : "o aparelho não informou");
  // FPS REAL do jogo: vem do SurfaceFlinger (frames apresentados de verdade),
  // não da taxa de tela. "—" quando o jogo não está na tela ou a camada não
  // expõe frames — melhor vazio do que um número inventado.
  const fpsV = document.querySelector('[data-stat="fps"]');
  const fpsN = num(S.fps);
  if (fpsV) fpsV.innerHTML = fpsN === null ? "—" : fpsN + "<small>fps</small>";
  const fpsF = document.querySelector('[data-stat="fpsf"]');
  if (fpsF){
    if (fpsN === null) fpsF.textContent = "abra o jogo para medir";
    else if (rCur !== null && fpsN >= rCur - 3) fpsF.textContent = "no teto da tela (" + rCur + " Hz)";
    else fpsF.textContent = "frames reais do jogo agora";
  }
  // Tempo ligado
  const upV = document.querySelector('[data-stat="up"]');
  const up = num(S.uptime_s);
  if (upV) upV.innerHTML = up === null ? "—" : fmtUp(up);
  const upF = document.querySelector('[data-stat="upf"]');
  if (upF) upF.textContent = up === null ? "o aparelho não informou" : "desde o último boot";
  // App em primeiro plano (precisa do Acesso a dados de uso)
  const fgV = document.querySelector('[data-stat="fg"]');
  if (fgV) fgV.textContent = has(S.fg_label) ? S.fg_label : "—";
  const fgF = document.querySelector('[data-stat="fgf"]');
  if (fgF) fgF.textContent = has(S.fg_label) ? (S.fg_pkg || "") : "libere o acesso a dados de uso";
  // Uso nas últimas 24 h (tempo total de tela)
  const usV = document.querySelector('[data-stat="usage"]');
  if (usV) usV.textContent = has(S.screen_time) ? S.screen_time : "—";
  const usF = document.querySelector('[data-stat="usagef"]');
  if (usF){
    const tops = Array.isArray(S.top_apps) ? S.top_apps : [];
    usF.textContent = tops.length
      ? "top: " + tops.slice(0,2).map(a => (a.label || a.pkg) + " " + (a.time || "")).join(" · ")
      : (has(S.screen_time) ? "tempo de tela nas últimas 24 h" : "libere o acesso a dados de uso");
  }
  // aviso de ausência de dados
  const anyData = STAT_KEYS.some(k => has(S[k]));
  const hint = document.getElementById("statsHint"); if (hint) hint.hidden = anyData;
  // "Uso do aparelho" só fica completo com o acesso a dados de uso
  const granted = S.usage_granted === true || has(S.fg_label) || has(S.screen_time);
  const uhint = document.getElementById("usageHint"); if (uhint) uhint.hidden = granted;
  const uneed = document.getElementById("usageNeed"); if (uneed) uneed.hidden = granted;
  const urow = document.getElementById("usagePermRow"); if (urow) urow.hidden = granted;
  const badge = document.getElementById("liveBadge"); if (badge) badge.hidden = !anyData;
  if (anyData && statsAt){
    const sec = Math.round((Date.now() - statsAt) / 1000);
    const lbl = sec < 5 ? "agora" : "há " + sec + " s";
    if (badge) badge.innerHTML = '<span class="dot"></span>ao vivo · ' + lbl;
  }
}
async function loadStats(){
  if (statsBusy) return; statsBusy = true;
  try{ const j = await apiGet("stats"); STATS = (j && j.stats) || {}; statsAt = Date.now(); }
  catch(e){ /* mantém o último valor real */ }
  statsBusy = false; renderStats(); renderVital();
}
function startStats(){
  loadStats();
  if (!statsTimer) statsTimer = setInterval(() => { if (!document.hidden) loadStats(); }, 4000);
}
function stopStats(){ if (statsTimer){ clearInterval(statsTimer); statsTimer = null; } }
const refreshBtn = document.getElementById("btnRefreshStats");
if (refreshBtn) refreshBtn.onclick = () => { loadStats(); toast("Métricas atualizadas", "ok"); };
const usagePermBtn = document.getElementById("btnUsagePerm");
if (usagePermBtn) usagePermBtn.onclick = openUsageSettings;
document.addEventListener("visibilitychange", () => { if (!document.hidden && !document.querySelector('section[data-g="Home"]').hidden) loadStats(); });

/* atalhos da Home */
function runActionById(id){
  const a = ACTIONS[id]; if (!a) return;
  const card = document.querySelector('.card[data-id="' + id + '"]');
  if (a.confirm){ pending = card || { dataset:{id:id}, querySelector:()=>null, classList:{contains:()=>false} }; run(card); }
  else doRun(a, {}, false, null);
}
/* modo gamer da tela inicial: abre o jogo ESCOLHIDO (não fixo no Free Fire) */
function runGameHome(btn){
  const a = ACTIONS["game_open"]; if (!a) return;
  const inp = btn.closest(".card")?.querySelector('input[data-p="pkg"]');
  const pkg = inp ? inp.value.trim() : "";
  if (!pkg){ toast("Escolha o jogo primeiro", "bad"); return; }
  doRun(a, { pkg }, false, btn);
}
document.querySelectorAll("[data-qa]").forEach(b => tapOnly(b, () => runActionById(b.dataset.qa)));
/* botões do hub do otimizador: rodam a sub-ação pelo id, como os atalhos da Home.
   O perfil escolhido no card é repassado às sub-ações que o aceitam. */
document.querySelectorAll("[data-hub]").forEach(b => tapOnly(b, () => {
  const a = ACTIONS[b.dataset.hub];
  if (!a) return;
  const card = b.closest(".card");
  const sel = card && card.querySelector('[data-p="perfil"]');
  // guarda a sub-ação e o perfil no próprio botão: o askConfirm põe o botão em
  // `pending`, e o runPending precisa saber o que reexecutar depois do "ok".
  b._subId = a.id; b._subParams = sel ? { perfil: sel.value } : {};
  if (a.confirm) askConfirm(b, a);
  else doRun(a, b._subParams, false, b);
}));

/* status do botão principal (Clean Phone) enquanto a limpeza roda */
const heroBtn = document.getElementById("rocketBtn");
const heroStatus = document.getElementById("heroStatus");
if (heroBtn && heroStatus){
  heroBtn.addEventListener("click", () => {
    heroStatus.textContent = "Otimizando…";
    const t = setInterval(() => {
      if (!heroBtn.classList.contains("busy")){ clearInterval(t); heroStatus.textContent = "Pronto para otimizar"; }
    }, 300);
  });
}

/* ---- Perfil personalizado: monta as escolhas e aplica numa ação só ---------- */
const CPROF = <?= json_encode($CPROF, JSON_UNESCAPED_UNICODE) ?>;
const CPROF_DEFAULT = <?= json_encode($CPROF_DEFAULT, JSON_UNESCAPED_UNICODE) ?>;
const CPROF_KEY = "otm-custom-profile";

function profRead(){
  try{ const j = JSON.parse(localStorage.getItem(CPROF_KEY) || "{}");
       return Object.assign({}, CPROF_DEFAULT, (j && typeof j === "object") ? j : {}); }
  catch(e){ return Object.assign({}, CPROF_DEFAULT); }
}
function profPaint(){
  const cur = profRead();
  CPROF.forEach(c => {
    const row = document.querySelector('.cp-row[data-key="' + c.k + '"]'); if (!row) return;
    row.querySelectorAll(".seg-btn").forEach(b => b.setAttribute("aria-pressed", b.dataset.val === cur[c.k] ? "true" : "false"));
    const sw = row.querySelector(".cpsw");
    if (sw) sw.setAttribute("aria-checked", cur[c.k] === sw.dataset.on ? "true" : "false");
  });
}
function profSet(k, v){
  const cur = profRead(); cur[k] = v;
  localStorage.setItem(CPROF_KEY, JSON.stringify(cur));
  profPaint();
}
// Lê o estado ligado/desligado da chave. O "on" varia por opção (on/ligados...),
// por isso o valor vem do próprio botão, não de um "true" fixo.
function profToggle(sw){ return sw.getAttribute("aria-checked") === "true"; }
function profActiveCount(){
  const cur = profRead();
  return CPROF.filter(c => cur[c.k] !== CPROF_DEFAULT[c.k]).length;
}
function openCustomProfile(){
  profPaint();
  const n = profActiveCount();
  const hint = document.getElementById("profHint");
  if (hint) hint.textContent = n === 0
    ? "Nada alterado do padrão — escolha os recursos e toque em Aplicar."
    : n + " recurso(s) diferente(s) do padrão. Toque em Aplicar para valer.";
  document.getElementById("profMask").classList.add("open");
}
async function applyCustomProfile(a, btn){
  const cur = profRead();
  const params = {};
  CPROF.forEach(c => { params[c.k] = cur[c.k]; });
  setBusy(true, btn);
  openConsole(a.label, "executando…");
  try{
    const r = await fetch("api.php?do=run", {
      method:"POST",
      headers:{"Content-Type":"application/json","X-OTM-Token":TOKEN},
      body: JSON.stringify({id:"profile.custom.apply", params, confirm:true})
    });
    const j = await r.json();
    let head = (j.ok ? "[ok] " : "[erro] ") + "[" + (j.code ?? "?") + "]";
    if (j.changed > 0) head += "  — " + j.changed + " mudança(s) confirmada(s)";
    openConsole(a.label, head + "\n\n" + (j.out || j.error || ""));
    if (j.ok) toast("Perfil personalizado aplicado", "ok"); else toast("Falhou ao aplicar o perfil", "bad");
    document.getElementById("profMask").classList.remove("open");
    loadState();
  }catch(e){
    openConsole(a.label, "erro: " + e);
    toast("Falhou ao aplicar o perfil", "bad");
  }finally{ setBusy(false, btn); }
}
document.querySelectorAll("#profList .cp-row").forEach(row => {
  row.querySelectorAll(".seg-btn").forEach(b => tapOnly(b, () => profSet(row.dataset.key, b.dataset.val)));
  const sw = row.querySelector(".cpsw");
  if (sw) tapOnly(sw, () => profSet(row.dataset.key, profToggle(sw) ? sw.dataset.off : sw.dataset.on));
});
tapOnly(document.getElementById("profApply"), () => applyCustomProfile(ACTIONS["profile.custom.apply"], document.getElementById("profApply")));
document.getElementById("profClose").onclick = () => document.getElementById("profMask").classList.remove("open");
document.getElementById("profReset").onclick = () => {
  localStorage.removeItem(CPROF_KEY); profPaint();
  const hint = document.getElementById("profHint"); if (hint) hint.textContent = "Escolhas limpas — tudo no padrão.";
};
document.getElementById("profOff").onclick = () => {
  const a = ACTIONS["profile.custom.off"];
  pending = { dataset:{id:"profile.custom.off"}, querySelector:()=>null, classList:{contains:()=>false} };
  run(pending);
};
profPaint();

(function buildJump(){
  const j = document.getElementById("jump"); if (!j) return;
  document.querySelectorAll("#nav a").forEach(a => {
    if (a.dataset.g === "Home") return;
    const b = document.createElement("button"); b.type = "button"; b.textContent = a.textContent.replace(/\s*\d+$/, "").trim();
    b.onclick = () => go(a.dataset.g);
    j.appendChild(b);
  });
})();

window.addEventListener("hashchange", fromHash);
addEventListener("keydown", e => { if (e.key === "Escape"){ $("#mask").classList.remove("open"); $("#gearMask").classList.remove("open"); $("#profMask").classList.remove("open"); document.body.classList.remove("drawer"); } });

/* apps instalados (autocomplete) + estado do modo de acesso */
(async () => {
  try{
    const m = await apiGet("mode");
    const names = {rish:"Shizuku", adb:"ADB Wi-Fi", su:"root", local:"local (sem acesso)"};
    const txt = names[m.mode] || m.mode || "auto";
    const modeTxt = $("#modeTxt");
    if (modeTxt) modeTxt.textContent = txt;
    const pill = $("#modePill");
    if (pill) pill.title = "Acesso: " + txt + (m.priv ? " — " + m.priv : "") + ". Configure em Configs.";
  }catch(e){ const mt = $("#modeTxt"); if (mt) mt.textContent = "offline"; }
  try{ const i = await apiGet("info");
    const t2 = $("#modeTxt");
    if (t2 && (!t2.textContent || t2.textContent === "verificando…"))
      t2.textContent = (i.have_adb ? "ADB ok" : "sem ADB") + " · PHP " + i.php;
  }catch(e){}
  // pré-carrega a lista de apps (nome + ícone) para o seletor abrir rápido
  loadApps();
  loadState();
})();

fromHash();
</script>
</body>
</html>
