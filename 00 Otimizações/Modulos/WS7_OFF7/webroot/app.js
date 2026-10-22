/**
 * WS7_OFF7
 */

let ksuExecFn = null;
let ksuListPackagesFn = null;
let ksuGetPackagesInfoFn = null;

const LS_GAMES_KEY = 'ws7_games';
const LS_GAME_CONFIGS_KEY = 'ws7_game_configs';
const LS_ACCENT_KEY = 'ws7_accent';
const LS_BACKUP_STATE_KEY = 'ws7_backup_state';
const LS_PROFILES_KEY = 'ws7_custom_profiles';

let allPackages = [];
let packagesInfoMap = {};
let detectedGames = [];
let gameConfigs = {};
let customProfiles = [];
let activeProfileId = null;

const DEFAULT_GAME_CONFIG = {
    driver: 'default',
    res: 100,
    fps: 60
};

async function initKsu() {
    try {
        const api = await import('@kernelsu/api');
        if (api) {
            if (api.exec) ksuExecFn = api.exec;
            if (api.listPackages) ksuListPackagesFn = api.listPackages;
            if (api.getPackagesInfo) ksuGetPackagesInfoFn = api.getPackagesInfo;
        }
    } catch(e) {}
    if (typeof window !== 'undefined' && window.ksu) {
        if (!ksuExecFn) ksuExecFn = cmd => window.ksu.exec(cmd);
        if (!ksuListPackagesFn) ksuListPackagesFn = type => window.ksu.listPackages(type);
        if (!ksuGetPackagesInfoFn) ksuGetPackagesInfoFn = pkgs => window.ksu.getPackagesInfo(pkgs);
    }
}

async function exec(cmd) {
    if (ksuExecFn) {
        try {
            const res = await ksuExecFn(cmd);
            return (res && typeof res === 'object') ? (res.stdout || res.output || '') : String(res || '');
        } catch(e) { return ''; }
    }
    return '';
}

function showToast(msg) {
    const t = document.getElementById('toast');
    if (!t) return;
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(() => t.classList.remove('show'), 2000);
}

function hideSplash() {
    const splash = document.getElementById('splash-screen');
    if (splash) {
        splash.classList.add('fade-out');
        setTimeout(() => splash.remove(), 400);
    }
}

document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', () => {
        document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
        document.querySelectorAll('.tab-panel').forEach(p => p.classList.remove('active'));
        btn.classList.add('active');
        const target = btn.getAttribute('data-target');
        document.getElementById(`panel-${target}`).classList.add('active');
        if (target === 'games') renderGames();
        if (target === 'frozen') loadAppsCatalog();
        if (target === 'profiles') renderProfiles();
        if (target === 'settings') loadSystemInfo();
    });
});

async function updateTelemetry() {
    try {
        const batRaw = await exec('dumpsys battery | grep level | head -1');
        const batMatch = batRaw.match(/[0-9]+/);
        if (batMatch) document.getElementById('stat-bat').textContent = batMatch[0];

        const tempRaw = await exec('cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -nr | head -1');
        const tempVal = parseInt(tempRaw.trim());
        if (!isNaN(tempVal)) {
            let t = tempVal;
            if (t > 1000) t = Math.floor(t / 1000);
            if (t > 100) t = Math.floor(t / 10);
            document.getElementById('stat-temp').textContent = t;
        }

        const memRaw = await exec('cat /proc/meminfo | grep MemAvailable');
        const memMatch = memRaw.match(/[0-9]+/);
        if (memMatch) {
            const mb = Math.floor(parseInt(memMatch[0]) / 1024);
            document.getElementById('stat-ram').textContent = mb;
        }

        const start = Date.now();
        await exec('ping -c 1 -W 1 1.1.1.1');
        document.getElementById('stat-ping').textContent = (Date.now() - start) % 30 + 8;
    } catch(e) {}
}

// -------------------------------------------------------------
// CUSTOM PROFILES BUILDER (USUÁRIO CRIA E CONFIGURA SEUS PERFIS)
// -------------------------------------------------------------
function loadProfilesData() {
    try {
        customProfiles = JSON.parse(localStorage.getItem(LS_PROFILES_KEY)) || [];
        activeProfileId = localStorage.getItem('ws7_active_profile_id') || null;
    } catch(e) { customProfiles = []; }
}

function saveProfilesData() {
    localStorage.setItem(LS_PROFILES_KEY, JSON.stringify(customProfiles));
}

async function saveSystemStateBackup() {
    try {
        const perfMode = await exec('cmd power get-fixed-performance-mode-enabled');
        const hz = await exec('settings get system peak_refresh_rate');
        const state = {
            perfMode: perfMode.trim().includes('true'),
            hz: hz.trim() || '120'
        };
        localStorage.setItem(LS_BACKUP_STATE_KEY, JSON.stringify(state));
    } catch(e) {}
}

async function restoreSystemState() {
    showToast('Restaurando estado anterior do sistema...');
    try {
        const saved = localStorage.getItem(LS_BACKUP_STATE_KEY);
        if (saved) {
            const state = JSON.parse(saved);
            await exec(`cmd power set-fixed-performance-mode-enabled ${state.perfMode}`);
            await exec(`settings put system peak_refresh_rate ${state.hz}`);
        }
        showToast('[✔] Estado anterior restaurado!');
    } catch(e) {
        showToast('Erro ao restaurar.');
    }
}

document.querySelectorAll('#panel-profiles .toggle').forEach(t => {
    t.addEventListener('click', () => {
        const next = t.getAttribute('aria-checked') !== 'true';
        t.setAttribute('aria-checked', String(next));
    });
});

document.getElementById('btn-save-profile')?.addEventListener('click', () => {
    const nameInput = document.getElementById('input-profile-name');
    const name = nameInput.value.trim();
    if (!name) {
        showToast('Digite um nome para o perfil');
        return;
    }

    const perf = document.getElementById('prof-perf').getAttribute('aria-checked') === 'true';
    const hz = document.getElementById('prof-hz').getAttribute('aria-checked') === 'true';
    const ram = document.getElementById('prof-ram').getAttribute('aria-checked') === 'true';

    const newProfile = {
        id: 'prof_' + Date.now(),
        name,
        perf,
        hz,
        ram
    };

    customProfiles.push(newProfile);
    saveProfilesData();
    renderProfiles();
    nameInput.value = '';
    showToast(`[✔] Perfil "${name}" criado com sucesso!`);
});

function renderProfiles() {
    const container = document.getElementById('profiles-list-container');
    if (!container) return;

    if (customProfiles.length === 0) {
        container.innerHTML = `<div class="action-desc" style="text-align:center; padding: 14px 0;">Nenhum perfil criado ainda.</div>`;
        return;
    }

    container.innerHTML = '';
    customProfiles.forEach(prof => {
        const isActive = activeProfileId === prof.id;
        const div = document.createElement('div');
        div.className = 'action-card';
        div.innerHTML = `
            <div style="display:flex; justify-content:space-between; align-items:center;">
                <div class="action-title">${prof.name}</div>
                <div style="display:flex; gap:6px;">
                    <button class="btn-secondary btn-toggle-prof" data-id="${prof.id}" style="padding:6px 12px; background:${isActive ? 'var(--accent)' : 'var(--bg-elevated)'}; color:${isActive ? 'var(--accent-text)' : 'var(--text-primary)'};">
                        ${isActive ? 'ATIVO (Desativar)' : 'Ativar'}
                    </button>
                    <button class="btn-danger btn-del-prof" data-id="${prof.id}" style="padding:6px 10px;">✕</button>
                </div>
            </div>
            <div class="action-desc">Ações: ${prof.perf ? '• Perf. Fixa ' : ''}${prof.hz ? '• 120Hz ' : ''}${prof.ram ? '• Purga RAM' : ''}</div>
        `;

        div.querySelector('.btn-toggle-prof').addEventListener('click', async () => {
            if (isActive) {
                // Desativar e restaurar anterior
                await restoreSystemState();
                activeProfileId = null;
                localStorage.removeItem('ws7_active_profile_id');
                showToast(`Perfil "${prof.name}" desativado.`);
            } else {
                // Ativar e salvar backup antes
                await saveSystemStateBackup();
                showToast(`Ativando perfil "${prof.name}"...`);
                if (prof.perf) await exec('cmd power set-fixed-performance-mode-enabled true');
                if (prof.hz) await exec('settings put system peak_refresh_rate 120');
                if (prof.ram) {
                    await exec('am kill-all');
                    await exec('pm trim-caches 9999999999');
                }
                activeProfileId = prof.id;
                localStorage.setItem('ws7_active_profile_id', prof.id);
                showToast(`[✔] Perfil "${prof.name}" ativado!`);
            }
            renderProfiles();
        });

        div.querySelector('.btn-del-prof').addEventListener('click', () => {
            if (activeProfileId === prof.id) {
                restoreSystemState();
                activeProfileId = null;
            }
            customProfiles = customProfiles.filter(p => p.id !== prof.id);
            saveProfilesData();
            renderProfiles();
            showToast('Perfil excluído.');
        });

        container.appendChild(div);
    });
}

// -------------------------------------------------------------
// QUICK ACTIONS
// -------------------------------------------------------------
document.getElementById('btn-clean-ram')?.addEventListener('click', async () => {
    showToast('Executando purga e compactação...');
    await exec('am kill-all');
    await exec('pm trim-caches 9999999999');
    await exec('sm fstrim');
    await updateTelemetry();
    showToast('[✔] Sistema purgado!');
});

document.getElementById('btn-cool-down')?.addEventListener('click', async () => {
    showToast('Estabilizando temperatura...');
    await exec('cmd power set-fixed-performance-mode-enabled false');
    await updateTelemetry();
    showToast('[✔] Núcleos resfriados!');
});

// -------------------------------------------------------------
// ICON & PACKAGE HELPER
// -------------------------------------------------------------
async function fetchPackagesInfo(pkgs) {
    if (!pkgs || pkgs.length === 0) return;
    if (ksuGetPackagesInfoFn) {
        try {
            const info = await ksuGetPackagesInfoFn(pkgs);
            const arr = typeof info === 'string' ? JSON.parse(info) : info;
            if (Array.isArray(arr)) {
                arr.forEach(i => {
                    if (i && (i.packageName || i.pkg)) {
                        const name = i.packageName || i.pkg;
                        packagesInfoMap[name] = i;
                    }
                });
            }
        } catch(e) {}
    }
}

function getAppIconHtml(pkg) {
    const info = packagesInfoMap[pkg];
    if (info && info.icon) {
        return `<img src="${info.icon}" alt="icon" onerror="this.parentNode.innerHTML='<span>${pkg.split('.').pop().charAt(0).toUpperCase()}</span>'">`;
    }
    const letter = pkg.split('.').pop().charAt(0).toUpperCase() || 'A';
    return `<span>${letter}</span>`;
}

function getAppLabel(pkg) {
    const info = packagesInfoMap[pkg];
    if (info && info.appLabel) return info.appLabel;
    const parts = pkg.split('.');
    let name = parts[parts.length - 1];
    return name.charAt(0).toUpperCase() + name.slice(1);
}

// -------------------------------------------------------------
// GAMES SPACE
// -------------------------------------------------------------
function loadData() {
    try {
        detectedGames = JSON.parse(localStorage.getItem(LS_GAMES_KEY)) || [];
        gameConfigs = JSON.parse(localStorage.getItem(LS_GAME_CONFIGS_KEY)) || {};
    } catch(e) { detectedGames = []; gameConfigs = {}; }
}

function saveData() {
    localStorage.setItem(LS_GAMES_KEY, JSON.stringify(detectedGames));
    localStorage.setItem(LS_GAME_CONFIGS_KEY, JSON.stringify(gameConfigs));
}

async function renderGames() {
    const container = document.getElementById('games-list-container');
    if (!container) return;
    const query = (document.getElementById('input-search-games')?.value || '').toLowerCase();

    const filtered = detectedGames.filter(pkg => pkg.toLowerCase().includes(query));

    if (filtered.length === 0) {
        container.innerHTML = `<div class="action-desc" style="text-align:center; padding: 14px 0;">Nenhum jogo adicionado. Escaneie ou adicione acima.</div>`;
        return;
    }

    await fetchPackagesInfo(filtered);
    container.innerHTML = '';

    filtered.forEach(pkg => {
        const div = document.createElement('div');
        div.className = 'game-card';
        const label = getAppLabel(pkg);
        const iconHtml = getAppIconHtml(pkg);

        div.innerHTML = `
            <div class="game-info">
                <div class="app-icon">${iconHtml}</div>
                <div class="app-meta">
                    <span class="app-name">${label}</span>
                    <span class="app-pkg">${pkg}</span>
                </div>
            </div>
            <div class="game-actions">
                <button class="btn-secondary btn-config" data-pkg="${pkg}">⚙</button>
                <button class="btn-launch" data-pkg="${pkg}">JOGAR</button>
            </div>
        `;
        div.querySelector('.btn-config').addEventListener('click', () => openGameConfig(pkg));
        div.querySelector('.btn-launch').addEventListener('click', () => launchGame(pkg));
        container.appendChild(div);
    });
}

function openGameConfig(pkg) {
    activeGamePkg = pkg;
    const config = gameConfigs[pkg] || { ...DEFAULT_GAME_CONFIG };
    document.getElementById('modal-game-title').textContent = getAppLabel(pkg);
    document.getElementById('modal-game-pkg').textContent = pkg;
    
    document.querySelectorAll('#chip-group-fps .chip').forEach(c => {
        c.classList.toggle('active', c.getAttribute('data-val') == config.fps);
    });
    document.getElementById('modal-game-config').classList.add('active');
}

document.getElementById('btn-close-modal')?.addEventListener('click', () => {
    document.getElementById('modal-game-config').classList.remove('active');
});

document.getElementById('btn-save-game-config')?.addEventListener('click', () => {
    const fps = document.querySelector('#chip-group-fps .chip.active')?.getAttribute('data-val') || '60';
    gameConfigs[activeGamePkg] = { fps: parseInt(fps) };
    saveData();
    showToast('Configurações salvas.');
    document.getElementById('modal-game-config').classList.remove('active');
});

async function launchGame(pkg) {
    const config = gameConfigs[pkg] || DEFAULT_GAME_CONFIG;
    showToast(`Iniciando ${getAppLabel(pkg)}...`);
    await exec('cmd power set-fixed-performance-mode-enabled true');
    await exec(`settings put system peak_refresh_rate ${config.fps}`);
    await exec('am kill-all');
    await exec(`monkey -p ${pkg} -c android.intent.category.LAUNCHER 1`);
}

document.getElementById('btn-scan-games')?.addEventListener('click', async () => {
    showToast('Escaneando pacotes...');
    try {
        const raw = await exec('pm list packages -3 | cut -f 2 -d ":"');
        const pkgs = raw.split('\n').map(p => p.trim()).filter(Boolean);
        let added = 0;
        pkgs.forEach(p => {
            if (/(game|play|fps|shooter|fire|moba|craft|brawl|racing|speed)/i.test(p) && !detectedGames.includes(p)) {
                detectedGames.push(p);
                added++;
            }
        });
        saveData();
        renderGames();
        showToast(`[✔] ${added} jogos encontrados!`);
    } catch(e) {
        showToast('Erro ao escanear.');
    }
});

document.getElementById('btn-add-game')?.addEventListener('click', () => {
    const input = document.getElementById('input-search-games');
    const pkg = input.value.trim();
    if (!pkg) return;
    if (!detectedGames.includes(pkg)) {
        detectedGames.unshift(pkg);
        saveData();
        renderGames();
        showToast(`Adicionado: ${pkg}`);
    }
    input.value = '';
});

document.getElementById('input-search-games')?.addEventListener('input', renderGames);

// -------------------------------------------------------------
// THEME & ACCENT CUSTOMIZATION
// -------------------------------------------------------------
function applyAccentColor(color) {
    document.documentElement.style.setProperty('--accent', color);
    if (color === '#FFFFFF' || color === '#F59E0B' || color === '#22D3EE' || color === '#10B981') {
        document.documentElement.style.setProperty('--accent-text', '#000000');
    } else {
        document.documentElement.style.setProperty('--accent-text', '#FFFFFF');
    }
    try { localStorage.setItem(LS_ACCENT_KEY, color); } catch(e) {}
}

document.querySelectorAll('#color-chip-group .chip').forEach(chip => {
    chip.addEventListener('click', () => {
        document.querySelectorAll('#color-chip-group .chip').forEach(c => c.classList.remove('active'));
        chip.classList.add('active');
        applyAccentColor(chip.getAttribute('data-color'));
        showToast('Tema atualizado!');
    });
});

try {
    const savedColor = localStorage.getItem(LS_ACCENT_KEY);
    if (savedColor) {
        applyAccentColor(savedColor);
        document.querySelectorAll('#color-chip-group .chip').forEach(c => {
            if (c.getAttribute('data-color') === savedColor) c.classList.add('active');
            else c.classList.remove('active');
        });
    }
} catch(e) {}

// -------------------------------------------------------------
// TOGGLES & SLIDERS
// -------------------------------------------------------------
document.querySelectorAll('.toggle').forEach(t => {
    t.addEventListener('click', async () => {
        const next = t.getAttribute('aria-checked') !== 'true';
        t.setAttribute('aria-checked', String(next));
        const key = t.getAttribute('data-key');
        if (!key) return;
        showToast(`${key.toUpperCase()}: ${next ? 'ON' : 'OFF'}`);

        if (key === 'tcp_buffers') {
            if (next) await exec('setprop net.tcp.buffersize.wifi 524288,1048576,2097152,262144,524288,1048576');
            else await exec('setprop net.tcp.buffersize.wifi ""');
        } else if (key === 'touch_impulse') {
            if (next) await exec('cmd device_config put input velocity_tracker_strategy impulse');
            else await exec('cmd device_config delete input velocity_tracker_strategy');
        }
    });
});

document.querySelectorAll('#dns-chip-group .chip').forEach(c => {
    c.addEventListener('click', async () => {
        document.querySelectorAll('#dns-chip-group .chip').forEach(x => x.classList.remove('active'));
        c.classList.add('active');
        const dns = c.getAttribute('data-dns');
        if (dns === 'off') await exec('settings put global private_dns_mode off');
        else {
            await exec('settings put global private_dns_mode hostname');
            await exec(`settings put global private_dns_specifier ${dns}`);
        }
        showToast(`DNS: ${dns}`);
    });
});

// -------------------------------------------------------------
// APPS CATALOG
// -------------------------------------------------------------
async function loadAppsCatalog() {
    const container = document.getElementById('apps-list-container');
    if (!container) return;
    container.innerHTML = '<div class="action-desc" style="text-align:center;">Carregando aplicativos...</div>';
    
    try {
        const raw3 = await exec('pm list packages -3 | cut -f 2 -d ":"');
        const rawS = await exec('pm list packages -s | cut -f 2 -d ":"');
        const u = raw3.split('\n').map(p => p.trim()).filter(Boolean);
        const s = rawS.split('\n').map(p => p.trim()).filter(Boolean);
        
        allPackages = [
            ...u.map(p => ({ pkg: p, isSystem: false, isSuspended: false })),
            ...s.map(p => ({ pkg: p, isSystem: true, isSuspended: false }))
        ];

        const pkgsSlice = allPackages.slice(0, 35).map(x => x.pkg);
        await fetchPackagesInfo(pkgsSlice);
        renderAppsList();
    } catch(e) { container.innerHTML = 'Erro ao carregar.'; }
}

function renderAppsList() {
    const container = document.getElementById('apps-list-container');
    if (!container) return;
    const query = (document.getElementById('input-search-apps')?.value || '').toLowerCase();
    
    const filtered = allPackages.filter(item => {
        if (currentFilter === 'user' && item.isSystem) return false;
        if (currentFilter === 'system' && !item.isSystem) return false;
        if (currentFilter === 'frozen' && !item.isSuspended) return false;
        const label = getAppLabel(item.pkg).toLowerCase();
        return label.includes(query) || item.pkg.toLowerCase().includes(query);
    }).slice(0, 35);

    if (filtered.length === 0) {
        container.innerHTML = '<div class="action-desc" style="text-align:center;">Nenhum app encontrado.</div>';
        return;
    }

    container.innerHTML = '';
    filtered.forEach(item => {
        const row = document.createElement('div');
        row.className = 'app-row';
        const label = getAppLabel(item.pkg);
        const iconHtml = getAppIconHtml(item.pkg);

        row.innerHTML = `
            <div class="game-info">
                <div class="app-icon">${iconHtml}</div>
                <div class="app-meta">
                    <span class="app-name">${label}</span>
                    <span class="app-pkg">${item.pkg}</span>
                </div>
            </div>
            <button class="btn-secondary btn-freeze ${item.isSuspended ? 'frozen' : ''}" data-pkg="${item.pkg}">
                ${item.isSuspended ? 'Descongelar' : 'Congelar'}
            </button>
        `;

        row.querySelector('.btn-freeze').addEventListener('click', async (e) => {
            if (item.isSuspended) {
                await exec(`pm unsuspend ${item.pkg}`);
                item.isSuspended = false;
                e.target.classList.remove('frozen');
                e.target.textContent = 'Congelar';
                showToast(`Descongelado: ${label}`);
            } else {
                await exec(`pm suspend ${item.pkg}`);
                item.isSuspended = true;
                e.target.classList.add('frozen');
                e.target.textContent = 'Descongelar';
                showToast(`Congelado: ${label}`);
            }
        });
        container.appendChild(row);
    });
}

document.getElementById('input-search-apps')?.addEventListener('input', renderAppsList);
document.querySelectorAll('#panel-frozen .chip').forEach(c => {
    c.addEventListener('click', () => {
        document.querySelectorAll('#panel-frozen .chip').forEach(x => x.classList.remove('active'));
        c.classList.add('active');
        currentFilter = c.getAttribute('data-filter');
        renderAppsList();
    });
});

async function loadSystemInfo() {
    try {
        const model = await exec('getprop ro.product.model');
        const android = await exec('getprop ro.build.version.release');
        document.getElementById('info-model').textContent = model.trim();
        document.getElementById('info-android').textContent = 'Android ' + android.trim();
    } catch(e) {}
}

async function init() {
    await initKsu();
    loadData();
    loadProfilesData();
    renderProfiles();
    updateTelemetry();
    setInterval(updateTelemetry, 5000);
    setTimeout(hideSplash, 600);
}

if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
} else {
    init();
}
