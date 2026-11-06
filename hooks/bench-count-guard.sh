#!/usr/bin/env bash
# PreToolUse(Bash): benchmark output saved for comparison needs -count >= 6,
# otherwise benchstat cannot tell signal from noise.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

MIN_COUNT=6

main() {
  local cmd count
  read_input
  cmd=$(json_get '.tool_input.command')
  printf '%s' "$cmd" | grep -Eq 'go[[:space:]]+test([[:space:]]|$)' || exit 0
  printf '%s' "$cmd" | grep -Eq '[[:space:]]-(test\.)?bench([= ]|$)' || exit 0
  printf '%s' "$cmd" | grep -Eq '>|[|][[:space:]]*tee' || exit 0
  count=$(printf '%s' "$cmd" | sed -nE 's/.*-(test\.)?count[= ]+([0-9]+).*/\2/p')
  [ -n "$count" ] && [ "$count" -ge "$MIN_COUNT" ] && exit 0
  block "BLOCKED: saving benchmark output with -count=${count:-1}. Use -count=10 so benchstat can test significance."
}

main
