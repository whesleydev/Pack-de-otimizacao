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
require_once __DIR__ . '/auth.php';

// --- login obrigatório --------------------------------------------------------
$erro_login = '';
if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST' && isset($_POST['user'], $_POST['pass'])) {
    if (!otm_csrf_ok($_POST['csrf'] ?? null)) {
        $erro_login = 'Sessão expirada. Tente de novo.';
    } elseif (otm_auth_login((string)$_POST['user'], (string)$_POST['pass'])) {
        header('Location: index.php');
        exit;
    } else {
        $erro_login = 'Usuário ou senha incorretos.';
    }
}
if (isset($_GET['sair'])) {
    otm_auth_logout();
    header('Location: index.php');
    exit;
}
if (!otm_auth_logged_in()) {
    if ($erro_login !== '') $_GET['erro'] = $erro_login;
    require __DIR__ . '/login.php';
    exit;
}

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
    'Extremos (root)'   => ['t' => 'Extremos (root)',   's' => 'Knobs avançados que quase ninguém conhece: VM, escalonador, GPU, núcleos, input, idle, zRAM e mais.'],
    'Avançado (sem root)'=> ['t' => 'Avançado (sem root)','s' => 'Ajustes pouco conhecidos que não pedem root: standby, rede móvel, notificações e janelas.'],
    'Diagnóstico'       => ['t' => 'Diagnóstico',       's' => 'Detecta o aparelho, mede e mostra o estado atual. Só leitura.'],
    'Configs'           => ['t' => 'Configs',           's' => 'Como o pack conversa com o Android: Shizuku (rish), ADB por Wi-Fi, root ou automático. Sem root por padrão.'],
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
html{scroll-behavior:smooth;overflow-x:clip}
html,body{margin:0}
body{
  font-family:var(--font); color:var(--ink); line-height:1.55; min-height:100dvh;
  -webkit-text-size-adjust:100%; overflow-x:clip;
  background:var(--paper);
}
/* papel de parede: fundo preenche a tela e a imagem aparece inteira (sem corte) */
html::before{content:"";position:fixed;inset:0;z-index:-3;
  background:url('assets/wallpaper.jpeg') center/cover no-repeat}
body::after{content:"";position:fixed;inset:0;z-index:-2;
  background:url('assets/wallpaper.jpeg') center/contain no-repeat}
/* véu para dar contraste ao conteúdo sobre o wallpaper */
body::before{content:"";position:fixed;inset:0;z-index:-1;background:var(--paper);opacity:.62}
a{color:var(--accent)}
button{font:inherit;color:inherit}

/* ---- topo (vidro) --------------------------------------------------------- */
.top{
  position:sticky; top:0; z-index:40; min-height:var(--top);
  display:flex; align-items:center; flex-wrap:wrap; gap:8px; row-gap:8px;
  padding:8px clamp(10px,3vw,20px);
  background:var(--glass); backdrop-filter:var(--blur); -webkit-backdrop-filter:var(--blur);
  border-bottom:1px solid var(--line);
}
.mark{width:36px;height:36px;flex:none;border-radius:11px;background:var(--accent);color:var(--accent-ink);
  display:grid;place-items:center;font-weight:800;font-size:14px;letter-spacing:-.05em}
.name{font-weight:800;letter-spacing:-.02em;font-size:15px;line-height:1.05;white-space:nowrap;min-width:0;overflow:hidden;text-overflow:ellipsis}
.name small{display:block;font-weight:500;font-size:11px;color:var(--muted);letter-spacing:0}
.grow{flex:1}
.iconbtn{
  border:1px solid var(--line);background:var(--glass-2);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border-radius:10px;padding:8px 11px;cursor:pointer;font-size:13px;font-weight:600;flex:none;
  display:inline-flex;align-items:center;gap:6px;transition:.15s;white-space:nowrap;text-decoration:none
}
.iconbtn svg{width:17px;height:17px;display:block}
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

/* ---- animações ------------------------------------------------------------- */
@keyframes otmRise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
@keyframes otmFade{from{opacity:0}to{opacity:1}}
@keyframes otmPop{from{opacity:0;transform:scale(.94)}to{opacity:1;transform:none}}
@keyframes otmSheen{0%{background-position:-160% 0}60%,100%{background-position:260% 0}}
@keyframes otmPulse{0%,100%{box-shadow:0 0 0 0 var(--ring)}50%{box-shadow:0 0 0 6px transparent}}
@keyframes otmSpin{to{transform:rotate(360deg)}}
@media (prefers-reduced-motion: reduce){
  *{animation-duration:.001ms!important;animation-iteration-count:1!important;transition-duration:.001ms!important}
  html{scroll-behavior:auto}
}

/* ---- layout --------------------------------------------------------------- */
.layout{max-width:1180px;margin:0 auto;display:grid;grid-template-columns:250px minmax(0,1fr);
  gap:clamp(14px,3vw,28px);padding:clamp(14px,3vw,26px) clamp(12px,3vw,22px)}
.side{align-self:start;position:static}
.side .panel{
  position:fixed; top:calc(var(--top) + 12px); z-index:30;
  left:calc(max((100vw - 1180px) / 2, 0px) + clamp(12px,3vw,22px)); width:250px;
  background:var(--glass); backdrop-filter:var(--blur); -webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line); border-radius:var(--r); box-shadow:var(--shadow);
  padding:12px; max-height:calc(100dvh - var(--top) - 24px); overflow:auto
}
.side h2{font-size:11px;text-transform:uppercase;letter-spacing:.12em;color:var(--muted);margin:2px 0 10px 8px}
.nav{display:flex;flex-direction:column;gap:2px}
.nav a{display:flex;align-items:center;gap:10px;padding:9px 11px;border-radius:var(--r-sm);
  color:var(--ink);text-decoration:none;font-size:13.5px;font-weight:600;border:1px solid transparent;
  position:relative;transition:background .15s ease, border-color .15s ease, transform .12s ease}
.nav a .c{width:6px;height:6px;border-radius:50%;background:var(--line-strong);flex:none;transition:background .2s}
.nav a:hover{background:var(--glass-2);transform:translateX(2px)}
.nav a:active{transform:translateX(0) scale(.99)}
.nav a[aria-current="true"]{background:var(--glass-2);border-color:var(--line-strong)}
.nav a[aria-current="true"]::before{content:"";position:absolute;left:-1px;top:8px;bottom:8px;width:3px;
  border-radius:3px;background:var(--accent);animation:otmPop .25s both}
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
  display:flex; flex-direction:column; gap:9px; box-shadow:var(--shadow);
  animation:otmRise .42s cubic-bezier(.2,.7,.3,1) both;
  animation-delay:calc(var(--i,0)*45ms);
  transition:transform .18s ease, box-shadow .18s ease, border-color .18s ease
}
@media (hover:hover){
  .card:hover{transform:translateY(-3px);border-color:var(--line-strong);
    box-shadow:0 2px 4px rgba(25,22,18,.08),0 22px 46px -22px rgba(25,22,18,.45)}
}
.card:active{transform:translateY(-1px) scale(.995)}
section[data-g] .head{animation:otmFade .3s both}
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
  padding:10px 15px;font-size:13.5px;font-weight:700;cursor:pointer;position:relative;overflow:hidden;
  transition:transform .12s ease,border-color .15s ease,filter .15s ease,box-shadow .15s ease}
.btn:hover{border-color:var(--accent)}
.btn:active{transform:scale(.97)}
.btn.primary{background:var(--accent);border-color:var(--accent);color:var(--accent-ink)}
.btn.primary:hover{filter:brightness(1.06)}
.btn.primary::after{content:"";position:absolute;inset:0;pointer-events:none;
  background:linear-gradient(100deg,transparent 30%,rgba(255,255,255,.35) 50%,transparent 70%);
  background-size:220% 100%;animation:otmSheen 4.6s ease-in-out infinite}
.btn.danger{background:var(--danger);border-color:var(--danger);color:#fff}
.btn:disabled{opacity:.55;cursor:progress}
.btn.busy::before{content:"";display:inline-block;width:12px;height:12px;margin-right:7px;vertical-align:-2px;
  border:2px solid currentColor;border-right-color:transparent;border-radius:50%;animation:otmSpin .7s linear infinite}
.help-btn{transition:transform .15s ease,border-color .15s,color .15s}
.help-btn:active{transform:scale(.9)}

/* ---- gaveta lateral (celular) -------------------------------------------- */
.scrim{position:fixed;inset:0;z-index:54;background:rgba(12,10,8,.5);backdrop-filter:blur(3px);
  opacity:0;visibility:hidden;transition:opacity .24s ease, visibility .24s}
body.drawer .scrim{opacity:1;visibility:visible}
.side-close{display:none}

/* ---- console -------------------------------------------------------------- */
.console{position:fixed;left:0;right:0;bottom:0;z-index:60;transform:translateY(102%);transition:transform .26s cubic-bezier(.2,.8,.3,1);
  background:rgba(12,11,9,.92);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  color:#ece6da;border-top:1px solid rgba(255,255,255,.12);max-height:56vh;display:flex;flex-direction:column;
  box-shadow:0 -14px 44px -22px rgba(0,0,0,.85);
  padding-bottom:env(safe-area-inset-bottom,0)}
.console.open{transform:none}
.console .bar{display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid rgba(255,255,255,.12)}
.console .bar b{font-size:13px}
.console pre{margin:0;padding:14px 16px;overflow:auto;font-family:var(--mono);font-size:12.5px;white-space:pre-wrap}
.close-x{border:1px solid rgba(255,255,255,.2);background:transparent;color:#ece6da;border-radius:8px;padding:6px 10px;cursor:pointer}

/* ---- modal ---------------------------------------------------------------- */
.mask{position:fixed;inset:0;z-index:70;background:rgba(12,10,8,.55);backdrop-filter:blur(4px);
  display:none;place-items:center;padding:16px;animation:otmFade .18s both}
.mask.open{display:grid}
.modal{background:var(--glass);backdrop-filter:var(--blur);-webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line-strong);border-radius:20px;max-width:min(92vw,460px);width:100%;
  padding:22px;box-shadow:var(--shadow);max-height:86dvh;overflow:auto;animation:otmPop .26s cubic-bezier(.2,.8,.3,1) both}
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

/* ---- configurações (engrenagem) ------------------------------------------ */
.set-group{margin:0 0 16px}
.set-label{font-size:11px;font-weight:700;color:var(--muted);letter-spacing:.06em;text-transform:uppercase;margin:0 0 8px 2px}
.seg{display:flex;gap:6px;background:var(--glass-2);border:1px solid var(--line);border-radius:12px;padding:4px}
.seg-btn{flex:1;border:0;background:transparent;border-radius:9px;padding:9px 8px;font-size:13px;font-weight:700;cursor:pointer;color:var(--muted)}
.seg-btn[aria-pressed="true"]{background:var(--accent);color:var(--accent-ink)}
.swatches{display:flex;gap:10px;flex-wrap:wrap}
.sw{width:34px;height:34px;border-radius:10px;border:2px solid var(--line-strong);background:var(--sw);cursor:pointer;transition:.15s}
.sw[aria-pressed="true"]{border-color:var(--ink);box-shadow:0 0 0 2px var(--ring)}
.switch{display:flex;align-items:center;gap:10px;font-size:14px;cursor:pointer}
.switch input{width:18px;height:18px;accent-color:var(--accent)}
.set-hint{font-size:12px;color:var(--muted);margin:6px 0 0 2px}
.slider{display:flex;align-items:center;gap:10px}
.slider input[type=range]{flex:1;accent-color:var(--accent);min-width:0}
.slider .val{min-width:56px;text-align:right;font-size:13px;font-weight:700;color:var(--accent)}
.modal.wide{max-width:520px;max-height:86vh;overflow:auto}
.set-actions{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 14px}
.set-actions .btn{flex:1;min-width:120px}
.perms{display:flex;flex-direction:column;gap:8px}
.perm{display:flex;gap:10px;align-items:flex-start;padding:10px 12px;border:1px solid var(--line);border-radius:12px;background:var(--glass-2)}
.perm .ico{width:30px;height:30px;flex:none;border-radius:9px;display:grid;place-items:center;background:var(--accent);color:var(--accent-ink);font-size:15px}
.perm b{display:block;font-size:13.5px}
.perm span{display:block;font-size:12px;color:var(--muted);line-height:1.45}
.perm .tag{display:inline-block;margin-top:5px;font-size:10.5px;font-weight:700;letter-spacing:.05em;text-transform:uppercase;color:var(--warn)}

/* ---- responsivo ----------------------------------------------------------- */
@media (max-width:960px){
  .layout{grid-template-columns:1fr;gap:14px;padding-left:clamp(12px,4vw,20px);padding-right:clamp(12px,4vw,20px)}
  .side{position:fixed;top:0;left:0;bottom:0;width:min(86vw,320px);z-index:56;padding:14px;
    transform:translateX(-104%);transition:transform .26s cubic-bezier(.2,.8,.3,1);
    padding-bottom:calc(14px + env(safe-area-inset-bottom,0))}
  .side .panel{position:static;width:auto;left:auto;top:auto;max-height:100%;height:100%;border-radius:0 var(--r) var(--r) 0;padding-top:calc(56px + env(safe-area-inset-top,0));
    overflow:auto}
  body.drawer .side{transform:none}
  .side-close{display:inline-flex;position:absolute;top:calc(12px + env(safe-area-inset-top,0));right:12px}
  .burger{display:inline-flex}
}
@media (max-width:560px){
  :root{--top:58px}
  .name small{display:none}
  .hide-sm{display:none}
  .grid{grid-template-columns:1fr}
  .fields{grid-template-columns:1fr}
  .banner .in{padding:16px 14px}
  .head h2{font-size:19px}
  .card{padding:14px}
  .btn{width:100%;padding:12px 15px}   /* alvo de toque maior no celular */
  .go{gap:10px}
  .console{max-height:70dvh}
  .toast{bottom:calc(16px + env(safe-area-inset-bottom,0))}
  .top{gap:6px;padding:7px clamp(8px,3vw,16px)}
  .iconbtn{padding:8px 10px;font-size:12.5px}
}
@media (max-width:380px){
  .name{font-size:14px}
  .mark{width:32px;height:32px;font-size:12px}
  .card{padding:12px}
}
/* ---- rodapé / créditos ---------------------------------------------------- */
.credits{border-top:1px solid var(--line); background:var(--glass); backdrop-filter:var(--blur);
  -webkit-backdrop-filter:var(--blur); padding:22px clamp(12px,3vw,22px)}
.credits .in{max-width:1180px; margin:0 auto; display:flex; align-items:center; gap:14px; flex-wrap:wrap}
.credits .who{font-size:13px; color:var(--muted)}
.credits .who b{color:var(--ink)}
.credits .who code{color:var(--accent); background:var(--glass-2); border:1px solid var(--line);
  border-radius:6px; padding:1px 6px}
.credits .sp{flex:1}
.dcb{display:inline-flex; align-items:center; gap:7px; text-decoration:none; color:var(--ink);
  border:1px solid var(--line); background:var(--glass-2); border-radius:10px; padding:8px 12px;
  font-size:12.5px; font-weight:700; transition:.15s; white-space:nowrap}
.dcb:hover{border-color:var(--accent); transform:translateY(-1px)}
.dcb:focus-visible{outline:2px solid var(--ring); outline-offset:1px}
.dcb svg{width:16px; height:16px; fill:currentColor; flex:none}
.dcb .arw{font-size:11px; color:var(--muted)}
@media (max-width:520px){ .credits .who{font-size:12px} .credits .in{gap:9px} }
@media (max-height:520px){
  .side .panel{padding-top:48px}
  .console{max-height:80dvh}
}
</style>
</head>
<body>
<header class="top">
  <button class="iconbtn burger" id="burger" aria-label="Abrir categorias" aria-expanded="false">☰</button>
  <div class="mark" aria-hidden="true">00</div>
  <div class="name">00deUdia Otimizações<small>painel de controle</small></div>
  <div class="grow"></div>
  <span class="iconbtn hide-sm" id="modePill" style="cursor:default"><span class="dot"></span><span id="modeTxt">verificando…</span></span>
  <button class="iconbtn hide-sm" id="btnTheme" aria-label="Alternar tema claro/escuro" title="Tema claro/escuro">◐</button>
  <button class="iconbtn" id="btnGear" aria-label="Configurações" title="Configurações"><svg viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 15.5A3.5 3.5 0 1 1 12 8.5a3.5 3.5 0 0 1 0 7Zm7.43-2.53c.04-.32.07-.64.07-.97s-.03-.66-.07-.98l2.11-1.65a.5.5 0 0 0 .12-.64l-2-3.46a.5.5 0 0 0-.61-.22l-2.49 1a7.3 7.3 0 0 0-1.69-.98l-.38-2.65A.5.5 0 0 0 14 2h-4a.5.5 0 0 0-.49.42l-.38 2.65c-.61.25-1.17.59-1.69.98l-2.49-1a.5.5 0 0 0-.61.22l-2 3.46a.5.5 0 0 0 .12.64L4.57 11c-.04.32-.07.65-.07.98s.03.65.07.97l-2.11 1.66a.5.5 0 0 0-.12.64l2 3.46c.14.24.42.34.68.22l2.49-1c.52.39 1.08.72 1.69.98l.38 2.65c.04.24.24.42.49.42h4c.25 0 .46-.18.49-.42l.38-2.65c.61-.25 1.17-.59 1.69-.98l2.49 1c.26.11.54.02.68-.22l2-3.46a.5.5 0 0 0-.12-.64l-2.11-1.66Z"/></svg></button>
  <button class="iconbtn hide-sm" id="btnStatus">Status</button>
  <button class="iconbtn hide-sm" id="btnLog">Histórico</button>
  <button class="iconbtn" id="btnConsole">Console</button>
  <a class="iconbtn hide-sm" href="index.php?sair=1" id="btnSair" title="Sair do painel">Sair</a>
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
          <?php foreach ($items as $ci => $a):
            $risk = $a['risk'] ?? 'safe'; ?>
            <article class="card" data-id="<?= htmlspecialchars($a['id'], ENT_QUOTES) ?>"
                     style="--i:<?= (int)($ci % 12) ?>">
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
                    $wide = in_array($t, ['pkg', 'host', 'text', 'name', 'enum'], true); ?>
                    <div class="field<?= $wide ? ' wide' : '' ?>">
                      <label for="<?= htmlspecialchars($a['id'] . '-' . $p['name'], ENT_QUOTES) ?>"><?= htmlspecialchars($p['label']) ?></label>
                      <?php if ($t === 'enum'): ?>
                        <select id="<?= htmlspecialchars($a['id'] . '-' . $p['name'], ENT_QUOTES) ?>"
                                data-p="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>">
                          <?php foreach (($p['options'] ?? []) as $opt): ?>
                            <option value="<?= htmlspecialchars((string) $opt, ENT_QUOTES) ?>"
                              <?= ((string) $opt === (string) ($p['default'] ?? '')) ? ' selected' : '' ?>><?= htmlspecialchars((string) $opt) ?></option>
                          <?php endforeach; ?>
                        </select>
                      <?php else: ?>
                      <input id="<?= htmlspecialchars($a['id'] . '-' . $p['name'], ENT_QUOTES) ?>"
                             data-p="<?= htmlspecialchars($p['name'], ENT_QUOTES) ?>"
                             type="<?= in_array($t, ['int', 'float'], true) ? 'number' : 'text' ?>"
                             value="<?= htmlspecialchars((string) ($p['default'] ?? ''), ENT_QUOTES) ?>"
                             <?= $t === 'pkg' ? 'list="applist" placeholder="com.exemplo.app"' : '' ?>
                             <?= $t === 'host' ? 'placeholder="dns.exemplo.com"' : '' ?>
                             <?= isset($p['min']) ? 'min="' . htmlspecialchars((string) $p['min'], ENT_QUOTES) . '"' : '' ?>
                             <?= isset($p['max']) ? 'max="' . htmlspecialchars((string) $p['max'], ENT_QUOTES) . '"' : '' ?>
                             <?= isset($p['step']) ? 'step="' . htmlspecialchars((string) $p['step'], ENT_QUOTES) . '"' : '' ?>>
                      <?php endif; ?>
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

<footer class="credits">
  <div class="in">
    <p class="who">Criado por <b>00deUdia</b> · Discord <code>cute_axolotl_51194</code></p>
    <span class="sp"></span>
    <a class="dcb" href="https://discord.com/users/cute_axolotl_51194" target="_blank" rel="noopener"
       title="Abrir meu perfil no Discord">
      <svg viewBox="0 0 127.14 96.36" aria-hidden="true"><path d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z"/></svg>
      Meu Discord <span class="arw">↗</span>
    </a>
    <a class="dcb" href="https://discord.gg/w9hFBeVKw8" target="_blank" rel="noopener"
       title="Entrar no meu servidor do Discord">
      <svg viewBox="0 0 127.14 96.36" aria-hidden="true"><path d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z"/></svg>
      Servidor <span class="arw">↗</span>
    </a>
  </div>
</footer>

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

<div class="mask" id="gearMask" role="dialog" aria-modal="true" aria-labelledby="gearTitle">
  <div class="modal wide">
    <h3 id="gearTitle">Configurações</h3>
    <p>Permissões, aparência e som. Fica tudo salvo neste aparelho.</p>

    <div class="set-group">
      <div class="set-label">Permissões e segundo plano</div>
      <div class="perms" id="permList">
        <div class="perm"><span class="ico" aria-hidden="true">🔔</span><div>
          <b>Notificações</b><span>Mostrar o aviso do pack e o andamento das ações.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true">🔋</span><div>
          <b>Bateria sem restrição</b><span>Sem isso o Android adormece o app e as otimizações param sozinhas.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true">♾️</span><div>
          <b>Rodar em segundo plano</b><span>Mantém o pack ativo quando a tela apaga ou você troca de app.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true">🛡️</span><div>
          <b>Isento do Doze</b><span>Impede o sistema de congelar o pack e o jogo em modo de espera.</span></div></div>
        <div class="perm"><span class="ico" aria-hidden="true">📶</span><div>
          <b>Acesso por Shizuku ou ADB</b><span>É o que dá poder de shell ao pack. Configure em Configs.</span></div></div>
      </div>
      <div class="set-actions">
        <button class="btn primary" id="setPermApp" type="button">Conceder ao app do pack</button>
        <button class="btn" id="setPermFF" type="button">Ao Free Fire</button>
        <button class="btn" id="setPermBattery" type="button">Bateria sem economia</button>
      </div>
      <div class="set-hint" id="setPermHint">Precisa de Shizuku, ADB por Wi-Fi ou root. Dá para desfazer em "Reverter TUDO".</div>
    </div>

    <div class="set-group">
      <div class="set-label">Tema</div>
      <div class="seg" id="setTheme">
        <button class="seg-btn" data-theme="light" type="button">Claro</button>
        <button class="seg-btn" data-theme="dark" type="button">Escuro</button>
        <button class="seg-btn" data-theme="auto" type="button">Automático</button>
      </div>
    </div>

    <div class="set-group">
      <div class="set-label">Cor de destaque</div>
      <div class="swatches" id="setAccent">
        <button class="sw" data-accent="laranja" style="--sw:#ff6a2b" aria-label="Laranja" type="button"></button>
        <button class="sw" data-accent="azul" style="--sw:#2f7bff" aria-label="Azul" type="button"></button>
        <button class="sw" data-accent="verde" style="--sw:#17a673" aria-label="Verde" type="button"></button>
        <button class="sw" data-accent="roxo" style="--sw:#8b5cf6" aria-label="Roxo" type="button"></button>
        <button class="sw" data-accent="rosa" style="--sw:#ec4899" aria-label="Rosa" type="button"></button>
        <button class="sw" data-accent="vermelho" style="--sw:#e5484d" aria-label="Vermelho" type="button"></button>
      </div>
    </div>

    <div class="set-group">
      <div class="set-label">Fonte</div>
      <div class="seg" id="setFont">
        <button class="seg-btn" data-font="sistema" type="button">Sistema</button>
        <button class="seg-btn" data-font="serif" type="button">Serifa</button>
        <button class="seg-btn" data-font="mono" type="button">Mono</button>
      </div>
    </div>

    <div class="set-group">
      <div class="set-label">Tamanho da interface (DPI)</div>
      <div class="slider"><span style="font-size:12px;color:var(--muted)">DPI</span>
        <input type="range" id="setScale" min="100" max="140" step="5" value="100">
        <span class="val" id="setScaleVal">100%</span></div>
      <div class="set-hint">Aumenta ou diminui tudo no painel (zoom do app, não do sistema).</div>
    </div>

    <div class="set-group" id="setSoundGroup">
      <div class="set-label">Som</div>
      <label class="switch"><input type="checkbox" id="setSound"><span>Reproduzir sons ao executar</span></label>
      <div class="set-hint">Se o volume de mídia do aparelho estiver no mínimo, não dá para ouvir.</div>
    </div>

    <div class="row">
      <button class="btn" id="gearReset" type="button">Restaurar padrão</button>
      <button class="btn primary" id="gearDone" type="button">Pronto</button>
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

/* tema + aparência (engrenagem) */
const ACCENTS = {
  laranja:{accent:"#ff6a2b",ink:"#180d06",ring:"rgba(255,106,43,.35)"},
  azul:{accent:"#2f7bff",ink:"#04122e",ring:"rgba(47,123,255,.35)"},
  verde:{accent:"#17a673",ink:"#04160f",ring:"rgba(23,166,115,.35)"},
  roxo:{accent:"#8b5cf6",ink:"#120726",ring:"rgba(139,92,246,.35)"},
  rosa:{accent:"#ec4899",ink:"#2a0616",ring:"rgba(236,72,153,.35)"},
  vermelho:{accent:"#e5484d",ink:"#2a0506",ring:"rgba(229,72,77,.35)"}
};
const FONTS = {
  sistema:'"Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif',
  serif:'Georgia,"Times New Roman",serif',
  mono:'ui-monospace,"SFMono-Regular",Menlo,Consolas,monospace'
};
function setAccentQuiet(name){
  const a = ACCENTS[name]; if (!a) return;
  const r = document.documentElement.style;
  r.setProperty("--accent", a.accent); r.setProperty("--accent-ink", a.ink); r.setProperty("--ring", a.ring);
}
/* DPI do app: zoom no <html>. A largura vira 100%/escala para o conteúdo não
   ultrapassar a tela (foi o que causava o arrasto lateral). */
function setScaleQuiet(pct){
  const z = Math.min(1.4, Math.max(1, (pct || 100) / 100));
  const r = document.documentElement.style;
  if (z === 1){ r.removeProperty("zoom"); r.removeProperty("width"); }
  else { r.setProperty("zoom", String(z)); r.setProperty("width", "calc(100% / " + z + ")"); }
}
function setFontQuiet(name){
  document.documentElement.style.setProperty("--font", FONTS[name] || FONTS.sistema);
}
function syncGear(){
  const t = localStorage.getItem("otm-theme") || "auto";
  document.querySelectorAll("#setTheme .seg-btn").forEach(b => b.setAttribute("aria-pressed", b.dataset.theme === t ? "true" : "false"));
  const a = localStorage.getItem("otm-accent") || "laranja";
  document.querySelectorAll("#setAccent .sw").forEach(b => b.setAttribute("aria-pressed", b.dataset.accent === a ? "true" : "false"));
  const f = localStorage.getItem("otm-font") || "sistema";
  document.querySelectorAll("#setFont .seg-btn").forEach(b => b.setAttribute("aria-pressed", b.dataset.font === f ? "true" : "false"));
  const sc = parseInt(localStorage.getItem("otm-scale") || "100", 10);
  const scEl = document.getElementById("setScale"); if (scEl) scEl.value = sc;
  const scVal = document.getElementById("setScaleVal"); if (scVal) scVal.textContent = sc + "%";
  const s = document.getElementById("setSound"); if (s) s.checked = localStorage.getItem("otm-sound") !== "0";
  const sg = document.getElementById("setSoundGroup"); if (sg && !window.OTM) sg.style.display = "none";
  const pl = document.getElementById("setPermHint");
  if (pl && !window.OTM) pl.textContent = "No site (PC) não dá para mexer no aparelho — isso funciona no app do celular.";
}
function setTheme(v){
  if (v === "auto"){ delete document.documentElement.dataset.theme; }
  else { document.documentElement.dataset.theme = v; }
  localStorage.setItem("otm-theme", v);
  syncGear();
}
function setAccent(name){ setAccentQuiet(name); localStorage.setItem("otm-accent", name); syncGear(); }
function setFont(name){ setFontQuiet(name); localStorage.setItem("otm-font", name); syncGear(); }
function setScale(pct){ setScaleQuiet(pct); localStorage.setItem("otm-scale", String(pct)); syncGear(); }
function setSound(on){
  localStorage.setItem("otm-sound", on ? "1" : "0");
  try { if (window.OTM) window.OTM.call("sound", on ? "test" : "off", "snd"); } catch(e){}
  syncGear();
}
/* Permissões/segundo plano: manda a ação de registro pelo mesmo caminho das
   outras (no app vira OTM.call; no site, o aviso de que é só no celular). */
function askPermission(id, label){
  if (!window.OTM){ toast("Permissões: use o app no celular.", "bad"); return; }
  openConsole(label, "concedendo…");
  fetch("api.php?do=run", { method:"POST",
    headers:{"Content-Type":"application/json","X-OTM-Token":TOKEN},
    body: JSON.stringify({id:id, params:{}, confirm:false}) })
    .then(r => r.json())
    .then(j => {
      const head = (j.ok ? "✔ " : "✘ ") + "[" + (j.code ?? "?") + "]";
      openConsole(label, head + "\n\n" + (j.out || j.error || ""));
      if (j.ok) toast("Feito: " + label, "ok"); else toast("Falhou: " + label, "bad");
    })
    .catch(e => { openConsole(label, "erro: " + e); toast("Erro", "bad"); });
}
(function initAppearance(){
  const t = localStorage.getItem("otm-theme"); if (t && t !== "auto") document.documentElement.dataset.theme = t;
  const a = localStorage.getItem("otm-accent"); if (a) setAccentQuiet(a);
  const f = localStorage.getItem("otm-font"); if (f) setFontQuiet(f);
  const sc = localStorage.getItem("otm-scale"); if (sc) setScaleQuiet(parseInt(sc, 10));
  if (localStorage.getItem("otm-sound") === "0" && window.OTM)
    try { window.OTM.call("sound", "off", "init"); } catch(e){}
})();
$("#btnTheme").onclick = () => {
  const cur = document.documentElement.dataset.theme ||
    (matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
  setTheme(cur === "dark" ? "light" : "dark");
};
$("#btnGear").onclick = () => { syncGear(); $("#gearMask").classList.add("open"); };
$("#gearDone").onclick = () => $("#gearMask").classList.remove("open");
$("#gearMask").onclick = e => { if (e.target.id === "gearMask") $("#gearMask").classList.remove("open"); };
document.querySelectorAll("#setTheme .seg-btn").forEach(b => b.onclick = () => setTheme(b.dataset.theme));
document.querySelectorAll("#setAccent .sw").forEach(b => b.onclick = () => setAccent(b.dataset.accent));
document.querySelectorAll("#setFont .seg-btn").forEach(b => b.onclick = () => setFont(b.dataset.font));
document.getElementById("setScale").oninput = e => setScale(parseInt(e.target.value, 10));
document.getElementById("setSound").onchange = e => setSound(e.target.checked);
const permBtn = (id, label) => { const b = document.getElementById(id); if (b) b.onclick = () => askPermission(id === "setPermApp" ? "perm.app" : id === "setPermFF" ? "perm.ff" : "perm.battery", label); };
permBtn("setPermApp", "Permissões do app do pack");
permBtn("setPermFF", "Permissões do Free Fire");
permBtn("setPermBattery", "Bateria sem economia");
const gearReset = document.getElementById("gearReset");
if (gearReset) gearReset.onclick = () => {
  ["otm-theme","otm-accent","otm-font","otm-scale"].forEach(k => localStorage.removeItem(k));
  delete document.documentElement.dataset.theme;
  setAccentQuiet("laranja"); setFontQuiet("sistema"); setScaleQuiet(100);
  syncGear(); toast("Aparência restaurada ao padrão.", "ok");
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
  if (a.id === "appearance"){ syncGear(); $("#gearMask").classList.add("open"); return; }
  const btn = card.querySelector("[data-run]");
  setBusy(true, btn);
  openConsole(a.label, "executando…");
  try{
    const r = await fetch("api.php?do=run", {
      method:"POST",
      headers:{"Content-Type":"application/json","X-OTM-Token":TOKEN},
      body: JSON.stringify({id:a.id, params, confirm:!!confirmed})
    });
    const j = await r.json();
    let head = (j.ok ? "✔ " : "✘ ") + "[" + (j.code ?? "?") + "]";
    if (j.applied && !j.real) head += "  — nenhuma mudança real no sistema";
    else if (j.changed > 0) head += "  — " + j.changed + " mudança(s) confirmada(s)";
    openConsole(a.label, head + "\n\n" + (j.out || j.error || ""));
    if (j.ok) toast("Feito: " + a.label, "ok");
    else if (j.applied && !j.real) toast("Nada mudou de verdade — veja Configs", "bad");
    else toast("Falhou: " + a.label, "bad");
  }catch(e){ openConsole(a.label, "erro: " + e); toast("Erro de rede", "bad"); }
  setBusy(false, btn);
}
document.querySelectorAll("[data-run]").forEach(b => b.onclick = () => run(b.closest(".card")));
const setBusy = (b, btn) => {
  document.querySelectorAll("[data-run]").forEach(x => x.disabled = b);
  if (btn) btn.classList.toggle("busy", b);
};

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
addEventListener("keydown", e => { if (e.key === "Escape"){ $("#mask").classList.remove("open"); $("#gearMask").classList.remove("open"); document.body.classList.remove("drawer"); } });

/* apps instalados (autocomplete) + estado do modo de acesso */
(async () => {
  try{
    const m = await apiGet("mode");
    const names = {rish:"Shizuku", adb:"ADB Wi-Fi", su:"root", local:"local (sem acesso)"};
    const txt = names[m.mode] || m.mode || "auto";
    $("#modeTxt").textContent = txt;
    const pill = $("#modePill");
    if (pill) pill.title = "Acesso: " + txt + (m.priv ? " — " + m.priv : "") + ". Configure em Configs.";
  }catch(e){ $("#modeTxt").textContent = "offline"; }
  try{ const i = await apiGet("info");
    if (!document.getElementById("modeTxt").textContent || document.getElementById("modeTxt").textContent === "verificando…")
      $("#modeTxt").textContent = (i.have_adb ? "ADB ok" : "sem ADB") + " · PHP " + i.php;
  }catch(e){}
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
