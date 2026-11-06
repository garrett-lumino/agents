# Global Engineering Rules

These rules apply to every project. A project's own `AGENTS.md` adds its layer map and may tighten them.

## Size & simplicity
- Write the minimum code that solves the stated problem. No speculative features, flags, config, or abstractions.
- Reuse before adding. Search for an existing helper before writing one; prefer deleting code to adding it.
- Limits: functions ≤ 40 lines, files ≤ 300 lines, cognitive complexity ≤ 15. Hooks and linters enforce these.
- If a diff passes ~150 lines, stop and propose a split before continuing.
- Prefer explicit, readable code over clever or compact code.

## Single responsibility
- One reason to change per function, type, and package.
- Name packages for what they provide. Never `util`, `common`, `helpers`, `misc`, or `shared`.
- Keep interfaces small and declare them where they are consumed, not where they are implemented.
- No boolean-flag parameters that switch behavior. Write two functions instead.

## Boundaries
- Dependencies point inward. Domain code never imports adapters, frameworks, or I/O.
- Each project's `AGENTS.md` defines its layer map. Follow it, and if a change needs to cross it, ask first.
- Wiring (constructors, DI, config loading) lives at the edge: `cmd/`, `main`, or route handlers.

## Payments & sensitive data
- Never use floats for money. Use integer minor units or a decimal type.
- Every mutating handler takes an idempotency key.
- Never log PAN, CVV, secrets, tokens, or full request bodies that may contain them.

## Workflow
- Plan before touching more than one file: list the files and what changes in each.
- Red-green-refactor: write a failing test, make it pass, then simplify.
- "Done" means `make check` passes *and* you have done a simplify pass over your diff.
- Make surgical changes: touch only what the task needs, and remove anything your change orphaned (imports, helpers, files, flags).
- Don't reformat or refactor unrelated code in the same change.

## Dangerous operations
- Destructive DB operations (DROP, TRUNCATE, DELETE): never run them. Show me the SQL and let me decide.
- Never run `terraform apply` or `terraform destroy`. Run `plan` and show me the output.
- No force pushes, no `git reset --hard` on main, and no AWS writes against prod profiles.

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
- TypeScript/Next.js: keep `app/` routes thin and put logic in `features/<name>/`; no `any`; server components by default.
- Python: type hints on public functions; `ruff` clean.
- Terraform: one module, one responsibility; no provider blocks in child modules.
- PostgreSQL: migrations are forward-only and reviewed; every query on a hot path has an index plan.
