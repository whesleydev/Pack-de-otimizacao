<?php
declare(strict_types=1);
require __DIR__ . '/lib.php';

$actions = array_values(otm_actions());
$groups = [];
foreach ($actions as $a) { $groups[$a['group']][] = $a; }
$token = is_file(__DIR__ . '/.token') ? trim((string)file_get_contents(__DIR__ . '/.token')) : '';
?>
<!DOCTYPE html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Painel · Pack de Otimização</title>
<style>
:root{
  --bg:#0a0d16; --bg2:#111726; --card:#141b2d; --card2:#1a2338; --line:#243048;
  --txt:#e8eefc; --mut:#93a3c4; --acc:#5b8cff; --acc2:#8a5bff;
  --ok:#31d0aa; --warn:#ffb020; --danger:#ff5d6c; --root:#ff8a3d;
  --sh:0 10px 30px rgba(0,0,0,.35);
}
*{box-sizing:border-box}
html,body{margin:0;height:100%}
body{
  font-family:"Inter",system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
  background:
    radial-gradient(1200px 600px at 15% -10%,rgba(26,37,71,.55) 0%,transparent 55%),
    radial-gradient(900px 500px at 100% 0%,rgba(42,26,71,.5) 0%,transparent 50%),
    linear-gradient(180deg,rgba(8,10,18,.82) 0%,rgba(8,10,18,.92) 100%),
    url('assets/wallpaper.jpeg') center/cover no-repeat fixed,
    var(--bg);
  color:var(--txt); min-height:100%; display:flex; flex-direction:column;
}
a{color:var(--acc);text-decoration:none}
header{
  display:flex;align-items:center;gap:14px;padding:14px 20px;
  border-bottom:1px solid var(--line);position:sticky;top:0;z-index:20;
  background:
    linear-gradient(90deg,rgba(8,10,18,.92) 0%,rgba(8,10,18,.62) 55%,rgba(8,10,18,.9) 100%),
    url('assets/banner.jpeg') center/cover no-repeat;
  box-shadow:0 8px 24px rgba(0,0,0,.35);
}
.brand{display:flex;align-items:center;gap:12px;font-weight:700;font-size:18px}
.brand .dot{width:34px;height:34px;border-radius:10px;
  background:linear-gradient(135deg,var(--acc),var(--acc2));box-shadow:var(--sh);
  display:grid;place-items:center;font-size:18px}
.brand small{display:block;font-weight:500;color:var(--mut);font-size:12px}
.spacer{flex:1}
.pill{font-size:12px;color:var(--mut);border:1px solid var(--line);padding:6px 12px;border-radius:999px}
.pill b{color:var(--ok)}
.btn{
  border:1px solid var(--line);background:var(--card);color:var(--txt);
  padding:9px 14px;border-radius:11px;cursor:pointer;font-size:13px;font-weight:600;
  transition:.15s;display:inline-flex;align-items:center;gap:7px
}
.btn:hover{border-color:var(--acc);transform:translateY(-1px)}
.btn.primary{background:linear-gradient(135deg,var(--acc),var(--acc2));border:0}
.btn.ghost{background:transparent}
.btn.danger{border-color:#5a2630;color:#ffb8bf}
.btn:disabled{opacity:.5;cursor:wait;transform:none}

.wrap{display:grid;grid-template-columns:230px 1fr;gap:0;flex:1;min-height:0}
nav{
  border-right:1px solid var(--line);padding:16px 12px;overflow:auto;
  background:rgba(17,23,38,.4)
}
nav h4{margin:16px 10px 8px;font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:var(--mut)}
nav button{
  width:100%;text-align:left;background:transparent;border:0;color:var(--txt);
  padding:10px 12px;border-radius:10px;cursor:pointer;font-size:13.5px;font-weight:600;
  display:flex;align-items:center;gap:9px;transition:.12s
}
nav button:hover{background:var(--card)}
nav button.active{background:linear-gradient(135deg,rgba(91,140,255,.22),rgba(138,91,255,.18));
  box-shadow:inset 0 0 0 1px var(--line)}
nav .ico{width:18px;text-align:center}

main{padding:22px 26px;overflow:auto;min-height:0}
.title{font-size:22px;font-weight:800;margin:0 0 4px}
.sub{color:var(--mut);font-size:13.5px;margin:0 0 18px}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(300px,1fr));gap:14px}
.card{
  background:linear-gradient(180deg,var(--card),var(--card2));
  border:1px solid var(--line);border-radius:16px;padding:16px;box-shadow:var(--sh);
  display:flex;flex-direction:column;gap:10px;transition:.15s
}
.card:hover{border-color:#33456b;transform:translateY(-2px)}
.card .top{display:flex;align-items:flex-start;gap:10px}
.card h3{margin:0;font-size:15px;font-weight:700;flex:1}
.card p{margin:0;color:var(--mut);font-size:12.8px;line-height:1.5}
.badge{font-size:10.5px;font-weight:800;text-transform:uppercase;letter-spacing:.05em;
  padding:4px 9px;border-radius:999px;border:1px solid transparent;white-space:nowrap}
.badge.safe{color:var(--ok);background:rgba(49,208,170,.12);border-color:rgba(49,208,170,.3)}
.badge.careful{color:var(--warn);background:rgba(255,176,32,.12);border-color:rgba(255,176,32,.3)}
.badge.root{color:var(--root);background:rgba(255,138,61,.12);border-color:rgba(255,138,61,.3)}
.params{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.params label{font-size:11px;color:var(--mut);display:block;margin-bottom:4px}
.params input{
  width:100%;background:var(--bg2);border:1px solid var(--line);color:var(--txt);
  border-radius:9px;padding:8px 10px;font-size:13px;outline:none
}
.params input:focus{border-color:var(--acc)}
.card .go{margin-top:auto;display:flex;gap:8px}

/* output */
.console{
  position:fixed;left:0;right:0;bottom:0;max-height:46vh;transform:translateY(100%);
  transition:.25s;background:#070a12;border-top:1px solid var(--line);z-index:30;
  display:flex;flex-direction:column
}
.console.open{transform:translateY(0)}
.console .bar{display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid var(--line)}
.console .bar b{font-size:13px}
.console pre{margin:0;padding:14px 16px;overflow:auto;font-family:"JetBrains Mono",ui-monospace,Menlo,monospace;
  font-size:12.5px;color:#c9d6f5;white-space:pre-wrap}
.tag-ok{color:var(--ok)}.tag-fail{color:var(--danger)}

/* modal */
.mask{position:fixed;inset:0;background:rgba(4,6,12,.7);backdrop-filter:blur(3px);
  display:none;place-items:center;z-index:40;padding:20px}
.mask.open{display:grid}
.modal{background:var(--card);border:1px solid var(--line);border-radius:18px;
  max-width:460px;width:100%;padding:22px;box-shadow:var(--sh)}
.modal h3{margin:0 0 8px;font-size:18px}
.modal p{color:var(--mut);font-size:13.5px;line-height:1.6;margin:0 0 14px}
.ack{display:flex;gap:10px;align-items:flex-start;background:var(--bg2);
  border:1px solid var(--line);border-radius:12px;padding:12px;margin-bottom:16px;font-size:13px}
.ack input{margin-top:3px}
.modal .row{display:flex;gap:10px;justify-content:flex-end}
.toast{position:fixed;bottom:24px;right:24px;background:var(--card2);border:1px solid var(--line);
  border-left:4px solid var(--acc);padding:12px 16px;border-radius:12px;box-shadow:var(--sh);
  font-size:13px;z-index:50;opacity:0;transform:translateY(10px);transition:.2s;max-width:360px}
.toast.show{opacity:1;transform:none}
.toast.ok{border-left-color:var(--ok)}.toast.bad{border-left-color:var(--danger)}
.hint{background:rgba(91,140,255,.08);border:1px solid var(--line);border-radius:12px;
  padding:12px 14px;font-size:12.8px;color:var(--mut);margin-bottom:18px}
.hint b{color:var(--txt)}
@media(max-width:820px){.wrap{grid-template-columns:1fr}nav{display:flex;overflow-x:auto;border-right:0;border-bottom:1px solid var(--line)}
  nav h4{display:none}nav button{width:auto;white-space:nowrap}}
</style>
</head>
<body>
<header>
  <div class="brand"><span class="dot">⚡</span>
    <div>Painel de Otimização<small>controle o pack pelo navegador</small></div>
  </div>
  <div class="spacer"></div>
  <span class="pill" id="pillModo">modo: <b>—</b></span>
  <button class="btn ghost" id="btnStatus">🩺 Status</button>
  <button class="btn ghost" id="btnLog">🕘 Histórico</button>
  <button class="btn ghost" id="btnConsole">⌨ Console</button>
</header>

<div class="wrap">
  <nav id="nav">
    <h4>Categorias</h4>
  </nav>
  <main>
    <h2 class="title" id="grpTitle">Rápido</h2>
    <p class="sub" id="grpSub">Comece por aqui.</p>
    <div class="hint" id="hint">
      <b>Antes de mexer:</b> salve um <b>snapshot</b> (na aba Rápido) para poder voltar.
      Ações marcadas <span class="badge careful">cuidado</span> e
      <span class="badge root">root</span> pedem confirmação. Tudo é reversível.
    </div>
    <div class="grid" id="grid"></div>
  </main>
</div>

<div class="console" id="console">
  <div class="bar">
    <b id="consoleTitle">Saída</b>
    <span class="spacer" style="flex:1"></span>
    <button class="btn ghost" id="consoleClose">fechar ✕</button>
  </div>
  <pre id="consoleOut"></pre>
</div>

<div class="mask" id="mask">
  <div class="modal">
    <h3 id="mTitle">Confirmar</h3>
    <p id="mDesc"></p>
    <div class="ack" id="mAck">
      <input type="checkbox" id="mCheck">
      <label for="mCheck" id="mAckLabel">Estou ciente dos riscos e quero continuar.</label>
    </div>
    <div class="row">
      <button class="btn ghost" id="mCancel">Cancelar</button>
      <button class="btn danger" id="mGo">Executar mesmo assim</button>
    </div>
  </div>
</div>

<div class="toast" id="toast"></div>

<script>
const ACTIONS = <?= json_encode($actions, JSON_UNESCAPED_UNICODE) ?>;
const GROUPS  = <?= json_encode(array_keys($groups), JSON_UNESCAPED_UNICODE) ?>;
const TOKEN   = <?= json_encode($token) ?>;

const SUB = {
  "Rápido":"Aplicar o conjunto seguro, reverter tudo ou salvar um snapshot.",
  "DNS":"Escolha um perfil de DNS privado (privacidade, anúncios, família, latência).",
  "RAM / Limpeza":"Mais RAM livre e limpeza de cache.",
  "Renderizador":"Troque o motor gráfico (OpenGL, Skia, Vulkan).",
  "Por app / jogo":"Escolha um app/jogo e mude o renderizador, o modo ou a resolução.",
  "Touch / Free Fire":"Perfis de sensibilidade/mira e ajustes do Free Fire.",
  "Performance":"Animações, tela, bateria e DND.",
  "Congelar apps":"Congele apps de fundo para liberar RAM.",
  "Debloat":"⚠️ Desativa bloatware. Reversível com 'Debloat: reverter tudo'.",
  "Profundas (root)":"Só funcionam com root. Mexem em kernel/sysfs — use com cuidado."
};
const ICONS = {"Rápido":"🚀","DNS":"🌐","RAM / Limpeza":"🧠","Renderizador":"🎨",
  "Por app / jogo":"🎮","Touch / Free Fire":"🎯","Performance":"⚡","Congelar apps":"🧊",
  "Debloat":"🧹","Profundas (root)":"🔓"};
const RISKTXT = {careful:"AÇÃO DE CUIDADO", root:"AÇÃO COM ROOT"};

let current = GROUPS[0];
let pending = null;

const $ = s => document.querySelector(s);
const esc = s => (s??"").toString().replace(/[&<>"]/g, c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

function buildNav(){
  const nav = $("#nav");
  GROUPS.forEach(g=>{
    const b = document.createElement("button");
    b.innerHTML = `<span class="ico">${ICONS[g]||"•"}</span>${esc(g)}`;
    b.onclick = ()=> show(g);
    b.dataset.g = g;
    nav.appendChild(b);
  });
}
function show(g){
  current = g;
  document.querySelectorAll("#nav button").forEach(b=>b.classList.toggle("active", b.dataset.g===g));
  $("#grpTitle").textContent = g;
  $("#grpSub").textContent = SUB[g]||"";
  const grid = $("#grid"); grid.innerHTML="";
  ACTIONS.filter(a=>a.group===g).forEach(a=> grid.appendChild(card(a)));
}
function card(a){
  const el = document.createElement("div"); el.className="card";
  const risk = a.risk||"safe";
  const params = (a.params||[]).map(p=>{
    if(p.type==="float"||p.type==="int"){
      return `<div><label>${esc(p.label)}</label>
        <input data-p="${p.name}" type="number" value="${p.default??''}"
          ${p.min!==undefined?`min="${p.min}"`:""} ${p.max!==undefined?`max="${p.max}"`:""}
          ${p.step?`step="${p.step}"`:""}></div>`;
    }
    if(p.type==="pkg"){
      return `<div style="grid-column:1/-1"><label>${esc(p.label)}</label>
        <input data-p="${p.name}" list="applist" placeholder="com.exemplo.app"></div>`;
    }
    return `<div style="grid-column:1/-1"><label>${esc(p.label)}</label>
      <input data-p="${p.name}" placeholder="dns.exemplo.com"></div>`;
  }).join("");
  el.innerHTML = `
    <div class="top">
      <h3>${esc(a.label)}</h3>
      <span class="badge ${risk}">${risk==="safe"?"seguro":(risk==="root"?"root":"cuidado")}</span>
    </div>
    <p>${esc(a.desc||"")}</p>
    ${params?`<div class="params">${params}</div>`:""}
    <div class="go">
      <button class="btn ${risk==="safe"?"primary":""}" data-run>Executar</button>
    </div>`;
  el.querySelector("[data-run]").onclick = ()=> run(a, el);
  return el;
}
function collectParams(a, el){
  const out = {};
  (a.params||[]).forEach(p=>{
    const i = el.querySelector(`[data-p="${p.name}"]`);
    out[p.name] = i ? i.value.trim() : (p.default??"");
  });
  return out;
}
function run(a, el, confirmed=false){
  const params = collectParams(a, el);
  if(a.confirm && !confirmed){
    pending = {a, el};
    $("#mTitle").textContent = a.label;
    $("#mDesc").textContent = (RISKTXT[a.risk]||"") + " — " + (a.desc||"");
    $("#mAckLabel").textContent = (a.risk==="root")
      ? "Estou ciente: mexe no kernel/sistema e pode esquentar ou instabilizar. Quero continuar."
      : "Estou ciente dos riscos e quero continuar.";
    $("#mCheck").checked = false;
    $("#mGo").disabled = true;
    $("#mask").classList.add("open");
    return;
  }
  doRun(a, params, confirmed);
}
async function doRun(a, params, confirmed){
  setBusy(true);
  openConsole(a.label, "executando…");
  try{
    const r = await fetch("api.php?do=run", {
      method:"POST",
      headers:{"Content-Type":"application/json","X-OTM-Token":TOKEN},
      body: JSON.stringify({id:a.id, params, confirm:!!confirmed})
    });
    const j = await r.json();
    if(j.need_confirm){ setBusy(false); return run(a, pending?pending.el:null, false); }
    openConsole(a.label, (j.ok?"✔ ":"✘ ")+"["+(j.code??"?")+"]\n\n"+(j.out||""));
    toast(j.ok?"Feito: "+a.label:"Falhou: "+a.label, j.ok?"ok":"bad");
  }catch(e){
    openConsole(a.label, "erro: "+e);
    toast("Erro de rede", "bad");
  }
  setBusy(false);
}
function setBusy(b){ document.querySelectorAll("[data-run]").forEach(x=>x.disabled=b); }
function openConsole(title, out){
  $("#consoleTitle").textContent = title;
  $("#consoleOut").textContent = out;
  $("#console").classList.add("open");
}
function toast(msg, kind){
  const t = $("#toast"); t.textContent = msg; t.className = "toast show "+(kind||"");
  clearTimeout(t._h); t._h = setTimeout(()=> t.className="toast", 3200);
}
async function apiGet(action){
  const r = await fetch("api.php?action="+action, {headers:{"X-OTM-Token":TOKEN}});
  return r.json();
}

// eventos
$("#consoleClose").onclick = ()=> $("#console").classList.remove("open");
$("#btnConsole").onclick = ()=> $("#console").classList.toggle("open");
$("#mCancel").onclick = ()=>{ $("#mask").classList.remove("open"); pending=null; };
$("#mCheck").onchange = e => $("#mGo").disabled = !e.target.checked;
$("#mGo").onclick = ()=>{
  $("#mask").classList.remove("open");
  if(pending) doRun(pending.a, collectParams(pending.a, pending.el), true);
};
$("#mask").onclick = e => { if(e.target.id==="mask"){ $("#mask").classList.remove("open"); pending=null; } };
$("#btnStatus").onclick = async ()=>{
  openConsole("Status do aparelho", "lendo…");
  const j = await apiGet("status");
  openConsole("Status do aparelho", j.text||"(sem saída)");
};
$("#btnLog").onclick = async ()=>{
  openConsole("Histórico de ações", "lendo…");
  const j = await apiGet("log");
  const rows = (j.log||[]).map(x=>`${x.ok?"✔":"✘"}  ${x.ts}  ${x.label}\n     $ ${x.cmd}`);
  openConsole("Histórico de ações", rows.join("\n") || "(nada ainda)");
};

// carrega apps para o datalist e o modo
(async ()=>{
  try{
    const info = await apiGet("info");
    $("#pillModo").innerHTML = "ADB: <b>"+(info.have_adb?"ok":"ausente")+"</b> · PHP "+esc(info.php);
  }catch(e){}
  try{
    const j = await apiGet("apps");
    const dl = document.createElement("datalist"); dl.id="applist";
    (j.apps||[]).forEach(p=>{ const o=document.createElement("option"); o.value=p; dl.appendChild(o); });
    document.body.appendChild(dl);
  }catch(e){}
})();

buildNav();
show(current);
</script>
</body>
</html>
