#!/usr/bin/env bash
# PostToolUse(Edit|Write): flag table-locking DDL in migration files.
# Override for a reviewed case with a `-- lint:allow-blocking <reason>` comment.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

MIGRATION_PATH='(^|/)(migrations?|migrate)/.*\.sql$|\.up\.sql$'
VOLATILE_DEFAULT='add[[:space:]]+column.*default[[:space:]]+(gen_random_uuid|random|clock_timestamp|uuid_generate_v[14]|timeofday|txid_current)[[:space:]]*\('

index_without_concurrently() {
  grep -Ei 'create[[:space:]]+(unique[[:space:]]+)?index' "$1" | grep -Eiv 'concurrently'
}

main() {
  local file hits
  read_input
  file=$(json_get '.tool_input.file_path')
  [ -f "$file" ] || exit 0
  printf '%s' "$file" | grep -Eq "$MIGRATION_PATH" || exit 0
  grep -q 'lint:allow-blocking' "$file" && exit 0
  hits=$(index_without_concurrently "$file"; grep -Ei "$VOLATILE_DEFAULT" "$file")
  [ -n "$hits" ] || exit 0
  block "Blocking DDL in $file:
$hits
Use CREATE INDEX CONCURRENTLY (outside a transaction, e.g. goose '-- +goose NO TRANSACTION'),
and add volatile-default columns as nullable + backfill. If reviewed, add '-- lint:allow-blocking <reason>'."
}

main
