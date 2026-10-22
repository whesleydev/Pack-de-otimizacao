import fs from 'node:fs';
import path from 'node:path';

console.log('[BUILD] Validating Pack de Otimização assets...');

// Verify actions.json
const actionsPath = path.resolve('app/src/main/assets/panel/actions.json');
if (!fs.existsSync(actionsPath)) {
  console.error('[BUILD ERROR] actions.json not found at:', actionsPath);
  process.exit(1);
}

const actions = JSON.parse(fs.readFileSync(actionsPath, 'utf8'));
console.log(`[BUILD] Verified actions.json: ${actions.length} optimization actions found.`);

// Verify audio assets
const audioDir = path.resolve('app/src/main/assets/audio');
if (fs.existsSync(audioDir)) {
  const audios = fs.readdirSync(audioDir);
  console.log(`[BUILD] Verified audio assets: ${audios.length} sound files available.`);
}

// Verify brevent commands
const breventDir = path.resolve('00 Otimizações/Comandos Brevent');
if (fs.existsSync(breventDir)) {
  const files = fs.readdirSync(breventDir).filter(f => f.endsWith('.txt'));
  console.log(`[BUILD] Verified Brevent command modules: ${files.length} .txt files available.`);
}

// Verify scripts
const scriptsDir = path.resolve('scripts');
if (fs.existsSync(scriptsDir)) {
  const scripts = fs.readdirSync(scriptsDir).filter(f => f.endsWith('.sh'));
  console.log(`[BUILD] Verified shell scripts: ${scripts.length} shell automation scripts found.`);
}

console.log('[BUILD] Build verification successful!');
process.exit(0);
