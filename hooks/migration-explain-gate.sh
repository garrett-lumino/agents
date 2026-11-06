#!/usr/bin/env bash
# PreToolUse(Bash): committing a migration that adds an index or a query requires
# docs/explain/<migration>.txt with real EXPLAIN (ANALYZE) output.
# Opt-in per repo: active only when the repo has a docs/explain/ directory.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

MIGRATION_PATH='(^|/)(migrations?|migrate)/.*\.sql$|\.up\.sql$'
NEEDS_PLAN='create[[:space:]]+(unique[[:space:]]+)?index|(^|[^a-z_])(select|join)([^a-z_]|$)'
PLAN_OUTPUT='actual time|Execution Time'

explain_file_for() {
  local base
  base=$(basename "$1" .sql)
  printf 'docs/explain/%s.txt' "${base%.up}"
}

check_migration() {
  local root="$1" f="$2" plan
  [ -f "$root/$f" ] || return 0
  grep -Eiq "$NEEDS_PLAN" "$root/$f" || return 0
  plan=$(explain_file_for "$f")
  grep -Eq "$PLAN_OUTPUT" "$root/$plan" 2>/dev/null && return 0
  block "BLOCKED: $f adds an index or query but $plan has no EXPLAIN (ANALYZE, BUFFERS) output.
Run it on representative data through a read-only role (make explain Q=... OUT=$plan) and commit the plan with the migration."
}

main() {
  local cmd root f
  read_input
  cmd=$(json_get '.tool_input.command')
  is_git_commit "$cmd" || exit 0
  root=$(repo_root "$(hook_cwd)")
  [ -d "$root/docs/explain" ] || exit 0
  while IFS= read -r f; do
    printf '%s' "$f" | grep -Eq "$MIGRATION_PATH" && check_migration "$root" "$f"
  done < <(pending_files "$root" "$cmd" | sort -u)
  exit 0
}

main
