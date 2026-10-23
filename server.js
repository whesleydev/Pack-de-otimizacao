import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import url from 'node:url';
import { exec, spawn } from 'node:child_process';
import crypto from 'node:crypto';

const PORT = parseInt(process.env.DEFAULT_APP_PORT || '3000', 10);
const HOST = '0.0.0.0';
const ROOT_DIR = process.cwd();

// Setup Android stubs directory in /tmp/otm_bin so shell scripts find settings, cmd, getprop, etc.
const STUB_BIN = '/tmp/otm_bin';
const STUB_STORE = '/tmp/otm_store';
fs.mkdirSync(STUB_BIN, { recursive: true });
fs.mkdirSync(STUB_STORE, { recursive: true });

// Setup state dir
const STATE_DIR = path.join(process.env.HOME || '/root', '.packotm');
fs.mkdirSync(STATE_DIR, { recursive: true });

// Create realistic Android CLI stubs
fs.writeFileSync(path.join(STUB_BIN, 'settings'), `#!/bin/sh
STORE="${STUB_STORE}"
case "$1" in
  get) cat "$STORE/$2.$3" 2>/dev/null ;;
  put) t="$2"; k="$3"; shift 3; printf "%s" "$*" > "$STORE/$t.$k" ;;
  delete) rm -f "$STORE/$2.$3" ;;
esac
exit 0
`, { mode: 0o755 });

fs.writeFileSync(path.join(STUB_BIN, 'cmd'), `#!/bin/sh
exit 0
`, { mode: 0o755 });

fs.writeFileSync(path.join(STUB_BIN, 'am'), `#!/bin/sh
exit 0
`, { mode: 0o755 });

fs.writeFileSync(path.join(STUB_BIN, 'pm'), `#!/bin/sh
if [ "$1" = "list" ]; then
  cat <<'EOF'
package:com.dts.freefireth
package:com.dts.freefiremax
package:com.tencent.ig
package:com.activision.callofduty.shooter
package:com.roblox.client
package:com.miHoYo.GenshinImpact
package:com.whatsapp
package:com.instagram.android
package:com.google.android.youtube
package:com.android.chrome
package:com.discord
package:com.spotify.music
EOF
fi
exit 0
`, { mode: 0o755 });

fs.writeFileSync(path.join(STUB_BIN, 'getprop'), `#!/bin/sh
STORE="${STUB_STORE}"
val=$(cat "$STORE/prop.$1" 2>/dev/null)
if [ -n "$val" ]; then
  echo "$val"
else
  case "$1" in
    ro.product.model) echo "Snapdragon 8 Gen 2 Extreme" ;;
    ro.product.brand) echo "Android" ;;
    ro.build.version.release) echo "14" ;;
    debug.hwui.renderer) echo "skiagl" ;;
    *) echo "" ;;
  esac
fi
exit 0
`, { mode: 0o755 });

fs.writeFileSync(path.join(STUB_BIN, 'setprop'), `#!/bin/sh
STORE="${STUB_STORE}"
printf "%s" "$2" > "$STORE/prop.$1"
exit 0
`, { mode: 0o755 });

// Pre-seed some default settings if empty
if (!fs.existsSync(path.join(STUB_STORE, 'global.window_animation_scale'))) {
  fs.writeFileSync(path.join(STUB_STORE, 'global.window_animation_scale'), '0.5');
  fs.writeFileSync(path.join(STUB_STORE, 'global.transition_animation_scale'), '0.5');
  fs.writeFileSync(path.join(STUB_STORE, 'global.animator_duration_scale'), '0.5');
  fs.writeFileSync(path.join(STUB_STORE, 'global.force_gpu_rendering'), '1');
  fs.writeFileSync(path.join(STUB_STORE, 'system.peak_refresh_rate'), '120.0');
  fs.writeFileSync(path.join(STUB_STORE, 'system.min_refresh_rate'), '120.0');
  fs.writeFileSync(path.join(STUB_STORE, 'system.touch_responsiveness'), '110');
  fs.writeFileSync(path.join(STUB_STORE, 'global.private_dns_mode'), 'hostname');
  fs.writeFileSync(path.join(STUB_STORE, 'global.private_dns_specifier'), 'one.one.one.one');
}

// In-memory logs
const LOGS = [
  {
    id: 'init',
    label: 'Inicialização do Pack 00',
    cmd: 'sh scripts/pack.sh status',
    ok: true,
    code: 0,
    time: new Date().toLocaleTimeString('pt-BR'),
    out: '[ok] Sistema iniciado em modo Shizuku privilegiado (root concedido).'
  }
];

// Terminal history
const TERM_HIST = [
  'sh scripts/pack.sh status',
  'sh scripts/dns.sh list',
  'getprop debug.hwui.renderer'
];

// Load catalog
let catalog = {};
let actionsList = [];
try {
  const rawActions = fs.readFileSync(path.join(ROOT_DIR, 'android/app/src/main/assets/panel/actions.json'), 'utf8');
  actionsList = JSON.parse(rawActions);
  actionsList.forEach(a => { catalog[a.id] = a; });
} catch (e) {
  console.error('Failed to load actions.json:', e);
}

// Sound group mapping
function soundFor(group) {
  if (group === 'Desempenho' || group === 'Apps e jogos') return 'liberando-memoria-ram.mp3';
  if (group === 'DNS e rede' || group === 'Rede e conexão') return 'configurando-dns.mp3';
  if (group === 'Display & Touch' || group === 'Sistema') return 'ativando.mp3';
  return 'otimizando-o-sistema.mp3';
}

// App metadata icons (SVG encoded in base64)
function svgToBase64(svg) {
  return Buffer.from(svg).toString('base64');
}

const APPS_META = [
  {
    pkg: 'com.dts.freefireth',
    label: 'Garena Free Fire',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#E4571C"/><text x="50" y="62" font-family="sans-serif" font-weight="900" font-size="34" fill="#FFFFFF" text-anchor="middle">FF</text></svg>')
  },
  {
    pkg: 'com.dts.freefiremax',
    label: 'Free Fire MAX',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#D4A017"/><text x="50" y="62" font-family="sans-serif" font-weight="900" font-size="30" fill="#000000" text-anchor="middle">MAX</text></svg>')
  },
  {
    pkg: 'com.tencent.ig',
    label: 'PUBG Mobile',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#243244"/><text x="50" y="62" font-family="sans-serif" font-weight="900" font-size="28" fill="#FFCF5C" text-anchor="middle">PUBG</text></svg>')
  },
  {
    pkg: 'com.activision.callofduty.shooter',
    label: 'Call of Duty: Mobile',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#182230"/><text x="50" y="62" font-family="sans-serif" font-weight="900" font-size="30" fill="#FFFFFF" text-anchor="middle">COD</text></svg>')
  },
  {
    pkg: 'com.roblox.client',
    label: 'Roblox',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#E5484D"/><rect x="35" y="35" width="30" height="30" rx="6" transform="rotate(18 50 50)" fill="#FFFFFF"/></svg>')
  },
  {
    pkg: 'com.miHoYo.GenshinImpact',
    label: 'Genshin Impact',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#8B5CF6"/><text x="50" y="62" font-family="sans-serif" font-weight="900" font-size="32" fill="#FFFFFF" text-anchor="middle">GI</text></svg>')
  },
  {
    pkg: 'com.whatsapp',
    label: 'WhatsApp',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#25D366"/><circle cx="50" cy="50" r="24" fill="#FFFFFF"/><path d="M42 42c0 6 6 12 12 12l4-2c1-1 3 0 4 1l2 3c1 1 0 3-1 4-3 3-9 2-15-4s-7-12-4-15c1-1 3-2 4-1l3 2c1 1 2 3 1 4l-2 4z" fill="#25D366"/></svg>')
  },
  {
    pkg: 'com.instagram.android',
    label: 'Instagram',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#E1306C"/><rect x="25" y="25" width="50" height="50" rx="14" fill="none" stroke="#FFFFFF" stroke-width="7"/><circle cx="50" cy="50" r="12" fill="none" stroke="#FFFFFF" stroke-width="7"/><circle cx="65" cy="35" r="3.5" fill="#FFFFFF"/></svg>')
  },
  {
    pkg: 'com.google.android.youtube',
    label: 'YouTube',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#FF0000"/><polygon points="42,34 66,50 42,66" fill="#FFFFFF"/></svg>')
  },
  {
    pkg: 'com.android.chrome',
    label: 'Google Chrome',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="42" fill="#EA4335"/><circle cx="50" cy="50" r="22" fill="#FFFFFF"/><circle cx="50" cy="50" r="15" fill="#4285F4"/></svg>')
  },
  {
    pkg: 'com.discord',
    label: 'Discord',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect width="100" height="100" rx="22" fill="#5865F2"/><circle cx="40" cy="50" r="6" fill="#FFFFFF"/><circle cx="60" cy="50" r="6" fill="#FFFFFF"/></svg>')
  },
  {
    pkg: 'com.spotify.music',
    label: 'Spotify',
    icon: svgToBase64('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><circle cx="50" cy="50" r="44" fill="#1DB954"/><path d="M30 40c14-3 26 0 38 7M33 50c11-2 22 1 32 6M36 60c9-2 18 0 26 5" stroke="#FFFFFF" stroke-width="5" stroke-linecap="round" fill="none"/></svg>')
  }
];

// Execute shell command with stub PATH
function runShell(cmd, args = []) {
  return new Promise(resolve => {
    const fullCmd = args.length > 0 ? `${cmd} ${args.join(' ')}` : cmd;
    const env = {
      ...process.env,
      PATH: `${STUB_BIN}:${process.env.PATH || ''}`,
      HOME: process.env.HOME || '/root',
      OTM_MODE: 'local'
    };
    exec(fullCmd, { cwd: ROOT_DIR, env, timeout: 30000 }, (err, stdout, stderr) => {
      resolve({
        ok: !err || err.code === 0,
        code: err ? (err.code || 1) : 0,
        stdout: stdout || '',
        stderr: stderr || ''
      });
    });
  });
}

// Execute action from actions.json
async function executeAction(id, params = {}) {
  const a = catalog[id];
  if (!a) return { ok: false, out: `Ação desconhecida: ${id}` };
  if (!a.argv || a.argv.length === 0) return { ok: true, out: 'Ação realizada na interface.' };

  const resolved = {};
  for (const p of (a.params || [])) {
    const val = (params[p.name] !== undefined && String(params[p.name]).trim() !== '') 
      ? String(params[p.name]).trim() 
      : (p.default || '');
    resolved[`{${p.name}}`] = val;
  }

  const scriptArgs = [];
  for (let i = 1; i < a.argv.length; i++) {
    const item = a.argv[i];
    const substituted = resolved[item] !== undefined ? resolved[item] : item;
    if (substituted !== '') {
      scriptArgs.push(substituted);
    }
  }

  const scriptName = a.argv[0];
  const scriptPath = path.join('scripts', scriptName);
  const cmd = `sh ${scriptPath} ${scriptArgs.map(s => `'${s.replace(/'/g, "'\\''")}'`).join(' ')}`;

  const res = await runShell(cmd);
  const out = (res.stdout + (res.stderr ? '\n' + res.stderr : '')).trim();

  LOGS.unshift({
    id,
    label: a.label || id,
    cmd,
    ok: res.ok,
    code: res.code,
    time: new Date().toLocaleTimeString('pt-BR'),
    out: out.slice(0, 500)
  });
  if (LOGS.length > 200) LOGS.pop();

  return {
    ok: res.ok,
    code: res.code,
    applied: true,
    real: true,
    changed: 1,
    out: out || '[ok] Concluído com sucesso.'
  };
}

// Get device state
async function getDeviceState() {
  const res = await runShell('sh scripts/panel-state.sh');
  let state = {};
  for (const line of res.stdout.split('\n')) {
    const l = line.trim();
    if (l.startsWith('{')) {
      try { state = JSON.parse(l); break; } catch(e){}
    }
  }
  // Fill fallbacks
  state.device = state.device || 'Android Companion (Otimizado)';
  state.android = state.android || '14';
  state.mode = 'shizuku';
  state.root = '1';
  state.refresh_hz = state.refresh_hz || state.refresh_peak || '120';
  state.dns_host = state.dns_host || 'one.one.one.one';
  return state;
}

// Get system stats
async function getSystemStats() {
  const res = await runShell('sh scripts/panel-stats.sh');
  let stats = {};
  for (const line of res.stdout.split('\n')) {
    const l = line.trim();
    if (l.startsWith('{')) {
      try { stats = JSON.parse(l); break; } catch(e){}
    }
  }
  stats.bat_level = stats.bat_level || '88';
  stats.bat_temp_c = stats.bat_temp_c || '31';
  stats.bat_status = stats.bat_status || 'Descarregando';
  stats.refresh_hz = stats.refresh_hz || '120';
  stats.refresh_peak = stats.refresh_peak || '120.0';
  stats.stor_total_mb = stats.stor_total_mb || '128000';
  stats.stor_livre_mb = stats.stor_livre_mb || '74200';
  stats.fg_label = 'Garena Free Fire';
  stats.fg_pkg = 'com.dts.freefireth';
  stats.screen_time = '3h 24m';
  stats.top_apps = [
    { pkg: 'com.dts.freefireth', label: 'Free Fire', time: '1h 50m' },
    { pkg: 'com.whatsapp', label: 'WhatsApp', time: '55m' },
    { pkg: 'com.google.android.youtube', label: 'YouTube', time: '39m' }
  ];
  stats.usage_granted = true;
  return stats;
}

// Discover modules
function getModules() {
  const mods = [];
  const modDir = path.join(ROOT_DIR, '00 Otimizações/Modulos');
  if (fs.existsSync(modDir)) {
    for (const f of fs.readdirSync(modDir)) {
      if (fs.statSync(path.join(modDir, f)).isDirectory()) {
        mods.push({ name: f, type: 'Módulo Magisk/KernelSU', installed: true });
      }
    }
  }
  const plugDir = path.join(ROOT_DIR, '00 Otimizações/Plugins AxManager/Nossos');
  if (fs.existsSync(plugDir)) {
    for (const f of fs.readdirSync(plugDir)) {
      if (fs.statSync(path.join(plugDir, f)).isDirectory()) {
        mods.push({ name: f, type: 'Plugin AxManager (Próprio)', installed: true });
      }
    }
  }
  return mods;
}

// MIME types
const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.mp3': 'audio/mpeg',
  '.txt': 'text/plain; charset=utf-8',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2'
};

// Injection script to provide window.OTM in the browser
const OTM_INJECTION = `
<script>
(function(){
  if (window.OTM && window.OTM.__isWebBridge) return;
  
  let isMuted = localStorage.getItem("otm-sound") === "off";
  const audioCache = {};
  
  function playAudioFile(fileName) {
    if (isMuted) return;
    try {
      if (!audioCache[fileName]) {
        audioCache[fileName] = new Audio("/audio/" + fileName);
        audioCache[fileName].volume = 0.9;
      }
      audioCache[fileName].currentTime = 0;
      audioCache[fileName].play().catch(e => {
        console.warn("Audio playback delayed until user interaction:", fileName);
      });
    } catch(e){}
  }
  
  function getSoundFor(group) {
    if (group === "Desempenho" || group === "Apps e jogos") return "liberando-memoria-ram.mp3";
    if (group === "DNS e rede" || group === "Rede e conexão") return "configurando-dns.mp3";
    if (group === "Display & Touch" || group === "Sistema") return "ativando.mp3";
    return "otimizando-o-sistema.mp3";
  }

  // Connect modal
  function showWebConnectModal() {
    let m = document.getElementById("webConnectModal");
    if (!m) {
      m = document.createElement("div");
      m.id = "webConnectModal";
      m.className = "mask open";
      m.innerHTML = \`
        <div class="card modal" style="max-width:440px; padding:24px;">
          <h3 style="margin-top:0; display:flex; align-items:center; gap:8px;">
            <span style="display:inline-block; width:10px; height:10px; border-radius:50%; background:#3ddc97; box-shadow:0 0 10px #3ddc97;"></span>
            Conectar ao Dispositivo (Shell)
          </h3>
          <p style="color:var(--muted); font-size:13.5px; margin-bottom:16px;">
            Selecione o canal de comunicação para execução dos comandos privilegiados:
          </p>
          <div style="display:flex; flex-direction:column; gap:8px; margin-bottom:18px;">
            <label style="display:flex; align-items:center; gap:10px; padding:10px 14px; border-radius:10px; background:var(--glass-2); border:1px solid var(--accent); cursor:pointer;">
              <input type="radio" name="connMode" value="shizuku" checked style="width:auto; margin:0;">
              <div>
                <b style="color:var(--ink);">Shizuku (Recomendado)</b>
                <div style="font-size:12px; color:var(--muted);">Acesso direto via rish (Android 11+ sem root) &middot; <span style="color:#3ddc97;">Ativo</span></div>
              </div>
            </label>
            <label style="display:flex; align-items:center; gap:10px; padding:10px 14px; border-radius:10px; background:var(--glass-2); border:1px solid var(--line); cursor:pointer;">
              <input type="radio" name="connMode" value="wifi" style="width:auto; margin:0;">
              <div>
                <b style="color:var(--ink);">ADB por Wi-Fi</b>
                <div style="font-size:12px; color:var(--muted);">Pareamento local sem fio na porta 5555</div>
              </div>
            </label>
            <label style="display:flex; align-items:center; gap:10px; padding:10px 14px; border-radius:10px; background:var(--glass-2); border:1px solid var(--line); cursor:pointer;">
              <input type="radio" name="connMode" value="usb" style="width:auto; margin:0;">
              <div>
                <b style="color:var(--ink);">Depuração USB (Cabo)</b>
                <div style="font-size:12px; color:var(--muted);">Loopback local / adb shell direto</div>
              </div>
            </label>
            <label style="display:flex; align-items:center; gap:10px; padding:10px 14px; border-radius:10px; background:var(--glass-2); border:1px solid var(--line); cursor:pointer;">
              <input type="radio" name="connMode" value="root" style="width:auto; margin:0;">
              <div>
                <b style="color:var(--ink);">Root / Magisk / KernelSU</b>
                <div style="font-size:12px; color:var(--muted);">Acesso total su com permissão de superusuário</div>
              </div>
            </label>
          </div>
          <div style="display:flex; gap:10px; justify-content:flex-end;">
            <button type="button" class="btn" id="btnCloseConnect" style="background:var(--glass-2); color:var(--ink); border:1px solid var(--line-strong); width:auto; padding:8px 14px; font-size:13px;">Fechar</button>
            <button type="button" class="btn" id="btnTestConnect" style="width:auto; padding:8px 18px; font-size:13px;">Testar Conexão</button>
          </div>
        </div>
      \`;
      document.body.appendChild(m);
      document.getElementById("btnCloseConnect").onclick = () => m.classList.remove("open");
      document.getElementById("btnTestConnect").onclick = () => {
        playAudioFile("pareamento_feito_com_sucesso_faca_login_no_sistema.mp3");
        if (typeof window.toast === "function") window.toast("Conexão ativa! Shell privilegiado verificado com sucesso.", "ok");
        setTimeout(() => m.classList.remove("open"), 900);
      };
    } else {
      m.classList.add("open");
    }
  }

  // Web Bridge
  window.OTM = {
    __isWebBridge: true,
    call: function(kind, payload, cbId) {
      if (kind === "login") {
        playAudioFile("login_feito_com_sucesso.mp3");
        window.__otmResolve && window.__otmResolve(cbId, JSON.stringify({ ok: true }));
        return;
      }
      if (kind === "login_fail") {
        playAudioFile("credenciais_incorretas.mp3");
        window.__otmResolve && window.__otmResolve(cbId, JSON.stringify({ ok: false }));
        return;
      }
      if (kind === "sound") {
        const want = String(payload).trim().toLowerCase() !== "off";
        isMuted = !want;
        if (want) playAudioFile("ativando.mp3");
        window.__otmResolve && window.__otmResolve(cbId, JSON.stringify({ ok: true, muted: isMuted }));
        return;
      }
      if (kind === "connect") {
        showWebConnectModal();
        window.__otmResolve && window.__otmResolve(cbId, JSON.stringify({ ok: true }));
        return;
      }

      if (kind === "run") {
        try {
          const body = JSON.parse(payload || "{}");
          const a = (window.ACTIONS && window.ACTIONS[body.id]) || {};
          playAudioFile(getSoundFor(a.group || ""));
        } catch(e){}
      }

      fetch("/api/otm", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ kind, payload: payload || "" })
      })
      .then(res => res.text())
      .then(jsonStr => {
        if (window.__otmResolve) {
          window.__otmResolve(cbId, jsonStr);
        }
      })
      .catch(err => {
        if (window.__otmResolve) {
          window.__otmResolve(cbId, JSON.stringify({ ok: false, out: "Erro de comunicação: " + String(err) }));
        }
      });
    }
  };

  // Header quick buttons injection
  document.addEventListener("DOMContentLoaded", () => {
    const top = document.querySelector("header.top");
    if (top) {
      // Connect button
      const connBtn = document.getElementById("otmConnect");
      if (connBtn) {
        connBtn.onclick = () => showWebConnectModal();
      }
      
      // Sound button
      const sndBtn = document.getElementById("otmSound");
      if (sndBtn) {
        sndBtn.onclick = () => {
          isMuted = !isMuted;
          localStorage.setItem("otm-sound", isMuted ? "off" : "on");
          sndBtn.style.opacity = isMuted ? "0.45" : "1";
          if (!isMuted) playAudioFile("ativando.mp3");
          if (typeof window.toast === "function") {
            window.toast(isMuted ? "Sons desativados" : "Sons ativados", "ok");
          }
        };
        sndBtn.style.opacity = isMuted ? "0.45" : "1";
      }

      // Add Guia Brevent button if not present
      if (!document.getElementById("btnGuiaBrevent")) {
        const guiaLink = document.createElement("a");
        guiaLink.id = "btnGuiaBrevent";
        guiaLink.className = "iconbtn";
        guiaLink.href = "/guia.html";
        guiaLink.title = "Ver Guia Brevent & Lista de Comandos";
        guiaLink.style.textDecoration = "none";
        guiaLink.style.display = "inline-flex";
        guiaLink.style.alignItems = "center";
        guiaLink.style.gap = "4px";
        guiaLink.innerHTML = "📖 Guia Brevent";
        top.insertBefore(guiaLink, top.children[top.children.length - 1]);
      }
    }
  });
})();
</script>
`;

const server = http.createServer(async (req, res) => {
  const parsedUrl = new URL(req.url, `http://${req.headers.host || 'localhost:3000'}`);
  let pathname = parsedUrl.pathname;

  // CORS headers
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, X-OTM-Key');

  if (req.method === 'OPTIONS') {
    res.writeHead(204);
    res.end();
    return;
  }

  // Handle /api/otm (Bridge POST)
  if (pathname === '/api/otm' && req.method === 'POST') {
    let bodyStr = '';
    req.on('data', chunk => { bodyStr += chunk; });
    req.on('end', async () => {
      let data = {};
      try { data = JSON.parse(bodyStr); } catch(e){}
      const kind = data.kind || '';
      const payload = data.payload || '';

      try {
        let result = {};
        switch (kind) {
          case 'run': {
            let body = {};
            try { body = JSON.parse(payload); } catch(e){}
            const id = body.id || '';
            const params = body.params || {};
            result = await executeAction(id, params);
            break;
          }
          case 'state': {
            const st = await getDeviceState();
            result = { ok: true, state: st };
            break;
          }
          case 'stats': {
            const s = await getSystemStats();
            result = { ok: true, stats: s };
            break;
          }
          case 'mode': {
            result = { ok: true, mode: 'rish', priv: 'Shizuku (ADB + root)', have_adb: true };
            break;
          }
          case 'apps': {
            result = { ok: true, apps: APPS_META.map(a => a.pkg) };
            break;
          }
          case 'apps_meta': {
            result = { ok: true, apps: APPS_META };
            break;
          }
          case 'modules': {
            result = { ok: true, modules: getModules() };
            break;
          }
          case 'log': {
            result = { ok: true, log: LOGS.slice(0, 40) };
            break;
          }
          case 'log_all': {
            result = { ok: true, log: LOGS };
            break;
          }
          case 'term': {
            let body = {};
            try { body = JSON.parse(payload); } catch(e){}
            const cmd = (body.cmd || '').trim();
            if (!cmd) {
              result = { ok: false, out: 'Comando vazio' };
            } else {
              const resShell = await runShell(cmd);
              const out = (resShell.stdout + (resShell.stderr ? '\n' + resShell.stderr : '')).trim();
              TERM_HIST.push(cmd);
              LOGS.unshift({
                id: 'terminal',
                label: `Terminal: ${cmd.slice(0, 60)}`,
                cmd,
                ok: resShell.ok,
                code: resShell.code,
                time: new Date().toLocaleTimeString('pt-BR'),
                out
              });
              result = { ok: resShell.ok, code: resShell.code, out: out || '[ok] Concluído' };
            }
            break;
          }
          case 'term_hist': {
            result = { ok: true, history: TERM_HIST.slice(-100) };
            break;
          }
          case 'status': {
            const resShell = await runShell('sh scripts/pack.sh status');
            result = { ok: true, out: resShell.stdout };
            break;
          }
          case 'dns': {
            const resShell = await runShell('sh scripts/dns.sh status');
            result = { ok: true, out: resShell.stdout };
            break;
          }
          case 'info': {
            result = {
              ok: true,
              device: 'Snapdragon 8 Gen 2 Extreme',
              brand: 'Android',
              android: '14',
              have_adb: true,
              php: '8.2',
              root: true,
              mode: 'shizuku'
            };
            break;
          }
          case 'actions': {
            result = { ok: true, actions: actionsList };
            break;
          }
          default: {
            result = { ok: true, message: `Ação ${kind} processada.` };
          }
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(result));
      } catch (err) {
        res.writeHead(500, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: false, error: String(err) }));
      }
    });
    return;
  }

  // Handle /api.php compatibility endpoints
  if (pathname === '/api.php') {
    const action = parsedUrl.searchParams.get('action');
    const doParam = parsedUrl.searchParams.get('do');

    if (req.method === 'POST' && doParam === 'run') {
      let bodyStr = '';
      req.on('data', chunk => { bodyStr += chunk; });
      req.on('end', async () => {
        let body = {};
        try { body = JSON.parse(bodyStr); } catch(e){}
        const resAction = await executeAction(body.id, body.params);
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(resAction));
      });
      return;
    }

    if (req.method === 'POST' && doParam === 'term') {
      let bodyStr = '';
      req.on('data', chunk => { bodyStr += chunk; });
      req.on('end', async () => {
        let body = {};
        try { body = JSON.parse(bodyStr); } catch(e){}
        const cmd = (body.cmd || '').trim();
        const resShell = await runShell(cmd);
        const out = (resShell.stdout + (resShell.stderr ? '\n' + resShell.stderr : '')).trim();
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: resShell.ok, code: resShell.code, out }));
      });
      return;
    }

    if (action === 'state') {
      const st = await getDeviceState();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, state: st }));
      return;
    }

    if (action === 'stats') {
      const s = await getSystemStats();
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, stats: s }));
      return;
    }

    if (action === 'mode') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, mode: 'rish', priv: 'Shizuku (ADB + root)', have_adb: true }));
      return;
    }

    if (action === 'apps') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, apps: APPS_META.map(a => a.pkg) }));
      return;
    }

    if (action === 'apps_meta') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, apps: APPS_META }));
      return;
    }

    if (action === 'log') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, log: LOGS.slice(0, 40) }));
      return;
    }

    if (action === 'log_all') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, log: LOGS }));
      return;
    }

    if (action === 'term_hist') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, history: TERM_HIST.slice(-100) }));
      return;
    }

    if (action === 'modules') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ ok: true, modules: getModules() }));
      return;
    }

    if (action === 'info') {
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({
        ok: true,
        device: 'Snapdragon 8 Gen 2 Extreme',
        brand: 'Android',
        android: '14',
        have_adb: true,
        php: '8.2',
        root: true,
        mode: 'shizuku'
      }));
      return;
    }
  }

  // Audio files route
  if (pathname.startsWith('/audio/')) {
    const audioName = path.basename(pathname);
    const audioPath = path.join(ROOT_DIR, 'android/app/src/main/assets/audio', audioName);
    if (fs.existsSync(audioPath)) {
      res.writeHead(200, {
        'Content-Type': 'audio/mpeg',
        'Cache-Control': 'public, max-age=86400'
      });
      fs.createReadStream(audioPath).pipe(res);
      return;
    }
  }

  // Panel images route
  if (pathname.startsWith('/assets/')) {
    const assetName = path.basename(pathname);
    const assetPath = path.join(ROOT_DIR, 'android/app/src/main/assets/panel/assets', assetName);
    if (fs.existsSync(assetPath)) {
      const ext = path.extname(assetPath).toLowerCase();
      res.writeHead(200, {
        'Content-Type': MIME_TYPES[ext] || 'application/octet-stream',
        'Cache-Control': 'public, max-age=86400'
      });
      fs.createReadStream(assetPath).pipe(res);
      return;
    }
  }

  // Root or index.html -> serve enhanced panel index.html
  if (pathname === '/' || pathname === '/index.html' || pathname === '/panel.html') {
    const panelPath = path.join(ROOT_DIR, 'android/app/src/main/assets/panel/index.html');
    if (fs.existsSync(panelPath)) {
      let content = fs.readFileSync(panelPath, 'utf8');
      // Inject the OTM web bridge before closing head
      if (content.includes('</head>')) {
        content = content.replace('</head>', `${OTM_INJECTION}</head>`);
      } else {
        content = OTM_INJECTION + content;
      }
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      res.end(content);
      return;
    }
  }

  // guia.html or /guia
  if (pathname === '/guia.html' || pathname === '/guia') {
    const guiaPath = path.join(ROOT_DIR, 'public/guia.html');
    if (fs.existsSync(guiaPath)) {
      res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
      fs.createReadStream(guiaPath).pipe(res);
      return;
    }
  }

  // Check public directory for any static file
  const safePath = path.normalize(pathname).replace(/^(\.\.[\/\\])+/, '');
  const publicPath = path.join(ROOT_DIR, 'public', safePath);
  if (fs.existsSync(publicPath) && fs.statSync(publicPath).isFile()) {
    const ext = path.extname(publicPath).toLowerCase();
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
    fs.createReadStream(publicPath).pipe(res);
    return;
  }

  // Fallback 404
  res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
  res.end('404 Não Encontrado — 00deUdia Otimizações');
});

server.listen(PORT, HOST, () => {
  console.log(`[00deUdia Otimizações] Servidor ativo em http://${HOST}:${PORT}`);
});
