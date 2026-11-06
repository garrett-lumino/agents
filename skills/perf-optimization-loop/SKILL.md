---
name: perf-optimization-loop
description: Use when asked to make code faster, reduce allocations, latency or memory, or when changing code because of a profile or benchmark. Requires measurement before and after. Language-agnostic; defers to golang-benchmark and golang-performance for Go tooling.
---

# Performance optimization loop

No optimization without a measured before, a measured after, and a significance test.

1. **Target.** Name the metric (p50/p99 latency, throughput, allocs/op, B/op, RSS) and a target, and why it matters.
2. **Is it this code?** Check system saturation first, using USE (utilization, saturation, errors) for CPU, memory, disk, network, and pool limits. A saturated DB pool is not fixed by a faster loop.
3. **Baseline.** Measure on the unchanged code, ≥10 samples:
   - Go: `make bench-old` (`go test -run='^$' -bench=X -benchmem -count=10`)
   - TS: tinybench or vitest bench with fixed iterations
   - Python: pyperf
4. **Profile the baseline** (CPU, alloc, block/mutex, or trace). List the top frames above ~5%.
5. **One hypothesis.** Link one profile frame to one specific change.
6. **One change.** Change exactly that, nothing else.
7. **Re-measure** the same way, on the same machine, with nothing else running (`make bench-new`).
8. **Significance.** `benchstat old.txt new.txt`:
   - accept only p < 0.05 with a delta that matters for the target;
   - `~` means no change, so revert.
9. **Go hot paths.** Check escape analysis (`make escape`) and justify every new heap escape.
10. **Memory layout last.** Look at field order, `fieldalignment`, values vs pointers in slices, and false sharing, only after allocations are handled.
11. **Readability tax.** Reject micro-optimizations that hurt readability without a significant result.
12. **Evidence.** Paste the benchstat table into the commit message, or save it as `perf/<topic>.txt`. The perf-commit-gate hook enforces this.
13. **Keep the benchmark** in the repo so regressions show up.
14. **Stop** when the target is met. Don't chase more without a new reason.

Overlaps: superpowers systematic-debugging (finding the cause); defer to golang-benchmark for benchstat/pprof mechanics, golang-performance for Go allocation patterns, postgres-query-review when the hot path is a query.
