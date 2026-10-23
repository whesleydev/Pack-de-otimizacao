<?php
// =============================================================================
//  Turso.php - Cliente HTTP do banco Turso (libSQL) em PHP puro.
//
//  Fala com a API v2/pipeline por cURL. Não precisa de extensão libsql nem de
//  binário do turso: só PHP com curl. As consultas usam placeholders (?) com
//  argumentos tipados — nada de concatenar valor em SQL.
//
//  Uso:
//      $db = Turso::fromConfig();
//      $rows = $db->all('select * from otm_keys where id = ?', [$id]);
//      $db->run('update otm_keys set label = ? where id = ?', ['x', $id]);
//      $id  = $db->insert('insert into otm_keys (key_hash) values (?)', [$h]);
// =============================================================================

declare(strict_types=1);

final class TursoError extends RuntimeException {}

final class Turso implements OtmDb
{
    private string $endpoint;
    private string $token;
    private int $timeout;

    public function __construct(string $url, string $token, int $timeout = 20)
    {
        // libsql://trix-x.turso.io -> https://trix-x.turso.io
        $u = preg_replace('~^libsql://~i', 'https://', trim($url));
        $u = rtrim((string)$u, '/');
        if ($u === '' || $token === '') {
            throw new TursoError('Turso: URL ou token vazio.');
        }
        $this->endpoint = $u . '/v2/pipeline';
        $this->token    = $token;
        $this->timeout  = $timeout;
    }

    /** Monta a partir de config/turso.php (ou das variáveis de ambiente). */
    public static function fromConfig(?string $configFile = null): self
    {
        $cfg = otm_config('turso', $configFile);
        $url = (string)($cfg['url'] ?? getenv('TURSO_DATABASE_URL') ?: '');
        $tok = (string)($cfg['token'] ?? getenv('TURSO_AUTH_TOKEN') ?: '');
        return new self($url, $tok, (int)($cfg['timeout'] ?? 20));
    }

    // -------------------------------------------------------------------------
    //  API pública
    // -------------------------------------------------------------------------

    /** Executa e devolve todas as linhas (array de arrays associativos). */
    public function all(string $sql, array $args = []): array
    {
        $res = $this->pipeline([$this->stmt($sql, $args)]);
        return $this->rowsToAssoc($res[0]);
    }

    /** Primeira linha ou null. */
    public function one(string $sql, array $args = []): ?array
    {
        $rows = $this->all($sql, $args);
        return $rows[0] ?? null;
    }

    /** Primeiro campo da primeira linha. */
    public function scalar(string $sql, array $args = [])
    {
        $row = $this->one($sql, $args);
        if ($row === null) return null;
        return $row[array_key_first($row)] ?? null;
    }

    /** Executa escrita/DDL. Devolve nº de linhas afetadas. */
    public function run(string $sql, array $args = []): int
    {
        $res = $this->pipeline([$this->stmt($sql, $args)]);
        return (int)($res[0]['result']['affected_row_count'] ?? 0);
    }

    /** INSERT que devolve o id gerado. */
    public function insert(string $sql, array $args = []): int
    {
        $res = $this->pipeline([$this->stmt($sql, $args)]);
        $id = $res[0]['result']['last_insert_rowid'] ?? null;
        return $id === null ? 0 : (int)$id;
    }

    /** Vários comandos numa só ida à rede (uma transação implícita). */
    public function batch(array $statements): array
    {
        $reqs = [];
        foreach ($statements as $s) {
            $reqs[] = $this->stmt((string)$s['sql'], (array)($s['args'] ?? []));
        }
        return $this->pipeline($reqs);
    }

    /** Testa a conexão. Devolve a versão do SQLite. */
    public function ping(): string
    {
        return (string)$this->scalar('select sqlite_version()');
    }

    /** Nomes das tabelas existentes. */
    public function tables(): array
    {
        return array_map(
            static fn(array $r) => (string)$r['name'],
            $this->all("select name from sqlite_master where type = 'table' order by name")
        );
    }

    // -------------------------------------------------------------------------
    //  Interno
    // -------------------------------------------------------------------------

    /** @param array<int,array> $reqs */
    private function pipeline(array $reqs): array
    {
        $reqs[] = ['type' => 'close'];
        $body = json_encode(['requests' => $reqs], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if ($body === false) throw new TursoError('Turso: falha ao montar o JSON.');

        $ch = curl_init($this->endpoint);
        if ($ch === false) throw new TursoError('Turso: cURL indisponível.');
        curl_setopt_array($ch, [
            CURLOPT_POST           => true,
            CURLOPT_POSTFIELDS     => $body,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT        => $this->timeout,
            CURLOPT_CONNECTTIMEOUT => 10,
            CURLOPT_HTTPHEADER     => [
                'Authorization: Bearer ' . $this->token,
                'Content-Type: application/json',
            ],
        ]);
        $raw  = curl_exec($ch);
        $code = (int)curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $cerr = curl_error($ch);
        curl_close($ch);

        if ($raw === false) {
            throw new TursoError('Turso: falha de rede — ' . $cerr);
        }
        $json = json_decode((string)$raw, true);
        if (!is_array($json)) {
            throw new TursoError('Turso: resposta inválida (HTTP ' . $code . ').');
        }
        if ($code >= 400 && isset($json['error'])) {
            throw new TursoError('Turso: HTTP ' . $code . ' — ' . (string)$json['error']);
        }

        $out = [];
        foreach (($json['results'] ?? []) as $r) {
            if (($r['type'] ?? '') === 'error') {
                throw new TursoError('Turso: ' . (string)($r['error']['message'] ?? 'erro desconhecido'));
            }
            $resp = $r['response'] ?? [];
            if (($resp['type'] ?? '') === 'execute') {
                $out[] = $resp;
            }
        }
        return $out;
    }

    private function stmt(string $sql, array $args): array
    {
        $typed = [];
        foreach ($args as $a) $typed[] = self::typed($a);
        return ['type' => 'execute', 'stmt' => ['sql' => $sql, 'args' => $typed]];
    }

    /** Converte um valor PHP no argumento tipado que o Turso espera. */
    private static function typed($v): array
    {
        if ($v === null)                       return ['type' => 'null'];
        if (is_bool($v))                       return ['type' => 'integer', 'value' => $v ? '1' : '0'];
        if (is_int($v))                        return ['type' => 'integer', 'value' => (string)$v];
        if (is_float($v))                      return ['type' => 'float',   'value' => (string)$v];
        if (is_string($v))                     return ['type' => 'text',    'value' => $v];
        // blob: aceita string binária marcada por um wrapper
        if (is_array($v) && isset($v['__blob'])) return ['type' => 'blob', 'base64' => base64_encode((string)$v['__blob'])];
        return ['type' => 'text', 'value' => (string)$v];
    }

    /** @param array{result:array} $resp */
    private static function rowsToAssoc(array $resp): array
    {
        $cols = array_map(static fn(array $c) => (string)$c['name'], $resp['result']['cols'] ?? []);
        $rows = [];
        foreach (($resp['result']['rows'] ?? []) as $r) {
            $row = [];
            foreach ($cols as $i => $name) {
                $cell = $r[$i] ?? ['type' => 'null'];
                $row[$name] = self::untyped($cell);
            }
            $rows[] = $row;
        }
        return $rows;
    }

    /** Converte a célula tipada do Turso no valor PHP. */
    private static function untyped(array $cell)
    {
        return match ($cell['type'] ?? 'null') {
            'null'    => null,
            'integer' => (int)($cell['value'] ?? 0),
            'float'   => (float)($cell['value'] ?? 0),
            'blob'    => base64_decode((string)($cell['base64'] ?? ''), true) ?: '',
            default   => (string)($cell['value'] ?? ''),
        };
    }
}
