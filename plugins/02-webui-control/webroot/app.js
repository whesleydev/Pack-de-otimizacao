/**
 * Pack OTM · WebUI Control
 * Comunica com o shell via ponte do KernelSU/AxManager (@kernelsu/api).
 */

const APPLY = '/data/adb/packotm/apply.sh';

let execFn = null;

async function initBridge() {
  try {
    const api = await import('@kernelsu/api');
    if (api && api.exec) execFn = api.exec;
  } catch (e) { /* fora do ambiente de módulo */ }
  if (!execFn && typeof window !== 'undefined' && window.ksu && window.ksu.exec) {
    execFn = cmd => window.ksu.exec(cmd);
  }
  return !!execFn;
}

async function exec(cmd) {
  if (!execFn) return '';
  try {
    const r = await execFn(cmd);
    if (r && typeof r === 'object') return r.stdout || r.output || '';
    return String(r || '');
  } catch (e) { return ''; }
}

function toast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(t._t);
  t._t = setTimeout(() => t.classList.remove('show'), 1800);
}

async function loadStatus() {
  const ram = await exec('cat /proc/meminfo | grep MemAvailable | tr -dc "0-9 " | awk \'{print int($1/1024)}\'');
  const bat = await exec('dumpsys battery | grep level | tr -dc 0-9');
  const temp = await exec('cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -nr | head -1');
  const hz = await exec('settings get system peak_refresh_rate');

  setText('s-ram', ram.trim() || '–');
  setText('s-bat', bat.trim() || '–');
  let t = parseInt((temp || '').trim(), 10);
  if (!isNaN(t)) { if (t > 1000) t = Math.round(t / 1000); else if (t > 100) t = Math.round(t / 10); }
  setText('s-temp', isNaN(t) ? '–' : t);
  setText('s-hz', (hz || '').trim() && (hz || '').trim() !== 'null' ? String(Math.round(parseFloat(hz))) : '–');
}

function setText(id, v) { const el = document.getElementById(id); if (el) el.textContent = v; }

async function loadConfig() {
  const raw = await exec(`sh ${APPLY} show`);
  const cfg = {};
  (raw || '').split('\n').forEach(line => {
    const i = line.indexOf('=');
    if (i > 0) cfg[line.slice(0, i).trim()] = line.slice(i + 1).trim();
  });
  const map = {
    't-perf': 'CFG_PERF', 't-gfx': 'CFG_GFX', 't-net': 'CFG_NET',
    't-game': 'CFG_GAME', 't-freeze': 'CFG_FREEZE', 't-dnd': 'CFG_DND',
    't-tv': 'CFG_TV', 't-touch': 'CFG_TOUCH', 't-loop': 'CFG_LOOP',
    't-gametune': 'CFG_GAMETUNE',
    't-angle': 'CFG_ANGLE', 't-debloat': 'CFG_DEBLOAT',
    't-deep': 'CFG_DEEP', 't-thermal': 'CFG_THERMAL'
  };
  for (const [id, key] of Object.entries(map)) {
    const el = document.getElementById(id);
    if (el) el.checked = cfg[key] === '1';
  }
  const num = {
    'i-anim': 'CFG_ANIM', 'i-tr': 'CFG_TR', 'i-lp': 'CFG_LP',
    'i-ps': 'CFG_PS', 'i-slop': 'CFG_SLOP', 'i-hz': 'CFG_HZ',
    'i-gt-ds': 'CFG_GT_DS', 'i-gt-fps': 'CFG_GT_FPS'
  };
  for (const [id, key] of Object.entries(num)) {
    const el = document.getElementById(id);
    if (el && cfg[key] !== undefined) el.value = cfg[key];
  }
  const txt = { 'i-gt-pkg': 'CFG_GT_PKG', 'i-angle-pkgs': 'CFG_ANGLE_PKGS' };
  for (const [id, key] of Object.entries(txt)) {
    const el = document.getElementById(id);
    if (el && cfg[key] !== undefined) el.value = cfg[key];
  }
}

async function pushConfig() {
  const map = {
    't-perf': 'CFG_PERF', 't-gfx': 'CFG_GFX', 't-net': 'CFG_NET',
    't-game': 'CFG_GAME', 't-freeze': 'CFG_FREEZE', 't-dnd': 'CFG_DND',
    't-tv': 'CFG_TV', 't-touch': 'CFG_TOUCH', 't-loop': 'CFG_LOOP',
    't-gametune': 'CFG_GAMETUNE',
    't-angle': 'CFG_ANGLE', 't-debloat': 'CFG_DEBLOAT',
    't-deep': 'CFG_DEEP', 't-thermal': 'CFG_THERMAL'
  };
  for (const [id, key] of Object.entries(map)) {
    const el = document.getElementById(id);
    if (el) await exec(`sh ${APPLY} set ${key} ${el.checked ? 1 : 0}`);
  }
  const num = {
    'i-anim': 'CFG_ANIM', 'i-tr': 'CFG_TR', 'i-lp': 'CFG_LP',
    'i-ps': 'CFG_PS', 'i-slop': 'CFG_SLOP', 'i-hz': 'CFG_HZ',
    'i-gt-ds': 'CFG_GT_DS', 'i-gt-fps': 'CFG_GT_FPS'
  };
  for (const [id, key] of Object.entries(num)) {
    const el = document.getElementById(id);
    if (el && el.value !== '') await exec(`sh ${APPLY} set ${key} ${el.value}`);
  }
  const txt = { 'i-gt-pkg': 'CFG_GT_PKG', 'i-angle-pkgs': 'CFG_ANGLE_PKGS' };
  for (const [id, key] of Object.entries(txt)) {
    const el = document.getElementById(id);
    if (el && el.value !== '') await exec(`sh ${APPLY} set ${key} ${el.value}`);
  }
}

document.addEventListener('DOMContentLoaded', async () => {
  const ok = await initBridge();
  if (!ok) toast('Ponte indisponível (abra pelo gerenciador)');

  loadStatus();
  loadConfig();

  document.getElementById('btn-apply').onclick = async () => {
    await pushConfig();
    const out = await exec(`sh ${APPLY} apply`);
    toast((out || '').includes('ok') ? 'Aplicado!' : 'Aplicado');
    loadStatus();
  };
  document.getElementById('btn-save').onclick = async () => {
    await pushConfig();
    await exec(`sh ${APPLY} save`);
    toast('Config salva');
  };
  document.getElementById('btn-refresh').onclick = () => { loadStatus(); toast('Status atualizado'); };
  document.getElementById('btn-restore').onclick = async () => {
    await exec(`sh ${APPLY} restore`);
    loadConfig();
    loadStatus();
    toast('Restaurado');
  };

  setInterval(loadStatus, 10000);
});
