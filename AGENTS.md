# Global Engineering Rules

These rules apply to every project. A project's own `AGENTS.md` adds its layer map and may tighten them. Where a project's stated convention differs, follow the project.

## Size & simplicity
- Write the minimum code that solves the stated problem. No speculative features, flags, config, or abstractions.
- Reuse before adding. Search for an existing helper before writing one; prefer deleting code to adding it.
- Limits: functions ≤ 40 lines, files ≤ 300 lines, cognitive complexity ≤ 15. Hooks and linters enforce these.
- If a diff passes ~150 lines, stop and propose a split before continuing.
- Prefer explicit, readable code over clever or compact code.

## Single responsibility
- One reason to change per function, type, and package.
- Go: name packages for what they provide, never `util`, `common`, `helpers`, `misc`. Elsewhere, follow the framework's convention (e.g. NestJS `common/`).
- Keep interfaces small and declare them where they are consumed, not where they are implemented.
- No positional boolean flags that switch behavior. Split the function, or use an options object.
- Names describe what a thing is, not who calls it (`getUser`, not `getUserForCheckout`). No package/type stutter. Public signatures use named types.

## Boundaries
- Dependencies point inward. Domain code never imports adapters, frameworks, or I/O.
- Each project's `AGENTS.md` defines its layer map. Follow it, and if a change needs to cross it, ask first.
- Wiring (constructors, DI, config loading) lives at the edge: `cmd/`, `main`, or route handlers.
- Tunables live in one validated config loaded at startup. No env reads in business logic.
- Ask before adding a dependency, or changing a public API, serialization format, DB schema, or route.

## Payments & sensitive data
- Money is integer minor units (cents) plus a currency, never float dollars. Convert to dollars only in one display formatter.
- Every mutating handler takes an idempotency key.
- Never log PAN, CVV, secrets, tokens, PII (email, name, phone, IP), or full request bodies that may contain them. Log IDs or a salted hash.

## Workflow
- Plan before touching more than one file: list the files and what changes in each.
- Red-green-refactor: write a failing test, make it pass, then simplify.
- "Done" means the project's checks pass (`make check` where it exists) *and* you have done a simplify pass over your diff.
- Make surgical changes: touch only what the task needs, and remove anything your change orphaned (imports, helpers, files, flags).
- Don't reformat or refactor unrelated code in the same change.
- Never weaken or delete an assertion to get green. Assert persisted state, not just responses. Test names claim only what they assert.
- Before moving untested code, add characterization tests. Don't delete code you can't prove is dead (reflection, DI, codegen, routes).

## Dangerous operations
- Destructive DB operations (DROP, TRUNCATE, DELETE): never run them, via shell or MCP. Show me the SQL and let me decide.
- Never run `terraform apply` or `terraform destroy`. Run `plan` and show me the output.
- No force pushes, no direct pushes or `git reset --hard` on main/master/develop, and no AWS writes against prod profiles.

## Measure & verify
- State n and the Big-O budget before choosing a data structure (skill: algorithm-choice).
- No optimization without before/after benchmarks and a benchstat significance check (perf-optimization-loop).
- No query, index, or migration change without `EXPLAIN (ANALYZE, BUFFERS)` on representative data (postgres-query-review).
- Every multi-write operation names its isolation level, guard, and failure modes (data-consistency-review).
- Lint suppressions name the rule and the reason; fix the finding when you can.

## ML & data
- Baseline first; report metrics only on a frozen, hashed test set never used for tuning (eval-design).
- Real card numbers never enter training data, eval data, prompts, or third-party GPUs (training-data-hygiene).
- Never launch paid GPU jobs or push to the Hub without an approved `.ml/cost-estimate.json` and a clean data attestation (gpu-cost-gate). Model repos are private.
- Never use `trust_remote_code`; pin models and VCS dependencies to exact revisions.

## Language notes
- Go: wrap errors with context (`fmt.Errorf("doing x: %w", err)`); accept `context.Context` first; no package-level mutable state.
- TypeScript/Next.js: keep `app/` routes thin (follow the project's layout: feature folders or route colocation); no `any`; server components by default; only `NEXT_PUBLIC_*` reaches the browser; preserve `use client`/`use server` boundaries.
- Python: type hints on public functions; follow the project's formatter and linter.
- Rust: `thiserror` in libraries, `anyhow` in binaries; no `unwrap`/`expect` in library code; `cargo fmt` and `cargo clippy -- -D warnings` clean.
- Terraform: one module, one responsibility; no provider blocks in child modules.
- PostgreSQL: migrations are reviewed; in production, fix forward (keep `down()` if the project requires it). Every hot-path query has an index plan.

## How to write to me
- Every reply, commit message, PR description, and doc follows the unslop rules below. Code and quoted output are exempt.

@~/agents/skills/unslop/SKILL.md
