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
  { id: 19, prefix: "00-FWYE", label: "Whesley (dono)", role: "owner", status: "active",
    devices: 1, maxDevices: 0, uses: 3, maxUses: 0, expiresAt: "", sealed: true, mine: true },
  { id: 13, prefix: "TRIX-6Z0T", label: "00", role: "user", status: "active",
    devices: 2, maxDevices: 1, uses: 9, maxUses: 0, expiresAt: "", sealed: true, mine: false },
  { id: 6, prefix: "TRIX-BQR6", label: "Whesley", role: "user", status: "expired",
    devices: 1, maxDevices: 1, uses: 1, maxUses: 0, expiresAt: "2026-01-01 00:00:00", sealed: false, mine: false },
];

const OWNER_KEY = "00-FWYE-DC42-99WV";
const DEVICES = [{ id: 1, model: "Pixel 8", android: "14", app: "2.52.0",
  lastSeen: "2026-11-05 12:00:00", blocked: false }];

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
        expiresAt: "", devices: 1, maxDevices: 0, uses: 3, sealed: true, db: true, id: 19 };
    case "nick":
      return { ok: true, nick: "Whesley" };
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

console.log(fails.length ? "\nFALHAS: " + fails.join(", ") : "\nTODOS OS TESTES DE DOM PASSARAM");
process.exit(fails.length ? 1 : 0);
