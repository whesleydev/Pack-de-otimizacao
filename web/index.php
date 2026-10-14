<?php
declare(strict_types=1);
/**
 * 00deUdia Otimizações — painel de controle (PHP).
 *
 * Toda a estrutura (menu de categorias e cards de ação) é renderizada aqui no
 * servidor a partir do registro em lib.php. O JavaScript só cuida de trocar de
 * categoria, executar via api.php e mostrar saída/confirmação.
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
    'Congelar apps'     => ['t' => 'Congelar apps',     's' => 'Congele apps em segundo plano para liberar RAM.'],
    'Debloat'           => ['t' => 'Debloat',           's' => 'Desativa bloatware. Tudo é reversível.'],
    'Profundas (root)'  => ['t' => 'Profundas (root)',  's' => 'Mexem em kernel e sistema. Só com root, use com cuidado.'],
];

$riskLabel = ['safe' => 'seguro', 'careful' => 'cuidado', 'root' => 'root'];

$token = is_file(__DIR__ . '/.token') ? trim((string) file_get_contents(__DIR__ . '/.token')) : '';
$first = array_key_first($groups);
?>
<!DOCTYPE html>
<html lang="pt-BR" class="js-off">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<title>00deUdia Otimizações</title>
<style>
/* ---- tema: tinta quente + laranja de chama (identidade própria) ---------- */
:root{
  --paper:#f4f0e8; --card:#fffdf9; --ink:#191612; --muted:#6d675c;
  --line:#e4ddd1; --line2:#d3cab9; --accent:#e4571c; --accent-ink:#fff;
  --teal:#0e7c6b; --warn:#a9741a; --danger:#bc332a;
  --ring:rgba(228,87,28,.28);
  --shadow:0 1px 2px rgba(25,22,18,.05),0 8px 24px -12px rgba(25,22,18,.18);
  --r:14px; --r-sm:10px;
  --font:"Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif;
  --mono:ui-monospace,"SFMono-Regular",Menlo,Consolas,monospace;
}
@media (prefers-color-scheme: dark){
  :root{
    --paper:#0e0d0b; --card:#181613; --ink:#f4f0e8; --muted:#a39c8f;
    --line:#2b2823; --line2:#3a352d; --accent:#ff6a2b; --accent-ink:#1a0f08;
    --teal:#2fbfa4; --warn:#e0a53a; --danger:#ff6b5e;
    --shadow:0 1px 2px rgba(0,0,0,.4),0 10px 30px -14px rgba(0,0,0,.7);
  }
}
html[data-theme="light"]{ --paper:#f4f0e8; --card:#fffdf9; --ink:#191612; --muted:#6d675c;
  --line:#e4ddd1; --line2:#d3cab9; --accent:#e4571c; --accent-ink:#fff; --teal:#0e7c6b;
  --warn:#a9741a; --danger:#bc332a; --shadow:0 1px 2px rgba(25,22,18,.05),0 8px 24px -12px rgba(25,22,18,.18); }
html[data-theme="dark"]{ --paper:#0e0d0b; --card:#181613; --ink:#f4f0e8; --muted:#a39c8f;
  --line:#2b2823; --line2:#3a352d; --accent:#ff6a2b; --accent-ink:#1a0f08; --teal:#2fbfa4;
  --warn:#e0a53a; --danger:#ff6b5e; --shadow:0 1px 2px rgba(0,0,0,.4),0 10px 30px -14px rgba(0,0,0,.7); }

*{box-sizing:border-box}
html,body{margin:0}
body{
  font-family:var(--font); background:var(--paper); color:var(--ink);
  line-height:1.5; -webkit-text-size-adjust:100%;
  background-image:url('assets/wallpaper.jpeg');
  background-size:cover; background-position:center; background-attachment:fixed;
  background-blend-mode:soft-light;
}
body::before{content:"";position:fixed;inset:0;background:var(--paper);opacity:.9;z-index:-1}
a{color:var(--accent)}
button{font:inherit}

/* ---- topo ---------------------------------------------------------------- */
.top{
  position:sticky; top:0; z-index:40; display:flex; align-items:center; gap:12px;
  padding:10px clamp(12px,3vw,22px); background:color-mix(in srgb,var(--paper) 88%,transparent);
  backdrop-filter:blur(10px); border-bottom:1px solid var(--line);
}
.mark{
  width:38px;height:38px;flex:none;border-radius:11px;background:var(--accent);color:var(--accent-ink);
  display:grid;place-items:center;font-weight:800;font-size:15px;letter-spacing:-.04em;
  box-shadow:var(--shadow)
}
.name{font-weight:800;letter-spacing:-.02em;font-size:16px;line-height:1.1}
.name span{display:block;font-weight:500;font-size:11.5px;color:var(--muted);letter-spacing:0}
.grow{flex:1}
.iconbtn{
  border:1px solid var(--line);background:var(--card);color:var(--ink);border-radius:10px;
  padding:8px 11px;cursor:pointer;font-size:13px;font-weight:600;display:inline-flex;
  align-items:center;gap:6px;transition:.15s
}
.iconbtn:hover{border-color:var(--line2)}
.iconbtn:focus-visible{outline:2px solid var(--ring);outline-offset:1px}
.burger{display:none}
@media (max-width:760px){ .name span{display:none} .hide-sm{display:none} .burger{display:inline-flex} }

/* ---- banner (imagem do usuário) ----------------------------------------- */
.banner{
  position:relative; color:#fff; overflow:hidden; border-bottom:1px solid var(--line);
  background:url('assets/banner.jpeg') center/cover no-repeat, #241f19;
}
.banner::after{content:"";position:absolute;inset:0;
  background:linear-gradient(90deg,rgba(18,14,10,.9),rgba(18,14,10,.55) 60%,rgba(18,14,10,.75))}
.banner .in{position:relative;z-index:1;padding:clamp(20px,5vw,40px) clamp(12px,3vw,22px);max-width:1200px;margin:0 auto}
.banner h1{margin:0;font-size:clamp(22px,4.5vw,34px);font-weight:800;letter-spacing:-.03em}
.banner p{margin:6px 0 0;color:#e9e2d7;font-size:clamp(13px,2.4vw,15px);max-width:60ch}
.pill{display:inline-flex;align-items:center;gap:7px;margin-top:14px;padding:5px 11px;border-radius:999px;
  background:rgba(255,255,255,.14);border:1px solid rgba(255,255,255,.25);font-size:12px;font-weight:600}
.dot{width:7px;height:7px;border-radius:50%;background:var(--teal)}

/* ---- layout -------------------------------------------------------------- */
.layout{max-width:1200px;margin:0 auto;display:grid;grid-template-columns:240px 1fr;gap:clamp(16px,3vw,30px);
  padding:clamp(16px,3vw,28px) clamp(12px,3vw,22px) 80px}
.side{position:sticky;top:64px;align-self:start;max-height:calc(100vh - 84px);overflow:auto}
.side h2{font-size:11px;text-transform:uppercase;letter-spacing:.12em;color:var(--muted);margin:0 0 10px 8px}
.nav{display:flex;flex-direction:column;gap:2px}
.nav a{
  display:flex;align-items:center;gap:10px;padding:9px 11px;border-radius:var(--r-sm);
  color:var(--ink);text-decoration:none;font-size:13.5px;font-weight:600;border:1px solid transparent
}
.nav a .c{width:6px;height:6px;border-radius:50%;background:var(--line2);flex:none}
.nav a:hover{background:color-mix(in srgb,var(--card) 70%,transparent)}
.nav a[aria-current="true"]{background:var(--card);border-color:var(--line);box-shadow:var(--shadow)}
.nav a[aria-current="true"] .c{background:var(--accent)}
.nav .count{margin-left:auto;font-size:11px;color:var(--muted);font-weight:600}

/* ---- conteúdo ------------------------------------------------------------ */
.head h2{margin:0;font-size:clamp(19px,3.5vw,24px);font-weight:800;letter-spacing:-.02em}
.head p{margin:4px 0 0;color:var(--muted);font-size:14px}
.note{display:flex;gap:10px;align-items:flex-start;margin:18px 0;padding:12px 14px;border-radius:var(--r-sm);
  background:var(--card);border:1px solid var(--line);color:var(--muted);font-size:13px}
.note b{color:var(--ink)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,300px),1fr));gap:14px;margin-top:6px}
section[hidden]{display:none}

.card{background:var(--card);border:1px solid var(--line);border-radius:var(--r);padding:16px;
  display:flex;flex-direction:column;gap:10px;box-shadow:var(--shadow)}
.card .row{display:flex;align-items:flex-start;gap:10px}
.card h3{margin:0;font-size:14.5px;font-weight:700;flex:1;letter-spacing:-.01em}
.card p{margin:0;color:var(--muted);font-size:13px}
.chip{font-size:10.5px;font-weight:800;text-transform:uppercase;letter-spacing:.06em;padding:3px 8px;
  border-radius:999px;border:1px solid var(--line2);color:var(--muted);white-space:nowrap}
.chip.careful{color:var(--warn);border-color:color-mix(in srgb,var(--warn) 40%,var(--line))}
.chip.root{color:var(--danger);border-color:color-mix(in srgb,var(--danger) 40%,var(--line))}
.fields{display:grid;grid-template-columns:1fr 1fr;gap:10px}
.field{display:flex;flex-direction:column;gap:5px}
.field.wide{grid-column:1/-1}
.field label{font-size:11px;font-weight:600;color:var(--muted);letter-spacing:.02em}
.field input{width:100%;padding:9px 11px;border-radius:var(--r-sm);border:1px solid var(--line2);
  background:var(--paper);color:var(--ink);font-size:13.5px}
.field input:focus-visible{outline:2px solid var(--ring);outline-offset:1px;border-color:var(--accent)}
.go{margin-top:auto;display:flex;gap:8px}
.btn{border:1px solid var(--line2);background:var(--card);color:var(--ink);border-radius:var(--r-sm);
  padding:10px 15px;font-size:13.5px;font-weight:700;cursor:pointer;transition:.15s}
.btn:hover{border-color:var(--accent)}
.btn.primary{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}
.btn.primary:hover{filter:brightness(1.06)}
.btn.danger{background:var(--danger);border-color:var(--danger);color:#fff}
.btn:disabled{opacity:.5;cursor:progress}

/* ---- console ------------------------------------------------------------- */
.console{position:fixed;left:0;right:0;bottom:0;z-index:50;transform:translateY(102%);transition:transform .22s ease;
  background:#0c0b09;color:#ece6da;border-top:1px solid #2b2823;max-height:52vh;display:flex;flex-direction:column;
  box-shadow:0 -10px 40px -20px rgba(0,0,0,.8)}
.console.open{transform:none}
.console .bar{display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid #2b2823}
.console .bar b{font-size:13px}
.console pre{margin:0;padding:14px 16px;overflow:auto;font-family:var(--mono);font-size:12.5px;white-space:pre-wrap}
.close-x{border:1px solid #3a352d;background:transparent;color:#ece6da;border-radius:8px;padding:6px 10px;cursor:pointer}

/* ---- modal --------------------------------------------------------------- */
.mask{position:fixed;inset:0;z-index:60;background:rgba(12,10,8,.62);display:none;place-items:center;padding:18px}
.mask.open{display:grid}
.modal{background:var(--card);color:var(--ink);border:1px solid var(--line);border-radius:18px;max-width:440px;
  width:100%;padding:22px;box-shadow:var(--shadow)}
.modal h3{margin:0 0 6px;font-size:18px;letter-spacing:-.02em}
.modal p{margin:0 0 14px;color:var(--muted);font-size:13.5px}
.ack{display:flex;gap:10px;align-items:flex-start;padding:12px;border:1px solid var(--line);border-radius:var(--r-sm);
  background:var(--paper);font-size:13px;margin-bottom:16px}
.ack input{margin-top:2px}
.modal .row{display:flex;gap:10px;justify-content:flex-end}
.toast{position:fixed;left:50%;bottom:22px;transform:translate(-50%,14px);z-index:70;background:var(--card);
  color:var(--ink);border:1px solid var(--line);border-left:4px solid var(--accent);border-radius:12px;
  padding:11px 16px;font-size:13px;box-shadow:var(--shadow);opacity:0;transition:.2s;max-width:90vw}
.toast.show{opacity:1;transform:translate(-50%,0)}
.toast.ok{border-left-color:var(--teal)} .toast.bad{border-left-color:var(--danger)}

/* ---- responsivo ---------------------------------------------------------- */
@media (max-width:900px){
  .layout{grid-template-columns:1fr;gap:16px}
  .side{position:fixed;top:0;left:0;bottom:0;width:min(84vw,300px);z-index:55;background:var(--card);
    border-right:1px solid var(--line);padding:16px;transform:translateX(-102%);transition:transform .22s ease;
    max-height:none;box-shadow:var(--shadow)}
  body.drawer .side{transform:none}
  .side h2{margin-top:44px}
  .scrim{position:fixed;inset:0;z-index:54;background:rgba(12,10,8,.5);display:none}
  body.drawer .scrim{display:block}
  .side-close{display:inline-flex}
}
.side-close{display:none;position:absolute;top:12px;right:12px}
@media (max-width:420px){ .fields{grid-template-columns:1fr} }
@media (prefers-reduced-motion: reduce){ *{transition:none!important} }
</style>
</head>
<body>
<header class="top">
  <button class="iconbtn burger" id="burger" aria-label="Abrir categorias">☰</button>
  <div class="mark" aria-hidden="true">00</div>
  <div class="name">00deUdia Otimizações<span>painel de controle</span></div>
  <div class="grow"></div>
  <span class="pill hide-sm" id="modePill" style="margin:0;background:color-mix(in srgb,var(--card) 80%,transparent);color:var(--ink);border-color:var(--line)">
    <span class="dot"></span><span id="modeTxt">verificando…</span>
  </span>
  <button class="iconbtn" id="btnTheme" aria-label="Alternar tema">◐</button>
  <button class="iconbtn hide-sm" id="btnStatus">Status</button>
  <button class="iconbtn hide-sm" id="btnLog">Histórico</button>
  <button class="iconbtn" id="btnConsole">Console</button>
</header>

<div class="banner">
  <div class="in">
    <h1>00deUdia Otimizações</h1>
    <p>Controle o pack inteiro pelo navegador: DNS, RAM, renderizador, touch do Free Fire, debloat e ajustes profundos. As ações de risco pedem confirmação.</p>
    <span class="pill"><span class="dot"></span>conectado ao pack local</span>
  </div>
</div>

<div class="scrim" id="scrim"></div>

<div class="layout">
  <aside class="side" id="side" aria-label="Categorias">
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
          <span>ⓘ</span>
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
              </div>
              <?php if (!empty($a['desc'])): ?><p><?= htmlspecialchars($a['desc']) ?></p><?php endif; ?>
              <?php if (!empty($a['params'])): ?>
                <div class="fields">
                  <?php foreach ($a['params'] as $p):
                    $t = $p['type'] ?? 'text';
                    $wide = in_array($t, ['pkg', 'host', 'text'], true); ?>
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
    <label class="ack"><input type="checkbox" id="mCheck">
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
document.documentElement.classList.remove("js-off");
let pending = null;

/* tema: lembra a escolha, senão segue o sistema */
const saved = localStorage.getItem("otm-theme");
if (saved) document.documentElement.dataset.theme = saved;
$("#btnTheme").onclick = () => {
  const cur = document.documentElement.dataset.theme ||
    (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  const next = cur === "dark" ? "light" : "dark";
  document.documentElement.dataset.theme = next;
  localStorage.setItem("otm-theme", next);
};

/* navegação entre categorias */
function go(g, push){
  document.querySelectorAll("section[data-g]").forEach(s => s.hidden = s.dataset.g !== g);
  document.querySelectorAll("#nav a").forEach(a => a.setAttribute("aria-current", a.dataset.g === g ? "true" : "false"));
  document.body.classList.remove("drawer");
  if (push !== false) history.replaceState(null, "", "#" + encodeURIComponent(g));
  window.scrollTo({top:0, behavior:"instant"});
}
document.querySelectorAll("#nav a").forEach(a => a.onclick = e => { e.preventDefault(); go(a.dataset.g); });
const fromHash = () => { const g = decodeURIComponent(location.hash.slice(1)); if (g) go(g, false); };

/* gaveta no celular */
$("#burger").onclick = () => document.body.classList.add("drawer");
$("#scrim").onclick = $("#sideClose").onclick = () => document.body.classList.remove("drawer");

/* coletar e executar */
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
    $("#mDesc").textContent = (RISKTXT[a.risk] || "") + " — " + (a.desc || "");
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

/* apps instalados para o autocomplete + estado do modo */
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
