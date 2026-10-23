<?php
// =============================================================================
//  KeyService.php - Regras de negócio das chaves (licenças).
//
//  É o único lugar que decide o que é uma chave "ativa". O painel, o endpoint
//  do app e o CLI chamam estes métodos — assim as três pontas nunca divergem.
//
//  Situações de uma chave:
//    active    — vale agora
//    expired   — passou da data (o acesso acabou sozinho)
//    revoked   — alguém cortou na mão
//    exhausted — bateu o limite de usos
//    scheduled — ainda não usada; expira a partir do 1º uso
// =============================================================================

declare(strict_types=1);

final class KeyService
{
    public function __construct(private OtmDb $db) {}

    // -------------------------------------------------------------------------
    //  leitura
    // -------------------------------------------------------------------------

    /**
     * Lista chaves com filtros e paginação.
     * @param array{q?:string,status?:string,plan?:int,limit?:int,offset?:int,order?:string} $f
     * @return array{rows:array,total:int}
     */
    public function search(array $f = []): array
    {
        $where = [];
        $args  = [];

        $q = trim((string)($f['q'] ?? ''));
        if ($q !== '') {
            $where[] = '(k.label LIKE ? OR k.owner_contact LIKE ? OR k.note LIKE ? OR k.key_prefix LIKE ?)';
            $like = '%' . $q . '%';
            array_push($args, $like, $like, $like, $like);
        }

        if (!empty($f['plan'])) {
            $where[] = 'k.plan_id = ?';
            $args[]  = (int)$f['plan'];
        }

        $now = otm_now();
        $status = (string)($f['status'] ?? '');
        $cond = [
            'active'    => "k.revoked_at IS NULL AND (k.expires_at IS NULL OR k.expires_at > ?) AND (k.max_uses = 0 OR k.uses_count < k.max_uses)",
            'expired'   => "k.revoked_at IS NULL AND k.expires_at IS NOT NULL AND k.expires_at <= ?",
            'revoked'   => "k.revoked_at IS NOT NULL",
            'exhausted' => "k.revoked_at IS NULL AND k.max_uses > 0 AND k.uses_count >= k.max_uses AND (k.expires_at IS NULL OR k.expires_at > ?)",
        ];
        if (isset($cond[$status])) {
            $where[] = '(' . $cond[$status] . ')';
            $args[]  = $now;
        }

        $w = $where ? ' WHERE ' . implode(' AND ', $where) : '';

        $total = (int)$this->db->scalar('SELECT COUNT(*) FROM otm_keys k' . $w, $args);

        $limit  = max(1, min(200, (int)($f['limit'] ?? 25)));
        $offset = max(0, (int)($f['offset'] ?? 0));

        $order = match ((string)($f['order'] ?? 'recent')) {
            'oldest'   => 'k.created_at ASC',
            'expiring' => 'k.expires_at IS NULL, k.expires_at ASC',
            'label'    => 'k.label COLLATE NOCASE ASC',
            default    => 'k.created_at DESC',
        };

        $rows = $this->db->all(
            'SELECT k.*, p.name AS plan_name
               FROM otm_keys k LEFT JOIN otm_plans p ON p.id = k.plan_id' . $w .
            ' ORDER BY ' . $order . ' LIMIT ? OFFSET ?',
            [...$args, $limit, $offset]
        );

        return ['rows' => array_map([$this, 'decorate'], $rows), 'total' => $total];
    }

    public function find(int $id): ?array
    {
        $row = $this->db->one(
            'SELECT k.*, p.name AS plan_name
               FROM otm_keys k LEFT JOIN otm_plans p ON p.id = k.plan_id WHERE k.id = ?',
            [$id]
        );
        return $row ? $this->decorate($row) : null;
    }

    /** Acrescenta campos calculados (status, dias restantes). */
    public function decorate(array $row): array
    {
        $row['status']    = $this->statusOf($row);
        $row['days_left'] = otm_days_left($row['expires_at'] ?? null);
        $row['devices']   = (int)($row['device_count'] ?? 0);
        return $row;
    }

    public function statusOf(array $row): string
    {
        if (!empty($row['revoked_at'])) return 'revoked';
        $exp = $row['expires_at'] ?? null;
        if ($exp !== null && $exp !== '' && $exp <= otm_now()) return 'expired';
        $max = (int)($row['max_uses'] ?? 0);
        if ($max > 0 && (int)($row['uses_count'] ?? 0) >= $max) return 'exhausted';
        return 'active';
    }

    // -------------------------------------------------------------------------
    //  escrita
    // -------------------------------------------------------------------------

    /**
     * Cria uma chave. Devolve a chave em TEXTO uma única vez — depois só o hash
     * existe. duration_days null = vitalício.
     * @param array{label?:string,owner_contact?:string,note?:string,plan_id?:?int,
     *              duration_days?:?int,max_devices?:int,max_uses?:int,created_by?:string} $in
     * @return array{id:int,key:string,row:array}
     */
    public function create(array $in): array
    {
        $raw  = otm_key_generate();
        $days = array_key_exists('duration_days', $in) ? $in['duration_days'] : 30;
        $days = ($days === null) ? null : max(0, (int)$days);

        $id = $this->db->insert(
            'INSERT INTO otm_keys
                (key_hash, key_prefix, label, owner_contact, note, plan_id, duration_days,
                 max_devices, max_uses, created_at, expires_at, created_by)
             VALUES (?,?,?,?,?,?,?,?,?,?,?,?)',
            [
                otm_key_hash($raw),
                otm_key_prefix_of($raw),
                otm_str($in['label'] ?? '', 120),
                otm_str($in['owner_contact'] ?? '', 160),
                otm_str($in['note'] ?? '', 500),
                !empty($in['plan_id']) ? (int)$in['plan_id'] : null,
                $days,
                max(0, (int)($in['max_devices'] ?? 1)),
                max(0, (int)($in['max_uses'] ?? 0)),
                otm_now(),
                otm_expiry_from_days($days),
                otm_str($in['created_by'] ?? '', 80),
            ]
        );

        return ['id' => $id, 'key' => $raw, 'row' => $this->find($id) ?? []];
    }

    /** Campos que o painel pode editar depois de criada. */
    public function update(int $id, array $in): bool
    {
        $sets = [];
        $args = [];

        foreach (['label' => 120, 'owner_contact' => 160, 'note' => 500] as $col => $max) {
            if (array_key_exists($col, $in)) { $sets[] = "$col = ?"; $args[] = otm_str((string)$in[$col], $max); }
        }
        if (array_key_exists('max_devices', $in)) { $sets[] = 'max_devices = ?'; $args[] = max(0, (int)$in['max_devices']); }
        if (array_key_exists('max_uses', $in))    { $sets[] = 'max_uses = ?';    $args[] = max(0, (int)$in['max_uses']); }
        if (array_key_exists('plan_id', $in))     { $sets[] = 'plan_id = ?';     $args[] = !empty($in['plan_id']) ? (int)$in['plan_id'] : null; }

        if (!$sets) return false;
        $args[] = $id;
        return $this->db->run('UPDATE otm_keys SET ' . implode(', ', $sets) . ' WHERE id = ?', $args) >= 0;
    }

    /**
     * Muda a duração (a partir de agora). days=null vira vitalício.
     * É o "mudar a duração" do painel.
     */
    public function setDuration(int $id, ?int $days): bool
    {
        $days = $days === null ? null : max(0, $days);
        return $this->db->run(
            'UPDATE otm_keys SET duration_days = ?, expires_at = ? WHERE id = ?',
            [$days, otm_expiry_from_days($days), $id]
        ) >= 0;
    }

    /** Estende a partir da data atual de expiração (ou de agora, se já venceu). */
    public function extend(int $id, int $days): bool
    {
        $row = $this->find($id);
        if (!$row) return false;
        $base = $row['expires_at'] ?: otm_now();
        $ts   = strtotime($base . ' UTC');
        $ts   = ($ts === false || $ts < time()) ? time() : $ts;
        return $this->db->run(
            'UPDATE otm_keys SET expires_at = ?, revoked_at = NULL WHERE id = ?',
            [gmdate('Y-m-d H:i:s', $ts + max(0, $days) * 86400), $id]
        ) >= 0;
    }

    public function revoke(int $id, string $reason = ''): bool
    {
        return $this->db->run(
            'UPDATE otm_keys SET revoked_at = ?, revoked_reason = ? WHERE id = ? AND revoked_at IS NULL',
            [otm_now(), otm_str($reason, 200), $id]
        ) >= 0;
    }

    public function restore(int $id): bool
    {
        return $this->db->run(
            'UPDATE otm_keys SET revoked_at = NULL, revoked_reason = ? WHERE id = ?',
            ['', $id]
        ) >= 0;
    }

    public function delete(int $id): bool
    {
        // devices/events caem junto pelo ON DELETE CASCADE / SET NULL
        return $this->db->run('DELETE FROM otm_keys WHERE id = ?', [$id]) >= 0;
    }

    // -------------------------------------------------------------------------
    //  validação (usada pelo endpoint do app)
    // -------------------------------------------------------------------------

    /**
     * Confere uma chave vinda do app e registra o evento.
     * @param array{device_id?:string,model?:string,android_ver?:string,app_version?:string} $device
     * @return array{ok:bool,result:string,message:string,key_id:?int,label:string,expires_at:?string,days_left:?int}
     */
    public function validate(string $raw, array $device = [], string $ip = ''): array
    {
        $deviceId = otm_str($device['device_id'] ?? '', 120);
        $model    = otm_str($device['model'] ?? '', 80);
        $android  = otm_str($device['android_ver'] ?? '', 20);
        $appVer   = otm_str($device['app_version'] ?? '', 40);

        $prefix = otm_key_prefix_of($raw);

        $fail = function (string $result, string $message, ?int $keyId = null) use ($prefix, $deviceId, $model, $appVer, $ip): array {
            $this->logEvent($keyId, $prefix, $result, $deviceId, $model, $appVer, $ip, $message);
            return ['ok' => false, 'result' => $result, 'message' => $message,
                    'key_id' => $keyId, 'label' => '', 'expires_at' => null, 'days_left' => null];
        };

        if (!otm_key_well_formed($raw)) {
            return $fail('unknown', 'Chave em formato inválido.');
        }

        $row = $this->db->one('SELECT * FROM otm_keys WHERE key_hash = ?', [otm_key_hash($raw)]);
        if (!$row) {
            return $fail('unknown', 'Chave não encontrada.');
        }

        $keyId = (int)$row['id'];
        $status = $this->statusOf($row);

        if ($status === 'revoked')  return $fail('revoked', 'Chave revogada.', $keyId);
        if ($status === 'expired')  return $fail('expired', 'Chave expirada.', $keyId);
        if ($status === 'exhausted') return $fail('use_limit', 'Limite de usos atingido.', $keyId);

        // limite de aparelhos (0 = ilimitado)
        $maxDev = (int)$row['max_devices'];
        if ($maxDev > 0 && $deviceId !== '') {
            $known = $this->db->one(
                'SELECT id, blocked_at FROM otm_key_devices WHERE key_id = ? AND device_id = ?',
                [$keyId, $deviceId]
            );
            if ($known && !empty($known['blocked_at'])) {
                return $fail('blocked', 'Este aparelho está bloqueado para esta chave.', $keyId);
            }
            if (!$known) {
                $n = (int)$this->db->scalar(
                    'SELECT COUNT(*) FROM otm_key_devices WHERE key_id = ? AND blocked_at IS NULL',
                    [$keyId]
                );
                if ($n >= $maxDev) {
                    return $fail('device_limit', 'Limite de aparelhos atingido (' . $maxDev . ').', $keyId);
                }
            }
        }

        // passou: marca uso e atualiza o aparelho
        $now = otm_now();
        $this->db->run(
            'UPDATE otm_keys
                SET uses_count = uses_count + 1,
                    last_used_at = ?, last_seen_ip = ?,
                    activated_at = COALESCE(activated_at, ?)
              WHERE id = ?',
            [$now, $ip, $now, $keyId]
        );

        if ($deviceId !== '') {
            $this->db->run(
                'INSERT INTO otm_key_devices (key_id, device_id, model, android_ver, app_version, first_seen_at, last_seen_at, last_ip)
                 VALUES (?,?,?,?,?,?,?,?)
                 ON CONFLICT(key_id, device_id) DO UPDATE SET
                    last_seen_at = excluded.last_seen_at,
                    last_ip = excluded.last_ip,
                    model = CASE WHEN excluded.model <> \'\' THEN excluded.model ELSE model END,
                    android_ver = CASE WHEN excluded.android_ver <> \'\' THEN excluded.android_ver ELSE android_ver END,
                    app_version = CASE WHEN excluded.app_version <> \'\' THEN excluded.app_version ELSE app_version END',
                [$keyId, $deviceId, $model, $android, $appVer, $now, $now, $ip]
            );
        }

        $this->logEvent($keyId, $prefix, 'ok', $deviceId, $model, $appVer, $ip, '');

        $exp = $row['expires_at'] ?? null;
        return [
            'ok'         => true,
            'result'     => 'ok',
            'message'    => 'Chave válida.',
            'key_id'     => $keyId,
            'label'      => (string)$row['label'],
            'expires_at' => $exp,
            'days_left'  => otm_days_left($exp),
        ];
    }

    private function logEvent(?int $keyId, string $prefix, string $result, string $deviceId,
                              string $model, string $appVer, string $ip, string $detail): void
    {
        $this->db->run(
            'INSERT INTO otm_key_events (key_id, key_prefix, result, device_id, model, app_version, ip, detail, created_at)
             VALUES (?,?,?,?,?,?,?,?,?)',
            [$keyId, $prefix, $result, $deviceId, $model, $appVer, $ip, $detail, otm_now()]
        );
    }

    // -------------------------------------------------------------------------
    //  aparelhos e eventos
    // -------------------------------------------------------------------------

    public function devices(int $keyId): array
    {
        return $this->db->all(
            'SELECT * FROM otm_key_devices WHERE key_id = ? ORDER BY last_seen_at DESC',
            [$keyId]
        );
    }

    public function blockDevice(int $keyId, string $deviceId, bool $block = true): bool
    {
        return $this->db->run(
            'UPDATE otm_key_devices SET blocked_at = ? WHERE key_id = ? AND device_id = ?',
            [$block ? otm_now() : null, $keyId, $deviceId]
        ) >= 0;
    }

    /** Apaga o aparelho da lista: libera a vaga para outro. */
    public function forgetDevice(int $keyId, string $deviceId): bool
    {
        return $this->db->run(
            'DELETE FROM otm_key_devices WHERE key_id = ? AND device_id = ?',
            [$keyId, $deviceId]
        ) >= 0;
    }

    public function events(int $keyId, int $limit = 50): array
    {
        return $this->db->all(
            'SELECT * FROM otm_key_events WHERE key_id = ? ORDER BY created_at DESC LIMIT ?',
            [$keyId, $limit]
        );
    }

    public function recentEvents(int $limit = 40): array
    {
        return $this->db->all(
            'SELECT e.*, k.label FROM otm_key_events e
               LEFT JOIN otm_keys k ON k.id = e.key_id
              ORDER BY e.created_at DESC LIMIT ?',
            [$limit]
        );
    }

    /** Preenche device_count em lote (evita N+1 na listagem). */
    public function attachDeviceCounts(array $rows): array
    {
        if (!$rows) return $rows;
        $ids = array_map(static fn(array $r) => (int)$r['id'], $rows);
        $in  = implode(',', array_fill(0, count($ids), '?'));
        $counts = [];
        foreach ($this->db->all(
            "SELECT key_id, COUNT(*) n FROM otm_key_devices WHERE blocked_at IS NULL AND key_id IN ($in) GROUP BY key_id",
            $ids
        ) as $r) {
            $counts[(int)$r['key_id']] = (int)$r['n'];
        }
        foreach ($rows as &$r) $r['device_count'] = $counts[(int)$r['id']] ?? 0;
        unset($r);
        return $rows;
    }

    // -------------------------------------------------------------------------
    //  métricas do painel
    // -------------------------------------------------------------------------

    public function stats(): array
    {
        $now = otm_now();
        return [
            'total'     => (int)$this->db->scalar('SELECT COUNT(*) FROM otm_keys'),
            'active'    => (int)$this->db->scalar(
                'SELECT COUNT(*) FROM otm_keys WHERE revoked_at IS NULL AND (expires_at IS NULL OR expires_at > ?) AND (max_uses = 0 OR uses_count < max_uses)', [$now]),
            'expired'   => (int)$this->db->scalar(
                'SELECT COUNT(*) FROM otm_keys WHERE revoked_at IS NULL AND expires_at IS NOT NULL AND expires_at <= ?', [$now]),
            'revoked'   => (int)$this->db->scalar('SELECT COUNT(*) FROM otm_keys WHERE revoked_at IS NOT NULL'),
            'devices'   => (int)$this->db->scalar('SELECT COUNT(*) FROM otm_key_devices'),
            'checks24h' => (int)$this->db->scalar(
                "SELECT COUNT(*) FROM otm_key_events WHERE created_at > datetime('now','-1 day')"),
            'fails24h'  => (int)$this->db->scalar(
                "SELECT COUNT(*) FROM otm_key_events WHERE result <> 'ok' AND created_at > datetime('now','-1 day')"),
            'expiring7' => (int)$this->db->scalar(
                'SELECT COUNT(*) FROM otm_keys WHERE revoked_at IS NULL AND expires_at IS NOT NULL
                   AND expires_at > ? AND expires_at <= datetime(?, \'+7 day\')', [$now, $now]),
        ];
    }
}
