<?php
declare(strict_types=1);
/**
 * 00deUdia Otimizações — painel de controle (PHP).
 *
 * A estrutura (menu de categorias e cards de ação) é renderizada aqui no servidor
 * a partir do registro em lib.php. O JavaScript só cuida de trocar de categoria,
 * executar via api.php, mostrar saída e a explicação de cada ação.
 */
require __DIR__ . '/lib.php';

$actions = array_values(otm_actions());

$groups = [];
foreach ($actions as $a) { $groups[$a['group']][] = $a; }

$meta = [
    'Rápido'            => ['t' => 'Rápido',            's' => 'Aplique o conjunto seguro, reverta tudo ou salve um snapshot.'],
    'DNS'               => ['t' => 'DNS privado',       's' => 'Perfis de DNS-over-TLS: privacidade, anúncios, família e latência.'],
    'RAM / Limpeza'     => ['t' => 'RAM e limpeza',     's' => 'Mais memória livre e limpeza de cache.'],
    'Renderizador'      => ['t' => 'Renderizador',      's' => 'Troque o motor gráfico: OpenGL, SkiaGL ou Skia Vulkan.'],
    'Por app / jogo'    => ['t' => 'Por app ou jogo',   's' => 'Escolha um app e mude renderizador, modo ou resolução.'],
    'Touch / Free Fire' => ['t' => 'Touch e Free Fire', 's' => 'Perfis de sensibilidade, mira e ajustes do jogo.'],
    'Performance'       => ['t' => 'Performance',       's' => 'Animações, tela, bateria e modo não perturbe.'],
    'Wi-Fi e rede'      => ['t' => 'Wi-Fi e rede',      's' => 'Varredura de Wi-Fi, buffers TCP e reset de rede.'],
    'Congelar apps'     => ['t' => 'Congelar apps',     's' => 'Congele apps em segundo plano para liberar RAM.'],
    'Debloat'           => ['t' => 'Debloat',           's' => 'Desativa bloatware por perfil ou por app. Tudo é reversível.'],
    'Profundas (root)'  => ['t' => 'Profundas (root)',  's' => 'Mexem em kernel e sistema. Só com root, use com cuidado.'],
    'Diagnóstico'       => ['t' => 'Diagnóstico',       's' => 'Detecta o aparelho, mede e mostra o estado atual. Só leitura.'],
    'Módulos'           => ['t' => 'Módulos',           's' => 'Complementos do pack (tweaks, touch, GPU, bateria).'],
];

$riskLabel = ['safe' => 'seguro', 'careful' => 'cuidado', 'root' => 'root'];

$token = is_file(__DIR__ . '/.token') ? trim((string) file_get_contents(__DIR__ . '/.token')) : '';
$first = array_key_first($groups);
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>00deUdia Otimizações</title>
<style>
/* ---- identidade: tinta quente + laranja, com efeito de vidro ---------------- */
:root{
  --paper:#f3efe7; --ink:#1a1713; --muted:#6b655b;
  --line:rgba(120,110,95,.22); --line-strong:rgba(120,110,95,.34);
  --accent:#e4571c; --accent-ink:#fff; --teal:#0e7c6b; --warn:#a9741a; --danger:#bc332a;
  --glass:rgba(255,255,255,.55); --glass-2:rgba(255,255,255,.34);
  --blur:saturate(150%) blur(18px);
  --ring:rgba(228,87,28,.35);
  --shadow:0 1px 2px rgba(25,22,18,.06),0 14px 34px -18px rgba(25,22,18,.35);
  --r:16px; --r-sm:11px;
  --font:"Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif;
  --mono:ui-monospace,"SFMono-Regular",Menlo,Consolas,monospace;
  --top:58px;
}
@media (prefers-color-scheme: dark){
  :root{
    --paper:#0d0c0a; --ink:#f3efe7; --muted:#a49d90;
    --line:rgba(255,255,255,.12); --line-strong:rgba(255,255,255,.2);
    --accent:#ff6a2b; --accent-ink:#180d06; --teal:#31c0a5; --warn:#e0a53a; --danger:#ff6b5e;
    --glass:rgba(30,28,24,.5); --glass-2:rgba(30,28,24,.34);
    --shadow:0 1px 2px rgba(0,0,0,.45),0 16px 40px -20px rgba(0,0,0,.8);
  }
}
html[data-theme="light"]{ --paper:#f3efe7; --ink:#1a1713; --muted:#6b655b;
  --line:rgba(120,110,95,.22); --line-strong:rgba(120,110,95,.34); --accent:#e4571c; --accent-ink:#fff;
  --teal:#0e7c6b; --warn:#a9741a; --danger:#bc332a; --glass:rgba(255,255,255,.55); --glass-2:rgba(255,255,255,.34);
  --shadow:0 1px 2px rgba(25,22,18,.06),0 14px 34px -18px rgba(25,22,18,.35); }
html[data-theme="dark"]{ --paper:#0d0c0a; --ink:#f3efe7; --muted:#a49d90;
  --line:rgba(255,255,255,.12); --line-strong:rgba(255,255,255,.2); --accent:#ff6a2b; --accent-ink:#180d06;
  --teal:#31c0a5; --warn:#e0a53a; --danger:#ff6b5e; --glass:rgba(30,28,24,.5); --glass-2:rgba(30,28,24,.34);
  --shadow:0 1px 2px rgba(0,0,0,.45),0 16px 40px -20px rgba(0,0,0,.8); }

*{box-sizing:border-box}
[hidden]{display:none!important}
html{scroll-behavior:smooth}
html,body{margin:0}
body{
  font-family:var(--font); color:var(--ink); line-height:1.55; min-height:100dvh;
  -webkit-text-size-adjust:100%; overflow-x:hidden;
  background:url('assets/wallpaper.jpeg') center/cover fixed no-repeat var(--paper);
}
/* véu para dar contraste ao conteúdo sobre o wallpaper */
body::before{content:"";position:fixed;inset:0;z-index:-1;background:var(--paper);opacity:.8}
a{color:var(--accent)}
button{font:inherit;color:inherit}

/* ---- topo (vidro) --------------------------------------------------------- */
.top{
  position:sticky; top:0; z-index:40; height:var(--top);
  display:flex; align-items:center; gap:10px;
  padding:0 clamp(10px,3vw,20px);
  background:var(--glass); backdrop-filter:var(--blur); -webkit-backdrop-filter:var(--blur);
  border-bottom:1px solid var(--line);
}
.mark{width:36px;height:36px;flex:none;border-radius:11px;background:var(--accent);color:var(--accent-ink);
  display:grid;place-items:center;font-weight:800;font-size:14px;letter-spacing:-.05em}
.name{font-weight:800;letter-spacing:-.02em;font-size:15px;line-height:1.05;white-space:nowrap}
.name small{display:block;font-weight:500;font-size:11px;color:var(--muted);letter-spacing:0}
.grow{flex:1}
.iconbtn{
  border:1px solid var(--line);background:var(--glass-2);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border-radius:10px;padding:8px 11px;cursor:pointer;font-size:13px;font-weight:600;
  display:inline-flex;align-items:center;gap:6px;transition:.15s;white-space:nowrap
}
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

/* ---- layout --------------------------------------------------------------- */
.layout{max-width:1180px;margin:0 auto;display:grid;grid-template-columns:250px minmax(0,1fr);
  gap:clamp(14px,3vw,28px);padding:clamp(14px,3vw,26px) clamp(12px,3vw,22px)}
.side{align-self:start;position:sticky;top:calc(var(--top) + 12px)}
.side .panel{
  background:var(--glass); backdrop-filter:var(--blur); -webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line); border-radius:var(--r); box-shadow:var(--shadow);
  padding:12px; max-height:calc(100dvh - var(--top) - 24px); overflow:auto
}
.side h2{font-size:11px;text-transform:uppercase;letter-spacing:.12em;color:var(--muted);margin:2px 0 10px 8px}
.nav{display:flex;flex-direction:column;gap:2px}
.nav a{display:flex;align-items:center;gap:10px;padding:9px 11px;border-radius:var(--r-sm);
  color:var(--ink);text-decoration:none;font-size:13.5px;font-weight:600;border:1px solid transparent}
.nav a .c{width:6px;height:6px;border-radius:50%;background:var(--line-strong);flex:none}
.nav a:hover{background:var(--glass-2)}
.nav a[aria-current="true"]{background:var(--glass-2);border-color:var(--line-strong)}
.nav a[aria-current="true"] .c{background:var(--accent)}
.nav .count{margin-left:auto;font-size:11px;color:var(--muted);font-weight:700}

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
  background:var(--glass); backdrop-filter:var(--blur); -webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line); border-radius:var(--r); padding:15px;
  display:flex; flex-direction:column; gap:9px; box-shadow:var(--shadow)
}
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
  padding:10px 15px;font-size:13.5px;font-weight:700;cursor:pointer;transition:.15s}
.btn:hover{border-color:var(--accent)}
.btn.primary{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}
.btn.primary:hover{filter:brightness(1.06)}
.btn.danger{background:var(--danger);border-color:var(--danger);color:#fff}
.btn:disabled{opacity:.5;cursor:progress}

/* ---- gaveta lateral (celular) -------------------------------------------- */
.scrim{position:fixed;inset:0;z-index:54;background:rgba(12,10,8,.5);opacity:0;visibility:hidden;transition:.2s}
body.drawer .scrim{opacity:1;visibility:visible}
.side-close{display:none}

/* ---- console -------------------------------------------------------------- */
.console{position:fixed;left:0;right:0;bottom:0;z-index:60;transform:translateY(102%);transition:transform .22s ease;
  background:rgba(12,11,9,.92);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  color:#ece6da;border-top:1px solid rgba(255,255,255,.12);max-height:56vh;display:flex;flex-direction:column;
  box-shadow:0 -14px 44px -22px rgba(0,0,0,.85)}
.console.open{transform:none}
.console .bar{display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid rgba(255,255,255,.12)}
.console .bar b{font-size:13px}
.console pre{margin:0;padding:14px 16px;overflow:auto;font-family:var(--mono);font-size:12.5px;white-space:pre-wrap}
.close-x{border:1px solid rgba(255,255,255,.2);background:transparent;color:#ece6da;border-radius:8px;padding:6px 10px;cursor:pointer}

/* ---- modal ---------------------------------------------------------------- */
.mask{position:fixed;inset:0;z-index:70;background:rgba(12,10,8,.55);backdrop-filter:blur(4px);
  display:none;place-items:center;padding:16px}
.mask.open{display:grid}
.modal{background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line-strong);border-radius:20px;max-width:min(92vw,460px);width:100%;
  padding:22px;box-shadow:var(--shadow);max-height:86dvh;overflow:auto}
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

/* ---- responsivo ----------------------------------------------------------- */
@media (max-width:960px){
  .layout{grid-template-columns:1fr;gap:14px}
  .side{position:fixed;top:0;left:0;bottom:0;width:min(86vw,320px);z-index:56;padding:14px}
  .side .panel{max-height:100%;height:100%;border-radius:0 var(--r) var(--r) 0;padding-top:56px}
  .side{transform:translateX(-104%);transition:transform .22s ease}
  body.drawer .side{transform:none}
  .side-close{display:inline-flex;position:absolute;top:12px;right:12px}
  .burger{display:inline-flex}
}
@media (max-width:560px){
  .name small{display:none}
  .hide-sm{display:none}
  .grid{grid-template-columns:1fr}
  .fields{grid-template-columns:1fr}
  .banner .in{padding:16px 14px}
  .head h2{font-size:19px}
}
@media (max-width:380px){
  .name{font-size:14px}
  .mark{width:32px;height:32px;font-size:12px}
}
@media (prefers-reduced-motion: reduce){ *{transition:none!important} html{scroll-behavior:auto} }
</style>
</head>
<body>
<header class="top">
  <button class="iconbtn burger" id="burger" aria-label="Abrir categorias" aria-expanded="false">☰</button>
  <div class="mark" aria-hidden="true">00</div>
  <div class="name">00deUdia Otimizações<small>painel de controle</small></div>
  <div class="grow"></div>
  <span class="iconbtn hide-sm" id="modePill" style="cursor:default"><span class="dot"></span><span id="modeTxt">verificando…</span></span>
  <button class="iconbtn" id="btnTheme" aria-label="Alternar tema claro/escuro" title="Tema claro/escuro">◐</button>
  <button class="iconbtn hide-sm" id="btnStatus">Status</button>
  <button class="iconbtn hide-sm" id="btnLog">Histórico</button>
  <button class="iconbtn" id="btnConsole">Console</button>
</header>

<div class="banner">
  <div class="in">
    <h1>00deUdia Otimizações</h1>
    <p>Controle o pack inteiro pelo navegador: DNS, RAM, renderizador, touch do Free Fire, debloat e ajustes profundos. Toque no <b>?</b> de cada cartão para entender o que ele faz.</p>
    <span class="tag"><span class="dot"></span>conectado ao pack local</span>
  </div>
</div>

<div class="scrim" id="scrim"></div>

<div class="layout">
  <aside class="side" id="side" aria-label="Categorias">
    <div class="panel">
      <button class="iconbtn side-close" id="sideClose" aria-label="Fechar">✕</button>
      <h2>Categorias</h2>
      <nav class="nav" id="nav">
        <?php foreach ($groups as $g => $items): ?>
          <a href="#<?= htmlspecialchars(rawurlencode($g), ENT_QUOTES) ?>" data-g="<?= htmlspecialchars($g, ENT_QUOTES) ?>"
             aria-current="<?= $g === $first ? 'true' : 'false' ?>">
            <span class="c"></span><?= htmlspecialchars($meta[$g]['t'] ?? $g) ?>
            <span class="count"><?= count($items) ?></span>
          </a>
        <?php endforeach; ?>
      </nav>
    </div>
  </aside>

  <main class="content">
    <?php foreach ($groups as $g => $items): ?>
      <section id="g-<?= htmlspecialchars(rawurlencode($g), ENT_QUOTES) ?>" data-g="<?= htmlspecialchars($g, ENT_QUOTES) ?>"
               <?= $g !== $first ? 'hidden' : '' ?>>
        <div class="head">
          <h2><?= htmlspecialchars($meta[$g]['t'] ?? $g) ?></h2>
          <p><?= htmlspecialchars($meta[$g]['s'] ?? '') ?></p>
        </div>
        <div class="note">
          <span aria-hidden="true">ⓘ</span>
          <div><b>Antes de mexer:</b> salve um <b>snapshot</b> na aba Rápido para poder voltar.
          Ações <b>cuidado</b> e <b>root</b> pedem confirmação e são reversíveis.</div>
        </div>
        <div class="grid">
          <?php foreach ($items as $a):
            $risk = $a['risk'] ?? 'safe'; ?>
            <article class="card" data-id="<?= htmlspecialchars($a['id'], ENT_QUOTES) ?>">
              <div class="row">
                <h3><?= htmlspecialchars($a['label']) ?></h3>
                <span class="chip <?= htmlspecialchars($risk, ENT_QUOTES) ?>"><?= htmlspecialchars($riskLabel[$risk] ?? $risk) ?></span>
                <button class="help-btn" data-help="<?= htmlspecialchars($a['id'], ENT_QUOTES) ?>"
                        aria-label="O que faz: <?= htmlspecialchars($a['label'], ENT_QUOTES) ?>" title="O que isso faz?">?</button>
              </div>
              <?php if (!empty($a['desc'])): ?><p><?= htmlspecialchars($a['desc']) ?></p><?php endif; ?>
              <?php if (!empty($a['params'])): ?>
                <div class="fields">
                  <?php foreach ($a['params'] as $p):
                    $t = $p['type'] ?? 'text';
                    $wide = in_array($t, ['pkg', 'host', 'text', 'name'], true); ?>
                    <div class="field<?= $wide ? ' wide' : '' ?>">
                      <label for="<?= htmlspecialchars($a['id'] . '-' . $p['name'], ENT_QUOTES) ?>"><?= htmlspecialchars($p['label']) ?></label>
                      <input id="<?= htmlspecialchars($a['id'] . '-' . $p['name'], ENT_QUOTES) ?>"
                             data-p="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>"
                             type="<?= in_array($t, ['int', 'float'], true) ? 'number' : 'text' ?>"
                             value="<?= htmlspecialchars((string) ($p['default'] ?? ''), ENT_QUOTES) ?>"
                             <?= $t === 'pkg' ? 'list="applist" placeholder="com.exemplo.app"' : '' ?>
                             <?= $t === 'host' ? 'placeholder="dns.exemplo.com"' : '' ?>
                             <?= isset($p['min']) ? 'min="' . htmlspecialchars((string) $p['min'], ENT_QUOTES) . '"' : '' ?>
                             <?= isset($p['max']) ? 'max="' . htmlspecialchars((string) $p['max'], ENT_QUOTES) . '"' : '' ?>
                             <?= isset($p['step']) ? 'step="' . htmlspecialchars((string) $p['step'], ENT_QUOTES) . '"' : '' ?>>
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
  </main>
</div>

<div class="console" id="console" role="region" aria-label="Saída">
  <div class="bar"><b id="consoleTitle">Saída</b><span class="grow"></span>
    <button class="close-x" id="consoleClose">fechar ✕</button></div>
  <pre id="consoleOut"></pre>
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

<div class="toast" id="toast" role="status"></div>

<script>
const TOKEN = <?= json_encode($token) ?>;
const ACTIONS = <?= json_encode(array_column($actions, null, 'id'), JSON_UNESCAPED_UNICODE) ?>;
const RISKTXT = {careful:"AÇÃO DE CUIDADO", root:"AÇÃO COM ROOT"};
const $ = s => document.querySelector(s);
let pending = null;

/* tema */
const saved = localStorage.getItem("otm-theme");
if (saved) document.documentElement.dataset.theme = saved;
$("#btnTheme").onclick = () => {
  const cur = document.documentElement.dataset.theme ||
    (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  const next = cur === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  localStorage.setItem("otm-theme", next);
};

/* navegação */
function go(g, push){
  document.querySelectorAll("section[data-g]").forEach(s => s.hidden = s.dataset.g !== g);
  document.querySelectorAll("#nav a").forEach(a => a.setAttribute("aria-current", a.dataset.g === g ? "true" : "false"));
  document.body.classList.remove("drawer");
  $("#burger").setAttribute("aria-expanded", "false");
  if (push !== false) history.replaceState(null, "", "#" + encodeURIComponent(g));
  window.scrollTo({top:0, behavior:"instant"});
}
document.querySelectorAll("#nav a").forEach(a => a.onclick = e => { e.preventDefault(); go(a.dataset.g); });
const fromHash = () => { const g = decodeURIComponent(location.hash.slice(1)); if (g) go(g, false); };

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
function run(card, confirmed){
  const a = ACTIONS[card.dataset.id];
  if (a.confirm && !confirmed){
    pending = card;
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
    return;
  }
  doRun(card, collect(card), confirmed);
}
async function doRun(card, params, confirmed){
  const a = ACTIONS[card.dataset.id];
  setBusy(true);
  openConsole(a.label, "executando…");
  try{
    const r = await fetch("api.php?do=run", {
      method:"POST",
      headers:{"Content-Type":"application/json","X-OTM-Token":TOKEN},
      body: JSON.stringify({id:a.id, params, confirm:!!confirmed})
    });
    const j = await r.json();
    openConsole(a.label, (j.ok ? "✔ " : "✘ ") + "[" + (j.code ?? "?") + "]\n\n" + (j.out || j.error || ""));
    toast(j.ok ? "Feito: " + a.label : "Falhou: " + a.label, j.ok ? "ok" : "bad");
  }catch(e){ openConsole(a.label, "erro: " + e); toast("Erro de rede", "bad"); }
  setBusy(false);
}
document.querySelectorAll("[data-run]").forEach(b => b.onclick = () => run(b.closest(".card")));
const setBusy = b => document.querySelectorAll("[data-run]").forEach(x => x.disabled = b);

function openConsole(t, out){ $("#consoleTitle").textContent = t; $("#consoleOut").textContent = out; $("#console").classList.add("open"); }
function toast(m, k){ const t = $("#toast"); t.textContent = m; t.className = "toast show " + (k || "");
  clearTimeout(t._h); t._h = setTimeout(() => t.className = "toast", 3200); }
const apiGet = async a => (await fetch("api.php?action=" + a, {headers:{"X-OTM-Token":TOKEN}})).json();

$("#consoleClose").onclick = () => $("#console").classList.remove("open");
$("#btnConsole").onclick = () => $("#console").classList.toggle("open");
$("#mCancel").onclick = () => { $("#mask").classList.remove("open"); pending = null; };
$("#mCheck").onchange = e => $("#mGo").disabled = !e.target.checked;
$("#mGo").onclick = () => { $("#mask").classList.remove("open");
  if (pending) doRun(pending, collect(pending), true); };
$("#mask").onclick = e => { if (e.target.id === "mask"){ $("#mask").classList.remove("open"); pending = null; } };
$("#btnStatus").onclick = async () => { openConsole("Status do aparelho", "lendo…");
  const j = await apiGet("status"); openConsole("Status do aparelho", j.text || "(sem saída)"); };
$("#btnLog").onclick = async () => { openConsole("Histórico", "lendo…");
  const j = await apiGet("log");
  openConsole("Histórico", (j.log || []).map(x => (x.ok ? "✔" : "✘") + "  " + x.ts + "  " + x.label).join("\n") || "(nada ainda)"); };

window.addEventListener("hashchange", fromHash);
addEventListener("keydown", e => { if (e.key === "Escape"){ $("#mask").classList.remove("open"); document.body.classList.remove("drawer"); } });

/* apps instalados (autocomplete) + estado do modo */
(async () => {
  try{ const i = await apiGet("info"); $("#modeTxt").textContent = (i.have_adb ? "ADB ok" : "ADB ausente") + " · PHP " + i.php; }
  catch(e){ $("#modeTxt").textContent = "offline"; }
  try{ const j = await apiGet("apps");
    const dl = document.createElement("datalist"); dl.id = "applist";
    (j.apps || []).forEach(p => { const o = document.createElement("option"); o.value = p; dl.appendChild(o); });
    document.body.appendChild(dl);
  }catch(e){}
})();

fromHash();
</script>
</body>
</html>
