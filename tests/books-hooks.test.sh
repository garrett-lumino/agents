#!/usr/bin/env bash
# Book-practice hooks: perf commits, migrations, benchmarks, money floats, lint suppressions.
set -u
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"

test_perf_commit_gate() {
  local repo
  repo=$(new_repo perf)
  bash_case 2 perf-commit-gate.sh 'git commit -m "perf: faster ledger scan"' "$repo"
  bash_case 2 perf-commit-gate.sh 'git commit -m "Optimize allocation path"' "$repo"
  bash_case 0 perf-commit-gate.sh 'git commit -m "perf: faster scan

geomean  1.2ms  0.8ms  -33.0% (p=0.000 n=10)"' "$repo"
  bash_case 0 perf-commit-gate.sh 'git commit -m "fix: allocate fee to merchant"' "$repo"
  bash_case 0 perf-commit-gate.sh 'go test ./...' "$repo"
  mkdir -p "$repo/perf"
  printf 'name old new\ngeomean 10 8 -20%% (p=0.002 n=10)\n' >"$repo/perf/scan.txt"
  git -C "$repo" add perf/scan.txt
  bash_case 0 perf-commit-gate.sh 'git commit -m "perf: faster scan"' "$repo"
}

test_migration_explain_gate() {
  local repo
  repo=$(new_repo mig-optout)
  mkdir -p "$repo/db/migrations"
  printf 'CREATE INDEX idx_a ON t (a);\n' >"$repo/db/migrations/0001_a.up.sql"
  git -C "$repo" add db/migrations
  bash_case 0 migration-explain-gate.sh 'git commit -m "repo without docs/explain is not opted in"' "$repo"
  repo=$(new_repo mig)
  mkdir -p "$repo/db/migrations" "$repo/docs/explain"
  printf 'CREATE INDEX CONCURRENTLY idx_tx_created ON tx (created_at);\n' >"$repo/db/migrations/0002_idx.up.sql"
  git -C "$repo" add db/migrations
  bash_case 2 migration-explain-gate.sh 'git commit -m "add index"' "$repo"
  printf 'Index Scan ... (actual time=0.01..0.02 rows=1)\nExecution Time: 0.05 ms\n' >"$repo/docs/explain/0002_idx.txt"
  bash_case 0 migration-explain-gate.sh 'git commit -m "add index"' "$repo"
  printf 'ALTER TABLE tx ADD COLUMN note text;\n' >"$repo/db/migrations/0003_note.up.sql"
  git -C "$repo" add db/migrations/0003_note.up.sql
  bash_case 0 migration-explain-gate.sh 'git commit -m "add note column"' "$repo"
}

test_bench_count_guard() {
  bash_case 2 bench-count-guard.sh 'go test -bench=. -count=1 ./ledger > old.txt'
  bash_case 2 bench-count-guard.sh 'go test -run=^$ -bench=Scan ./... | tee new.txt'
  bash_case 0 bench-count-guard.sh 'go test -run=^$ -bench=. -benchmem -count=10 ./ledger > old.txt'
  bash_case 0 bench-count-guard.sh 'go test -bench=. ./ledger'
}

test_index_concurrently_guard() {
  local dir="$TMP/app/migrations"
  mkdir -p "$dir"
  printf 'CREATE INDEX idx_a ON t (a);\n' >"$dir/0001_a.sql"
  expect 2 "index: CREATE INDEX without CONCURRENTLY" index-concurrently-guard.sh "$(edit_json "$dir/0001_a.sql")"
  printf 'CREATE UNIQUE INDEX CONCURRENTLY idx_b ON t (b);\n' >"$dir/0002_b.sql"
  expect 0 "index: CONCURRENTLY" index-concurrently-guard.sh "$(edit_json "$dir/0002_b.sql")"
  printf 'ALTER TABLE t ADD COLUMN id2 uuid DEFAULT gen_random_uuid();\n' >"$dir/0003_c.sql"
  expect 2 "index: volatile default" index-concurrently-guard.sh "$(edit_json "$dir/0003_c.sql")"
  printf -- '-- lint:allow-blocking tiny table\nCREATE INDEX idx_d ON t (d);\n' >"$dir/0004_d.sql"
  expect 0 "index: override comment" index-concurrently-guard.sh "$(edit_json "$dir/0004_d.sql")"
  printf 'CREATE INDEX idx_e ON t (e);\n' >"$TMP/app/notes.sql"
  expect 0 "index: not a migration" index-concurrently-guard.sh "$(edit_json "$TMP/app/notes.sql")"
}

# shellcheck disable=SC2016  # literal TS template strings fed to the hook
test_money_float_guard() {
  write_case 2 money-float-guard.sh x.go 'type Charge struct { Amount float64 }'
  write_case 2 money-float-guard.sh x.go 'var totalPrice float32'
  write_case 0 money-float-guard.sh x.go 'type Charge struct { AmountMinor int64 }'
  write_case 0 money-float-guard.sh x.go 'var feedRate float64'
  write_case 0 money-float-guard.sh x.go 'var latencyMs float64'
  write_case 0 money-float-guard.sh x.ts 'interface Order { amount: number }' # integer cents
  write_case 0 money-float-guard.sh x.ts 'readonly amountMinorUnits: number;'
  write_case 0 money-float-guard.sh x.ts 'const totalCents = priceCents * quantity'
  write_case 2 money-float-guard.sh x.ts 'const dollars = amountCents / 100'
  write_case 2 money-float-guard.sh x.ts 'const price = parseFloat(priceInput)'
  write_case 2 money-float-guard.sh x.ts 'const rounded = Math.round(price * 100) / 100'
  write_case 2 money-float-guard.sh x.ts 'const cents = 100 * amount'
  write_case 0 money-float-guard.sh x.ts 'return `$${(amountCents / 100).toFixed(2)}` // lint:allow-float display only'
  write_case 0 money-float-guard.sh x.ts 'const pct = ratio * 100'
  write_case 0 money-float-guard.sh x.tsx '}).format(amountMinorUnits / 100)}'
  write_case 2 money-float-guard.sh x.ts 'const fee = Math.round(amount * 100)'
  write_case 2 money-float-guard.sh x.py 'def f(unit_price: float) -> None: ...'
  write_case 0 money-float-guard.sh x.py 'ratio: float = 0.5'
  write_case 0 money-float-guard.sh x.go 'Amount float64 // lint:allow-float: chart scale'
  write_case 0 money-float-guard.sh x.md 'Amount float64'
}

test_nolint_justification() {
  write_case 2 nolint-justification.sh x.go 'func f() { //nolint'
  write_case 2 nolint-justification.sh x.go 'func f() { //nolint:funlen'
  write_case 0 nolint-justification.sh x.go 'func f() { //nolint:funlen // generated table dispatch'
  write_case 2 nolint-justification.sh x.py 'import os  # noqa: F401'
  write_case 0 nolint-justification.sh x.py 'import os  # noqa: F401  # re-exported for plugins'
  write_case 2 nolint-justification.sh x.ts '// eslint-disable-next-line no-console'
  write_case 0 nolint-justification.sh x.ts '// eslint-disable-next-line no-console -- CLI entrypoint'
  write_case 0 nolint-justification.sh x.md '//nolint'
}

test_perf_commit_gate
test_migration_explain_gate
test_bench_count_guard
test_index_concurrently_guard
test_money_float_guard
test_nolint_justification
finish
