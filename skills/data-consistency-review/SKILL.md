---
name: data-consistency-review
description: Use when code performs more than one write (DB rows, queues, external APIs, caches) as one logical operation, handles retries or webhooks, moves money, or publishes events. Requires naming the isolation level, the guard, and the failure modes.
---

# Data consistency review

1. **List every write** in the operation and its system (Postgres, queue, PSP API, cache).
2. **Name the isolation level** (Postgres default: Read Committed) and the anomaly that matters: lost update, write skew, phantom, or read skew.
3. **Choose the guard explicitly:**
   - `SELECT … FOR UPDATE`
   - a conditional `UPDATE … WHERE version = $n` (check rows affected)
   - a unique constraint
   - `SERIALIZABLE` with a retry loop on SQLSTATE 40001
4. **Idempotency.** Every externally triggered operation takes an idempotency key stored under a unique constraint. Decide what a replay returns: the original result, not a second effect.
5. **No exactly-once.** Assume at-least-once delivery, and make consumers idempotent.
6. **No external calls in a transaction.** Never call an external API inside an open DB transaction. Write an outbox row in the same transaction as the state change, and let a relay deliver it.
7. **Crash points.** For each write, say what happens if the process dies right after it. Each must be recoverable or compensable.
8. **Money is double-entry and immutable:** balanced ledger rows, and corrections are new entries, never updates.
9. **Ordering** comes from a DB sequence or a monotonic source, not wall-clock timestamps across machines.
10. **A timeout is "unknown outcome".** Reconcile with the other side; don't assume failure and retry blindly.
11. **Event consumers:** state the ordering guarantee per key and the dedup strategy.
12. **Caches:** state the invalidation strategy and the staleness bound. Never cache an authoritative balance without one.
13. **Concurrency test.** Race two goroutines or transactions on the same key, and assert the invariants: no negative balance, no double charge.
14. **Comment at the transaction boundary:** the level, the guard, and the failure mode.

Overlaps: designing-data-intensive-applications (theory and vocabulary); defer to concurrency-correctness for in-process races and postgres-query-review for lock and plan behaviour.
