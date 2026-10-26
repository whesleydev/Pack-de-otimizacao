<?php
// =============================================================================
//  Db.php - Banco local (SQLite) com a MESMA interface do Turso.
//
//  Serve para dois casos:
//    1) desenvolvimento e testes sem internet (nenhuma chamada de rede);
//    2) quem prefere rodar o painel com um arquivo .sqlite em vez do Turso.
//
//  O código do painel (Auth, Audit…) não sabe qual dos dois está
//  embaixo: chama all/one/scalar/run/insert e pronto. Trocar de banco é só
//  mudar a configuração, não o código.
//
//  Ativação: defina OTM_LOCAL_DB com o caminho do arquivo, por exemplo
//      OTM_LOCAL_DB=/tmp/painel.sqlite php panel/bin/migrate.php
//  Quando o Turso está configurado, ele tem prioridade.
// =============================================================================

declare(strict_types=1);

final class DbError extends RuntimeException {}

final class Db implements OtmDb
{
    private PDO $pdo;

    public function __construct(string $file)
    {
        if ($file === '') throw new DbError('Db: caminho vazio.');
        $dir = dirname($file);
        if (!is_dir($dir) && !@mkdir($dir, 0775, true) && !is_dir($dir)) {
            throw new DbError("Db: não consegui criar a pasta $dir.");
        }
        try {
            $this->pdo = new PDO('sqlite:' . $file, null, null, [
                PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            ]);
            $this->pdo->exec('PRAGMA journal_mode = WAL');
            $this->pdo->exec('PRAGMA foreign_keys = ON');
            $this->pdo->exec('PRAGMA busy_timeout = 5000');
        } catch (PDOException $e) {
            throw new DbError('Db: ' . $e->getMessage());
        }
    }

    /** Caminho vindo de OTM_LOCAL_DB (ou o padrão em config/local.php). */
    public static function fromConfig(): self
    {
        $cfg = otm_config('local');
        $file = otm_env('OTM_LOCAL_DB', (string)($cfg['file'] ?? ''));
        if ($file === '') $file = OTM_PANEL_ROOT . '/database/painel.sqlite';
        return new self($file);
    }

    // -------------------------------------------------------------------------
    //  API (igual à do Turso)
    // -------------------------------------------------------------------------

    public function all(string $sql, array $args = []): array
    {
        $st = $this->pdo->prepare($sql);
        $st->execute($args);
        return $st->fetchAll();
    }

    public function one(string $sql, array $args = []): ?array
    {
        $rows = $this->all($sql, $args);
        return $rows[0] ?? null;
    }

    public function scalar(string $sql, array $args = [])
    {
        $row = $this->one($sql, $args);
        if ($row === null) return null;
        return $row[array_key_first($row)] ?? null;
    }

    public function run(string $sql, array $args = []): int
    {
        $st = $this->pdo->prepare($sql);
        $st->execute($args);
        return $st->rowCount();
    }

    public function insert(string $sql, array $args = []): int
    {
        $this->run($sql, $args);
        return (int)$this->pdo->lastInsertId();
    }

    /** Vários comandos numa transação. */
    public function batch(array $statements): array
    {
        $this->pdo->beginTransaction();
        try {
            foreach ($statements as $s) {
                $this->run((string)$s['sql'], (array)($s['args'] ?? []));
            }
            $this->pdo->commit();
        } catch (Throwable $e) {
            $this->pdo->rollBack();
            throw new DbError('Db: ' . $e->getMessage());
        }
        return [];
    }

    public function ping(): string
    {
        return (string)$this->scalar('select sqlite_version()');
    }

    public function tables(): array
    {
        return array_map(
            static fn(array $r) => (string)$r['name'],
            $this->all("select name from sqlite_master where type = 'table' order by name")
        );
    }

    /** Roda um arquivo .sql inteiro (usado pelas migrações). */
    public function execFile(string $path): void
    {
        $sql = (string)@file_get_contents($path);
        if ($sql === '') throw new DbError("Db: não consegui ler $path.");
        $this->pdo->exec($sql);
    }
}
