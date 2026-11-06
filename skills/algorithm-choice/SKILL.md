---
name: algorithm-choice
description: Use when choosing or changing a data structure or algorithm, writing loops over collections that can grow, or reviewing code with nested iteration, sorting, searching, graph traversal, or string matching. Not for one-off scripts over fixed small inputs.
---

# Algorithm choice

Decide with numbers, not habit. Write the assumptions down before the code.

## Before writing code
1. State n: typical and worst case, growth over time, and whether the input is sorted, unique, or bounded.
2. State the operation mix (point reads, inserts, deletes, range queries, ordered iteration, top-k) and rough ratios.
3. Write the complexity budget per request and in total for that n.

## Feasibility at a glance
| n (per operation) | Feasible complexity |
|---|---|
| ≤ 20 | exponential / brute force is fine |
| ≤ 10⁴ | O(n²) |
| ≤ 10⁶ | O(n log n) |
| ≤ 10⁸ | O(n), tight constant |
| unbounded, per request | sublinear or amortized; index it or precompute |

## Choosing
4. Pick by operation mix:
   - point lookups → hash map
   - ordered or range queries → sorted slice + binary search, or a balanced tree
   - top-k or scheduling → heap (`container/heap`)
   - connectivity → union-find
   - prefixes → trie
   - dense small domains → bitset
5. Go: for small n or iteration-heavy work, a sorted slice usually beats a map (cache locality, no GC pointer scanning, deterministic order).
6. Look for a known problem shape and use its algorithm: shortest path, interval scheduling, matching, topological order, sliding window, two pointers, prefix sums.
7. Hunt for hidden quadratics:
   - a nested loop over the same collection
   - `slices.Contains` or a linear search inside a loop
   - string concatenation in a loop
   - `append` without a preallocated capacity
8. State space complexity and whether the working set fits in memory or cache at the expected n.
9. Prefer the standard library (`slices`, `sort`, `maps`, `container/heap`) over hand-rolled structures.

## Proving it
10. Give an informal correctness argument: a loop invariant, or an exchange argument for greedy choices.
11. Comparators need a total order, plus stability when ties matter. Property-test antisymmetry and transitivity.
12. Benchmark across sizes (`b.Run` over n = 10², 10⁴, 10⁶) to confirm the curve matches the claim.
13. Leave a one-line comment recording the decision, e.g. `// O(n log n), n≤1e5: sorted slice over map for ordered scans`.

Overlaps: golang-data-structures (Go specifics); defer to perf-optimization-loop when the goal is speed rather than correctness of choice, and to property-based-testing for invariants.
