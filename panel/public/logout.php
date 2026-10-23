<?php
// =============================================================================
//  logout.php - Encerra a sessão do administrador.
// =============================================================================

declare(strict_types=1);

require __DIR__ . '/../src/guard.php';

$auth->logout();
otm_redirect('login.php');
