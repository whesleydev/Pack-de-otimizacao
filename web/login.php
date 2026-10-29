<?php
// =============================================================================
//  login.php - Tela de entrada do painel Trix.
//  Renderizada por index.php quando não há sessão. Não mostra nada do pack
//  antes de autenticar.
// =============================================================================

declare(strict_types=1);
require_once __DIR__ . '/auth.php';

$erro = (string)($_GET['erro'] ?? '');
$csrf = otm_csrf();
?>
<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#0d0c0a">
<title>Entrar — Trix</title>
<link rel="icon" href="assets/banner.jpeg">
<style>
:root{
  --paper:#f3efe7; --ink:#1a1713; --muted:#6b655b;
  --line:rgba(120,110,95,.22); --line-strong:rgba(120,110,95,.34);
  --accent:#8d939e; --accent-ink:#fff; --danger:#bc332a;
  --glass:rgba(255,255,255,.55); --glass-2:rgba(255,255,255,.34);
  --blur:saturate(150%) blur(18px);
  --ring:rgba(141,147,158,.35);
  --shadow:0 1px 2px rgba(25,22,18,.06),0 14px 34px -18px rgba(25,22,18,.35);
  --r:18px; --r-sm:11px;
  --font:"Segoe UI",system-ui,-apple-system,Roboto,Helvetica,Arial,sans-serif;
}
@media (prefers-color-scheme: dark){
  :root{ --paper:#0d0c0a; --ink:#f3efe7; --muted:#a49d90;
    --line:rgba(255,255,255,.12); --line-strong:rgba(255,255,255,.2);
    --accent:#c7ccd6; --accent-ink:#14161a; --danger:#ff6b5e;
    --glass:rgba(30,28,24,.5); --glass-2:rgba(30,28,24,.34);
    --shadow:0 1px 2px rgba(0,0,0,.45),0 16px 40px -20px rgba(0,0,0,.8); }
}
@keyframes otmRise{from{opacity:0;transform:translateY(16px)}to{opacity:1;transform:none}}
@keyframes otmFade{from{opacity:0}to{opacity:1}}
@keyframes otmPop{from{opacity:0;transform:scale(.94)}to{opacity:1;transform:none}}
@keyframes otmSheen{0%{background-position:-160% 0}60%,100%{background-position:260% 0}}
@keyframes otmSpin{to{transform:rotate(360deg)}}
@keyframes otmShake{10%,90%{transform:translateX(-2px)}30%,70%{transform:translateX(3px)}50%{transform:translateX(-4px)}}
@media (prefers-reduced-motion: reduce){*{animation-duration:.001ms!important;transition-duration:.001ms!important}}
*{box-sizing:border-box}
html,body{margin:0;min-height:100%}
body{
  font-family:var(--font); color:var(--ink); line-height:1.55; min-height:100dvh;
  display:flex; flex-direction:column; padding:22px; overflow-x:hidden;
  background:url('assets/wallpaper.jpeg') center/cover fixed no-repeat var(--paper);
}
body::before{content:"";position:fixed;inset:0;z-index:-1;background:var(--paper);opacity:.82}
/* o cartão ocupa o espaço todo e fica centrado; os créditos descem para o rodapé */
.wrap{width:100%; max-width:380px; margin:auto; animation:otmRise .5s cubic-bezier(.2,.7,.3,1) both}
.brand{display:flex; flex-direction:column; align-items:center; gap:10px; margin-bottom:18px; animation:otmFade .6s both}
.mark{width:56px; height:56px; border-radius:16px; display:grid; place-items:center;
  background:var(--accent); color:var(--accent-ink); font-weight:800; font-size:20px;
  box-shadow:var(--shadow); animation:otmPop .5s .1s both}
.brand h1{margin:0; font-size:20px; font-weight:800; letter-spacing:-.02em}
.brand p{margin:0; color:var(--muted); font-size:13px}
.card{
  background:var(--glass); backdrop-filter:var(--blur); -webkit-backdrop-filter:var(--blur);
  border:1px solid var(--line); border-radius:var(--r); padding:22px;
  box-shadow:var(--shadow); animation:otmRise .5s .06s cubic-bezier(.2,.7,.3,1) both;
}
label{display:block; font-size:12px; font-weight:700; color:var(--muted); margin:0 0 5px 3px}
.field{margin-bottom:14px}
input{
  width:100%; padding:12px 14px; border-radius:var(--r-sm); border:1px solid var(--line-strong);
  background:var(--glass-2); color:var(--ink); font-size:15px; transition:border-color .15s, box-shadow .15s;
}
input:focus-visible{outline:none; border-color:var(--accent); box-shadow:0 0 0 3px var(--ring)}
.pw{position:relative}
.pw button{position:absolute; right:6px; top:50%; transform:translateY(-50%); border:0; background:transparent;
  color:var(--muted); cursor:pointer; padding:8px; border-radius:8px; font-size:13px}
.btn{
  width:100%; border:1px solid var(--accent); background:var(--accent); color:var(--accent-ink);
  border-radius:var(--r-sm); padding:12px 16px; font-size:15px; font-weight:800; cursor:pointer;
  position:relative; overflow:hidden; transition:transform .12s, filter .15s;
}
.btn:hover{filter:brightness(1.06)}
.btn:active{transform:scale(.98)}
.btn::after{content:""; position:absolute; inset:0; pointer-events:none;
  background:linear-gradient(100deg,transparent 30%,rgba(255,255,255,.35) 50%,transparent 70%);
  background-size:220% 100%; animation:otmSheen 5s ease-in-out infinite}
.btn.busy::before{content:""; display:inline-block; width:13px; height:13px; margin-right:8px; vertical-align:-2px;
  border:2px solid currentColor; border-right-color:transparent; border-radius:50%; animation:otmSpin .7s linear infinite}
.erro{
  display:flex; gap:9px; align-items:flex-start; margin:0 0 14px; padding:11px 13px; font-size:13px;
  border:1px solid var(--danger); border-left-width:4px; border-radius:var(--r-sm); color:var(--ink);
  background:var(--glass-2); animation:otmShake .4s both;
}
.erro b{color:var(--danger)}
.hint{margin:14px 0 0; font-size:12px; color:var(--muted); text-align:center}
.hint code{background:var(--glass-2); border:1px solid var(--line); border-radius:6px; padding:1px 6px}
.foot{margin-top:16px; text-align:center; font-size:11.5px; color:var(--muted); animation:otmFade .7s .2s both}
.credits{margin-top:20px; padding-top:16px; border-top:1px solid var(--line); text-align:center;
  font-size:12px; color:var(--muted); animation:otmFade .7s .3s both}
.credits .who{margin:0 0 10px}
.credits .who b{color:var(--ink)}
.credits .who code{color:var(--accent)}
.dcb{display:inline-flex; align-items:center; gap:8px; text-decoration:none;
  border:1px solid var(--line-strong); background:var(--glass-2); border-radius:999px;
  padding:9px 15px; font-size:12.5px; font-weight:700; color:var(--ink); transition:.15s}
.dcb:hover{border-color:var(--accent); transform:translateY(-1px)}
.dcb svg{width:17px; height:17px; fill:currentColor; flex:none}
.dcb .arw{font-size:11px; color:var(--muted)}
</style>
</head>
<body>
<div class="wrap">
  <div class="brand">
    <div class="mark" aria-hidden="true">TX</div>
    <h1>Trix</h1>
    <p>Entre para acessar o painel</p>
  </div>

  <form class="card" method="post" action="index.php" autocomplete="on">
    <?php if ($erro !== ''): ?>
      <div class="erro" role="alert"><span aria-hidden="true">⚠</span>
        <div><b>Não deu para entrar.</b><br><?= htmlspecialchars($erro, ENT_QUOTES) ?></div></div>
    <?php endif; ?>
    <input type="hidden" name="csrf" value="<?= htmlspecialchars($csrf, ENT_QUOTES) ?>">
    <div class="field">
      <label for="user">Usuário</label>
      <input id="user" name="user" type="text" inputmode="text" autocomplete="username"
             required autofocus>
    </div>
    <div class="field">
      <label for="pass">Senha</label>
      <div class="pw">
        <input id="pass" name="pass" type="password" autocomplete="current-password" required>
        <button type="button" id="toggle" aria-label="Mostrar senha">ver</button>
      </div>
    </div>
    <button class="btn" id="entrar" type="submit">Entrar</button>
  </form>

  <div class="foot">Painel local — sem root, via Shizuku ou ADB por Wi-Fi.</div>
</div>

<!-- Fora do .wrap: o cartão fica centrado e os créditos descem para o rodapé. -->
<div class="credits">
    <p class="who">Criado por <b>00deUdia</b> · Discord <code>cute_axolotl_51194</code></p>
    <a class="dcb" href="https://discord.com/users/cute_axolotl_51194" target="_blank" rel="noopener"
       title="Abrir meu perfil no Discord">
      <svg viewBox="0 0 127.14 96.36" aria-hidden="true"><path d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z"/></svg>
      Meu Discord <span class="arw">↗</span>
    </a>
    <a class="dcb" href="https://discord.gg/w9hFBeVKw8" target="_blank" rel="noopener"
       title="Entrar no meu servidor do Discord" style="margin-left:8px">
      <svg viewBox="0 0 127.14 96.36" aria-hidden="true"><path d="M107.7,8.07A105.15,105.15,0,0,0,81.47,0a72.06,72.06,0,0,0-3.36,6.83A97.68,97.68,0,0,0,49,6.83,72.37,72.37,0,0,0,45.64,0,105.89,105.89,0,0,0,19.39,8.09C2.79,32.65-1.71,56.6.54,80.21h0A105.73,105.73,0,0,0,32.71,96.36,77.7,77.7,0,0,0,39.6,85.25a68.42,68.42,0,0,1-10.85-5.18c.91-.66,1.8-1.34,2.66-2a75.57,75.57,0,0,0,64.32,0c.87.71,1.76,1.39,2.66,2a68.68,68.68,0,0,1-10.87,5.19,77,77,0,0,0,6.89,11.1A105.25,105.25,0,0,0,126.6,80.22h0C129.24,52.84,122.09,29.11,107.7,8.07ZM42.45,65.69C36.18,65.69,31,60,31,53s5-12.74,11.43-12.74S54,46,53.89,53,48.84,65.69,42.45,65.69Zm42.24,0C78.41,65.69,73.25,60,73.25,53s5-12.74,11.44-12.74S96.23,46,96.12,53,91.08,65.69,84.69,65.69Z"/></svg>
      Servidor <span class="arw">↗</span>
    </a>
</div>

<script>
document.getElementById("toggle").onclick = (e) => {
  const p = document.getElementById("pass");
  const on = p.type === "password";
  p.type = on ? "text" : "password";
  e.currentTarget.textContent = on ? "ocultar" : "ver";
  e.currentTarget.setAttribute("aria-label", on ? "Ocultar senha" : "Mostrar senha");
};
document.querySelector("form").addEventListener("submit", () => {
  document.getElementById("entrar").classList.add("busy");
  document.getElementById("entrar").textContent = "Entrando…";
});
</script>
</body>
</html>
