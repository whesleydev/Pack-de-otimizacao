// property by kazuyoo
import { exec, toast } from 'https://cdn.jsdelivr.net/npm/kernelsu@1.0.6/+esm';

const SCRIPT_NAME   = "kazuyoo";
const TEMP_FILE     = "/data/local/tmp/gamelist.txt";
const GAMELIST_BACKUP = "/data/adb/kazuyoo_gamelist.txt";

let Elements        = {};
let isSecondaryActive  = false;
let currentUtilityType = null;
let _gameListLocked    = false;
let _monitorTimer      = null;
let cachedScriptPath   = null;
let scriptPathResolved = false;

const utilityConfigs = {
  'Refresh Rate':    { key: 'refresh',     opts: ["Default","60Hz","90Hz","120Hz","144Hz"] },
  'Composition Type':{ key: 'composition', opts: ["Default","gpu","cpu","dyn","hwc","c2d","mdp"] },
  'Game Driver':     { key: 'driver',      opts: ["Default","GameDriver","AngleNative"] },
  'Renderer Engine': { key: 'renderer',    opts: ["Default","skiagl","skiavk"] }
};

const SPECIAL_VALUE_KEYS = new Set(["composition","renderer","refresh","driver","dns_private"]);
const SKIP_RESTORE_KEYS  = new Set(["app_logs", "_module_ver", "last_sync_uptime", "first_install_run"]);

const safeExec = async (cmd, fallback = "") => {
  try { return (await exec(cmd)).stdout.trim(); }
  catch { return fallback; }
};

const getScriptPath = async () => {
  if (scriptPathResolved && cachedScriptPath) return cachedScriptPath;
  if ((await safeExec(`[ -f "${SCRIPT_NAME}" ] && echo 1`, "0")) === "1") {
    cachedScriptPath = SCRIPT_NAME;
    scriptPathResolved = true;
    return cachedScriptPath;
  }
  const path = (await safeExec(`command -v "${SCRIPT_NAME}"`, "")).trim();
  if (path) {
    cachedScriptPath = path;
    scriptPathResolved = true;
  }
  return cachedScriptPath;
};

const safeExecScript = async (command, value = "", silent = false) => {
  try {
    const script = await getScriptPath();
    if (!script) return "";
    const args   = value ? `${command} ${value}` : command;
    const useShell = !script.startsWith("/system/bin");
    const cmd    = useShell ? `sh ${script} ${args} 2>&1` : `${script} ${args} 2>&1`;
    const result = await exec(cmd);
    if (!silent) {
      const s = value === "on" || value === "trigger" ? "on"
              : value === "off" ? "off" : "success";
      window.addLog(`${command.toUpperCase()}: ${value || "Executed"}`, s);
    }
    return result.stdout.trim();
  } catch (err) { console.error(err); return ""; }
};

const applyJobSchedulerLimit = async (on) => {
  if (on) {
    await safeExec(`settings put global job_scheduler_constants "min_latency=7200000,max_latency=86400000,max_batch_delay=14400000,background_settle_time=60000,conn_congestion_delay=900000,conn_prefetch_relax=false,min_ready_non_active_jobs_count=10,max_cpu_only_job_batch_delay_ms=14400000,max_non_active_job_batch_delay_ms=14400000,standby_heartbeat=1800000,min_exp_backoff_time_ms=120000,system_stop_to_failure_ratio=1"`, "");
    await safeExec(`settings put global job_scheduler_time_controller_constants "active=3600000,working=10800000,frequent=21600000,rare=43200000,never=86400000"`, "");
    await safeExec(`settings put global job_scheduler_quota_controller_constants "max_job_count_active=5,max_job_count_working=3,max_job_count_frequent=1,max_job_count_rare=1,max_job_count_restricted=0,ej_limit_active_ms=30000,rate_limiting_window_ms=3600000,max_job_count_per_rate_limiting_window=5"`, "");
  } else {
    await safeExec("settings put global job_scheduler_constants 0", "");
    await safeExec("settings put global job_scheduler_time_controller_constants 0", "");
    await safeExec("settings put global job_scheduler_quota_controller_constants max_job_count_per_rate_limiting_window=10,rate_limiting_window_ms=60000,max_job_count_active=75,max_session_count_active=75", "");
  }
};

const applyStoragePressure = async (on) => {
  await safeExec(on ? "cmd devicestoragemonitor force-not-low" : "cmd devicestoragemonitor reset", "");
};

window.openSubTemplate = (pageTitle, templateId, callback = null) => {
  const secondary = document.getElementById('sub-page-secondary');
  if (secondary) secondary.classList.remove('active');
  isSecondaryActive  = false;
  currentUtilityType = null;

  const template = document.getElementById(templateId);
  const overlay  = document.getElementById('sub-page-overlay');
  const body     = document.getElementById('sub-page-body');
  const title    = document.getElementById('sub-page-title');
  if (!template || !overlay) return;

  title.innerText  = pageTitle;
  body.innerHTML   = template.innerHTML;
  overlay.classList.add('active');
  document.body.style.overflow = 'hidden';
  window.history.pushState({ page: 'subpage' }, '');
  if (callback) setTimeout(callback, 50);
};

window.closeSubPage = () => {
  const overlay = document.getElementById('sub-page-overlay');
  if (!overlay) return;
  overlay.classList.remove('active');
  document.body.style.overflow = 'scroll';
  if (window.history.state?.page === 'subpage') window.history.back();
  currentUtilityType = null;
};

window.handleBack = () => {
  const secondary = document.getElementById('sub-page-secondary');
  if (secondary?.classList.contains('active')) {
    secondary.classList.remove('active');
    document.getElementById('sub-page-title').innerText = "Utility Tool";
    isSecondaryActive  = false;
    currentUtilityType = null;
  } else {
    window.closeSubPage();
  }
};

function renderUtilityOptions(type) {
  const secondary     = document.getElementById('sub-page-secondary');
  const secondaryBody = document.getElementById('secondary-body');
  if (!secondary || !secondaryBody) return;

  const config = utilityConfigs[type];
  if (!config) { toast('Utility not available'); return; }

  currentUtilityType = type;
  const current = localStorage.getItem(config.key) || "Default";

  secondaryBody.innerHTML = `<div style="display:flex;flex-direction:column;gap:8px;padding:16px;">` +
    config.opts.map(opt => {
      const active = current === opt;
      const bullet = active
        ? 'width:14px;height:14px;border-radius:50%;background:var(--m3-primary);transition:all .2s'
        : 'width:14px;height:14px;border-radius:50%;background:transparent;border:2px solid var(--m3-outline);transition:all .2s';
      return `<div class="list-card-alt" onclick="window.selectUtilityOption('${config.key}','${opt}')"
        style="display:flex;justify-content:space-between;align-items:center;padding:16px;
               border-radius:28px;background:var(--m3-surface-container);cursor:pointer;
               border:1px solid var(--m3-outline-variant);">
        <span style="color:var(--m3-on-surface);font-weight:500;">${opt}</span>
        <span style="${bullet}"></span>
      </div>`;
    }).join('') + `</div>`;

  secondary.classList.add('active');
  isSecondaryActive = true;
}

window.openSettingsPage = (type, fromUtility = false) => {
  if (type === "Utility Tool") {
    window.openSubTemplate("Utility Tool", "utility-template", () => {
      const ids = {
        'silent-log-toggle':  'disable_logging',
        'sensor-toggle':      'dis_sensor',
        'network-toggle':     'network_adjuster',
        'dev-conf-toggle':    'dev_conf',
      };
      for (const [id, key] of Object.entries(ids)) {
        const el = document.getElementById(id);
        if (!el) continue;
        el.checked  = localStorage.getItem(key) === "on";
        el.onchange = e => window.toggleAction(key, e.target.checked);
      }
      const gmsToggle = document.getElementById("gms-toggle");
      if (gmsToggle) {
        gmsToggle.checked  = localStorage.getItem("gms_doze") === "on";
        gmsToggle.onchange = e => {
          const checked = e.target.checked;
          e.target.checked = false;
          if (checked) {
            window.showGmsWarning(() => {
              gmsToggle.checked = true;
              window.toggleAction("gms_doze", true);
            });
          } else {
            window.toggleAction("gms_doze", false);
          }
        };
      }
      initGapStatus();
    });

  } else if (type === "Logging") {
    window.openSubTemplate("Logging Info", "logging-template", () => {
      const logs = JSON.parse(localStorage.getItem("app_logs") || "[]");
      renderLogs(logs, document.getElementById("log-display"));
      document.getElementById("clear-logs-btn").onclick = () => window.clearAllLogs();
    });

  } else if (type === "Service Manager") {
    window.openSubTemplate("Service Manager", "server-template", async () => {
      await initServerStatus();
      const btn = document.getElementById('server-restart-btn');
      if (btn) btn.onclick = window.reloadServer;
    });

  } else if (utilityConfigs[type] && fromUtility) {
    document.getElementById('sub-page-title').innerText = type;
    renderUtilityOptions(type);
  }
};

window.selectUtilityOption = async (key, value) => {
  const secondaryBody = document.getElementById('secondary-body');
  secondaryBody?.querySelectorAll('.list-card-alt').forEach(div => {
    const textSpan = div.querySelector('span:first-child');
    const bullet   = div.querySelector('span:last-child');
    if (!textSpan || !bullet) return;
    const active = textSpan.innerText === value;
    Object.assign(bullet.style, {
      background:   active ? 'var(--m3-primary)' : 'transparent',
      border:       active ? 'none' : '2px solid var(--m3-outline)',
      width: '14px', height: '14px', borderRadius: '50%'
    });
  });
  await window.applySetting(key, value).catch(console.error);
};

window.applySetting = async (key, value, close = false) => {
  localStorage.setItem(key, value);
  const cmdVal  = value === "Default" ? "off" : value;
  const safeVal = cmdVal.replace(/'/g, "'\\''");
  await exec(`printf '%s' '${safeVal}' > /data/local/tmp/kazuyoo_${key}`);
  await safeExecScript(key, cmdVal);
  if (close) window.closeSubPage();
};

window.toggleAction = async (action, isCheckedOrString) => {
  const value = (isCheckedOrString === "on" || isCheckedOrString === "off")
    ? isCheckedOrString : (isCheckedOrString ? "on" : "off");
  localStorage.setItem(action, value);
  await safeExecScript(action, value);
};

window.showGmsWarning = (onConfirm) => {
  const overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;';
  overlay.innerHTML = `
    <div style="background:var(--m3-surface-container-high);border-radius:28px;padding:24px;margin:24px;width:calc(100% - 48px);max-width:360px;">
      <h3 style="margin:0 0 8px;font-size:16px;font-weight:600;color:var(--m3-on-surface);">Enable GMS Doze?</h3>
      <p style="margin:0 0 20px;font-size:13px;line-height:1.6;color:var(--m3-on-surface);opacity:.7;">
        Notifications from WhatsApp, Telegram, Instagram, YouTube, and other Google-based apps
        will experience delays. New notifications will come in when the app is opened manually.
      </p>
      <div style="display:flex;gap:8px;justify-content:flex-end;">
        <button id="gms-warn-cancel" class="m3-btn outlined" style="min-width:80px;">Cancel</button>
        <button id="gms-warn-confirm" class="m3-btn filled" style="min-width:80px;">Enable</button>
      </div>
    </div>`;
  document.body.appendChild(overlay);
  overlay.querySelector('#gms-warn-cancel').onclick  = () => document.body.removeChild(overlay);
  overlay.querySelector('#gms-warn-confirm').onclick = () => { document.body.removeChild(overlay); onConfirm(); };
  overlay.onclick = e => { if (e.target === overlay) document.body.removeChild(overlay); };
};

const checkGapInstalled = async () =>
  (await safeExec("command -v GAP 2>/dev/null", "")).trim() !== "";

const initGapStatus = async () => {
  const text = document.getElementById('gap-status-text');
  if (!text) return;
  const installed    = await checkGapInstalled();
  text.innerText     = installed ? "Module already installed" : "Tap to download module";
  text.style.color   = installed ? 'var(--m3-primary)' : '';
  text.style.opacity = installed ? '1' : '0.6';
};

window.showDownloadDialog = async () => {
  if (await checkGapInstalled()) { window.showGapStatus(); return; }
  const dialog = document.getElementById('download-dialog');
  if (dialog) { dialog.style.display = 'flex'; document.body.style.overflow = 'hidden'; }
};

window.showGapStatus = async () => {
  const pidRaw = await safeExec("cat /data/local/tmp/gap_server.pid 2>/dev/null", "");
  const pid    = pidRaw.trim();
  let isRunning = false, foundPid = "";

  if (pid) {
    const ok = await safeExec(`kill -0 ${pid} 2>/dev/null && echo 1 || echo 0`, "0");
    if (ok === "1") { isRunning = true; foundPid = pid; }
  }

  if (!isRunning) {
    const pg = await safeExec("pgrep -x GAP 2>/dev/null", "");
    if (pg.trim()) { isRunning = true; foundPid = pg.trim().split("\n")[0]; }
  }

  if (!isRunning) {
    const scan = await safeExec(`
      for p in /proc/[0-9]*; do
        cmdline=$(cat "$p/cmdline" 2>/dev/null | tr '\\0' ' ')
        case "$cmdline" in
          *GAP*|*/system/bin/GAP*)
            basename "$p"; break ;;
        esac
      done
    `, "");
    if (scan.trim()) { isRunning = true; foundPid = scan.trim(); }
  }

  const gameCount = isRunning
    ? await safeExec(`grep -vc '^#' ${TEMP_FILE} 2>/dev/null || echo 0`, "0")
    : "0";

  const overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;inset:0;z-index:99999;background:rgba(0,0,0,.5);display:flex;align-items:center;justify-content:center;';
  overlay.innerHTML = `
    <div style="background:var(--m3-surface-container-high);border-radius:28px;padding:24px;margin:24px;width:calc(100% - 48px);max-width:360px;">
      <h3 style="margin:0 0 16px;font-size:16px;font-weight:600;color:var(--m3-on-surface);">Game Preload Status</h3>
      <div style="display:flex;flex-direction:column;gap:10px;margin-bottom:20px;">
        ${[
          ['Status', isRunning ? `<span style="color:var(--m3-primary);font-weight:600;">Running</span>` : `<span style="color:var(--m3-error);font-weight:600;">Not Running</span>`],
          ['PID', foundPid || '-'],
          ['Games in list', gameCount.trim()]
        ].map(([label, val]) => `
          <div style="display:flex;justify-content:space-between;align-items:center;">
            <span style="font-size:13px;color:var(--m3-outline);">${label}</span>
            <span style="font-size:13px;font-weight:600;color:var(--m3-on-surface);">${val}</span>
          </div>`).join('')}
      </div>
      <div style="display:flex;justify-content:flex-end;">
        <button id="gap-status-close" class="m3-btn filled" style="min-width:80px;">OK</button>
      </div>
    </div>`;
  document.body.appendChild(overlay);
  overlay.querySelector('#gap-status-close').onclick = () => document.body.removeChild(overlay);
  overlay.onclick = e => { if (e.target === overlay) document.body.removeChild(overlay); };
};

window.closeDownloadDialog = () => {
  const dialog = document.getElementById('download-dialog');
  if (dialog) { dialog.style.display = 'none'; document.body.style.overflow = 'scroll'; }
};

window.goToDownload = async () => {
  window.closeDownloadDialog();
  await exec("am start -a android.intent.action.VIEW -d 'https://t.me/KzyoCh'");
};

const checkServiceRunning = async () => {
  const pidRaw = await safeExec("cat /data/local/tmp/svc_server.pid 2>/dev/null", "");
  const pid    = pidRaw.trim();
  if (pid) {
    const ok = await safeExec(`kill -0 ${pid} 2>/dev/null && echo 1 || echo 0`, "0");
    if (ok === "1") return true;
  }

  const pg = await safeExec("pgrep -f cgo_engine 2>/dev/null", "");
  if (pg.trim()) return true;

  const scan = await safeExec(`
    for p in /proc/[0-9]*; do
      cmdline=$(cat "$p/cmdline" 2>/dev/null | tr '\\0' ' ')
      case "$cmdline" in
        *cgo_engine*|*/system/bin/cgo_engine*)
          basename "$p"; break ;;
      esac
    done
  `, "");
  return scan.trim() !== "";
};

const updateServiceStatus = async () => {
  const running     = await checkServiceRunning();
  const statusTitle = document.getElementById('status-title');
  const statusDesc  = document.getElementById('status-desc');
  const statusCard  = document.getElementById('status-card');
  if (statusTitle) statusTitle.innerText = running ? "Running" : "Service not running";
  if (statusDesc)  statusDesc.innerText  = running ? "Process ID detected." : "Process ID was not detected.";
  if (statusCard) {
    statusCard.classList.remove('error-card','success-card');
    statusCard.classList.add(running ? 'success-card' : 'error-card');
    statusCard.style.borderLeft = running ? '4px solid #4caf50' : '4px solid #ff5252';
  }
};

const initServerStatus = async () => {
  const dot   = document.getElementById('server-svc-dot');
  const label = document.getElementById('server-svc-label');
  const card  = document.getElementById('server-status-card');
  if (!dot || !label) return;
  label.innerText = "Checking...";
  const running   = await checkServiceRunning();
  dot.style.background = running ? '#4caf50' : 'var(--m3-error)';
  dot.style.boxShadow  = running ? '0 0 8px #4caf5088' : '0 0 8px var(--m3-error)';
  label.innerText      = running ? 'Running' : 'Not running';
  if (card) card.style.borderLeft = running ? '4px solid #4caf50' : '4px solid var(--m3-error)';
};

window.reloadServer = async () => {
  const btn   = document.getElementById('server-restart-btn');
  const dot   = document.getElementById('server-svc-dot');
  const label = document.getElementById('server-svc-label');
  const card  = document.getElementById('server-status-card');

  if (btn) {
    btn.disabled = true; btn.style.opacity = '0.5';
    btn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"
      style="animation:spin .8s linear infinite;">
      <path d="M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8
               c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6
               s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/>
    </svg> Restarting...`;
  }
  if (dot)   { dot.style.background = '#ff9800'; dot.style.boxShadow = '0 0 8px #ff980088'; }
  if (label) label.innerText = "Restarting...";
  if (card)  card.style.borderLeft = '4px solid #ff9800';
  toast("Restarting service...");

  await safeExec(`
    pid=$(cat /data/local/tmp/svc_server.pid 2>/dev/null)
    [ -n "$pid" ] && kill -9 "$pid" 2>/dev/null
    pkill -9 -f cgo_engine 2>/dev/null
    rm -f /data/local/tmp/svc_server.pid
  `, "");
  await new Promise(r => setTimeout(r, 800));
  await safeExec(`cgo_engine --execute </dev/null >/dev/null 2>&1 &`, "");
  window.addLog("SERVER: cgo_engine restarted", "on");
  await new Promise(r => setTimeout(r, 1500));

  const running = await checkServiceRunning();
  if (dot)   { dot.style.background = running ? '#4caf50' : 'var(--m3-error)'; dot.style.boxShadow = running ? '0 0 8px #4caf5088' : '0 0 8px var(--m3-error)'; }
  if (label) label.innerText = running ? 'Running' : 'Failed to start';
  if (card)  card.style.borderLeft = running ? '4px solid #4caf50' : '4px solid var(--m3-error)';
  if (btn) {
    btn.disabled = false; btn.style.opacity = '1';
    btn.innerHTML = `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor">
      <path d="M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8
               c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6
               s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z"/>
    </svg> Restart`;
  }
  toast(running ? "Service restarted successfully!" : "Failed to start service");
  await updateServiceStatus();
};

const getRamStats = async () => {
  const raw = await safeExec("cat /proc/meminfo", "");
  if (!raw) return { used: 0, total: 0, percentage: 0 };
  const t = +raw.match(/MemTotal:\s+(\d+)/)?.[1]     || 0;
  const a = +raw.match(/MemAvailable:\s+(\d+)/)?.[1] || 0;
  const u = t - a;
  return { used: u/1048576, total: t/1048576, percentage: t ? (u/t)*100 : 0 };
};

const getStorageData = async () => {
  try {
    const raw = await safeExec("df -k /data | tail -1", "");
    if (!raw) return { total:"0.0", used:"0.0", percentage:0 };
    const p = raw.trim().split(/\s+/);
    return {
      total:   (parseFloat(p[1])/1048576).toFixed(1),
      used:    (parseFloat(p[2])/1048576).toFixed(1),
      percentage: Math.round((parseFloat(p[2])/parseFloat(p[1]))*100)
    };
  } catch { return { total:"0.0", used:"0.0", percentage:0 }; }
};

const getDeviceInfo = async () => {
  const out   = await safeExec("getprop ro.build.version.release; getprop ro.build.version.sdk; getprop ro.product.cpu.abilist; uname -r; getenforce", "");
  const lines = out.split("\n");
  const $ = id => document.getElementById(id);
  if ($('android-info')) $('android-info').innerText = `${lines[0]||'N/A'} (API ${lines[1]||'N/A'})`;
  if ($('abis-info'))    $('abis-info').innerText    = lines[2] || 'N/A';
  if ($('kernel-info'))  $('kernel-info').innerText  = lines[3] || 'N/A';
  if ($('selinux-info')) $('selinux-info').innerText = lines[4] || 'N/A';
};

const updateSystemStats = async () => {
  const [ram, st] = await Promise.all([getRamStats(), getStorageData()]);
  if (Elements.ramUsage)       Elements.ramUsage.innerText         = `${ram.used.toFixed(1)} / ${ram.total.toFixed(1)} GB`;
  if (Elements.ramBar)         Elements.ramBar.style.width         = `${ram.percentage}%`;
  if (Elements.storageTotal)   Elements.storageTotal.innerText     = `Total: ${st.total} GB`;
  if (Elements.storageUsed)    Elements.storageUsed.innerText      = `Used: ${st.used} GB`;
  if (Elements.usedStorageBar) Elements.usedStorageBar.style.width = `${st.percentage}%`;
};

const ensureGameListFile = async () => {
  const exists = await safeExec(`[ -s ${TEMP_FILE} ] && echo 1 || echo 0`, "0");
  if (exists === "0") {
    const hasBackup = await safeExec(`[ -f ${GAMELIST_BACKUP} ] && echo 1 || echo 0`, "0");
    await exec(hasBackup === "1" ? `cp ${GAMELIST_BACKUP} ${TEMP_FILE}` : `touch ${TEMP_FILE}`);
  }
};

const writeGameList = async (pkgMap) => {
  const lines  = Array.from(pkgMap.values());
  const tmpFile = `${TEMP_FILE}.tmp`;
  const content = lines.join("\\n");
  await safeExec(`printf '${content.replace(/'/g,"'\\''")}\n' > ${tmpFile} && mv ${tmpFile} ${TEMP_FILE}`, "");
  await safeExec(`cp ${TEMP_FILE} ${GAMELIST_BACKUP} 2>/dev/null`, "");
};

const readGameList = async () => {
  const raw = await safeExec(`cat ${TEMP_FILE}`, "");
  if (!raw) return new Map();
  const map = new Map();
  for (const line of raw.split('\n').map(l => l.replace(/\r/,'').trim()).filter(Boolean)) {
    map.set(line.replace(/^#+/,''), line);
  }
  return map;
};

window.toggleGameOpt = async (pkg, isEnabled) => {
  if (_gameListLocked) return;
  _gameListLocked = true;
  try {
    const map = await readGameList();
    map.set(pkg, isEnabled ? pkg : "#" + pkg);
    await writeGameList(map);
    await window.updateGameListUI();
  } catch(err) { console.error(err); toast("Failed to update game list"); await window.updateGameListUI(); }
  finally { _gameListLocked = false; }
};

window.addGameToList = async () => {
  const input = document.getElementById('add-game-input');
  const pkg   = input?.value.trim();
  if (!pkg || !pkg.includes('.')) { toast("Enter a valid package name (e.g. com.example.app)"); return; }
  if (_gameListLocked) return;
  _gameListLocked = true;
  try {
    const map = await readGameList();
    if (map.has(pkg)) { toast("Already in list"); return; }
    map.set(pkg, pkg);
    await writeGameList(map);
    if (input) input.value = "";
    await window.updateGameListUI();
  } catch(err) { console.error(err); toast("Failed to add game"); }
  finally { _gameListLocked = false; }
};

window.removeGameFromList = async (pkg) => {
  if (_gameListLocked) return;
  _gameListLocked = true;
  try {
    const map = await readGameList();
    map.delete(pkg);
    await writeGameList(map);
    await window.updateGameListUI();
    toast("Removed: " + pkg);
  } catch(err) { console.error(err); toast("Failed to remove game"); }
  finally { _gameListLocked = false; }
};

window.compileGame = (pkg) => {
  const mode = localStorage.getItem(`compile_mode_${pkg}`) || "unknown";
  if (mode === "unknown") { toast("Select a compile mode first"); return; }
  toast(`Compiling ${pkg}...`);
  exec(`setsid sh -c '
    sdk=$(getprop ro.build.version.sdk)
    if [ "$sdk" -ge 34 ]; then
      pm compile -m ${mode} -p PRIORITY_INTERACTIVE_FAST --full -f "${pkg}" 2>/dev/null
    else
      pm compile -m ${mode} "${pkg}" 2>/dev/null
    fi
  ' >/dev/null 2>&1 &`).catch(() => {});
};

window.setCompileMode = (pkg, mode) => {
  localStorage.setItem(`compile_mode_${pkg}`, mode);
  window.updateGameListUI();
};

window.toggleDnd = async (pkg, isEnabled) => {
  localStorage.setItem(`dnd_${pkg}`, isEnabled ? "on" : "off");
  await safeExec(`cmd notification ${isEnabled ? "allow_dnd" : "disallow_dnd"} "${pkg}" 2>/dev/null`, "");
};

window.updateGameListUI = async () => {
  const container = document.getElementById('game-list-container');
  if (!container) return;
  try {
    const map   = await readGameList();
    const lines = Array.from(map.values());

    let html = `<div style="display:flex;gap:8px;padding:12px 16px 8px;align-items:center;">
      <input id="add-game-input" type="text" placeholder="com.package.name"
        style="flex:1;padding:10px 14px;border-radius:20px;border:1px solid var(--m3-outline-variant);
               background:var(--m3-surface-container);color:var(--m3-on-surface);font-size:13px;outline:none;">
      <button onclick="window.addGameToList()"
        style="padding:10px 18px;border-radius:20px;border:none;background:var(--m3-primary);
               color:var(--m3-on-primary);font-size:13px;font-weight:600;cursor:pointer;">Add</button>
    </div>`;

    if (lines.length === 0) {
      html += '<p class="body-small" style="padding:12px 16px;text-align:center;color:var(--m3-on-surface-variant);">No games in list. Add one above.</p>';
      container.innerHTML = html;
      return;
    }

    html += '<div style="background:var(--m3-surface-container);border-radius:28px;margin:8px 16px 16px;border:1px solid var(--m3-outline-variant);overflow:hidden;">';
    lines.forEach((line, idx) => {
      const isEnabled = !line.startsWith("#");
      const pkgName   = line.replace(/^#+/,'').trim();
      const savedMode = localStorage.getItem(`compile_mode_${pkgName}`) || "unknown";
      const dndOn     = localStorage.getItem(`dnd_${pkgName}`) === "on";
      const border    = idx < lines.length-1 ? 'border-bottom:1px solid var(--m3-outline-variant);' : '';

      html += `<div style="padding:14px 20px;${border}">
        <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:10px;">
          <div style="flex:1;min-width:0;">
            <h3 style="margin:0;font-size:14px;font-weight:600;color:var(--m3-on-surface);overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${pkgName}</h3>
            <p style="margin:2px 0 0;font-size:11px;color:${savedMode==='unknown'?'var(--m3-on-surface-variant)':'var(--m3-primary)'};opacity:${savedMode==='unknown'?.5:1};">Mode: ${savedMode}</p>
          </div>
          <div style="display:flex;align-items:center;gap:6px;flex-shrink:0;">
            <button onclick="window.compileGame('${pkgName}')"
              style="display:flex;align-items:center;justify-content:center;width:32px;height:32px;
                     background:var(--m3-primary);border:none;border-radius:50%;cursor:pointer;" title="Compile">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="var(--m3-on-primary)"><path d="M8 5v14l11-7z"/></svg>
            </button>
            <label class="switch">
              <input type="checkbox" ${isEnabled?'checked':''} onchange="window.toggleGameOpt('${pkgName}',this.checked)">
              <span class="slider"></span>
            </label>
            <button onclick="window.removeGameFromList('${pkgName}')"
              style="display:flex;align-items:center;justify-content:center;width:32px;height:32px;
                     background:none;border:none;cursor:pointer;color:var(--m3-error);border-radius:50%;" title="Remove">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="currentColor">
                <path d="M19 6.41L17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z"/>
              </svg>
            </button>
          </div>
        </div>
        <div style="display:flex;gap:8px;align-items:center;justify-content:space-between;">
          <div style="display:flex;gap:6px;">
            ${['speed-profile','speed'].map(m => `
              <button onclick="window.setCompileMode('${pkgName}','${m}')"
                style="padding:5px 12px;border-radius:12px;font-size:11px;font-weight:600;cursor:pointer;transition:all .15s;
                       border:1px solid ${savedMode===m?'var(--m3-primary)':'var(--m3-outline-variant)'};
                       background:${savedMode===m?'var(--m3-primary)':'transparent'};
                       color:${savedMode===m?'var(--m3-on-primary)':'var(--m3-on-surface-variant)'};">${m}</button>`).join('')}
          </div>
          <div style="display:flex;align-items:center;gap:6px;">
            <span style="font-size:11px;opacity:.6;color:var(--m3-on-surface);">DND</span>
            <label class="switch" style="transform:scale(.85);transform-origin:right center;">
              <input type="checkbox" ${dndOn?'checked':''} onchange="window.toggleDnd('${pkgName}',this.checked)">
              <span class="slider"></span>
            </label>
          </div>
        </div>
      </div>`;
    });
    html += '</div>';
    container.innerHTML = html;
  } catch(err) {
    console.error(err);
    container.innerHTML = '<p class="body-small" style="padding:16px;text-align:center;color:var(--m3-error);">Error loading games.</p>';
  }
};

window.addLog = (message, status = null) => {
  if (typeof message !== "string") return;
  if (message.includes("[{") || message.startsWith("APP_LOGS")) return;
  const entry = { timestamp: new Date().toLocaleTimeString("en-GB",{hour12:false}), message, status };
  let logs = [];
  try { logs = JSON.parse(localStorage.getItem("app_logs")) || []; } catch { logs = []; }
  logs.unshift(entry);
  if (logs.length > 50) logs.length = 50;
  localStorage.setItem("app_logs", JSON.stringify(logs));
  const container = document.getElementById("log-display");
  if (container) renderLogs(logs, container);
};

function renderLogs(logs, container) {
  if (!Array.isArray(logs) || !logs.length) { container.textContent = "No logs yet."; return; }
  container.innerHTML = logs
    .filter(l => typeof l.message === "string")
    .map(l => {
      const s = String(l.status||"").toLowerCase();
      const c = s==="on"?"#4caf50":s==="off"?"#ff5252":"#ddd";
      return `<div>[${l.timestamp}] <span style="color:${c}">${l.message}</span></div>`;
    }).join("");
}

window.clearAllLogs = () => {
  localStorage.removeItem('app_logs');
  const d = document.getElementById('log-display');
  if (d) d.innerHTML = "Logs cleared.";
  toast("Logs cleared successfully");
};

window.runCleanRam = async () => {
  toast("Cleaning Background Apps...");
  await safeExecScript("clean_ram","trigger");
  toast("RAM Cleaned!");
  updateSystemStats();
};

window.runCleanCache = async () => {
  toast("Cleaning Cache...");
  await safeExecScript("clean_cache","trigger");
  toast("Cache cleaned successfully");
  updateSystemStats();
};

const setupControls = () => {
  document.querySelectorAll("select").forEach(sel => {
    const saved = localStorage.getItem(sel.id);
    if (saved) sel.value = saved;
    sel.onchange = async () => {
      localStorage.setItem(sel.id, sel.value);
      const cmd = sel.getAttribute("data-setting");
      if (cmd) await safeExecScript(cmd, sel.value);
    };
  });
};

const initTweaksListeners = () => {
  document.querySelectorAll('.list-card-alt, .card-action').forEach(card => {
    card.addEventListener('click', async () => {
      const title = (card.dataset.action
        || card.querySelector('h3')?.innerText?.trim()
        || card.querySelector('.card-title')?.innerText?.trim() || "").trim();
      if (!title) return;

      if (title === "Cleaning") {
        window.openSubTemplate("Cleaning", "cleaning-template", async () => {
          const [ram, st] = await Promise.all([getRamStats(), getStorageData()]);
          document.getElementById("cleanRamUsed").innerText     = `${Math.round(ram.used*1024)} MB`;
          document.getElementById("cleanRamBar").style.width    = `${ram.percentage}%`;
          document.getElementById("cleanStorageUsed").innerText = `${st.used} GB`;
          const bar = document.getElementById("cleanStorageBar");
          if (bar && st.total > 0) bar.style.width = `${Math.min(100,Math.round((parseFloat(st.used)/parseFloat(st.total))*100))}%`;

          const toggle = document.getElementById("ram-compact-toggle");
          if (toggle) {
            toggle.checked = localStorage.getItem("ram_compact") === "on";
            toggle.onchange = e => window.toggleAction("ram_compact", e.target.checked);
          }

          const jobSw = document.getElementById("job-scheduler-toggle");
          if (jobSw) {
            jobSw.checked = localStorage.getItem("job_scheduler_limit") === "on";
            jobSw.onchange = async e => {
              const on = e.target.checked;
              localStorage.setItem("job_scheduler_limit", on ? "on" : "off");
              await applyJobSchedulerLimit(on);
            };
          }

          document.getElementById("btnCleanRam").onclick   = window.runCleanRam;
          document.getElementById("btnCleanCache").onclick = window.runCleanCache;

          const spSw = document.getElementById("storage-pressure-toggle");
          if (spSw) {
            spSw.checked  = localStorage.getItem("storage_pressure") === "on";
            spSw.onchange = async e => {
              const on = e.target.checked;
              localStorage.setItem("storage_pressure", on ? "on" : "off");
              await applyStoragePressure(on);
            };
          }
        });

      } else if (title === "Downscaling") {
        window.openSubTemplate("Downscaling", "downscale-template", () => {
          const slider   = document.getElementById("render-slider");
          const scaleVal = document.getElementById("scale-val");
          slider.value   = localStorage.getItem("render_scale") || "1.00";
          scaleVal.innerText = slider.value + "x";
          slider.oninput = () => { scaleVal.innerText = slider.value + "x"; };
          document.getElementById("apply-downscale").onclick = async () => {
            localStorage.setItem("render_scale", slider.value);
            await safeExecScript("downscale", slider.value);
            toast("Applied: " + slider.value + "x — restart game to take effect");
          };
          document.getElementById("reset-downscale").onclick = async () => {
            slider.value = "1.00"; scaleVal.innerText = "1.00x";
            localStorage.setItem("render_scale","1.00");
            await safeExecScript("downscale","disable");
            toast("Downscale reset — restart game to take effect");
          };
        });

      } else if (title === "DNS Private") {
        window.openSubTemplate("DNS Private", "dns-template", () => {
          const select = document.getElementById("dns-select");
          select.value = localStorage.getItem("dns_private") || "Default";
          select.onchange = e => window.applySetting("dns_private", e.target.value);
        });

      } else if (title === "Utility Tool") {
        window.openSettingsPage('Utility Tool');
      } else if (title === "Service Manager") {
        window.openSettingsPage('Service Manager');
      } else if (utilityConfigs[title]) {
        window.openSettingsPage(title, true);
      }
    });
  });
};

const setDefaultStates = () => {
  ["saver","ram_compact","disable_logging","network_adjuster","gms_doze","dis_sensor"]
    .forEach(k => localStorage.setItem(k, "off"));
  localStorage.setItem("first_install_run","true");
};

const restoreSession = async () => {
  await new Promise(r => setTimeout(r, 1000));

  const reset = await safeExecScript("check_reset_flag","trigger",true);
  if (reset.trim() === "1") {
    localStorage.clear(); setDefaultStates();
    setTimeout(() => location.reload(), 500); return;
  }

  const moduleVer = await safeExec(
    "grep '^version=' /data/adb/modules/CelestialGameOpt/module.prop 2>/dev/null | cut -d= -f2", "");
  if (moduleVer && moduleVer !== localStorage.getItem("_module_ver")) {
    localStorage.clear();
    localStorage.setItem("_module_ver", moduleVer);
    setDefaultStates();
    setTimeout(() => location.reload(), 500); return;
  }

  const uptime     = parseInt(await safeExec("awk '{print int($1)}' /proc/uptime","0")) || 0;
  const lastUptime = parseInt(localStorage.getItem("last_sync_uptime") || "0");
  const isReboot   = uptime < lastUptime;

  document.querySelectorAll("select").forEach(sel => {
    const saved = localStorage.getItem(sel.id);
    if (saved) sel.value = saved;
  });

  if (isReboot) {
    const restoreCmds = [];
    const dndRestores = [];

    for (const [key, value] of Object.entries(localStorage)) {
      if (SKIP_RESTORE_KEYS.has(key) || key.startsWith("compile_mode_")) continue;

      if (key.startsWith("dnd_")) {
        if (value === "on") dndRestores.push(key.slice(4));
        continue;
      }
      if (key === "job_scheduler_limit") {
        if (value === "on" || value === "off") await applyJobSchedulerLimit(value === "on");
        continue;
      }
      if (key === "storage_pressure") {
        if (value === "on" || value === "off") await applyStoragePressure(value === "on");
        continue;
      }
      if (key === "render_scale") {
        if (value && value !== "1.00") restoreCmds.push(["downscale", value]);
        continue;
      }
      if (SPECIAL_VALUE_KEYS.has(key)) {
        if (value && value !== "off" && value !== "Default") restoreCmds.push([key, value]);
        continue;
      }
      if (value === "on" || value === "off") restoreCmds.push([key, value]);
    }

    for (const [key, value] of restoreCmds) {
      await safeExecScript(key, value);
    }
    for (const pkg of dndRestores) {
      await safeExec(`cmd notification allow_dnd "${pkg}" 2>/dev/null`, "");
    }
  }

  if (!localStorage.getItem("first_install_run")) setDefaultStates();
  localStorage.setItem("last_sync_uptime", uptime.toString());
};

const startMonitor = () => {
  if (_monitorTimer) clearTimeout(_monitorTimer);
  const tick = () => {
    updateSystemStats().finally(() => { _monitorTimer = setTimeout(tick, 4000); });
  };
  _monitorTimer = setTimeout(tick, 4000);
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && !_monitorTimer) {
      _monitorTimer = setTimeout(tick, 0);
    }
  });
};

document.addEventListener("DOMContentLoaded", () => {
  try {
    const raw = localStorage.getItem("app_logs");
    if (raw) {
      const logs = JSON.parse(raw);
      if (Array.isArray(logs)) {
        localStorage.setItem("app_logs", JSON.stringify(
          logs.map(l => typeof l === "string" ? { timestamp:"?", message:l, status:null } : l)
        ));
      }
    }
  } catch { localStorage.removeItem("app_logs"); }

  Elements = {
    ramUsage:       document.getElementById("ramUsage"),
    ramBar:         document.getElementById("ramBar"),
    storageTotal:   document.getElementById("storageTotal"),
    storageUsed:    document.getElementById("storageUsed"),
    usedStorageBar: document.getElementById("usedStorageBar"),
  };

  initTweaksListeners();
  setupControls();

  requestAnimationFrame(() => {
    Promise.all([updateServiceStatus(), getDeviceInfo()]).catch(console.error);
  });

  ensureGameListFile().then(() => window.updateGameListUI()).catch(console.error);
  restoreSession().catch(console.error);
  startMonitor();

  const saverBtn = document.getElementById('saver-toggle');
  if (saverBtn) {
    if (!localStorage.getItem('saver')) localStorage.setItem('saver','off');
    saverBtn.classList.toggle('active', localStorage.getItem('saver') === 'on');
    saverBtn.addEventListener('click', async () => {
      const next = !saverBtn.classList.contains('active');
      saverBtn.classList.toggle('active', next);
      await window.toggleAction('saver', next ? 'on' : 'off');
    });
  }
});

window.addEventListener('popstate', () => {
  if (document.getElementById('sub-page-overlay')?.classList.contains('active')) {
    window.closeSubPage();
  }
});

window.openUrl = async url => exec(`am start -a android.intent.action.VIEW -d '${url}'`);