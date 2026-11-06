---
name: concurrency-correctness
description: Use when writing goroutines, channels, mutexes or atomics, lock-free code, distributed coordination (leases, leader election, consensus), replicated state or CRDTs, or retry and ordering protocols.
---

# Concurrency correctness

1. **Ownership.** Name the shared state and who owns it. Prefer confinement or message passing over sharing.
2. **Race detector.** Run `go test -race` on every change that touches concurrency, with a test that actually exercises the race.
3. **No goroutine leaks.** Every goroutine has a termination path tied to a `context`.
4. **Atomics** are for single-word state only. Anything compound takes a mutex.
5. **Lock-free code** needs a written linearization point and a stress test. Default: don't write it.
6. **Distributed locks** need fencing tokens. Leases need a margin for clock skew.
7. **Don't hand-roll consensus.** Use etcd/Raft, or Postgres advisory locks for single-DB coordination.
8. **Replicated state.**
   - State the merge semantics (last-writer-wins, or which CRDT).
   - Property-test that the merge is commutative, associative, and idempotent.
9. **Model it first** for protocols with more than 3 interacting actors, retries, or timeouts: a small TLA+/PlusCal spec if TLC is installed locally, otherwise a model-based property test.
10. **Executable invariants.** Write invariants as assertions in property tests (`rapid` for Go, Hypothesis, fast-check).
11. **Ordering.** Document the guarantees per channel, queue, or partition key.

Overlaps: golang-concurrency (Go idioms); defer to data-consistency-review for DB transactions and property-based-testing for writing the invariants.
