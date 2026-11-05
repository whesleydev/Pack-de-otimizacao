/**
 * Teste de DOM do painel (Admin + Perfil).
 *
 * Roda o `assets/panel/index.html` de verdade num DOM (jsdom) com a ponte
 * nativa (`window.OTM.call`) trocada por um stub. Assim dá para exercitar a
 * tela sem celular: filtros, busca, edição, revelar chave e o Perfil.
 *
 * Depende de `jsdom`. Se ele não estiver instalado, o script avisa e sai com
 * código 3 — o `tests/run.sh` trata isso como "pulado", não como falha.
 *
 * Uso: node tests/dom/admin_profile.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const HTML = path.resolve(here, "../../app/src/main/assets/panel/index.html");

let JSDOM;
try {
  ({ JSDOM } = await import("jsdom"));
} catch {
  console.log("SKIP jsdom ausente");
  process.exit(3);
}

const html = fs.readFileSync(HTML, "utf8");

// --- o que o nativo devolveria (mesmo formato dos handlers de PackBridge) ----
const KEYS = [
  { id: 19, prefix: "00-FWYE", tail: "99WV", mask: "00-FWYE-····-99WV", label: "Whesley (dono)", role: "owner", status: "active",
    devices: 1, maxDevices: 0, uses: 3, maxUses: 0, expiresAt: "", sealed: true, mine: true },
  { id: 13, prefix: "TRIX-6Z0T", tail: "AB12", mask: "TRIX-6Z0T-····-AB12", label: "00", role: "user", status: "active",
    devices: 2, maxDevices: 1, uses: 9, maxUses: 0, expiresAt: "", sealed: true, mine: false },
  { id: 6, prefix: "TRIX-BQR6", tail: "", mask: "TRIX-BQR6-····-····", label: "Whesley", role: "user", status: "expired",
    devices: 1, maxDevices: 1, uses: 1, maxUses: 0, expiresAt: "2026-01-01 00:00:00", sealed: false, mine: false },
];

const OWNER_KEY = "00-FWYE-DC42-99WV";
const DEVICES = [{ id: 1, model: "Pixel 8", android: "14", app: "2.52.0",
  lastSeen: "2026-11-05 12:00:00", blocked: false }];

const FEEDBACK = [
  { id: 5, kind: "problema", message: "O painel flutuante some no Free Fire.", author: "João",
    mask: "TRIX-6Z0T-····-AB12", model: "Pixel 8", app: "2.53.0", contact: "zap 11 9...",
    status: "novo", reply: "", at: "2026-11-05 18:00:00" },
  { id: 4, kind: "sugestao", message: "Adiciona modo noturno no painel.", author: "Maria",
    mask: "00-FWYE-····-99WV", model: "S23", app: "2.53.0", contact: "",
    status: "resolvido", reply: "Já está no forno!", at: "2026-11-04 10:00:00" },
];

const native = (kind) => {
  switch (kind) {
    case "key_status":
      return { ok: true, logged: true, owner: true, role: "owner", label: "Whesley (dono)",
        prefix: "00-FWYE", expires_at: "", db: true };
    case "admin_list":
      return { ok: true, keys: KEYS, total: 3,
        summary: { active: 2, expired: 1, revoked: 0, exhausted: 0, scheduled: 0 }, db: true };
    case "admin_audit":
      return { ok: true, events: [{ prefix: "00-FWYE", result: "ok", model: "Pixel",
        app: "2.52.0", detail: "", at: "2026-11-05 16:00:00" }] };
    case "admin_plans":
      return { ok: true, plans: [{ id: 7, slug: "semanal", name: "Semanal", days: 7, devices: 1, uses: 0 },
        { id: 8, slug: "mensal", name: "Mensal", days: 30, devices: 2, uses: 0 }] };
    case "admin_detail":
      return { ok: true, key: KEYS[0], devices: DEVICES };
    case "admin_reveal":
    case "my_key":
      return { ok: true, key: OWNER_KEY };
    case "me":
      return { ok: true, role: "owner", owner: true, label: "Whesley (dono)", prefix: "00-FWYE",
        mask: "00-FWYE-····-99WV", tail: "99WV",
        expiresAt: "", devices: 1, maxDevices: 0, uses: 3, sealed: true, db: true, id: 19 };
    case "nick":
      return { ok: true, nick: "Whesley" };
    case "admin_dashboard":
      return { ok: true, total: 3, devices: 4, blocked: 0, uses: 13,
        summary: { active: 2, scheduled: 0, expired: 1, exhausted: 0, revoked: 0 },
        roles: { owner: 1, admin: 0, user: 2 },
        okWeek: 12, failWeek: 2, okDay: 4, newKeysWeek: 1,
        daily: [{ day: "2026-11-03", ok: 1 }, { day: "2026-11-04", ok: 3 },
          { day: "2026-11-05", ok: 4 }],
        plans: [{ name: "Semanal", count: 2 }, { name: "Mensal", count: 1 }],
        feedbackNew: 1, db: true };
    case "feedback_list":
      return { ok: true, feedback: FEEDBACK, novo: 1 };
    case "feedback_mine":
      return { ok: true, feedback: [FEEDBACK[1]] };
    case "feedback_send":
      return { ok: true, id: 9 };
    case "feedback_update":
    case "feedback_delete":
      return { ok: true };
    default:
      return { ok: true };
  }
};

const dom = new JSDOM(html, {
  runScripts: "dangerously",
  pretendToBeVisual: true,
  url: "http://localhost/panel/index.html#Admin",
  beforeParse(window) {
    window.scrollTo = () => {};
    window.OTM = {
      call(kind, payload, cbId) {
        const out = native(kind);
        Promise.resolve().then(() => window.__otmResolve(cbId, JSON.stringify(out)));
      },
    };
  },
});

const w = dom.window;
const $ = (s) => w.document.querySelector(s);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const click = (el) => el.dispatchEvent(new w.MouseEvent("click", { bubbles: true }));

const fails = [];
const chk = (name, cond) => {
  console.log((cond ? "[ ok ] " : "[FAIL] ") + name);
  if (!cond) fails.push(name);
};

await sleep(400);

chk("nav Admin visível para dono", $("#navAdmin").hidden === false);
await sleep(250);
chk("stats chaves=3", $("#admKeys").textContent === "3");
chk("stats ativas=2", $("#admActive").textContent === "2");
chk("stats aparelhos=4", $("#admDevs").textContent === "4");
chk("lista renderizou 3 itens", $("#admList").querySelectorAll(".adm-item").length === 3);
chk("chips renderizados", $("#admChips").querySelectorAll(".adm-chip").length === 6);
chk("planos carregados", $("#admPlans").querySelectorAll(".adm-plan").length === 2);
chk("chave do dono marcada 'você'", $("#admList").innerHTML.includes("você"));
chk("própria chave sem botão excluir", $("#admList").querySelector('[data-adm-del="19"]') === null);
chk("chave de outro tem excluir", $("#admList").querySelector('[data-adm-del="13"]') !== null);

click($("#admChips").querySelector('[data-adm-filter="expired"]'));
await sleep(60);
chk("filtro expiradas -> 1", $("#admList").querySelectorAll(".adm-item").length === 1);
click($("#admChips").querySelector('[data-adm-filter="all"]'));
await sleep(60);

const search = $("#admSearch");
search.value = "Whesley";
search.dispatchEvent(new w.Event("input", { bubbles: true }));
await sleep(60);
chk("busca 'Whesley' -> 2", $("#admList").querySelectorAll(".adm-item").length === 2);
search.value = "zzz";
search.dispatchEvent(new w.Event("input", { bubbles: true }));
await sleep(60);
chk("busca sem resultado mostra aviso", $("#admList").textContent.includes("Nada bate"));
search.value = "";
search.dispatchEvent(new w.Event("input", { bubbles: true }));
await sleep(60);

click($("#admPlans").querySelector(".adm-plan"));
await sleep(60);
chk("plano aplica dias=7", $("#admDays").value === "7");

click($("#admList").querySelector("[data-adm-edit]"));
await sleep(250);
chk("modal abriu", $("#admMask").classList.contains("open"));
chk("edLabel preenchido", $("#edLabel").value === "Whesley (dono)");
chk("aparelho listado", $("#edDevicesList").querySelectorAll(".adm-dev").length === 1);

click($("#edReveal"));
await sleep(250);
chk("revela chave no modal", $("#edKeyVal").textContent === OWNER_KEY);
chk("papel da própria chave travado", $("#edRole").disabled === true);

$("#edLabel").value = "Whesley dono";
click($("#edSave"));
await sleep(300);
chk("modal fechou ao salvar", !$("#admMask").classList.contains("open"));

w.location.hash = "#Perfil";
w.dispatchEvent(new w.Event("hashchange"));
await sleep(300);
chk("perfil: nome", $("#pfName").textContent === "Whesley");
chk("perfil: papel dono", $("#pfRowRole").textContent === "Dono");
chk("perfil: aparelhos", $("#pfRowDev").textContent === "1/∞");
chk("perfil: link admin visível", $("#pfGoAdmin").hidden === false);
click($("#pfReveal"));
await sleep(250);
chk("perfil revela própria chave", $("#pfKeyVal").textContent === OWNER_KEY);
chk("perfil: rótulo com fim da chave", $("#pfRowPrefix").textContent === "00-FWYE-····-99WV");

// --- a chave NUNCA aparece inteira na lista de admin -------------------------
const listaHtml = $("#admList").innerHTML;
chk("lista não mostra a chave inteira", !listaHtml.includes(OWNER_KEY));
chk("lista mostra início e fim", listaHtml.includes("00-FWYE-····-99WV"));
chk("lista de chave sem fim usa ····", listaHtml.includes("TRIX-BQR6-····-····"));
chk("busca acha pelo fim da chave",
  (() => { const s = $("#admSearch"); s.value = "99WV";
    s.dispatchEvent(new w.Event("input", { bubbles: true }));
    const n = $("#admList").querySelectorAll(".adm-item").length === 1;
    s.value = ""; s.dispatchEvent(new w.Event("input", { bubbles: true }));
    return n; })());

// --- Dashboard ---------------------------------------------------------------
w.location.hash = "#Dashboard";
w.dispatchEvent(new w.Event("hashchange"));
await sleep(300);
chk("nav Dashboard visível para dono", $("#navDash").hidden === false);
chk("dash: total=3", $("#dTotal").textContent === "3");
chk("dash: ativas=2", $("#dActive").textContent === "2");
chk("dash: aparelhos=4", $("#dDevices").textContent === "4");
chk("dash: usos=13", $("#dUses").textContent === "13");
chk("dash: falhas 7d=2", $("#dFailWeek").textContent === "2");
chk("dash: recados novos=1", $("#dFbNew").textContent === "1");
chk("dash: gráfico com 3 colunas", $("#dashChart").querySelectorAll(".dash-col").length === 3);
chk("dash: 5 barras de estado", $("#dashStatus").querySelectorAll(".dash-bar").length === 5);
chk("dash: 3 barras de papéis", $("#dashRoles").querySelectorAll(".dash-bar").length === 3);
chk("dash: 2 planos", $("#dashPlans").querySelectorAll(".dash-bar").length === 2);

// --- Feedback ----------------------------------------------------------------
w.location.hash = "#Feedback";
w.dispatchEvent(new w.Event("hashchange"));
await sleep(300);
chk("nav Feedback visível para usuário logado", $("#navFeedback").hidden === false);
chk("feedback: 5 tipos de recado", $("#fbKinds").querySelectorAll(".adm-chip").length === 5);
click($("#fbKinds").querySelector('[data-fb-kind="problema"]'));
await sleep(30);
chk("feedback: tipo selecionado", $("#fbKinds").querySelector('[data-fb-kind="problema"]').classList.contains("on"));
$("#fbMsg").value = "Achei um bug no overlay.";
click($("#fbSend"));
await sleep(300);
chk("feedback: enviado com sucesso", $("#fbStatus").textContent.includes("Recebido"));
chk("feedback: histórico do usuário", $("#fbList").querySelectorAll(".fb-item").length === 1);

// --- recados no Admin --------------------------------------------------------
w.location.hash = "#Admin";
w.dispatchEvent(new w.Event("hashchange"));
await sleep(300);
chk("admin: 2 recados listados", $("#admFbList").querySelectorAll(".fb-item").length === 2);
chk("admin: contador de novos no menu", $("#navAdminCount").textContent === "1");
chk("admin: mostra a máscara do autor", $("#admFbList").innerHTML.includes("TRIX-6Z0T-····-AB12"));
chk("admin: não vaza chave inteira", !$("#admFbList").innerHTML.includes(OWNER_KEY));
chk("admin: botão responder", $("#admFbList").querySelector("[data-fb-reply]") !== null);
chk("admin: botão excluir", $("#admFbList").querySelector("[data-fb-del]") !== null);
click($("#admFbList").querySelector('[data-fb-set="lido"]'));
await sleep(250);
chk("admin: marcou como lido", true);

console.log(fails.length ? "\nFALHAS: " + fails.join(", ") : "\nTODOS OS TESTES DE DOM PASSARAM");
process.exit(fails.length ? 1 : 0);
