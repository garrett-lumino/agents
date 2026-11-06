---
name: probabilistic-estimation
description: Use when sizing capacity, estimating QPS, storage or bandwidth, choosing approximate structures (HyperLogLog, Count-Min, Bloom filters, sampling), or designing or analysing an A/B test or benchmark comparison.
---

# Probabilistic estimation

## Back-of-the-envelope
1. **Write the inputs** with units on every line: users, QPS (average and peak), payload size, retention, replication factor.
2. **Use powers of 10** and latency orders of magnitude. Give a range, not a point.

## Approximate structures
3. **Before picking a sketch,** state the acceptable error (ε) and confidence (δ), then derive the memory it needs.
4. **HyperLogLog:** state the standard error (≈1.04/√m) and the register count. Never use it for exact or billing counts.
5. **Count-Min:** it only ever overestimates. Size width and depth from ε and δ, and say whether heavy hitters are enough for the use.
6. **Bloom filter:** state the false-positive rate and expected n. Plan a rebuild for when n outgrows it.
7. **Sampling:** say whether it's uniform or stratified and give error bars. For streams, use reservoir sampling.

## Experiments and comparisons
8. **A/B tests:**
   - pre-register the metric, minimum detectable effect (MDE), α, and power, and compute the sample size;
   - no peeking (or use a sequential test);
   - check for sample-ratio mismatch.
9. **Benchmarks.** Runs are samples. Use benchstat or an equivalent test, and report a confidence interval, never the best run.
10. **Many metrics** means correcting for multiple comparisons.
11. **Report the effect size** alongside significance.

Overlaps: system-design (estimation numbers and building blocks); defer to perf-optimization-loop for benchmark procedure and eval-design for model metrics.
