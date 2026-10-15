<?php
// Temporário: renderiza o painel logado como HTML estático (para embutir no app).
declare(strict_types=1);
session_name('otm_sess');
$_SESSION = [];
session_start();
$_SESSION['otm_user'] = '00deUdia';
$_SESSION['otm_csrf'] = 'static-capture';
require __DIR__ . '/index.php';
