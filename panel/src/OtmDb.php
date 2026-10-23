<?php
// =============================================================================
//  OtmDb.php - Contrato comum dos bancos do painel.
//
//  Turso (remoto, HTTP) e Db (SQLite local) implementam estes métodos. O resto
//  do painel depende só desta interface — trocar de banco não muda o código.
// =============================================================================

declare(strict_types=1);

interface OtmDb
{
    /** Todas as linhas (array de arrays associativos). */
    public function all(string $sql, array $args = []): array;

    /** Primeira linha ou null. */
    public function one(string $sql, array $args = []): ?array;

    /** Primeiro campo da primeira linha. */
    public function scalar(string $sql, array $args = []);

    /** Escrita/DDL: devolve nº de linhas afetadas. */
    public function run(string $sql, array $args = []): int;

    /** INSERT que devolve o id gerado. */
    public function insert(string $sql, array $args = []): int;

    /** Vários comandos numa só ida. */
    public function batch(array $statements): array;

    /** Testa a conexão e devolve a versão do SQLite. */
    public function ping(): string;

    /** Nomes das tabelas existentes. */
    public function tables(): array;
}
