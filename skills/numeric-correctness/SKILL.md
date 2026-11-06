---
name: numeric-correctness
description: Use when code handles money, prices, FX, percentages, interest, fees, rounding, counters that can overflow, or floating-point comparisons or accumulations.
---

# Numeric correctness

## Money
1. **Integer minor units (cents), never float dollars.**
   - Go: `int64` cents plus an ISO-4217 currency code (or `shopspring/decimal` for rates).
   - Python: `int` cents or `Decimal`.
   - TS: an integer-cents `number` is correct (exact up to 2⁵³). A branded `type Cents = number & { readonly __brand: "Cents" }` stops dollar floats from being passed where cents are expected. Use `bigint` beyond 2⁵³.
   - The money-float-guard hook flags float money types in Go and Python. In TS it flags `parseFloat` and cents↔dollars `/100` and `*100` in logic.
2. **Currency exponents vary** (JPY has 0, KWD has 3). Look them up; never hard-code 2.
3. **Rounding.** State the mode (half-even or half-up) and where it happens. Round once, at a defined boundary, through one helper.
4. **Splitting and allocation.** Distribute remainders deterministically so the parts always sum to the total.
5. **No implicit FX.** Never mix currencies without an explicit conversion that carries rate, source, and timestamp.
6. **Overflow.** Check multiplications (amount × quantity × rate). Use checked math or `math/big` once ranges aren't bounded.

## Boundaries
7. **JSON:** send money as a string or as integer minor units. A JS `number` loses integers above 2⁵³.
8. **Postgres:** use `numeric(p,s)` or `bigint` minor units. Never `real`, `double precision`, or the `money` type.
9. **Parsing and serialization:** handle NaN, ±Inf, and −0 explicitly.

## Floating point (non-money)
10. **Never compare floats with `==`.** Use a relative plus absolute tolerance, and document why that tolerance.
11. **Long sums:** use Kahan/Neumaier summation. Running mean and variance: use Welford.
12. **Cancellation.** Avoid subtracting nearly equal numbers; reformulate the expression instead.

## Tests
13. **Property tests:**
    - split-then-sum equals the total;
    - parse then format round-trips exactly;
    - no overflow at the maximum realistic amount.
14. **Golden tests** for half-unit rounding cases, compared against exact integer arithmetic.

Overlaps: property-based-testing (writing the properties); defer to data-consistency-review for ledger and idempotency rules.
