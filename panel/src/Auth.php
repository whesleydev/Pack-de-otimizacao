<?php
// =============================================================================
//  Auth.php - Login e sessão dos administradores do painel.
//
//  Aqui existe usuário e senha (diferente do cliente final, que usa chave).
//  A senha é guardada com password_hash (bcrypt) e conferida com
//  password_verify. A sessão fica no banco (otm_admin_sessions) para o painel
//  conseguir listar e derrubar acessos ativos.
//
//  Freio contra força bruta: após N falhas no mesmo IP em X minutos, o login
//  fica bloqueado por um tempo.
// =============================================================================

declare(strict_types=1);

final class Auth
{
    private const MAX_TRIES  = 8;    // tentativas por janela
    private const WINDOW_MIN = 15;   // janela de observação
    private const SESSION_H  = 12;   // validade da sessão em horas

    private ?array $admin = null;

    public function __construct(private OtmDb $db) {}

    // -------------------------------------------------------------------------
    //  login
    // -------------------------------------------------------------------------

    /** @return array{ok:bool,error?:string,admin?:array} */
    public function login(string $user, string $pass, string $ip, string $ua = ''): array
    {
        $user = strtolower(trim($user));

        if ($this->tooManyAttempts($ip)) {
            $this->recordAttempt($user, $ip, false);
            return ['ok' => false, 'error' => 'Muitas tentativas. Aguarde alguns minutos e tente de novo.'];
        }

        $row = $this->db->one('SELECT * FROM otm_admins WHERE lower(username) = ?', [$user]);
        $hash = $row['password_hash'] ?? '$2y$10$invalidinvalidinvalidinvalidinvalidinvalidinvalidinvalidinvalid';

        // password_verify sempre roda: o tempo de resposta não denuncia se o
        // usuário existe.
        $ok = password_verify($pass, (string)$hash);

        if (!$row || !$ok || (int)($row['is_active'] ?? 0) !== 1) {
            $this->recordAttempt($user, $ip, false);
            return ['ok' => false, 'error' => 'Usuário ou senha inválidos.'];
        }

        $this->recordAttempt($user, $ip, true);
        $this->db->run('UPDATE otm_admins SET last_login_at = ?, last_login_ip = ? WHERE id = ?',
                       [otm_now(), $ip, (int)$row['id']]);

        $this->openSession((int)$row['id'], $ip, $ua);
        return ['ok' => true, 'admin' => $row];
    }

    public function logout(): void
    {
        if (session_status() !== PHP_SESSION_ACTIVE) return;
        $sid = (string)($_SESSION['otm_sid'] ?? '');
        if ($sid !== '') {
            try { $this->db->run('DELETE FROM otm_admin_sessions WHERE id = ?', [$sid]); } catch (Throwable) {}
        }
        $_SESSION = [];
        if (ini_get('session.use_cookies')) {
            $p = session_get_cookie_params();
            setcookie(session_name(), '', time() - 42000, $p['path'], $p['domain'], (bool)$p['secure'], (bool)$p['httponly']);
        }
        @session_destroy();
    }

    // -------------------------------------------------------------------------
    //  sessão
    // -------------------------------------------------------------------------

    private function openSession(int $adminId, string $ip, string $ua): void
    {
        otm_session_start();
        session_regenerate_id(true);
        $sid = bin2hex(random_bytes(24));
        $_SESSION['otm_sid']     = $sid;
        $_SESSION['otm_admin_id'] = $adminId;
        $_SESSION['otm_csrf']    = bin2hex(random_bytes(16));
        $_SESSION['otm_login_at'] = time();

        $this->db->run(
            'INSERT INTO otm_admin_sessions (id, admin_id, ip, user_agent, created_at, last_seen_at, expires_at)
             VALUES (?,?,?,?,?,?,?)',
            [$sid, $adminId, $ip, otm_substr($ua, 0, 250), otm_now(), otm_now(),
             gmdate('Y-m-d H:i:s', time() + self::SESSION_H * 3600)]
        );
    }

    /** Admin logado (ou null). Valida a sessão contra o banco. */
    public function user(): ?array
    {
        if ($this->admin !== null) return $this->admin;
        if (session_status() !== PHP_SESSION_ACTIVE) return null;

        $sid = (string)($_SESSION['otm_sid'] ?? '');
        if ($sid === '') return null;

        $row = $this->db->one(
            'SELECT s.id AS sid, s.expires_at, a.*
               FROM otm_admin_sessions s JOIN otm_admins a ON a.id = s.admin_id
              WHERE s.id = ? AND s.expires_at > ?',
            [$sid, otm_now()]
        );
        if (!$row || (int)($row['is_active'] ?? 0) !== 1) return null;

        $this->db->run('UPDATE otm_admin_sessions SET last_seen_at = ? WHERE id = ?', [otm_now(), $sid]);
        return $this->admin = $row;
    }

    public function check(): bool { return $this->user() !== null; }

    public function isOwner(): bool { return ($this->user()['role'] ?? '') === 'owner'; }

    /** Pode escrever (owner/admin); viewer só lê. */
    public function canWrite(): bool
    {
        return in_array($this->user()['role'] ?? '', ['owner', 'admin'], true);
    }

    // -------------------------------------------------------------------------
    //  CSRF
    // -------------------------------------------------------------------------

    public function csrf(): string
    {
        otm_session_start();
        if (empty($_SESSION['otm_csrf'])) $_SESSION['otm_csrf'] = bin2hex(random_bytes(16));
        return (string)$_SESSION['otm_csrf'];
    }

    public function csrfOk(?string $t): bool
    {
        return is_string($t) && $t !== ''
            && !empty($_SESSION['otm_csrf'])
            && hash_equals((string)$_SESSION['otm_csrf'], $t);
    }

    // -------------------------------------------------------------------------
    //  administradores
    // -------------------------------------------------------------------------

    /** Cria/atualiza um admin pelo nome de usuário (usado pelo CLI). */
    public function upsert(string $username, string $password, string $role = 'admin', string $name = '', string $email = ''): int
    {
        $username = strtolower(trim($username));
        $hash = password_hash($password, PASSWORD_DEFAULT);
        $ex = $this->db->one('SELECT id FROM otm_admins WHERE username = ?', [$username]);
        if ($ex) {
            $this->db->run('UPDATE otm_admins SET password_hash = ?, role = ?, name = ?, email = ?, is_active = 1, updated_at = ? WHERE id = ?',
                           [$hash, $role, otm_str($name, 120), otm_str($email, 160), otm_now(), (int)$ex['id']]);
            return (int)$ex['id'];
        }
        return $this->db->insert(
            'INSERT INTO otm_admins (username, name, email, password_hash, role, created_at) VALUES (?,?,?,?,?,?)',
            [$username, otm_str($name, 120), otm_str($email, 160), $hash, $role, otm_now()]
        );
    }

    public function countAdmins(): int
    {
        return (int)$this->db->scalar('SELECT COUNT(*) FROM otm_admins');
    }

    public function sessions(int $adminId): array
    {
        return $this->db->all(
            'SELECT * FROM otm_admin_sessions WHERE admin_id = ? AND expires_at > ? ORDER BY last_seen_at DESC',
            [$adminId, otm_now()]
        );
    }

    public function killSession(string $sid): void
    {
        $this->db->run('DELETE FROM otm_admin_sessions WHERE id = ?', [$sid]);
    }

    // -------------------------------------------------------------------------
    //  força bruta
    // -------------------------------------------------------------------------

    private function tooManyAttempts(string $ip): bool
    {
        if ($ip === '') return false;
        $n = (int)$this->db->scalar(
            "SELECT COUNT(*) FROM otm_login_attempts
              WHERE ip = ? AND ok = 0 AND created_at > datetime('now', ?)",
            [$ip, '-' . self::WINDOW_MIN . ' minutes']
        );
        return $n >= self::MAX_TRIES;
    }

    private function recordAttempt(string $user, string $ip, bool $ok): void
    {
        try {
            $this->db->run('INSERT INTO otm_login_attempts (username, ip, ok, created_at) VALUES (?,?,?,?)',
                           [otm_substr($user, 0, 80), $ip, $ok ? 1 : 0, otm_now()]);
            if (random_int(1, 20) === 1) {
                $this->db->run("DELETE FROM otm_login_attempts WHERE created_at < datetime('now','-7 day')");
            }
        } catch (Throwable) {}
    }
}

/** Sobe a sessão com cookie httpOnly (mesmos ajustes para todo o painel). */
function otm_session_start(): void
{
    if (session_status() === PHP_SESSION_ACTIVE) return;
    if (headers_sent()) return;
    session_name('otm_admin');
    session_set_cookie_params([
        'lifetime' => 0,
        'path'     => '/',
        'httponly' => true,
        'samesite' => 'Lax',
        'secure'   => (($_SERVER['HTTPS'] ?? '') === 'on'),
    ]);
    @session_start();
}
