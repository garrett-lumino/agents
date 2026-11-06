#!/usr/bin/env bash
# Shared test helpers. Source from a *.test.sh file, call `finish` at the end.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOKS="$ROOT/hooks"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
unset AWS_PROFILE AWS_DEFAULT_PROFILE
PASS=0
FAIL=0

# expect <code> <description> <hook> <json> [PATH override]
expect() {
  local want="$1" desc="$2" hook="$3" json="$4" got
  if [ -n "${5:-}" ]; then
    printf '%s' "$json" | PATH="$5" "$HOOKS/$hook" >/dev/null 2>&1
  else
    printf '%s' "$json" | "$HOOKS/$hook" >/dev/null 2>&1
  fi
  got=$?
  if [ "$got" = "$want" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s (want %s, got %s)\n' "$desc" "$want" "$got"
  fi
}

bash_json() { jq -nc --arg c "$1" --arg d "${2:-$TMP}" '{tool_name:"Bash",cwd:$d,tool_input:{command:$c}}'; }
write_json() { jq -nc --arg f "$1" --arg c "$2" '{tool_name:"Write",tool_input:{file_path:$f,content:$c}}'; }
edit_json() { jq -nc --arg f "$1" --arg s "${2:-}" '{tool_name:"Edit",tool_input:{file_path:$f,new_string:$s}}'; }

# Run a Bash-tool hook: bash_case <code> <hook> <command> [cwd]
bash_case() { expect "$1" "$2: $3" "$2" "$(bash_json "$3" "${4:-}")"; }

# Run a Write-tool hook: write_case <code> <hook> <file> <content>
write_case() { expect "$1" "$2: $3 <- $(printf '%s' "$4" | head -c 50)" "$2" "$(write_json "$3" "$4")"; }

# A fresh git repo on main with one commit; prints its path.
new_repo() {
  local repo="$TMP/$1"
  git init -q -b main "$repo"
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '%s' "$repo"
}

# PATH containing only jq (plus system dirs), for "tool missing" cases.
jq_only_path() {
  mkdir -p "$TMP/jqbin"
  [ -e "$TMP/jqbin/jq" ] || ln -s "$(command -v jq)" "$TMP/jqbin/jq"
  printf '%s' "$TMP/jqbin:/usr/bin:/bin"
}

# PATH with bash and a few coreutils but no jq (macOS ships /usr/bin/jq, so
# stripping PATH to system dirs isn't enough).
no_jq_path() {
  local t
  mkdir -p "$TMP/nojq"
  for t in bash dirname basename cat; do
    [ -e "$TMP/nojq/$t" ] || ln -s "$(command -v "$t")" "$TMP/nojq/$t"
  done
  printf '%s' "$TMP/nojq"
}

# check <description> <command...>: pass if the command succeeds.
check() {
  local desc="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    printf 'FAIL: %s\n' "$desc"
  fi
}

finish() {
  printf '%s: %d passed, %d failed\n' "$(basename "$0")" "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
