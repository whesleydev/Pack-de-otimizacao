<?php
// =============================================================================
//  Audit.php - Registro de quem fez o quê no painel.
//
//  Toda ação que muda algo (criar/revogar/editar chave, mexer em plano,
//  login…) deixa uma linha em otm_audit. É o que permite responder "quem
//  revogou a chave do cliente?" semanas depois.
// =============================================================================

declare(strict_types=1);

final class Audit
{
    public function __construct(private OtmDb $db) {}

    public function log(string $action, string $entity = '', string $entityId = '',
                        string $details = '', ?array $admin = null): void
    {
        try {
            $this->db->run(
                'INSERT INTO otm_audit (admin_id, actor, action, entity, entity_id, details, ip, created_at)
                 VALUES (?,?,?,?,?,?,?,?)',
                [
                    $admin['id'] ?? null,
                    (string)($admin['username'] ?? 'sistema'),
                    $action,
                    $entity,
                    (string)$entityId,
                    otm_substr($details, 0, 500),
                    otm_client_ip(),
                    otm_now(),
                ]
            );
        } catch (Throwable) {
            // auditoria nunca deve derrubar a ação principal
        }
    }

    public function recent(int $limit = 100, int $offset = 0): array
    {
        return $this->db->all(
            'SELECT * FROM otm_audit ORDER BY created_at DESC LIMIT ? OFFSET ?',
            [$limit, $offset]
        );
    }

    public function count(): int
    {
        return (int)$this->db->scalar('SELECT COUNT(*) FROM otm_audit');
    }

    /** Apaga registros antigos (mais de N dias). Devolve quantos sobraram. */
    public function prune(int $days): int
    {
        $limite = gmdate('Y-m-d H:i:s', time() - max(1, $days) * 86400);
        $this->db->run('DELETE FROM otm_audit WHERE created_at < ?', [$limite]);
        return $this->count();
    }

    /** Apaga tudo (usado quando o log fica grande demais). */
    public function clear(): void
    {
        $this->db->run('DELETE FROM otm_audit');
    }
}
