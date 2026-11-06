---
name: postgres-query-review
description: Use when writing or changing SQL, adding indexes or migrations, writing pagination, or investigating a slow Postgres query. Requires an EXPLAIN (ANALYZE, BUFFERS) plan on representative data before and after.
---

# Postgres query review

1. **Real plan.**
   - Run `EXPLAIN (ANALYZE, BUFFERS)` on representative data, never on an empty dev DB.
   - Use a read-only role (`make explain Q=... OUT=docs/explain/<name>.txt`). ANALYZE executes the query, so never use it on writes against shared data.
2. **Estimates vs actuals.** Compare estimated and actual rows per node. A gap of 10× or more is a statistics problem, not an index problem: run `ANALYZE`, add extended statistics, or raise `default_statistics_target`.
3. **Access path per table.** Name it (Seq / Index / Index Only / Bitmap) and justify it from selectivity.
4. **Composite index order.** Equality columns first, then range or sort columns. One index should serve both WHERE and ORDER BY.
5. **Index killers:**
   - functions or casts on indexed columns (`lower(col)`, implicit type casts); use an expression index if needed;
   - leading-wildcard `LIKE '%x'` on a B-tree.
6. **Joins.** Name the strategy (nested loop / hash / merge) and check it fits the row counts. Watch for nested loops driven by misestimated outer rows.
7. **Smaller working set.** Prefer covering (`INCLUDE`) or partial indexes when they shrink it. Confirm index-only scans by checking heap fetches.
8. **Pagination is keyset**, e.g. `WHERE (created_at, id) < ($1, $2) ORDER BY created_at DESC, id DESC LIMIT n`. Reject OFFSET on large tables.
9. **No N+1.** Batch with `= ANY($1)` or a join.
10. **Index creation.** Migrations use `CREATE INDEX CONCURRENTLY`:
    - outside a transaction (goose: `-- +goose NO TRANSACTION`);
    - plan for cleaning up an INVALID index if the build fails;
    - the index-concurrently-guard hook enforces this.
11. **Write cost.** Every index slows writes and reduces HOT updates. Justify each one against the read it serves.
12. **MVCC.** Long transactions block vacuum and bloat tables. Keep transactions short, and watch dead tuples on hot tables.
13. **Record.** Save before and after plans (execution time, buffers) to `docs/explain/<migration>.txt`. The migration-explain-gate hook requires this.
14. **After deploy,** confirm with `pg_stat_statements` when available.

Overlaps: supabase-postgres-best-practices (rule catalogue; this skill is the review procedure); defer to data-consistency-review for isolation and locking semantics.
