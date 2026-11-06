#!/usr/bin/env bash
# Stop: if the repo has a `make check` target, it must pass before the agent stops.
# Deliberately language-agnostic: the project's Makefile decides what "check" means.
set -u
# shellcheck source=hooks/lib.sh
. "$(dirname "$0")/lib.sh"

has_check_target() {
  grep -Eq '^check[[:space:]]*:([^=]|$)' "$1/Makefile"
}

main() {
  local cwd root out
  read_input
  [ "$(json_get '.stop_hook_active')" = true ] && exit 0
  cwd=$(json_get '.cwd')
  cwd="${cwd:-$PWD}"
  root=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || root="$cwd"
  [ -f "$root/Makefile" ] && has_check_target "$root" || exit 0
  out=$(make -C "$root" check 2>&1) || block "make check failed in $root - not done yet:
$(printf '%s\n' "$out" | tail -n 40)"
  exit 0
}

main
